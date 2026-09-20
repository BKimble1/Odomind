import XCTest
@testable import OdomindCore

final class DistanceRuleTests: XCTestCase {
    let today = makeDate(2026, 6, 15)

    func testDueInDistanceAfterCompletion() {
        let item = Fixture.planItem(rule: .distance(interval: Distance(5_000, .miles)))
        let context = Fixture.context(
            readings: [Fixture.reading(52_000, on: makeDate(2026, 6, 10))],
            services: [Fixture.service(on: makeDate(2026, 1, 10), odometer: 48_000)],
            asOf: today
        )
        let result = ScheduleEngine.evaluate(item, in: context)

        XCTAssertEqual(result.state, .upcoming)
        XCTAssertEqual(result.basis, .distance)
        XCTAssertEqual(result.nextDueOdometer, Distance(53_000, .miles))
        XCTAssertEqual(result.distanceRemaining, Distance(1_000, .miles))
        XCTAssertEqual(result.lastCompletedOdometer, Distance(48_000, .miles))
    }

    func testExactBoundaryIsDueNotOverdue() {
        // Reaching the due odometer exactly counts as due now, not as "999 to go".
        let item = Fixture.planItem(rule: .distance(interval: Distance(5_000, .miles)))
        let context = Fixture.context(
            readings: [Fixture.reading(53_000, on: makeDate(2026, 6, 14))],
            services: [Fixture.service(on: makeDate(2026, 1, 10), odometer: 48_000)],
            asOf: today
        )
        let result = ScheduleEngine.evaluate(item, in: context)
        XCTAssertEqual(result.state, .overdue)
        XCTAssertEqual(result.distanceRemaining, Distance(0, .miles))
    }

    func testOneUnitBeforeBoundaryIsDueSoonNotOverdue() {
        let item = Fixture.planItem(rule: .distance(interval: Distance(5_000, .miles)))
        let context = Fixture.context(
            readings: [Fixture.reading(52_999, on: makeDate(2026, 6, 14))],
            services: [Fixture.service(on: makeDate(2026, 1, 10), odometer: 48_000)],
            asOf: today
        )
        let result = ScheduleEngine.evaluate(item, in: context)
        XCTAssertEqual(result.state, .dueSoon)
        XCTAssertEqual(result.distanceRemaining, Distance(1, .miles))
    }

    func testDueSoonThresholdBoundary() {
        // 500 miles remaining with a 500-mile window is due soon; 501 is not.
        func state(atOdometer odometer: Int) -> DueState {
            let item = Fixture.planItem(rule: .distance(interval: Distance(5_000, .miles)))
            let context = Fixture.context(
                readings: [Fixture.reading(odometer, on: makeDate(2026, 6, 14))],
                services: [Fixture.service(on: makeDate(2026, 1, 10), odometer: 48_000)],
                asOf: today
            )
            return ScheduleEngine.evaluate(item, in: context).state
        }
        XCTAssertEqual(state(atOdometer: 52_500), .dueSoon)
        XCTAssertEqual(state(atOdometer: 52_499), .upcoming)
    }

    func testKilometreVehicleWithMileTemplate() {
        // The catalog publishes 5,000 miles; the owner works in kilometres. The
        // remaining distance comes back in the owner's unit.
        let vehicle = Fixture.vehicle(unit: .kilometers)
        let item = Fixture.planItem(rule: .distance(interval: Distance(5_000, .miles)))
        let context = Fixture.context(
            vehicle: vehicle,
            readings: [Fixture.reading(80_000, on: makeDate(2026, 6, 10), unit: .kilometers)],
            services: [Fixture.service(on: makeDate(2026, 1, 10), odometer: 74_000, unit: .kilometers)],
            asOf: today
        )
        let result = ScheduleEngine.evaluate(item, in: context)
        XCTAssertEqual(result.distanceRemaining?.unit, .kilometers)
        // 74,000 km + 5,000 mi (8,047 km) = 82,047 km due; 2,047 km remaining.
        XCTAssertEqual(result.distanceRemaining?.amount, 2_047)
    }

