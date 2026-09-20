import Foundation

/// Supplies "now" to services that need it.
///
/// Every service that reads the current time takes one of these so tests can
/// pin the clock. The pure scheduling functions in `ScheduleEngine` go further
/// and take the instant as a parameter, which keeps them referentially
/// transparent.
public protocol OdomindClock: Sendable {
    var now: Date { get }
}

public struct SystemClock: OdomindClock {
    public init() {}
    public var now: Date { Date() }
}

/// A clock pinned to a fixed instant. Test-only convenience, but it lives in
/// the library so app-side tests can use it too.
public final class FixedClock: OdomindClock, @unchecked Sendable {
    private let lock = NSLock()
    private var instant: Date

    public init(_ instant: Date) {
        self.instant = instant
    }

    public var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return instant
    }

    public func set(_ newInstant: Date) {
        lock.lock()
        instant = newInstant
        lock.unlock()
    }

    public func advance(by seconds: TimeInterval) {
        lock.lock()
        instant = instant.addingTimeInterval(seconds)
        lock.unlock()
    }
}

public enum DateSupport {
    /// A `Calendar` suitable for scheduling in `timeZone`.
    ///
    /// Odomind schedules on calendar days, so the calendar's time zone decides
    /// which day a deadline lands on. Callers pass the owner's current zone;
    /// tests pass a fixed one.
    public static func calendar(timeZone: TimeZone, identifier: Calendar.Identifier = .gregorian) -> Calendar {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = timeZone
        return calendar
    }

    /// Whole calendar days from `start` to `end` in `calendar`.
    ///
    /// Both instants are normalised to the start of their day first, so a
    /// deadline at 09:00 tomorrow is "1 day away" no matter what time it is now.
    public static func dayCount(from start: Date, to end: Date, in calendar: Calendar) -> Int {
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        return calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0
    }

    /// `date` moved to `hour`:`minute` local time on the same calendar day.
    public static func time(_ hour: Int, _ minute: Int, on date: Date, in calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: calendar.startOfDay(for: date))
    }
}
