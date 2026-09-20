import Foundation

public enum VolumeUnit: String, Codable, Sendable, CaseIterable, Hashable {
    case liters
    case usQuarts

    public var abbreviation: String {
        switch self {
        case .liters: return "L"
        case .usQuarts: return "qt"
        }
    }
}

public enum PressureUnit: String, Codable, Sendable, CaseIterable, Hashable {
    case psi
    case kilopascals
    case bar

    public var abbreviation: String {
        switch self {
        case .psi: return "psi"
        case .kilopascals: return "kPa"
        case .bar: return "bar"
        }
    }
}

public enum TorqueUnit: String, Codable, Sendable, CaseIterable, Hashable {
    case poundFeet
    case newtonMeters

    public var abbreviation: String {
        switch self {
        case .poundFeet: return "lb-ft"
        case .newtonMeters: return "N·m"
        }
    }
}

public enum SmallLengthUnit: String, Codable, Sendable, CaseIterable, Hashable {
    case millimeters
    case inches

    public var abbreviation: String {
        switch self {
        case .millimeters: return "mm"
        case .inches: return "in"
        }
    }
}

/// A specification value together with the unit it was published in.
///
/// Values keep their source unit. Odomind shows "4.7 L" when the manual says
/// 4.7 L and "5 qt" when the manual says 5 qt, rather than converting and
/// implying a precision the source never claimed.
public enum SpecificationValue: Hashable, Sendable {
    case text(String)
    case volume(amount: Double, unit: VolumeUnit)
    case pressure(amount: Double, unit: PressureUnit)
    case torque(amount: Double, unit: TorqueUnit)
    case length(amount: Double, unit: SmallLengthUnit)

    public var displayString: String {
        switch self {
        case .text(let value):
            return value
        case .volume(let amount, let unit):
            return "\(SpecificationValue.format(amount)) \(unit.abbreviation)"
        case .pressure(let amount, let unit):
            return "\(SpecificationValue.format(amount)) \(unit.abbreviation)"
        case .torque(let amount, let unit):
            return "\(SpecificationValue.format(amount)) \(unit.abbreviation)"
        case .length(let amount, let unit):
            return "\(SpecificationValue.format(amount)) \(unit.abbreviation)"
        }
    }

    public static func format(_ amount: Double) -> String {
        if amount == amount.rounded() && abs(amount) < 1e9 {
            return String(Int(amount))
        }
        return String(format: "%.1f", amount)
    }
}

// The catalog is a published, documented file format, so `SpecificationValue`
// encodes through an explicit `kind` discriminator rather than relying on the
// compiler's synthesised shape for enums with associated values.
extension SpecificationValue: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case value
        case amount
        case unit
    }

    private enum Kind: String, Codable {
        case text
        case volume
        case pressure
        case torque
        case length
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .text:
            self = .text(try container.decode(String.self, forKey: .value))
        case .volume:
            self = .volume(
                amount: try container.decode(Double.self, forKey: .amount),
                unit: try container.decode(VolumeUnit.self, forKey: .unit)
            )
        case .pressure:
            self = .pressure(
                amount: try container.decode(Double.self, forKey: .amount),
                unit: try container.decode(PressureUnit.self, forKey: .unit)
            )
        case .torque:
            self = .torque(
                amount: try container.decode(Double.self, forKey: .amount),
                unit: try container.decode(TorqueUnit.self, forKey: .unit)
            )
        case .length:
            self = .length(
                amount: try container.decode(Double.self, forKey: .amount),
                unit: try container.decode(SmallLengthUnit.self, forKey: .unit)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let value):
            try container.encode(Kind.text, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .volume(let amount, let unit):
            try container.encode(Kind.volume, forKey: .kind)
            try container.encode(amount, forKey: .amount)
            try container.encode(unit, forKey: .unit)
        case .pressure(let amount, let unit):
            try container.encode(Kind.pressure, forKey: .kind)
            try container.encode(amount, forKey: .amount)
            try container.encode(unit, forKey: .unit)
        case .torque(let amount, let unit):
            try container.encode(Kind.torque, forKey: .kind)
            try container.encode(amount, forKey: .amount)
            try container.encode(unit, forKey: .unit)
        case .length(let amount, let unit):
            try container.encode(Kind.length, forKey: .kind)
            try container.encode(amount, forKey: .amount)
            try container.encode(unit, forKey: .unit)
        }
    }
}

/// The kinds of specification Odomind can store.
///
/// Wheel size is separate from tyre size on purpose: they are different
/// measurements and owners routinely need the wheel size on its own.
public enum SpecificationKind: String, Codable, Sendable, CaseIterable, Hashable {
    case engineOilViscosity
    case engineOilCapacityWithFilter
    case engineOilStandard
    case engineOilFilterPartNumber
    case tireSizeFront
    case tireSizeRear
    case wheelSizeFront
    case wheelSizeRear
    case coldTirePressureFront
    case coldTirePressureRear
    case spareTireSize
    case spareTirePressure
    case lugNutTorque
    case coolantType
    case coolantCapacity
    case brakeFluidType
    case transmissionFluidType
    case transmissionFluidCapacity
    case transferCaseFluidType
    case frontDifferentialFluidType
    case rearDifferentialFluidType
    case powerSteeringFluidType
    case batteryGroupSize
    case sparkPlugType
    case sparkPlugGap
    case wiperBladeSizeDriver
    case wiperBladeSizePassenger
    case wiperBladeSizeRear
    case cabinAirFilterPartNumber
    case engineAirFilterPartNumber
    case fuelGrade
    case fuelTankCapacity