    func testNoOdometerReadingMeansNeedsSetup() {
        let item = Fixture.planItem(rule: .distance(interval: Distance(5_000, .miles)))
        let context = Fixture.context(
            services: [Fixture.service(on: makeDate(2026, 1, 10), odometer: 48_000)],
            asOf: today
        )
        let result = ScheduleEngine.evaluate(item, in: context)
        XCTAssertEqual(result.state, .needsSetup)
        XCTAssertTrue(result.hasReason { $0 == .noOdometerReading })
    }
}

final class CalendarRuleTests: XCTestCase {
    let today = makeDate(2026, 6, 15)

    func testDueInDays() {
        let item = Fixture.planItem(rule: .time(interval: .months(6)))
        let context = Fixture.context(
            services: [Fixture.service(on: makeDate(2026, 1, 15), odometer: nil)],
            asOf: today
        )
        let result = ScheduleEngine.evaluate(item, in: context)
        XCTAssertEqual(result.state, .dueSoon)
        XCTAssertEqual(result.basis, .date)
        XCTAssertEqual(result.daysRemaining, 30, "2026-01-15 plus six months is 2026-07-15")
        XCTAssertTrue(result.hasReason { $0 == .dueInDays(30) })
    }

    func testOverdueByDays() {
        let item = Fixture.planItem(rule: .time(interval: .months(6)))
        let context = Fixture.context(
            services: [Fixture.service(on: makeDate(2025, 12, 1), odometer: nil)],
            asOf: today
        )
        let result = ScheduleEngine.evaluate(item, in: context)
        XCTAssertEqual(result.state, .overdue)
        XCTAssertEqual(result.daysRemaining, -14)
        XCTAssertTrue(result.hasReason { $0 == .overdueByDays(14) })
    }

    func testMonthEndServiceDateClampsCorrectly() {
        // Serviced 31 August, due six months later on 28 February.
        let item = Fixture.planItem(rule: .time(interval: .months(6)))
        let context = Fixture.context(
            services: [Fixture.service(on: makeDate(2025, 8, 31), odometer: nil)],
            asOf: makeDate(2026, 2, 27)
        )
        let result = ScheduleEngine.evaluate(item, in: context)
        XCTAssertEqual(result.daysRemaining, 1)
    }

    func testTimeZoneAffectsWhichDayADeadlineFallsOn() {
        // A deadline late on 30 June UTC is still "today" in New York.
        let item = Fixture.planItem(rule: .time(interval: .months(6)))
        let utcContext = Fixture.context(
            services: [Fixture.service(on: makeDate(2025, 12, 31, hour: 23, calendar: .utc), odometer: nil)],
            asOf: makeDate(2026, 6, 30, hour: 20, calendar: .utc),
            calendar: .utc
        )
        let utcResult = ScheduleEngine.evaluate(item, in: utcContext)
        XCTAssertEqual(utcResult.daysRemaining, 0)

        let nyCalendar = Calendar.fixed("America/New_York")
        let nyContext = Fixture.context(
            services: [Fixture.service(on: makeDate(2025, 12, 31, hour: 23, calendar: .utc), odometer: nil)],
            asOf: makeDate(2026, 6, 30, hour: 20, calendar: .utc),
            calendar: nyCalendar
        )
        let nyResult = ScheduleEngine.evaluate(item, in: nyContext)
        // 31 December 23:00 UTC is 18:00 on 31 December in New York, so the
        // six-month deadline is 30 June there too.
        XCTAssertEqual(nyResult.daysRemaining, 0)
    }
}

final class EitherFirstRuleTests: XCTestCase {
    let today = makeDate(2026, 6, 15)

