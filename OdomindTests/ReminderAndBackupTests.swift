import XCTest
@testable import Odomind
import OdomindCore

@MainActor
final class ReminderCoordinatorTests: XCTestCase {

    private var scratchDirectories: [URL] = []

    override func tearDown() {
        for directory in scratchDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        scratchDirectories = []
        super.tearDown()
    }

    private func makeModel() throws -> (AppModel, InMemoryNotificationScheduler) {
        let built = try AppFixture.makeModel()
        scratchDirectories.append(built.attachmentsDirectory)
        return (built.model, built.scheduler)
    }

    /// Adds a vehicle with one task that has a real calendar deadline and a
    /// reminder switched on.
    private func makeVehicleWithReminder(_ model: AppModel) throws -> (vehicleID: UUID, planItemID: UUID) {
        let vehicleID = try XCTUnwrap(model.addVehicle(from: AppFixture.draft(taskIDs: ["engine-oil-and-filter"])))
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
        _ = model.saveService(draft)
        model.setReminder(ReminderPreference(isEnabled: true, leadDays: 7, hour: 9), planItemID: oil.planItemID)
        return (vehicleID, oil.planItemID)
    }

    func testNothingIsScheduledUntilRemindersAreTurnedOn() async throws {
        let (model, scheduler) = try makeModel()
        _ = try makeVehicleWithReminder(model)
        await model.syncReminders()

        let pending = await scheduler.pending()
        XCTAssertTrue(pending.isEmpty)
        XCTAssertEqual(scheduler.authorizationRequestCount, 0, "permission must not be requested on its own")
    }

    func testEnablingRemindersRequestsPermissionThenSchedules() async throws {
        let (model, scheduler) = try makeModel()
        _ = try makeVehicleWithReminder(model)

        scheduler.authorization = .notDetermined
        let granted = await model.enableReminders()
        XCTAssertTrue(granted)
        XCTAssertEqual(scheduler.authorizationRequestCount, 1)

        let pending = await scheduler.pending()
        XCTAssertEqual(pending.count, 1)
    }

    func testDeniedPermissionLeavesTheAppWorkingAndSaysSo() async throws {
        let (model, scheduler) = try makeModel()
        _ = try makeVehicleWithReminder(model)

        scheduler.authorization = .notDetermined
        scheduler.grantsAuthorization = false
        let granted = await model.enableReminders()

        XCTAssertFalse(granted)
        XCTAssertNotNil(model.alert, "a denied permission has to be explained, not silently swallowed")
        XCTAssertFalse(model.snapshot.settings.reminders.remindersEnabled)
        let pending = await scheduler.pending()
        XCTAssertTrue(pending.isEmpty)
    }

    func testRepeatedSyncsDoNotStackDuplicates() async throws {
        let (model, scheduler) = try makeModel()
        _ = try makeVehicleWithReminder(model)
        _ = await model.enableReminders()

        let first = await scheduler.pending()
        await model.syncReminders()
        await model.syncReminders()
        let after = await scheduler.pending()

        XCTAssertEqual(after.count, first.count)
        XCTAssertEqual(Set(after.map(\.id)).count, after.count)
        XCTAssertEqual(model.reminderReport.scheduled, 0, "a no-op sync should schedule nothing new")
        XCTAssertGreaterThan(model.reminderReport.unchanged, 0)
    }

    func testTurningRemindersOffCancelsEverythingPending() async throws {
        let (model, scheduler) = try makeModel()
        _ = try makeVehicleWithReminder(model)
        _ = await model.enableReminders()
        let whileEnabled = await scheduler.pending()
        XCTAssertFalse(whileEnabled.isEmpty)

        await model.disableReminders()
        let afterDisabling = await scheduler.pending()
        XCTAssertTrue(afterDisabling.isEmpty)
    }

    func testDeletingAVehicleCancelsItsReminders() async throws {
        let (model, scheduler) = try makeModel()
        let (vehicleID, _) = try makeVehicleWithReminder(model)
        _ = await model.enableReminders()
        let beforeDeleting = await scheduler.pending()
        XCTAssertFalse(beforeDeleting.isEmpty)

        await model.deleteVehicle(id: vehicleID)
        let afterDeleting = await scheduler.pending()
        XCTAssertTrue(afterDeleting.isEmpty, "a deleted vehicle must not keep firing notifications")
    }

