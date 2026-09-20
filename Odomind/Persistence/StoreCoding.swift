import Foundation
import OdomindCore

/// JSON coding for the value types stored inside persistence models.
///
/// The same `Codable` conformances back the backup format, so anything that
/// round-trips through a backup round-trips through the store. Failures are
/// surfaced rather than swallowed: a record Odomind cannot read is reported to
/// the owner instead of quietly appearing empty.
enum StoreCoding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    /// Encodes an optional, using empty `Data` for `nil` so the column is never
    /// null and decoding stays symmetric.
    static func encodeOptional<T: Encodable>(_ value: T?) throws -> Data {
        guard let value else { return Data() }
        return try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }

    static func decodeOptional<T: Decodable>(_ type: T.Type, from data: Data) throws -> T? {
        guard !data.isEmpty else { return nil }
        return try decoder.decode(type, from: data)
    }

    /// Decodes with a fallback, recording the failure for the diagnostics
    /// screen. Used where a single unreadable field must not take down a whole
    /// list, for example when rendering history.
    static func decodeOrFallback<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        fallback: T,
        context: String,
        problems: inout [StoreProblem]
    ) -> T {
        guard !data.isEmpty else { return fallback }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            problems.append(StoreProblem(context: context, message: String(describing: error)))
            return fallback
        }
    }

    static func decodeOptionalOrFallback<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        context: String,
        problems: inout [StoreProblem]
    ) -> T? {
        guard !data.isEmpty else { return nil }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            problems.append(StoreProblem(context: context, message: String(describing: error)))
            return nil
        }
    }
}

/// A record Odomind could not fully read.
struct StoreProblem: Hashable, Sendable, Identifiable {
    var id: String { context + message }
    var context: String
    var message: String
}