    func testDistanceWinsWhenReachedFirst() {
        let item = Fixture.planItem(rule: .distanceOrTime(distance: Distance(5_000, .miles), time: .months(6)))
        let context = Fixture.context(
            readings: [Fixture.reading(53_500, on: makeDate(2026, 6, 14))],
            services: [Fixture.service(on: makeDate(2026, 5, 1), odometer: 48_000)],
            asOf: today
        )
        let result = ScheduleEngine.evaluate(item, in: context)
        XCTAssertEqual(result.state, .overdue)
        XCTAssertEqual(result.basis, .distance)
    }

    func testTimeWinsWhenReachedFirst() {
        let item = Fixture.planItem(rule: .distanceOrTime(distance: Distance(5_000, .miles), time: .months(6)))
        let context = Fixture.context(
            readings: [Fixture.reading(48_500, on: makeDate(2026, 6, 14))],
            services: [Fixture.service(on: makeDate(2025, 11, 1), odometer: 48_000)],
            asOf: today
        )
        let result = ScheduleEngine.evaluate(item, in: context)
        XCTAssertEqual(result.state, .overdue)
        XCTAssertEqual(result.basis, .date)
    }

    func testBothOverdueReportsBothAsTheBasis() {
        let item = Fixture.planItem(rule: .distanceOrTime(distance: Distance(5_000, .miles), time: .months(6)))
        let context = Fixture.context(
            readings: [Fixture.reading(60_000, on: makeDate(2026, 6, 14))],
            services: [Fixture.service(on: makeDate(2025, 1, 1), odometer: 48_000)],
            asOf: today
        )
        let result = ScheduleEngine.evaluate(item, in: context)
        XCTAssertEqual(result.state, .overdue)
        XCTAssertEqual(result.basis, .both)
    }

    func testCalendarSideStillWorksWithoutAnyOdometerReading() {
        // "5,000 miles or 6 months" is still useful to an owner who has not
        // entered a reading: the calendar half keeps running.
        let item = Fixture.planItem(rule: .distanceOrTime(distance: Distance(5_000, .miles), time: .months(6)))
        let context = Fixture.context(
            services: [Fixture.service(on: makeDate(2025, 11, 1), odometer: nil)],
            asOf: today
        )
        let result = ScheduleEngine.evaluate(item, in: context)
        XCTAssertEqual(result.state, .overdue)
        XCTAssertEqual(result.basis, .date)
        XCTAssertTrue(result.hasReason { $0 == .noOdometerReading })
    }
}

final class UnknownHistoryTests: XCTestCase {
    let today = makeDate(2026, 6, 15)

    func testNoHistoryIsNeedsSetupNotUpToDate() {
        let item = Fixture.planItem(rule: .distanceOrTime(distance: Distance(5_000, .miles), time: .months(6)))
        let context = Fixture.context(
            readings: [Fixture.reading(52_000, on: makeDate(2026, 6, 10))],
            asOf: today
        )
        let result = ScheduleEngine.evaluate(item, in: context)
        XCTAssertEqual(result.state, .needsSetup)
        XCTAssertTrue(result.hasReason { $0 == .noCompletionRecorded })
        XCTAssertNil(result.nextDueDate)
        XCTAssertNil(result.nextDueOdometer)
    }

    func testOwnerSaidTheyDoNotKnowIsItsOwnState() {
        let item = Fixture.planItem(
            rule: .distanceOrTime(distance: Distance(5_000, .miles), time: .months(6)),
            baseline: .unknownToOwner
        )
        let context = Fixture.context(
            readings: [Fixture.reading(52_000, on: makeDate(2026, 6, 10))],
            asOf: today
        )
        let result = ScheduleEngine.evaluate(item, in: context)
        XCTAssertEqual(result.state, .historyUnknown)
        XCTAssertNotEqual(result.state, .upcoming)
        XCTAssertNotEqual(result.state, .overdue)
        XCTAssertTrue(result.hasReason { $0 == .ownerDoesNotKnowHistory })
    }