    func testLoggingServiceMovesTheReminderRatherThanAddingOne() async throws {
        let (model, scheduler) = try makeModel()
        let (vehicleID, planItemID) = try makeVehicleWithReminder(model)
        _ = await model.enableReminders()

        let pendingBefore = await scheduler.pending()
        let before = try XCTUnwrap(pendingBefore.first)

        var draft = ServiceDraft(
            vehicleID: vehicleID,
            performedOn: appDate(2026, 6, 14),
            odometerAmount: 121_000,
            currencyCode: "USD"
        )
        draft.selectedPlanItemIDs = [planItemID]
        _ = model.saveService(draft)
        await model.syncReminders()

        let after = await scheduler.pending()
        XCTAssertEqual(after.count, 1, "the reminder moved; it did not multiply")
        XCTAssertNotEqual(after[0].fireDate, before.fireDate)
        XCTAssertEqual(after[0].id, before.id, "the identifier is stable across recomputation")
    }

    func testSnoozeDelaysTheReminderWithoutClearingTheDueState() async throws {
        let (model, scheduler) = try makeModel()
        let (_, planItemID) = try makeVehicleWithReminder(model)
        _ = await model.enableReminders()
        let pendingBefore = await scheduler.pending()
        let before = try XCTUnwrap(pendingBefore.first)

        model.snooze(planItemID: planItemID, until: appDate(2027, 1, 1))
        await model.syncReminders()

        let pendingAfter = await scheduler.pending()
        let after = try XCTUnwrap(pendingAfter.first)
        XCTAssertGreaterThan(after.fireDate, before.fireDate)
        XCTAssertTrue(model.evaluation(planItemID: planItemID)?.isSnoozed ?? false)
    }
}

@MainActor
final class BackupRoundTripTests: XCTestCase {

    private var scratchDirectories: [URL] = []

    override func tearDown() {
        for directory in scratchDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        scratchDirectories = []
        super.tearDown()
    }

    private func makeModel() throws -> AppModel {
        let built = try AppFixture.makeModel()
        scratchDirectories.append(built.attachmentsDirectory)
        return built.model
    }

    /// A tiny valid JPEG so the attachment path is exercised for real.
    private var sampleImage: Data {
        Data([
            0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
            0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xD9
        ])
    }

    private func populate(_ model: AppModel) throws -> UUID {
        let vehicleID = try XCTUnwrap(model.addVehicle(from: AppFixture.draft()))
        let oil = try XCTUnwrap(
            model.evaluations(for: vehicleID).first { $0.definitionID == "engine-oil-and-filter" }
        )
        let attachmentID = try XCTUnwrap(model.addAttachment(data: sampleImage, contentType: "image/jpeg"))

        var draft = ServiceDraft(
            vehicleID: vehicleID,
            performedOn: appDate(2026, 6, 1),
            odometerAmount: 120_000,
            currencyCode: "USD"
        )
        draft.selectedPlanItemIDs = [oil.planItemID]
        draft.totalCostText = "89.97"
        draft.attachmentIDs = [attachmentID]
        draft.notes = "Corner Garage, with a receipt"
        _ = model.saveService(draft)

        model.saveSpecification(
            Specification(kind: .engineOilViscosity, value: .text("5W-20"), provenance: .userEntered),
            for: vehicleID
        )
        return vehicleID
    }

    func testBackupAndRestoreReproducesTheGarage() async throws {
        let source = try makeModel()
        let vehicleID = try populate(source)

        let archive = source.backupService.makeArchive(
            from: source.snapshot,
            includeAttachments: true,
            includeDemoContent: false,
            appVersion: "test",
            now: appDate(2026, 6, 15)
        )
        XCTAssertEqual(archive.attachments.count, 1)
        XCTAssertNotNil(archive.attachments.first?.decodedData())

        // Round-trip through the file format, not just the object.
        let encoded = try archive.encoded()
        let decoded = try BackupArchive.decode(encoded)

        let destination = try makeModel()
        let applied = await destination.applyImport(archive: decoded, strategy: .replaceEverything)
        XCTAssertTrue(applied, "unexpected alert: \(String(describing: destination.alert))")

        XCTAssertEqual(destination.snapshot.vehicles.count, 1)
        XCTAssertEqual(destination.snapshot.vehicles.first?.id, vehicleID)
        XCTAssertEqual(destination.snapshot.serviceRecords.count, source.snapshot.serviceRecords.count)
        XCTAssertEqual(
            destination.snapshot.serviceRecords.first?.totalCost?.amount,
            Decimal(string: "89.97")!
        )
        XCTAssertEqual(destination.snapshot.specifications(for: vehicleID).count, 1)

        let restoredAttachmentID = try XCTUnwrap(destination.snapshot.serviceRecords.first?.attachmentIDs.first)
        XCTAssertEqual(destination.attachmentData(restoredAttachmentID), sampleImage)

        // And the schedule comes out the same on the other side.
        XCTAssertEqual(
            destination.evaluations(for: vehicleID).first { $0.definitionID == "engine-oil-and-filter" }?.nextDueOdometer,
            source.evaluations(for: vehicleID).first { $0.definitionID == "engine-oil-and-filter" }?.nextDueOdometer
        )
    }

