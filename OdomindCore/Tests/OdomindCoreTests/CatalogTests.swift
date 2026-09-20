import XCTest
@testable import OdomindCore

final class BundledCatalogTests: XCTestCase {

    func testBundledCatalogLoadsAndValidates() throws {
        let catalog = try CatalogLoader.loadBundled()
        XCTAssertEqual(catalog.schemaVersion, MaintenanceCatalog.currentSchemaVersion)
        XCTAssertFalse(catalog.catalogVersion.isEmpty)
        XCTAssertFalse(catalog.taskDefinitions.isEmpty)
        XCTAssertFalse(catalog.coverageNotice.isEmpty)

        let issues = CatalogValidator.validate(catalog)
        let errors = issues.filter { $0.severity == .error }
        XCTAssertTrue(errors.isEmpty, "bundled catalog has errors: \(errors.map(\.description))")
    }

    func testBundledCatalogHasNoWarningsEither() throws {
        let catalog = try CatalogLoader.loadBundled()
        let warnings = CatalogValidator.validate(catalog).filter { $0.severity == .warning }
        XCTAssertTrue(warnings.isEmpty, "bundled catalog has warnings: \(warnings.map(\.description))")
    }

    func testNothingInTheBundledCatalogClaimsToBeVerified() throws {
        // Odomind ships no manufacturer-sourced values today, and the app must
        // not display a verified badge for anything it does ship. If a future
        // change adds a genuinely sourced value, this test will point at it so
        // the claim gets reviewed rather than slipping in.
        let catalog = try CatalogLoader.loadBundled()
        for profile in catalog.vehicleProfiles {
            for specification in profile.specifications {
                XCTAssertFalse(
                    specification.provenance.origin == .manufacturerSourced && !specification.provenance.isVerified,
                    "\(profile.id).\(specification.kind.rawValue) claims a manufacturer source without a citation"
                )
            }
            for fact in profile.configurationFacts {
                XCTAssertNotEqual(fact.provenance.origin, .userEntered)
            }
        }
    }

    func testEveryTaskHasAPurposeAndAStableIdentifier() throws {
        let catalog = try CatalogLoader.loadBundled()
        for definition in catalog.taskDefinitions {
            XCTAssertTrue(CatalogValidator.isValidIdentifier(definition.id), "bad id: \(definition.id)")
            XCTAssertFalse(definition.purpose.isEmpty, "\(definition.id) has no purpose")
            XCTAssertFalse(definition.title.isEmpty)
        }
    }

    func testConditionBasedConsumablesGetNoReplacementInterval() throws {
        let catalog = try CatalogLoader.loadBundled()
        let tyreTask = catalog.definition(id: "tire-condition-inspection")
        XCTAssertNotNil(tyreTask)
        XCTAssertEqual(tyreTask?.action, .inspect)
        XCTAssertTrue(tyreTask?.defaultRule?.isInspectionOnly ?? false)

        let brakes = catalog.definition(id: "brake-inspection")
        XCTAssertTrue(brakes?.defaultRule?.isInspectionOnly ?? false)

        // Brake pad replacement exists to record work, not to schedule it.
        let pads = catalog.definition(id: "brake-pad-replacement-note")
        XCTAssertNil(pads?.defaultRule)
    }

    func testDemoContentIsFictionalAndCarriesNoVIN() throws {
        let catalog = try CatalogLoader.loadBundled()
        let demo = try XCTUnwrap(catalog.demoContent)
        XCTAssertNil(demo.identity.vin)
        XCTAssertFalse(demo.disclaimer.isEmpty)
        let ids = Set(catalog.taskDefinitions.map(\.id))
        for service in demo.services {
            for id in service.definitionIDs {
                XCTAssertTrue(ids.contains(id), "demo references unknown task \(id)")
            }
        }
    }

