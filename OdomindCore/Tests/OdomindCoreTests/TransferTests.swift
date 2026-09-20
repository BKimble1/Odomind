import XCTest
@testable import OdomindCore

final class CSVExportTests: XCTestCase {
    let calendar = Calendar.utc

    func testQuotingFollowsRFC4180() {
        XCTAssertEqual(CSVWriter.field("plain"), "plain")
        XCTAssertEqual(CSVWriter.field("has,comma"), "\"has,comma\"")
        XCTAssertEqual(CSVWriter.field("say \"hi\""), "\"say \"\"hi\"\"\"")
        XCTAssertEqual(CSVWriter.field("two\nlines"), "\"two\nlines\"")
    }

    func testOneRowPerVisitNotPerTask() {
        let vehicle = Fixture.vehicle()
        let record = Fixture.service(
            on: makeDate(2026, 5, 1),
            odometer: 52_000,
            definitionIDs: ["engine-oil-and-filter", "tire-rotation", "cabin-air-filter"],
            totalCost: Money(amount: Decimal(string: "89.97")!, currencyCode: "USD")
        )
        let csv = ServiceHistoryCSV.export(
            vehicles: [vehicle],
            records: [record],
            calendar: calendar
        )
        let lines = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 2, "one header row and one visit row")
        XCTAssertTrue(lines[1].contains("2026-05-01"))
        XCTAssertTrue(lines[1].contains("89.97"))
        XCTAssertEqual(lines[1].components(separatedBy: "89.97").count - 1, 1, "the total must appear exactly once")
        XCTAssertTrue(lines[1].contains("engine-oil-and-filter; tire-rotation; cabin-air-filter"))
    }

    func testDemoRecordsAreExcludedByDefault() {
        let vehicle = Fixture.vehicle()
        var demo = Fixture.service(on: makeDate(2026, 5, 1), odometer: 52_000)
        demo.isDemo = true
        let real = Fixture.service(on: makeDate(2026, 4, 1), odometer: 51_000)

        let withoutDemo = ServiceHistoryCSV.export(vehicles: [vehicle], records: [demo, real], calendar: calendar)
        XCTAssertEqual(withoutDemo.components(separatedBy: "\r\n").filter { !$0.isEmpty }.count, 2)

        let withDemo = ServiceHistoryCSV.export(
            vehicles: [vehicle],
            records: [demo, real],
            includeDemoContent: true,
            calendar: calendar
        )
        XCTAssertEqual(withDemo.components(separatedBy: "\r\n").filter { !$0.isEmpty }.count, 3)
    }

    func testNotesWithCommasSurviveTheRoundTrip() {
        let vehicle = Fixture.vehicle()
        var record = Fixture.service(on: makeDate(2026, 5, 1), odometer: 52_000)
        record.notes = "Oil, filter, and a quick look at the brakes"
        let csv = ServiceHistoryCSV.export(vehicles: [vehicle], records: [record], calendar: calendar)
        XCTAssertTrue(csv.contains("\"Oil, filter, and a quick look at the brakes\""))
    }
}

final class BackupTests: XCTestCase {
    let now = makeDate(2026, 6, 15)