    func testRestoringWithoutAttachmentsKeepsTheRecords() async throws {
        let source = try makeModel()
        _ = try populate(source)

        let archive = source.backupService.makeArchive(
            from: source.snapshot,
            includeAttachments: false,
            includeDemoContent: false,
            appVersion: "test",
            now: appDate(2026, 6, 15)
        )

        let destination = try makeModel()
        let applied = await destination.applyImport(archive: archive, strategy: .replaceEverything)
        XCTAssertTrue(applied)
        XCTAssertEqual(destination.snapshot.serviceRecords.count, 1)
        XCTAssertTrue(
            destination.snapshot.serviceRecords.first?.attachmentIDs.isEmpty ?? false,
            "a record must not point at a receipt that was not restored"
        )
    }

    func testMergeSkipsRecordsAlreadyPresent() async throws {
        let source = try makeModel()
        _ = try populate(source)
        let archive = source.backupService.makeArchive(
            from: source.snapshot,
            includeAttachments: true,
            includeDemoContent: false,
            appVersion: "test",
            now: appDate(2026, 6, 15)
        )

        let before = source.snapshot.serviceRecords.count
        let applied = await source.applyImport(archive: archive, strategy: .addMissingOnly)
        XCTAssertTrue(applied)
        XCTAssertEqual(source.snapshot.serviceRecords.count, before, "restoring your own backup must not duplicate it")
        XCTAssertEqual(source.snapshot.vehicles.count, 1)
    }

    func testAnInvalidFileIsRejectedWithoutTouchingAnything() async throws {
        let model = try makeModel()
        _ = try populate(model)
        let before = model.snapshot.vehicles.count

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        scratchDirectories.append(directory)
        let url = directory.appendingPathComponent("broken.odomindbackup")
        try Data("this is not a backup".utf8).write(to: url)

        XCTAssertNil(model.previewImport(from: url, strategy: .replaceEverything))
        XCTAssertNotNil(model.alert)
        XCTAssertEqual(model.snapshot.vehicles.count, before, "a bad file must not delete anything")
    }

    func testCSVExportHasOneRowPerVisit() throws {
        let model = try makeModel()
        _ = try populate(model)
        let file = try XCTUnwrap(model.exportHistoryCSV(vehicleIDs: nil, includeDemoContent: false))
        defer { model.clearExports() }

        let csv = try String(contentsOf: file.url, encoding: .utf8)
        let lines = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 2, "header plus one visit")
        XCTAssertTrue(lines[1].contains("89.97"))
    }

    func testPDFExportProducesAReadableDocument() throws {
        let model = try makeModel()
        let vehicleID = try populate(model)
        let file = try XCTUnwrap(
            model.exportHistoryPDF(vehicleID: vehicleID, includeVIN: false, includeDemoContent: false)
        )
        defer { model.clearExports() }

        let data = try Data(contentsOf: file.url)
        XCTAssertGreaterThan(data.count, 1_000)
        XCTAssertEqual(data.prefix(4), Data("%PDF".utf8))
    }

    func testAttachmentsAreCleanedUpWhenARecordIsDeleted() async throws {
        let model = try makeModel()
        _ = try populate(model)

        let recordID = try XCTUnwrap(model.snapshot.serviceRecords.first?.id)
        let metadata = try XCTUnwrap(model.snapshot.attachments.first)
        XCTAssertTrue(model.attachments.exists(metadata))

        await model.deleteService(id: recordID)

        XCTAssertTrue(model.snapshot.attachments.isEmpty)
        XCTAssertFalse(model.attachments.exists(metadata), "the file should be gone, not just the record of it")
    }
}
