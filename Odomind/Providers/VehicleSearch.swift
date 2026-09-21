import Foundation
import Observation
import OdomindCore

/// One selectable vehicle from a search.
///
/// Carries where it came from, because a provider match and something the
/// owner typed are different things and must never be recorded as the same.
struct VehicleSearchResult: Identifiable, Hashable, Sendable {
    var id: String { "\(modelYear.map(String.init) ?? "any")-\(make)-\(model)" }
    /// Absent until the owner picks a year, which Odomind asks for after a
    /// vehicle is chosen rather than before it will search at all.
    var modelYear: Int?
    var make: String
    var model: String
    /// `.referenceSourced` when the model name came back from vPIC,
    /// `.userEntered` when the owner typed it and Odomind could not confirm it.
    var origin: DataOrigin

    var displayName: String {
        guard let modelYear else { return "\(make) \(model)" }
        return "\(modelYear) \(make) \(model)"
    }

    var identity: VehicleIdentity {
        VehicleIdentity(
            modelYear: modelYear,
            make: make,
            model: model,
            identityProvenance: origin
        )
    }
}

/// Drives the search field in onboarding and Add a vehicle.
///
/// What changed in Build 3, and why.
///
/// - **A year is no longer a precondition.** Build 2 refused to make any
///   request without a four-digit year *and* a make from a hard-coded list,
///   so "Wrangler" produced an instruction to type more. vPIC answers
///   `GetModelsForMake` without a year, so the year is now asked for after a
///   vehicle is chosen, when Odomind knows which years it was built.
/// - **Every input transition invalidates what is in flight.** Build 2 bumped
///   its sequence number only once a query was complete enough to act on, so
///   clearing the field or backspacing into an incomplete query left an older
///   request eligible to land and overwrite the screen. The generation now
///   advances on every transition, including to nothing at all.
/// - **The index suggests; the provider decides.** An unrecognised make used
///   to dead-end. It now still reaches the provider.
@MainActor
@Observable
final class VehicleSearchModel {
    enum State: Equatable {
        case idle
        /// Makes to offer before anything useful has been typed, or while a
        /// make is still being typed.
        case makeSuggestions([String])
        case searching
        case results([VehicleSearchResult])
        case empty(String)
        case offline(String)

        /// Whether there is already something useful on screen. Used to
        /// decide whether a spinner or an error would be an improvement on
        /// what the owner can already see.
        var hasResults: Bool {
            if case .results(let results) = self { return !results.isEmpty }
            return false
        }
    }

    private(set) var state: State = .idle
    /// Words the query carried beyond the model name — a trim or a body
    /// style. Offered as a refinement after selection, never used to discard
    /// a model.
    private(set) var trimHint: String?

    var providerName: String { provider.displayName }
    var providerHost: String { provider.contactedHost }

    private let provider: VehicleIdentificationProvider
    private let clock: OdomindClock
    private var searchTask: Task<Void, Never>?
    /// Bumped on *every* input transition. A response is only allowed to
    /// touch state while its generation is still the current one.
    private var generation = 0
    private var modelCache: [String: [String]] = [:]
    private var index: VehicleIndex = .empty

    init(provider: VehicleIdentificationProvider, clock: OdomindClock = SystemClock()) {
        self.provider = provider
        self.clock = clock
    }

    /// Loads the bundled suggestion index off the main actor.
    ///
    /// A few hundred kilobytes of JSON is not something a keystroke should
    /// wait for, so searching works before this finishes — against the
    /// provider alone — and suggestions sharpen once it lands.
    func loadIndex() async {
        guard index.makes.isEmpty else { return }
        let loaded = await Task.detached(priority: .utility) {
            try? VehicleIndexLoader.loadBundled()
        }.value
        guard let loaded else { return }
        index = loaded
        // Deliberately does not put suggestions on screen.
        //
        // It used to, and that pushed "Type it in myself" and "Use my VIN"
        // below twelve car brands nobody had asked for — off the first
        // screen, and out of the accessibility tree entirely, because a List
        // does not realise rows that far down. The two ways out of a failing
        // search were unreachable on a fresh install. Suggestions are worth
        // showing once somebody starts typing, not before.
    }

    /// Makes to show before anything has been typed.
    func suggestedMakes(limit: Int = 12) -> [String] {
        Array(index.passengerMakes.prefix(limit))
    }

    /// Cancels anything in flight and makes its answer unusable.
    ///
    /// Called when the field clears and when the screen goes away. Bumping the
    /// generation is the part that matters: cancellation alone races, because
    /// a response already decoded cannot be un-delivered.
    func cancel() {
        generation += 1
        searchTask?.cancel()
        searchTask = nil
    }

