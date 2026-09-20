import EventKit
import XCTest
@testable import Odomind
import OdomindCore

final class CalendarServiceTests: XCTestCase {

    private let calendar = Calendar.fixedUTC()

    private func draft(isEstimated: Bool) -> CalendarEventDraft? {
        CalendarService.makeEventDraft(
            title: "Engine oil and filter",
            vehicleName: "The Jeep",
            dueDate: appDate(2026, 7, 15, hour: 14),
            isEstimated: isEstimated,
            scheduleSummary: "Every 5,000 miles or 6 months, whichever comes first",
            calendar: calendar
        )
    }

    func testEventIsAllDayAndSpansOneDay() throws {
        let draft = try XCTUnwrap(self.draft(isEstimated: false))
        let event = draft.event

        XCTAssertTrue(event.isAllDay)
        XCTAssertEqual(event.startDate, calendar.startOfDay(for: appDate(2026, 7, 15)))
        XCTAssertEqual(
            event.endDate,
            calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: appDate(2026, 7, 15)))
        )
        XCTAssertEqual(event.title, "Engine oil and filter — The Jeep")
    }

    func testNotesSayThatTheEventIsASnapshot() throws {
        let draft = try XCTUnwrap(self.draft(isEstimated: false))
        let notes = try XCTUnwrap(draft.event.notes)

        XCTAssertTrue(notes.contains("Every 5,000 miles"), "the schedule should travel with the event")
        XCTAssertTrue(
            notes.lowercased().contains("will not update"),
            "the event must say Odomind cannot keep it in step: \(notes)"
        )
    }

    func testAnEstimatedDueDateSaysSoInTheEvent() throws {
        let draft = try XCTUnwrap(self.draft(isEstimated: true))
        let notes = try XCTUnwrap(draft.event.notes)
        XCTAssertTrue(
            notes.lowercased().contains("estimate"),
            "an event built from a projection must say so: \(notes)"
        )
    }

    func testAConfirmedDueDateDoesNotClaimToBeAnEstimate() throws {
        let draft = try XCTUnwrap(self.draft(isEstimated: false))
        let notes = try XCTUnwrap(draft.event.notes)
        XCTAssertFalse(notes.lowercased().contains("is an estimate"))
    }

    func testTheDraftKeepsItsStore() throws {
        // EventKit objects must not outlive the store they came from; the draft
        // exists to hold both for the lifetime of the editor sheet.
        let draft = try XCTUnwrap(self.draft(isEstimated: false))
        XCTAssertTrue(draft.store is EKEventStore)
    }
}

@MainActor
final class StoreTransactionTests: XCTestCase {

    private var scratchDirectories: [URL] = []

    override func tearDown() {
        for directory in scratchDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        scratchDirectories = []
        super.tearDown()
    }

    private struct WriterFailure: Error {}

    func testAFailedRestoreLeavesTheStoreUntouched() throws {
        let store = try OdomindStore(inMemory: true)

        let existing = Vehicle(
            nickname: "Keep me",
            identity: VehicleIdentity(modelYear: 2018, make: "Honda", model: "Civic"),
            createdAt: appDate(2026, 1, 1)
        )
        try store.save(vehicle: existing)
        try store.save(
            reading: OdometerReading(
                vehicleID: existing.id,
                recordedOn: appDate(2026, 5, 1),
                value: Distance(40_000, .miles)
            )
        )

        let incoming = Vehicle(
            nickname: "Should not land",
            identity: VehicleIdentity(modelYear: 2010, make: "Jeep", model: "Wrangler"),
            createdAt: appDate(2026, 1, 1)
        )
        let attachmentID = UUID()
        var record = ServiceRecord(
            vehicleID: incoming.id,
            performedOn: appDate(2026, 4, 1),
            items: [ServiceLineItem(definitionID: "engine-oil-and-filter", title: "Oil", action: .replace)],
            createdAt: appDate(2026, 4, 1),
            updatedAt: appDate(2026, 4, 1)
        )
        record.attachmentIDs = [attachmentID]

        let applySet = BackupApplySet(
            vehicles: [incoming],
            readings: [],
            planItems: [],
            serviceRecords: [record],
            specifications: [],
            attachments: [
                BackupAttachment.make(
                    id: attachmentID,
                    fileName: "receipt.jpg",
                    contentType: "image/jpeg",
                    data: Data([1, 2, 3])
                )
            ],
            settings: nil,
            removesExistingData: true
        )

        // The attachment writer fails part-way, which is the realistic failure:
        // the disk is full, or the file cannot be written.
        XCTAssertThrowsError(
            try store.apply(applySet) { _ in throw WriterFailure() }
        )

        let snapshot = try store.snapshot()
        XCTAssertEqual(snapshot.vehicles.map(\.nickname), ["Keep me"], "a failed restore must not delete what was there")
        XCTAssertEqual(snapshot.readings.count, 1)
        XCTAssertTrue(snapshot.serviceRecords.isEmpty, "nothing from the failed restore may be left behind")
        XCTAssertTrue(snapshot.attachments.isEmpty)
    }

    func testAFailedRestoreThroughTheAppModelKeepsTheGarageAndTheFiles() async throws {
        let built = try AppFixture.makeModel()
        scratchDirectories.append(built.attachmentsDirectory)
        let model = built.model

        let vehicleID = try XCTUnwrap(model.addVehicle(from: AppFixture.draft()))
        let before = try XCTUnwrap(model.snapshot.vehicle(id: vehicleID))

        // An archive whose only attachment fails its integrity check: the plan
        // refuses it outright rather than starting and stopping half way.
        var archive = model.backupService.makeArchive(
            from: model.snapshot,
            includeAttachments: true,
            includeDemoContent: false,
            appVersion: "test",
            now: appDate(2026, 6, 15)
        )
        archive.attachments = [
            BackupAttachment(
                id: UUID(),
                fileName: "broken.jpg",
                contentType: "image/jpeg",
                byteCount: 99,
                checksum: "deadbeef",
                base64Data: Data("nope".utf8).base64EncodedString()
            )
        ]

        let applied = await model.applyImport(archive: archive, strategy: .replaceEverything)
        XCTAssertFalse(applied)
        XCTAssertNotNil(model.alert)
        XCTAssertEqual(model.snapshot.vehicles.count, 1, "the existing garage must survive a refused restore")
        XCTAssertEqual(model.snapshot.vehicle(id: vehicleID), before)
    }
}
