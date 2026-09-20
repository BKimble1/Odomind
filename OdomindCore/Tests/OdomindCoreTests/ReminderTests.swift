import XCTest
@testable import OdomindCore

final class ReminderPlannerTests: XCTestCase {
    let calendar = Calendar.utc
    let now = makeDate(2026, 6, 15, hour: 8)

    private func settings(
        enabled: Bool = true,
        mileageReminders: Bool = false,
        estimates: Bool = true
    ) -> ReminderSettings {
        ReminderSettings(
            remindersEnabled: enabled,
            mileageUpdateRemindersEnabled: mileageReminders,
            mileageUpdateIntervalDays: 30,
            preferredHour: 9,
            preferredMinute: 0,
            includeEstimatedMileageReminders: estimates
        )
    }

    private func deadlineScenario(
        leadDays: Int = 7,
        reminderEnabled: Bool = true,
        snoozedUntil: Date? = nil
    ) -> (vehicle: Vehicle, item: MaintenancePlanItem, evaluation: ScheduleEvaluation) {
        let vehicle = Fixture.vehicle()
        var item = Fixture.planItem(
            rule: .time(interval: .months(6)),
            snoozedUntil: snoozedUntil,
            reminder: ReminderPreference(isEnabled: reminderEnabled, leadDays: leadDays, hour: 9, minute: 0)
        )
        item.title = "Engine oil and filter"
        let context = Fixture.context(
            vehicle: vehicle,
            services: [Fixture.service(on: makeDate(2026, 1, 15), odometer: nil)],
            asOf: now
        )
        return (vehicle, item, ScheduleEngine.evaluate(item, in: context))
    }

    func testNoRemindersWhenTheFeatureIsOff() {
        let scenario = deadlineScenario()
        let requests = ReminderPlanner.plan(
            vehicle: scenario.vehicle,
            evaluations: [scenario.evaluation],
            planItems: [scenario.item],
            settings: settings(enabled: false),
            lastOdometerUpdate: nil,
            now: now,
            calendar: calendar
        )
        XCTAssertTrue(requests.isEmpty)
    }

