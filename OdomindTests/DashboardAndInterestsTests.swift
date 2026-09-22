import XCTest
@testable import Odomind
import OdomindCore

/// Build 4's behaviour: which car the app is about, what the first-run answer
/// does, and the dashboard's own numbers.
///
/// Every one of these is a thing a screenshot cannot check and a compiler will
/// not catch — a pin that does not survive a switch, a stored answer nothing
/// reads, a distance that counts a single reading as zero miles driven.
@MainActor
final class DashboardAndInterestsTests: XCTestCase {

    private var scratchDirectories: [URL] = []

    override func tearDown() {
        for directory in scratchDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        scratchDirectories = []
        super.tearDown()
    }

    private func makeModel(now: Date = appDate(2026, 6, 15)) throws -> AppModel {
        let built = try AppFixture.makeModel(now: now)
        scratchDirectories.append(built.attachmentsDirectory)
        return built.model
    }

    // MARK: - Which car the dashboard is about

    func testOneVehicleNeedsNoChoice() throws {
        let model = try makeModel()
        let id = try XCTUnwrap(model.addVehicle(from: AppFixture.draft()))

        XCTAssertEqual(model.dashboardVehicle?.id, id)
        // The switcher does not appear at all, which is the point: most people
        // have one car and were being asked to operate a control with one
        // entry in it.
        XCTAssertFalse(model.hasVehicleChoice)
    }

    func testPinnedVehicleWinsOverTheSelectedOne() throws {
        let model = try makeModel()
        let jeep = try XCTUnwrap(model.addVehicle(from: AppFixture.draft()))
        let camry = try XCTUnwrap(
            model.addVehicle(from: AppFixture.draft(make: "Toyota", model: "Camry", year: 2018))
        )

        // Adding selects the new vehicle, so the dashboard is on the Camry.
        XCTAssertEqual(model.dashboardVehicle?.id, camry)
        XCTAssertTrue(model.hasVehicleChoice)

        let jeepVehicle = try XCTUnwrap(model.snapshot.vehicle(id: jeep))
        model.togglePin(jeepVehicle)

        XCTAssertEqual(model.dashboardVehicle?.id, jeep)
        XCTAssertTrue(model.isPinned(jeepVehicle))
        // Pinning selects too, so nothing else in the app is left on the Camry.
        XCTAssertEqual(model.selectedVehicleID, jeep)
    }

    func testUnpinningFallsBackToTheSelection() throws {
        let model = try makeModel()
        let jeep = try XCTUnwrap(model.addVehicle(from: AppFixture.draft()))
        _ = try XCTUnwrap(
            model.addVehicle(from: AppFixture.draft(make: "Toyota", model: "Camry", year: 2018))
        )

        let jeepVehicle = try XCTUnwrap(model.snapshot.vehicle(id: jeep))
        model.togglePin(jeepVehicle)
        model.togglePin(jeepVehicle)

        XCTAssertFalse(model.isPinned(jeepVehicle))
        XCTAssertNil(model.preferences.pinnedVehicleID)
        // Still the Jeep, because pinning selected it. Unpinning is "stop
        // holding this one", not "go back to whatever was there before".
        XCTAssertEqual(model.dashboardVehicle?.id, jeep)
    }

    /// The bug this pairing exists to prevent: the dashboard on one car while
    /// another screen's switcher says a different one, with nothing on screen
    /// to explain it.
    func testSwitchingCarsMovesThePin() throws {
        let model = try makeModel()
        let jeep = try XCTUnwrap(model.addVehicle(from: AppFixture.draft()))
        let camry = try XCTUnwrap(
            model.addVehicle(from: AppFixture.draft(make: "Toyota", model: "Camry", year: 2018))
        )

        model.togglePin(try XCTUnwrap(model.snapshot.vehicle(id: jeep)))
        XCTAssertEqual(model.dashboardVehicle?.id, jeep)

        model.showVehicle(camry)

        XCTAssertEqual(model.dashboardVehicle?.id, camry)
        XCTAssertEqual(model.preferences.pinnedVehicleID, camry)
        XCTAssertEqual(model.selectedVehicleID, camry)
    }

