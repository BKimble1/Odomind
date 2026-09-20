import Foundation

public enum Market: String, Codable, Sendable, CaseIterable, Hashable {
    case unitedStates
    case canada
    case other
    case unspecified

    public var displayName: String {
        switch self {
        case .unitedStates: return "United States"
        case .canada: return "Canada"
        case .other: return "Other market"
        case .unspecified: return "Not set"
        }
    }
}

/// How hard the vehicle is used.
///
/// Manufacturers publish separate "severe" schedules, but the criteria differ by
/// make, so Odomind leaves this `unspecified` until the owner chooses and only
/// offers the choice where the catalog actually carries both schedules.
public enum UsageProfile: String, Codable, Sendable, CaseIterable, Hashable {
    case unspecified
    case normal
    case severe

    public var displayName: String {
        switch self {
        case .unspecified: return "Not set"
        case .normal: return "Normal use"
        case .severe: return "Severe use"
        }
    }
}

public enum PowertrainKind: String, Codable, Sendable, CaseIterable, Hashable {
    case gasoline
    case diesel
    case hybrid
    case pluginHybrid
    case batteryElectric
    case hydrogenFuelCell
    case other
    case unknown

    /// True when the powertrain has a combustion engine that takes engine oil.
    ///
    /// Drives task applicability: a battery-electric vehicle never gets an
    /// engine-oil task, and a hybrid does.
    public var hasCombustionEngine: Bool {
        switch self {
        case .gasoline, .diesel, .hybrid, .pluginHybrid, .other:
            return true
        case .batteryElectric, .hydrogenFuelCell:
            return false
        case .unknown:
            return true
        }
    }

    public var isDefinite: Bool { self != .unknown }

    public var displayName: String {
        switch self {
        case .gasoline: return "Gasoline"
        case .diesel: return "Diesel"
        case .hybrid: return "Hybrid"
        case .pluginHybrid: return "Plug-in hybrid"
        case .batteryElectric: return "Battery electric"
        case .hydrogenFuelCell: return "Hydrogen fuel cell"
        case .other: return "Other"
        case .unknown: return "Not confirmed"
        }
    }
}

public enum TransmissionKind: String, Codable, Sendable, CaseIterable, Hashable {
    case manual
    case automatic
    case continuouslyVariable
    case dualClutch
    case singleSpeedReduction
    case unknown

    public var displayName: String {
        switch self {
        case .manual: return "Manual"
        case .automatic: return "Automatic"
        case .continuouslyVariable: return "CVT"
        case .dualClutch: return "Dual-clutch"
        case .singleSpeedReduction: return "Single-speed"
        case .unknown: return "Not confirmed"
        }
    }
}

public enum DrivetrainLayout: String, Codable, Sendable, CaseIterable, Hashable {
    case frontWheelDrive
    case rearWheelDrive
    case allWheelDrive
    case fourWheelDrivePartTime
    case fourWheelDriveFullTime
    case unknown

    /// Whether this layout normally includes a transfer case.
    ///
    /// `nil` where it genuinely depends on the vehicle, which keeps the transfer
    /// case task out of the plan until the owner confirms.
    public var impliesTransferCase: Bool? {
        switch self {
        case .frontWheelDrive, .rearWheelDrive: return false
        case .fourWheelDrivePartTime, .fourWheelDriveFullTime: return true
        case .allWheelDrive: return nil
        case .unknown: return nil
        }
    }

    public var displayName: String {
        switch self {
        case .frontWheelDrive: return "Front-wheel drive"
        case .rearWheelDrive: return "Rear-wheel drive"
        case .allWheelDrive: return "All-wheel drive"
        case .fourWheelDrivePartTime: return "Four-wheel drive (part-time)"
        case .fourWheelDriveFullTime: return "Four-wheel drive (full-time)"
        case .unknown: return "Not confirmed"
        }
    }
}

/// How the camshafts are driven, which decides whether a timing-belt service
/// applies at all. Left `unknown` unless a source says otherwise — assuming
/// every engine has a belt invents an expensive service that may not exist.
public enum CamshaftDrive: String, Codable, Sendable, CaseIterable, Hashable {
    case timingBelt
    case timingChain
    case gearDriven
    case notApplicable
    case unknown

    public var displayName: String {
        switch self {
        case .timingBelt: return "Timing belt"
        case .timingChain: return "Timing chain"
        case .gearDriven: return "Gear-driven"
        case .notApplicable: return "Not applicable"
        case .unknown: return "Not confirmed"
        }
    }
}

/// Tri-state answer used for equipment that may or may not be fitted.
///
/// `unknown` is a first-class answer: it keeps a task out of the active plan and
/// surfaces a "confirm this" prompt instead of guessing either way.
public enum Fitment: String, Codable, Sendable, CaseIterable, Hashable {
    case fitted
    case notFitted
    case unknown

    public init(_ value: Bool?) {
        switch value {
        case .some(true): self = .fitted
        case .some(false): self = .notFitted
        case .none: self = .unknown
        }
    }

    public var displayName: String {
        switch self {
        case .fitted: return "Yes"
        case .notFitted: return "No"
        case .unknown: return "Not confirmed"
        }
    }
}

