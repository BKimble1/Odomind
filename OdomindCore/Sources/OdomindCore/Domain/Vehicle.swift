import Foundation

/// The identity of a vehicle, separate from its mechanical configuration.
///
/// Identification (who made it, what model, what VIN) and specification (what
/// fluid it takes) come from different sources with different reliability, so
/// Odomind keeps them in different types and never lets one imply the other.
public struct VehicleIdentity: Codable, Hashable, Sendable {
    public var modelYear: Int?
    public var make: String
    public var model: String
    public var trim: String?
    public var series: String?
    public var bodyClass: String?
    /// Stored locally only. Never logged, never exported in analytics, never
    /// included in a crash report or a screenshot fixture.
    public var vin: String?
    public var identityProvenance: DataOrigin

    public init(
        modelYear: Int? = nil,
        make: String,
        model: String,
        trim: String? = nil,
        series: String? = nil,
        bodyClass: String? = nil,
        vin: String? = nil,
        identityProvenance: DataOrigin = .userEntered
    ) {
        self.modelYear = modelYear
        self.make = make
        self.model = model
        self.trim = trim
        self.series = series
        self.bodyClass = bodyClass
        self.vin = vin
        self.identityProvenance = identityProvenance
    }

    public var displayName: String {
        var parts: [String] = []
        if let modelYear { parts.append(String(modelYear)) }
        if !make.isEmpty { parts.append(make) }
        if !model.isEmpty { parts.append(model) }
        if let trim, !trim.isEmpty { parts.append(trim) }
        return parts.isEmpty ? "Vehicle" : parts.joined(separator: " ")
    }

    /// The last six characters of the VIN, for confirming which vehicle you are
    /// looking at without putting the full number on screen.
    public var vinSuffix: String? {
        guard let vin, vin.count >= 6 else { return nil }
        return String(vin.suffix(6))
    }
}

/// Records that the odometer unit itself was replaced.
///
/// Without this, a legitimate instrument-cluster swap looks identical to a typo.
/// Odomind refuses to treat a decreasing reading as a replacement on its own;
/// the owner has to record one explicitly.
public struct OdometerReplacement: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var occurredOn: Date
    /// Final reading shown on the unit being removed.
    public var previousUnitFinalReading: Distance
    /// Reading shown on the newly fitted unit, usually but not always zero.
    public var replacementUnitStartReading: Distance
    public var note: String?

    public init(
        id: UUID = UUID(),
        occurredOn: Date,
        previousUnitFinalReading: Distance,
        replacementUnitStartReading: Distance,
        note: String? = nil
    ) {
        self.id = id
        self.occurredOn = occurredOn
        self.previousUnitFinalReading = previousUnitFinalReading
        self.replacementUnitStartReading = replacementUnitStartReading
        self.note = note
    }

    /// Distance to add to readings taken after this replacement so they stay on
    /// the same cumulative scale as earlier readings.
    public var offset: Distance {
        previousUnitFinalReading - replacementUnitStartReading
    }
}

public enum OdometerSource: String, Codable, Sendable, CaseIterable, Hashable {
    case manualEntry
    case initialSetup
    case serviceRecord
    case odometerReplacement
    case importedBackup

    public var displayName: String {
        switch self {
        case .manualEntry: return "Entered by you"
        case .initialSetup: return "Setup"
        case .serviceRecord: return "From a service record"
        case .odometerReplacement: return "Odometer replacement"
        case .importedBackup: return "Restored from backup"
        }
    }
}

/// A dated odometer reading exactly as it was read off the instrument cluster.
public struct OdometerReading: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var vehicleID: UUID
    public var recordedOn: Date
    public var value: Distance
    public var source: OdometerSource
    public var note: String?

    public init(
        id: UUID = UUID(),
        vehicleID: UUID,
        recordedOn: Date,
        value: Distance,
        source: OdometerSource = .manualEntry,
        note: String? = nil
    ) {
        self.id = id
        self.vehicleID = vehicleID
        self.recordedOn = recordedOn
        self.value = value
        self.source = source
        self.note = note
    }
}

/// One vehicle in the garage.
public struct Vehicle: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var nickname: String?
    public var identity: VehicleIdentity
    public var configuration: VehicleConfiguration
    /// The unit this vehicle's readings are shown in. Stored per vehicle so a
    /// household can keep one car in miles and another in kilometres.
    public var displayUnit: DistanceUnit
    public var acquiredOn: Date?
    /// The date the vehicle entered service, used for age-based manufacturer
    /// milestones. Distinct from `acquiredOn`: buying a 2010 model in 2020 does
    /// not make it a 2020 vehicle. Left `nil` until the owner supplies it, which
    /// keeps age milestones in "Needs setup" rather than guessing.
    public var inServiceOn: Date?
    public var odometerReplacements: [OdometerReplacement]
    public var photoAttachmentID: UUID?
    /// How this vehicle should be pictured. Optional so a store or backup
    /// written before Build 2 decodes unchanged; see `VehicleArtworkPreference`.
    public var artwork: VehicleArtworkPreference?
    public var isDemo: Bool
    public var createdAt: Date
    public var sortIndex: Int

    public init(
        id: UUID = UUID(),
        nickname: String? = nil,
        identity: VehicleIdentity,
        configuration: VehicleConfiguration = VehicleConfiguration(),
        displayUnit: DistanceUnit = .miles,
        acquiredOn: Date? = nil,
        inServiceOn: Date? = nil,
        odometerReplacements: [OdometerReplacement] = [],
        photoAttachmentID: UUID? = nil,
        artwork: VehicleArtworkPreference? = nil,
        isDemo: Bool = false,
        createdAt: Date = Date(),
        sortIndex: Int = 0
    ) {
        self.id = id
        self.nickname = nickname
        self.identity = identity
        self.configuration = configuration
        self.displayUnit = displayUnit
        self.acquiredOn = acquiredOn
        self.inServiceOn = inServiceOn
        self.odometerReplacements = odometerReplacements
        self.photoAttachmentID = photoAttachmentID
        self.artwork = artwork
        self.isDemo = isDemo
        self.createdAt = createdAt
        self.sortIndex = sortIndex
    }

    public var displayName: String {
        if let nickname, !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nickname
        }
        return identity.displayName
    }
}