    private func sampleArchive(
        attachmentData: Data? = Data("receipt-bytes".utf8),
        includeAttachmentPayload: Bool = true
    ) -> BackupArchive {
        let vehicle = Fixture.vehicle()
        let attachmentID = UUID()
        var record = Fixture.service(
            on: makeDate(2026, 5, 1),
            odometer: 52_000,
            totalCost: Money(amount: Decimal(string: "89.97")!, currencyCode: "USD")
        )
        record.attachmentIDs = attachmentData == nil ? [] : [attachmentID]

        var attachments: [BackupAttachment] = []
        if let attachmentData {
            var attachment = BackupAttachment.make(
                id: attachmentID,
                fileName: "receipt.jpg",
                contentType: "image/jpeg",
                data: attachmentData
            )
            if !includeAttachmentPayload { attachment.base64Data = nil }
            attachments.append(attachment)
        }

        return BackupArchive(
            generatedBy: "Odomind test",
            exportedOn: now,
            vehicles: [vehicle],
            readings: [Fixture.reading(52_000, on: makeDate(2026, 5, 1))],
            planItems: [Fixture.planItem(rule: .distance(interval: Distance(5_000, .miles)))],
            serviceRecords: [record],
            specifications: [
                VehicleSpecificationRecord(
                    vehicleID: vehicle.id,
                    specification: Specification(
                        kind: .engineOilViscosity,
                        value: .text("5W-20"),
                        provenance: .userEntered,
                        updatedAt: Fixture.stamp
                    )
                )
            ],
            attachments: attachments,
            settings: BackupSettings(reminderSettings: .default, selectedVehicleID: vehicle.id)
        )
    }

    func testRoundTripPreservesEverythingIncludingAttachments() throws {
        let archive = sampleArchive()
        let data = try archive.encoded()
        let decoded = try BackupArchive.decode(data)

        XCTAssertEqual(decoded.vehicles, archive.vehicles)
        XCTAssertEqual(decoded.readings, archive.readings)
        XCTAssertEqual(decoded.planItems, archive.planItems)
        XCTAssertEqual(decoded.serviceRecords, archive.serviceRecords)
        XCTAssertEqual(decoded.specifications, archive.specifications)
        XCTAssertEqual(decoded.settings, archive.settings)
        XCTAssertEqual(decoded.attachments.first?.decodedData(), Data("receipt-bytes".utf8))
    }

    func testMoneySurvivesExactly() throws {
        let archive = sampleArchive()
        let decoded = try BackupArchive.decode(try archive.encoded())
        XCTAssertEqual(decoded.serviceRecords[0].totalCost?.amount, Decimal(string: "89.97")!)
    }

    func testCorruptAttachmentBlocksTheImport() throws {
        var archive = sampleArchive()
        archive.attachments[0].base64Data = Data("tampered".utf8).base64EncodedString()

        let plan = BackupImporter.plan(
            archive: archive,
            existingVehicleIDs: [],
            existingServiceRecordIDs: [],
            strategy: .replaceEverything,
            now: now
        )
        XCTAssertFalse(plan.canApply, "a damaged attachment must stop the restore rather than lose data")
        XCTAssertTrue(plan.blockingIssues.contains { if case .corruptAttachment = $0 { return true }; return false })
    }

    func testMissingAttachmentIsAWarningAndTheReferenceIsStripped() {
        var archive = sampleArchive()
        archive.attachments = []

        let plan = BackupImporter.plan(
            archive: archive,
            existingVehicleIDs: [],
            existingServiceRecordIDs: [],
            strategy: .replaceEverything,
            now: now
        )
        XCTAssertTrue(plan.canApply)
        XCTAssertTrue(plan.warnings.contains { if case .missingAttachment = $0 { return true }; return false })

        let applySet = BackupImporter.makeApplySet(
            archive: archive,
            existingVehicleIDs: [],
            existingServiceRecordIDs: [],
            strategy: .replaceEverything
        )
        XCTAssertTrue(
            applySet.serviceRecords[0].attachmentIDs.isEmpty,
            "a restored record must never point at a file that is not there"
        )
    }

    func testOrphanedRecordsAreReportedAndDropped() {
        var archive = sampleArchive()
        let strayVehicleID = UUID()
        archive.readings.append(
            OdometerReading(vehicleID: strayVehicleID, recordedOn: makeDate(2026, 1, 1), value: Distance(10, .miles))
        )
        archive.serviceRecords.append(Fixture.service(on: makeDate(2026, 1, 1), odometer: 10, vehicleID: strayVehicleID))

        let plan = BackupImporter.plan(
            archive: archive,
            existingVehicleIDs: [],
            existingServiceRecordIDs: [],
            strategy: .replaceEverything,
            now: now
        )
        XCTAssertTrue(plan.canApply)
        XCTAssertTrue(plan.warnings.contains { if case .readingForUnknownVehicle = $0 { return true }; return false })
        XCTAssertTrue(plan.warnings.contains { if case .serviceRecordForUnknownVehicle = $0 { return true }; return false })

        let applySet = BackupImporter.makeApplySet(
            archive: archive,
            existingVehicleIDs: [],
            existingServiceRecordIDs: [],
            strategy: .replaceEverything
        )
        XCTAssertEqual(applySet.readings.count, 1, "the orphan is dropped, not written")
        XCTAssertEqual(applySet.serviceRecords.count, 1)
    }

