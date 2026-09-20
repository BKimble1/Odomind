import Foundation

/// How close to due counts as "due soon" for one task.
public struct DueSoonThreshold: Codable, Hashable, Sendable {
    public var distance: Distance?
    public var days: Int?

    public init(distance: Distance? = nil, days: Int? = nil) {
        self.distance = distance
        self.days = days
    }

    /// The default window: 500 miles or 30 days. Chosen so an owner who checks
    /// the app roughly monthly still gets a warning before the deadline.
    public static let standard = DueSoonThreshold(distance: Distance(500, .miles), days: 30)

    public static let none = DueSoonThreshold()
}

/// When to remind, relative to the due point.
public struct ReminderPreference: Codable, Hashable, Sendable {
    public var isEnabled: Bool
    /// Days before a calendar deadline to fire the reminder.
    public var leadDays: Int
    /// Local hour (0-23) the reminder should arrive.
    public var hour: Int
    public var minute: Int

    public init(isEnabled: Bool = true, leadDays: Int = 7, hour: Int = 9, minute: Int = 0) {
        self.isEnabled = isEnabled
        self.leadDays = max(0, leadDays)
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    public static let standard = ReminderPreference()
    public static let disabled = ReminderPreference(isEnabled: false)
}

/// A catalog-published change to a rule the owner is already using.
///
/// Odomind never rewrites an active schedule underneath someone. When a catalog
/// update carries a different rule for a task the owner already has, the new
/// rule is parked here until it is accepted, and the old rule keeps running.
public struct RuleChangeProposal: Codable, Hashable, Sendable {
    public var proposedRule: ScheduleRule
    public var proposedProvenance: Provenance
    public var catalogVersion: String
    public var proposedOn: Date
    public var summaryOfChange: String

    public init(
        proposedRule: ScheduleRule,
        proposedProvenance: Provenance,
        catalogVersion: String,
        proposedOn: Date,
        summaryOfChange: String
    ) {
        self.proposedRule = proposedRule
        self.proposedProvenance = proposedProvenance
        self.catalogVersion = catalogVersion
        self.proposedOn = proposedOn
        self.summaryOfChange = summaryOfChange
    }
}

/// Whether the owner has told Odomind anything about past completions.
public enum HistoryBaseline: Hashable, Sendable {
    /// Nothing recorded and the owner has not said either way. The task sits in
    /// "Needs setup" and is never shown as due or as up to date.
    case notProvided
    /// The owner explicitly said they do not know. Odomind stops asking and
    /// keeps the task visibly separate from scheduled work.
    case unknownToOwner
    /// The owner supplied a starting point without a full service record.
    case declared(date: Date?, odometer: Distance?)

    public var isKnown: Bool {
        switch self {
        case .notProvided, .unknownToOwner: return false
        case .declared(let date, let odometer): return date != nil || odometer != nil
        }
    }

    /// True when the owner has answered, even if the answer was "I don't know".
    public var isAnswered: Bool {
        if case .notProvided = self { return false }
        return true
    }
}

// Written by hand because this value travels in the versioned backup format,
// where a stable discriminator matters more than brevity.
extension HistoryBaseline: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case date
        case odometer
    }

    private enum Kind: String, Codable {
        case notProvided
        case unknownToOwner
        case declared
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .notProvided:
            self = .notProvided
        case .unknownToOwner:
            self = .unknownToOwner
        case .declared:
            self = .declared(
                date: try container.decodeIfPresent(Date.self, forKey: .date),
                odometer: try container.decodeIfPresent(Distance.self, forKey: .odometer)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .notProvided:
            try container.encode(Kind.notProvided, forKey: .type)
        case .unknownToOwner:
            try container.encode(Kind.unknownToOwner, forKey: .type)
        case .declared(let date, let odometer):
            try container.encode(Kind.declared, forKey: .type)
            try container.encodeIfPresent(date, forKey: .date)
            try container.encodeIfPresent(odometer, forKey: .odometer)
        }
    }
}

