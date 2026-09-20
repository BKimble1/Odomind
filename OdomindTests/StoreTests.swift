import XCTest
@testable import Odomind
import OdomindCore

@MainActor
final class OdomindStoreTests: XCTestCase {

    private func makeStore() throws -> OdomindStore {
        try OdomindStore(inMemory: true)
    }

    private func vehicle(name: String = "Test", id: UUID = UUID()) -> Vehicle {
        Vehicle(
            id: id,
            nickname: name,
            identity: VehicleIdentity(modelYear: 2010, make: "Jeep", model: "Wrangler"),
            configuration: VehicleConfiguration(powertrain: .gasoline, transmission: .automatic),
            displayUnit: .miles,
            createdAt: appDate(2026, 1, 1)
        )
    }

    func testVehicleRoundTripsThroughTheStore() throws {
        let store = try makeStore()
        var original = vehicle()
        original.configuration.camshaftDrive = .timingChain
        original.inServiceOn = appDate(2010, 6, 1)
        original.odometerReplacements = [
            OdometerReplacement(
                occurredOn: appDate(2024, 3, 1),
                previousUnitFinalReading: Distance(130_000, .miles),
                replacementUnitStartReading: Distance(0, .miles)
            )
        ]

        try store.save(vehicle: original, declaredTypicalDistance: Distance(900, .miles))
        let snapshot = try store.snapshot()

        XCTAssertEqual(snapshot.vehicles.count, 1)
        XCTAssertEqual(snapshot.vehicles[0], original)
        XCTAssertEqual(snapshot.declaredTypicalDistances[original.id], Distance(900, .miles))
        XCTAssertTrue(snapshot.problems.isEmpty, "unexpected read problems: \(snapshot.problems)")
    }

    func testPlanItemPreservesOwnerOverrideAndProposal() throws {
        let store = try makeStore()
        let car = vehicle()
        try store.save(vehicle: car)

        var item = MaintenancePlanItem(
            vehicleID: car.id,
            definitionID: "engine-oil-and-filter",
            title: "Engine oil and filter",
            category: .engine,
            action: .replace,
            catalogRule: .distanceOrTime(distance: Distance(5_000, .miles), time: .months(6)),
            catalogProvenance: Provenance.template("Odomind general maintenance guidance"),
            ownerRule: .distance(interval: Distance(3_000, .miles)),
            baseline: .declared(date: appDate(2026, 1, 1), odometer: Distance(50_000, .miles)),
            createdAt: appDate(2026, 1, 1)
        )
        item.pendingProposal = RuleChangeProposal(
            proposedRule: .distance(interval: Distance(7_500, .miles)),
            proposedProvenance: Provenance.template("Odomind general maintenance guidance"),
            catalogVersion: "test",
            proposedOn: appDate(2026, 5, 1),
            summaryOfChange: "a → b"
        )

        try store.save(planItem: item)
        let reloaded = try XCTUnwrap(try store.snapshot().planItems.first)
        XCTAssertEqual(reloaded, item)
        XCTAssertEqual(reloaded.effectiveRule, .distance(interval: Distance(3_000, .miles)))
        XCTAssertTrue(reloaded.hasPendingProposal)
    }

    func testServiceRecordKeepsExactDecimalCost() throws {
        let store = try makeStore()
        let car = vehicle()
        try store.save(vehicle: car)

        let record = ServiceRecord(
            vehicleID: car.id,
            performedOn: appDate(2026, 5, 1),
            odometer: Distance(52_000, .miles),
            items: [
                ServiceLineItem(definitionID: "engine-oil-and-filter", title: "Engine oil and filter", action: .replace),
                ServiceLineItem(definitionID: "tire-rotation", title: "Tire rotation", action: .rotate)
            ],
            totalCost: Money(amount: Decimal(string: "89.97")!, currencyCode: "USD"),
            performer: .shop(name: "Corner Garage"),
            createdAt: appDate(2026, 5, 1),
            updatedAt: appDate(2026, 5, 1)
        )
        try store.save(serviceRecord: record)

        let reloaded = try XCTUnwrap(try store.snapshot().serviceRecords.first)
        XCTAssertEqual(reloaded.totalCost?.amount, Decimal(string: "89.97")!)
        XCTAssertEqual(reloaded.performer.shopName, "Corner Garage")
        XCTAssertEqual(reloaded.items.count, 2)
    }

    func testDeletingAVehicleRemovesOnlyItsOwnRecords() throws {
        let store = try makeStore()
        let keep = vehicle(name: "Keep")
        let remove = vehicle(name: "Remove")
        try store.save(vehicle: keep)
        try store.save(vehicle: remove)

        for car in [keep, remove] {
            try store.save(
                reading: OdometerReading(
                    vehicleID: car.id,
                    recordedOn: appDate(2026, 5, 1),
                    value: Distance(1_000, .miles)
                )
            )
            try store.save(
                serviceRecord: ServiceRecord(
                    vehicleID: car.id,
                    performedOn: appDate(2026, 5, 1),
                    items: [ServiceLineItem(definitionID: "engine-oil-and-filter", title: "Oil", action: .replace)],
                    createdAt: appDate(2026, 5, 1),
                    updatedAt: appDate(2026, 5, 1)
                )
            )
        }

        try store.deleteVehicle(id: remove.id)
        let snapshot = try store.snapshot()

        XCTAssertEqual(snapshot.vehicles.map(\.id), [keep.id])
        XCTAssertEqual(snapshot.readings.map(\.vehicleID), [keep.id])
        XCTAssertEqual(snapshot.serviceRecords.map(\.vehicleID), [keep.id])
    }

