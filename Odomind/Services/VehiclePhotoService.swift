import Foundation
import OdomindCore

/// Resolves and caches a real photograph for each vehicle.
///
/// Three things this has to get right.
///
/// **A late answer must not land on the wrong car.** Every request carries the
/// revision of the vehicle it was made for — a fingerprint of the identity that
/// changes the moment the owner picks a different vehicle. A response whose
/// revision is no longer current is dropped rather than shown, which is the
/// same rule the search uses and for the same reason.
///
/// **Nothing heavy on the main actor.** Network, JSON, disk and image decoding
/// all happen off it; what comes back is a small record and an already
/// downsampled image.
///
/// **The owner's own photo always wins.** It is not a fallback for when the
/// provider fails; it is the best answer there is, and it is checked first.
@MainActor
@Observable
final class VehiclePhotoService {

    /// What the app has for one vehicle right now.
    enum Status: Equatable {
        case idle
        case looking
        case found(VehiclePhoto)
        /// Looked, and there is nothing Odomind may show. The quiet fallback
        /// and an upload action belong here.
        case none(String)
    }

    private(set) var statuses: [UUID: Status] = [:]

    private let provider: VehiclePhotoProvider
    private let cache: PhotoCache
    /// False in UI tests, where reaching Commons would make a screenshot run
    /// depend on somebody else's uptime.
    private let enabled: Bool
    private var inFlight: [UUID: Task<Void, Never>] = [:]
    /// The revision each vehicle's outstanding request was made for.
    private var revisions: [UUID: String] = [:]

    init(
        provider: VehiclePhotoProvider? = nil,
        cache: PhotoCache = PhotoCache(),
        enabled: Bool = true
    ) {
        self.provider = provider ?? CommonsPhotoProvider()
        self.cache = cache
        self.enabled = enabled
    }

    func status(for vehicleID: UUID) -> Status {
        statuses[vehicleID] ?? .idle
    }

    /// A fingerprint of everything about a vehicle that changes which
    /// photograph is correct. Paint is deliberately absent: Odomind never
    /// claims the picture shows the owner's colour.
    nonisolated static func revision(for vehicle: Vehicle) -> String {
        [
            vehicle.identity.modelYear.map(String.init) ?? "-",
            vehicle.identity.make,
            vehicle.identity.model,
            vehicle.identity.bodyClass ?? "-",
        ]
        .map { VehicleTextMatch.normalise($0) }
        .joined(separator: "|")
    }

    /// Looks for a photograph, unless one is already known for this exact
    /// revision.
    func resolve(for vehicle: Vehicle, force: Bool = false) {
        let id = vehicle.id
        let revision = Self.revision(for: vehicle)

        // A different vehicle, or the same one changed: whatever is in flight
        // is now for something else.
        if revisions[id] != revision {
            inFlight[id]?.cancel()
            inFlight[id] = nil
            statuses[id] = .idle
        }
        revisions[id] = revision

        guard enabled else { return }
        if !force, case .found = status(for: id) { return }
        if inFlight[id] != nil { return }

        if let cached = cache.record(vehicleID: id, revision: revision) {
            statuses[id] = cached.isDisplayable ? .found(cached) : .none("No photo available for this vehicle yet.")
            return
        }

        statuses[id] = .looking
        let request = VehiclePhotoRequest(
            modelYear: vehicle.identity.modelYear,
            make: vehicle.identity.make,
            model: vehicle.identity.model,
            bodyClass: vehicle.identity.bodyClass,
            excludedWords: Self.excludedVariantWords(for: vehicle)
        )
        let provider = self.provider
        let cache = self.cache

        inFlight[id] = Task { [weak self] in
            let found = try? await provider.photo(for: request)
            guard let self else { return }
            await self.finish(id: id, revision: revision, photo: found, cache: cache)
        }
    }

    private func finish(id: UUID, revision: String, photo: VehiclePhoto?, cache: PhotoCache) async {
        inFlight[id] = nil
        // The guard that stops one car wearing another's portrait.
        guard revisions[id] == revision else { return }

        guard let photo, photo.isDisplayable else {
            statuses[id] = .none("No photo Odomind can show was found for this vehicle.")
            return
        }
        cache.store(photo, vehicleID: id, revision: revision)
        statuses[id] = .found(photo)
    }

    /// Words that would make a candidate a picture of a different variant.
    ///
    /// A four-door Wrangler owner must not be shown a two-door one, which is
    /// the example the brief gives. Derived from the body class rather than
    /// guessed from the model name.
    nonisolated static func excludedVariantWords(for vehicle: Vehicle) -> [String] {
        let body = (vehicle.identity.bodyClass ?? "").lowercased()
        let trim = (vehicle.identity.trim ?? "").lowercased()
        let isLongWheelbase = trim.contains("unlimited") || body.contains("4 door") || body.contains("4dr")

        if isLongWheelbase {
            return ["2door", "2dr", "twodoor", "convertible"]
        }
        if body.contains("2 door") || body.contains("2dr") {
            return ["unlimited", "4door", "4dr"]
        }
        return []
    }
}

/// Where resolved photographs live between launches.
///
/// Records only — the image bytes are left to `URLCache`, which already knows
/// how to bound itself and respects the server's caching headers. Storing a
/// second copy would mean maintaining a second eviction policy badly.
final class PhotoCache: @unchecked Sendable {
    private let directory: URL
    private let queue = DispatchQueue(label: "com.idlery.odomind.photocache")

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VehiclePhotos", isDirectory: true)
        self.directory = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    private func url(vehicleID: UUID, revision: String) -> URL {
        // The revision is in the file name, so a vehicle that changes does not
        // read back the previous car's photograph.
        let digest = String(format: "%08x", UInt32(truncatingIfNeeded: revision.hashValue))
        return directory.appendingPathComponent("\(vehicleID.uuidString)-\(digest).json")
    }

    /// The same date handling the rest of the app's stored JSON uses, so a
    /// cached record written by one build reads back in the next.
    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = DateCoding.decodingStrategy
        return decoder
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = DateCoding.encodingStrategy
        return encoder
    }

    func record(vehicleID: UUID, revision: String) -> VehiclePhoto? {
        queue.sync {
            guard let data = try? Data(contentsOf: url(vehicleID: vehicleID, revision: revision)) else { return nil }
            return try? Self.decoder.decode(VehiclePhoto.self, from: data)
        }
    }

    func store(_ photo: VehiclePhoto, vehicleID: UUID, revision: String) {
        queue.async {
            guard let data = try? Self.encoder.encode(photo) else { return }
            try? data.write(to: self.url(vehicleID: vehicleID, revision: revision), options: .atomic)
        }
    }

    func removeAll() {
        queue.sync {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
