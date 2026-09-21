import Foundation
import Observation
import OdomindCore

/// One selectable vehicle from a search.
///
/// Carries where it came from, because a provider match and something the
/// owner typed are different things and must never be recorded as the same.
struct VehicleSearchResult: Identifiable, Hashable, Sendable {
    var id: String { "\(modelYear)-\(make)-\(model)" }
    var modelYear: Int
    var make: String
    var model: String
    /// `.referenceSourced` when the model name came back from vPIC,
    /// `.userEntered` when the owner typed it and Odomind could not confirm it.
    var origin: DataOrigin

    var displayName: String { "\(modelYear) \(make) \(model)" }

    var identity: VehicleIdentity {
        VehicleIdentity(
            modelYear: modelYear,
            make: make,
            model: model,
            identityProvenance: origin
        )
    }
}

/// The makes Odomind offers as a starting point.
///
/// This list is Odomind's own and is only a routing aid: it decides which make
/// to ask vPIC about. The *models* always come from the provider. vPIC's own
/// all-makes endpoint returns thousands of entries including trailer and
/// equipment manufacturers, which is accurate and useless as a suggestion list.
///
/// A make that is not here is not blocked: the owner can still type it, and
/// Odomind asks the provider about exactly what they typed.
enum CommonMakes {
    static let all: [String] = [
        "Acura", "Alfa Romeo", "Audi", "BMW", "Buick", "Cadillac", "Chevrolet", "Chrysler",
        "Dodge", "Fiat", "Ford", "Genesis", "GMC", "Honda", "Hyundai", "Infiniti", "Jaguar",
        "Jeep", "Kia", "Land Rover", "Lexus", "Lincoln", "Lucid", "Maserati", "Mazda",
        "Mercedes-Benz", "MINI", "Mitsubishi", "Nissan", "Polestar", "Pontiac", "Porsche",
        "Ram", "Rivian", "Saab", "Saturn", "Scion", "Subaru", "Suzuki", "Tesla", "Toyota",
        "Volkswagen", "Volvo"
    ]

    /// The best make match inside a free-text query, longest name first so
    /// "Land Rover" wins over a stray "Rover".
    static func match(in text: String) -> String? {
        let lowered = text.lowercased()
        return all
            .sorted { $0.count > $1.count }
            .first { lowered.contains($0.lowercased()) }
    }
}

/// What the owner typed, taken apart.
struct ParsedVehicleQuery: Equatable {
    var modelYear: Int?
    var make: String?
    /// Everything left over, which is where the model name will be.
    var remainder: String

    /// Pulls a four-digit year and a known make out of free text.
    ///
    /// "2010 Jeep Wrangler" and "jeep wrangler 2010" both parse the same way,
    /// because people type both.
    static func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> ParsedVehicleQuery {
        let currentYear = calendar.component(.year, from: now)
        var working = text

        var year: Int?
        if let range = working.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression) {
            let candidate = Int(working[range])
            // A model year can run one ahead of the calendar year; anything
            // beyond that is a part number, not a year.
            if let candidate, candidate >= 1900, candidate <= currentYear + 1 {
                year = candidate
                working.removeSubrange(range)
            }
        }

        var make: String?
        if let matched = CommonMakes.match(in: working) {
            make = matched
            if let range = working.range(of: matched, options: .caseInsensitive) {
                working.removeSubrange(range)
            }
        }

        return ParsedVehicleQuery(
            modelYear: year,
            make: make,
            remainder: working.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

/// Drives the search field in onboarding and Add a vehicle.
///
/// Four things this does that a naive implementation does not:
///
/// - **Debounces.** A request per keystroke is a request per keystroke.
/// - **Cancels.** The previous search is cancelled when a new one starts.
/// - **Refuses stale answers.** Every search carries a sequence number and a
///   result is dropped unless it belongs to the newest one. Without this, a
///   slow response for "jee" can land after a fast one for "jeep wrangler" and
///   silently replace the right answer with the wrong one.
/// - **Caches.** A make-and-year pair is asked for once per session.
@MainActor
@Observable
final class VehicleSearchModel {
    enum State: Equatable {
        case idle
        case needsMoreDetail(String)
        case searching
        case results([VehicleSearchResult])
        case empty(String)
        case offline(String)
    }

    private(set) var state: State = .idle

    /// Whether this session has already disclosed that searching contacts the
    /// provider. Shown once as a line under the field, not as a modal per
    /// keystroke.
    var providerName: String { provider.displayName }
    var providerHost: String { provider.contactedHost }

    private let provider: VehicleIdentificationProvider
    private let clock: OdomindClock
    private var searchTask: Task<Void, Never>?
    private var sequence = 0
    private var cache: [String: [String]] = [:]

    init(provider: VehicleIdentificationProvider, clock: OdomindClock = SystemClock()) {
        self.provider = provider
        self.clock = clock
    }

    // No `deinit` cancel: `deinit` is nonisolated and cannot touch a
    // main-actor property. The search task holds `self` weakly and the view
    // cancels on disappear, so nothing outlives the screen either way.

    func cancel() {
        searchTask?.cancel()
        searchTask = nil
    }

    /// Runs a search for what the owner has typed so far.
    func search(_ text: String, debounce: Duration = .milliseconds(350)) {
        searchTask?.cancel()

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            state = .idle
            return
        }

        let parsed = ParsedVehicleQuery.parse(trimmed, now: clock.now)
        guard let year = parsed.modelYear, let make = parsed.make else {
            state = .needsMoreDetail(hint(for: parsed))
            return
        }

        sequence += 1
        let mySequence = sequence
        state = .searching

        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: debounce)
            } catch {
                return
            }
            if Task.isCancelled { return }
            await self.run(make: make, year: year, needle: parsed.remainder, sequence: mySequence)
        }
    }

    private func run(make: String, year: Int, needle: String, sequence mySequence: Int) async {
        let key = "\(make.lowercased())-\(year)"
        var models = cache[key]

        if models == nil {
            do {
                models = try await provider.models(make: make, modelYear: year)
            } catch let error as ProviderError {
                guard mySequence == sequence else { return }
                if error == .cancelled { return }
                state = .offline(error.errorDescription ?? "The vehicle lookup service is not available.")
                return
            } catch {
                guard mySequence == sequence else { return }
                state = .offline("The vehicle lookup service is not available.")
                return
            }
            cache[key] = models
        }

        // An answer for an older keystroke is discarded rather than shown: a
        // slow reply must never overwrite a newer selection.
        guard mySequence == sequence else { return }

        let all = models ?? []
        let needleLowered = needle.lowercased()
        let filtered = needleLowered.isEmpty
            ? all
            : all.filter { $0.lowercased().contains(needleLowered) }

        let results = filtered
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map {
                VehicleSearchResult(modelYear: year, make: make, model: $0, origin: .referenceSourced)
            }

        if results.isEmpty {
            state = .empty(
                all.isEmpty
                    ? "The vehicle service had no models for \(make) in \(year)."
                    : "No \(year) \(make) model matched “\(needle)”."
            )
        } else {
            state = .results(results)
        }
    }

    private func hint(for parsed: ParsedVehicleQuery) -> String {
        if parsed.modelYear == nil && parsed.make == nil {
            return "Try a year and a make — “2010 Jeep”."
        }
        if parsed.modelYear == nil {
            return "Add the model year — “2010 \(parsed.make ?? "")”."
        }
        return "Add the make — “\(parsed.modelYear.map(String.init) ?? "") Jeep”."
    }
}
