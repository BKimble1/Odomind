import XCTest
@testable import OdomindCore

final class ApplicabilityTests: XCTestCase {

    func testElectricVehiclesGetNoEngineOilTask() throws {
        let catalog = try CatalogLoader.loadBundled()
        let ev = Fixture.vehicle(configuration: Fixture.electricConfiguration)
        let ids = PlanBuilder.suggestions(for: ev, catalog: catalog).map(\.definition.id)
        XCTAssertFalse(ids.contains("engine-oil-and-filter"))
        XCTAssertFalse(ids.contains("engine-air-filter"))
        XCTAssertFalse(ids.contains("engine-coolant"))
        XCTAssertTrue(ids.contains("tire-rotation"), "tires still apply to an EV")
        XCTAssertTrue(ids.contains("cabin-air-filter"))
        XCTAssertTrue(ids.contains("ev-battery-coolant"))
    }

    func testCombustionVehiclesGetNoDriveBatteryCoolantTask() throws {
        let catalog = try CatalogLoader.loadBundled()
        let ids = PlanBuilder.suggestions(for: Fixture.vehicle(), catalog: catalog).map(\.definition.id)
        XCTAssertTrue(ids.contains("engine-oil-and-filter"))
        XCTAssertFalse(ids.contains("ev-battery-coolant"))
    }

    func testTimingBeltIsNotOfferedForAChainDrivenEngine() throws {
        let catalog = try CatalogLoader.loadBundled()
        let chainDriven = Fixture.vehicle()
        XCTAssertEqual(chainDriven.configuration.camshaftDrive, .timingChain)
        let ids = PlanBuilder.suggestions(for: chainDriven, catalog: catalog).map(\.definition.id)
        XCTAssertFalse(ids.contains("timing-belt"), "a chain-driven engine must never be given a belt service")
    }

    func testTimingBeltNeedsConfirmationWhenTheEngineIsUnconfirmed() throws {
        let catalog = try CatalogLoader.loadBundled()
        var configuration = Fixture.combustionConfiguration
        configuration.camshaftDrive = .unknown
        let vehicle = Fixture.vehicle(configuration: configuration)

        let suggestion = PlanBuilder.suggestions(for: vehicle, catalog: catalog)
            .first { $0.definition.id == "timing-belt" }
        let timingBelt = try XCTUnwrap(suggestion, "the task should be offered, flagged for confirmation")
        guard case .needsConfirmation(let question, _) = timingBelt.applicability else {
            return XCTFail("expected a confirmation prompt, got \(timingBelt.applicability)")
        }
        XCTAssertEqual(question, .camshaftDrive)
        XCTAssertFalse(timingBelt.isRecommendedByDefault)
    }

    func testTransferCaseTaskFollowsTheDrivetrain() throws {
        let catalog = try CatalogLoader.loadBundled()

        var frontWheelDrive = Fixture.combustionConfiguration
        frontWheelDrive.drivetrain = .frontWheelDrive
        let fwdIDs = PlanBuilder.suggestions(
            for: Fixture.vehicle(configuration: frontWheelDrive),
            catalog: catalog
        ).map(\.definition.id)
        XCTAssertFalse(fwdIDs.contains("transfer-case-fluid"))
        XCTAssertFalse(fwdIDs.contains("front-differential-fluid"), "a FWD transaxle has no separately serviced front diff")
        XCTAssertFalse(fwdIDs.contains("rear-differential-fluid"))

        let fourWheelDriveIDs = PlanBuilder.suggestions(for: Fixture.vehicle(), catalog: catalog).map(\.definition.id)
        XCTAssertTrue(fourWheelDriveIDs.contains("transfer-case-fluid"))
        XCTAssertTrue(fourWheelDriveIDs.contains("front-differential-fluid"))
        XCTAssertTrue(fourWheelDriveIDs.contains("rear-differential-fluid"))
    }

