import Foundation

/// The shape of a vehicle's body, at the resolution artwork actually needs.
///
/// Not a taxonomy of the market — a list of silhouettes Odomind can draw well.
/// `offRoadSUV` is separate from `suv` because a body-on-frame off-roader and a
/// unibody crossover look nothing alike, and putting a rounded crossover under
/// a Wrangler is exactly the "generic sedan" failure the artwork exists to
/// avoid.
public enum VehicleBodyStyle: String, Codable, Sendable, CaseIterable, Hashable {
    case sedan
    case hatchback
    case coupe
    case wagon
    case crossover
    case suv
    case offRoadSUV
    case pickup
    case van

    public var displayName: String {
        switch self {
        case .sedan: return "Sedan"
        case .hatchback: return "Hatchback"
        case .coupe: return "Coupe"
        case .wagon: return "Wagon"
        case .crossover: return "Crossover"
        case .suv: return "SUV"
        case .offRoadSUV: return "Off-road SUV"
        case .pickup: return "Pickup"
        case .van: return "Van or minivan"
        }
    }

    /// Best guess from what identification actually gives us.
    ///
    /// vPIC's `BodyClass` is free text with a handful of recurring shapes, and
    /// the model name carries the rest. Everything here is a *presentation*
    /// decision: getting it wrong draws a slightly wrong picture, never a wrong
    /// service interval, which is why it is allowed to guess at all. It returns
    /// `nil` rather than defaulting to a sedan when nothing matches, so the
    /// caller can decide what an unknown shape should look like.
    public static func classify(
        identity: VehicleIdentity,
        configuration: VehicleConfiguration = VehicleConfiguration()
    ) -> VehicleBodyStyle? {
        let body = (identity.bodyClass ?? "").lowercased()
        let model = identity.model.lowercased()
        let series = (identity.series ?? "").lowercased()
        let trim = (identity.trim ?? "").lowercased()
        let haystack = [model, series, trim].joined(separator: " ")

        // Model names first: a name is a stronger signal than vPIC's very
        // broad "Sport Utility Vehicle (SUV)/Multi-Purpose Vehicle (MPV)",
        // which covers everything from a Wrangler to a small crossover.
        let offRoadNames = [
            "wrangler", "bronco", "defender", "4runner", "land cruiser",
            "g-class", "g-wagon", "gladiator", "xterra", "fj cruiser"
        ]
        if offRoadNames.contains(where: { haystack.contains($0) }) {
            // The Gladiator is a pickup wearing a Wrangler's face.
            return haystack.contains("gladiator") ? .pickup : .offRoadSUV
        }

        if body.contains("pickup") || body.contains("truck") { return .pickup }
        if body.contains("van") || body.contains("minivan") { return .van }
        if body.contains("wagon") { return .wagon }
        if body.contains("hatchback") || body.contains("liftback") { return .hatchback }
        if body.contains("coupe") { return .coupe }
        if body.contains("convertible") || body.contains("roadster") { return .coupe }
        if body.contains("sedan") || body.contains("saloon") { return .sedan }
        if body.contains("crossover") { return .crossover }
        if body.contains("sport utility") || body.contains("suv") || body.contains("mpv") {
            // Four-wheel drive alone does not make something an off-roader, so
            // an unqualified SUV stays an SUV.
            return .suv
        }
        if body.contains("hatch") { return .hatchback }
        return nil
    }
}

/// Whether a vehicle shows the owner's photo or Odomind's illustration.
public enum VehicleArtworkMode: String, Codable, Sendable, CaseIterable, Hashable {
    case illustration
    case photo

    public var displayName: String {
        switch self {
        case .illustration: return "Illustration"
        case .photo: return "Your photo"
        }
    }
}

/// A paint colour the owner can pick for their illustration.
///
/// A fixed, named set rather than a free colour picker: the illustrations are
/// drawn with matched shadow and glass tones per colour, and an arbitrary hue
/// would break that. Stored as an identifier so the palette can be retuned
/// without rewriting anyone's saved choice.
public enum VehiclePaintColor: String, Codable, Sendable, CaseIterable, Hashable {
    case slate
    case black
    case white
    case silver
    case red
    case blue
    case green
    case orange
    case sand

    public var displayName: String {
        switch self {
        case .slate: return "Slate"
        case .black: return "Black"
        case .white: return "White"
        case .silver: return "Silver"
        case .red: return "Red"
        case .blue: return "Blue"
        case .green: return "Green"
        case .orange: return "Orange"
        case .sand: return "Sand"
        }
    }

    public static let `default` = VehiclePaintColor.slate
}

/// How one vehicle should be pictured.
///
/// Optional on `Vehicle` so a store or a backup written before Build 2 decodes
/// without it — Swift's synthesised `Codable` uses `decodeIfPresent` for
/// optional properties, so an archive that has never heard of artwork still
/// reads, and a Build 1 reader ignores the extra key. That is why this did not
/// need a backup format bump.
public struct VehicleArtworkPreference: Codable, Hashable, Sendable {
    public var mode: VehicleArtworkMode
    public var paintColor: VehiclePaintColor
    /// Set when the owner corrects the shape Odomind guessed.
    public var bodyStyleOverride: VehicleBodyStyle?

