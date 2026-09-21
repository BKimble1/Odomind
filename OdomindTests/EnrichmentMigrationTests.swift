import XCTest
@testable import Odomind
import OdomindCore

/// What has to keep working when Odomind knows less about a vehicle than it
/// would like — or learns more about one it already has.
///
/// Build 3 turns on automatic enrichment: a vehicle acquires a configuration,
/// specifications and a photograph after it has been added, in the background,
/// from services that can be slow or down. The brief's rule for all of it is
/// that none of it may become a precondition. "Existing vehicles should
/// receive optional enrichment without being recreated" and "a provider outage
/// should not prevent logging service or reading saved data."
@MainActor
final class EnrichmentMigrationTests: XCTestCase {

    private var scratchDirectories: [URL] = []

    override func tearDown() {
        for directory in scratchDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        scratchDirectories = []
        super.tearDown()
    }

    private func makeModel(
        provider: VehicleIdentificationProvider = StubIdentificationProvider()
    ) throws -> AppModel {
        let built = try AppFixture.makeModel(provider: provider)
        scratchDirectories.append(built.attachmentsDirectory)
        return built.model
    }

    /// A vehicle as it arrives when nothing came back from anybody: a year, a
    /// make, a model, and no configuration at all.
    private func bareDraft() -> VehicleDraft {
        var draft = VehicleDraft()
        draft.identity = VehicleIdentity(modelYear: 2010, make: "Jeep", model: "Wrangler")
        draft.configuration = VehicleConfiguration()
        draft.displayUnit = .miles
        draft.odometerAmount = 120_000
        draft.odometerDate = appDate(2026, 6, 15)
        draft.selectedTaskIDs = ["engine-oil-and-filter", "tire-rotation"]
        return draft
    }

    // MARK: - Logging with nothing enriched

    func testAVehicleWithNoConfigurationStillGetsAPlan() throws {
        let model = try makeModel()
        let vehicleID = try XCTUnwrap(model.addVehicle(from: bareDraft()))

        let evaluations = model.evaluations(for: vehicleID)
        XCTAssertFalse(
            evaluations.isEmpty,
            "an unconfigured vehicle must still get the tasks the owner picked"
        )
        XCTAssertTrue(
            evaluations.contains { $0.definitionID == "engine-oil-and-filter" },
            "got \(evaluations.map(\.definitionID))"
        )
    }

    func testServiceCanBeLoggedAgainstAnUnconfiguredVehicle() throws {
        let model = try makeModel()
        let vehicleID = try XCTUnwrap(model.addVehicle(from: bareDraft()))
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
        XCTAssertNotNil(model.saveService(draft), "logging must not depend on enrichment")
        XCTAssertNil(model.alert, "got \(String(describing: model.alert))")

        let after = try XCTUnwrap(
            model.evaluations(for: vehicleID).first { $0.definitionID == "engine-oil-and-filter" }
        )
        XCTAssertEqual(after.lastCompletedOdometer, Distance(120_000, .miles))
        XCTAssertNotNil(after.nextDueOdometer, "the due calculation must still run")
    }

    func testAProviderOutageDoesNotPreventLoggingService() throws {
        // Everything external is down. The app is a record of what the owner
        // told it, and that has to keep working offline.
        var provider = StubIdentificationProvider()
        provider.error = .notConnected
        let model = try makeModel(provider: provider)

        let vehicleID = try XCTUnwrap(model.addVehicle(from: bareDraft()))
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
        XCTAssertNotNil(model.saveService(draft))
        XCTAssertEqual(model.serviceRecords(for: vehicleID).count, 1)
    }

    // MARK: - Enrichment arriving later

    func testEnrichmentUpdatesTheVehicleInPlaceAndKeepsItsHistory() throws {
        let model = try makeModel()
        let vehicleID = try XCTUnwrap(model.addVehicle(from: bareDraft()))

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
        let recordID = try XCTUnwrap(model.saveService(draft))

        // Enrichment lands: the configuration and the body class are filled in
        // on the vehicle that is already there.
        var vehicle = try XCTUnwrap(model.snapshot.vehicle(id: vehicleID))
        vehicle.configuration.powertrain = .gasoline
        vehicle.configuration.engineDisplacementLiters = 3.8
        vehicle.identity.bodyClass = "Sport Utility Vehicle (SUV)/Multi-Purpose Vehicle (MPV)"
        model.updateVehicle(vehicle)

        XCTAssertEqual(model.snapshot.vehicles.count, 1, "enrichment must not add a second vehicle")
        let enriched = try XCTUnwrap(model.snapshot.vehicle(id: vehicleID))
        XCTAssertEqual(enriched.id, vehicleID, "the vehicle keeps its identity")
        XCTAssertEqual(enriched.configuration.powertrain, .gasoline)
        XCTAssertEqual(
            model.serviceRecords(for: vehicleID).map(\.id), [recordID],
            "history must survive enrichment"
        )
        XCTAssertEqual(model.latestReading(for: vehicleID)?.value, Distance(120_000, .miles))
        XCTAssertEqual(
            model.evaluations(for: vehicleID).first { $0.definitionID == "engine-oil-and-filter" }?
                .lastCompletedOdometer,
            Distance(120_000, .miles)
        )
    }

    func testEnrichmentThatChangesTheCarAsksForADifferentPhotograph() throws {
        // The photo service is keyed on a revision of the identity. If
        // enrichment corrects the model, the old photograph must stop being
        // the answer rather than staying on screen under a new name.
        let model = try makeModel()
        let vehicleID = try XCTUnwrap(model.addVehicle(from: bareDraft()))
        var vehicle = try XCTUnwrap(model.snapshot.vehicle(id: vehicleID))

        let before = VehiclePhotoService.revision(for: vehicle)
        vehicle.nickname = "The blue one"
        XCTAssertEqual(
            VehiclePhotoService.revision(for: vehicle), before,
            "a nickname does not change which car it is"
        )

        vehicle.identity.bodyClass = "Convertible"
        XCTAssertNotEqual(
            VehiclePhotoService.revision(for: vehicle), before,
            "a different body class is a different photograph"
        )
    }

    // MARK: - Reading data written before enrichment existed

    func testAStoreWrittenWithoutTheBuildThreeFieldsStillOpens() throws {
        // Build 3 added no stored property to the vehicle: photographs are
        // cached outside the database and the shopping area lives in
        // preferences. This asserts that, so adding one later cannot pass
        // unnoticed — a new non-defaulted property would fail to open an
        // existing store on the owner's phone, and the first sign would be a
        // TestFlight crash report.
        let store = try OdomindStore(inMemory: true)
        let identity = VehicleIdentity(modelYear: 2010, make: "Jeep", model: "Wrangler")
        let vehicle = Vehicle(nickname: nil, identity: identity)
        try store.save(vehicle: vehicle, declaredTypicalDistance: nil)
        try store.save(
            reading: OdometerReading(
                vehicleID: vehicle.id,
                recordedOn: appDate(2026, 6, 15),
                value: Distance(120_000, .miles),
                source: .manualEntry
            )
        )

        let snapshot = try store.snapshot()
        XCTAssertEqual(snapshot.vehicles.map(\.id), [vehicle.id])
        let reopened = try XCTUnwrap(snapshot.vehicle(id: vehicle.id))
        XCTAssertEqual(reopened.identity.model, "Wrangler")
        XCTAssertEqual(reopened.configuration, VehicleConfiguration())
        XCTAssertEqual(snapshot.readings(for: vehicle.id).first?.value, Distance(120_000, .miles))
    }
}
