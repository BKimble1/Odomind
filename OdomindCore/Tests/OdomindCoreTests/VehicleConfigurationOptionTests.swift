import XCTest
@testable import OdomindCore

/// Mapping a provider's own words onto Odomind's configuration.
///
/// Every string below is a value from fueleconomy.gov's published vocabulary,
/// not one invented for the test. The rule under all of it: a field the
/// provider did not state stays unset, because a wrong drivetrain silently
/// adds or removes whole jobs from a plan.
final class VehicleConfigurationOptionTests: XCTestCase {

    private func option(
        fuel: String? = nil,
        drive: String? = nil,
        transmission: String? = nil,
        displacement: Double? = nil,
        cylinders: Int? = nil
    ) -> VehicleConfigurationOption {
        VehicleConfigurationOption(
            id: "12345",
            providerName: "Test provider",
            label: "test option",
            engineDisplacementLiters: displacement,
            cylinders: cylinders,
            transmissionDescription: transmission,
            driveDescription: drive,
            fuelDescription: fuel,
            retrievedOn: Date(timeIntervalSince1970: 1_780_000_000)
        )
    }

    // MARK: - Powertrain

    func testOrdinaryFuelDescriptionsMapToGasoline() {
        for fuel in ["Regular Gasoline", "Premium Gasoline", "Midgrade Gasoline", "Gasoline or E85"] {
            XCTAssertEqual(option(fuel: fuel).powertrain, .gasoline, "for \(fuel)")
        }
    }

    func testDieselIsDiesel() {
        XCTAssertEqual(option(fuel: "Diesel").powertrain, .diesel)
    }

    func testElectricityAloneIsBatteryElectric() {
        XCTAssertEqual(option(fuel: "Electricity").powertrain, .batteryElectric)
    }

    func testFuelAndElectricityIsAPlugIn() {
        for fuel in ["Premium and Electricity", "Regular Gas and Electricity"] {
            XCTAssertEqual(option(fuel: fuel).powertrain, .pluginHybrid, "for \(fuel)")
        }
    }

    func testAnUnrecognisedFuelLeavesThePowertrainUnknown() {
        XCTAssertEqual(option(fuel: "Compressed Natural Gas").powertrain, .unknown)
        XCTAssertEqual(option(fuel: nil).powertrain, .unknown)
    }

    // MARK: - Drivetrain

    func testEachStatedDrivetrainMaps() {
        XCTAssertEqual(option(drive: "Front-Wheel Drive").drivetrain, .frontWheelDrive)
        XCTAssertEqual(option(drive: "Rear-Wheel Drive").drivetrain, .rearWheelDrive)
        XCTAssertEqual(option(drive: "All-Wheel Drive").drivetrain, .allWheelDrive)
        XCTAssertEqual(option(drive: "Part-time 4-Wheel Drive").drivetrain, .fourWheelDrivePartTime)
    }

    func testFourWheelDriveWithNoSubTypeStaysUndifferentiated() {
        // The provider said 4WD and nothing more. `.fourWheelDrive` exists so
        // that Odomind can record exactly that much.
        XCTAssertEqual(option(drive: "4-Wheel Drive").drivetrain, .fourWheelDrive)
    }

    func testAnAmbiguousDrivetrainIsRefusedRatherThanGuessed() {
        // A real value in this vocabulary, and it means the source does not
        // distinguish the two. Resolving it either way would decide whether a
        // transfer-case service appears in the plan.
        XCTAssertEqual(option(drive: "4-Wheel or All-Wheel Drive").drivetrain, .unknown)
    }

    // MARK: - Transmission

    func testTransmissionWordings() {
        XCTAssertEqual(option(transmission: "Automatic (S6)").transmission, .automatic)
        XCTAssertEqual(option(transmission: "Automatic 4-spd").transmission, .automatic)
        XCTAssertEqual(option(transmission: "Manual 6-spd").transmission, .manual)
        XCTAssertEqual(
            option(transmission: "Automatic (variable gear ratios)").transmission,
            .continuouslyVariable
        )
        XCTAssertEqual(option(transmission: "Automated Manual-Selectable").transmission, .dualClutch)
        XCTAssertEqual(option(transmission: nil).transmission, .unknown)
    }

    // MARK: - Applying it

    func testApplyingFillsOnlyWhatTheProviderStated() {
        let chosen = option(
            fuel: "Regular Gasoline",
            drive: "Part-time 4-Wheel Drive",
            transmission: "Automatic 4-spd",
            displacement: 3.8,
            cylinders: 6
        )
        let updated = chosen.applied(to: VehicleConfiguration())

        XCTAssertEqual(updated.powertrain, .gasoline)
        XCTAssertEqual(updated.drivetrain, .fourWheelDrivePartTime)
        XCTAssertEqual(updated.transmission, .automatic)
        XCTAssertEqual(updated.engineDisplacementLiters, 3.8)
        XCTAssertEqual(updated.engineCylinders, 6)
        // Untouched, because the provider said nothing about it.
        XCTAssertEqual(updated.camshaftDrive, .unknown)
        XCTAssertEqual(updated.market, .unspecified)
    }

    func testApplyingNeverOverwritesWhatTheOwnerConfirmed() {
        // The owner was looking at their own car. The provider was looking at
        // a table of what was sold.
        var existing = VehicleConfiguration()
        existing.drivetrain = .rearWheelDrive
        existing.confirmedFields = ["drivetrain"]

        let updated = option(fuel: "Regular Gasoline", drive: "All-Wheel Drive").applied(to: existing)
        XCTAssertEqual(updated.drivetrain, .rearWheelDrive, "a confirmed answer is not a suggestion")
        XCTAssertEqual(updated.powertrain, .gasoline, "unconfirmed fields still fill in")
    }

    func testAnOptionThatStatesNothingChangesNothing() {
        let before = VehicleConfiguration()
        XCTAssertEqual(option().applied(to: before), before)
    }
}