    func testSourcesRecordTheirTermsAndLimitations() throws {
        let catalog = try CatalogLoader.loadBundled()
        XCTAssertFalse(catalog.sources.isEmpty)
        for source in catalog.sources {
            XCTAssertFalse(source.terms.isEmpty, "\(source.id) has no terms")
            XCTAssertFalse(source.coverage.isEmpty, "\(source.id) has no coverage statement")
            XCTAssertFalse(source.limitations.isEmpty, "\(source.id) has no limitations statement")
            if source.attributionRequired {
                XCTAssertFalse((source.attributionText ?? "").isEmpty)
            }
        }
        let vpic = catalog.source(id: "nhtsa-vpic")
        XCTAssertNotNil(vpic)
        XCTAssertFalse(vpic?.allowsRedistribution ?? true, "vPIC must not be marked redistributable")
    }
}

final class CatalogValidationTests: XCTestCase {

    private func minimalCatalog(
        tasks: [MaintenanceTaskDefinition],
        profiles: [VehicleProfile] = [],
        sources: [CatalogSource]? = nil
    ) -> MaintenanceCatalog {
        MaintenanceCatalog(
            catalogVersion: "test",
            publishedOn: makeDate(2026, 1, 1),
            coverageNotice: "Test catalog.",
            sources: sources ?? [
                CatalogSource(
                    id: "test-source",
                    name: "Test source",
                    coverage: "Testing.",
                    terms: "Test only.",
                    allowsRedistribution: true,
                    limitations: "None."
                )
            ],
            taskDefinitions: tasks,
            vehicleProfiles: profiles
        )
    }

    func testUnverifiedManufacturerClaimIsRejected() {
        let profile = VehicleProfile(
            id: "p1",
            displayName: "Test",
            match: VehicleMatch(makes: ["Test"], models: ["Model"]),
            specifications: [
                ProfileSpecification(
                    kind: .engineOilViscosity,
                    value: .text("5W-20"),
                    provenance: Provenance(
                        origin: .manufacturerSourced,
                        attribution: SourceAttribution(sourceName: "Somewhere")
                    ),
                    sourceID: "test-source"
                )
            ]
        )
        let catalog = minimalCatalog(
            tasks: [MaintenanceTaskDefinition(id: "t", title: "T", purpose: "P", category: .engine, action: .replace)],
            profiles: [profile]
        )
        let issues = CatalogValidator.validate(catalog)
        XCTAssertTrue(
            issues.contains { $0.severity == .error && $0.message.contains("source reference and a review date") },
            "a manufacturer claim without a citation must be rejected"
        )
    }

    func testVerifiedManufacturerValueIsAccepted() {
        let profile = VehicleProfile(
            id: "p1",
            displayName: "Test",
            match: VehicleMatch(makes: ["Test"], models: ["Model"], earliestModelYear: 2010, latestModelYear: 2010),
            specifications: [
                ProfileSpecification(
                    kind: .engineOilViscosity,
                    value: .text("5W-20"),
                    provenance: Provenance(
                        origin: .manufacturerSourced,
                        attribution: SourceAttribution(
                            sourceName: "Owner's manual",
                            sourceReference: "page 402",
                            reviewedOn: makeDate(2026, 1, 1),
                            reviewedBy: "maintainer"
                        ),
                        scope: ConfigurationScope(modelYears: [2010])
                    ),
                    sourceID: "test-source"
                )
            ]
        )
        let catalog = minimalCatalog(
            tasks: [MaintenanceTaskDefinition(id: "t", title: "T", purpose: "P", category: .engine, action: .replace)],
            profiles: [profile]
        )
        let errors = CatalogValidator.validate(catalog).filter { $0.severity == .error }
        XCTAssertTrue(errors.isEmpty, "unexpected errors: \(errors.map(\.description))")
    }

    func testDuplicateTaskIdentifiersAreRejected() {
        let task = MaintenanceTaskDefinition(id: "dup", title: "A", purpose: "P", category: .engine, action: .replace)
        let catalog = minimalCatalog(tasks: [task, task])
        let issues = CatalogValidator.validate(catalog)
        XCTAssertTrue(issues.contains { $0.message.contains("Duplicate task id") })
    }