    func testAllWheelDriveAsksRatherThanAssuming() throws {
        let catalog = try CatalogLoader.loadBundled()
        var awd = Fixture.combustionConfiguration
        awd.drivetrain = .allWheelDrive
        let suggestion = PlanBuilder.suggestions(for: Fixture.vehicle(configuration: awd), catalog: catalog)
            .first { $0.definition.id == "transfer-case-fluid" }
        let transferCase = try XCTUnwrap(suggestion)
        guard case .needsConfirmation(let question, _) = transferCase.applicability else {
            return XCTFail("AWD should prompt rather than assume")
        }
        XCTAssertEqual(question, .transferCase)
    }

    func testManualAndAutomaticGearboxTasksDoNotOverlap() throws {
        let catalog = try CatalogLoader.loadBundled()
        var manual = Fixture.combustionConfiguration
        manual.transmission = .manual
        let manualIDs = PlanBuilder.suggestions(for: Fixture.vehicle(configuration: manual), catalog: catalog)
            .map(\.definition.id)
        XCTAssertTrue(manualIDs.contains("manual-transmission-fluid"))
        XCTAssertFalse(manualIDs.contains("automatic-transmission-fluid"))

        let autoIDs = PlanBuilder.suggestions(for: Fixture.vehicle(), catalog: catalog).map(\.definition.id)
        XCTAssertTrue(autoIDs.contains("automatic-transmission-fluid"))
        XCTAssertFalse(autoIDs.contains("manual-transmission-fluid"))
    }

    func testAdvancedTasksAreHiddenFromTheShortList() throws {
        let catalog = try CatalogLoader.loadBundled()
        let short = PlanBuilder.suggestions(for: Fixture.vehicle(), catalog: catalog, includeAdvanced: false)
        XCTAssertFalse(short.contains { $0.definition.isAdvanced })
        XCTAssertTrue(short.allSatisfy { $0.rule != nil || !$0.isRecommendedByDefault })

        let full = PlanBuilder.suggestions(for: Fixture.vehicle(), catalog: catalog, includeAdvanced: true)
        XCTAssertGreaterThan(full.count, short.count)
    }
}

final class ProfileMatchingTests: XCTestCase {

    func testJeepProfileMatchesTheRightVehicleAndSuppressesTimingBelt() throws {
        let catalog = try CatalogLoader.loadBundled()
        var configuration = VehicleConfiguration(
            powertrain: .gasoline,
            engineDisplacementLiters: 3.8,
            transmission: .automatic,
            drivetrain: .fourWheelDrivePartTime,
            market: .unitedStates
        )
        configuration.camshaftDrive = .unknown
        let identity = VehicleIdentity(modelYear: 2010, make: "JEEP", model: "Wrangler")

        let profile = try XCTUnwrap(catalog.bestProfile(for: identity, configuration: configuration))
        XCTAssertEqual(profile.id, "jeep-wrangler-jk-2007-2011-3800")

        let camshaftFact = profile.configurationFacts.first { $0.field == .camshaftDrive }
        XCTAssertEqual(camshaftFact?.value, "timingChain")
        XCTAssertEqual(camshaftFact?.provenance.origin, .referenceSourced)
        XCTAssertFalse(camshaftFact?.provenance.isVerified ?? true, "a reference note is not a verified manufacturer value")
    }

    func testProfileDoesNotMatchTheWrongYearOrEngine() throws {
        let catalog = try CatalogLoader.loadBundled()
        let configuration = VehicleConfiguration(
            powertrain: .gasoline,
            engineDisplacementLiters: 3.6,
            transmission: .automatic,
            drivetrain: .fourWheelDrivePartTime,
            market: .unitedStates
        )
        let wrongEngine = VehicleIdentity(modelYear: 2010, make: "Jeep", model: "Wrangler")
        XCTAssertNil(catalog.bestProfile(for: wrongEngine, configuration: configuration))

        var rightEngine = configuration
        rightEngine.engineDisplacementLiters = 3.8
        let wrongYear = VehicleIdentity(modelYear: 2015, make: "Jeep", model: "Wrangler")
        XCTAssertNil(catalog.bestProfile(for: wrongYear, configuration: rightEngine))
    }

