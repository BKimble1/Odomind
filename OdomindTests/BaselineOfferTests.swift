import XCTest
@testable import Odomind
@testable import OdomindCore

/// When Odomind may offer to start tracking from today, and when doing so
/// would overwrite something the owner already told it.
///
/// Build 3's brief: "A baseline action belongs only where the baseline is
/// actually unknown; a vehicle with a known qualifying service must not be
/// offered a contradictory 'start tracking today' shortcut."
///
/// Build 2 asked whether the *baseline field* was empty, which is a different
/// question from whether the history is unknown. A job with a real recorded
/// service could still carry an empty baseline, so the screen printed "Last
/// done Mar 5, 2026 at 123,800 mi" and offered to start from today directly
/// underneath it. Accepting that offer wrote today over the owner's own
/// history.
@MainActor
final class BaselineOfferTests: XCTestCase {

    private let vehicleID = UUID()

    private func item(baseline: HistoryBaseline) -> MaintenancePlanItem {
        MaintenancePlanItem(
            vehicleID: vehicleID,
            definitionID: "engine-oil",
            title: "Engine oil and filter",
            category: .engine,
            action: .replace,
            baseline: baseline
        )
    }

    private func evaluation(
        for item: MaintenancePlanItem,
        state: DueState,
        lastCompletedOn: Date? = nil,
        lastCompletedOdometer: Distance? = nil
    ) -> ScheduleEvaluation {
        ScheduleEvaluation(
            planItemID: item.id,
            vehicleID: vehicleID,
            definitionID: item.definitionID,
            title: item.title,
            state: state,
            lastCompletedOn: lastCompletedOn,
            lastCompletedOdometer: lastCompletedOdometer
        )
    }

    // MARK: - Where the offer belongs

    func testTheOfferAppearsWhenNothingIsKnown() {
        let job = item(baseline: .notProvided)
        XCTAssertTrue(
            TaskDetailView.canStartTrackingFromToday(
                item: job,
                evaluation: evaluation(for: job, state: .needsSetup)
            )
        )
    }

    func testTheOfferAppearsWhenTheOwnerSaidTheyDoNotKnow() {
        // "I don't know" is exactly the case starting from today solves.
        let job = item(baseline: .unknownToOwner)
        XCTAssertTrue(
            TaskDetailView.canStartTrackingFromToday(
                item: job,
                evaluation: evaluation(for: job, state: .historyUnknown)
            )
        )
    }

    // MARK: - Where it would overwrite something

    func testARecordedServiceSuppressesTheOfferEvenWithAnEmptyBaseline() {
        // The exact Build 2 defect. The baseline field is empty and the
        // history is not: a service record is the baseline.
        let job = item(baseline: .notProvided)
        let evaluated = evaluation(
            for: job,
            state: .upcoming,
            lastCompletedOn: Date(timeIntervalSince1970: 1_770_000_000),
            lastCompletedOdometer: Distance(123_800, .miles)
        )
        XCTAssertFalse(
            TaskDetailView.canStartTrackingFromToday(item: job, evaluation: evaluated),
            "a job showing a completion must not also offer to invent one"
        )
    }

    func testAnOdometerOnlyCompletionIsStillACompletion() {
        let job = item(baseline: .notProvided)
        let evaluated = evaluation(
            for: job,
            state: .upcoming,
            lastCompletedOdometer: Distance(88_000, .miles)
        )
        XCTAssertFalse(TaskDetailView.canStartTrackingFromToday(item: job, evaluation: evaluated))
    }

    func testADateOnlyCompletionIsStillACompletion() {
        let job = item(baseline: .notProvided)
        let evaluated = evaluation(
            for: job,
            state: .upcoming,
            lastCompletedOn: Date(timeIntervalSince1970: 1_770_000_000)
        )
        XCTAssertFalse(TaskDetailView.canStartTrackingFromToday(item: job, evaluation: evaluated))
    }

    func testADeclaredStartingPointSuppressesTheOffer() {
        // The owner already supplied a starting point. Offering to replace it
        // with today is offering to throw it away.
        let job = item(
            baseline: .declared(
                date: Date(timeIntervalSince1970: 1_760_000_000),
                odometer: Distance(110_000, .miles)
            )
        )
        XCTAssertFalse(
            TaskDetailView.canStartTrackingFromToday(
                item: job,
                evaluation: evaluation(for: job, state: .upcoming)
            )
        )
    }
}