    func testDeclaredStartingPointSchedulesWithoutAServiceRecord() {
        let item = Fixture.planItem(
            rule: .distanceOrTime(distance: Distance(5_000, .miles), time: .months(6)),
            baseline: .declared(date: makeDate(2026, 3, 1), odometer: Distance(50_000, .miles))
        )
        let context = Fixture.context(
            readings: [Fixture.reading(52_000, on: makeDate(2026, 6, 10))],
            asOf: today
        )
        let result = ScheduleEngine.evaluate(item, in: context)
        XCTAssertEqual(result.state, .upcoming)
        XCTAssertEqual(result.nextDueOdometer, Distance(55_000, .miles))
        XCTAssertEqual(result.distanceRemaining, Distance(3_000, .miles))
    }
}

final class FixedMilestoneTests: XCTestCase {
    let today = makeDate(2026, 6, 15)

    private func milestoneItem(
        threshold: DueSoonThreshold = DueSoonThreshold(distance: Distance(500, .miles), days: 30)
    ) -> MaintenancePlanItem {
        Fixture.planItem(
            definitionID: "major-service-milestone",
            title: "Major service checkpoint",
            rule: .fixedMilestones(
                FixedMilestoneSchedule(
                    distanceMilestones: [Distance(30_000, .miles), Distance(60_000, .miles), Distance(90_000, .miles)],
                    repeatEvery: Distance(30_000, .miles)
                )
            ),
            threshold: threshold
        )
    }

    func testEarlyServiceDoesNotMoveTheNextMilestone() {
        // Done at 55,000 — well before the 60,000 milestone — so 60,000 still
        // stands. This is the behaviour that separates a milestone schedule
        // from an ordinary interval.
        let context = Fixture.context(
            readings: [Fixture.reading(58_000, on: makeDate(2026, 6, 10))],
            services: [
                Fixture.service(on: makeDate(2025, 1, 1), odometer: 30_100, definitionIDs: ["major-service-milestone"]),
                Fixture.service(on: makeDate(2026, 2, 1), odometer: 55_000, definitionIDs: ["major-service-milestone"])
            ],
            asOf: today
        )
        let result = ScheduleEngine.evaluate(milestoneItem(), in: context)
        XCTAssertEqual(result.nextDueOdometer, Distance(60_000, .miles))
        XCTAssertEqual(result.state, .upcoming)
    }

    func testServiceJustBeforeAMilestoneCounts() {
        // 59,700 is inside the 500-mile due-soon window, so the 60,000
        // milestone is satisfied and the next one is 90,000.
        let context = Fixture.context(
            readings: [Fixture.reading(61_000, on: makeDate(2026, 6, 10))],
            services: [
                Fixture.service(on: makeDate(2025, 1, 1), odometer: 30_100, definitionIDs: ["major-service-milestone"]),
                Fixture.service(on: makeDate(2026, 2, 1), odometer: 59_700, definitionIDs: ["major-service-milestone"])
            ],
            asOf: today
        )
        let result = ScheduleEngine.evaluate(milestoneItem(), in: context)
        XCTAssertEqual(result.nextDueOdometer, Distance(90_000, .miles))
    }

    func testAMissedMilestoneIsOverdueRatherThanSkipped() {
        // Never serviced, now at 65,000: the 30,000 milestone is the first one
        // outstanding, and it is long past.
        let context = Fixture.context(
            readings: [Fixture.reading(65_000, on: makeDate(2026, 6, 10))],
            asOf: today
        )
        let result = ScheduleEngine.evaluate(milestoneItem(), in: context)
        XCTAssertEqual(result.state, .overdue)
        XCTAssertEqual(result.nextDueOdometer, Distance(30_000, .miles))
        XCTAssertTrue(result.hasReason { $0 == .milestoneAlreadyPassed(Distance(30_000, .miles)) })
    }