    func testAVehicleWithNoProfileStillGetsGeneralTemplates() throws {
        let catalog = try CatalogLoader.loadBundled()
        let unknownModel = Vehicle(
            identity: VehicleIdentity(modelYear: 2018, make: "Acme", model: "Runabout"),
            configuration: Fixture.combustionConfiguration
        )
        XCTAssertNil(catalog.bestProfile(for: unknownModel.identity, configuration: unknownModel.configuration))

        let suggestions = PlanBuilder.suggestions(for: unknownModel, catalog: catalog, includeAdvanced: false)
        let oil = try XCTUnwrap(suggestions.first { $0.definition.id == "engine-oil-and-filter" })
        XCTAssertNotNil(oil.rule)
        XCTAssertEqual(oil.provenance.origin, .generalTemplate)
        XCTAssertFalse(oil.isVehicleSpecific)
        XCTAssertFalse(oil.provenance.isVerified)
    }
}

final class CatalogUpdateTests: XCTestCase {
    let now = makeDate(2026, 6, 15)

    private func catalogWithOilRule(_ rule: ScheduleRule, version: String) -> MaintenanceCatalog {
        MaintenanceCatalog(
            catalogVersion: version,
            publishedOn: makeDate(2026, 1, 1),
            coverageNotice: "Test catalog.",
            sources: [
                CatalogSource(
                    id: "s",
                    name: "Test source",
                    coverage: "Testing.",
                    terms: "Test.",
                    allowsRedistribution: true,
                    limitations: "None."
                )
            ],
            taskDefinitions: [
                MaintenanceTaskDefinition(
                    id: "engine-oil-and-filter",
                    title: "Engine oil and filter",
                    purpose: "Testing.",
                    category: .engine,
                    action: .replace,
                    defaultRule: rule,
                    defaultRuleProvenance: Provenance.template("Test source", datasetVersion: version)
                )
            ]
        )
    }

    func testACatalogChangeIsProposedNotApplied() {
        let vehicle = Fixture.vehicle()
        let original = catalogWithOilRule(.distance(interval: Distance(5_000, .miles)), version: "1")
        let updated = catalogWithOilRule(.distance(interval: Distance(7_500, .miles)), version: "2")

        let suggestion = PlanBuilder.suggestions(for: vehicle, catalog: original)[0]
        let item = PlanBuilder.makePlanItem(from: suggestion, vehicle: vehicle)
        XCTAssertEqual(item.effectiveRule, .distance(interval: Distance(5_000, .miles)))

        let result = PlanBuilder.applyCatalogUpdate(to: [item], vehicle: vehicle, catalog: updated, now: now)
        let after = result.items[0]

        XCTAssertEqual(
            after.effectiveRule,
            .distance(interval: Distance(5_000, .miles)),
            "the active schedule must not change until the owner accepts"
        )
        XCTAssertTrue(after.hasPendingProposal)
        XCTAssertEqual(after.pendingProposal?.proposedRule, .distance(interval: Distance(7_500, .miles)))
        XCTAssertEqual(after.pendingProposal?.catalogVersion, "2")
        XCTAssertEqual(result.changes.count, 1)
        XCTAssertEqual(result.changes[0].kind, .scheduleChanged)
    }

