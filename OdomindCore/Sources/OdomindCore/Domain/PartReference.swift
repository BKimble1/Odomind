import Foundation

/// What a catalogue says about a part, independent of anyone selling it.
///
/// Kept separate from `PartOffer` deliberately. A manufacturer part number is
/// a durable fact about a component; a price is a perishable fact about one
/// shop on one afternoon. Conflating them is how an app ends up showing a
/// stale price as though it were a specification, or a retailer's own SKU as
/// though it were the part number to search for anywhere else.
public struct PartReference: Codable, Hashable, Sendable, Identifiable {
    /// Namespaced by provider, so two catalogues cannot collide.
    public var id: String
    /// Who makes the part — Mopar, Bosch, Fram.
    public var brand: String
    /// The manufacturer's own number. **Not** a retailer SKU: those are
    /// specific to one shop and mean nothing at the next one.
    public var manufacturerPartNumber: String
    /// The catalogue's internal identifier, kept for re-querying.
    public var providerPartID: String?
    public var category: String
    /// Front, rear, left, right — where more than one is fitted.
    public var position: String?
    /// How many the job takes, when the catalogue says.
    public var quantityRequired: Int?
    /// Conditions the catalogue attaches: "with 3.8L engine", "to VIN break
    /// 
    /// EL123456", "heavy duty cooling". Shown verbatim rather than
    /// summarised, because summarising a qualifier is how it stops being true.
    public var qualifiers: [String]
    public var applicability: PartApplicability
    /// Numbers this one replaces.
    public var supersedes: [String]
    /// Set when this number has itself been replaced.
    public var supersededBy: String?
    public var provenance: DataOrigin
    public var sourceName: String
    public var retrievedOn: Date

    public init(
        id: String,
        brand: String,
        manufacturerPartNumber: String,
        providerPartID: String? = nil,
        category: String,
        position: String? = nil,
        quantityRequired: Int? = nil,
        qualifiers: [String] = [],
        applicability: PartApplicability,
        supersedes: [String] = [],
        supersededBy: String? = nil,
        provenance: DataOrigin = .referenceSourced,
        sourceName: String,
        retrievedOn: Date
    ) {
        self.id = id
        self.brand = brand
        self.manufacturerPartNumber = manufacturerPartNumber
        self.providerPartID = providerPartID
        self.category = category
        self.position = position
        self.quantityRequired = quantityRequired
        self.qualifiers = qualifiers
        self.applicability = applicability
        self.supersedes = supersedes
        self.supersededBy = supersededBy
        self.provenance = provenance
        self.sourceName = sourceName
        self.retrievedOn = retrievedOn
    }

    /// Whether the app may say "Fits your vehicle".
    ///
    /// Three things all have to hold, and each has bitten somebody's app
    /// before: the catalogue has to have confirmed it, nothing may still be
    /// unanswered, and a superseded number is not the one to buy even when the
    /// old record still technically applies.
    public var fitsConfirmed: Bool {
        guard case .confirmed = applicability else { return false }
        return supersededBy == nil
    }

    /// The single line shown beside the part. Never "fits" unless it does.
    public var fitSummary: String {
        if let supersededBy {
            return "Replaced by \(supersededBy) — buy that instead."
        }
        switch applicability {
        case .confirmed:
            return qualifiers.isEmpty ? "Fits your vehicle" : "Fits your vehicle — \(qualifiers.joined(separator: ", "))"
        case .conditional(let missing):
            let what = missing.joined(separator: ", ")
            return "Fits if \(what) — Odomind does not know that yet."
        case .notApplicable(let reason):
            return "Does not fit — \(reason)"
        }
    }
}

/// Whether a part applies to the vehicle in hand.
public enum PartApplicability: Codable, Hashable, Sendable {
    /// The catalogue confirmed it against the configuration Odomind holds.
    case confirmed
    /// It depends on something not yet established. The missing pieces are
    /// named so the app can ask one specific question rather than shrugging.
    case conditional(missing: [String])
    /// The catalogue lists the part for this vehicle but rules it out for this
    /// configuration.
    case notApplicable(reason: String)
}

/// What one seller is asking, at one moment.
///
/// Every field a retailer supplies and nothing Odomind inferred. An offer
/// without a price is an offer without a price; the app says so rather than
/// filling the gap.
public struct PartOffer: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    /// The part this is an offer *for*, by manufacturer part number.
    public var manufacturerPartNumber: String
    public var retailerName: String
    /// The retailer's own identifier. Useful for their site, meaningless
    /// elsewhere, and never presented as the part number.
    public var retailerSKU: String?
    public var productURL: URL?
    public var price: Money?
    public var availability: String?
    /// Which branch, when the offer is store-level rather than online.
    public var storeName: String?
    public var retrievedOn: Date

    public init(
        id: String,
        manufacturerPartNumber: String,
        retailerName: String,
        retailerSKU: String? = nil,
        productURL: URL? = nil,
        price: Money? = nil,
        availability: String? = nil,
        storeName: String? = nil,
        retrievedOn: Date
    ) {
        self.id = id
        self.manufacturerPartNumber = manufacturerPartNumber
        self.retailerName = retailerName
        self.retailerSKU = retailerSKU
        self.productURL = productURL
        self.price = price
        self.availability = availability
        self.storeName = storeName
        self.retrievedOn = retrievedOn
    }

    /// An online price is not a promise about the shelf in a shop, and a shop
    /// being near is not a promise it has one.
    public static let localPriceCaveat =
        "Online prices and in-store prices differ, and distance is not stock. Check with the shop before setting off."
}

/// A part and what is on offer for it, which is what a screen actually shows.
public struct PartResult: Hashable, Sendable, Identifiable {
    public var id: String { reference.id }
    public var reference: PartReference
    public var offers: [PartOffer]

    public init(reference: PartReference, offers: [PartOffer] = []) {
        self.reference = reference
        self.offers = offers
    }

    /// The cheapest offer, but only when there is more than one to compare and
    /// all of them carry a price. "Cheapest" from a single offer is not a
    /// comparison, and the brief is explicit that Odomind must not advertise
    /// one.
    public var comparableBest: PartOffer? {
        let priced = offers.filter { $0.price != nil }
        guard priced.count > 1 else { return nil }
        return priced.min { ($0.price?.amount ?? 0) < ($1.price?.amount ?? 0) }
    }
}