/// The confirmed mechanical configuration of one vehicle.
///
/// Everything here is either confirmed by the owner or reported by a decoder and
/// then confirmed. Task applicability reads from this, so an unconfirmed field
/// suppresses the dependent tasks rather than inventing them.
public struct VehicleConfiguration: Codable, Hashable, Sendable {
    public var powertrain: PowertrainKind
    public var engineDisplacementLiters: Double?
    public var engineCylinders: Int?
    /// Manufacturer engine code or family, e.g. "EGH".
    public var engineCode: String?
    public var transmission: TransmissionKind
    public var transmissionSpeeds: Int?
    public var drivetrain: DrivetrainLayout
    public var camshaftDrive: CamshaftDrive
    public var transferCase: Fitment
    public var frontDifferential: Fitment
    public var rearDifferential: Fitment
    public var market: Market
    public var usageProfile: UsageProfile
    /// Fields the owner has explicitly confirmed, by coding key.
    public var confirmedFields: Set<String>

    public init(
        powertrain: PowertrainKind = .unknown,
        engineDisplacementLiters: Double? = nil,
        engineCylinders: Int? = nil,
        engineCode: String? = nil,
        transmission: TransmissionKind = .unknown,
        transmissionSpeeds: Int? = nil,
        drivetrain: DrivetrainLayout = .unknown,
        camshaftDrive: CamshaftDrive = .unknown,
        transferCase: Fitment = .unknown,
        frontDifferential: Fitment = .unknown,
        rearDifferential: Fitment = .unknown,
        market: Market = .unspecified,
        usageProfile: UsageProfile = .unspecified,
        confirmedFields: Set<String> = []
    ) {
        self.powertrain = powertrain
        self.engineDisplacementLiters = engineDisplacementLiters
        self.engineCylinders = engineCylinders
        self.engineCode = engineCode
        self.transmission = transmission
        self.transmissionSpeeds = transmissionSpeeds
        self.drivetrain = drivetrain
        self.camshaftDrive = camshaftDrive
        self.transferCase = transferCase
        self.frontDifferential = frontDifferential
        self.rearDifferential = rearDifferential
        self.market = market
        self.usageProfile = usageProfile
        self.confirmedFields = confirmedFields
    }

    /// Configuration questions Odomind still needs answered before it can decide
    /// which tasks apply. Drives the "Needs setup" group and the confirm step.
    public var openQuestions: [ConfigurationQuestion] {
        var questions: [ConfigurationQuestion] = []
        if powertrain == .unknown { questions.append(.powertrain) }
        if transmission == .unknown { questions.append(.transmission) }
        if drivetrain == .unknown { questions.append(.drivetrain) }
        if drivetrain.impliesTransferCase == nil, transferCase == .unknown {
            questions.append(.transferCase)
        }
        if powertrain.hasCombustionEngine, camshaftDrive == .unknown {
            questions.append(.camshaftDrive)
        }
        return questions
    }

    /// Resolves transfer-case fitment, preferring an explicit answer and falling
    /// back to what the drivetrain layout implies.
    public var effectiveTransferCase: Fitment {
        if transferCase != .unknown { return transferCase }
        return Fitment(drivetrain.impliesTransferCase)
    }

    /// Whether a *separately serviceable* front differential is fitted.
    ///
    /// A front-wheel-drive car has a differential, but it lives inside the
    /// transaxle and shares its fluid, so there is no separate front-diff
    /// service. Treating it as fitted would invent a job that does not exist.
    public var effectiveFrontDifferential: Fitment {
        if frontDifferential != .unknown { return frontDifferential }
        switch drivetrain {
        case .frontWheelDrive, .rearWheelDrive:
            return .notFitted
        case .fourWheelDrivePartTime, .fourWheelDriveFullTime:
            return .fitted
        case .allWheelDrive, .unknown:
            return .unknown
        }
    }

    /// Whether a separately serviceable rear differential is fitted.
    public var effectiveRearDifferential: Fitment {
        if rearDifferential != .unknown { return rearDifferential }
        switch drivetrain {
        case .rearWheelDrive, .fourWheelDrivePartTime, .fourWheelDriveFullTime:
            return .fitted
        case .frontWheelDrive:
            return .notFitted
        case .allWheelDrive, .unknown:
            return .unknown
        }
    }
}

public enum ConfigurationQuestion: String, Codable, Sendable, CaseIterable, Hashable {
    case powertrain
    case transmission
    case drivetrain
    case transferCase
    case camshaftDrive

    public var prompt: String {
        switch self {
        case .powertrain: return "What does this vehicle run on?"
        case .transmission: return "Which transmission does it have?"
        case .drivetrain: return "Which wheels does it drive?"
        case .transferCase: return "Does it have a transfer case?"
        case .camshaftDrive: return "Does the engine use a timing belt or a timing chain?"
        }
    }

    /// Why Odomind is asking, so the question does not feel arbitrary.
    public var rationale: String {
        switch self {
        case .powertrain:
            return "Electric vehicles do not take engine oil, so this decides which tasks apply."
        case .transmission:
            return "Manual and automatic transmissions take different fluid and different service."
        case .drivetrain:
            return "Drivetrain decides whether differential and transfer-case service apply."
        case .transferCase:
            return "All-wheel-drive vehicles vary, so Odomind will not assume one is fitted."
        case .camshaftDrive:
            return "Timing-belt replacement only applies to belt-driven engines. Odomind will not schedule it otherwise."
        }
    }
}
