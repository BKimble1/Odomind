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

/// Finds parts shops around a point, using MapKit's own search.
///
/// It asks for a point and it never asks for permission. Build 3 had this
/// class running its own `CLLocationManager` beside `ShoppingLocationService`,
/// so two objects could each put a location prompt on screen and the answer
/// one of them got was thrown away when the screen closed. The owner's
/// shopping area is now the single answer to "where", chosen once, and this
/// searches around whatever coordinate that produces.
///
/// Nothing about the vehicle is sent anywhere by this. MapKit is asked for
/// "auto parts store" near a point, and that is the whole request.
@MainActor
@Observable
final class NearbyStoreFinder {
    enum State: Equatable {
        case idle
        case searching
        case results([NearbyStore])
        case failed(String)
    }

    private(set) var state: State = .idle

    private var searchTask: Task<Void, Never>?

    /// Searches around a point the app already has.
    func search(term: String, near coordinate: CLLocationCoordinate2D) {
        searchTask?.cancel()
        searchTask = Task {
            state = .searching
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
            state = .failed("Odomind could not search for shops. Check your connection.")
        }
    }
}