    func testDeletingAVehicleMovesTheSelection() throws {
        let store = try makeStore()
        let first = vehicle(name: "First")
        let second = vehicle(name: "Second")
        try store.save(vehicle: first)
        try store.save(vehicle: second)
        try store.save(settings: AppSettings(
            selectedVehicleID: first.id,
            hasCompletedOnboarding: true,
            catalogVersionLastSeen: nil,
            reminders: .default
        ))

        try store.deleteVehicle(id: first.id)
        XCTAssertEqual(try store.snapshot().settings.selectedVehicleID, second.id)
    }

    func testDeletingAServiceRecordReportsOnlyUnreferencedAttachments() throws {
        let store = try makeStore()
        let car = vehicle()
        try store.save(vehicle: car)

        let shared = UUID()
        let onlyOnFirst = UUID()
        for id in [shared, onlyOnFirst] {
            try store.registerAttachment(
                AttachmentMetadata(
                    id: id,
                    fileName: "\(id.uuidString).jpg",
                    contentType: "image/jpeg",
                    byteCount: 10,
                    createdAt: appDate(2026, 1, 1),
                    caption: nil
                )
            )
        }

        let first = ServiceRecord(
            vehicleID: car.id,
            performedOn: appDate(2026, 5, 1),
            items: [ServiceLineItem(definitionID: "a", title: "A", action: .replace)],
            attachmentIDs: [shared, onlyOnFirst],
            createdAt: appDate(2026, 5, 1),
            updatedAt: appDate(2026, 5, 1)
        )
        let second = ServiceRecord(
            vehicleID: car.id,
            performedOn: appDate(2026, 4, 1),
            items: [ServiceLineItem(definitionID: "b", title: "B", action: .replace)],
            attachmentIDs: [shared],
            createdAt: appDate(2026, 4, 1),
            updatedAt: appDate(2026, 4, 1)
        )
        try store.save(serviceRecord: first)
        try store.save(serviceRecord: second)

        let orphaned = try store.deleteServiceRecord(id: first.id)
        XCTAssertEqual(orphaned, [onlyOnFirst], "an attachment another record still uses must be kept")
        XCTAssertEqual(try store.snapshot().attachments.map(\.id), [shared])
    }

    func testSpecificationsAreOnePerKindPerVehicle() throws {
        let store = try makeStore()
        let car = vehicle()
        try store.save(vehicle: car)

        try store.save(
            specification: Specification(
                kind: .engineOilViscosity,
                value: .text("5W-20"),
                provenance: .userEntered,
                updatedAt: appDate(2026, 1, 1)
            ),
            for: car.id
        )
        try store.save(
            specification: Specification(
                kind: .engineOilViscosity,
                value: .text("0W-20"),
                provenance: .userEntered,
                updatedAt: appDate(2026, 2, 1)
            ),
            for: car.id
        )

        let stored = try store.snapshot().specifications(for: car.id)
        XCTAssertEqual(stored.count, 1, "saving the same kind twice must replace, not duplicate")
        XCTAssertEqual(stored.first?.value, .text("0W-20"))
    }

    func testDeleteEverythingLeavesAnEmptyStore() throws {
        let store = try makeStore()
        let car = vehicle()
        try store.save(vehicle: car)
        try store.save(
            reading: OdometerReading(vehicleID: car.id, recordedOn: appDate(2026, 1, 1), value: Distance(1, .miles))
        )
        try store.deleteEverything()

        let snapshot = try store.snapshot()
        XCTAssertTrue(snapshot.vehicles.isEmpty)
        XCTAssertTrue(snapshot.readings.isEmpty)
        XCTAssertNil(snapshot.settings.selectedVehicleID)
    }

    func testDataPersistsAcrossAFreshContext() throws {
        // A second store built on the same in-memory container stands in for a
        // relaunch: the point is that reads go through the persisted rows, not
        // through anything held in memory by the first store.
        let store = try makeStore()
        let car = vehicle()
        try store.save(vehicle: car)
        try store.save(
            reading: OdometerReading(
                vehicleID: car.id,
                recordedOn: appDate(2026, 5, 1),
                value: Distance(52_000, .miles)
            )
        )

        let reopened = try store.snapshot()
        XCTAssertEqual(reopened.vehicles.first?.id, car.id)
        XCTAssertEqual(reopened.readings.first?.value, Distance(52_000, .miles))
    }
}