    func testDeadlineReminderFiresAtThePreferredTimeOnTheLeadDay() {
        let scenario = deadlineScenario(leadDays: 7)
        // Serviced 15 January, six months later is 15 July, minus seven days is
        // 8 July at 09:00 local.
        let requests = ReminderPlanner.plan(
            vehicle: scenario.vehicle,
            evaluations: [scenario.evaluation],
            planItems: [scenario.item],
            settings: settings(),
            lastOdometerUpdate: nil,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(requests.count, 1)
        let request = requests[0]
        XCTAssertEqual(request.kind, .calendarDeadline)
        XCTAssertEqual(request.fireDate, makeDate(2026, 7, 8, hour: 9, calendar: calendar))
        XCTAssertEqual(request.id, ReminderRequest.identifier(planItemID: scenario.item.id, kind: .calendarDeadline))
        XCTAssertTrue(request.deepLink.hasPrefix("odomind://vehicle/"))
    }

    func testAPastLeadDayGivesOneNudgeRatherThanFiringImmediately() {
        let vehicle = Fixture.vehicle()
        var item = Fixture.planItem(
            rule: .time(interval: .months(6)),
            reminder: ReminderPreference(isEnabled: true, leadDays: 7, hour: 9, minute: 0)
        )
        item.title = "Overdue job"
        let context = Fixture.context(
            vehicle: vehicle,
            services: [Fixture.service(on: makeDate(2025, 6, 1), odometer: nil)],
            asOf: now
        )
        let evaluation = ScheduleEngine.evaluate(item, in: context)
        XCTAssertEqual(evaluation.state, .overdue)

        let requests = ReminderPlanner.plan(
            vehicle: vehicle,
            evaluations: [evaluation],
            planItems: [item],
            settings: settings(),
            lastOdometerUpdate: nil,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(requests.count, 1)
        // "Now" is 08:00, so the next 09:00 is today.
        XCTAssertEqual(requests[0].fireDate, makeDate(2026, 6, 15, hour: 9, calendar: calendar))
    }

    func testSnoozePushesTheReminderOutWithoutChangingTheDueDate() {
        let snoozeUntil = makeDate(2026, 7, 20, hour: 12)
        let scenario = deadlineScenario(leadDays: 7, snoozedUntil: snoozeUntil)
        XCTAssertEqual(scenario.evaluation.state, .dueSoon)
        XCTAssertTrue(scenario.evaluation.isSnoozed)

        let requests = ReminderPlanner.plan(
            vehicle: scenario.vehicle,
            evaluations: [scenario.evaluation],
            planItems: [scenario.item],
            settings: settings(),
            lastOdometerUpdate: nil,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(requests.count, 1)
        XCTAssertGreaterThan(requests[0].fireDate, snoozeUntil)
        XCTAssertEqual(requests[0].fireDate, makeDate(2026, 7, 21, hour: 9, calendar: calendar))
    }

    func testDisabledPerTaskReminderProducesNothing() {
        let scenario = deadlineScenario(reminderEnabled: false)
        let requests = ReminderPlanner.plan(
            vehicle: scenario.vehicle,
            evaluations: [scenario.evaluation],
            planItems: [scenario.item],
            settings: settings(),
            lastOdometerUpdate: nil,
            now: now,
            calendar: calendar
        )
        XCTAssertTrue(requests.isEmpty)
    }

    func testEstimatedReminderNeedsAConfidentEstimateAndNoRealDeadline() {
        let vehicle = Fixture.vehicle()
        var item = Fixture.planItem(
            rule: .distance(interval: Distance(10_000, .miles)),
            reminder: ReminderPreference(isEnabled: true, leadDays: 7, hour: 9, minute: 0)
        )
        item.title = "Engine oil and filter"
        let context = Fixture.context(
            vehicle: vehicle,
            readings: [
                Fixture.reading(50_000, on: makeDate(2026, 1, 1)),
                Fixture.reading(51_500, on: makeDate(2026, 2, 20)),
                Fixture.reading(53_000, on: makeDate(2026, 4, 10)),
                Fixture.reading(54_500, on: makeDate(2026, 5, 30))
            ],
            services: [Fixture.service(on: makeDate(2025, 12, 20), odometer: 50_000)],
            asOf: now
        )
        let evaluation = ScheduleEngine.evaluate(item, in: context)
        XCTAssertNil(evaluation.nextDueDate)
        XCTAssertNotNil(evaluation.estimatedDueDate)

        let requests = ReminderPlanner.plan(
            vehicle: vehicle,
            evaluations: [evaluation],
            planItems: [item],
            settings: settings(),
            lastOdometerUpdate: nil,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].kind, .estimatedMileage)
        XCTAssertTrue(requests[0].body.lowercased().contains("estimated"), "an estimated reminder must say so")

        let withoutEstimates = ReminderPlanner.plan(
            vehicle: vehicle,
            evaluations: [evaluation],
            planItems: [item],
            settings: settings(estimates: false),
            lastOdometerUpdate: nil,
            now: now,
            calendar: calendar
        )
        XCTAssertTrue(withoutEstimates.isEmpty)
    }

    func testMileageUpdateReminder() {
        let vehicle = Fixture.vehicle()
        let requests = ReminderPlanner.plan(
            vehicle: vehicle,
            evaluations: [],
            planItems: [],
            settings: settings(mileageReminders: true),
            lastOdometerUpdate: makeDate(2026, 6, 1),
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].kind, .mileageUpdate)
        XCTAssertEqual(requests[0].id, ReminderRequest.mileageIdentifier(vehicleID: vehicle.id))
        XCTAssertEqual(requests[0].fireDate, makeDate(2026, 7, 1, hour: 9, calendar: calendar))
    }

    func testBoundingKeepsTheNearestRemindersAndDeduplicates() {
        let vehicleID = UUID()
        var requests: [ReminderRequest] = []
        for index in 0..<120 {
            requests.append(
                ReminderRequest(
                    id: "task.\(index)",
                    vehicleID: vehicleID,
                    planItemID: nil,
                    kind: .calendarDeadline,
                    fireDate: makeDate(2026, 6, 16).addingTimeInterval(Double(index) * 86_400),
                    title: "T\(index)",
                    body: "B",
                    deepLink: "odomind://vehicle/\(vehicleID.uuidString)"
                )
            )
        }
        // A duplicate identifier with a later date must not displace the earlier one.
        requests.append(
            ReminderRequest(
                id: "task.0",
                vehicleID: vehicleID,
                planItemID: nil,
                kind: .calendarDeadline,
                fireDate: makeDate(2027, 1, 1),
                title: "T0 later",
                body: "B",
                deepLink: "odomind://vehicle/\(vehicleID.uuidString)"
            )
        )

        let bounded = ReminderPlanner.bounded(requests)
        XCTAssertEqual(bounded.count, ReminderPlanner.maximumPendingRequests)
        XCTAssertEqual(Set(bounded.map(\.id)).count, bounded.count, "identifiers must be unique")
        XCTAssertEqual(bounded.first?.id, "task.0")
        XCTAssertEqual(bounded.first?.fireDate, makeDate(2026, 6, 16))
        XCTAssertEqual(bounded, bounded.sorted { $0.fireDate < $1.fireDate })
    }

    func testReconciliationSchedulesCancelsAndLeavesUnchanged() {
        let vehicleID = UUID()
        func request(_ id: String, _ date: Date) -> ReminderRequest {
            ReminderRequest(
                id: id,
                vehicleID: vehicleID,
                planItemID: nil,
                kind: .calendarDeadline,
                fireDate: date,
                title: id,
                body: "B",
                deepLink: "odomind://vehicle/\(vehicleID.uuidString)"
            )
        }

        let desired = [
            request("keep", makeDate(2026, 7, 1, hour: 9)),
            request("moved", makeDate(2026, 8, 1, hour: 9)),
            request("new", makeDate(2026, 9, 1, hour: 9))
        ]
        let pending = [
            PendingReminder(id: "keep", fireDate: makeDate(2026, 7, 1, hour: 9)),
            PendingReminder(id: "moved", fireDate: makeDate(2026, 8, 15, hour: 9)),
            PendingReminder(id: "gone", fireDate: makeDate(2026, 6, 20, hour: 9))
        ]

        let result = ReminderPlanner.reconcile(desired: desired, pending: pending)
        XCTAssertEqual(result.unchanged, ["keep"])
        XCTAssertEqual(result.toSchedule.map(\.id), ["moved", "new"])
        XCTAssertEqual(result.toCancel, ["gone"])
    }

    func testReconcilingAnEmptyPlanCancelsEverything() {
        let pending = [
            PendingReminder(id: "a", fireDate: makeDate(2026, 7, 1)),
            PendingReminder(id: "b", fireDate: makeDate(2026, 8, 1))
        ]
        let result = ReminderPlanner.reconcile(desired: [], pending: pending)
        XCTAssertEqual(result.toCancel, ["a", "b"])
        XCTAssertTrue(result.toSchedule.isEmpty)
    }

    func testSchedulingIsIdempotent() {
        let scenario = deadlineScenario()
        let first = ReminderPlanner.plan(
            vehicle: scenario.vehicle,
            evaluations: [scenario.evaluation],
            planItems: [scenario.item],
            settings: settings(),
            lastOdometerUpdate: nil,
            now: now,
            calendar: calendar
        )
        let pending = first.map { PendingReminder(id: $0.id, fireDate: $0.fireDate) }
        let second = ReminderPlanner.reconcile(desired: first, pending: pending)
        XCTAssertTrue(second.isEmpty, "recomputing without changes must not re-register anything")
    }

    func testRemindersRespectTheOwnersTimeZone() {
        let nyCalendar = Calendar.fixed("America/New_York")
        let vehicle = Fixture.vehicle()
        var item = Fixture.planItem(
            rule: .time(interval: .months(6)),
            reminder: ReminderPreference(isEnabled: true, leadDays: 7, hour: 9, minute: 0)
        )
        item.title = "Engine oil and filter"
        let context = Fixture.context(
            vehicle: vehicle,
            services: [Fixture.service(on: makeDate(2026, 1, 15), odometer: nil)],
            asOf: now,
            calendar: nyCalendar
        )
        let evaluation = ScheduleEngine.evaluate(item, in: context)
        let requests = ReminderPlanner.plan(
            vehicle: vehicle,
            evaluations: [evaluation],
            planItems: [item],
            settings: settings(),
            lastOdometerUpdate: nil,
            now: now,
            calendar: nyCalendar
        )
        XCTAssertEqual(requests.count, 1)
        // 09:00 in New York on 8 July 2026 is 13:00 UTC (EDT is UTC-4).
        XCTAssertEqual(requests[0].fireDate, makeDate(2026, 7, 8, hour: 13, calendar: .utc))
    }
}

final class DeepLinkTests: XCTestCase {

    func testRoundTrip() {
        let vehicleID = UUID()
        let planItemID = UUID()
        let cases: [DeepLink] = [
            .vehicle(id: vehicleID),
            .task(vehicleID: vehicleID, planItemID: planItemID),
            .updateMileage(vehicleID: vehicleID),
            .logService(vehicleID: vehicleID)
        ]
        for link in cases {
            let parsed = DeepLink(urlString: link.urlString)
            XCTAssertEqual(parsed, link, "failed to round-trip \(link.urlString)")
        }
    }

    func testRejectsForeignOrMalformedLinks() {
        XCTAssertNil(DeepLink(urlString: "https://example.com/vehicle/123"))
        XCTAssertNil(DeepLink(urlString: "odomind://other/123"))
        XCTAssertNil(DeepLink(urlString: "odomind://vehicle/not-a-uuid"))
        XCTAssertNil(DeepLink(urlString: "odomind://vehicle/\(UUID().uuidString)/task/nope"))
    }
}