    func testADeletedPinnedVehicleDoesNotStrandTheDashboard() async throws {
        let model = try makeModel()
        let jeep = try XCTUnwrap(model.addVehicle(from: AppFixture.draft()))
        let camry = try XCTUnwrap(
            model.addVehicle(from: AppFixture.draft(make: "Toyota", model: "Camry", year: 2018))
        )

        model.togglePin(try XCTUnwrap(model.snapshot.vehicle(id: jeep)))
        await model.deleteVehicle(id: jeep)

        // The preference still names a vehicle that is gone. The dashboard has
        // to fall through to something real rather than showing nothing.
        XCTAssertEqual(model.dashboardVehicle?.id, camry)
    }

    // MARK: - What the first-run question does

    func testInterestsNarrowWhatTheStarterPlanTicks() throws {
        let model = try makeModel()
        let vehicle = AppFixture.previewVehicle()
        let suggestions = model.allSuggestions(for: vehicle)
        XCTAssertFalse(suggestions.isEmpty, "the bundled catalog should offer this vehicle something")

        let everything = model.recommendedTaskIDs(from: suggestions)

        model.setTrackingInterests([.tyresAndBrakes])
        let narrowed = model.recommendedTaskIDs(from: suggestions)

        XCTAssertFalse(narrowed.isEmpty)
        XCTAssertLessThan(narrowed.count, everything.count, "an answer that changes nothing is not an answer")

        // Everything ticked is in a category the owner actually asked for.
        let wanted = Set<TrackingInterest>([.tyresAndBrakes]).categories
        for id in narrowed {
            let suggestion = try XCTUnwrap(suggestions.first { $0.definition.id == id })
            XCTAssertTrue(
                wanted.contains(suggestion.definition.category),
                "\(id) is \(suggestion.definition.category), which nobody asked for"
            )
        }
    }

    func testSkippingTheQuestionKeepsTheOrdinarySet() throws {
        let model = try makeModel()
        let suggestions = model.allSuggestions(for: AppFixture.previewVehicle())

        let everything = model.recommendedTaskIDs(from: suggestions)
        model.setTrackingInterests([])

        XCTAssertEqual(model.recommendedTaskIDs(from: suggestions), everything)
        // Skipping is an answer, so the question is not put again.
        XCTAssertTrue(model.preferences.hasAnsweredTrackingQuestion)
    }

    /// "What it costs me" is about what Odomind shows, not about which jobs
    /// exist, so on its own it must not narrow anything to nothing.
    func testAnInterestThatMapsToNoCategoryDoesNotEmptyThePlan() throws {
        let model = try makeModel()
        let suggestions = model.allSuggestions(for: AppFixture.previewVehicle())
        let everything = model.recommendedTaskIDs(from: suggestions)

        model.setTrackingInterests([.spending])

        XCTAssertEqual(model.recommendedTaskIDs(from: suggestions), everything)
    }

    func testInterestsSurviveASaveAndReload() throws {
        let model = try makeModel()
        model.setTrackingInterests([.essentials, .paperwork])
        model.refresh()

        XCTAssertEqual(model.preferences.trackingInterests, [.essentials, .paperwork])
        XCTAssertTrue(model.preferences.hasAnsweredTrackingQuestion)
    }

    // MARK: - The dashboard's own numbers

    func testDistanceThisMonthNeedsTwoReadingsToMeanAnything() throws {
        let model = try makeModel(now: appDate(2026, 6, 15))
        let id = try XCTUnwrap(model.addVehicle(from: AppFixture.draft(odometer: 120_000)))

        // One reading is a position, not a distance travelled. Reporting zero
        // would be a claim Odomind cannot make.
        XCTAssertNil(model.distanceThisMonth(for: id))

        model.recordOdometer(vehicleID: id, amount: 120_600, on: appDate(2026, 6, 14))

        XCTAssertEqual(model.distanceThisMonth(for: id), Distance(600, .miles))
    }

