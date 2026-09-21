import XCTest

/// The journey a new owner actually takes.
///
/// Every run starts from a clean store via the app's UI-testing launch flag, so
/// the test never depends on what a previous run left on the simulator.
/// Elements are found by accessibility identifier rather than by visible text,
/// because most rows combine their children into one element for VoiceOver and
/// the individual labels are not separately addressable.
final class OdomindJourneyUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-odomind-ui-testing"]
        app.launch()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    // MARK: - Helpers

    @discardableResult
    private func waitFor(_ element: XCUIElement, _ seconds: TimeInterval = 15, _ message: String) -> XCUIElement {
        XCTAssertTrue(element.waitForExistence(timeout: seconds), message)
        return element
    }

    private func type(_ text: String, into field: XCUIElement) {
        waitFor(field, 10, "field never appeared")
        field.tap()
        field.typeText(text)
    }

    /// Clears a field before typing.
    ///
    /// Odometer fields pre-fill with the last reading, so typing alone would
    /// append to it and quietly record a much larger number than intended.
    private func replaceText(_ text: String, in field: XCUIElement) {
        waitFor(field, 10, "field never appeared")
        field.tap()
        let existing = (field.value as? String) ?? ""
        if !existing.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count + 2))
        }
        field.typeText(text)
    }

    /// Walks onboarding to a garage containing one vehicle.
    ///
    /// Typed in by hand rather than searched. The search path needs the
    /// vehicle lookup service, which is not something a UI test on a runner
    /// should depend on being up — the provider is covered against recorded
    /// fixtures in `ProviderTests`, and its live availability by the separate
    /// `provider-smoke` workflow. What this exercises is the path that has to
    /// work with no connection at all.
    private func addVehicle(odometer: String = "120000", powertrain: String? = "Gasoline") {
        let start = waitFor(
            app.buttons["onboarding.addVehicle"],
            20,
            "onboarding did not appear — the app may not have started from a clean store"
        )
        start.tap()

        waitFor(app.buttons["addVehicle.manual"], 10, "the manual entry option is missing").tap()
        type("2010", into: app.textFields["addVehicle.year"])
        type("Jeep", into: app.textFields["addVehicle.make"])
        type("Wrangler", into: app.textFields["addVehicle.model"])
        waitFor(app.buttons["addVehicle.manualDone"], 10, "the manual entry sheet cannot be finished").tap()

        let next = waitFor(app.buttons["addVehicle.next"], 10, "the Next button is missing")
        next.tap()          // find -> confirm

        // Odomind will not assume a vehicle burns fuel, so engine oil and
        // everything else that depends on a combustion engine stays out of the
        // plan until this is answered. Answering it is what a real owner does
        // on this step, and it is what makes the rest of the journey exist.
        if let powertrain {
            let picker = waitFor(
                app.element(withIdentifier: "confirm.powertrain"),
                10,
                "the powertrain picker is missing from the confirmation step"
            )
            picker.tap()
            waitFor(app.buttons[powertrain], 10, "\(powertrain) was not offered").tap()
        }

        replaceText(odometer, in: app.textFields["addVehicle.odometer"])
        next.tap()          // confirm -> plan

        waitFor(app.buttons["addVehicle.finish"], 10, "the Add vehicle button is missing").tap()
        waitFor(app.navigationBars["Home"], 15, "Home did not appear after adding a vehicle")
    }

    // MARK: - Tests

    func testAddAVehicleAndSeeItOnToday() {
        addVehicle()

        let odometer = waitFor(app.element(withIdentifier: "home.odometer"), 10, "the odometer summary is missing")
        XCTAssertTrue(
            odometer.label.contains("120"),
            "the recorded odometer should be on Today, got '\(odometer.label)'"
        )
        XCTAssertTrue(app.scrollTo(app.buttons["home.logService"]), "Log service should be reachable on Home")
        XCTAssertTrue(app.buttons["home.updateMileage"].exists)
    }

    func testUpdateMileage() {
        addVehicle()
        app.scrollTo(app.buttons["home.updateMileage"], hittable: true)
        app.buttons["home.updateMileage"].tap()

        let field = waitFor(app.textFields["mileage.field"], 10, "the mileage field did not appear")
        field.tap()
        field.typeText("124800")
        app.buttons["mileage.save"].tap()

        waitFor(app.navigationBars["Home"], 10, "the sheet did not close")
        let odometer = waitFor(app.element(withIdentifier: "home.odometer"), 10, "the odometer summary is missing")
        XCTAssertTrue(
            odometer.label.contains("124"),
            "the new reading should replace the old one, got '\(odometer.label)'"
        )
    }

    func testHomeDoesNotClaimAllClearWhileHistoryIsUnknown() {
        addVehicle()

        // The Build 1 failure this replaces: a green "nothing currently due"
        // above fifteen unanswered setup rows. Nothing has been logged, so
        // Home must say the plan is ready and offer the action that would make
        // it useful — not congratulate anyone.
        let empty = waitFor(
            app.element(withIdentifier: "home.upNextEmpty"),
            10,
            "Home should say something honest when there is nothing actionable"
        )
        XCTAssertTrue(
            empty.label.lowercased().contains("plan is ready"),
            "expected the unknown-history wording, got '\(empty.label)'"
        )
        XCTAssertFalse(
            empty.label.lowercased().contains("nothing due"),
            "an all-clear must not appear while history is unknown: '\(empty.label)'"
        )
        XCTAssertTrue(
            app.scrollTo(app.buttons["home.setStartingPoint"]),
            "the honest empty state should offer a way to fix it"
        )
    }

    func testAnUnconfirmedPowertrainKeepsEngineOilOutOfThePlan() {
        // Skip the confirmation step, the way someone in a hurry would.
        addVehicle(powertrain: nil)

        app.tabBars.buttons["Jobs"].tap()
        waitFor(app.navigationBars["Jobs"], 10, "the Jobs tab did not open")

        // Tyre rotation applies to anything with wheels, so the plan is not
        // empty — this is a filter, not a failure to build a plan.
        waitFor(
            app.element(withIdentifier: "jobs.task.tire-rotation"),
            10,
            "a task that applies to every vehicle should still be tracked"
        )

        // Engine oil depends on there being an engine, and Odomind was never
        // told there is one. Scheduling it anyway would be the guess the whole
        // provenance model exists to avoid.
        XCTAssertFalse(
            app.element(withIdentifier: "jobs.task.engine-oil-and-filter").exists,
            "engine oil must not be scheduled for a vehicle whose powertrain was never confirmed"
        )
    }

    func testJobsTabListsTheChosenTasks() {
        addVehicle()

        app.tabBars.buttons["Jobs"].tap()
        waitFor(app.navigationBars["Jobs"], 10, "the Jobs tab did not open")
        waitFor(
            app.element(withIdentifier: "jobs.task.engine-oil-and-filter"),
            10,
            "the default tasks should be tracked after onboarding"
        )
    }

    func testTaskDetailExplainsWhyNothingIsScheduledYet() {
        addVehicle()

        app.tabBars.buttons["Jobs"].tap()
        waitFor(app.element(withIdentifier: "jobs.task.engine-oil-and-filter"), 10, "the oil task is missing").tap()

        XCTAssertTrue(
            app.element(labelContaining: "No completion recorded").waitForExistence(timeout: 10),
            "the task detail should explain that there is no history yet"
        )
        // The schedule and its provenance are reference rather than action,
        // so they sit below the fold and collapsed. That is the point of the
        // change — the button that records the work is above them — but they
        // still have to be reachable and still have to say where the interval
        // came from. Scrolling is part of the assertion: a `List` does not
        // realise a row until it is near the viewport, so waiting on this one
        // without moving the list would never find it.
        let disclosure = app.element(withIdentifier: "task.scheduleDisclosure")
        XCTAssertTrue(
            app.scrollTo(disclosure, hittable: true),
            "the schedule should be reachable from the job screen — saw \(app.visibleRowLabels())"
        )
        disclosure.tap()
        XCTAssertTrue(
            app.element(labelContaining: "Every 5,000 miles").waitForExistence(timeout: 5)
                || app.element(labelContaining: "whichever comes first").exists,
            "the schedule and where it came from should be one tap away"
        )
    }

    func testBrowsingAnUntrackedJobOpensThatJobRatherThanTheLibrary() {
        // The brief: "Browsing an untracked job should open that job's details
        // directly, not a generic add-task form that loses the selection."
        // Build 2 pushed the whole catalog here and threw the query away.
        addVehicle()

        let search = waitFor(app.textFields["home.search"], 10, "the Home search field is missing")
        search.tap()
        // Not one of the two tasks the setup flow adds, so it is certainly
        // untracked.
        search.typeText("brake fluid")

        let result = waitFor(
            app.element(withIdentifier: "jobSearch.brake-fluid"),
            10,
            "a brake fluid job should be found — saw \(app.visibleRowLabels())"
        )
        result.tap()

        // The job, with its own action — not "Add a task" with the query gone.
        XCTAssertFalse(
            app.navigationBars["Add a task"].exists,
            "an untracked job must not open the catalog library"
        )
        XCTAssertTrue(
            app.scrollTo(app.buttons["untracked.track"], hittable: true),
            "the untracked job should offer to track itself — saw \(app.visibleRowLabels())"
        )
    }

    func testLogAServiceAndItAppearsInHistory() {
        addVehicle()

        app.scrollTo(app.buttons["home.logService"], hittable: true)
        app.buttons["home.logService"].tap()
        waitFor(app.navigationBars["Log service"], 10, "the log service sheet did not open")

        app.buttons["logService.task.engine-oil-and-filter"].tap()
        app.buttons["logService.save"].tap()

        waitFor(app.navigationBars["Home"], 10, "the sheet did not close after saving")

        app.tabBars.buttons["Calendar"].tap()
        waitFor(app.navigationBars["Calendar"], 10, "the Calendar tab did not open")
        waitFor(app.element(withIdentifier: "calendar.entry.completed"), 10, "the logged service should appear in the calendar")
    }

    func testLoggingServiceProducesANextDuePoint() {
        addVehicle()

        app.scrollTo(app.buttons["home.logService"], hittable: true)
        app.buttons["home.logService"].tap()
        waitFor(app.navigationBars["Log service"], 10, "the log service sheet did not open")
        app.buttons["logService.task.engine-oil-and-filter"].tap()
        app.buttons["logService.save"].tap()
        waitFor(app.navigationBars["Home"], 10, "the sheet did not close")

        app.tabBars.buttons["Jobs"].tap()
        waitFor(app.element(withIdentifier: "jobs.task.engine-oil-and-filter"), 10, "the oil task is missing").tap()

        // Serviced at 120,000 with a 5,000-mile interval. "Next due" is
        // reference detail below the status block and the action, so the list
        // has to be moved before the row exists to be asserted on.
        let nextDue = app.element(labelContaining: "125,000")
        XCTAssertTrue(
            app.scrollTo(nextDue),
            "the next due odometer should be shown after logging the service — saw \(app.visibleRowLabels())"
        )
    }

    func testAddATaskFromTheCatalog() {
        addVehicle()

        app.tabBars.buttons["Jobs"].tap()
        waitFor(app.navigationBars["Jobs"], 10, "the Jobs tab did not open")

        // Onboarding starts a vehicle on every recommended task, so the one
        // task guaranteed not to be tracked yet is an advanced one — which
        // also means the test has to ask for advanced tasks to be shown.
        //
        // Power steering fluid specifically. It is advanced, it carries no
        // applicability constraint so it is offered whatever the vehicle
        // turns out to be, and it sits in `fluids` — the second of fourteen
        // categories, in the order both this screen and the catalog group by.
        // So it is near the top of each list.
        //
        // The previous target was in the eleventh category, thirty-odd tall
        // rows down, and the test spent seventy-eight seconds swiping without
        // reaching it. Scrolling, not searching: `.searchable` keeps its field
        // tucked under the navigation bar until the list is pulled down, and
        // fighting that is a presentation detail with no payoff. That advanced
        // tasks stay filtered out until asked for is already pinned by
        // PlanBuilderTests.testAdvancedTasksAreHiddenFromTheShortList, which
        // also pins that this particular task is among them.
        let taskID = "power-steering-fluid"
        let tracked = "jobs.task.\(taskID)"
        XCTAssertFalse(
            app.element(withIdentifier: tracked).exists,
            "power steering fluid should not be tracked yet"
        )

        app.element(withIdentifier: "jobs.addMenu").tap()
        waitFor(app.element(withIdentifier: "jobs.addFromCatalog"), 10, "the add menu did not open").tap()
        waitFor(app.navigationBars["Add a task"], 10, "the catalog did not open")

        // Addressed as a switch, and waited on. Tapping whatever a query
        // across every descendant returns first hits the row, not the
        // control: the switch stayed off, the catalog stayed filtered, and
        // the failure surfaced two steps later as a row that was "not there".
        XCTAssertTrue(
            app.setSwitch("addTask.showAdvanced", on: true),
            "the advanced toggle did not turn on, so the catalog is still filtered"
        )

        let add = app.element(withIdentifier: "addTask.add.\(taskID)")
        XCTAssertTrue(
            app.scrollTo(add, hittable: true),
            "power steering fluid should be offered once advanced tasks are shown; the catalog showed \(app.visibleRowLabels())"
        )
        add.tap()

        // The row stops offering Add once the task is tracked, so this says
        // the add landed rather than merely that the button was tappable.
        XCTAssertTrue(
            add.waitForNonExistence(timeout: 5),
            "the row should stop offering Add once the task is tracked"
        )

        app.navigationBars.buttons.element(boundBy: 0).tap()
        waitFor(app.navigationBars["Jobs"], 10, "did not return to Jobs")
        XCTAssertTrue(
            app.scrollTo(app.element(withIdentifier: tracked)),
            "the added task should now be tracked; Maintenance showed \(app.visibleRowLabels())"
        )
    }

    func testEditingARecordChangesWhatHistoryShows() {
        addVehicle()

        app.scrollTo(app.buttons["home.logService"], hittable: true)
        app.buttons["home.logService"].tap()
        waitFor(app.navigationBars["Log service"], 10, "the log service sheet did not open")
        app.buttons["logService.task.engine-oil-and-filter"].tap()

        app.scrollTo(app.textFields["logService.odometer"])
        replaceText("121000", in: app.textFields["logService.odometer"])
        app.buttons["logService.save"].tap()
        waitFor(app.navigationBars["Home"], 10, "the sheet did not close after saving")

        app.tabBars.buttons["Calendar"].tap()
        waitFor(app.navigationBars["Calendar"], 10, "the Calendar tab did not open")
        let record = waitFor(app.element(withIdentifier: "calendar.entry.completed"), 10, "the logged service is missing")
        XCTAssertTrue(record.label.contains("121,000"), "expected the recorded reading, got '\(record.label)'")
        record.tap()

        waitFor(app.element(withIdentifier: "record.edit"), 10, "the record cannot be edited").tap()

        app.scrollTo(app.textFields["logService.odometer"])
        replaceText("122500", in: app.textFields["logService.odometer"])
        app.buttons["logService.save"].tap()

        app.tabBars.buttons["Calendar"].tap()
        waitFor(app.navigationBars["Calendar"], 10, "the Calendar tab did not reopen")
        let corrected = waitFor(app.element(withIdentifier: "calendar.entry.completed"), 10, "the record disappeared after editing")
        XCTAssertTrue(
            corrected.label.contains("122,500"),
            "the correction should replace the old reading, not sit beside it: '\(corrected.label)'"
        )
        XCTAssertFalse(
            corrected.label.contains("121,000"),
            "the old reading should be gone after the correction: '\(corrected.label)'"
        )
    }

    func testGarageShowsSpecificationsAndSaysWhatIsMissing() {
        addVehicle()

        app.tabBars.buttons["Garage"].tap()
        waitFor(app.navigationBars["Garage"], 10, "the Garage tab did not open")
        waitFor(app.element(withIdentifier: "garage.vehicle"), 10, "the vehicle row is missing").tap()

        // Addressed by identifier rather than as a button: which element type
        // a NavigationLink row resolves to is SwiftUI's business, and pinning
        // the query to one makes "wrong type" and "not scrolled to yet" look
        // like the same failure.
        let specifications = app.element(withIdentifier: "vehicle.specifications")
        XCTAssertTrue(
            app.scrollTo(specifications, hittable: true),
            "the specifications link is missing — saw \(app.visibleRowLabels())"
        )
        specifications.tap()
        waitFor(app.navigationBars["Specifications"], 10, "the specifications screen did not open")

        // The honest empty state: Odomind ships no fluid values, and says so.
        XCTAssertTrue(
            app.element(labelContaining: "Not available").waitForExistence(timeout: 10),
            "unknown specifications should be shown as unavailable, not as a guess"
        )
    }

    func testExportScreenOffersTheThreeFormats() {
        addVehicle()

        app.tabBars.buttons["Calendar"].tap()
        waitFor(app.navigationBars["Calendar"], 10, "the Calendar tab did not open")

        waitFor(app.buttons["calendar.menu"], 10, "the Calendar menu is missing").tap()
        waitFor(app.buttons["calendar.export"], 10, "the menu did not offer Export").tap()

        waitFor(app.navigationBars["Export"], 10, "the Export screen did not open")
        XCTAssertTrue(app.buttons["export.csv"].exists)
        XCTAssertTrue(app.buttons["export.backup"].exists)
    }

    func testTheWelcomePermissionStepIsOfferedAndSkippable() {
        // Opt-in, because it puts two system dialogues between onboarding and
        // the vehicle flow and every other journey wants the vehicle flow.
        let fresh = XCUIApplication()
        fresh.launchArguments = ["-odomind-ui-testing", "-odomind-exercise-permissions"]
        fresh.launch()

        waitFor(fresh.buttons["onboarding.addVehicle"], 20, "onboarding did not appear").tap()

        // Both questions are put, and neither prompt fires on appearance —
        // each waits for its own tap.
        waitFor(fresh.buttons["permissions.reminders"], 10, "the reminders question is missing")
        waitFor(fresh.buttons["permissions.location"], 10, "the location question is missing")

        // Skipping both has to leave the app perfectly usable.
        fresh.buttons["permissions.reminders.skip"].tap()
        fresh.buttons["permissions.location.skip"].tap()
        waitFor(fresh.buttons["permissions.continue"], 10, "Continue is missing").tap()

        waitFor(fresh.buttons["addVehicle.manual"], 15, "skipping permissions should lead to the vehicle flow")
    }

    func testThePermissionStepIsNotAskedTwice() {
        let fresh = XCUIApplication()
        fresh.launchArguments = ["-odomind-ui-testing", "-odomind-exercise-permissions"]
        fresh.launch()

        waitFor(fresh.buttons["onboarding.addVehicle"], 20, "onboarding did not appear").tap()
        waitFor(fresh.buttons["permissions.continue"], 10, "the permission step is missing").tap()
        waitFor(fresh.buttons["addVehicle.manual"], 15, "the vehicle flow should follow")

        // Back out without adding anything, then start again. A refusal is an
        // answer; re-asking is how an app trains people to dismiss it.
        fresh.buttons["addVehicle.cancel"].tap()
        waitFor(fresh.buttons["onboarding.addVehicle"], 10, "onboarding should come back").tap()
        waitFor(fresh.buttons["addVehicle.manual"], 15, "the permission step must not be put a second time")
    }

    func testSampleVehicleIsClearlyMarked() {
        waitFor(app.buttons["onboarding.sample"], 20, "onboarding did not appear").tap()
        waitFor(app.navigationBars["Home"], 15, "Home did not appear after adding the sample")

        XCTAssertTrue(
            app.element(labelContaining: "SAMPLE").waitForExistence(timeout: 10),
            "sample content must be visibly marked"
        )
    }
}

/// Checks the app still lays out sensibly at large text sizes.
final class OdomindAccessibilityUITests: XCTestCase {

    func testOnboardingRemainsUsableAtLargeTextSizes() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-odomind-ui-testing",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityL"
        ]
        app.launch()

        let start = app.buttons["onboarding.addVehicle"]
        XCTAssertTrue(start.waitForExistence(timeout: 20), "onboarding did not appear at a large text size")

        // Onboarding scrolls, because at these text sizes it has more content
        // than screen. "Reachable" therefore means scrollable-to and then
        // tappable — not that it happens to start on screen.
        XCTAssertTrue(
            app.scrollTo(start, hittable: true),
            "the primary action must be reachable and tappable when text is enlarged"
        )
    }
}
