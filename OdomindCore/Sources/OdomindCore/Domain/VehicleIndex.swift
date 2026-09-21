import Foundation

/// Odomind's bootstrap make and model index.
///
/// Generated from vPIC's public endpoints by
/// `.github/scripts/build-vehicle-index.py`, not typed by hand. It exists for
/// two jobs and no others:
///
/// - **Suggest instantly.** Somebody who has typed "jee" should see Jeep
///   before any network call finishes.
/// - **Route a query.** "wrangler" on its own has to become "ask vPIC about
///   Jeep", and only an index that maps models back to makes can do that.
///
/// It is explicitly *not* the authority on what exists. Authoritative model
/// lists come from the provider at search time, so a vehicle missing from this
/// file is slower to suggest and never blocked — which is the difference
/// between this and the 43-make list it replaces, where an unlisted make meant
/// the query never reached the provider at all.
public struct VehicleIndex: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var source: String
    public var sourceURL: String
    public var generatedOn: String
    /// Typed shorthand no provider knows: chevy, vw, mercedes.
    public var aliases: [String: String]
    /// Every make vPIC knows, including the equipment manufacturers.
    public var makes: [String]
    /// The subset that sells passenger vehicles, which is what gets suggested.
    public var passengerMakes: [String]
    /// Make to its model names.
    public var models: [String: [String]]

    public init(
        schemaVersion: Int = 1,
        source: String = "",
        sourceURL: String = "",
        generatedOn: String = "",
        aliases: [String: String] = [:],
        makes: [String] = [],
        passengerMakes: [String] = [],
        models: [String: [String]] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.source = source
        self.sourceURL = sourceURL
        self.generatedOn = generatedOn
        self.aliases = aliases
        self.makes = makes
        self.passengerMakes = passengerMakes
        self.models = models
    }

    public static let empty = VehicleIndex()

    // MARK: - Lookups

    /// The make a word names, if any. Tries the alias table, then an exact
    /// name match, then a normalised one so "mercedes benz" finds
    /// "MERCEDES-BENZ".
    public func make(named text: String) -> String? {
        let normalised = VehicleTextMatch.normalise(text)
        guard !normalised.isEmpty else { return nil }
        if let aliased = aliases[normalised] { return aliased }
        let key = VehicleTextMatch.key(text)
        return makes.first { VehicleTextMatch.key($0) == key }
    }

    /// Makes worth suggesting for a partly typed name, best first.
    public func makes(matching text: String, limit: Int = 8) -> [String] {
        let queryTokens = VehicleTextMatch.tokens(text)
        guard !queryTokens.isEmpty else { return Array(passengerMakes.prefix(limit)) }

        if let aliased = aliases[VehicleTextMatch.normalise(text)] {
            return [aliased]
        }

        let pool = passengerMakes.isEmpty ? makes : passengerMakes
        return VehicleTextMatch.rank(models: pool, queryTokens: queryTokens, limit: limit)
            .map(\.model)
    }

    /// The makes that offer a model answering this query, best first.
    ///
    /// This is what lets "wrangler" work with no make typed at all.
    public func makesOffering(modelTokens: [String], limit: Int = 6) -> [(make: String, model: String, match: VehicleTextMatch.ModelMatch)] {
        guard !modelTokens.isEmpty else { return [] }
        var hits: [(make: String, model: String, match: VehicleTextMatch.ModelMatch)] = []
        for make in models.keys.sorted() {
            guard let names = models[make] else { continue }
            // Only the single best model per make, so one make cannot fill the
            // whole list with near-duplicate trims.
            if let best = VehicleTextMatch.rank(models: names, queryTokens: modelTokens, limit: 1).first {
                hits.append((make, best.model, best.match))
            }
        }
        return hits
            .sorted { left, right in
                if left.match != right.match { return left.match < right.match }
                return left.make.localizedCaseInsensitiveCompare(right.make) == .orderedAscending
            }
            .prefix(limit)
            .map { $0 }
    }

    public func models(for make: String) -> [String] {
        let key = VehicleTextMatch.key(make)
        guard let found = models.first(where: { VehicleTextMatch.key($0.key) == key }) else { return [] }
        return found.value
    }
}
