import XCTest
@testable import Odomind
import OdomindCore

@MainActor
final class AppModelTests: XCTestCase {

    private var scratchDirectories: [URL] = []

    override func tearDown() {
        for directory in scratchDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        scratchDirectories = []
        super.tearDown()
    }

    private func makeModel(now: Date = appDate(2026, 6, 15)) throws -> (AppModel, InMemoryNotificationScheduler) {
        let built = try AppFixture.makeModel(now: now)
        scratchDirectories.append(built.attachmentsDirectory)
        return (built.model, built.scheduler)
    }

    // MARK: - The main journey

    func testAddVehicleRecordMileageLogServiceAndSeeNextDue() throws {
        let (model, _) = try makeModel()

        let vehicleID = try XCTUnwrap(model.addVehicle(from: AppFixture.draft()))
        XCTAssertEqual(model.snapshot.vehicles.count, 1)
        XCTAssertEqual(model.selectedVehicleID, vehicleID)
        XCTAssertEqual(model.latestReading(for: vehicleID)?.value, Distance(120_000, .miles))

        // Nothing is due yet, because nothing has been logged — and the app says
        // that rather than pretending everything was just serviced.
        let oil = try XCTUnwrap(
            model.evaluations(for: vehicleID).first { $0.definitionID == "engine-oil-and-filter" }
        )
        XCTAssertEqual(oil.state, .needsSetup)

        // Log an oil change at 120,000.
        var draft = ServiceDraft(
            vehicleID: vehicleID,
            performedOn: appDate(2026, 6, 15),
            odometerAmount: 120_000,
            currencyCode: "USD"
        )
        draft.selectedPlanItemIDs = [oil.planItemID]
        draft.totalCostText = "89.97"
        XCTAssertNotNil(model.saveService(draft))

        let after = try XCTUnwrap(
            model.evaluations(for: vehicleID).first { $0.definitionID == "engine-oil-and-filter" }
        )
        XCTAssertEqual(after.state, .upcoming)
        XCTAssertEqual(after.nextDueOdometer, Distance(125_000, .miles))
        XCTAssertNotNil(after.nextDueDate)

        // The visit's cost is counted once.
        let records = model.serviceRecords(for: vehicleID)
        XCTAssertEqual(records.count, 1)
        guard case .single(let total) = model.spending(for: records) else {
            return XCTFail("expected a single currency total")
        }
        XCTAssertEqual(total.amount, Decimal(string: "89.97")!)
    }

    func testUpdatingMileageMovesTheTaskTowardsDue() throws {
        let (model, _) = try makeModel()
        let vehicleID = try XCTUnwrap(model.addVehicle(from: AppFixture.draft()))
        let oil = try XCTUnwrap(
            model.evaluations(for: vehicleID).first { $0.definitionID == "engine-oil-and-filter" }
        )

        var draft = ServiceDraft(
            vehicleID: vehicleID,
            performedOn: appDate(2026, 6, 15),
            odometerAmount: 120_000,
            currencyCode: "USD"
        )
        draft.selectedPlanItemIDs = [oil.planItemID]
        _ = model.saveService(draft)

        XCTAssertTrue(model.recordOdometer(vehicleID: vehicleID, amount: 124_800, on: appDate(2026, 6, 15)))

        let updated = try XCTUnwrap(
            model.evaluations(for: vehicleID).first { $0.definitionID == "engine-oil-and-filter" }
        )
        XCTAssertEqual(updated.state, .dueSoon)
        XCTAssertEqual(updated.distanceRemaining, Distance(200, .miles))
    }

    func testEditingAServiceRecordRecomputesTheSchedule() throws {
        let (model, _) = try makeModel()
        let vehicleID = try XCTUnwrap(model.addVehicle(from: AppFixture.draft()))
        let oil = try XCTUnwrap(
            model.evaluations(for: vehicleID).first { $0.definitionID == "engine-oil-and-filter" }
        )

        var draft = ServiceDraft(
            vehicleID: vehicleID,
            performedOn: appDate(2026, 6, 1),
            odometerAmount: 120_000,
            currencyCode: "USD"
        )
        draft.selectedPlanItemIDs = [oil.planItemID]
        let recordID = try XCTUnwrap(model.saveService(draft))
        XCTAssertEqual(
            model.evaluation(planItemID: oil.planItemID)?.nextDueOdometer,
            Distance(125_000, .miles)
        )

        // Correct the odometer on that visit; the due point must follow.
        draft.editingRecordID = recordID
        draft.odometerAmount = 118_000
        _ = model.saveService(draft)

        XCTAssertEqual(model.snapshot.serviceRecords.count, 1, "editing must not create a second record")
        XCTAssertEqual(
            model.evaluation(planItemID: oil.planItemID)?.nextDueOdometer,
            Distance(123_000, .miles)
        )
    }

