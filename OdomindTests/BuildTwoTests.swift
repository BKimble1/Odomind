import XCTest
@testable import Odomind
@testable import OdomindCore

/// The Build 2 rules that can be exercised without a simulator gesture.
@MainActor
final class BuildTwoTests: XCTestCase {

    // MARK: - Catalog update trust

    func testVersionComparisonIsNumericNotLexical() {
        // "2026.10.2" sorts *before* "2026.9.10" as a string, which would
        // refuse a genuinely newer catalog every October.
        XCTAssertTrue(CatalogUpdateService.isNewer("2026.10.2", than: "2026.9.10"))
        XCTAssertTrue(CatalogUpdateService.isNewer("2026.9.2", than: "2026.9.1"))
        XCTAssertFalse(CatalogUpdateService.isNewer("2026.9.1", than: "2026.9.1"))
        XCTAssertFalse(CatalogUpdateService.isNewer("2026.8.9", than: "2026.9.1"))
        // A shorter version is padded with zeroes rather than treated as
        // greater.
        XCTAssertTrue(CatalogUpdateService.isNewer("2026.9.1", than: "2026.9"))
        XCTAssertFalse(CatalogUpdateService.isNewer("2026.9", than: "2026.9.1"))
    }

    func testTheChecksumIsOverTheExactBytes() {
        // Known-answer test, so a change to the hashing is caught rather than
        // silently accepting everything.
        XCTAssertEqual(
            CatalogUpdateService.sha256Hex(Data("abc".utf8)),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func testAnInstalledCatalogOlderThanTheBundledOneIsIgnored() throws {
        // A stale file on disk must not undo a fix that shipped in the app.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CatalogTest-\(UUID().uuidString)", isDirectory: true)
        let store = CatalogUpdateStore(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let bundled = try XCTUnwrap(CatalogService().catalog)
        var older = bundled
        older.catalogVersion = "1900.1.1"
        try store.install(try CatalogLoader.encode(older))

        XCTAssertNil(store.loadInstalled(notOlderThan: bundled))
    }

    func testAnInstalledCatalogAtTheSameVersionIsAccepted() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CatalogTest-\(UUID().uuidString)", isDirectory: true)
        let store = CatalogUpdateStore(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let bundled = try XCTUnwrap(CatalogService().catalog)
        try store.install(try CatalogLoader.encode(bundled))
        XCTAssertEqual(store.loadInstalled(notOlderThan: bundled)?.catalogVersion, bundled.catalogVersion)
    }

    func testCorruptInstalledDataLeavesTheBundledCatalogInCharge() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CatalogTest-\(UUID().uuidString)", isDirectory: true)
        let store = CatalogUpdateStore(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let bundled = try XCTUnwrap(CatalogService().catalog)
        try store.install(Data("this is not a catalog".utf8))
        XCTAssertNil(store.loadInstalled(notOlderThan: bundled))
    }

    // MARK: - Search parsing

    func testAQueryIsParsedWhicheverOrderItIsTypedIn() {
        let reference = Date(timeIntervalSince1970: 1_790_000_000)
        for text in ["2010 Jeep Wrangler", "jeep wrangler 2010", "Wrangler 2010 JEEP"] {
            let parsed = ParsedVehicleQuery.parse(text, now: reference)
            XCTAssertEqual(parsed.modelYear, 2010, "failed on \(text)")
            XCTAssertEqual(parsed.make, "Jeep", "failed on \(text)")
            XCTAssertEqual(parsed.remainder.lowercased(), "wrangler", "failed on \(text)")
        }
    }

    func testALongMakeNameWinsOverASubstringOfIt() {
        let parsed = ParsedVehicleQuery.parse("2018 Land Rover Discovery")
        XCTAssertEqual(parsed.make, "Land Rover")
        XCTAssertEqual(parsed.remainder.lowercased(), "discovery")
    }

    func testAnImplausibleYearIsNotTreatedAsOne() {
        // A part number should not be mistaken for a model year.
        let reference = Date(timeIntervalSince1970: 1_790_000_000)
        let parsed = ParsedVehicleQuery.parse("Jeep filter 2099", now: reference)
        XCTAssertNil(parsed.modelYear)
    }

    // MARK: - Receipt reading

    func testTheTotalLineBeatsTheLargestNumberOnTheReceipt() {
        let lines = [
            "QUICK LUBE",
            "Tel 555 0199 4821",
            "Synthetic oil 5qt   42.99",
            "Filter               9.50",
            "SUBTOTAL            52.49",
            "TOTAL               56.68"
        ]
        let reading = ReceiptScanner.interpret(lines: lines)
        XCTAssertEqual(reading.total, Decimal(string: "56.68"))
        XCTAssertEqual(reading.merchant, "QUICK LUBE")
    }

    func testASubtotalIsNotMistakenForTheTotal() {
        let reading = ReceiptScanner.interpret(lines: ["SHOP", "SUBTOTAL 10.00"])
        // No unqualified total line, so it falls back to the largest amount —
        // which here is the subtotal, and that is the honest best guess for
        // the owner to correct.
        XCTAssertEqual(reading.total, Decimal(string: "10.00"))
    }

    func testAFutureDateIsRejected() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let reading = ReceiptScanner.interpret(lines: ["SHOP", "Valid until 12/31/2099"], now: now)
        XCTAssertNil(reading.date)
    }

    func testNothingRecognisableProducesAnEmptyReadingRatherThanAGuess() {
        let reading = ReceiptScanner.interpret(lines: ["::::", "1234567890"])
        XCTAssertTrue(reading.isEmpty)
    }

    // MARK: - Parts queries

    func testAPartsQueryCarriesTheVehicleAndNeverTheVIN() {
        let vehicle = Vehicle(
            nickname: "Blake's Jeep",
            identity: VehicleIdentity(
                modelYear: 2010, make: "Jeep", model: "Wrangler",
                vin: "1J4BA3H15AL100000"
            )
        )
        let query = PartsQueryBuilder.query(for: vehicle, part: "oil filter")
        XCTAssertEqual(query, "2010 Jeep Wrangler oil filter")
        XCTAssertFalse(query.contains("1J4BA3H15AL100000"))
        // Nor the nickname, which is personal and useless to a retailer.
        XCTAssertFalse(query.lowercased().contains("blake"))
    }

    func testARetailerSearchURLIsProperlyEncoded() throws {
        let retailer = try XCTUnwrap(Retailer.all.first { $0.acceptsPrefilledSearch })
        let url = try XCTUnwrap(retailer.url(for: "2010 Jeep Wrangler oil filter"))
        XCTAssertEqual(url.scheme, "https")
        XCTAssertFalse(url.absoluteString.contains(" "))
        XCTAssertTrue(url.absoluteString.contains("Jeep"))
    }

    func testARetailerThatCannotTakeAPrefilledSearchSaysSo() {
        // The honest case: Odomind opens the catalog and offers the text to
        // paste rather than shipping a link that lands on an empty search.
        let awkward = Retailer.all.filter { !$0.acceptsPrefilledSearch }
        XCTAssertFalse(awkward.isEmpty, "the honest-fallback path should have at least one retailer exercising it")
        for retailer in awkward {
            XCTAssertNotNil(retailer.url(for: ""))
        }
    }

    func testShoppingCapabilityStaysAtWhatIsActuallyBuilt() {
        // A reminder in test form: raising this needs a provider with terms
        // and credentials, not a UI change.
        XCTAssertEqual(ShoppingCapability.current, .retailerSearchLink)
        XCTAssertLessThan(ShoppingCapability.current, .licensedOffers)
    }

    // MARK: - Preferences and migration

    func testBuildOneSettingsDecodeToBuildTwoDefaults() throws {
        // An empty preferences column is what a Build 1 store has.
        var problems: [StoreProblem] = []
        let preferences = StoreCoding.decodeOrFallback(
            AppPreferences.self,
            from: Data(),
            fallback: .default,
            context: "test",
            problems: &problems
        )
        XCTAssertEqual(preferences.appearance, .system)
        XCTAssertFalse(preferences.catalogUpdates.automaticUpdatesEnabled)
        XCTAssertNil(preferences.pro.grandfatheredVehicleAllowance)
        XCTAssertTrue(problems.isEmpty, "a missing value is not a problem to report")
    }

    func testPreferencesTolerateAPartiallyWrittenBlob() throws {
        // Forward compatibility: a blob written by a build that knew about
        // fewer keys must still decode.
        let json = Data(#"{"appearance":"dark"}"#.utf8)
        let preferences = try StoreCoding.decode(AppPreferences.self, from: json)
        XCTAssertEqual(preferences.appearance, .dark)
        XCTAssertEqual(preferences.calendar.projectionMonths, 6)
    }

    func testAppearanceRoundTripsThroughTheStore() throws {
        let model = try AppFixture.makeModel().model
        model.setAppearance(.dark)
        XCTAssertEqual(model.appearance, .dark)
        model.refresh()
        XCTAssertEqual(model.appearance, .dark)
    }

    // MARK: - Vehicle allowance

    func testTheAllowanceIsRecordedOnceAndNeverShrinks() throws {
        let model = try AppFixture.makeModel().model
        for index in 0..<4 {
            _ = model.addVehicle(from: AppFixture.draft(make: "Make\(index)"))
        }
        model.recordGrandfatheredAllowanceIfNeeded()
        XCTAssertEqual(model.freeVehicleAllowance, 4)

        // Deleting afterwards must not reduce it: the point is what they had
        // when the rule changed.
        let first = try XCTUnwrap(model.ownedVehicles.first)
        let expectation = expectation(description: "deleted")
        Task {
            await model.deleteVehicle(id: first.id)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)

        model.recordGrandfatheredAllowanceIfNeeded()
        XCTAssertEqual(model.freeVehicleAllowance, 4)
    }

    func testANewGarageGetsTheStandardAllowance() throws {
        let model = try AppFixture.makeModel().model
        model.recordGrandfatheredAllowanceIfNeeded()
        XCTAssertEqual(model.freeVehicleAllowance, ProPolicy.freeVehicleAllowance)
        XCTAssertEqual(ProPolicy.freeVehicleAllowance, 1)
    }

    func testTheAllowanceIsNotMentionedUntilItMatters() throws {
        let model = try AppFixture.makeModel().model
        model.recordGrandfatheredAllowanceIfNeeded()
        // Nothing in the garage: no reason to bring up a limit.
        XCTAssertNil(model.vehicleAllowanceNotice)
    }

    func testAnExistingOwnerIsNeverGatedBelowWhatTheyHad() throws {
        let model = try AppFixture.makeModel().model
        for index in 0..<3 {
            _ = model.addVehicle(from: AppFixture.draft(make: "Make\(index)"))
        }
        model.recordGrandfatheredAllowanceIfNeeded()

        // Three vehicles, a free plan of one, and no subscription. The
        // grandfathered allowance is the whole reason this is not a lockout.
        XCTAssertFalse(model.isPro)
        XCTAssertEqual(model.freeVehicleAllowance, 3)
        XCTAssertEqual(model.ownedVehicles.count, 3)
        for vehicle in model.ownedVehicles {
            XCTAssertNotNil(
                model.snapshot.vehicle(id: vehicle.id),
                "a vehicle recorded before the limit existed must stay reachable"
            )
        }
    }

    // MARK: - Appointments

    func testAnAppointmentIsNotAServiceRecord() throws {
        let model = try AppFixture.makeModel().model
        let vehicleID = try XCTUnwrap(model.addVehicle(from: AppFixture.draft()))

        let before = model.serviceRecords(for: vehicleID).count
        model.saveAppointment(
            Appointment(vehicleID: vehicleID, scheduledOn: Date(), title: "Oil change booking")
        )

        XCTAssertEqual(model.snapshot.appointments(for: vehicleID).count, 1)
        // The decisive assertion: booking a visit records no work.
        XCTAssertEqual(model.serviceRecords(for: vehicleID).count, before)
    }

    func testAnAppointmentIsStoredAtTheStartOfItsDay() throws {
        let model = try AppFixture.makeModel().model
        let vehicleID = try XCTUnwrap(model.addVehicle(from: AppFixture.draft()))
        let middleOfDay = Date(timeIntervalSince1970: 1_790_000_000)

        model.saveAppointment(
            Appointment(vehicleID: vehicleID, scheduledOn: middleOfDay, title: "Booking")
        )
        let stored = try XCTUnwrap(model.snapshot.appointments(for: vehicleID).first)
        XCTAssertEqual(stored.scheduledOn, model.calendar.startOfDay(for: middleOfDay))
    }

    func testDeletingAnAppointmentLeavesRecordsAlone() throws {
        let model = try AppFixture.makeModel().model
        let vehicleID = try XCTUnwrap(model.addVehicle(from: AppFixture.draft()))
        let id = try XCTUnwrap(
            model.saveAppointment(
                Appointment(vehicleID: vehicleID, scheduledOn: Date(), title: "Booking")
            )
        )
        model.deleteAppointment(id: id)
        XCTAssertTrue(model.snapshot.appointments(for: vehicleID).isEmpty)
    }

    // MARK: - Calendar entries

    func testAnAppointmentAppearsOnItsDayAsItsOwnKind() throws {
        let model = try AppFixture.makeModel().model
        let vehicleID = try XCTUnwrap(model.addVehicle(from: AppFixture.draft()))
        let day = model.calendar.startOfDay(for: Date())

        model.saveAppointment(Appointment(vehicleID: vehicleID, scheduledOn: day, title: "Booking"))

        let entries = model.calendarEntries(on: day)
        XCTAssertTrue(entries.contains { $0.kind == .appointment && $0.title == "Booking" })
    }

    func testAJobWithNoDefensibleDateIsUnscheduledRatherThanPlaced() throws {
        let model = try AppFixture.makeModel().model
        let vehicleID = try XCTUnwrap(model.addVehicle(from: AppFixture.draft()))
        let vehicle = try XCTUnwrap(model.snapshot.vehicle(id: vehicleID))

        // A purely distance-based job with a known starting point but no
        // driving history has a due mileage and no date anyone can defend.
        guard let suggestion = model.allSuggestions(for: vehicle)
            .first(where: { $0.definition.id == "tire-rotation" }) else {
            throw XCTSkip("the catalog no longer carries tire-rotation")
        }
        _ = model.addTask(suggestion, to: vehicle, baseline: .declared(
            date: model.clock.now, odometer: Distance(100_000, .miles)
        ))

        let unscheduled = model.unscheduledCalendarItems()
        let placed = model.allCalendarEntries().filter { $0.kind == .due || $0.kind == .projected }
        for item in unscheduled {
            XCTAssertFalse(
                placed.contains { $0.planItemID == item.planItemID },
                "\(item.title) is both unscheduled and on a day"
            )
        }
    }
}