    func testDistanceThisMonthIgnoresLastMonthsReadings() throws {
        let model = try makeModel(now: appDate(2026, 6, 15))
        let id = try XCTUnwrap(model.addVehicle(from: AppFixture.draft(odometer: 120_000, now: appDate(2026, 5, 2))))

        model.recordOdometer(vehicleID: id, amount: 120_400, on: appDate(2026, 6, 3))
        model.recordOdometer(vehicleID: id, amount: 120_700, on: appDate(2026, 6, 14))

        // 300 within June, not 700 since the setup reading in May.
        XCTAssertEqual(model.distanceThisMonth(for: id), Distance(300, .miles))
    }

    // MARK: - Parts for a specific car

    /// The chain the whole Parts screen rests on: pick a configuration, and
    /// what that configuration states is recorded against the vehicle and
    /// comes back out of `resolvedSpecifications`.
    func testAChosenConfigurationsFuelGradeReachesTheVehicle() throws {
        let model = try makeModel()
        var draft = AppFixture.draft()
        draft.chosenOption = VehicleConfigurationOption(
            id: "31873",
            providerName: "fueleconomy.gov",
            providerKey: "fueleconomy.gov",
            providerURL: URL(string: "https://www.fueleconomy.gov/feg/Find.do?action=sbs&id=31873"),
            label: "3.8 L, 6 cyl, Automatic 4-spd, Regular Gasoline",
            fuelDescription: "Regular Gasoline"
        )

        let id = try XCTUnwrap(model.addVehicle(from: draft))
        let vehicle = try XCTUnwrap(model.snapshot.vehicle(id: id))
        let resolved = model.resolvedSpecifications(for: vehicle)

        let grade = try XCTUnwrap(resolved.first { $0.kind == .fuelGrade })
        XCTAssertEqual(grade.active.value.displayString, "Regular")
        XCTAssertEqual(grade.active.provenance.attribution?.sourceName, "fueleconomy.gov")
    }

    /// A vehicle added without picking a configuration records nothing, rather
    /// than a default grade nobody stated.
    func testNoChosenConfigurationMeansNoInventedSpecification() throws {
        let model = try makeModel()
        let id = try XCTUnwrap(model.addVehicle(from: AppFixture.draft()))
        let vehicle = try XCTUnwrap(model.snapshot.vehicle(id: id))

        XCTAssertTrue(model.resolvedSpecifications(for: vehicle).isEmpty)
    }

    /// The retailer search carries the recorded value, which is the whole
    /// point of holding one: "2010 Jeep Wrangler Regular fuel" beats "2010
    /// Jeep Wrangler fuel".
    func testARecordedSpecificationReachesTheRetailerSearch() throws {
        let model = try makeModel()
        let id = try XCTUnwrap(model.addVehicle(from: AppFixture.draft()))
        let vehicle = try XCTUnwrap(model.snapshot.vehicle(id: id))

        model.saveSpecification(
            Specification(
                kind: .batteryGroupSize,
                value: .text("Group 34"),
                provenance: .userEntered
            ),
            for: id
        )

        let resolved = model.resolvedSpecifications(for: vehicle)
        let battery = try XCTUnwrap(resolved.first { $0.kind == .batteryGroupSize })
        let query = PartsQueryBuilder.query(
            for: vehicle,
            part: "battery",
            specification: battery.active.value.displayString
        )

        XCTAssertTrue(query.contains("Group 34"), query)
        XCTAssertTrue(query.contains("Wrangler"), query)
        // Never the VIN, the nickname or anything from the history.
        XCTAssertFalse(query.lowercased().contains("vin"))
    }

    func testTheDashboardSummaryIsAboutTheRecordsOdomindHolds() throws {
        let model = try makeModel()
        let id = try XCTUnwrap(model.addVehicle(from: AppFixture.draft()))

        let summary = model.dashboardSummary(for: id)

        // Nothing has been logged, so nothing is claimed to be in good order.
        XCTAssertGreaterThan(summary.tracked, 0)
        XCTAssertNotNil(summary.headline)
        // "Needs setup", not "Good": no service has been logged, so Odomind
        // has nothing to base an all-clear on and must not offer one.
        XCTAssertEqual(summary.verdict, "Needs setup")
    }
}