    func testDeletingAServiceRecordRestoresTheEarlierSchedule() async throws {
        let (model, _) = try makeModel()
        let vehicleID = try XCTUnwrap(model.addVehicle(from: AppFixture.draft()))
        let oil = try XCTUnwrap(
            model.evaluations(for: vehicleID).first { $0.definitionID == "engine-oil-and-filter" }
        )

        var draft = ServiceDraft(
            vehicleID: vehicleID,
            performedOn: appDate(2026, 6, 1),
            odometerAmount: 120_000,
            currencyCode: "USD"
        )
        draft.selectedPlanItemIDs = [oil.planItemID]
        let recordID = try XCTUnwrap(model.saveService(draft))

        await model.deleteService(id: recordID)
        let after = try XCTUnwrap(model.evaluation(planItemID: oil.planItemID))
        XCTAssertEqual(after.state, .needsSetup, "with no completion there is nothing to schedule from")
        XCTAssertNil(after.nextDueOdometer)
    }

    func testFutureDatedServiceIsRefusedWithAnExplanation() throws {
        let (model, _) = try makeModel()
        let vehicleID = try XCTUnwrap(model.addVehicle(from: AppFixture.draft()))
        let oil = try XCTUnwrap(
            model.evaluations(for: vehicleID).first { $0.definitionID == "engine-oil-and-filter" }
        )

        var draft = ServiceDraft(
            vehicleID: vehicleID,
            performedOn: appDate(2027, 1, 1),
            odometerAmount: 121_000,
            currencyCode: "USD"
        )
        draft.selectedPlanItemIDs = [oil.planItemID]

        XCTAssertNil(model.saveService(draft))
        XCTAssertNotNil(model.alert)
        XCTAssertTrue(model.snapshot.serviceRecords.isEmpty)
    }

    func testCostParsingAcceptsEitherDecimalSeparator() {
        XCTAssertEqual(AppModel.parseAmount("89.97"), Decimal(string: "89.97"))
        XCTAssertEqual(AppModel.parseAmount("89,97"), Decimal(string: "89.97"))
        XCTAssertEqual(AppModel.parseAmount("$1200"), Decimal(string: "1200"))
        XCTAssertNil(AppModel.parseAmount("1.2.3"))
        XCTAssertNil(AppModel.parseAmount("abc"))
    }

    // MARK: - Vehicle isolation

    func testEditingOneVehicleNeverChangesAnother() throws {
        let (model, _) = try makeModel()
        let first = try XCTUnwrap(model.addVehicle(from: AppFixture.draft(make: "Jeep", model: "Wrangler")))
        let second = try XCTUnwrap(
            model.addVehicle(from: AppFixture.draft(make: "Honda", model: "Civic", odometer: 20_000))
        )

        let firstOil = try XCTUnwrap(
            model.evaluations(for: first).first { $0.definitionID == "engine-oil-and-filter" }
        )
        var draft = ServiceDraft(
            vehicleID: first,
            performedOn: appDate(2026, 6, 1),
            odometerAmount: 120_000,
            currencyCode: "USD"
        )
        draft.selectedPlanItemIDs = [firstOil.planItemID]
        _ = model.saveService(draft)

        let secondOil = try XCTUnwrap(
            model.evaluations(for: second).first { $0.definitionID == "engine-oil-and-filter" }
        )
        XCTAssertEqual(secondOil.state, .needsSetup, "the second vehicle has no history of its own")
        XCTAssertNil(secondOil.nextDueOdometer)
        XCTAssertEqual(model.latestReading(for: second)?.value, Distance(20_000, .miles))
    }

    // MARK: - Unknown history

    func testUnknownHistoryIsItsOwnGroupAndNeverOverdue() throws {
        let (model, _) = try makeModel()
        var draft = AppFixture.draft(taskIDs: ["engine-oil-and-filter"])
        draft.baselines["engine-oil-and-filter"] = .unknownToOwner
        let vehicleID = try XCTUnwrap(model.addVehicle(from: draft))

        let oil = try XCTUnwrap(
            model.evaluations(for: vehicleID).first { $0.definitionID == "engine-oil-and-filter" }
        )
        XCTAssertEqual(oil.state, .historyUnknown)

        let groups = model.grouped(for: vehicleID).map(\.state)
        XCTAssertTrue(groups.contains(.historyUnknown))
        XCTAssertFalse(groups.contains(.overdue))
    }

