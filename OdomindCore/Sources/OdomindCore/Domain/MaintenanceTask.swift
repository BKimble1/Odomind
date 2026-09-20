import Foundation

public enum MaintenanceCategory: String, Codable, Sendable, CaseIterable, Hashable {
    case engine
    case fluids
    case tiresAndWheels
    case brakes
    case filters
    case ignition
    case electrical
    case drivetrain
    case beltsAndHoses
    case visibility
    case suspensionAndSteering
    case climate
    case seasonal
    case inspection
    case other

    public var displayName: String {
        switch self {
        case .engine: return "Engine"
        case .fluids: return "Fluids"
        case .tiresAndWheels: return "Tires and wheels"
        case .brakes: return "Brakes"
        case .filters: return "Filters"
        case .ignition: return "Ignition"
        case .electrical: return "Electrical"
        case .drivetrain: return "Drivetrain"
        case .beltsAndHoses: return "Belts and hoses"
        case .visibility: return "Visibility"
        case .suspensionAndSteering: return "Suspension and steering"
        case .climate: return "Climate"
        case .seasonal: return "Seasonal"
        case .inspection: return "Inspection"
        case .other: return "Other"
        }
    }

    public var symbolName: String {
        switch self {
        case .engine: return "engine.combustion"
        case .fluids: return "drop"
        case .tiresAndWheels: return "circle.circle"
        case .brakes: return "hexagon"
        case .filters: return "aqi.medium"
        case .ignition: return "bolt"
        case .electrical: return "bolt.batteryblock"
        case .drivetrain: return "gearshape.2"
        case .beltsAndHoses: return "oval.portrait"
        case .visibility: return "windshield.front.and.wiper"
        case .suspensionAndSteering: return "steeringwheel"
        case .climate: return "fan"
        case .seasonal: return "snowflake"
        case .inspection: return "magnifyingglass"
        case .other: return "wrench.adjustable"
        }
    }
}

/// What is actually done when the task is performed.
///
/// Kept separate from the title so the app can say "Inspect brake pads" and
/// "Replace brake pads" without ever implying that an inspection interval is a
/// replacement deadline.
public enum ServiceAction: String, Codable, Sendable, CaseIterable, Hashable {
    case replace
    case inspect
    case rotate
    case adjust
    case serviceOrFlush
    case topOff
    case test
    case recordIndicator
    case clean

    public var verb: String {
        switch self {
        case .replace: return "Replace"
        case .inspect: return "Inspect"
        case .rotate: return "Rotate"
        case .adjust: return "Adjust"
        case .serviceOrFlush: return "Service"
        case .topOff: return "Top off"
        case .test: return "Test"
        case .recordIndicator: return "Record"
        case .clean: return "Clean"
        }
    }

    /// Inspections and tests never become a replacement deadline on their own.
    public var isCheckOnly: Bool {
        switch self {
        case .inspect, .test, .recordIndicator:
            return true
        case .replace, .rotate, .adjust, .serviceOrFlush, .topOff, .clean:
            return false
        }
    }
}

/// Whether a task belongs in a particular vehicle's plan.
public enum TaskApplicability: Hashable, Sendable {
    case applies
    case doesNotApply(reason: String)
    /// Odomind cannot tell yet; the owner is asked rather than guessed at.
    case needsConfirmation(question: ConfigurationQuestion, reason: String)

    public var isApplicable: Bool {
        if case .applies = self { return true }
        return false
    }
}

/// Declarative conditions under which a catalog task applies.
///
/// `nil` means "does not care". A condition that depends on a configuration
/// field the owner has not confirmed produces `needsConfirmation`, never a
/// silent yes or no.
public struct TaskApplicabilityRule: Codable, Hashable, Sendable {
    public var requiresCombustionEngine: Bool?
    public var powertrains: [PowertrainKind]?
    public var excludedPowertrains: [PowertrainKind]?
    public var transmissions: [TransmissionKind]?
    public var requiresTransferCase: Bool?
    public var requiresFrontDifferential: Bool?
    public var requiresRearDifferential: Bool?
    public var camshaftDrives: [CamshaftDrive]?
    public var markets: [Market]?

    public init(
        requiresCombustionEngine: Bool? = nil,
        powertrains: [PowertrainKind]? = nil,
        excludedPowertrains: [PowertrainKind]? = nil,
        transmissions: [TransmissionKind]? = nil,
        requiresTransferCase: Bool? = nil,
        requiresFrontDifferential: Bool? = nil,
        requiresRearDifferential: Bool? = nil,
        camshaftDrives: [CamshaftDrive]? = nil,
        markets: [Market]? = nil
    ) {
        self.requiresCombustionEngine = requiresCombustionEngine
        self.powertrains = powertrains
        self.excludedPowertrains = excludedPowertrains
        self.transmissions = transmissions
        self.requiresTransferCase = requiresTransferCase
        self.requiresFrontDifferential = requiresFrontDifferential
        self.requiresRearDifferential = requiresRearDifferential
        self.camshaftDrives = camshaftDrives
        self.markets = markets
    }

    public static let always = TaskApplicabilityRule()

