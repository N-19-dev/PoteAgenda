import CoreLocation
import MapKit
import SwiftUI

struct LocationSuggestion: Identifiable, Hashable, Sendable {
    let id = UUID()
    let title: String
    let subtitle: String
}

private struct ResolvedPlace: Identifiable, Sendable {
    let id: UUID
    let title: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D
}

@MainActor
final class LocationSearchCompleterModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [LocationSuggestion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func update(query: String) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            results = []
            return
        }
        completer.queryFragment = query
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let newResults = completer.results.map { LocationSuggestion(title: $0.title, subtitle: $0.subtitle) }
        Task { @MainActor in
            self.results = newResults
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.results = []
        }
    }
}

struct LocationSearchField: View {
    @Binding var location: String
    @Binding var coordinate: CLLocationCoordinate2D?
    @State private var showingSearch = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    showingSearch = true
                } label: {
                    HStack {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(.secondary)
                        Text(location.isEmpty ? "Lieu" : location)
                            .foregroundStyle(location.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)

                if !location.isEmpty {
                    Button {
                        location = ""
                        coordinate = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }

            if let coordinate {
                Map(
                    initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 600, longitudinalMeters: 600)),
                    interactionModes: []
                ) {
                    Marker(location, coordinate: coordinate)
                }
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .sheet(isPresented: $showingSearch) {
            LocationSearchSheet(location: $location, coordinate: $coordinate)
        }
    }
}

private struct LocationSearchSheet: View {
    @Binding var location: String
    @Binding var coordinate: CLLocationCoordinate2D?
    @Environment(\.dismiss) private var dismiss
    @StateObject private var completerModel = LocationSearchCompleterModel()
    @State private var query = ""
    @State private var markers: [ResolvedPlace] = []
    @State private var isResolvingMarkers = false
    @State private var selectedMarkerID: UUID?
    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Map(position: $cameraPosition, selection: $selectedMarkerID) {
                    ForEach(markers) { marker in
                        Marker(marker.title, coordinate: marker.coordinate)
                            .tag(marker.id)
                    }
                }
                .frame(height: 220)
                .overlay(alignment: .center) {
                    if isResolvingMarkers && markers.isEmpty {
                        ProgressView()
                    }
                }

                List {
                    ForEach(completerModel.results) { result in
                        Button {
                            select(result)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.title)
                                    .foregroundStyle(.primary)
                                if !result.subtitle.isEmpty {
                                    Text(result.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && completerModel.results.isEmpty {
                        Text("Aucun lieu trouvé")
                            .foregroundStyle(.secondary)
                    }
                }
                .listStyle(.plain)
            }
            .searchable(text: $query, prompt: "Rechercher un lieu")
            .onChange(of: query) { _, newValue in
                completerModel.update(query: newValue)
            }
            .task(id: completerModel.results) {
                isResolvingMarkers = true
                let resolved = await resolveMarkers(for: completerModel.results)
                markers = resolved
                if let region = regionFitting(resolved) {
                    cameraPosition = .region(region)
                }
                isResolvingMarkers = false
            }
            .onChange(of: selectedMarkerID) { _, newValue in
                guard let newValue, let marker = markers.first(where: { $0.id == newValue }) else { return }
                finalize(title: marker.title, subtitle: marker.subtitle, coordinate: marker.coordinate)
            }
            .navigationTitle("Lieu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
            .onAppear { query = location }
        }
    }

    private func select(_ result: LocationSuggestion) {
        if let marker = markers.first(where: { $0.id == result.id }) {
            finalize(title: marker.title, subtitle: marker.subtitle, coordinate: marker.coordinate)
        } else {
            Task {
                if let place = await resolvePlace(result) {
                    finalize(title: place.title, subtitle: place.subtitle, coordinate: place.coordinate)
                } else {
                    location = result.subtitle.isEmpty ? result.title : "\(result.title), \(result.subtitle)"
                    dismiss()
                }
            }
        }
    }

    private func finalize(title: String, subtitle: String, coordinate: CLLocationCoordinate2D) {
        location = subtitle.isEmpty ? title : "\(title), \(subtitle)"
        self.coordinate = coordinate
        dismiss()
    }

    private func resolveMarkers(for suggestions: [LocationSuggestion]) async -> [ResolvedPlace] {
        await withTaskGroup(of: ResolvedPlace?.self) { group in
            for suggestion in suggestions.prefix(6) {
                group.addTask {
                    await resolvePlace(suggestion)
                }
            }
            var places: [ResolvedPlace] = []
            for await place in group {
                if let place {
                    places.append(place)
                }
            }
            return places
        }
    }

    private func regionFitting(_ places: [ResolvedPlace]) -> MKCoordinateRegion? {
        guard !places.isEmpty else { return nil }
        let lats = places.map(\.coordinate.latitude)
        let lons = places.map(\.coordinate.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return nil }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.6, 0.02),
            longitudeDelta: max((maxLon - minLon) * 1.6, 0.02)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

private func resolvePlace(_ suggestion: LocationSuggestion) async -> ResolvedPlace? {
    let request = MKLocalSearch.Request()
    request.naturalLanguageQuery = suggestion.subtitle.isEmpty ? suggestion.title : "\(suggestion.title), \(suggestion.subtitle)"
    guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
    return ResolvedPlace(id: suggestion.id, title: suggestion.title, subtitle: suggestion.subtitle, coordinate: item.placemark.coordinate)
}

private extension String {
    var appleMapsURL: URL? {
        guard let encoded = addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "https://maps.apple.com/?q=\(encoded)")
    }
}

/// Ouvre Plans sur cette adresse : le backend ne stocke qu'un texte (pas de
/// coordonnées), donc on laisse Plans résoudre l'adresse lui-même plutôt que
/// de re-géocoder côté app.
struct LocationLink: View {
    let location: String

    var body: some View {
        if let url = location.appleMapsURL {
            Link(destination: url) {
                Label(location, systemImage: "mappin.and.ellipse")
            }
            .foregroundStyle(Color.accentColor)
        } else {
            Label(location, systemImage: "mappin.and.ellipse")
        }
    }
}

struct EmptyStateView: View {
    let title: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage)
    }
}

struct EventTimeText: View {
    let start: String
    let end: String

    var body: some View {
        Text("\(time(start)) - \(time(end))")
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.secondary)
    }

    private func time(_ value: String) -> String {
        guard let date = DateHelpers.parse(value) else { return value }
        return DateHelpers.displayTimeString(date)
    }
}

extension View {
    @ViewBuilder
    func poteUsernameInputTraits() -> some View {
        #if os(iOS)
        self.textContentType(.username)
            .textInputAutocapitalization(.never)
        #else
        self
        #endif
    }

    @ViewBuilder
    func poteEmailInputTraits() -> some View {
        #if os(iOS)
        self.keyboardType(.emailAddress)
            .textContentType(.emailAddress)
            .textInputAutocapitalization(.never)
        #else
        self
        #endif
    }

    @ViewBuilder
    func potePasswordInputTraits(isNewPassword: Bool) -> some View {
        #if os(iOS)
        self.textContentType(isNewPassword ? .newPassword : .password)
        #else
        self
        #endif
    }

    @ViewBuilder
    func poteSearchInputTraits() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never)
        #else
        self
        #endif
    }
}

extension ToolbarItemPlacement {
    static var poteTopBarTrailing: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .automatic
        #endif
    }
}