    func testMilestonesWorkWithoutAnyCompletionHistory() {
        // Anchored to the vehicle, not to a completion, so a brand new owner
        // still gets a real answer.
        let context = Fixture.context(
            readings: [Fixture.reading(12_000, on: makeDate(2026, 6, 10))],
            asOf: today
        )
        let result = ScheduleEngine.evaluate(milestoneItem(), in: context)
        XCTAssertEqual(result.state, .upcoming)
        XCTAssertEqual(result.nextDueOdometer, Distance(30_000, .miles))
        XCTAssertNotEqual(result.state, .needsSetup)
    }

    func testRepeatExtendsBeyondTheListedMilestones() {
        let context = Fixture.context(
            readings: [Fixture.reading(155_000, on: makeDate(2026, 6, 10))],
            services: [
                Fixture.service(on: makeDate(2026, 1, 1), odometer: 150_200, definitionIDs: ["major-service-milestone"])
            ],
            asOf: today
        )
        let result = ScheduleEngine.evaluate(milestoneItem(), in: context)
        XCTAssertEqual(result.nextDueOdometer, Distance(180_000, .miles))
    }

    func testNextUnmetMilestoneIsPureAndBounded() {
        let schedule = FixedMilestoneSchedule(
            distanceMilestones: [Distance(10_000, .miles)],
            repeatEvery: Distance(10_000, .miles)
        )
        let next = ScheduleEngine.nextUnmetMilestone(
            schedule: schedule,
            current: Distance(1_000_000, .miles),
            tolerance: Distance(0, .miles),
            completions: []
        )
        XCTAssertEqual(next, Distance(10_000, .miles))
    }
}

final class ConditionAndIndicatorTests: XCTestCase {
    let today = makeDate(2026, 6, 15)

    func testConditionCheckIsLabelledAsInspectionOnly() {
        let item = Fixture.planItem(
            definitionID: "brake-inspection",
            title: "Brake inspection",
            rule: .conditionCheck(every: RecurrenceBasis(distance: Distance(6_000, .miles), time: .months(6)))
        )
        let context = Fixture.context(
            readings: [Fixture.reading(52_000, on: makeDate(2026, 6, 10))],
            services: [Fixture.service(on: makeDate(2026, 5, 1), odometer: 51_000, definitionIDs: ["brake-inspection"])],
            asOf: today
        )
        let result = ScheduleEngine.evaluate(item, in: context)
        XCTAssertEqual(result.state, .upcoming)
        XCTAssertTrue(result.hasReason { $0 == .inspectionIntervalOnly })
    }

    func testIndicatorWithoutABackstopIsWatchedNotOverdue() {
        let item = Fixture.planItem(
            definitionID: "oil-life-monitor",
            title: "Oil life monitor reading",
            rule: .vehicleIndicator(VehicleIndicatorSchedule(indicatorName: "Oil Change Required"))
        )
        let context = Fixture.context(
            readings: [Fixture.reading(52_000, on: makeDate(2026, 6, 10))],
            asOf: today
        )
        let result = ScheduleEngine.evaluate(item, in: context)
        XCTAssertEqual(result.state, .upcoming)
        XCTAssertEqual(result.basis, .indicator)
        XCTAssertTrue(result.hasReason { $0 == .indicatorNotReported("Oil Change Required") })
    }

    func testIndicatorBackstopBecomesDueWhenExceeded() {
        let item = Fixture.planItem(
            definitionID: "oil-life-monitor",
            title: "Oil life monitor reading",
            rule: .vehicleIndicator(
                VehicleIndicatorSchedule(
                    indicatorName: "Oil Change Required",
                    maximumDistance: Distance(10_000, .miles),
                    maximumTime: .months(12)
                )
            )
        )
        let context = Fixture.context(
            readings: [Fixture.reading(62_000, on: makeDate(2026, 6, 10))],
            services: [
                Fixture.service(on: makeDate(2025, 1, 1), odometer: 48_000, definitionIDs: ["oil-life-monitor"])
            ],
            asOf: today
        )
        let result = ScheduleEngine.evaluate(item, in: context)
        XCTAssertEqual(result.state, .overdue)
        XCTAssertTrue(result.hasReason { $0 == .indicatorBackstop })
    }
}

