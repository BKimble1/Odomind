import Foundation

/// How Odomind compares what somebody typed against a vehicle name.
///
/// Build 2 took everything left after removing a year and a make and matched
/// it against each model name as one substring. That is why
/// "2010 Jeep Wrangler Unlimited Sport" found nothing: the leftover was
/// "Unlimited Sport", no model is called that, and a perfectly good Wrangler
/// was discarded. Extra words the owner types are almost always *more*
/// specific, not different — they should narrow a result, never delete it.
///
/// Everything here is pure text work so it can be tested without a network,
/// a provider or a simulator.
public enum VehicleTextMatch {

    /// Folds away the differences people do not think about: case, accents,
    /// punctuation and spacing. "F-150", "f150" and "F 150" all land on the
    /// same thing, which is the whole point.
    public static func normalise(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let scalars = folded.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) { return Character(scalar) }
            return " "
        }
        return String(scalars)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }

    /// The words of a query, normalised.
    public static func tokens(_ text: String) -> [String] {
        let normalised = normalise(text)
        guard !normalised.isEmpty else { return [] }
        return normalised.split(separator: " ").map(String.init)
    }

    /// A comparison key that ignores word breaks entirely, so "F 150" and
    /// "f150" are the same key. Used for exact-name equality only; general
    /// matching goes through tokens, because ignoring word breaks everywhere
    /// would make "Accord" match "Accordion".
    public static func key(_ text: String) -> String {
        tokens(text).joined()
    }

    /// How well a model name answers a query, and what the query said beyond it.
    public struct ModelMatch: Equatable, Sendable, Comparable {
        /// Higher is a better answer to what was typed.
        public enum Quality: Int, Sendable, Comparable {
            /// The query names this model and nothing else: "wrangler".
            case exact = 4
            /// Every word of the model appears, in order, at the start:
            /// "wrangler unlimited" against "Wrangler".
            case leadingRun = 3
            /// Every word of the model appears somewhere: "jeep wrangler 4dr".
            case allWordsPresent = 2
            /// The model name begins with what was typed: "wran".
            case prefix = 1

            public static func < (a: Quality, b: Quality) -> Bool { a.rawValue < b.rawValue }
        }

        public var quality: Quality
        /// Query words the model name did not account for. These are a trim or
        /// a body style — "unlimited", "sport" — and become a refinement, not
        /// a reason to drop the model.
        public var leftover: [String]

        public init(quality: Quality, leftover: [String]) {
            self.quality = quality
            self.leftover = leftover
        }

        /// Better matches sort first: stronger quality, then fewer unexplained
        /// words, so "Wrangler" beats "Wrangler JK" for the query "wrangler".
        public static func < (a: ModelMatch, b: ModelMatch) -> Bool {
            if a.quality != b.quality { return a.quality > b.quality }
            return a.leftover.count < b.leftover.count
        }
    }

    /// Whether `model` is a reasonable answer to `queryTokens`, and what was
    /// left unexplained.
    ///
    /// Returns `nil` only when the model genuinely has nothing to do with the
    /// query. A model the owner named plus extra detail always matches.
    public static func match(model: String, queryTokens: [String]) -> ModelMatch? {
        let modelTokens = tokens(model)
        guard !modelTokens.isEmpty, !queryTokens.isEmpty else { return nil }

        let modelKey = modelTokens.joined()
        let queryKey = queryTokens.joined()

        if modelKey == queryKey {
            return ModelMatch(quality: .exact, leftover: [])
        }

        // Every model word present, in order, starting at the first query word.
        if queryTokens.count >= modelTokens.count,
           Array(queryTokens.prefix(modelTokens.count)) == modelTokens {
            return ModelMatch(
                quality: .leadingRun,
                leftover: Array(queryTokens.dropFirst(modelTokens.count))
            )
        }

        // Every model word present somewhere. Consumed word-by-word so a model
        // needing two "gt"s is not satisfied by one.
        var remaining = queryTokens
        var matchedAll = true
        for token in modelTokens {
            if let index = remaining.firstIndex(of: token) {
                remaining.remove(at: index)
            } else {
                matchedAll = false
                break
            }
        }
        if matchedAll {
            return ModelMatch(quality: .allWordsPresent, leftover: remaining)
        }

        // Still typing. Only the joined form, so "wran" finds "Wrangler"
        // without "acc" dragging in every model containing those letters.
        if !queryKey.isEmpty, modelKey.hasPrefix(queryKey) {
            return ModelMatch(quality: .prefix, leftover: [])
        }

        return nil
    }

    /// The models that answer a query, best first.
    ///
    /// - Parameter limit: nil returns everything, which the tests want and no
    ///   screen does.
    public static func rank(models: [String], queryTokens: [String], limit: Int? = nil) -> [(model: String, match: ModelMatch)] {
        guard !queryTokens.isEmpty else {
            let sorted = models.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            let capped = limit.map { Array(sorted.prefix($0)) } ?? sorted
            return capped.map { ($0, ModelMatch(quality: .prefix, leftover: [])) }
        }

        let scored = models.compactMap { model -> (model: String, match: ModelMatch)? in
            guard let match = match(model: model, queryTokens: queryTokens) else { return nil }
            return (model, match)
        }
        .sorted { left, right in
            if left.match != right.match { return left.match < right.match }
            return left.model.localizedCaseInsensitiveCompare(right.model) == .orderedAscending
        }

        return limit.map { Array(scored.prefix($0)) } ?? scored
    }
}
