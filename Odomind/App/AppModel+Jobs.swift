import Foundation
import OdomindCore

/// One hit from the Jobs search.
///
/// A tracked job and an untracked one both appear, marked, so searching for
/// "oil" finds the owner's oil change *and* the cabin filter they have not
/// added yet — without offering to add a second copy of something already in
/// the plan.
struct JobSearchResult: Identifiable, Hashable {
    var id: String { definitionID }
    var definitionID: String
    var title: String
    var purpose: String
    var category: MaintenanceCategory
    /// Set when this job is already in the plan.
    var planItemID: UUID?
    var state: DueState?
    var isAdvanced: Bool
    var isCustom: Bool

    var isTracked: Bool { planItemID != nil }
}

extension AppModel {

    // MARK: - Searching

    /// Everything matching a query: tracked jobs first, then the rest of the
    /// library.
    ///
    /// Matching goes through the catalog's own keyword list, so "lube",
    /// "oil change" and "service" all reach the oil job, and a custom job the
    /// owner wrote is searched by its title.
    func searchJobs(query: String, vehicle: Vehicle, includeUntracked: Bool = true) -> [JobSearchResult] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let definitions = catalogService.catalog?.definitionsByID ?? [:]
        let evaluations = Dictionary(
            evaluations(for: vehicle.id).map { ($0.planItemID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var results: [JobSearchResult] = []
        var trackedDefinitionIDs: Set<String> = []

        for item in snapshot.planItems(for: vehicle.id) {
            trackedDefinitionIDs.insert(item.definitionID)
            let matches: Bool
            if needle.isEmpty {
                matches = true
            } else if let definition = definitions[item.definitionID] {
                matches = definition.matches(query: needle) || item.title.lowercased().contains(needle)
            } else {
                // A custom job has no catalog entry, so its own words are all
                // there is to search.
                matches = item.title.lowercased().contains(needle)
                    || item.purpose.lowercased().contains(needle)
            }
            guard matches else { continue }
            results.append(
                JobSearchResult(
                    definitionID: item.definitionID,
                    title: item.title,
                    purpose: item.purpose,
                    category: item.category,
                    planItemID: item.id,
                    state: evaluations[item.id]?.state,
                    isAdvanced: definitions[item.definitionID]?.isAdvanced ?? false,
                    isCustom: item.isCustom
                )
            )
        }

        if includeUntracked, !needle.isEmpty {
            for suggestion in allSuggestions(for: vehicle) where !trackedDefinitionIDs.contains(suggestion.definition.id) {
                guard suggestion.definition.matches(query: needle) else { continue }
                results.append(
                    JobSearchResult(
                        definitionID: suggestion.definition.id,
                        title: suggestion.definition.title,
                        purpose: suggestion.definition.purpose,
                        category: suggestion.definition.category,
                        planItemID: nil,
                        state: nil,
                        isAdvanced: suggestion.definition.isAdvanced,
                        isCustom: false
                    )
                )
            }
        }

        // Tracked first, then by how much attention the job wants, then by
        // title so the order is stable between keystrokes.
        return results.sorted { left, right in
            if left.isTracked != right.isTracked { return left.isTracked }
            let leftRank = left.state?.sortRank ?? Int.max
            let rightRank = right.state?.sortRank ?? Int.max
            if leftRank != rightRank { return leftRank < rightRank }
            return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
        }
    }

    // MARK: - The agenda

    /// The few things on Home worth showing.
    ///
    /// Only jobs with something to act on: overdue, due soon, and the nearest
    /// upcoming ones. A job whose history is unknown is deliberately not here —
    /// fifteen of those on the home screen is the backlog the brief asked to
    /// be rid of, and the empty state says the useful thing about them instead.
    func upNext(for vehicle: Vehicle, limit: Int = 4) -> [ScheduleEvaluation] {
        evaluations(for: vehicle.id)
            .filter { $0.state == .overdue || $0.state == .dueSoon || $0.state == .upcoming }
            .sorted { $0.urgencyKey < $1.urgencyKey }
            .prefix(limit)
            .map { $0 }
    }

    /// How many things sit on one day, for the week strip's dot and the
    /// month grid.
    func calendarDayLoad(_ day: Date) -> Int {
        calendarEntries(on: day).count
    }

    // MARK: - Quick logging

    /// Records one job as done, with the date and mileage the owner confirmed.
    ///
    /// Goes through `saveService` like every other recording, so the plan,
    /// the calendar and the reminders all recompute exactly once and in the
    /// same order as a full visit.
    @discardableResult
    func quickLog(
        vehicleID: UUID,
        planItemIDs: Set<UUID>,
        performedOn: Date,
        odometerAmount: Int?,
        performer: ServicePerformer,
        totalCostText: String,
        notes: String
    ) -> UUID? {
        guard snapshot.vehicle(id: vehicleID) != nil else { return nil }
        var draft = ServiceDraft(
            vehicleID: vehicleID,
            performedOn: performedOn,
            odometerAmount: odometerAmount,
            currencyCode: Locale.current.currency?.identifier ?? "USD"
        )
        draft.selectedPlanItemIDs = planItemIDs
        draft.performer = performer
        draft.totalCostText = totalCostText
        draft.notes = notes
        return saveService(draft)
    }
}
