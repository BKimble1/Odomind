import Foundation

/// Where a piece of vehicle information came from.
///
/// The distinction between `manufacturerSourced` and `referenceSourced` matters:
/// a VIN decoder tells you what a vehicle *is*, not what fluid it takes. Odomind
/// never labels decoder output, or anything it inferred, as verified.
public enum DataOrigin: String, Codable, Sendable, CaseIterable, Hashable {
    /// Transcribed from manufacturer documentation (owner's manual, service
    /// manual, tyre placard) by a person who recorded the source and the date.
    case manufacturerSourced

    /// Reported by an identification or reference source — a VIN decoder such
    /// as NHTSA vPIC, or a maintainer's engine-family reference note. Useful,
    /// and often correct, but not checked against the manufacturer's own
    /// documentation, so it is never shown as verified.
    case referenceSourced

    /// A general, vehicle-independent guideline. Shown as guidance, never as
    /// "your manufacturer says".
    case generalTemplate

    /// Entered by the owner, typically from their own manual or door placard.
    case userEntered

    public var shortLabel: String {
        switch self {
        case .manufacturerSourced: return "Manufacturer"
        case .referenceSourced: return "Reference"
        case .generalTemplate: return "General guidance"
        case .userEntered: return "You"
        }
    }
}

/// Citation details for a value.
public struct SourceAttribution: Codable, Hashable, Sendable {
    /// Human-readable source, e.g. "2010 Jeep Wrangler Owner's Manual".
    public var sourceName: String
    /// A URL, ISBN, document number or page reference. Required before a value
    /// can be considered verified.
    public var sourceReference: String?
    /// Version of the dataset this value shipped in.
    public var datasetVersion: String?
    /// The date a person checked this value against `sourceName`.
    public var reviewedOn: Date?
    /// Who performed that review.
    public var reviewedBy: String?
    public var note: String?

    public init(
        sourceName: String,
        sourceReference: String? = nil,
        datasetVersion: String? = nil,
        reviewedOn: Date? = nil,
        reviewedBy: String? = nil,
        note: String? = nil
    ) {
        self.sourceName = sourceName
        self.sourceReference = sourceReference
        self.datasetVersion = datasetVersion
        self.reviewedOn = reviewedOn
        self.reviewedBy = reviewedBy
        self.note = note
    }
}

/// Which vehicle configuration a value is valid for.
///
/// A value that only applies to the 3.8 L engine must not leak onto a different
/// engine. An empty scope means "applies to every configuration of this model",
/// which the catalog validator only permits for general templates.
public struct ConfigurationScope: Codable, Hashable, Sendable {
    public var modelYears: [Int]?
    public var engineCodes: [String]?
    public var engineDisplacementLiters: [Double]?
    public var transmissions: [TransmissionKind]?
    public var drivetrains: [DrivetrainLayout]?
    public var markets: [Market]?
    public var trims: [String]?
    public var usageProfiles: [UsageProfile]?

    public init(
        modelYears: [Int]? = nil,
        engineCodes: [String]? = nil,
        engineDisplacementLiters: [Double]? = nil,
        transmissions: [TransmissionKind]? = nil,
        drivetrains: [DrivetrainLayout]? = nil,
        markets: [Market]? = nil,
        trims: [String]? = nil,
        usageProfiles: [UsageProfile]? = nil
    ) {
        self.modelYears = modelYears
        self.engineCodes = engineCodes
        self.engineDisplacementLiters = engineDisplacementLiters
        self.transmissions = transmissions
        self.drivetrains = drivetrains
        self.markets = markets
        self.trims = trims
        self.usageProfiles = usageProfiles
    }

    public static let any = ConfigurationScope()

    public var isUnconstrained: Bool {
        modelYears == nil && engineCodes == nil && engineDisplacementLiters == nil
            && transmissions == nil && drivetrains == nil && markets == nil
            && trims == nil && usageProfiles == nil
    }
}

/// Provenance attached to a specification value or a schedule rule.
public struct Provenance: Codable, Hashable, Sendable {
    public var origin: DataOrigin
    public var attribution: SourceAttribution?
    public var scope: ConfigurationScope

    public init(origin: DataOrigin, attribution: SourceAttribution? = nil, scope: ConfigurationScope = .any) {
        self.origin = origin
        self.attribution = attribution
        self.scope = scope
    }

    /// True only when a person checked this value against a citable manufacturer
    /// source and recorded when they did it.
    ///
    /// This is the single definition of "verified" in Odomind. Nothing else in
    /// the app is allowed to display a verified badge, and the catalog validator
    /// rejects any entry that claims `manufacturerSourced` without satisfying it.
    public var isVerified: Bool {
        guard origin == .manufacturerSourced, let attribution else { return false }
        guard let reference = attribution.sourceReference, !reference.isEmpty else { return false }
        return attribution.reviewedOn != nil
    }

    public static let userEntered = Provenance(origin: .userEntered)

    public static func template(_ sourceName: String, datasetVersion: String? = nil) -> Provenance {
        Provenance(
            origin: .generalTemplate,
            attribution: SourceAttribution(sourceName: sourceName, datasetVersion: datasetVersion)
        )
    }
}
