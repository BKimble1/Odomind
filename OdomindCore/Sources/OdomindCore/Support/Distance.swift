import Foundation

/// The distance units Odomind supports for odometers and service intervals.
public enum DistanceUnit: String, Codable, Sendable, CaseIterable, Hashable {
    case miles
    case kilometers

    /// Exact whole-millimetre size of one unit.
    ///
    /// One international mile is exactly 1609.344 m, so both units convert to a
    /// whole number of millimetres. Working in that integer space means Odomind
    /// never accumulates floating-point drift when it compares a reading taken
    /// in kilometres against an interval published in miles.
    var millimetresPerUnit: Int {
        switch self {
        case .miles: return 1_609_344
        case .kilometers: return 1_000_000
        }
    }

    public var abbreviation: String {
        switch self {
        case .miles: return "mi"
        case .kilometers: return "km"
        }
    }

    public var localizedName: String {
        switch self {
        case .miles: return "miles"
        case .kilometers: return "kilometers"
        }
    }
}

/// A distance expressed as a whole number of miles or kilometres.
///
/// Odometers, service intervals and thresholds are always whole numbers in
/// practice, so `Distance` stores an `Int` in the unit it was captured in and
/// compares through an exact integer millimetre scale. Equality is defined on
/// that scale, which keeps `==`, `<` and `hashValue` mutually consistent while
/// still letting the UI show the number the owner actually typed.
public struct Distance: Codable, Hashable, Sendable, Comparable, CustomStringConvertible {
    /// Whole units in `unit`. Negative values occur only for computed deltas.
    public let amount: Int
    public let unit: DistanceUnit

    public init(_ amount: Int, _ unit: DistanceUnit) {
        self.amount = amount
        self.unit = unit
    }

    public static func miles(_ amount: Int) -> Distance { Distance(amount, .miles) }
    public static func kilometers(_ amount: Int) -> Distance { Distance(amount, .kilometers) }

    /// Exact integer millimetre value used for every comparison.
    public var millimetres: Int { amount * unit.millimetresPerUnit }

    /// Converts to `target`, rounding half away from zero to a whole unit.
    ///
    /// Rounding is only applied when producing a value for display or for the
    /// owner's preferred unit. Comparisons use `millimetres` and never round.
    public func converted(to target: DistanceUnit) -> Distance {
        if target == unit { return self }
        let scaled = Double(millimetres) / Double(target.millimetresPerUnit)
        return Distance(Int(scaled.rounded()), target)
    }

    public var isZero: Bool { amount == 0 }
    public var isNegative: Bool { amount < 0 }
    public var magnitude: Distance { Distance(abs(amount), unit) }

    public static func == (lhs: Distance, rhs: Distance) -> Bool {
        lhs.millimetres == rhs.millimetres
    }

    public static func < (lhs: Distance, rhs: Distance) -> Bool {
        lhs.millimetres < rhs.millimetres
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(millimetres)
    }

    /// Sum, expressed in the left operand's unit.
    public static func + (lhs: Distance, rhs: Distance) -> Distance {
        let right = rhs.converted(to: lhs.unit)
        return Distance(lhs.amount + right.amount, lhs.unit)
    }

    /// Difference, expressed in the left operand's unit.
    public static func - (lhs: Distance, rhs: Distance) -> Distance {
        let right = rhs.converted(to: lhs.unit)
        return Distance(lhs.amount - right.amount, lhs.unit)
    }

    public static func * (lhs: Distance, rhs: Int) -> Distance {
        Distance(lhs.amount * rhs, lhs.unit)
    }

    public var description: String { "\(amount) \(unit.abbreviation)" }
}
