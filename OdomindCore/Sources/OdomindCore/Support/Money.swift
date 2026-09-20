import Foundation

/// A decimal money amount tagged with its ISO 4217 currency code.
///
/// Costs are stored as `Decimal` rather than `Double` so that a receipt total
/// of 89.97 round-trips exactly. `Money` never implicitly converts between
/// currencies; combining amounts is done through `MoneyTotal`, which keeps
/// mixed currencies visibly separate instead of producing a misleading sum.
public struct Money: Codable, Hashable, Sendable {
    public var amount: Decimal
    /// Uppercase ISO 4217 code, e.g. `USD`.
    public var currencyCode: String

    public init(amount: Decimal, currencyCode: String) {
        self.amount = amount
        self.currencyCode = currencyCode.uppercased()
    }

    public var isNegative: Bool { amount < 0 }
}

/// The result of adding up a set of `Money` values.
///
/// Odomind refuses to add USD to CAD. When a history filter spans more than one
/// currency the UI shows each currency's subtotal rather than a single number
/// that would be wrong in every currency.
public enum MoneyTotal: Hashable, Sendable {
    case empty
    case single(Money)
    case mixed([Money])

    /// Sums `values`, grouping by currency.
    public static func total<S: Sequence>(of values: S) -> MoneyTotal where S.Element == Money {
        var byCurrency: [String: Decimal] = [:]
        var order: [String] = []
        for value in values {
            if byCurrency[value.currencyCode] == nil {
                order.append(value.currencyCode)
            }
            byCurrency[value.currencyCode, default: 0] += value.amount
        }
        switch order.count {
        case 0:
            return .empty
        case 1:
            let code = order[0]
            return .single(Money(amount: byCurrency[code] ?? 0, currencyCode: code))
        default:
            return .mixed(order.map { Money(amount: byCurrency[$0] ?? 0, currencyCode: $0) })
        }
    }

    public var isMixedCurrency: Bool {
        if case .mixed = self { return true }
        return false
    }

    /// All currency subtotals, in first-seen order.
    public var components: [Money] {
        switch self {
        case .empty: return []
        case .single(let money): return [money]
        case .mixed(let monies): return monies
        }
    }
}
