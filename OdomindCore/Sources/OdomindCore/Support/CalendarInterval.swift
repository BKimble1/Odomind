import Foundation

/// A calendar-relative duration such as "6 months" or "2 years".
///
/// Intervals are applied with `Calendar`, not by multiplying seconds, so that
/// month ends, leap days and daylight-saving transitions land where an owner
/// would expect: an oil change on 31 August due in 6 months falls on 28
/// February, and 29 February plus one year falls on 28 February.
public struct CalendarInterval: Codable, Hashable, Sendable, CustomStringConvertible {
    public enum Unit: String, Codable, Sendable, CaseIterable, Hashable {
        case days
        case weeks
        case months
        case years
    }

    public var count: Int
    public var unit: Unit

    public init(count: Int, unit: Unit) {
        self.count = count
        self.unit = unit
    }

    public static func days(_ count: Int) -> CalendarInterval { .init(count: count, unit: .days) }
    public static func weeks(_ count: Int) -> CalendarInterval { .init(count: count, unit: .weeks) }
    public static func months(_ count: Int) -> CalendarInterval { .init(count: count, unit: .months) }
    public static func years(_ count: Int) -> CalendarInterval { .init(count: count, unit: .years) }

    var dateComponents: DateComponents {
        var components = DateComponents()
        switch unit {
        case .days: components.day = count
        case .weeks: components.day = count * 7
        case .months: components.month = count
        case .years: components.year = count
        }
        return components
    }

    /// Adds this interval to `date` using `calendar`.
    ///
    /// Returns `nil` only when the calendar cannot represent the result, which
    /// callers treat as "cannot schedule" rather than silently substituting a
    /// different date.
    public func advancing(_ date: Date, in calendar: Calendar) -> Date? {
        calendar.date(byAdding: dateComponents, to: date)
    }

    /// A rough ordering weight used only to pick the shorter of two intervals
    /// when no anchor date is available. Never used for due-date arithmetic.
    var approximateDays: Int {
        switch unit {
        case .days: return count
        case .weeks: return count * 7
        case .months: return count * 30
        case .years: return count * 365
        }
    }

    public var description: String {
        let noun: String
        switch unit {
        case .days: noun = count == 1 ? "day" : "days"
        case .weeks: noun = count == 1 ? "week" : "weeks"
        case .months: noun = count == 1 ? "month" : "months"
        case .years: noun = count == 1 ? "year" : "years"
        }
        return "\(count) \(noun)"
    }
}
