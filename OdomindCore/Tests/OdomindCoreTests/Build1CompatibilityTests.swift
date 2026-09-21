import XCTest
@testable import OdomindCore

/// A real Build 1 backup, read by Build 2.
///
/// This is the gate the architecture note calls a release gate. Build 2 added
/// an optional `artwork` property to `Vehicle`, and the whole argument for not
/// bumping `BackupArchive.formatVersion` is that Swift's synthesised decoding
/// treats a missing optional as `nil`. An argument is not a test. The fixture
/// below is the shape Build 1 actually wrote — no `artwork` key anywhere — and
/// it has to keep importing, unchanged, for as long as anyone might still have
/// one on a phone.
///
/// If this test ever has to be edited to keep passing, that edit *is* the
/// breaking change, and the reader has to be taught the old shape in the same
/// commit. See `docs/ARCHITECTURE.md`.
final class Build1CompatibilityTests: XCTestCase {

    private func fixture() throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "build-1-backup", withExtension: "json"),
            "the Build 1 backup fixture is missing from the test bundle"
        )
        return try Data(contentsOf: url)
    }

    func testABuildOneBackupStillImports() throws {
        let result = BackupImporter.decode(try fixture())
        guard case .success(let archive) = result else {
            return XCTFail("a Build 1 backup must still decode: \(result)")
        }

        XCTAssertEqual(archive.formatVersion, BackupArchive.currentFormatVersion)
        XCTAssertEqual(archive.vehicles.count, 1)
        XCTAssertEqual(archive.readings.count, 1)
        XCTAssertEqual(archive.planItems.count, 1)
        XCTAssertEqual(archive.serviceRecords.count, 1)
    }

    func testEveryRecordSurvivesWithItsValuesIntact() throws {
        guard case .success(let archive) = BackupImporter.decode(try fixture()) else {
            return XCTFail("the fixture did not decode")
        }

        let vehicle = try XCTUnwrap(archive.vehicles.first)
        XCTAssertEqual(vehicle.nickname, "Blake's Jeep")
        XCTAssertEqual(vehicle.identity.modelYear, 2010)
        XCTAssertEqual(vehicle.identity.make, "Jeep")
        XCTAssertEqual(vehicle.displayUnit, .miles)
        XCTAssertEqual(vehicle.configuration.powertrain, .gasoline)
        XCTAssertEqual(vehicle.configuration.camshaftDrive, .timingChain)

        // The point of the whole exercise: no artwork key, no failure, and a
        // `nil` that the resolver knows how to handle.
        XCTAssertNil(vehicle.artwork)

        let reading = try XCTUnwrap(archive.readings.first)
        XCTAssertEqual(reading.value, Distance(209_800, .miles))

        let record = try XCTUnwrap(archive.serviceRecords.first)
        XCTAssertEqual(record.odometer, Distance(204_500, .miles))
        XCTAssertEqual(record.totalCost?.amount, Decimal(string: "68.40"))
        XCTAssertEqual(record.performer.shopName, "Corner Garage")

        // Unknown history stays unknown across the import. A restore that
        // quietly turned "not provided" into a completion would reschedule
        // everything from a date nobody supplied.
        let item = try XCTUnwrap(archive.planItems.first)
        XCTAssertEqual(item.baseline, .notProvided)
        XCTAssertFalse(item.baseline.isAnswered)
    }

    func testABuildOneVehicleStillResolvesToAPicture() throws {
        guard case .success(let archive) = BackupImporter.decode(try fixture()) else {
            return XCTFail("the fixture did not decode")
        }
        let vehicle = try XCTUnwrap(archive.vehicles.first)

        // "Unlimited Sport" is the four-door name, so the vehicle the owner
        // restored gets the matched four-door drawing rather than a fallback.
        XCTAssertEqual(
            VehicleArtworkResolver.resolve(vehicle: vehicle, hasPhoto: false),
            .matchedIllustration(.jeepWranglerJKUnlimited)
        )
    }

    func testTheImportPlanAcceptsItWithNoBlockingIssues() throws {
        guard case .success(let archive) = BackupImporter.decode(try fixture()) else {
            return XCTFail("the fixture did not decode")
        }
        let plan = BackupImporter.plan(
            archive: archive,
            existingVehicleIDs: [],
            existingServiceRecordIDs: [],
            strategy: .replaceEverything
        )
        XCTAssertTrue(
            plan.issues.filter(\.isBlocking).isEmpty,
            "a Build 1 backup must import without a blocking issue: \(plan.issues)"
        )
    }
}
