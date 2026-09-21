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

    func testTheBundledCatalogPassesTheSameBarAnUpdateHasTo() throws {
        // The updater is strict, and the bundled catalog is the reference for
        // what strict means. If this ever fails, the bar moved.
        let bundled = try XCTUnwrap(CatalogService().catalog)
        XCTAssertTrue(
            CatalogValidator.validate(bundled).isEmpty,
            "the bundled catalog must clear the same bar a downloaded one has to: \(CatalogValidator.validate(bundled))"
        )
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

    func testAMissingManifestIsReportedAsNotPublishedRatherThanAnOutage() async throws {
        // Build 3 finding: the manifest location has never held a file — the
        // `catalog` ref does not exist on the repository — so every check
        // answered "the update service did not answer", which reads as an
        // outage and blames the wrong thing. The host answered perfectly
        // well; nobody has published anything.
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        StubURLProtocol.handler = { _ in .init(statusCode: 404, body: Data("Not Found".utf8)) }

        let bundled = try XCTUnwrap(CatalogService().catalog)
        let service = CatalogUpdateService(
            store: CatalogUpdateStore(directory: Self.scratchDirectory()),
            session: StubURLProtocol.makeSession(),
            manifestURL: CatalogUpdateService.manifestURL
        )
        let result = await service.check(against: bundled)

        guard case .notPublished = result else {
            return XCTFail("a 404 on the manifest means nothing is published, got \(result)")
        }
    }

    func testARealOutageIsStillReportedAsAnOutage() async throws {
        StubURLProtocol.reset()
        defer { StubURLProtocol.reset() }
        StubURLProtocol.handler = { _ in .init(statusCode: 503, body: Data()) }

        let bundled = try XCTUnwrap(CatalogService().catalog)
        let service = CatalogUpdateService(
            store: CatalogUpdateStore(directory: Self.scratchDirectory()),
            session: StubURLProtocol.makeSession(),
            manifestURL: CatalogUpdateService.manifestURL
        )
        let result = await service.check(against: bundled)

        guard case .unreachable = result else {
            return XCTFail("a 503 is the service being down, got \(result)")
        }
    }

    func testTheUpdateLocationIsTheHostTheUpdaterPinsTo() {
        // The pinned-host check is only worth anything while the shipped
        // manifest URL is actually on that host.
        XCTAssertEqual(CatalogUpdateService.manifestURL.scheme, "https")
        XCTAssertEqual(CatalogUpdateService.manifestURL.host, CatalogUpdateService.catalogHost)
    }

    private static func scratchDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("CatalogTest-\(UUID().uuidString)", isDirectory: true)
    }

    // MARK: - Search parsing
    //
    // The planner replaced ParsedVehicleQuery. Its behaviour is covered in
    // depth by OdomindCore's VehicleSearchMatchingTests, which run against the
    // real generated index; what is kept here is the app-level shape.

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

    func testARecognisedDateIsNeverInTheFuture() {
        // The assertion this started as — that a receipt mentioning 2099
        // yields no date at all — was wrong about the mechanism.
        // `NSDataDetector` is happy to resolve a vague phrase like
        // "Valid until …" against the reference date, so it returns *today*
        // rather than nothing. Today is harmless (it is the field's default
        // anyway, and the owner reviews it before anything is saved), and the
        // guarantee that actually matters is the one asserted here: whatever
        // it makes of the text, a receipt is never dated ahead of the moment
        // it was read.
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let reading = ReceiptScanner.interpret(
            lines: ["SHOP", "Valid until 12/31/2099", "Warranty through 2099"],
            now: now
        )
        if let date = reading.date {
            XCTAssertLessThanOrEqual(date, now, "a receipt cannot be dated in the future")
        }
    }

    func testARealReceiptDateIsPickedUp() throws {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let reading = ReceiptScanner.interpret(
            lines: ["QUICK LUBE", "03/14/2026", "TOTAL 56.68"],
            now: now
        )
        let date = try XCTUnwrap(reading.date, "a plain date on a receipt should be read")
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: date)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 3)
    }

    func testADateOlderThanTenYearsIsIgnored() {
        // Almost always a misread part number rather than a transaction date.
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let reading = ReceiptScanner.interpret(lines: ["SHOP", "01/02/1998"], now: now)
        if let date = reading.date {
            let cutoff = Calendar(identifier: .gregorian)
                .date(byAdding: .year, value: -10, to: now) ?? now
            XCTAssertGreaterThanOrEqual(date, cutoff)
        }
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

    func testAPartNameCannotAddAParameterToARetailersURL() throws {
        // "oil & filter" through `.urlQueryAllowed` leaves the ampersand
        // intact, which turns the rest of the term into a second query
        // parameter on somebody else's site.
        let retailer = try XCTUnwrap(Retailer.all.first { $0.acceptsPrefilledSearch })
        let url = try XCTUnwrap(retailer.url(for: "2010 Jeep Wrangler oil & filter ?x=1"))
        let tail = url.absoluteString.replacingOccurrences(
            of: retailer.searchTemplate.replacingOccurrences(of: "{query}", with: ""),
            with: ""
        )
        XCTAssertFalse(tail.contains("&"), "an ampersand in the term must not survive: \(url)")
        XCTAssertFalse(tail.contains("?"), "a question mark in the term must not survive: \(url)")
        XCTAssertFalse(tail.contains("="), "an equals in the term must not survive: \(url)")
        // And the term is still actually searchable.
        XCTAssertTrue(url.absoluteString.contains("Wrangler"))
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

/// The vehicle search's ordering rules.
///
/// These are the behaviours that are invisible when they work and produce a
/// baffling bug report when they do not: a slow answer landing after a newer
/// one, or one request per keystroke.
@MainActor
final class VehicleSearchTests: XCTestCase {

    /// A model with the real bundled index loaded, because an empty index
    /// exercises a different path than the app ever takes.
    private func makeSearch(_ provider: VehicleIdentificationProvider) async -> VehicleSearchModel {
        let search = VehicleSearchModel(provider: provider, clock: FixedClock(Date()))
        await search.loadIndex()
        return search
    }

    // MARK: - The thing Build 3 exists to fix

    func testAModelNameAloneReachesTheProviderWithoutAYear() async throws {
        let provider = ScriptedModelProvider()
        let search = await makeSearch(provider)

        // No year, no make. Build 2 answered this with "type more".
        search.search("wrangler", debounce: .zero)

        let called = await provider.waitForCall(make: "JEEP")
        XCTAssertTrue(called, "a bare model name must reach the provider")

        await provider.answer(make: "JEEP", with: ["Wrangler", "Wrangler JK", "Cherokee"])
        try await waitUntil { if case .results = search.state { return true }; return false }

        guard case .results(let results) = search.state else {
            return XCTFail("expected results, got \(search.state)")
        }
        XCTAssertEqual(results.first?.model, "Wrangler")
        XCTAssertNil(results.first?.modelYear, "the year is asked for after selection, not before searching")
    }

    func testExtraTrimWordsNarrowRatherThanEliminate() async throws {
        let provider = ScriptedModelProvider()
        let search = await makeSearch(provider)

        search.search("2010 Jeep Wrangler Unlimited Sport", debounce: .zero)
        _ = await provider.waitForCall(make: "JEEP")
        await provider.answer(make: "JEEP", with: ["Wrangler", "Cherokee", "Compass"])
        try await waitUntil { if case .results = search.state { return true }; return false }

        guard case .results(let results) = search.state else {
            return XCTFail("expected results, got \(search.state)")
        }
        XCTAssertEqual(results.first?.model, "Wrangler", "the trim words must not delete the model")
        XCTAssertEqual(results.first?.modelYear, 2010)
        XCTAssertEqual(search.trimHint, "unlimited sport", "the extra words become a refinement")
    }

    func testAMakeAloneListsWhatItBuilds() async throws {
        let provider = ScriptedModelProvider()
        let search = await makeSearch(provider)

        search.search("Jeep", debounce: .zero)
        let called = await provider.waitForCall(make: "JEEP")
        XCTAssertTrue(called)
    }

    func testShorthandResolvesToTheRealMake() async throws {
        let provider = ScriptedModelProvider()
        let search = await makeSearch(provider)

        search.search("chevy", debounce: .zero)
        let called = await provider.waitForCall(make: "CHEVROLET")
        XCTAssertTrue(called, "chevy should be asked about as Chevrolet")
    }

    func testPartOfAMakeSuggestsWithoutAskingTheProvider() async throws {
        let provider = ScriptedModelProvider()
        let search = await makeSearch(provider)

        search.search("jee", debounce: .zero)
        try await Task.sleep(nanoseconds: 150_000_000)

        guard case .makeSuggestions(let makes) = search.state else {
            return XCTFail("expected make suggestions, got \(search.state)")
        }
        XCTAssertTrue(makes.contains("JEEP"))
        let count = await provider.callCount()
        XCTAssertEqual(count, 0, "suggesting a make needs no request")
    }

    func testIndexResultsAreNotReplacedByASpinner() async throws {
        // The index puts real results on screen the instant somebody types a
        // model name. Showing a spinner over them while the provider confirms
        // the same thing is a flicker that makes them pointless.
        let provider = ScriptedModelProvider()
        let search = await makeSearch(provider)

        search.search("wrangler", debounce: .zero)

        guard case .results(let immediate) = search.state else {
            return XCTFail("the index should answer immediately, got \(search.state)")
        }
        XCTAssertEqual(immediate.first?.model, "Wrangler")

        // The provider has been asked and has not answered. The screen must
        // still show what the index found.
        let called = await provider.waitForCall(make: "JEEP")
        XCTAssertTrue(called)
        XCTAssertTrue(search.state.hasResults, "a pending confirmation must not blank the results")
    }

    func testAProviderOutageDoesNotTakeAwayAGoodAnswer() async throws {
        let provider = StubIdentificationProvider(error: .notConnected)
        let search = await makeSearch(provider)

        search.search("wrangler", debounce: .zero)
        guard case .results = search.state else {
            return XCTFail("the index should answer immediately")
        }

        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(
            search.state.hasResults,
            "an outage is a reason to stop confirming, not to remove a correct answer"
        )
    }

    // MARK: - Races

    func testASlowAnswerForAnEarlierQueryIsDiscarded() async throws {
        let provider = ScriptedModelProvider()
        let search = await makeSearch(provider)

        search.search("2010 Jeep", debounce: .zero)
        let jeepCalled = await provider.waitForCall(make: "JEEP")
        XCTAssertTrue(jeepCalled)

        search.search("2010 Ford", debounce: .zero)
        let fordCalled = await provider.waitForCall(make: "FORD")
        XCTAssertTrue(fordCalled)

        await provider.answer(make: "FORD", with: ["F-150", "Explorer"])
        try await waitUntil { if case .results = search.state { return true }; return false }

        await provider.answer(make: "JEEP", with: ["Wrangler"])
        try await Task.sleep(nanoseconds: 300_000_000)

        guard case .results(let still) = search.state else {
            return XCTFail("expected the newer results to stand, got \(search.state)")
        }
        XCTAssertEqual(
            still.map(\.model), ["Explorer", "F-150"],
            "a slow answer for an earlier query must not replace a newer selection"
        )
    }

    func testClearingTheFieldInvalidatesWhatIsInFlight() async throws {
        // The Build 2 defect: the sequence number advanced only once a query
        // was complete enough to act on, so clearing the field left the older
        // request eligible to land on an empty screen.
        let provider = ScriptedModelProvider()
        let search = await makeSearch(provider)

        search.search("2010 Jeep", debounce: .zero)
        let called = await provider.waitForCall(make: "JEEP")
        XCTAssertTrue(called)

        search.search("", debounce: .zero)
        await provider.answer(make: "JEEP", with: ["Wrangler"])
        try await Task.sleep(nanoseconds: 300_000_000)

        if case .results = search.state {
            XCTFail("a cleared field must not be filled in by an older answer")
        }
    }

    func testBackspacingIntoAnIncompleteQueryInvalidatesToo() async throws {
        let provider = ScriptedModelProvider()
        let search = await makeSearch(provider)

        search.search("2010 Jeep", debounce: .zero)
        let called = await provider.waitForCall(make: "JEEP")
        XCTAssertTrue(called)

        // Down to something that only suggests makes and makes no request.
        search.search("j", debounce: .zero)
        await provider.answer(make: "JEEP", with: ["Wrangler"])
        try await Task.sleep(nanoseconds: 300_000_000)

        if case .results = search.state {
            XCTFail("an older answer must not land on an incomplete query")
        }
    }

    func testLeavingTheScreenInvalidatesWhatIsInFlight() async throws {
        let provider = ScriptedModelProvider()
        let search = await makeSearch(provider)

        search.search("2010 Jeep", debounce: .zero)
        let called = await provider.waitForCall(make: "JEEP")
        XCTAssertTrue(called)

        search.cancel()
        await provider.answer(make: "JEEP", with: ["Wrangler"])
        try await Task.sleep(nanoseconds: 300_000_000)

        if case .results = search.state {
            XCTFail("a dismissed screen must not be updated by a late answer")
        }
    }

    // MARK: - Caching and failure

    func testTheSameMakeIsAskedForOnce() async throws {
        let provider = ScriptedModelProvider()
        let search = await makeSearch(provider)

        search.search("2010 Jeep Wr", debounce: .zero)
        _ = await provider.waitForCall(make: "JEEP")
        await provider.answer(make: "JEEP", with: ["Wrangler", "Grand Cherokee"])
        try await waitUntil { if case .results = search.state { return true }; return false }

        search.search("2010 Jeep Wrangler", debounce: .zero)
        try await waitUntil {
            if case .results(let r) = search.state { return r.count == 1 }
            return false
        }
        let count = await provider.callCount()
        XCTAssertEqual(count, 1, "a make and year should be asked for once per session")
    }

    func testAProviderOutageIsReportedAsOneRatherThanAsNoMatch() async throws {
        // Distinguishing "no such model" from "the service is down" is the
        // difference between a useful message and a wrong one.
        let provider = StubIdentificationProvider(error: .notConnected)
        let search = await makeSearch(provider)

        search.search("2010 Jeep Wrangler", debounce: .zero)
        try await waitUntil { if case .offline = search.state { return true }; return false }

        guard case .offline = search.state else {
            return XCTFail("expected an offline state, got \(search.state)")
        }
    }

    func testAnEmptyProviderAnswerIsReportedAsNoMatch() async throws {
        let provider = ScriptedModelProvider()
        let search = await makeSearch(provider)

        search.search("2010 Jeep Wrangler", debounce: .zero)
        _ = await provider.waitForCall(make: "JEEP")
        await provider.answer(make: "JEEP", with: [])
        try await waitUntil { if case .empty = search.state { return true }; return false }

        guard case .empty = search.state else {
            return XCTFail("expected an empty state, got \(search.state)")
        }
    }

    /// Polls a condition on the main actor, so a test never sleeps longer than
    /// it has to or races an update it was about to see.
    private func waitUntil(
        timeout: TimeInterval = 5,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(condition(), "condition never became true")
    }
}