    func testAddMissingOnlySkipsWhatIsAlreadyThere() {
        let archive = sampleArchive()
        let existingVehicle = archive.vehicles[0].id
        let existingRecord = archive.serviceRecords[0].id

        let plan = BackupImporter.plan(
            archive: archive,
            existingVehicleIDs: [existingVehicle],
            existingServiceRecordIDs: [existingRecord],
            strategy: .addMissingOnly,
            now: now
        )
        XCTAssertTrue(plan.vehiclesToAdd.isEmpty)
        XCTAssertEqual(plan.vehiclesAlreadyPresent.count, 1)
        XCTAssertTrue(plan.warnings.contains { if case .duplicateVehicle = $0 { return true }; return false })

        let applySet = BackupImporter.makeApplySet(
            archive: archive,
            existingVehicleIDs: [existingVehicle],
            existingServiceRecordIDs: [existingRecord],
            strategy: .addMissingOnly
        )
        XCTAssertTrue(applySet.isEmpty)
        XCTAssertFalse(applySet.removesExistingData)
        XCTAssertNil(applySet.settings, "merging must not overwrite the owner's current settings")
    }

    func testReplaceEverythingCarriesSettingsAndFlagsTheDeletion() {
        let archive = sampleArchive()
        let applySet = BackupImporter.makeApplySet(
            archive: archive,
            existingVehicleIDs: [UUID()],
            existingServiceRecordIDs: [],
            strategy: .replaceEverything
        )
        XCTAssertTrue(applySet.removesExistingData)
        XCTAssertNotNil(applySet.settings)
        XCTAssertEqual(applySet.vehicles.count, 1)
    }

    func testUnsupportedFormatVersionIsRejected() throws {
        var archive = sampleArchive()
        archive.formatVersion = 99
        let data = try archive.encoded()
        let result = BackupImporter.decode(data)
        guard case .failure(let issue) = result else { return XCTFail("expected a failure") }
        guard case .unsupportedFormatVersion(let found, _) = issue else {
            return XCTFail("expected unsupportedFormatVersion")
        }
        XCTAssertEqual(found, 99)
        XCTAssertTrue(issue.isBlocking)
    }

    func testGarbageFileIsRejectedWithAReadableMessage() {
        let result = BackupImporter.decode(Data("this is not a backup".utf8))
        guard case .failure(let issue) = result else { return XCTFail("expected a failure") }
        guard case .malformed(let detail) = issue else { return XCTFail("expected malformed") }
        XCTAssertFalse(detail.isEmpty)
        XCTAssertTrue(issue.isBlocking)
    }

    func testAttachmentsOmittedFromExportProduceAWarningNotACorruptionError() {
        let archive = sampleArchive(includeAttachmentPayload: false)
        let plan = BackupImporter.plan(
            archive: archive,
            existingVehicleIDs: [],
            existingServiceRecordIDs: [],
            strategy: .replaceEverything,
            now: now
        )
        XCTAssertTrue(plan.canApply)
        XCTAssertTrue(plan.warnings.contains { if case .attachmentWithoutData = $0 { return true }; return false })
        XCTAssertFalse(plan.issues.contains { if case .corruptAttachment = $0 { return true }; return false })
    }