    func testStartTrackingFromTodayRecordsAStartingPointNotAService() throws {
        let (model, _) = try makeModel()
        var draft = AppFixture.draft(taskIDs: ["engine-oil-and-filter"])
        draft.baselines["engine-oil-and-filter"] = .unknownToOwner
        let vehicleID = try XCTUnwrap(model.addVehicle(from: draft))
        let oil = try XCTUnwrap(
            model.evaluations(for: vehicleID).first { $0.definitionID == "engine-oil-and-filter" }
        )

        model.startTrackingFromToday(planItemID: oil.planItemID)

        XCTAssertTrue(model.snapshot.serviceRecords.isEmpty, "no service record may be invented")
        let after = try XCTUnwrap(model.evaluation(planItemID: oil.planItemID))
        XCTAssertEqual(after.state, .upcoming)
        XCTAssertEqual(after.nextDueOdometer, Distance(125_000, .miles))
    }

    // MARK: - Odometer corrections

    func testAnOdometerDecreaseIsFlaggedNotAccepted() throws {
        let (model, _) = try makeModel()
        let vehicleID = try XCTUnwrap(model.addVehicle(from: AppFixture.draft()))
        let vehicle = try XCTUnwrap(model.snapshot.vehicle(id: vehicleID))

        let issues = model.odometerIssues(for: vehicle, proposedAmount: 900, on: appDate(2026, 6, 15))
        XCTAssertTrue(issues.contains { if case .decreasedFromEarlier = $0 { return true }; return false })
    }

    func testRecordingAnOdometerReplacementKeepsTheSchedule() throws {
        let (model, _) = try makeModel()
        // Every reading before the replacement, so the ledger is exercised the
        // way it happens in life: old unit, swap, new unit starting at zero.
        var vehicleDraft = AppFixture.draft()
        vehicleDraft.odometerDate = appDate(2026, 5, 1)
        let vehicleID = try XCTUnwrap(model.addVehicle(from: vehicleDraft))
        let oil = try XCTUnwrap(
            model.evaluations(for: vehicleID).first { $0.definitionID == "engine-oil-and-filter" }
        )

        var draft = ServiceDraft(
            vehicleID: vehicleID,
            performedOn: appDate(2026, 5, 1),
            odometerAmount: 120_000,
            currencyCode: "USD"
        )
        draft.selectedPlanItemIDs = [oil.planItemID]
        _ = model.saveService(draft)

        model.recordOdometerReplacement(
            vehicleID: vehicleID,
            occurredOn: appDate(2026, 6, 10),
            previousFinalReading: 121_000,
            newStartReading: 0,
            note: "Cluster replaced"
        )
        XCTAssertTrue(model.recordOdometer(vehicleID: vehicleID, amount: 500, on: appDate(2026, 6, 14)))

        let after = try XCTUnwrap(model.evaluation(planItemID: oil.planItemID))
        // 121,500 cumulative against a 125,000 due point.
        XCTAssertEqual(after.nextDueOdometer, Distance(125_000, .miles))
        XCTAssertEqual(after.distanceRemaining, Distance(3_500, .miles))
    }

    // MARK: - Sample content

    func testSampleContentIsSeparateAndRemovable() async throws {
        let (model, _) = try makeModel()
        model.addDemoContent()

        XCTAssertTrue(model.hasDemoContent)
        let demo = try XCTUnwrap(model.snapshot.vehicles.first(where: \.isDemo))
        XCTAssertTrue(model.snapshot.serviceRecords(for: demo.id).allSatisfy(\.isDemo))
        XCTAssertNil(demo.identity.vin, "sample content must never carry a VIN")

        let real = try XCTUnwrap(model.addVehicle(from: AppFixture.draft()))
        await model.removeDemoContent()

        XCTAssertFalse(model.hasDemoContent)
        XCTAssertEqual(model.snapshot.vehicles.map(\.id), [real], "removing the sample must not touch real records")
    }

    func testSampleContentIsNotAddedTwice() throws {
        let (model, _) = try makeModel()
        model.addDemoContent()
        model.addDemoContent()
        XCTAssertEqual(model.snapshot.vehicles.filter(\.isDemo).count, 1)
    }

    // MARK: - Deleting everything

    func testDeleteAllDataClearsRecordsAndReminders() async throws {
        let (model, scheduler) = try makeModel()
        _ = model.addVehicle(from: AppFixture.draft())
        await model.deleteAllData()

        XCTAssertTrue(model.snapshot.vehicles.isEmpty)
        XCTAssertTrue(model.snapshot.serviceRecords.isEmpty)
        let pending = await scheduler.pending()
        XCTAssertTrue(pending.isEmpty)
    }
}
