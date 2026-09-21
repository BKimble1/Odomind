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
            providerKey: "test-provider",
            label: "test option",
            engineDisplacementLiters: displacement,
            cylinders: cylinders,
            transmissionDescription: transmission,
            driveDescription: drive,
            fuelDescription: fuel,
            retrievedOn: Date(timeIntervalSince1970: 1_780_000_000)
        )
    }

    // MARK: - Values this service actually returned
    //
    // Recorded from a live probe on 2026-09-21, for the three vehicles the
    // brief names. Written down because the vocabulary is the thing most
    // likely to move under this code, and a test written from memory of an
    // API is a test of the memory.

    func testTheExactValuesObservedForA2010JeepWrangler() {
        // fueleconomy.gov id 29531, "Wrangler 2WD":
        // displ 3.8, cylinders 6, drive "Rear-Wheel Drive",
        // trany "Automatic 4-spd", fuelType "Regular".
        let observed = option(
            fuel: "Regular",
            drive: "Rear-Wheel Drive",
            transmission: "Automatic 4-spd",
            displacement: 3.8,
            cylinders: 6
        )
        // Note "Regular", not "Regular Gasoline". The service says the grade,
        // not the fuel, and reading it as unknown would have left every
        // petrol car asking the owner what it runs on.
        XCTAssertEqual(observed.powertrain, .gasoline)
        XCTAssertEqual(observed.drivetrain, .rearWheelDrive)
        XCTAssertEqual(observed.transmission, .automatic)
        XCTAssertEqual(observed.engineDisplacementLiters, 3.8)
        XCTAssertEqual(observed.cylinders, 6)
    }

    func testTheExactValuesObservedForA2015ToyotaCamry() {
        // id 35734: displ 2.5, cylinders 4, drive "Front-Wheel Drive",
        // trany "Automatic (S6)", fuelType "Regular".
        let observed = option(
            fuel: "Regular",
            drive: "Front-Wheel Drive",
            transmission: "Automatic (S6)",
            displacement: 2.5,
            cylinders: 4
        )
        XCTAssertEqual(observed.powertrain, .gasoline)
        XCTAssertEqual(observed.drivetrain, .frontWheelDrive)
        XCTAssertEqual(observed.transmission, .automatic)
    }

    func testTheExactValuesObservedForA2018FordF150() {
        // id 39243: displ 2.7, cylinders 6, drive "Rear-Wheel Drive",
        // trany "Automatic (S10)", fuelType "Regular", eng_dscr "SIDI & PFI".
        let observed = option(
            fuel: "Regular",
            drive: "Rear-Wheel Drive",
            transmission: "Automatic (S10)",
            displacement: 2.7,
            cylinders: 6
        )
        XCTAssertEqual(observed.powertrain, .gasoline)
        XCTAssertEqual(observed.drivetrain, .rearWheelDrive)
        // A ten-speed automatic. The wording carries a number this mapping
        // must not choke on.
        XCTAssertEqual(observed.transmission, .automatic)
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
        // The bug this caught: matching the substring "gas" read
        // "Compressed Natural Gas" as a petrol car. Petrol is matched by its
        // named grades instead.
        XCTAssertEqual(option(fuel: "Compressed Natural Gas").powertrain, .unknown)
        XCTAssertEqual(option(fuel: "CNG").powertrain, .unknown)
        XCTAssertEqual(option(fuel: nil).powertrain, .unknown)
    }

    func testABiFuelVehicleIsStillAPetrolOne() {
        // "Gasoline or propane" is a real value in this vocabulary. It has a
        // petrol engine, and everything Odomind decides from the powertrain —
        // oil, spark plugs, coolant — follows from that rather than from the
        // second fuel.
        XCTAssertEqual(option(fuel: "Gasoline or propane").powertrain, .gasoline)
        XCTAssertEqual(option(fuel: "Gasoline or natural gas").powertrain, .gasoline)
    }

    func testAnUnmodelledCombinationWithElectricityIsRefused() {
        // Not a plug-in, because nothing here says it burns petrol or diesel.
        XCTAssertEqual(option(fuel: "Hydrogen and Electricity").powertrain, .unknown)
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

    func testAnOptionThatStatesNothingStillRecordsWhichOptionItWas() {
        // The identifier is not a fact about the car, it is a record of what
        // the owner picked — so it is kept even when the option itself stated
        // nothing else.
        let before = VehicleConfiguration()
        let after = VehicleConfigurationOption(
            id: "12345",
            providerName: "Test provider",
            providerKey: "test-provider",
            label: "test option"
        ).applied(to: before)
        XCTAssertEqual(after.externalIdentifiers["test-provider"], "12345")
        XCTAssertEqual(after.powertrain, before.powertrain, "it states nothing else, so nothing else moves")
        XCTAssertEqual(after.drivetrain, before.drivetrain)
    }

    func testTheProvidersIdentifierIsNamespacedOntoTheVehicle() {
        let chosen = VehicleConfigurationOption(
            id: "29531",
            providerName: "fueleconomy.gov (US DOE/EPA)",
            providerKey: "fueleconomy.gov",
            label: "Auto 4-spd, 6 cyl, 3.8 L",
            driveDescription: "Rear-Wheel Drive",
            fuelDescription: "Regular"
        )
        let updated = chosen.applied(to: VehicleConfiguration())
        XCTAssertEqual(
            updated.externalIdentifiers["fueleconomy.gov"], "29531",
            "an id is only meaningful next to the service that issued it"
        )
    }

    func testAConfigurationSavedBeforeThisFieldExistedStillDecodes() {
        // The shape a vehicle saved by Build 2 has on disk. A synthesised
        // decoder requires every key, so adding a field without this would
        // mean a garage that comes back empty on upgrade.
        let old = Data("""
        {"powertrain":"gasoline","transmission":"automatic","drivetrain":"fourWheelDrivePartTime",
         "camshaftDrive":"timingChain","transferCase":"fitted","frontDifferential":"fitted",
         "rearDifferential":"fitted","market":"unitedStates","usageProfile":"unspecified",
         "confirmedFields":[],"engineDisplacementLiters":3.8}
        """.utf8)
        let decoded = try? JSONDecoder().decode(VehicleConfiguration.self, from: old)
        XCTAssertNotNil(decoded, "a configuration written before externalIdentifiers must still read")
        XCTAssertEqual(decoded?.powertrain, .gasoline)
        XCTAssertEqual(decoded?.engineDisplacementLiters, 3.8)
        XCTAssertEqual(decoded?.externalIdentifiers, [:], "absent means empty, not a failure")
    }

    func testAnOptionRoundTripsThroughItsOwnEncoding() {
        let chosen = option(fuel: "Regular", drive: "Front-Wheel Drive", displacement: 2.5)
        guard let data = try? JSONEncoder().encode(chosen),
              let back = try? JSONDecoder().decode(VehicleConfigurationOption.self, from: data) else {
            return XCTFail("an option should survive its own encoding")
        }
        XCTAssertEqual(back, chosen)
    }
}
