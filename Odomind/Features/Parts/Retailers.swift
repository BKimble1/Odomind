import Foundation
import OdomindCore

/// What a shopping integration can honestly show.
///
/// This exists so the boundary is a type rather than a habit. Odomind has
/// place search and retailer deep links; it has no licensed product feed and
/// no store inventory, so the two richer cases below are unreachable in this
/// build and the UI is written against the level actually available.
enum ShoppingCapability: Int, Comparable {
    /// Nearby businesses, from a map search. No stock, no price.
    case placeSearchOnly = 0
    /// A link into a retailer's own search. "Check price and fit there."
    case retailerSearchLink = 1
    /// A licensed product feed: real price, currency, pack size, seller, and
    /// the time the offer was read.
    case licensedOffers = 2
    /// Store-level stock, to whatever extent a provider actually supplies it.
    case verifiedInventory = 3

    static func < (lhs: ShoppingCapability, rhs: ShoppingCapability) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// What this build can do.
    ///
    /// Raising this is not a UI change: it requires a provider with terms,
    /// credentials that are not in this repository or the app binary, and a
    /// conformance to `ProductOfferProvider` below.
    static let current: ShoppingCapability = .retailerSearchLink
}

/// The boundary a live-offer provider would implement.
///
/// Deliberately small and unimplemented. A protocol is not a feature: nothing
/// in the app claims prices, and until something conforms to this and
/// `ShoppingCapability.current` is raised, the offers UI stays unreachable.
protocol ProductOfferProvider: Sendable {
    var displayName: String { get }
    /// Terms under which offers may be shown, for the data-sources screen.
    var termsSummary: String { get }
    func offers(matching query: String, near postalCode: String?) async throws -> [ProductOffer]
}

/// A real, licensed offer. No instance of this is produced in this build.
struct ProductOffer: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var seller: String
    var price: Money
    /// Pack size, so a one-quart bottle is never compared with a five-quart
    /// jug as though they were the same thing.
    var quantityDescription: String?
    var condition: String?
    var shippingNote: String?
    /// When the offer was read, so a cached one can say how old it is rather
    /// than passing as current.
    var retrievedAt: Date
    var url: URL
}

/// A retailer Odomind can open a search at.
///
/// Every template here opens the retailer's own search with a properly encoded
/// query. Where a retailer cannot reliably take a pre-filled vehicle, the entry
/// says so and Odomind offers to copy the specification instead of pretending
/// the link carries it.
struct Retailer: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    /// Search-term placeholder is `{query}`.
    var searchTemplate: String
    /// True when the retailer's search page takes a free-text term reliably.
    /// False means Odomind opens their vehicle selector and says so.
    var acceptsPrefilledSearch: Bool
    /// What a nearby map search would look for.
    var mapQuery: String

    func url(for query: String) -> URL? {
        // Not `.urlQueryAllowed`: that set permits `&`, `=`, `?` and `+`, so a
        // part name containing one would not be escaped — it would end up
        // adding a parameter to somebody else's URL instead of being searched
        // for. Encoding the sub-delimiters as well keeps the whole term inside
        // the one parameter it belongs to.
        let encoded = query.addingPercentEncoding(withAllowedCharacters: Retailer.queryValueAllowed) ?? ""
        return URL(string: searchTemplate.replacingOccurrences(of: "{query}", with: encoded))
    }

    /// `urlQueryAllowed` minus the characters that would change the URL's
    /// structure rather than its content.
    static let queryValueAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=?+#/;:$,@[]!'()*")
        return allowed
    }()

    /// The retailers Odomind links to.
    ///
    /// Each is a public search endpoint, opened in the owner's browser. No
    /// affiliate parameters, no tracking identifiers, and no vehicle history
    /// or VIN is ever put in one of these URLs.
    static let all: [Retailer] = [
        Retailer(
            id: "autozone",
            name: "AutoZone",
            searchTemplate: "https://www.autozone.com/searchresult?searchText={query}",
            acceptsPrefilledSearch: true,
            mapQuery: "auto parts store"
        ),
        Retailer(
            id: "oreilly",
            name: "O'Reilly Auto Parts",
            searchTemplate: "https://www.oreillyauto.com/search?q={query}",
            acceptsPrefilledSearch: true,
            mapQuery: "auto parts store"
        ),
        Retailer(
            id: "advance",
            name: "Advance Auto Parts",
            searchTemplate: "https://shop.advanceautoparts.com/web/SearchResults?searchTerm={query}",
            acceptsPrefilledSearch: true,
            mapQuery: "auto parts store"
        ),
        Retailer(
            id: "napa",
            name: "NAPA Auto Parts",
            searchTemplate: "https://www.napaonline.com/en/search?text={query}",
            acceptsPrefilledSearch: true,
            mapQuery: "NAPA auto parts"
        ),
        Retailer(
            id: "rockauto",
            name: "RockAuto",
            // RockAuto navigates by a catalog tree rather than a text search
            // that takes a vehicle, so Odomind opens the catalog and offers
            // the specification to paste rather than claiming a pre-filled
            // result it cannot deliver.
            searchTemplate: "https://www.rockauto.com/en/catalog/",
            acceptsPrefilledSearch: false,
            mapQuery: "auto parts store"
        ),
        Retailer(
            id: "tirerack",
            name: "Tire Rack",
            searchTemplate: "https://www.tirerack.com/tires/TireSearchResults.jsp?width={query}",
            acceptsPrefilledSearch: false,
            mapQuery: "tire shop"
        )
    ]
}

/// Turns what Odomind knows about a vehicle into a search term.
enum PartsQueryBuilder {
    /// The vehicle, then the part. Year-make-model is what every retailer's
    /// search expects first.
    ///
    /// Never includes the VIN, the nickname or anything from the service
    /// history: a retailer has no business receiving any of that, and the
    /// owner did not ask Odomind to send it.
    static func query(for vehicle: Vehicle, part: String, specification: String? = nil) -> String {
        var parts: [String] = []
        if let year = vehicle.identity.modelYear { parts.append(String(year)) }
        if !vehicle.identity.make.isEmpty { parts.append(vehicle.identity.make) }
        if !vehicle.identity.model.isEmpty { parts.append(vehicle.identity.model) }
        if let specification, !specification.isEmpty {
            parts.append(specification)
        }
        let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { parts.append(trimmed) }
        return parts.joined(separator: " ")
    }

    /// The fitment caveat, worded so a generic model match is never read as a
    /// promise that a part fits.
    static let fitmentCaveat = "Odomind matched the year, make and model. That is a starting point, not a guarantee of fit — trim, engine and factory options all change which part is correct. Confirm fitment on the retailer's site before you buy."
}
