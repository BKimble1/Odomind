import Foundation

/// A data source the catalog draws on, with the terms it was used under.
///
/// Every value that claims a manufacturer source has to point at one of these,
/// which is what makes "verified" auditable rather than decorative.
public struct CatalogSource: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var url: String?
    /// What this source does and does not cover, in plain language.
    public var coverage: String
    /// The terms the data is used under.
    public var terms: String
    /// Whether the source permits redistributing its content inside this app.
    public var allowsRedistribution: Bool
    public var attributionRequired: Bool
    public var attributionText: String?
    public var retrievedOn: Date?
    /// Known operational limits: rate limits, downtime, stale records.
    public var limitations: String

    public init(
        id: String,
        name: String,
        url: String? = nil,
        coverage: String,
        terms: String,
        allowsRedistribution: Bool,
        attributionRequired: Bool = false,
        attributionText: String? = nil,
        retrievedOn: Date? = nil,
        limitations: String
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.coverage = coverage
        self.terms = terms
        self.allowsRedistribution = allowsRedistribution
        self.attributionRequired = attributionRequired
        self.attributionText = attributionText
        self.retrievedOn = retrievedOn
        self.limitations = limitations
    }
}

/// How specific a profile match is. A more specific match wins.
public enum ProfileMatchQuality: Int, Sendable, Hashable, Comparable {
    case none = 0
    case makeModel = 1
    case makeModelYear = 2
    case makeModelYearEngine = 3

    public static func < (lhs: ProfileMatchQuality, rhs: ProfileMatchQuality) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The vehicles a profile applies to.
public struct VehicleMatch: Codable, Hashable, Sendable {
    public var makes: [String]
    public var models: [String]
    public var earliestModelYear: Int?
    public var latestModelYear: Int?
    public var engineDisplacementLiters: [Double]?
    public var engineCodes: [String]?
    public var markets: [Market]?

    public init(
        makes: [String],
        models: [String],
        earliestModelYear: Int? = nil,
        latestModelYear: Int? = nil,
        engineDisplacementLiters: [Double]? = nil,
        engineCodes: [String]? = nil,
        markets: [Market]? = nil
    ) {
        self.makes = makes
        self.models = models
        self.earliestModelYear = earliestModelYear
        self.latestModelYear = latestModelYear
        self.engineDisplacementLiters = engineDisplacementLiters
        self.engineCodes = engineCodes
        self.markets = markets
    }

    /// Scores a vehicle against this match.
    ///
    /// Returns `.none` unless make **and** model match. A year or engine
    /// constraint that the vehicle contradicts also returns `.none`: Odomind
    /// would rather have no profile than the wrong one.
    public func quality(for identity: VehicleIdentity, configuration: VehicleConfiguration) -> ProfileMatchQuality {
        let make = identity.make.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let model = identity.model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard makes.contains(where: { $0.lowercased() == make }) else { return .none }
        guard models.contains(where: { $0.lowercased() == model }) else { return .none }

        var quality = ProfileMatchQuality.makeModel

        if earliestModelYear != nil || latestModelYear != nil {
            guard let year = identity.modelYear else { return .none }
            if let earliest = earliestModelYear, year < earliest { return .none }
            if let latest = latestModelYear, year > latest { return .none }
            quality = .makeModelYear
        }

        if let displacements = engineDisplacementLiters, !displacements.isEmpty {
            guard let actual = configuration.engineDisplacementLiters else { return .none }
            guard displacements.contains(where: { abs($0 - actual) < 0.05 }) else { return .none }
            quality = .makeModelYearEngine
        }

        if let codes = engineCodes, !codes.isEmpty {
            guard let actual = configuration.engineCode?.uppercased() else { return .none }
            guard codes.contains(where: { $0.uppercased() == actual }) else { return .none }
            quality = .makeModelYearEngine
        }

        if let markets, !markets.isEmpty, configuration.market != .unspecified {
            guard markets.contains(configuration.market) else { return .none }
        }

        return quality
    }
}

/// A specification published for a matched vehicle.
public struct ProfileSpecification: Codable, Hashable, Sendable {
    public var kind: SpecificationKind
    public var value: SpecificationValue
    public var provenance: Provenance
    public var basis: EquipmentBasis
    public var appliesToNote: String?
    /// The `CatalogSource.id` this value came from.
    public var sourceID: String

