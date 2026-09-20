import Foundation

public enum ServicePerformer: Hashable, Sendable {
    case doItYourself
    case shop(name: String)

    public var displayName: String {
        switch self {
        case .doItYourself: return "DIY"
        case .shop(let name):
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Shop" : trimmed
        }
    }

    public var shopName: String? {
        if case .shop(let name) = self { return name }
        return nil
    }
}

extension ServicePerformer: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case name
    }

    private enum Kind: String, Codable {
        case diy
        case shop
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .diy:
            self = .doItYourself
        case .shop:
            self = .shop(name: try container.decodeIfPresent(String.self, forKey: .name) ?? "")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .doItYourself:
            try container.encode(Kind.diy, forKey: .type)
        case .shop(let name):
            try container.encode(Kind.shop, forKey: .type)
            try container.encode(name, forKey: .name)
        }
    }
}

/// One completed task inside a service visit.
///
/// A line item carries an optional cost of its own. It deliberately does **not**
/// carry the visit total: a single receipt covering four jobs must not be
/// counted four times, so `ServiceRecord.totalCost` is the only figure that
/// feeds spending summaries.
public struct ServiceLineItem: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    /// The plan item this completion satisfies, when the task is in the plan.
    public var planItemID: UUID?
    /// Catalog key or custom-task key, kept even if the plan item is deleted so
    /// history survives.
    public var definitionID: String
    public var title: String
    public var action: ServiceAction
    /// Optional per-item breakdown. `nil` means "not broken out", not "free".
    public var itemCost: Money?
    public var notes: String?

    public init(
        id: UUID = UUID(),
        planItemID: UUID? = nil,
        definitionID: String,
        title: String,
        action: ServiceAction,
        itemCost: Money? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.planItemID = planItemID
        self.definitionID = definitionID
        self.title = title
        self.action = action
        self.itemCost = itemCost
        self.notes = notes
    }
}

/// A completed service visit.
public struct ServiceRecord: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var vehicleID: UUID
    public var performedOn: Date
    /// Odometer as read on the day of service, before any replacement offset.
    public var odometer: Distance?
    public var items: [ServiceLineItem]
    /// The whole visit's cost. Counted once, no matter how many items.
    public var totalCost: Money?
    public var performer: ServicePerformer
    public var notes: String?
    public var attachmentIDs: [UUID]
    public var isDemo: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        vehicleID: UUID,
        performedOn: Date,
        odometer: Distance? = nil,
        items: [ServiceLineItem] = [],
        totalCost: Money? = nil,
        performer: ServicePerformer = .doItYourself,
        notes: String? = nil,
        attachmentIDs: [UUID] = [],
        isDemo: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.vehicleID = vehicleID
        self.performedOn = performedOn
        self.odometer = odometer
        self.items = items
        self.totalCost = totalCost
        self.performer = performer
        self.notes = notes
        self.attachmentIDs = attachmentIDs
        self.isDemo = isDemo
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func includes(definitionID: String) -> Bool {
        items.contains { $0.definitionID == definitionID }
    }

    public var title: String {
        switch items.count {
        case 0: return "Service"
        case 1: return items[0].title
        default: return "\(items[0].title) and \(items.count - 1) more"
        }
    }
}

/// Problems found before saving a service record.
public enum ServiceRecordIssue: Hashable, Sendable {
    case futureDated(Date)
    case noItems
    case negativeCost
    case odometerBelowEarlierReading(earlier: Distance, on: Date)
    case duplicateDefinition(String)
    case itemCostsExceedTotal
    case mixedCurrencies

    public var isBlocking: Bool {
        switch self {
        case .futureDated, .noItems, .negativeCost, .duplicateDefinition, .mixedCurrencies:
            return true
        case .odometerBelowEarlierReading, .itemCostsExceedTotal:
            return false
        }
    }

    public var message: String {
        switch self {
        case .futureDated:
            return "This service is dated in the future."
        case .noItems:
            return "Choose at least one task that was completed."
        case .negativeCost:
            return "Cost cannot be negative."
        case .odometerBelowEarlierReading(let earlier, _):
            return "The odometer is lower than an earlier reading of \(earlier.description)."
        case .duplicateDefinition:
            return "The same task is listed twice in this visit."
        case .itemCostsExceedTotal:
            return "The itemised costs add up to more than the visit total."
        case .mixedCurrencies:
            return "All costs in one visit must use the same currency."
        }
    }
}

public enum ServiceRecordValidator {
    public static func issues(
        for record: ServiceRecord,
        ledger: OdometerLedger,
        now: Date,
        calendar: Calendar
    ) -> [ServiceRecordIssue] {
        var found: [ServiceRecordIssue] = []

        if calendar.startOfDay(for: record.performedOn) > calendar.startOfDay(for: now) {
            found.append(.futureDated(record.performedOn))
        }
        if record.items.isEmpty {
            found.append(.noItems)
        }
        if let total = record.totalCost, total.isNegative {
            found.append(.negativeCost)
        }
        if record.items.contains(where: { ($0.itemCost?.isNegative ?? false) }) {
            found.append(.negativeCost)
        }

        var seen = Set<String>()
        for item in record.items {
            if !seen.insert(item.definitionID).inserted {
                found.append(.duplicateDefinition(item.title))
            }
        }

        var currencies = Set<String>()
        if let total = record.totalCost { currencies.insert(total.currencyCode) }
        for item in record.items {
            if let cost = item.itemCost { currencies.insert(cost.currencyCode) }
        }
        if currencies.count > 1 {
            found.append(.mixedCurrencies)
        }

        if let total = record.totalCost, currencies.count <= 1 {
            let itemised = record.items.compactMap { $0.itemCost?.amount }
            if !itemised.isEmpty {
                let sum = itemised.reduce(Decimal(0), +)
                if sum > total.amount {
                    found.append(.itemCostsExceedTotal)
                }
            }
        }

        if let odometer = record.odometer {
            let cumulative = ledger.cumulative(rawValue: odometer, on: record.performedOn)
            if let earlier = ledger.cumulativeReading(asOf: record.performedOn), cumulative < earlier.distance {
                found.append(.odometerBelowEarlierReading(earlier: earlier.distance, on: earlier.recordedOn))
            }
        }

        return found
    }
}
