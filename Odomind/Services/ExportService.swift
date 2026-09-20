import Foundation
import OdomindCore
import UIKit

/// Produces the files an owner can take with them.
///
/// Two formats, for two purposes: CSV for a spreadsheet, and a PDF for a buyer,
/// a mechanic or a warranty claim. Both exclude sample content by default, and
/// neither one includes a VIN unless the owner asks for it.
struct ExportService {

    func writeCSV(
        snapshot: GarageSnapshot,
        vehicleIDs: Set<UUID>?,
        includeDemoContent: Bool,
        calendar: Calendar,
        to directory: URL,
        fileName: String
    ) throws -> URL {
        let vehicles = snapshot.vehicles.filter { vehicleIDs?.contains($0.id) ?? true }
        let records = snapshot.serviceRecords.filter { vehicleIDs?.contains($0.vehicleID) ?? true }
        let csv = ServiceHistoryCSV.export(
            vehicles: vehicles,
            records: records,
            includeDemoContent: includeDemoContent,
            calendar: calendar
        )
        let url = directory.appendingPathComponent("\(fileName).csv", isDirectory: false)
        try Data(csv.utf8).write(to: url, options: [.atomic])
        return url
    }

    /// Renders a service history PDF.
    ///
    /// Plain and printable on purpose: this is a document someone hands over,
    /// not a marketing page. The VIN is included only when the owner opts in on
    /// the export screen.
    func writePDF(
        vehicle: Vehicle,
        records: [ServiceRecord],
        readings: [OdometerReading],
        includeVIN: Bool,
        includeDemoContent: Bool,
        generatedOn: Date,
        locale: Locale,
        calendar: Calendar,
        to directory: URL,
        fileName: String
    ) throws -> URL {
        let pageWidth: CGFloat = 612   // US Letter at 72 dpi
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 48
        let contentWidth = pageWidth - margin * 2

        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.calendar = calendar
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none

        let currencyFormatter = NumberFormatter()
        currencyFormatter.locale = locale
        currencyFormatter.numberStyle = .currency

        let visible = records
            .filter { includeDemoContent || !$0.isDemo }
            .sorted { $0.performedOn > $1.performedOn }

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
        let url = directory.appendingPathComponent("\(fileName).pdf", isDirectory: false)

        try renderer.writePDF(to: url) { context in
            var cursor: CGFloat = margin
            context.beginPage()

            func newPageIfNeeded(_ requiredHeight: CGFloat) {
                if cursor + requiredHeight > pageHeight - margin {
                    context.beginPage()
                    cursor = margin
                }
            }

            func draw(_ text: String, font: UIFont, color: UIColor = .black, spacingAfter: CGFloat = 6) {
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                let bounding = (text as NSString).boundingRect(
                    with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attributes,
                    context: nil
                )
                newPageIfNeeded(bounding.height + spacingAfter)
                (text as NSString).draw(
                    with: CGRect(x: margin, y: cursor, width: contentWidth, height: bounding.height),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attributes,
                    context: nil
                )
                cursor += bounding.height + spacingAfter
            }

            func rule() {
                newPageIfNeeded(12)
                let path = UIBezierPath()
                path.move(to: CGPoint(x: margin, y: cursor))
                path.addLine(to: CGPoint(x: pageWidth - margin, y: cursor))
                UIColor.separator.setStroke()
                path.lineWidth = 0.5
                path.stroke()
                cursor += 12
            }

            draw("Service history", font: .systemFont(ofSize: 24, weight: .semibold), spacingAfter: 2)
            draw(vehicle.displayName, font: .systemFont(ofSize: 15), color: .darkGray, spacingAfter: 2)

            var identityLines: [String] = []
            if let year = vehicle.identity.modelYear {
                identityLines.append("\(year) \(vehicle.identity.make) \(vehicle.identity.model)")
            }
            if let trim = vehicle.identity.trim, !trim.isEmpty { identityLines.append("Trim: \(trim)") }
            if includeVIN, let vin = vehicle.identity.vin { identityLines.append("VIN: \(vin)") }
            if let latest = readings.filter({ $0.vehicleID == vehicle.id }).max(by: { $0.recordedOn < $1.recordedOn }) {
                identityLines.append(
                    "Latest recorded odometer: \(latest.value.amount.formatted()) \(latest.value.unit.abbreviation) on \(dateFormatter.string(from: latest.recordedOn))"
                )
            }
            if !identityLines.isEmpty {
                draw(identityLines.joined(separator: "\n"), font: .systemFont(ofSize: 11), color: .darkGray)
            }
            draw(
                "Generated by Odomind on \(dateFormatter.string(from: generatedOn)). Records entered by the vehicle's owner.",
                font: .systemFont(ofSize: 10),
                color: .gray
            )
            rule()

            if visible.isEmpty {
                draw("No service records.", font: .systemFont(ofSize: 13), color: .darkGray)
            }

            for record in visible {
                var header = dateFormatter.string(from: record.performedOn)
                if let odometer = record.odometer {
                    header += "  ·  \(odometer.amount.formatted()) \(odometer.unit.abbreviation)"
                }
                header += "  ·  \(record.performer.displayName)"
                if record.isDemo { header += "  ·  SAMPLE DATA" }
                draw(header, font: .systemFont(ofSize: 13, weight: .semibold), spacingAfter: 3)

                let tasks = record.items.map { "• \($0.action.verb) \($0.title)" }.joined(separator: "\n")
                if !tasks.isEmpty {
                    draw(tasks, font: .systemFont(ofSize: 12), color: .darkGray, spacingAfter: 3)
                }

                if let cost = record.totalCost {
                    currencyFormatter.currencyCode = cost.currencyCode
                    let text = currencyFormatter.string(from: cost.amount as NSDecimalNumber)
                        ?? "\(cost.currencyCode) \(DecimalText.plain(cost.amount))"
                    draw("Total: \(text)", font: .systemFont(ofSize: 12), color: .darkGray, spacingAfter: 3)
                }

                if let notes = record.notes, !notes.isEmpty {
                    draw(notes, font: .italicSystemFont(ofSize: 11), color: .darkGray, spacingAfter: 3)
                }
                if !record.attachmentIDs.isEmpty {
                    let count = record.attachmentIDs.count
                    draw(
                        "\(count) attachment\(count == 1 ? "" : "s") kept in Odomind",
                        font: .systemFont(ofSize: 10),
                        color: .gray,
                        spacingAfter: 3
                    )
                }
                rule()
            }
        }

        return url
    }
}
