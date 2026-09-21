import Foundation

/// One make that offers a model somebody typed.
public struct MakeCandidate: Equatable, Sendable, Hashable {
    public var make: String
    public var model: String
    public var quality: VehicleTextMatch.ModelMatch.Quality

    public init(make: String, model: String, quality: VehicleTextMatch.ModelMatch.Quality) {
        self.make = make
        self.model = model
        self.quality = quality
    }
}

/// What a typed query is asking for.
public struct VehicleQuery: Equatable, Sendable {
    public enum Intent: Equatable, Sendable {
        /// Nothing to act on yet.
        case tooShort
        /// Part of a make name: offer these.
        case makeSuggestions([String])
        /// A make and nothing more: list what it builds.
        case make(String)
        /// Model words with no make. The index says who builds it, which is
        /// what makes "wrangler" on its own a usable query.
        case model(tokens: [String], candidates: [MakeCandidate])
        /// Both, so the model list can be narrowed immediately.
        case makeAndModel(make: String, tokens: [String])
        /// Recognised by nobody. Still worth asking the provider about —
        /// the index is a suggestion aid, never the authority on what exists.
        case unrecognised(tokens: [String])
    }

    public var modelYear: Int?
    public var intent: Intent
    public var raw: String

    public init(modelYear: Int? = nil, intent: Intent, raw: String) {
        self.modelYear = modelYear
        self.intent = intent
        self.raw = raw
    }
}

/// Turns what somebody typed into something Odomind can act on.
///
/// The change from Build 2 is what happens when a query is incomplete. Build 2
/// required a four-digit year *and* a make from a hand-typed list of 43 before
/// it would make any request at all, so "Wrangler" — which is how people
/// actually talk about their car — produced a instruction to type more. A year
/// is now something Odomind asks for *after* a vehicle is chosen, when it
/// knows which years that model was even built.
public enum VehicleQueryPlanner {

    public static func plan(
        _ text: String,
        index: VehicleIndex,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> VehicleQuery {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var working = raw

        // A model year, wherever it sits: people type "2010 Jeep Wrangler" and
        // "jeep wrangler 2010" in roughly equal numbers.
        var year: Int?
        let currentYear = calendar.component(.year, from: now)
        if let range = working.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression) {
            let candidate = Int(working[range])
            // A model year runs at most one ahead of the calendar. Beyond that
            // it is a part number or an engine size, not a year.
            if let candidate, candidate >= 1900, candidate <= currentYear + 1 {
                year = candidate
                working.removeSubrange(range)
            }
        }

        let tokens = VehicleTextMatch.tokens(working)
        guard !tokens.isEmpty else {
            return VehicleQuery(modelYear: year, intent: .tooShort, raw: raw)
        }

        // Order matters here, and it is not obvious.
        //
        // A make can be more than one word, so the longest leading run is
        // tried first: "land rover discovery" must not resolve to a make of
        // "land". But only against makes that actually sell cars — vPIC's
        // full list contains "WRANGLER", so consulting it first turned a
        // search for a Jeep into a search for a trailer manufacturer.
        if let resolved = leadingMake(tokens, using: { index.passengerMake(named: $0) }) {
            return VehicleQuery(modelYear: year, intent: resolved, raw: raw)
        }

        // Then the words as a model. This is what makes a bare "wrangler"
        // answerable, and it has to come before the full make list.
        let candidates = index.makesOffering(modelTokens: tokens).map {
            MakeCandidate(make: $0.make, model: $0.model, quality: $0.match.quality)
        }
        if !candidates.isEmpty {
            return VehicleQuery(modelYear: year, intent: .model(tokens: tokens, candidates: candidates), raw: raw)
        }

        // Only now the long tail, so a genuinely unusual make still works.
        if let resolved = leadingMake(tokens, using: { index.anyMake(named: $0) }) {
            return VehicleQuery(modelYear: year, intent: resolved, raw: raw)
        }

        // Still part-way through typing a make?
        let partial = index.makes(matching: working)
        if !partial.isEmpty {
            return VehicleQuery(modelYear: year, intent: .makeSuggestions(partial), raw: raw)
        }

        return VehicleQuery(modelYear: year, intent: .unrecognised(tokens: tokens), raw: raw)
    }

    /// The longest leading run of words that `resolve` recognises as a make.
    private static func leadingMake(
        _ tokens: [String],
        using resolve: (String) -> String?
    ) -> VehicleQuery.Intent? {
        for length in stride(from: min(tokens.count, 3), through: 1, by: -1) {
            let leading = tokens.prefix(length).joined(separator: " ")
            guard let make = resolve(leading) else { continue }
            let rest = Array(tokens.dropFirst(length))
            return rest.isEmpty ? .make(make) : .makeAndModel(make: make, tokens: rest)
        }
        return nil
    }
}