/// An active maintenance task for one vehicle.
///
/// The effective rule is the owner's override when they set one, otherwise the
/// catalog's. Both are kept so the app can show what changed and so an override
/// survives every catalog update.
public struct MaintenancePlanItem: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var vehicleID: UUID
    /// Catalog key, or a generated key for a custom task.
    public var definitionID: String
    public var title: String
    public var purpose: String
    public var category: MaintenanceCategory
    public var action: ServiceAction

    public var catalogRule: ScheduleRule?
    public var catalogProvenance: Provenance?
    /// Set when the owner edits the schedule. Never overwritten by a catalog
    /// update.
    public var ownerRule: ScheduleRule?
    public var pendingProposal: RuleChangeProposal?

    public var baseline: HistoryBaseline
    public var isEnabled: Bool
    public var snoozedUntil: Date?
    public var dueSoonThreshold: DueSoonThreshold
    public var reminder: ReminderPreference
    public var relatedSpecifications: [SpecificationKind]
    public var notes: String?
    public var isCustom: Bool
    public var safetyNote: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        vehicleID: UUID,
        definitionID: String,
        title: String,
        purpose: String = "",
        category: MaintenanceCategory,
        action: ServiceAction,
        catalogRule: ScheduleRule? = nil,
        catalogProvenance: Provenance? = nil,
        ownerRule: ScheduleRule? = nil,
        pendingProposal: RuleChangeProposal? = nil,
        baseline: HistoryBaseline = .notProvided,
        isEnabled: Bool = true,
        snoozedUntil: Date? = nil,
        dueSoonThreshold: DueSoonThreshold = .standard,
        reminder: ReminderPreference = .disabled,
        relatedSpecifications: [SpecificationKind] = [],
        notes: String? = nil,
        isCustom: Bool = false,
        safetyNote: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.vehicleID = vehicleID
        self.definitionID = definitionID
        self.title = title
        self.purpose = purpose
        self.category = category
        self.action = action
        self.catalogRule = catalogRule
        self.catalogProvenance = catalogProvenance
        self.ownerRule = ownerRule
        self.pendingProposal = pendingProposal
        self.baseline = baseline
        self.isEnabled = isEnabled
        self.snoozedUntil = snoozedUntil
        self.dueSoonThreshold = dueSoonThreshold
        self.reminder = reminder
        self.relatedSpecifications = relatedSpecifications
        self.notes = notes
        self.isCustom = isCustom
        self.safetyNote = safetyNote
        self.createdAt = createdAt
    }

    /// The rule actually used for scheduling.
    public var effectiveRule: ScheduleRule? { ownerRule ?? catalogRule }

    public var isOwnerOverridden: Bool { ownerRule != nil }

    /// Provenance of the rule in force.
    public var effectiveProvenance: Provenance {
        if ownerRule != nil { return .userEntered }
        return catalogProvenance ?? Provenance(origin: .generalTemplate)
    }

    public var hasPendingProposal: Bool { pendingProposal != nil }

    /// Applies a catalog-published rule.
    ///
    /// When the owner has an override, or the incoming rule differs from the one
    /// already running, the change is parked as a proposal instead of being
    /// applied. Only an identical rule updates silently, which keeps provenance
    /// fresh without changing behaviour.
    public mutating func apply(
        catalogRule newRule: ScheduleRule,
        provenance newProvenance: Provenance,
        catalogVersion: String,
        now: Date
    ) {
        guard let existing = catalogRule else {
            catalogRule = newRule
            catalogProvenance = newProvenance
            return
        }

        if existing == newRule {
            catalogProvenance = newProvenance
            return
        }

        pendingProposal = RuleChangeProposal(
            proposedRule: newRule,
            proposedProvenance: newProvenance,
            catalogVersion: catalogVersion,
            proposedOn: now,
            summaryOfChange: "\(effectiveRule?.summary ?? "No schedule") → \(newRule.summary)"
        )
    }

    /// Accepts a parked proposal. An owner override is cleared only because
    /// accepting is an explicit choice to use the published schedule.
    public mutating func acceptPendingProposal() {
        guard let proposal = pendingProposal else { return }
        catalogRule = proposal.proposedRule
        catalogProvenance = proposal.proposedProvenance
        ownerRule = nil
        pendingProposal = nil
    }

    /// Dismisses a parked proposal and keeps the current schedule.
    public mutating func dismissPendingProposal() {
        pendingProposal = nil
    }
}
