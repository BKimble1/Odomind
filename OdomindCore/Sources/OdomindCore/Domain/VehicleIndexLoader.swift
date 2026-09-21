import Foundation

/// Loads the bundled make/model index.
///
/// Kept off whatever thread the UI is on. The index is a few hundred
/// kilobytes of JSON covering twelve thousand makes, and decoding it is not
/// something a keystroke should wait for — so the first search runs against
/// an empty index and the provider, and suggestions sharpen a moment later
/// once it has loaded. Never blocking is the point; a search that works
/// without the index is a search that works when the index is missing.
public enum VehicleIndexLoader {
    public enum LoadError: Error, CustomStringConvertible {
        case notBundled
        case unreadable(String)

        public var description: String {
            switch self {
            case .notBundled: return "vehicle-index.json is not in the bundle"
            case .unreadable(let why): return "vehicle-index.json could not be read: \(why)"
            }
        }
    }

    public static func loadBundled() throws -> VehicleIndex {
        guard let url = Bundle.module.url(forResource: "vehicle-index", withExtension: "json") else {
            throw LoadError.notBundled
        }
        return try load(contentsOf: url)
    }

    public static func load(contentsOf url: URL) throws -> VehicleIndex {
        do {
            return try JSONDecoder().decode(VehicleIndex.self, from: Data(contentsOf: url))
        } catch {
            throw LoadError.unreadable(String(describing: error))
        }
    }
}
