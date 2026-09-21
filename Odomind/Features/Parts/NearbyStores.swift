import Foundation
import MapKit
import CoreLocation
import Observation

/// A business a map search actually returned.
struct NearbyStore: Identifiable, Hashable {
    var id: String
    var name: String
    var address: String?
    /// Metres, when the search had a location to measure from.
    var distance: CLLocationDistance?
    var phone: String?
    var website: URL?
    var coordinate: CLLocationCoordinate2D

    static func == (lhs: NearbyStore, rhs: NearbyStore) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var directionsURL: URL? {
        let query = "\(coordinate.latitude),\(coordinate.longitude)"
        return URL(string: "http://maps.apple.com/?daddr=\(query)")
    }
}

/// Finds parts shops near the owner, using MapKit's own search.
///
/// Two things this deliberately does not do: ask for location at launch, and
/// require location at all. Permission is requested when the owner taps
/// "Near me", and a postal code or town works just as well — the accuracy
/// difference does not matter for "which shops are around here".
///
/// Nothing about the vehicle is sent anywhere by this. MapKit is asked for
/// "auto parts store" near a point, and that is the whole request.
@MainActor
@Observable
final class NearbyStoreFinder: NSObject {
    enum State: Equatable {
        case idle
        case searching
        case results([NearbyStore])
        case failed(String)
        case locationDenied
    }

    private(set) var state: State = .idle

    private let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?
    private var searchTask: Task<Void, Never>?

    override init() {
        super.init()
        locationManager.delegate = self
        // Reduced accuracy is plenty for "shops around here", and it is the
        // least the owner has to give up to get an answer.
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Searches near the device, asking for permission at this moment and not
    /// before.
    func searchNearMe(term: String) {
        searchTask?.cancel()
        searchTask = Task {
            state = .searching
            let status = locationManager.authorizationStatus
            if status == .denied || status == .restricted {
                state = .locationDenied
                return
            }
            if status == .notDetermined {
                locationManager.requestWhenInUseAuthorization()
            }
            guard let location = await currentLocation() else {
                state = .locationDenied
                return
            }
            await run(term: term, near: location.coordinate)
        }
    }

    /// The path that needs no permission at all.
    func search(term: String, place: String) {
        searchTask?.cancel()
        searchTask = Task {
            state = .searching
            let geocoder = CLGeocoder()
            let placemarks = try? await geocoder.geocodeAddressString(place)
            guard let coordinate = placemarks?.first?.location?.coordinate else {
                state = .failed("Odomind could not find “\(place)”. Try a postal code or a town name.")
                return
            }
            await run(term: term, near: coordinate)
        }
    }

    private func run(term: String, near coordinate: CLLocationCoordinate2D) async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = term
        request.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 40_000,
            longitudinalMeters: 40_000
        )

        do {
            let response = try await MKLocalSearch(request: request).start()
            if Task.isCancelled { return }
            let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let stores = response.mapItems.compactMap { item -> NearbyStore? in
                guard let name = item.name else { return nil }
                let itemLocation = item.placemark.location
                return NearbyStore(
                    id: "\(name)-\(item.placemark.coordinate.latitude)-\(item.placemark.coordinate.longitude)",
                    name: name,
                    address: item.placemark.title,
                    distance: itemLocation.map { origin.distance(from: $0) },
                    phone: item.phoneNumber,
                    website: item.url,
                    coordinate: item.placemark.coordinate
                )
            }
            .sorted { ($0.distance ?? .greatestFiniteMagnitude) < ($1.distance ?? .greatestFiniteMagnitude) }

            state = stores.isEmpty
                ? .failed("No parts shops came back for that area.")
                : .results(stores)
        } catch {
            if Task.isCancelled { return }
            state = .failed("Odomind could not search for nearby shops. Check your connection and try again.")
        }
    }

    private func currentLocation() async -> CLLocation? {
        if let existing = locationManager.location { return existing }
        return await withCheckedContinuation { continuation in
            locationContinuation = continuation
            locationManager.requestLocation()
        }
    }
}

extension NearbyStoreFinder: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in
            locationContinuation?.resume(returning: location)
            locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            locationContinuation?.resume(returning: nil)
            locationContinuation = nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = manager.authorizationStatus
            if status == .denied || status == .restricted {
                locationContinuation?.resume(returning: nil)
                locationContinuation = nil
                if case .searching = state { state = .locationDenied }
            }
        }
    }
}
