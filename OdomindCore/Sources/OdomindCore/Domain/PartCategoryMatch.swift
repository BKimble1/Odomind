import Foundation

/// What a parts search is actually about, and which of the vehicle's
/// specifications matter to it.
///
/// The Build 2 defect this replaces: the Parts screen, opened without a job,
/// showed a fixed four — oil viscosity, oil capacity, tyre size and battery
/// group size — whatever had been typed. Searching "cabin air filter" put a
/// tyre size and a battery group in front of the owner and left out the one
/// number that identifies a cabin filter. The brief names it: "A filter lookup
/// should not default to unrelated battery/tire specifications."
///
/// Pure text work, so it is testable without a screen. Deliberately
/// conservative: a query it does not recognise gets the general set rather
/// than a wrong guess, and the general set is stated once here instead of
/// being spelled out at each call site.
public enum PartCategoryMatch {

    /// A part category Odomind can recognise from what somebody typed.
    public enum Category: String, Sendable, CaseIterable, Hashable {
        case engineOil
        case oilFilter
        case engineAirFilter
        case cabinAirFilter
        case tires
        case battery
        case brakes
        case coolant
        case transmissionFluid
        case sparkPlugs
        case wiperBlades
        case differentialFluid
        case transferCaseFluid
        case powerSteeringFluid
        case fuel

        /// The specifications that identify a part in this category.
        public var specifications: [SpecificationKind] {
            switch self {
            case .engineOil:
                return [.engineOilViscosity, .engineOilCapacityWithFilter, .engineOilStandard]
            case .oilFilter:
                return [.engineOilFilterPartNumber, .engineOilViscosity, .engineOilCapacityWithFilter]
            case .engineAirFilter:
                return [.engineAirFilterPartNumber]
            case .cabinAirFilter:
                return [.cabinAirFilterPartNumber]
            case .tires:
                return [.tireSizeFront, .tireSizeRear, .coldTirePressureFront, .coldTirePressureRear, .lugNutTorque]
            case .battery:
                return [.batteryGroupSize]
            case .brakes:
                return [.brakeFluidType, .lugNutTorque]
            case .coolant:
                return [.coolantType, .coolantCapacity]
            case .transmissionFluid:
                return [.transmissionFluidType, .transmissionFluidCapacity]
            case .sparkPlugs:
                return [.sparkPlugType, .sparkPlugGap]
            case .wiperBlades:
                return [.wiperBladeSizeDriver, .wiperBladeSizePassenger, .wiperBladeSizeRear]
            case .differentialFluid:
                return [.frontDifferentialFluidType, .rearDifferentialFluidType]
            case .transferCaseFluid:
                return [.transferCaseFluidType]
            case .powerSteeringFluid:
                return [.powerSteeringFluidType]
            case .fuel:
                return [.fuelGrade, .fuelTankCapacity]
            }
        }

        /// Words that mean this category. Ordered longest-first where one
        /// contains another, because "cabin air filter" must not be read as
        /// "air filter" and "oil filter" must not be read as "oil".
        var phrases: [String] {
            switch self {
            case .cabinAirFilter: return ["cabin air filter", "cabin filter", "pollen filter"]
            case .engineAirFilter: return ["engine air filter", "air filter", "air cleaner"]
            case .oilFilter: return ["oil filter", "oil and filter", "filter change"]
            case .engineOil: return ["engine oil", "motor oil", "oil change", "oil"]
            case .tires: return ["tire", "tyre", "wheel", "rotation", "alignment"]
            case .battery: return ["battery", "group size"]
            case .brakes: return ["brake", "pad", "rotor", "caliper"]
            case .coolant: return ["coolant", "antifreeze", "radiator"]
            case .transmissionFluid: return ["transmission fluid", "transmission", "gearbox", "atf"]
            case .sparkPlugs: return ["spark plug", "sparkplug", "ignition"]
            case .wiperBlades: return ["wiper", "windshield blade", "windscreen blade"]
            case .differentialFluid: return ["differential", "diff fluid", "gear oil"]
            case .transferCaseFluid: return ["transfer case"]
            case .powerSteeringFluid: return ["power steering"]
            case .fuel: return ["fuel", "petrol", "gasoline", "octane"]
            }
        }
    }

    /// The order phrases are tested in: most words first, then longest, so a
    /// specific category always beats a general one whose words it contains.
    /// "cabin air filter" is tried before "air filter", and "oil filter"
    /// before "oil".
    private static var orderedPhrases: [(tokens: [String], category: Category)] {
        Category.allCases
            .flatMap { category in
                category.phrases.map { (tokens: stemmedTokens($0), category: category) }
            }
            .filter { !$0.tokens.isEmpty }
            .sorted { left, right in
                if left.tokens.count != right.tokens.count { return left.tokens.count > right.tokens.count }
                return left.tokens.joined().count > right.tokens.joined().count
            }
    }

    /// Words, with a plural "s" taken off anything long enough for that to be
    /// a plural rather than the word.
    ///
    /// People type "spark plugs", "brake pads" and "wiper blades"; the phrase
    /// list is written in the singular. Four characters is the floor so "gas"
    /// does not become "ga".
    static func stemmedTokens(_ text: String) -> [String] {
        VehicleTextMatch.tokens(text).map { token in
            guard token.count >= 4, token.hasSuffix("s") else { return token }
            return String(token.dropLast())
        }
    }

    /// The category a query names, or `nil`.
    ///
    /// - Parameters:
    ///   - query: what the owner typed, or a job's title.
    ///   - categoryHint: the job's own category name, used only when the text
    ///     names nothing.
    public static func category(for query: String, categoryHint: String? = nil) -> Category? {
        if let found = category(inText: query) { return found }
        if let categoryHint { return category(inText: categoryHint) }
        return nil
    }

    private static func category(inText text: String) -> Category? {
        let words = stemmedTokens(text)
        guard !words.isEmpty else { return nil }
        for entry in orderedPhrases where contains(words, entry.tokens) {
            return entry.category
        }
        return nil
    }

    /// Whether `phrase` appears in `words` as whole words, in order.
    ///
    /// Whole words, not substrings: "oil" inside "coil" would turn an
    /// ignition coil into an oil change.
    private static func contains(_ words: [String], _ phrase: [String]) -> Bool {
        guard !phrase.isEmpty, words.count >= phrase.count else { return false }
        for start in 0...(words.count - phrase.count) {
            if Array(words[start..<(start + phrase.count)]) == phrase { return true }
        }
        return false
    }

    /// What to show when nothing in the query names a category.
    ///
    /// The four things most owners look up, and an honest general answer
    /// rather than a wrong specific one.
    public static let generalSpecifications: [SpecificationKind] = [
        .engineOilViscosity,
        .engineOilCapacityWithFilter,
        .tireSizeFront,
        .batteryGroupSize,
    ]

    /// The specifications a parts search should show.
    public static func specifications(for query: String, categoryHint: String? = nil) -> [SpecificationKind] {
        category(for: query, categoryHint: categoryHint)?.specifications ?? generalSpecifications
    }
}
