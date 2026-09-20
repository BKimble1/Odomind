import Foundation

/// Writes RFC 4180 comma-separated values.
public enum CSVWriter {
    public static func field(_ value: String) -> String {
        let needsQuoting = value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r")
        guard needsQuoting else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    public static func row(_ values: [String]) -> String {
        values.map(field).joined(separator: ",")
    }

    public static func document(header: [String], rows: [[String]]) -> String {
        ([row(header)] + rows.map(row)).joined(separator: "\r\n") + "\r\n"
    }
}

/// Builds the service-history CSV.
///
/// One row per visit, not per task, so a receipt covering four jobs appears once
/// with its real total. The tasks are listed in their own column.
public enum ServiceHistoryCSV {
    public static let header = [
        "Vehicle",
        "Service date",
        "Odometer",
        "Unit",
        "Tasks",
        "Performed by",
        "Total cost",
        "Currency",
        "Attachments",
        "Notes"
    ]

    public static func export(
        vehicles: [Vehicle],
        records: [ServiceRecord],
        includeDemoContent: Bool = false,
        calendar: Calendar
    ) -> String {
        let vehiclesByID = Dictionary(vehicles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = calendar.timeZone

        let rows = records
            .filter { includeDemoContent || !$0.isDemo }
            .sorted { $0.performedOn > $1.performedOn }
            .map { record -> [String] in
                let vehicle = vehiclesByID[record.vehicleID]
                return [
                    vehicle?.displayName ?? "Unknown vehicle",
                    formatter.string(from: record.performedOn),
                    record.odometer.map { String($0.amount) } ?? "",
                    record.odometer?.unit.abbreviation ?? vehicle?.displayUnit.abbreviation ?? "",
                    record.items.map(\.title).joined(separator: "; "),
                    record.performer.displayName,
                    record.totalCost.map { DecimalText.plain($0.amount) } ?? "",
                    record.totalCost?.currencyCode ?? "",
                    record.attachmentIDs.isEmpty ? "" : String(record.attachmentIDs.count),
                    record.notes ?? ""
                ]
            }

        return CSVWriter.document(header: header, rows: rows)
    }
}

/// Decimal rendering that does not depend on a locale.
///
/// Used for machine-readable output only; anything shown in the app is
/// formatted with the owner's locale in the presentation layer.
public enum DecimalText {
    public static func plain(_ value: Decimal) -> String {
        var input = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 2, .plain)
        return "\(rounded)"
    }
}
