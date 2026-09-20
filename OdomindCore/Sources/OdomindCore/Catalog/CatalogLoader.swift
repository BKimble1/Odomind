import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum CatalogLoadError: Error, Hashable, Sendable {
    case resourceMissing(String)
    case unsupportedSchema(found: Int, supported: Int)
    case decodingFailed(String)
    case invalid([CatalogValidationIssue])

    public var message: String {
        switch self {
        case .resourceMissing(let name):
            return "The catalog file \(name) is missing from the app bundle."
        case .unsupportedSchema(let found, let supported):
            return "This catalog uses schema version \(found); this version of Odomind reads version \(supported)."
        case .decodingFailed(let detail):
            return "The catalog could not be read: \(detail)"
        case .invalid(let issues):
            let errors = issues.filter { $0.severity == .error }
            return "The catalog failed validation with \(errors.count) error\(errors.count == 1 ? "" : "s")."
        }
    }
}

/// Reads and writes the catalog file format.
public enum CatalogLoader {
    public static let bundledResourceName = "odomind-catalog"
    public static let bundledResourceExtension = "json"

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = DateCoding.decodingStrategy
        return decoder
    }

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = DateCoding.encodingStrategy
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    /// Decodes and validates a catalog.
    ///
    /// Validation is not optional: a catalog that claims a manufacturer source
    /// without a citation, or carries two rules for the same task, is rejected
    /// rather than partially trusted.
    public static func load(data: Data) throws -> MaintenanceCatalog {
        let catalog: MaintenanceCatalog
        do {
            catalog = try makeDecoder().decode(MaintenanceCatalog.self, from: data)
        } catch {
            throw CatalogLoadError.decodingFailed(describe(error))
        }

        guard catalog.schemaVersion == MaintenanceCatalog.currentSchemaVersion else {
            throw CatalogLoadError.unsupportedSchema(
                found: catalog.schemaVersion,
                supported: MaintenanceCatalog.currentSchemaVersion
            )
        }

        let issues = CatalogValidator.validate(catalog)
        if issues.contains(where: { $0.severity == .error }) {
            throw CatalogLoadError.invalid(issues)
        }
        return catalog
    }

    /// Loads the catalog shipped inside this package's resource bundle.
    public static func loadBundled() throws -> MaintenanceCatalog {
        guard let url = Bundle.module.url(
            forResource: bundledResourceName,
            withExtension: bundledResourceExtension
        ) else {
            throw CatalogLoadError.resourceMissing("\(bundledResourceName).\(bundledResourceExtension)")
        }
        let data = try Data(contentsOf: url)
        return try load(data: data)
    }

    public static func encode(_ catalog: MaintenanceCatalog) throws -> Data {
        try makeEncoder().encode(catalog)
    }

    public static func describe(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else {
            return String(describing: error)
        }
        switch decodingError {
        case .keyNotFound(let key, let context):
            return "missing key '\(key.stringValue)' at \(path(context))"
        case .typeMismatch(let type, let context):
            return "expected \(type) at \(path(context))"
        case .valueNotFound(let type, let context):
            return "missing value of type \(type) at \(path(context))"
        case .dataCorrupted(let context):
            return "corrupted data at \(path(context)): \(context.debugDescription)"
        @unknown default:
            return String(describing: decodingError)
        }
    }

    private static func path(_ context: DecodingError.Context) -> String {
        let components = context.codingPath.map { $0.stringValue }
        return components.isEmpty ? "the root object" : components.joined(separator: ".")
    }
}
