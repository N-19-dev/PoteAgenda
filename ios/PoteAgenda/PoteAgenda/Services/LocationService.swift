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

    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocationCoordinate2D, Error>?

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
        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
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
        guard let coordinate = locations.last?.coordinate else { return }
        Task { @MainActor in
            self.locationContinuation?.resume(returning: coordinate)
            self.locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.locationContinuation?.resume(throwing: LocationServiceError.unableToLocate)
            self.locationContinuation = nil
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
