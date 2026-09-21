import CoreLocation
import Foundation
import Observation
import OdomindCore

/// Where the owner is shopping, shared by every screen that needs it.
///
/// Build 2 kept location inside the parts screen: a finder and a typed place
/// created per view, asked for permission the first time somebody opened
/// shopping, and forgotten on dismissal. So the answer to "where are you"
/// was re-established every visit and could not be shown anywhere else.
///
/// This is one service, chosen once and persisted. A manually selected town
/// stays selected until the owner changes it — it is a decision, not a cache.
@MainActor
@Observable
final class ShoppingLocationService {

    /// What the owner picked.
    enum Area: Codable, Equatable, Sendable {
        /// Follow the device.
        case currentLocation
        /// A town or postal code they chose. Coordinates are kept so a launch
        /// with no network still knows where to look.
        case place(name: String, detail: String?, latitude: Double, longitude: Double)

        var isCurrentLocation: Bool {
            if case .currentLocation = self { return true }
            return false
        }
    }

    /// What the service can actually act on right now.
    enum Resolution: Equatable {
        case none
        case resolving
        case ready(latitude: Double, longitude: Double, label: String)
        /// Permission refused. Distinct from a failure, because the remedy is
        /// Settings rather than trying again.
        case denied
        case failed(String)

        var coordinate: CLLocationCoordinate2D? {
            guard case .ready(let latitude, let longitude, _) = self else { return nil }
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }

        var label: String? {
            guard case .ready(_, _, let label) = self else { return nil }
            return label
        }
    }

    private(set) var area: Area = .currentLocation
    private(set) var resolution: Resolution = .none

    private let provider: DeviceLocationProvider
    private let geocoder = CLGeocoder()
    private let defaults: UserDefaults
    private var resolveTask: Task<Void, Never>?

    private static let storageKey = "com.idlery.odomind.shoppingArea"

    init(provider: DeviceLocationProvider = DeviceLocationProvider(), defaults: UserDefaults = .standard) {
        self.provider = provider
        self.defaults = defaults
        restore()
    }

    var authorizationStatus: CLAuthorizationStatus { provider.authorizationStatus }
    var isAuthorized: Bool { provider.isAuthorized }

    /// True when there is somewhere to search without asking anything first,
    /// which is what lets Parts load results on open rather than on tap.
    var hasUsableArea: Bool {
        if case .place = area { return true }
        return provider.isAuthorized
    }

    // MARK: - Choosing

    func useCurrentLocation() {
        area = .currentLocation
        persist()
        resolve(force: true)
    }

    func choose(_ place: PlaceSuggestion) {
        area = .place(
            name: place.name,
            detail: place.detail,
            latitude: place.latitude,
            longitude: place.longitude
        )
        persist()
        // A chosen place needs no lookup; it already carries its coordinates.
        resolution = .ready(latitude: place.latitude, longitude: place.longitude, label: place.name)
    }

    /// Resolves the chosen area into something searchable.
    func resolve(force: Bool = false) {
        if !force, case .ready = resolution { return }

        resolveTask?.cancel()
        switch area {
        case .place(let name, _, let latitude, let longitude):
            resolution = .ready(latitude: latitude, longitude: longitude, label: name)

        case .currentLocation:
            resolution = .resolving
            resolveTask = Task { [weak self] in
                guard let self else { return }
                let outcome = await self.provider.fix()
                guard !Task.isCancelled else { return }
                switch outcome {
                case .success(let location):
                    let label = await self.describe(location) ?? "Current location"
                    guard !Task.isCancelled else { return }
                    self.resolution = .ready(
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude,
                        label: label
                    )
                case .failure(.denied), .failure(.restricted):
                    self.resolution = .denied
                case .failure(.timedOut):
                    self.resolution = .failed("Odomind could not get a location in time. Try again, or type an area.")
                case .failure(.unavailable):
                    self.resolution = .failed("Odomind could not get a location. Try again, or type an area.")
                }
            }
        }
    }

    /// Asks for permission at a moment the owner chose.
    @discardableResult
    func requestPermission() async -> CLAuthorizationStatus {
        let status = await provider.requestAuthorization()
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            resolve(force: true)
        } else if status == .denied || status == .restricted {
            resolution = .denied
        }
        return status
    }

    // MARK: - Searching for an area

    /// Towns and postal codes matching what was typed.
    func places(matching text: String) async -> [PlaceSuggestion] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        guard let placemarks = try? await geocoder.geocodeAddressString(trimmed) else { return [] }
        return placemarks.compactMap { PlaceSuggestion(placemark: $0) }
    }

    private func describe(_ location: CLLocation) async -> String? {
        guard let placemarks = try? await geocoder.reverseGeocodeLocation(location) else { return nil }
        guard let first = placemarks.first else { return nil }
        return first.locality ?? first.subAdministrativeArea ?? first.administrativeArea
    }

    // MARK: - Persistence

    private func persist() {
        guard let data = try? JSONEncoder().encode(area) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private func restore() {
        guard let data = defaults.data(forKey: Self.storageKey),
              let stored = try? JSONDecoder().decode(Area.self, from: data) else { return }
        area = stored
        if case .place(let name, _, let latitude, let longitude) = stored {
            resolution = .ready(latitude: latitude, longitude: longitude, label: name)
        }
    }
}

/// One place the owner could pick.
struct PlaceSuggestion: Identifiable, Hashable, Sendable {
    var id: String { "\(name)|\(detail ?? "")|\(latitude),\(longitude)" }
    var name: String
    /// Region and country, shown when a name alone would be ambiguous —
    /// there is more than one Springfield.
    var detail: String?
    var latitude: Double
    var longitude: Double

    init?(placemark: CLPlacemark) {
        guard let location = placemark.location else { return nil }
        guard let name = placemark.locality
            ?? placemark.subAdministrativeArea
            ?? placemark.name else { return nil }
        self.name = name
        self.detail = [placemark.administrativeArea, placemark.country]
            .compactMap { $0 }
            .joined(separator: ", ")
            .nilWhenEmpty
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
    }

    init(name: String, detail: String?, latitude: Double, longitude: Double) {
        self.name = name
        self.detail = detail
        self.latitude = latitude
        self.longitude = longitude
    }
}

private extension String {
    var nilWhenEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