    public init(
        kind: SpecificationKind,
        value: SpecificationValue,
        provenance: Provenance,
        basis: EquipmentBasis = .factory,
        appliesToNote: String? = nil,
        sourceID: String
    ) {
        self.kind = kind
        self.value = value
        self.provenance = provenance
        self.basis = basis
        self.appliesToNote = appliesToNote
        self.sourceID = sourceID
    }
}

/// A schedule published for a matched vehicle, replacing the general template.
public struct ProfileScheduleRule: Codable, Hashable, Sendable {
    public var definitionID: String
    public var rule: ScheduleRule
    public var provenance: Provenance
    /// When set, the rule only applies to that usage profile, so an owner can
    /// knowingly choose between a normal and a severe schedule.
    public var usageProfile: UsageProfile?
    public var sourceID: String
    public var note: String?

    public init(
        definitionID: String,
        rule: ScheduleRule,
        provenance: Provenance,
        usageProfile: UsageProfile? = nil,
        sourceID: String,
        note: String? = nil
    ) {
        self.definitionID = definitionID
        self.rule = rule
        self.provenance = provenance
        self.usageProfile = usageProfile
        self.sourceID = sourceID
        self.note = note
    }
}

/// Configuration facts a profile can pre-fill, each with its own provenance.
///
/// Pre-filling is a suggestion, not a decision: the owner still confirms during
/// setup, and nothing here is treated as verified unless its provenance says so.
public struct ProfileConfigurationFact: Codable, Hashable, Sendable {
    public enum Field: String, Codable, Sendable, CaseIterable, Hashable {
        case powertrain
        case engineDisplacementLiters
        case engineCylinders
        case engineCode
        case camshaftDrive
        case drivetrain
        case transmission
        case transferCase
    }

    public var field: Field
    /// Raw value; interpreted per `field`.
    public var value: String
    public var provenance: Provenance
    public var sourceID: String

    public init(field: Field, value: String, provenance: Provenance, sourceID: String) {
        self.field = field
        self.value = value
        self.provenance = provenance
        self.sourceID = sourceID
    }
}

/// Everything the catalog knows about one family of vehicles.
public struct VehicleProfile: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var displayName: String
    public var match: VehicleMatch
    public var configurationFacts: [ProfileConfigurationFact]
    public var specifications: [ProfileSpecification]
    public var scheduleRules: [ProfileScheduleRule]
    /// Honest statements about what this profile does not contain.
    public var coverageNotes: [String]

    public init(
        id: String,
        displayName: String,
        match: VehicleMatch,
        configurationFacts: [ProfileConfigurationFact] = [],
        specifications: [ProfileSpecification] = [],
        scheduleRules: [ProfileScheduleRule] = [],
        coverageNotes: [String] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.match = match
        self.configurationFacts = configurationFacts
        self.specifications = specifications
        self.scheduleRules = scheduleRules
        self.coverageNotes = coverageNotes
    }
}

/// Fictional sample content, kept strictly separate from real records.
///
/// Every object created from this is flagged `isDemo`, shown with a demo badge,
/// excluded from exports by default and removable in one action.
public struct CatalogDemoContent: Codable, Hashable, Sendable {
    public var vehicleNickname: String
    public var identity: VehicleIdentity
    public var configuration: VehicleConfiguration
    public var displayUnit: DistanceUnit
    public var inServiceOn: Date?
    public var readings: [CatalogDemoReading]
    public var services: [CatalogDemoService]
    public var disclaimer: String