    func testConflictingSchedulesForTheSameTaskAreRejected() {
        let rule = ProfileScheduleRule(
            definitionID: "t",
            rule: .distance(interval: Distance(5_000, .miles)),
            provenance: Provenance.template("Test"),
            sourceID: "test-source"
        )
        var other = rule
        other.rule = .distance(interval: Distance(7_500, .miles))
        let profile = VehicleProfile(
            id: "p1",
            displayName: "Test",
            match: VehicleMatch(makes: ["Test"], models: ["Model"]),
            scheduleRules: [rule, other]
        )
        let catalog = minimalCatalog(
            tasks: [MaintenanceTaskDefinition(id: "t", title: "T", purpose: "P", category: .engine, action: .replace)],
            profiles: [profile]
        )
        XCTAssertTrue(CatalogValidator.validate(catalog).contains { $0.message.contains("Conflicting schedules") })
    }

    func testNonRedistributableSourceCannotShipASchedule() {
        let sources = [
            CatalogSource(
                id: "closed",
                name: "Closed source",
                coverage: "Schedules.",
                terms: "All rights reserved by a third party.",
                allowsRedistribution: false,
                limitations: "Cannot be shipped."
            )
        ]
        let profile = VehicleProfile(
            id: "p1",
            displayName: "Test",
            match: VehicleMatch(makes: ["Test"], models: ["Model"]),
            scheduleRules: [
                ProfileScheduleRule(
                    definitionID: "t",
                    rule: .distance(interval: Distance(5_000, .miles)),
                    provenance: Provenance.template("Closed source"),
                    sourceID: "closed"
                )
            ]
        )
        let catalog = minimalCatalog(
            tasks: [MaintenanceTaskDefinition(id: "t", title: "T", purpose: "P", category: .engine, action: .replace)],
            profiles: [profile],
            sources: sources
        )
        XCTAssertTrue(CatalogValidator.validate(catalog).contains { $0.message.contains("does not permit redistribution") })
    }

    func testTirePressureCannotComeFromAGeneralTemplate() {
        let profile = VehicleProfile(
            id: "p1",
            displayName: "Test",
            match: VehicleMatch(makes: ["Test"], models: ["Model"]),
            specifications: [
                ProfileSpecification(
                    kind: .coldTirePressureFront,
                    value: .pressure(amount: 35, unit: .psi),
                    provenance: Provenance.template("Guesswork"),
                    sourceID: "test-source"
                )
            ]
        )
        let catalog = minimalCatalog(
            tasks: [MaintenanceTaskDefinition(id: "t", title: "T", purpose: "P", category: .engine, action: .replace)],
            profiles: [profile]
        )
        XCTAssertTrue(
            CatalogValidator.validate(catalog).contains { $0.message.contains("vehicle placard") },
            "cold tire pressure must never come from a general template"
        )
    }

    func testMalformedCatalogIsRejectedWithAUsefulMessage() {
        let json = Data(#"{"schemaVersion": 1, "catalogVersion": "x"}"#.utf8)
        XCTAssertThrowsError(try CatalogLoader.load(data: json)) { error in
            guard let loadError = error as? CatalogLoadError else { return XCTFail("wrong error type") }
            guard case .decodingFailed(let detail) = loadError else {
                return XCTFail("expected decodingFailed, got \(loadError)")
            }
            XCTAssertTrue(detail.contains("missing key"), "message should name what is missing: \(detail)")
        }
    }

    func testUnsupportedSchemaVersionIsRejected() throws {
        var catalog = try CatalogLoader.loadBundled()
        catalog.schemaVersion = 99
        let data = try CatalogLoader.makeEncoder().encode(catalog)
        XCTAssertThrowsError(try CatalogLoader.load(data: data)) { error in
            guard let loadError = error as? CatalogLoadError,
                  case .unsupportedSchema(let found, let supported) = loadError else {
                return XCTFail("expected unsupportedSchema, got \(error)")
            }
            XCTAssertEqual(found, 99)
            XCTAssertEqual(supported, MaintenanceCatalog.currentSchemaVersion)
        }
    }

    func testCatalogRoundTripsThroughItsOwnEncoder() throws {
        let original = try CatalogLoader.loadBundled()
        let data = try CatalogLoader.encode(original)
        let reloaded = try CatalogLoader.load(data: data)
        XCTAssertEqual(reloaded, original)
    }
}