    func testAcceptingAProposalSwitchesToTheNewSchedule() {
        let vehicle = Fixture.vehicle()
        let original = catalogWithOilRule(.distance(interval: Distance(5_000, .miles)), version: "1")
        let updated = catalogWithOilRule(.distance(interval: Distance(7_500, .miles)), version: "2")
        let item = PlanBuilder.makePlanItem(
            from: PlanBuilder.suggestions(for: vehicle, catalog: original)[0],
            vehicle: vehicle
        )
        var after = PlanBuilder.applyCatalogUpdate(to: [item], vehicle: vehicle, catalog: updated, now: now).items[0]

        after.acceptPendingProposal()
        XCTAssertEqual(after.effectiveRule, .distance(interval: Distance(7_500, .miles)))
        XCTAssertFalse(after.hasPendingProposal)
    }

    func testDismissingAProposalKeepsTheCurrentSchedule() {
        let vehicle = Fixture.vehicle()
        let original = catalogWithOilRule(.distance(interval: Distance(5_000, .miles)), version: "1")
        let updated = catalogWithOilRule(.distance(interval: Distance(7_500, .miles)), version: "2")
        let item = PlanBuilder.makePlanItem(
            from: PlanBuilder.suggestions(for: vehicle, catalog: original)[0],
            vehicle: vehicle
        )
        var after = PlanBuilder.applyCatalogUpdate(to: [item], vehicle: vehicle, catalog: updated, now: now).items[0]
        after.dismissPendingProposal()
        XCTAssertEqual(after.effectiveRule, .distance(interval: Distance(5_000, .miles)))
        XCTAssertFalse(after.hasPendingProposal)
    }

    func testAnOwnerOverrideSurvivesACatalogUpdate() {
        let vehicle = Fixture.vehicle()
        let original = catalogWithOilRule(.distance(interval: Distance(5_000, .miles)), version: "1")
        let updated = catalogWithOilRule(.distance(interval: Distance(7_500, .miles)), version: "2")

        var item = PlanBuilder.makePlanItem(
            from: PlanBuilder.suggestions(for: vehicle, catalog: original)[0],
            vehicle: vehicle
        )
        item.ownerRule = .distance(interval: Distance(3_000, .miles))
        XCTAssertTrue(item.isOwnerOverridden)

        let after = PlanBuilder.applyCatalogUpdate(to: [item], vehicle: vehicle, catalog: updated, now: now).items[0]
        XCTAssertEqual(
            after.effectiveRule,
            .distance(interval: Distance(3_000, .miles)),
            "an owner override is never overwritten by the catalog"
        )
        XCTAssertEqual(after.ownerRule, .distance(interval: Distance(3_000, .miles)))
        XCTAssertTrue(after.hasPendingProposal, "the owner still gets to see what the catalog now says")
    }

    func testAnIdenticalRuleRefreshesProvenanceWithoutAProposal() {
        let vehicle = Fixture.vehicle()
        let original = catalogWithOilRule(.distance(interval: Distance(5_000, .miles)), version: "1")
        let same = catalogWithOilRule(.distance(interval: Distance(5_000, .miles)), version: "2")
        let item = PlanBuilder.makePlanItem(
            from: PlanBuilder.suggestions(for: vehicle, catalog: original)[0],
            vehicle: vehicle
        )
        let after = PlanBuilder.applyCatalogUpdate(to: [item], vehicle: vehicle, catalog: same, now: now).items[0]
        XCTAssertFalse(after.hasPendingProposal)
        XCTAssertEqual(after.catalogProvenance?.attribution?.datasetVersion, "2")
    }

    func testCustomTasksAreNeverTouchedByACatalogUpdate() {
        let vehicle = Fixture.vehicle()
        var custom = Fixture.planItem(definitionID: "custom-my-job", title: "My own job", rule: .time(interval: .months(4)))
        custom.isCustom = true
        let updated = catalogWithOilRule(.distance(interval: Distance(7_500, .miles)), version: "2")

        let after = PlanBuilder.applyCatalogUpdate(to: [custom], vehicle: vehicle, catalog: updated, now: now).items[0]
        XCTAssertEqual(after.effectiveRule, .time(interval: .months(4)))
        XCTAssertFalse(after.hasPendingProposal)
    }
}

final class SpecificationResolutionTests: XCTestCase {

