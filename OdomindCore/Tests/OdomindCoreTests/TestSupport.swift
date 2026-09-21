import Foundation
import XCTest
@testable import OdomindCore

// Shared fixtures. Everything here is deterministic: a fixed calendar, fixed
// instants and explicit inputs, so a failure always means a behaviour change
// rather than a slow test machine or a different time zone.

extension Calendar {
    static func fixed(_ timeZoneIdentifier: String = "UTC") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    static let utc = Calendar.fixed("UTC")
}

func makeDate(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    hour: Int = 12,
    minute: Int = 0,
    calendar: Calendar = .utc
) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    guard let date = calendar.date(from: components) else {
        fatalError("Could not build \(year)-\(month)-\(day) in the test calendar")
    }
    return date
}

enum Fixture {
    static let vehicleID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    /// A fixed "created at" used by every fixture.
    ///
    /// Real records are stamped by `SystemClock`, which rounds to the precision
    /// the transfer formats keep. Fixtures use a whole-second instant so a
    /// round-trip assertion tests the format, not the clock.
    static let stamp = makeDate(2026, 1, 1, hour: 9)

    static func vehicle(
        id: UUID = Fixture.vehicleID,
        unit: DistanceUnit = .miles,
        configuration: VehicleConfiguration = Fixture.combustionConfiguration,
        inServiceOn: Date? = nil,
        replacements: [OdometerReplacement] = [],
        createdAt: Date = makeDate(2020, 1, 1)
    ) -> Vehicle {
        Vehicle(
            id: id,
            nickname: "Test vehicle",
            identity: VehicleIdentity(modelYear: 2010, make: "Jeep", model: "Wrangler"),
            configuration: configuration,
            displayUnit: unit,
            inServiceOn: inServiceOn,
            odometerReplacements: replacements,
            createdAt: createdAt
        )
    }

    static var combustionConfiguration: VehicleConfiguration {
        VehicleConfiguration(
            powertrain: .gasoline,
            engineDisplacementLiters: 3.8,
            engineCylinders: 6,
            transmission: .automatic,
            drivetrain: .fourWheelDrivePartTime,
            camshaftDrive: .timingChain,
            market: .unitedStates,
            usageProfile: .normal
        )
    }

    static var electricConfiguration: VehicleConfiguration {
        VehicleConfiguration(
            powertrain: .batteryElectric,
            transmission: .singleSpeedReduction,
            drivetrain: .rearWheelDrive,
            camshaftDrive: .notApplicable,
            market: .unitedStates
        )
    }

    static func reading(
        _ amount: Int,
        on date: Date,
        vehicleID: UUID = Fixture.vehicleID,
        unit: DistanceUnit = .miles
    ) -> OdometerReading {
        OdometerReading(
            vehicleID: vehicleID,
            recordedOn: date,
            value: Distance(amount, unit)
        )
    }

    static func planItem(
        id: UUID = UUID(),
        vehicleID: UUID = Fixture.vehicleID,
        definitionID: String = "engine-oil-and-filter",
        title: String = "Engine oil and filter",
        rule: ScheduleRule?,
        baseline: HistoryBaseline = .notProvided,
        threshold: DueSoonThreshold = DueSoonThreshold(distance: Distance(500, .miles), days: 30),
        snoozedUntil: Date? = nil,
        reminder: ReminderPreference = .disabled,
        createdAt: Date = Fixture.stamp
    ) -> MaintenancePlanItem {
        MaintenancePlanItem(
            id: id,
            vehicleID: vehicleID,
            definitionID: definitionID,
            title: title,
            category: .engine,
            action: .replace,
            catalogRule: rule,
            catalogProvenance: Provenance.template("Odomind maintenance templates"),
            baseline: baseline,
            snoozedUntil: snoozedUntil,
            dueSoonThreshold: threshold,
            reminder: reminder,
            createdAt: createdAt
        )
    }

    static func service(
        on date: Date,
        odometer: Int?,
        definitionIDs: [String] = ["engine-oil-and-filter"],
        vehicleID: UUID = Fixture.vehicleID,
        totalCost: Money? = nil,
        unit: DistanceUnit = .miles,
        stamp: Date = Fixture.stamp
    ) -> ServiceRecord {
        ServiceRecord(
            vehicleID: vehicleID,
            performedOn: date,
            odometer: odometer.map { Distance($0, unit) },
            items: definitionIDs.map {
                ServiceLineItem(definitionID: $0, title: $0, action: .replace)
            },
            totalCost: totalCost,
            createdAt: stamp,
            updatedAt: stamp
        )
    }

    static func context(
        vehicle: Vehicle = Fixture.vehicle(),
        readings: [OdometerReading] = [],
        services: [ServiceRecord] = [],
        declaredTypical: Distance? = nil,
        asOf: Date,
        calendar: Calendar = .utc
    ) -> ScheduleContext {
        ScheduleContext.build(
            vehicle: vehicle,
            readings: readings,
            serviceRecords: services,
            declaredTypicalDistancePerMonth: declaredTypical,
            asOf: asOf,
            calendar: calendar
        )
    }
}

extension ScheduleEvaluation {
    /// Convenience for asserting that a particular explanation was produced.
    func hasReason(_ predicate: (EvaluationReason) -> Bool) -> Bool {
        reasons.contains(where: predicate)
    }
}