final class OneTimeRuleTests: XCTestCase {
    let today = makeDate(2026, 6, 15)

    func testOneTimeTaskBecomesCompleted() {
        let item = Fixture.planItem(
            definitionID: "first-service-inspection",
            title: "First service inspection",
            rule: .oneTime(atDistance: Distance(1_000, .miles), atAge: .months(3))
        )
        let context = Fixture.context(
            vehicle: Fixture.vehicle(inServiceOn: makeDate(2026, 1, 1)),
            readings: [Fixture.reading(2_000, on: makeDate(2026, 6, 10))],
            services: [
                Fixture.service(on: makeDate(2026, 2, 1), odometer: 950, definitionIDs: ["first-service-inspection"])
            ],
            asOf: today
        )
        let result = ScheduleEngine.evaluate(item, in: context)
        XCTAssertEqual(result.state, .completed)
    }

    func testOneTimeTaskNeedsAnInServiceDateForItsAgeSide() {
        let item = Fixture.planItem(
            definitionID: "first-service-inspection",
            title: "First service inspection",
            rule: .oneTime(atDistance: nil, atAge: .months(3))
        )
        let context = Fixture.context(
            readings: [Fixture.reading(2_000, on: makeDate(2026, 6, 10))],
            asOf: today
        )
        let result = ScheduleEngine.evaluate(item, in: context)
        XCTAssertEqual(result.state, .needsSetup)
        XCTAssertTrue(result.hasReason { $0 == .inServiceDateUnknown })
    }
}

final class SnoozeTests: XCTestCase {
    let today = makeDate(2026, 6, 15)

    func testSnoozeDoesNotMakeOverdueWorkLookDone() {
        let item = Fixture.planItem(
            rule: .time(interval: .months(6)),
            snoozedUntil: makeDate(2026, 7, 1)
        )
        let context = Fixture.context(
            services: [Fixture.service(on: makeDate(2025, 1, 1), odometer: nil)],
            asOf: today
        )
        let result = ScheduleEngine.evaluate(item, in: context)
        XCTAssertEqual(result.state, .overdue, "a snooze must not clear an overdue state")
        XCTAssertTrue(result.isSnoozed)
        XCTAssertEqual(result.snoozedUntil, makeDate(2026, 7, 1))
        XCTAssertTrue(result.hasReason { $0 == .snoozedUntil(makeDate(2026, 7, 1)) })
    }

    func testExpiredSnoozeIsNoLongerApplied() {
        let item = Fixture.planItem(
            rule: .time(interval: .months(6)),
            snoozedUntil: makeDate(2026, 5, 1)
        )
        let context = Fixture.context(
            services: [Fixture.service(on: makeDate(2025, 1, 1), odometer: nil)],
            asOf: today
        )
        let result = ScheduleEngine.evaluate(item, in: context)
        XCTAssertFalse(result.isSnoozed)
    }
}

final class CompletionSelectionTests: XCTestCase {
    let today = makeDate(2026, 6, 15)

    func testLoggingAnOlderServiceDoesNotDisplaceTheNewestOne() {
        let item = Fixture.planItem(rule: .distance(interval: Distance(5_000, .miles)))
        let newest = Fixture.service(on: makeDate(2026, 5, 1), odometer: 52_000)
        let forgotten = Fixture.service(on: makeDate(2024, 3, 1), odometer: 30_000)

        let context = Fixture.context(
            readings: [Fixture.reading(53_000, on: makeDate(2026, 6, 10))],
            services: [newest, forgotten],
            asOf: today
        )
        let result = ScheduleEngine.evaluate(item, in: context)
        XCTAssertEqual(result.lastCompletedOdometer, Distance(52_000, .miles))
        XCTAssertEqual(result.nextDueOdometer, Distance(57_000, .miles))
        XCTAssertEqual(result.state, .upcoming)
    }