    func testOwnerEntryWinsAndTheCatalogValueStaysVisible() throws {
        let catalog = try CatalogLoader.loadBundled()
        let vehicle = Fixture.vehicle()
        let ownerValue = Specification(
            kind: .engineOilViscosity,
            value: .text("5W-20"),
            provenance: .userEntered,
            appliesToNote: "From my owner's manual"
        )
        let resolved = PlanBuilder.resolvedSpecifications(
            vehicle: vehicle,
            catalog: catalog,
            ownerEntries: [ownerValue]
        )
        let oil = try XCTUnwrap(resolved.first { $0.kind == .engineOilViscosity })
        XCTAssertTrue(oil.isOwnerOverride)
        XCTAssertEqual(oil.active.value, .text("5W-20"))
        XCTAssertFalse(oil.active.isVerified, "an owner entry is trusted but not badged as manufacturer-verified")
    }

    func testAVehicleWithNoPublishedSpecificationsShowsOnlyWhatTheOwnerEntered() throws {
        let catalog = try CatalogLoader.loadBundled()
        let resolved = PlanBuilder.resolvedSpecifications(
            vehicle: Fixture.vehicle(),
            catalog: catalog,
            ownerEntries: []
        )
        XCTAssertTrue(
            resolved.isEmpty,
            "the bundled catalog deliberately publishes no specification values, so there is nothing to show"
        )
    }
}

final class CalendarExportStateTests: XCTestCase {

    private func item(exportedOn: Date?, exportedDueDate: Date?) -> MaintenancePlanItem {
        var item = Fixture.planItem(rule: .time(interval: .months(6)))
        item.lastCalendarExportOn = exportedOn
        item.lastCalendarExportDueDate = exportedDueDate
        return item
    }

    func testNothingExportedYet() {
        let state = item(exportedOn: nil, exportedDueDate: nil)
            .calendarExportState(currentDueDate: makeDate(2026, 7, 15))
        XCTAssertEqual(state, .notExported)
        XCTAssertFalse(state.hasEvent)
    }

    func testExportedAndStillMatching() {
        let due = makeDate(2026, 7, 15)
        let state = item(exportedOn: makeDate(2026, 6, 1), exportedDueDate: due)
            .calendarExportState(currentDueDate: due)
        XCTAssertEqual(state, .exported(on: makeDate(2026, 6, 1)))
        XCTAssertTrue(state.hasEvent)
    }

    func testScheduleMovedAfterTheEventWasCreated() {
        // Odomind cannot edit or remove an event it helped create, so when the
        // due date moves it has to say so rather than quietly disagree with the
        // owner's calendar.
        let state = item(exportedOn: makeDate(2026, 6, 1), exportedDueDate: makeDate(2026, 7, 15))
            .calendarExportState(currentDueDate: makeDate(2026, 9, 1))
        guard case .exportedButStale(let on, let eventDate) = state else {
            return XCTFail("expected exportedButStale, got \(state)")
        }
        XCTAssertEqual(on, makeDate(2026, 6, 1))
        XCTAssertEqual(eventDate, makeDate(2026, 7, 15))
        XCTAssertTrue(state.hasEvent)
    }

    func testASecondOfDriftIsNotTreatedAsAChange() {
        let due = makeDate(2026, 7, 15)
        let state = item(exportedOn: makeDate(2026, 6, 1), exportedDueDate: due)
            .calendarExportState(currentDueDate: due.addingTimeInterval(30))
        XCTAssertEqual(state, .exported(on: makeDate(2026, 6, 1)))
    }

    func testExportedWithNoCurrentDueDateIsStillReportedAsExported() {
        let state = item(exportedOn: makeDate(2026, 6, 1), exportedDueDate: makeDate(2026, 7, 15))
            .calendarExportState(currentDueDate: nil)
        XCTAssertEqual(state, .exported(on: makeDate(2026, 6, 1)))
    }
}