    public init(
        mode: VehicleArtworkMode = .illustration,
        paintColor: VehiclePaintColor = .default,
        bodyStyleOverride: VehicleBodyStyle? = nil
    ) {
        self.mode = mode
        self.paintColor = paintColor
        self.bodyStyleOverride = bodyStyleOverride
    }

    public static let `default` = VehicleArtworkPreference()
}

/// What a vehicle's picture should actually be, and how exact it is.
///
/// The distinction is the point. A body-style silhouette is not a rendering of
/// the owner's vehicle and must never be presented as one, and neither kind of
/// illustration says anything about what parts fit.
public enum VehicleArtworkResolution: Hashable, Sendable {
    /// The owner's own photo.
    case photo(UUID)
    /// A drawing matched to this model and generation.
    case matchedIllustration(VehicleIllustration)
    /// A drawing of the right *kind* of vehicle, nothing more.
    case bodyStyleIllustration(VehicleBodyStyle)
    /// Nothing is known about the shape. Drawn as a neutral mark, not a guess.
    case unknownShape

    /// One line, shown where the owner might otherwise assume the picture is a
    /// photograph of their car. Deliberately absent from the card itself.
    public var disclosure: String {
        switch self {
        case .photo:
            return "Your photo."
        case .matchedIllustration(let illustration):
            return "Odomind illustration matched to the \(illustration.displayName). An illustration, not a photograph, and not a statement about which parts fit."
        case .bodyStyleIllustration(let style):
            return "A general \(style.displayName.lowercased()) illustration. Odomind does not have a drawing of this exact model, so this shows the body style only."
        case .unknownShape:
            return "Odomind could not work out this vehicle's body style, so it shows a neutral mark rather than guessing."
        }
    }

    public var isExactMatch: Bool {
        if case .matchedIllustration = self { return true }
        return false
    }
}

/// A drawing Odomind has for a specific model and generation.
///
/// The list is short and honest. Adding one means drawing it, not declaring it.
public enum VehicleIllustration: String, Codable, Sendable, CaseIterable, Hashable {
    /// 2007–2018 Wrangler Unlimited (JK), four doors, hard top.
    case jeepWranglerJKUnlimited
    /// 2007–2018 Wrangler (JK), two doors.
    case jeepWranglerJKTwoDoor

    public var displayName: String {
        switch self {
        case .jeepWranglerJKUnlimited: return "Jeep Wrangler Unlimited (JK)"
        case .jeepWranglerJKTwoDoor: return "Jeep Wrangler (JK)"
        }
    }

    /// The silhouette family this drawing belongs to, used for scale and
    /// ground placement so a matched drawing and a fallback sit identically.
    public var bodyStyle: VehicleBodyStyle { .offRoadSUV }

    /// The drawing that matches this vehicle, if Odomind has one.
    ///
    /// Matching is deliberately narrow: model name, year range, and — for the
    /// door count, which is the whole difference between these two — the
    /// `Unlimited` name that Jeep uses for the four-door.
    public static func match(identity: VehicleIdentity) -> VehicleIllustration? {
        let make = identity.make.lowercased()
        let model = identity.model.lowercased()
        guard make.contains("jeep"), model.contains("wrangler") else { return nil }
        guard let year = identity.modelYear, (2007...2018).contains(year) else { return nil }

        let text = [model, identity.series ?? "", identity.trim ?? ""]
            .joined(separator: " ")
            .lowercased()
        // Jeep's own name for the four-door, and the JK's four-door-only
        // export name. Neither appears on a two-door.
        if text.contains("unlimited") || text.contains("jku") {
            return .jeepWranglerJKUnlimited
        }
        return .jeepWranglerJKTwoDoor
    }
}

public enum VehicleArtworkResolver {
    /// Owner's photo, then an exact drawing, then the right body style.
    ///
    /// Photo mode with no photo attached falls through to an illustration
    /// rather than showing an empty frame — the owner may have chosen photo
    /// mode before taking one.
    public static func resolve(
        vehicle: Vehicle,
        hasPhoto: Bool
    ) -> VehicleArtworkResolution {
        let preference = vehicle.artwork ?? .default

        if preference.mode == .photo, hasPhoto, let id = vehicle.photoAttachmentID {
            return .photo(id)
        }
        if let override = preference.bodyStyleOverride {
            return .bodyStyleIllustration(override)
        }
        if let illustration = VehicleIllustration.match(identity: vehicle.identity) {
            return .matchedIllustration(illustration)
        }
        if let style = VehicleBodyStyle.classify(
            identity: vehicle.identity,
            configuration: vehicle.configuration
        ) {
            return .bodyStyleIllustration(style)
        }
        return .unknownShape
    }
}