    func testDeletingTheNewestServiceRecomputesFromTheOneBefore() {
        let item = Fixture.planItem(rule: .distance(interval: Distance(5_000, .miles)))
        let older = Fixture.service(on: makeDate(2025, 6, 1), odometer: 45_000)
        let newest = Fixture.service(on: makeDate(2026, 5, 1), odometer: 52_000)

        let before = ScheduleEngine.evaluate(
            item,
            in: Fixture.context(
                readings: [Fixture.reading(53_000, on: makeDate(2026, 6, 10))],
                services: [older, newest],
                asOf: today
            )
        )
        XCTAssertEqual(before.nextDueOdometer, Distance(57_000, .miles))

        let after = ScheduleEngine.evaluate(
            item,
            in: Fixture.context(
                readings: [Fixture.reading(53_000, on: makeDate(2026, 6, 10))],
                services: [older],
                asOf: today
            )
        )
        XCTAssertEqual(after.nextDueOdometer, Distance(50_000, .miles))
        XCTAssertEqual(after.state, .overdue)
    }

    func testAMultiTaskVisitCompletesEveryTaskInIt() {
        let oil = Fixture.planItem(definitionID: "engine-oil-and-filter", rule: .distance(interval: Distance(5_000, .miles)))
        let rotation = Fixture.planItem(
            definitionID: "tire-rotation",
            title: "Tire rotation",
            rule: .distance(interval: Distance(6_000, .miles))
        )
        let visit = Fixture.service(
            on: makeDate(2026, 5, 1),
            odometer: 52_000,
            definitionIDs: ["engine-oil-and-filter", "tire-rotation"]
        )
        let context = Fixture.context(
            readings: [Fixture.reading(53_000, on: makeDate(2026, 6, 10))],
            services: [visit],
            asOf: today
        )
        XCTAssertEqual(ScheduleEngine.evaluate(oil, in: context).nextDueOdometer, Distance(57_000, .miles))
        XCTAssertEqual(ScheduleEngine.evaluate(rotation, in: context).nextDueOdometer, Distance(58_000, .miles))
    }
}

final class GroupingAndOrderingTests: XCTestCase {
    let today = makeDate(2026, 6, 15)

    func testEvaluationsSortMostUrgentFirstAndGroupByState() {
        let overdue = Fixture.planItem(definitionID: "a", title: "Overdue task", rule: .time(interval: .months(1)))
        let soon = Fixture.planItem(definitionID: "b", title: "Soon task", rule: .time(interval: .months(6)))
        let later = Fixture.planItem(definitionID: "c", title: "Later task", rule: .time(interval: .years(2)))
        let unset = Fixture.planItem(definitionID: "d", title: "Unset task", rule: .time(interval: .months(6)))

        let services = [
            Fixture.service(on: makeDate(2026, 1, 1), odometer: nil, definitionIDs: ["a"]),
            Fixture.service(on: makeDate(2026, 1, 1), odometer: nil, definitionIDs: ["b"]),
            Fixture.service(on: makeDate(2026, 1, 1), odometer: nil, definitionIDs: ["c"])
        ]
        let context = Fixture.context(services: services, asOf: today)
        let results = ScheduleEngine.evaluateAll([later, unset, overdue, soon], in: context)

        XCTAssertEqual(results.map(\.title), ["Overdue task", "Soon task", "Later task", "Unset task"])

        let groups = ScheduleEngine.grouped(results)
        XCTAssertEqual(groups.map(\.state), [.overdue, .dueSoon, .upcoming, .needsSetup])
    }

    func testDisabledTasksAreNotApplicable() {
        var item = Fixture.planItem(rule: .time(interval: .months(1)))
        item.isEnabled = false
        let context = Fixture.context(services: [Fixture.service(on: makeDate(2020, 1, 1), odometer: nil)], asOf: today)
        XCTAssertEqual(ScheduleEngine.evaluate(item, in: context).state, .notApplicable)
    }
}
