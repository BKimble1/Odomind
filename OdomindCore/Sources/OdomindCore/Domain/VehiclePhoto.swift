import Foundation

/// How closely a photograph actually corresponds to the owner's vehicle.
///
/// This exists so the app can never imply more than it knows. A photograph of
/// a two-door Wrangler is not a photograph of a four-door one, and a picture
/// of the right generation in the wrong paint is not a picture of *your* car.
/// Every level below carries its own sentence, and the app shows it.
public enum PhotoMatchLevel: String, Codable, Sendable, CaseIterable, Hashable, Comparable {
    /// The owner's own picture. Nothing beats this and nothing replaces it.
    case ownerPhoto
    /// Year, make, model and body style all line up.
    case exactModelYear
    /// The right model and generation, a different year within it.
    case generation
    /// The right kind of vehicle, not necessarily the right model.
    case representative

    public static func < (a: PhotoMatchLevel, b: PhotoMatchLevel) -> Bool {
        a.rank < b.rank
    }

    private var rank: Int {
        switch self {
        case .ownerPhoto: return 3
        case .exactModelYear: return 2
        case .generation: return 1
        case .representative: return 0
        }
    }

    /// What the app says under the picture. Never omitted, because the whole
    /// point of the level is that the owner knows which one they are looking
    /// at.
    public var disclosure: String {
        switch self {
        case .ownerPhoto:
            return "Your photo."
        case .exactModelYear:
            return "A photo of this year, make and model. Not your actual vehicle, so paint, wheels and options will differ."
        case .generation:
            return "A photo of this model's generation. The year shown may differ from yours, and so will paint, wheels and options."
        case .representative:
            return "A representative photo of this kind of vehicle, not this exact model. Shown only because no closer match was found."
        }
    }

    /// Whether the picture may be presented as being of this model at all.
    public var namesTheModel: Bool {
        self != .representative
    }
}

/// A photograph Odomind is allowed to show, and the terms it may show it on.
///
/// The licence and attribution are not optional metadata. A CC BY-SA image may
/// be displayed only with its author credited, so a record that cannot say who
/// took the picture is a record Odomind discards rather than renders.
public struct VehiclePhoto: Codable, Hashable, Sendable, Identifiable {
    public var id: String { sourceIdentifier }

    /// Namespaced, e.g. "commons:File:Example.jpg" — so two providers cannot
    /// collide and a cached record says where it came from.
    public var sourceIdentifier: String
    public var providerName: String
    /// The image itself.
    public var imageURL: URL
    /// The page a human should visit to see the licence in context.
    public var pageURL: URL?
    /// Short licence name as the provider states it, e.g. "CC BY-SA 4.0".
    public var licenceName: String
    public var licenceURL: URL?
    /// Who to credit. Empty is not acceptable for a licence that requires it.
    public var attribution: String
    public var matchLevel: PhotoMatchLevel
    /// What was searched for, kept so a cached record can be re-judged later.
    public var matchedQuery: String
    public var retrievedOn: Date
    public var pixelWidth: Int?
    public var pixelHeight: Int?

    public init(
        sourceIdentifier: String,
        providerName: String,
        imageURL: URL,
        pageURL: URL? = nil,
        licenceName: String,
        licenceURL: URL? = nil,
        attribution: String,
        matchLevel: PhotoMatchLevel,
        matchedQuery: String,
        retrievedOn: Date,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil
    ) {
        self.sourceIdentifier = sourceIdentifier
        self.providerName = providerName
        self.imageURL = imageURL
        self.pageURL = pageURL
        self.licenceName = licenceName
        self.licenceURL = licenceURL
        self.attribution = attribution
        self.matchLevel = matchLevel
        self.matchedQuery = matchedQuery
        self.retrievedOn = retrievedOn
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    /// Licences that oblige Odomind to name the author wherever the image is
    /// shown. Public-domain and CC0 images do not, though crediting anyway is
    /// no worse.
    public var requiresAttribution: Bool {
        let lowered = licenceName.lowercased()
        if lowered.contains("public domain") || lowered.contains("cc0") || lowered.contains("pd-") {
            return false
        }
        return true
    }

    /// Whether this record may be displayed at all.
    ///
    /// A missing licence is disqualifying, and so is a missing author on a
    /// licence that requires one. Odomind would rather show its quiet fallback
    /// than show somebody's photograph on terms it has not met.
    public var isDisplayable: Bool {
        guard !licenceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if requiresAttribution {
            return !attribution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    /// The one-line credit shown beneath the picture.
    public var creditLine: String {
        let who = attribution.trimmingCharacters(in: .whitespacesAndNewlines)
        if who.isEmpty { return licenceName }
        return "\(who) · \(licenceName)"
    }
}
