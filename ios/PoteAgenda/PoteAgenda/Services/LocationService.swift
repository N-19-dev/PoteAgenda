import CoreLocation
import Foundation
import MapKit

enum LocationServiceError: Error {
    case unauthorized
    case unableToLocate
}

enum TravelMode: String, CaseIterable, Identifiable {
    case automobile
    case transit
    case walking

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automobile: "Voiture"
        case .transit: "Transports en commun"
        case .walking: "À pied"
        }
    }

    var systemImage: String {
        switch self {
        case .automobile: "car.fill"
        case .transit: "tram.fill"
        case .walking: "figure.walk"
        }
    }

    var transportType: MKDirectionsTransportType {
        switch self {
        case .automobile: .automobile
        case .transit: .transit
        case .walking: .walking
        }
    }
}

@MainActor
final class LocationService: NSObject, ObservableObject {
    static let shared = LocationService()

    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    /// Délai maximal d'attente d'une position avant d'abandonner. CLLocationManager
    /// est censé toujours rappeler `didUpdateLocations` ou `didFailWithError`, mais
    /// rien ne le garantit dans tous les cas (ex. daemon de localisation bloqué) ;
    /// sans filet, une continuation jamais reprise bloquerait l'appelant pour toujours.
    private static let requestTimeout: TimeInterval = 15

    private let manager = CLLocationManager()
    /// Toutes les demandes en cours partagent le même appel `requestLocation()` :
    /// une seule requête CoreLocation à la fois, et chaque appelant peut être
    /// annulé indépendamment sans affecter les autres.
    private var pendingContinuations: [UUID: CheckedContinuation<CLLocationCoordinate2D, Error>] = [:]
    private var timeoutTask: Task<Void, Never>?

    private override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    func requestAuthorizationIfNeeded() {
        guard authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    func currentCoordinate() async throws -> CLLocationCoordinate2D {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            throw LocationServiceError.unauthorized
        }

        let requestId = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                register(continuation, id: requestId)
            }
        } onCancel: {
            Task { @MainActor in
                self.cancelRequest(id: requestId)
            }
        }
    }

    private func register(_ continuation: CheckedContinuation<CLLocationCoordinate2D, Error>, id: UUID) {
        let isFirstRequest = pendingContinuations.isEmpty
        pendingContinuations[id] = continuation
        guard isFirstRequest else { return }
        scheduleTimeout()
        manager.requestLocation()
    }

    private func cancelRequest(id: UUID) {
        guard let continuation = pendingContinuations.removeValue(forKey: id) else { return }
        continuation.resume(throwing: CancellationError())
        if pendingContinuations.isEmpty {
            timeoutTask?.cancel()
            timeoutTask = nil
        }
    }

    private func scheduleTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.requestTimeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.failPending(with: LocationServiceError.unableToLocate)
        }
    }

    private func resolvePending(with coordinate: CLLocationCoordinate2D) {
        timeoutTask?.cancel()
        timeoutTask = nil
        let continuations = pendingContinuations
        pendingContinuations.removeAll()
        for continuation in continuations.values {
            continuation.resume(returning: coordinate)
        }
    }

    private func failPending(with error: Error) {
        timeoutTask?.cancel()
        timeoutTask = nil
        let continuations = pendingContinuations
        pendingContinuations.removeAll()
        for continuation in continuations.values {
            continuation.resume(throwing: error)
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else {
            // CoreLocation ne devrait pas rappeler avec une liste vide, mais si
            // ça arrive, on échoue tout de suite plutôt que de laisser les
            // appelants attendre le timeout de 15s pour rien.
            Task { @MainActor in
                self.failPending(with: LocationServiceError.unableToLocate)
            }
            return
        }
        Task { @MainActor in
            self.resolvePending(with: coordinate)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.failPending(with: LocationServiceError.unableToLocate)
        }
    }
}

enum TravelTimeEstimator {
    static func travelTime(from origin: CLLocationCoordinate2D, toAddress address: String, mode: TravelMode) async throws -> TimeInterval {
        let placemarks = try await CLGeocoder().geocodeAddressString(address)
        guard let destination = placemarks.first?.location?.coordinate else {
            throw LocationServiceError.unableToLocate
        }

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = mode.transportType

        let response = try await MKDirections(request: request).calculateETA()
        return response.expectedTravelTime
    }
}
