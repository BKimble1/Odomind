import Foundation

/// ISO 8601 date coding shared by the catalog, the backup format and the store.
///
/// Encoding includes fractional seconds so a timestamp survives a backup and
/// restore to the millisecond. Decoding accepts both forms, so a catalog file a
/// person typed by hand — `2026-09-20T00:00:00Z` — reads without ceremony.
///
/// Millisecond precision is the documented guarantee. Odomind stores service
/// dates, readings and audit timestamps, none of which mean anything below that.
public enum DateCoding {
    private static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let withoutFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    public static func string(from date: Date) -> String {
        withFractionalSeconds.string(from: date)
    }

    public static func date(from string: String) -> Date? {
        withFractionalSeconds.date(from: string) ?? withoutFractionalSeconds.date(from: string)
    }

    /// Rounds to the precision the transfer formats preserve.
    ///
    /// Applied when Odomind creates a timestamp, so what is held in memory and
    /// what comes back from a backup are the same value rather than differing
    /// by a few microseconds.
    public static func normalized(_ date: Date) -> Date {
        let milliseconds = (date.timeIntervalSinceReferenceDate * 1000).rounded()
        return Date(timeIntervalSinceReferenceDate: milliseconds / 1000)
    }

    public static var encodingStrategy: JSONEncoder.DateEncodingStrategy {
        .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(string(from: date))
        }
    }

    public static var decodingStrategy: JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let value = date(from: text) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "'\(text)' is not an ISO 8601 date."
                )
            }
            return value
        }
    }
}