    public func evaluate(for configuration: VehicleConfiguration) -> TaskApplicability {
        if let requiresCombustionEngine {
            if configuration.powertrain == .unknown {
                return .needsConfirmation(
                    question: .powertrain,
                    reason: "Confirm what this vehicle runs on so Odomind knows whether this applies."
                )
            }
            if configuration.powertrain.hasCombustionEngine != requiresCombustionEngine {
                return .doesNotApply(
                    reason: requiresCombustionEngine
                        ? "This vehicle does not have a combustion engine."
                        : "This task only applies to vehicles without a combustion engine."
                )
            }
        }

        if let powertrains {
            if configuration.powertrain == .unknown {
                return .needsConfirmation(
                    question: .powertrain,
                    reason: "Confirm the powertrain so Odomind knows whether this applies."
                )
            }
            if !powertrains.contains(configuration.powertrain) {
                return .doesNotApply(reason: "Does not apply to a \(configuration.powertrain.displayName.lowercased()) powertrain.")
            }
        }

        if let excludedPowertrains, excludedPowertrains.contains(configuration.powertrain) {
            return .doesNotApply(reason: "Does not apply to a \(configuration.powertrain.displayName.lowercased()) powertrain.")
        }

        if let transmissions {
            if configuration.transmission == .unknown {
                return .needsConfirmation(
                    question: .transmission,
                    reason: "Confirm the transmission so Odomind schedules the right service."
                )
            }
            if !transmissions.contains(configuration.transmission) {
                return .doesNotApply(reason: "Does not apply to a \(configuration.transmission.displayName.lowercased()) transmission.")
            }
        }

        if let requiresTransferCase {
            switch configuration.effectiveTransferCase {
            case .unknown:
                return .needsConfirmation(
                    question: .transferCase,
                    reason: "Confirm whether a transfer case is fitted."
                )
            case .fitted where !requiresTransferCase:
                return .doesNotApply(reason: "This vehicle has a transfer case.")
            case .notFitted where requiresTransferCase:
                return .doesNotApply(reason: "This vehicle does not have a transfer case.")
            default:
                break
            }
        }

        if let requiresFrontDifferential {
            switch configuration.effectiveFrontDifferential {
            case .unknown:
                return .needsConfirmation(
                    question: .drivetrain,
                    reason: "Confirm the drivetrain so Odomind knows which differentials are fitted."
                )
            case .fitted where !requiresFrontDifferential:
                return .doesNotApply(reason: "This vehicle has a front differential.")
            case .notFitted where requiresFrontDifferential:
                return .doesNotApply(reason: "This vehicle does not have a front differential.")
            default:
                break
            }
        }

        if let requiresRearDifferential {
            switch configuration.effectiveRearDifferential {
            case .unknown:
                return .needsConfirmation(
                    question: .drivetrain,
                    reason: "Confirm the drivetrain so Odomind knows which differentials are fitted."
                )
            case .fitted where !requiresRearDifferential:
                return .doesNotApply(reason: "This vehicle has a rear differential.")
            case .notFitted where requiresRearDifferential:
                return .doesNotApply(reason: "This vehicle does not have a rear differential.")
            default:
                break
            }
        }

        if let camshaftDrives {
            if configuration.camshaftDrive == .unknown {
                return .needsConfirmation(
                    question: .camshaftDrive,
                    reason: "Timing-belt service only applies to belt-driven engines. Confirm which this engine uses."
                )
            }
            if !camshaftDrives.contains(configuration.camshaftDrive) {
                return .doesNotApply(reason: "This engine uses a \(configuration.camshaftDrive.displayName.lowercased()).")
            }
        }

        if let markets, configuration.market != .unspecified, !markets.contains(configuration.market) {
            return .doesNotApply(reason: "Not published for the \(configuration.market.displayName) market.")
        }

        return .applies
    }
}

/// A task as published in the catalog, before it is attached to a vehicle.
public struct MaintenanceTaskDefinition: Codable, Hashable, Sendable, Identifiable {
    /// Stable key used by plan items, service records and backups. Never reused
    /// for a different task, because history references it.
    public var id: String
    public var title: String
    /// One or two sentences on what the job is for, in plain language.
    public var purpose: String
    public var category: MaintenanceCategory
    public var action: ServiceAction
    public var applicability: TaskApplicabilityRule
    /// The general template interval. A vehicle-specific schedule from the
    /// catalog overrides this and carries its own provenance.
    public var defaultRule: ScheduleRule?
    public var defaultRuleProvenance: Provenance?
    /// Whether the task is offered during onboarding or only found by search.
    public var isAdvanced: Bool
    /// Specifications worth showing on the task's detail screen.
    public var relatedSpecifications: [SpecificationKind]
    public var searchKeywords: [String]
    public var safetyNote: String?

    public init(
        id: String,
        title: String,
        purpose: String,
        category: MaintenanceCategory,
        action: ServiceAction,
        applicability: TaskApplicabilityRule = .always,
        defaultRule: ScheduleRule? = nil,
        defaultRuleProvenance: Provenance? = nil,
        isAdvanced: Bool = false,
        relatedSpecifications: [SpecificationKind] = [],
        searchKeywords: [String] = [],
        safetyNote: String? = nil
    ) {
        self.id = id
        self.title = title
        self.purpose = purpose
        self.category = category
        self.action = action
        self.applicability = applicability
        self.defaultRule = defaultRule
        self.defaultRuleProvenance = defaultRuleProvenance
        self.isAdvanced = isAdvanced
        self.relatedSpecifications = relatedSpecifications
        self.searchKeywords = searchKeywords
        self.safetyNote = safetyNote
    }

    /// Matches a free-text query against title, purpose and keywords.
    public func matches(query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        if title.lowercased().contains(needle) { return true }
        if purpose.lowercased().contains(needle) { return true }
        if category.displayName.lowercased().contains(needle) { return true }
        return searchKeywords.contains { $0.lowercased().contains(needle) }
    }
}
