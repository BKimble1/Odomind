import Foundation
import SwiftUI
import OdomindCore

/// Locale-aware formatting for everything the owner reads.
///
/// The engine produces plain strings for its explanations; anything numeric or
/// date-like that appears in the UI comes through here so it follows the
/// device's language, region and calendar.
enum Format {

    static func distance(_ distance: Distance) -> String {
        "\(distance.amount.formatted()) \(distance.unit.abbreviation)"
    }

    static func distanceNumber(_ distance: Distance) -> String {
        distance.amount.formatted()
    }

    static func date(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    static func longDate(_ date: Date) -> String {
        date.formatted(date: .long, time: .omitted)
    }

    static func dateAndTime(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    static func time(hour: Int, minute: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// "today", "in 3 days", or a date once it is far enough away to need one.
    static func relativeDay(_ date: Date, from reference: Date, calendar: Calendar) -> String {
        let days = DateSupport.dayCount(from: reference, to: date, in: calendar)
        switch days {
        case 0: return "today"
        case 1: return "tomorrow"
        case -1: return "yesterday"
        case 2...6: return "in \(days) days"
        case -6 ... -2: return "\(-days) days ago"
        default: return Format.date(date)
        }
    }

    static func money(_ money: Money) -> String {
        money.amount.formatted(.currency(code: money.currencyCode))
    }

    static func moneyTotal(_ total: MoneyTotal) -> String {
        switch total {
        case .empty:
            return "—"
        case .single(let money):
            return Format.money(money)
        case .mixed(let monies):
            // Different currencies are never added together; each one is shown
            // on its own so the number means something.
            return monies.map(Format.money).joined(separator: "  ·  ")
        }
    }

    static func byteCount(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }

    static func dayCount(_ days: Int) -> String {
        let magnitude = abs(days)
        return "\(magnitude) day\(magnitude == 1 ? "" : "s")"
    }
}
