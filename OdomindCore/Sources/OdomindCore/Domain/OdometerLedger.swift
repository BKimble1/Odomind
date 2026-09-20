import Foundation

/// A problem found while validating an odometer entry.
public enum OdometerIssue: Hashable, Sendable {
    case futureDated(Date)
    case negativeValue
    case implausiblyLarge(Distance)
    case duplicateOfExisting(existing: Distance, on: Date)
    /// The reading is lower than an earlier one. Not treated as an error on its
    /// own — the owner is offered a correction or an odometer-replacement entry.
    case decreasedFromEarlier(earlier: Distance, earlierDate: Date)
    /// A very large jump that is more likely a typo (extra digit) than driving.
    case implausibleIncrease(perDay: Int, unit: DistanceUnit)

    public var isBlocking: Bool {
        switch self {
        case .futureDated, .negativeValue, .implausiblyLarge:
            return true
        case .duplicateOfExisting, .decreasedFromEarlier, .implausibleIncrease:
            return false
        }
    }
}

/// Reads a vehicle's odometer history on a single continuous scale.
///
/// Raw readings restart at zero when an instrument cluster is replaced. The
/// ledger folds recorded replacements back in so the scheduling engine always
/// works with cumulative distance, while the UI keeps showing the number that
/// is actually on the dash.
public struct OdometerLedger: Sendable {
    public let vehicle: Vehicle
    /// Readings sorted oldest first.
    public let readings: [OdometerReading]

    public init(vehicle: Vehicle, readings: [OdometerReading]) {
        self.vehicle = vehicle
        self.readings = readings
            .filter { $0.vehicleID == vehicle.id }
            .sorted { lhs, rhs in
                if lhs.recordedOn == rhs.recordedOn {
                    return lhs.value < rhs.value
                }
                return lhs.recordedOn < rhs.recordedOn
            }
    }

    /// Distance to add to a raw reading taken on `date` to place it on the
    /// cumulative scale.
    public func offset(on date: Date) -> Distance {
        let applicable = vehicle.odometerReplacements.filter { $0.occurredOn <= date }
        guard !applicable.isEmpty else { return Distance(0, vehicle.displayUnit) }
        var total = Distance(0, vehicle.displayUnit)
        for replacement in applicable {
            total = total + replacement.offset
        }
        return total
    }

    /// A raw reading placed on the cumulative scale.
    public func cumulative(_ reading: OdometerReading) -> Distance {
        reading.value + offset(on: reading.recordedOn)
    }

    /// A raw value placed on the cumulative scale as of `date`.
    public func cumulative(rawValue: Distance, on date: Date) -> Distance {
        rawValue + offset(on: date)
    }

    /// Turns a cumulative distance back into the number the dash would show on
    /// `date`, for display alongside the owner's own readings.
    public func rawValue(cumulative value: Distance, on date: Date) -> Distance {
        value - offset(on: date)
    }

    public var latestReading: OdometerReading? { readings.last }

    /// The most recent reading on the cumulative scale.
    public var latestCumulative: Distance? {
        guard let latestReading else { return nil }
        return cumulative(latestReading)
    }

    /// The most recent reading at or before `date`, on the cumulative scale.
    public func cumulativeReading(asOf date: Date) -> (distance: Distance, recordedOn: Date)? {
        guard let reading = readings.last(where: { $0.recordedOn <= date }) else { return nil }
        return (cumulative(reading), reading.recordedOn)
    }

    /// Validates a proposed reading against the existing history.
    ///
    /// Returns every issue found rather than the first, so the entry screen can
    /// explain all of them at once and offer the right correction.
    public func issues(
        forProposed value: Distance,
        on date: Date,
        now: Date,
        calendar: Calendar,
        excluding existingID: UUID? = nil
    ) -> [OdometerIssue] {
        var found: [OdometerIssue] = []

        if calendar.startOfDay(for: date) > calendar.startOfDay(for: now) {
            found.append(.futureDated(date))
        }
        if value.isNegative {
            found.append(.negativeValue)
        }
        if value > Distance(2_000_000, .miles) {
            found.append(.implausiblyLarge(value))
        }

        let others = readings.filter { $0.id != existingID }
        let earlier = others.last { $0.recordedOn <= date }
        if let earlier {
            let earlierCumulative = cumulative(earlier)
            let proposedCumulative = cumulative(rawValue: value, on: date)
            if proposedCumulative < earlierCumulative {
                found.append(.decreasedFromEarlier(earlier: earlier.value, earlierDate: earlier.recordedOn))
            } else {
                let days = max(1, DateSupport.dayCount(from: earlier.recordedOn, to: date, in: calendar))
                let delta = proposedCumulative - earlierCumulative
                let perDay = delta.amount / days
                if perDay > OdometerLedger.implausibleDailyDistance(in: delta.unit) {
                    found.append(.implausibleIncrease(perDay: perDay, unit: delta.unit))
                }
            }
            if earlier.value == value,
               calendar.isDate(earlier.recordedOn, inSameDayAs: date) {
                found.append(.duplicateOfExisting(existing: earlier.value, on: earlier.recordedOn))
            }
        }

        return found
    }

    /// Above this many units per day a reading is more likely a typo than a
    /// road trip. Deliberately generous: a long haul driver can cover 1,000
    /// miles in a day, so the threshold only catches an extra digit.
    static func implausibleDailyDistance(in unit: DistanceUnit) -> Int {
        switch unit {
        case .miles: return 2_000
        case .kilometers: return 3_200
        }
    }
}