    func testFutureDatedRecordIsReported() {
        var archive = sampleArchive()
        archive.serviceRecords[0].performedOn = makeDate(2027, 1, 1)
        let plan = BackupImporter.plan(
            archive: archive,
            existingVehicleIDs: [],
            existingServiceRecordIDs: [],
            strategy: .replaceEverything,
            now: now
        )
        XCTAssertTrue(plan.warnings.contains { if case .futureDatedRecord = $0 { return true }; return false })
    }

    func testChecksumDetectsTruncation() {
        let attachment = BackupAttachment.make(
            id: UUID(),
            fileName: "a.bin",
            contentType: "application/octet-stream",
            data: Data([1, 2, 3, 4, 5])
        )
        XCTAssertNotNil(attachment.decodedData())

        var truncated = attachment
        truncated.base64Data = Data([1, 2, 3]).base64EncodedString()
        XCTAssertNil(truncated.decodedData(), "a short payload must not pass verification")
    }
}

final class VehicleIsolationTests: XCTestCase {
    let today = makeDate(2026, 6, 15)

    func testEditingOneVehicleNeverChangesAnother() {
        let first = Fixture.vehicle(id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!)
        let second = Fixture.vehicle(id: UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!)

        let firstItem = Fixture.planItem(vehicleID: first.id, rule: .distance(interval: Distance(5_000, .miles)))
        let secondItem = Fixture.planItem(vehicleID: second.id, rule: .distance(interval: Distance(5_000, .miles)))

        let readings = [
            Fixture.reading(52_000, on: makeDate(2026, 6, 1), vehicleID: first.id),
            Fixture.reading(9_000, on: makeDate(2026, 6, 1), vehicleID: second.id)
        ]
        let services = [
            Fixture.service(on: makeDate(2026, 1, 1), odometer: 48_000, vehicleID: first.id),
            Fixture.service(on: makeDate(2026, 3, 1), odometer: 6_000, vehicleID: second.id)
        ]

        let firstContext = ScheduleContext.build(
            vehicle: first,
            readings: readings,
            serviceRecords: services,
            asOf: today,
            calendar: .utc
        )
        let secondContext = ScheduleContext.build(
            vehicle: second,
            readings: readings,
            serviceRecords: services,
            asOf: today,
            calendar: .utc
        )

        XCTAssertEqual(firstContext.ledger.latestCumulative, Distance(52_000, .miles))
        XCTAssertEqual(secondContext.ledger.latestCumulative, Distance(9_000, .miles))

        let firstResult = ScheduleEngine.evaluate(firstItem, in: firstContext)
        let secondResult = ScheduleEngine.evaluate(secondItem, in: secondContext)

        XCTAssertEqual(firstResult.nextDueOdometer, Distance(53_000, .miles))
        XCTAssertEqual(secondResult.nextDueOdometer, Distance(11_000, .miles))
        XCTAssertEqual(firstResult.vehicleID, first.id)
        XCTAssertEqual(secondResult.vehicleID, second.id)
    }

    func testAnOdometerReplacementOnOneVehicleDoesNotShiftAnother() {
        let replaced = Fixture.vehicle(
            id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!,
            replacements: [
                OdometerReplacement(
                    occurredOn: makeDate(2026, 3, 1),
                    previousUnitFinalReading: Distance(130_000, .miles),
                    replacementUnitStartReading: Distance(0, .miles)
                )
            ]
        )
        let untouched = Fixture.vehicle(id: UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!)

        let readings = [
            Fixture.reading(500, on: makeDate(2026, 6, 1), vehicleID: replaced.id),
            Fixture.reading(500, on: makeDate(2026, 6, 1), vehicleID: untouched.id)
        ]

        let replacedLedger = OdometerLedger(vehicle: replaced, readings: readings)
        let untouchedLedger = OdometerLedger(vehicle: untouched, readings: readings)

        XCTAssertEqual(replacedLedger.latestCumulative, Distance(130_500, .miles))
        XCTAssertEqual(untouchedLedger.latestCumulative, Distance(500, .miles))
    }
}