    func search(_ text: String, debounce: Duration = .milliseconds(300)) {
        // Before anything else, so no path through this function can leave an
        // older response eligible.
        generation += 1
        let mine = generation
        searchTask?.cancel()
        searchTask = nil
        trimHint = nil

        let query = VehicleQueryPlanner.plan(text, index: index, now: clock.now)

        switch query.intent {
        case .tooShort:
            // An empty field is not a short query: it is somebody who has not
            // started. Clearing the field puts the screen back the way it
            // opened rather than filling it with brands.
            let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            state = typed.isEmpty || index.makes.isEmpty
                ? .idle
                : .makeSuggestions(suggestedMakes())
            return

        case .makeSuggestions(let makes):
            state = .makeSuggestions(makes)
            return

        case .make(let make):
            run(mine, debounce: debounce, make: make, year: query.modelYear, narrowing: [])

        case .makeAndModel(let make, let tokens):
            run(mine, debounce: debounce, make: make, year: query.modelYear, narrowing: tokens)

        case .model(let tokens, let candidates):
            // The index already knows who builds it, so the shown results are
            // immediate and the provider confirms rather than gates.
            let immediate = candidates.map {
                VehicleSearchResult(
                    modelYear: query.modelYear,
                    make: $0.make,
                    model: $0.model,
                    origin: .referenceSourced
                )
            }
            state = immediate.isEmpty ? .searching : .results(immediate)
            trimHint = Self.hint(from: tokens, matching: candidates.first?.model)
            guard let best = candidates.first else { return }
            run(mine, debounce: debounce, make: best.make, year: query.modelYear, narrowing: tokens)

        case .unrecognised(let tokens):
            // The index has never heard of it. Ask the provider anyway, using
            // the first word as a make — this is exactly where Build 2 gave up.
            guard let first = tokens.first else {
                state = .empty("Nothing matched that.")
                return
            }
            run(
                mine,
                debounce: debounce,
                make: first,
                year: query.modelYear,
                narrowing: Array(tokens.dropFirst())
            )
        }
    }

    // MARK: - Running

    /// Debounces, then asks. No closure indirection: a `@Sendable` closure
    /// would not inherit this actor, and the generation check has to happen
    /// where the state is.
    private func run(_ mine: Int, debounce: Duration, make: String, year: Int?, narrowing tokens: [String]) {
        // Only show a spinner when there is nothing better to look at. For a
        // model query the index has already put real results on screen, and
        // replacing them with a spinner while the provider confirms the same
        // thing is a flicker that makes the instant suggestions pointless.
        if !state.hasResults { state = .searching }
        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(for: debounce)
            } catch {
                return
            }
            if Task.isCancelled { return }
            await self?.listModels(make: make, year: year, narrowing: tokens, generation: mine)
        }
    }

    private func listModels(make: String, year: Int?, narrowing tokens: [String], generation mine: Int) async {
        guard generation == mine else { return }
        let cacheKey = year.map { "\(make.lowercased())#\($0)" } ?? make.lowercased()
        var names = modelCache[cacheKey]

        if names == nil {
            do {
                // Written out rather than through `Optional.map`, whose
                // closure is synchronous and cannot carry an await.
                if let year {
                    names = try await provider.models(make: make, modelYear: year)
                } else {
                    names = try await provider.models(make: make)
                }
            } catch let error as ProviderError {
                guard generation == mine else { return }
                if error == .cancelled { return }
                // Keep what the index found. A provider outage is a reason to
                // stop confirming, not a reason to take away a correct answer
                // the owner is already looking at.
                guard !state.hasResults else { return }
                state = .offline(error.errorDescription ?? "The vehicle lookup service is not available.")
                return
            } catch {
                guard generation == mine else { return }
                guard !state.hasResults else { return }
                state = .offline("The vehicle lookup service is not available.")
                return
            }
            if let names, !names.isEmpty { modelCache[cacheKey] = names }
        }

        // The guard that matters. A response for an older keystroke — or for a
        // query the owner has since cleared — is dropped here rather than
        // being allowed to replace a newer answer.
        guard generation == mine else { return }

        let all = names ?? []
        let ranked = VehicleTextMatch.rank(models: all, queryTokens: tokens, limit: 25)
        trimHint = Self.hint(from: tokens, matching: ranked.first?.model)

        let results = ranked.map {
            VehicleSearchResult(modelYear: year, make: make, model: $0.model, origin: .referenceSourced)
        }

        if results.isEmpty {
            // Same rule: do not replace a usable answer with "no match".
            guard !state.hasResults else { return }
            state = .empty(
                all.isEmpty
                    ? "The vehicle service had no models for \(make)."
                    : "No \(make) model matched that."
            )
        } else {
            state = .results(results)
        }
    }

    /// The words a query carried past the model name.
    private static func hint(from tokens: [String], matching model: String?) -> String? {
        guard let model, !tokens.isEmpty else { return nil }
        guard let match = VehicleTextMatch.match(model: model, queryTokens: tokens) else { return nil }
        guard !match.leftover.isEmpty else { return nil }
        return match.leftover.joined(separator: " ")
    }
}