    public var displayName: String {
        switch self {
        case .engineOilViscosity: return "Engine oil viscosity"
        case .engineOilCapacityWithFilter: return "Engine oil capacity (with filter)"
        case .engineOilStandard: return "Engine oil specification"
        case .engineOilFilterPartNumber: return "Oil filter"
        case .tireSizeFront: return "Tire size (front)"
        case .tireSizeRear: return "Tire size (rear)"
        case .wheelSizeFront: return "Wheel size (front)"
        case .wheelSizeRear: return "Wheel size (rear)"
        case .coldTirePressureFront: return "Cold tire pressure (front)"
        case .coldTirePressureRear: return "Cold tire pressure (rear)"
        case .spareTireSize: return "Spare tire size"
        case .spareTirePressure: return "Spare tire pressure"
        case .lugNutTorque: return "Lug nut torque"
        case .coolantType: return "Coolant"
        case .coolantCapacity: return "Coolant capacity"
        case .brakeFluidType: return "Brake fluid"
        case .transmissionFluidType: return "Transmission fluid"
        case .transmissionFluidCapacity: return "Transmission fluid capacity"
        case .transferCaseFluidType: return "Transfer case fluid"
        case .frontDifferentialFluidType: return "Front differential fluid"
        case .rearDifferentialFluidType: return "Rear differential fluid"
        case .powerSteeringFluidType: return "Power steering fluid"
        case .batteryGroupSize: return "Battery group size"
        case .sparkPlugType: return "Spark plugs"
        case .sparkPlugGap: return "Spark plug gap"
        case .wiperBladeSizeDriver: return "Wiper blade (driver)"
        case .wiperBladeSizePassenger: return "Wiper blade (passenger)"
        case .wiperBladeSizeRear: return "Wiper blade (rear)"
        case .cabinAirFilterPartNumber: return "Cabin air filter"
        case .engineAirFilterPartNumber: return "Engine air filter"
        case .fuelGrade: return "Fuel grade"
        case .fuelTankCapacity: return "Fuel tank capacity"
        }
    }

    public var group: SpecificationGroup {
        switch self {
        case .engineOilViscosity, .engineOilCapacityWithFilter, .engineOilStandard, .engineOilFilterPartNumber:
            return .engineOil
        case .tireSizeFront, .tireSizeRear, .wheelSizeFront, .wheelSizeRear,
             .coldTirePressureFront, .coldTirePressureRear, .spareTireSize, .spareTirePressure, .lugNutTorque:
            return .tiresAndWheels
        case .coolantType, .coolantCapacity, .brakeFluidType, .transmissionFluidType,
             .transmissionFluidCapacity, .transferCaseFluidType, .frontDifferentialFluidType,
             .rearDifferentialFluidType, .powerSteeringFluidType:
            return .fluids
        case .batteryGroupSize, .sparkPlugType, .sparkPlugGap, .cabinAirFilterPartNumber, .engineAirFilterPartNumber:
            return .parts
        case .wiperBladeSizeDriver, .wiperBladeSizePassenger, .wiperBladeSizeRear:
            return .visibility
        case .fuelGrade, .fuelTankCapacity:
            return .fuel
        }
    }

    /// Whether a pressure specification must never be inferred from a tyre
    /// sidewall. Sidewall pressure is a maximum, not an operating pressure, and
    /// Odomind refuses to derive one from the other.
    public var isVehiclePlacardOnly: Bool {
        switch self {
        case .coldTirePressureFront, .coldTirePressureRear, .spareTirePressure:
            return true
        default:
            return false
        }
    }
}

public enum SpecificationGroup: String, Codable, Sendable, CaseIterable, Hashable {
    case engineOil
    case tiresAndWheels
    case fluids
    case parts
    case visibility
    case fuel

    public var displayName: String {
        switch self {
        case .engineOil: return "Engine oil"
        case .tiresAndWheels: return "Tires and wheels"
        case .fluids: return "Fluids"
        case .parts: return "Parts"
        case .visibility: return "Visibility"
        case .fuel: return "Fuel"
        }
    }

    public var symbolName: String {
        switch self {
        case .engineOil: return "drop.fill"
        case .tiresAndWheels: return "circle.circle"
        case .fluids: return "testtube.2"
        case .parts: return "wrench.and.screwdriver"
        case .visibility: return "windshield.front.and.wiper"
        case .fuel: return "fuelpump"
        }
    }
}

/// Whether a value describes how the vehicle left the factory, what is fitted
/// now, or what the owner prefers.
public enum EquipmentBasis: String, Codable, Sendable, CaseIterable, Hashable {
    case factory
    case currentlyInstalled
    case ownerPreference

    public var displayName: String {
        switch self {
        case .factory: return "Factory"
        case .currentlyInstalled: return "Installed now"
        case .ownerPreference: return "Your preference"
        }
    }
}

/// One specification value with everything needed to judge whether to trust it.
public struct Specification: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var kind: SpecificationKind
    public var value: SpecificationValue
    public var provenance: Provenance
    public var basis: EquipmentBasis
    /// Free text such as "with filter change" or "Sport trim, 16-inch wheels".
    public var appliesToNote: String?
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        kind: SpecificationKind,
        value: SpecificationValue,
        provenance: Provenance,
        basis: EquipmentBasis = .factory,
        appliesToNote: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.value = value
        self.provenance = provenance
        self.basis = basis
        self.appliesToNote = appliesToNote
        self.updatedAt = updatedAt
    }

    public var isVerified: Bool { provenance.isVerified }
}