    public init(
        vehicleNickname: String,
        identity: VehicleIdentity,
        configuration: VehicleConfiguration,
        displayUnit: DistanceUnit,
        inServiceOn: Date? = nil,
        readings: [CatalogDemoReading],
        services: [CatalogDemoService],
        disclaimer: String
    ) {
        self.vehicleNickname = vehicleNickname
        self.identity = identity
        self.configuration = configuration
        self.displayUnit = displayUnit
        self.inServiceOn = inServiceOn
        self.readings = readings
        self.services = services
        self.disclaimer = disclaimer
    }
}

public struct CatalogDemoReading: Codable, Hashable, Sendable {
    /// Days before "today" this reading was taken, so the sample stays current
    /// however long after publication it is loaded.
    public var daysAgo: Int
    public var value: Int

    public init(daysAgo: Int, value: Int) {
        self.daysAgo = daysAgo
        self.value = value
    }
}

public struct CatalogDemoService: Codable, Hashable, Sendable {
    public var daysAgo: Int
    public var odometer: Int
    public var definitionIDs: [String]
    public var totalCostMinorUnits: Int?
    public var currencyCode: String?
    public var shopName: String?
    public var notes: String?

    public init(
        daysAgo: Int,
        odometer: Int,
        definitionIDs: [String],
        totalCostMinorUnits: Int? = nil,
        currencyCode: String? = nil,
        shopName: String? = nil,
        notes: String? = nil
    ) {
        self.daysAgo = daysAgo
        self.odometer = odometer
        self.definitionIDs = definitionIDs
        self.totalCostMinorUnits = totalCostMinorUnits
        self.currencyCode = currencyCode
        self.shopName = shopName
        self.notes = notes
    }
}

/// The bundled, versioned maintenance catalog.
public struct MaintenanceCatalog: Codable, Hashable, Sendable {
    /// Bumped whenever the decoded shape changes in a way old builds cannot read.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    /// Human-readable content version, e.g. "2026.09.1".
    public var catalogVersion: String
    public var publishedOn: Date
    /// Shown in the app so coverage is never overstated.
    public var coverageNotice: String
    public var sources: [CatalogSource]
    public var taskDefinitions: [MaintenanceTaskDefinition]
    public var vehicleProfiles: [VehicleProfile]
    public var demoContent: CatalogDemoContent?

    public init(
        schemaVersion: Int = MaintenanceCatalog.currentSchemaVersion,
        catalogVersion: String,
        publishedOn: Date,
        coverageNotice: String,
        sources: [CatalogSource],
        taskDefinitions: [MaintenanceTaskDefinition],
        vehicleProfiles: [VehicleProfile] = [],
        demoContent: CatalogDemoContent? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.catalogVersion = catalogVersion
        self.publishedOn = publishedOn
        self.coverageNotice = coverageNotice
        self.sources = sources
        self.taskDefinitions = taskDefinitions
        self.vehicleProfiles = vehicleProfiles
        self.demoContent = demoContent
    }

    public func definition(id: String) -> MaintenanceTaskDefinition? {
        taskDefinitions.first { $0.id == id }
    }

    public func source(id: String) -> CatalogSource? {
        sources.first { $0.id == id }
    }

    public var definitionsByID: [String: MaintenanceTaskDefinition] {
        Dictionary(taskDefinitions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The best-matching profile for a vehicle, or `nil` when the catalog has
    /// nothing specific. `nil` is a normal, well-handled outcome.
    public func bestProfile(
        for identity: VehicleIdentity,
        configuration: VehicleConfiguration
    ) -> VehicleProfile? {
        var best: (profile: VehicleProfile, quality: ProfileMatchQuality)?
        for profile in vehicleProfiles {
            let quality = profile.match.quality(for: identity, configuration: configuration)
            guard quality != .none else { continue }
            if let current = best {
                if quality > current.quality { best = (profile, quality) }
            } else {
                best = (profile, quality)
            }
        }
        return best?.profile
    }
}
