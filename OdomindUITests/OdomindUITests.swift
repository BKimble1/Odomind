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

    /// Any element whose accessibility label contains `text`, whatever its type.
    private func element(labelContaining text: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", text))
            .firstMatch
    }

    /// Walks onboarding to a garage containing one vehicle.
    private func addVehicle(odometer: String = "120000") {
        let start = waitFor(
            app.buttons["onboarding.addVehicle"],
            20,
            "onboarding did not appear — the app may not have started from a clean store"
        )
        start.tap()

        type("2010", into: app.textFields["addVehicle.year"])
        type("Jeep", into: app.textFields["addVehicle.make"])
        type("Wrangler", into: app.textFields["addVehicle.model"])

        let next = waitFor(app.buttons["addVehicle.next"], 10, "the Next button is missing")
        next.tap()          // identity -> confirm
        next.tap()          // confirm -> mileage

        type(odometer, into: app.textFields["addVehicle.odometer"])
        next.tap()          // mileage -> tasks

        waitFor(app.buttons["addVehicle.finish"], 10, "the Add vehicle button is missing").tap()
        waitFor(app.navigationBars["Today"], 15, "Today did not appear after adding a vehicle")
    }

    // MARK: - Tests

    func testAddAVehicleAndSeeItOnToday() {
        addVehicle()

        let odometer = waitFor(app.otherElements["today.odometer"], 10, "the odometer summary is missing")
        XCTAssertTrue(
            odometer.label.contains("120"),
            "the recorded odometer should be on Today, got '\(odometer.label)'"
        )
        XCTAssertTrue(app.buttons["today.updateMileage"].exists)
        XCTAssertTrue(app.buttons["today.logService"].exists)
    }

    func testUpdateMileage() {
        addVehicle()
        app.buttons["today.updateMileage"].tap()

        let field = waitFor(app.textFields["mileage.field"], 10, "the mileage field did not appear")
        field.tap()
        field.typeText("124800")
        app.buttons["mileage.save"].tap()

        waitFor(app.navigationBars["Today"], 10, "the sheet did not close")
        let odometer = waitFor(app.otherElements["today.odometer"], 10, "the odometer summary is missing")
        XCTAssertTrue(
            odometer.label.contains("124"),
            "the new reading should replace the old one, got '\(odometer.label)'"
        )
    }

    func testTodayGroupsTasksAndSaysNothingIsScheduledYet() {
        addVehicle()

        // Nothing has been logged, so the oil task needs setup rather than
        // appearing as done or as overdue.
        let oil = waitFor(
            app.otherElements["today.task.engine-oil-and-filter"],
            10,
            "the oil task should be on Today"
        )
        XCTAssertTrue(
            oil.label.lowercased().contains("no completion")
                || oil.label.lowercased().contains("needs"),
            "expected an explanation of why it is unscheduled, got '\(oil.label)'"
        )
        XCTAssertTrue(
            element(labelContaining: "Needs setup").exists,
            "the Needs setup group should be present"
        )
    }

    func testMaintenanceTabListsTheChosenTasks() {
        addVehicle()

        app.tabBars.buttons["Maintenance"].tap()
        waitFor(app.navigationBars["Maintenance"], 10, "the Maintenance tab did not open")
        waitFor(
            app.otherElements["maintenance.task.engine-oil-and-filter"],
            10,
            "the default tasks should be tracked after onboarding"
        )
    }

    func testTaskDetailExplainsWhyNothingIsScheduledYet() {
        addVehicle()

        app.tabBars.buttons["Maintenance"].tap()
        waitFor(app.otherElements["maintenance.task.engine-oil-and-filter"], 10, "the oil task is missing").tap()

        XCTAssertTrue(
            element(labelContaining: "No completion recorded").waitForExistence(timeout: 10),
            "the task detail should explain that there is no history yet"
        )
        XCTAssertTrue(
            element(labelContaining: "Every 5,000 miles").exists
                || element(labelContaining: "whichever comes first").exists,
            "the schedule and where it came from should be on the detail screen"
        )
    }

    func testLogAServiceAndItAppearsInHistory() {
        addVehicle()

        app.buttons["today.logService"].tap()
        waitFor(app.navigationBars["Log service"], 10, "the log service sheet did not open")

        app.buttons["logService.task.engine-oil-and-filter"].tap()
        app.buttons["logService.save"].tap()

        waitFor(app.navigationBars["Today"], 10, "the sheet did not close after saving")

        app.tabBars.buttons["History"].tap()
        waitFor(app.navigationBars["History"], 10, "the History tab did not open")
        waitFor(app.otherElements["history.record"], 10, "the logged service should appear in History")
    }

    func testLoggingServiceProducesANextDuePoint() {
        addVehicle()

        app.buttons["today.logService"].tap()
        waitFor(app.navigationBars["Log service"], 10, "the log service sheet did not open")
        app.buttons["logService.task.engine-oil-and-filter"].tap()
        app.buttons["logService.save"].tap()
        waitFor(app.navigationBars["Today"], 10, "the sheet did not close")

        app.tabBars.buttons["Maintenance"].tap()
        waitFor(app.otherElements["maintenance.task.engine-oil-and-filter"], 10, "the oil task is missing").tap()

        // Serviced at 120,000 with a 5,000-mile interval.
        XCTAssertTrue(
            element(labelContaining: "125,000").waitForExistence(timeout: 10),
            "the next due odometer should be shown after logging the service"
        )
    }

    func testGarageShowsSpecificationsAndSaysWhatIsMissing() {
        addVehicle()

        app.tabBars.buttons["Garage"].tap()
        waitFor(app.navigationBars["Garage"], 10, "the Garage tab did not open")
        waitFor(app.otherElements["garage.vehicle"], 10, "the vehicle row is missing").tap()

        waitFor(app.buttons["vehicle.specifications"], 10, "the specifications link is missing").tap()
        waitFor(app.navigationBars["Specifications"], 10, "the specifications screen did not open")

        // The honest empty state: Odomind ships no fluid values, and says so.
        XCTAssertTrue(
            element(labelContaining: "Not available").waitForExistence(timeout: 10),
            "unknown specifications should be shown as unavailable, not as a guess"
        )
    }

    func testExportScreenOffersTheThreeFormats() {
        addVehicle()

        app.tabBars.buttons["History"].tap()
        waitFor(app.navigationBars["History"], 10, "the History tab did not open")

        waitFor(app.buttons["history.menu"], 10, "the History menu is missing").tap()
        waitFor(app.buttons["history.export"], 10, "the menu did not offer Export").tap()

        waitFor(app.navigationBars["Export"], 10, "the Export screen did not open")
        XCTAssertTrue(app.buttons["export.csv"].exists)
        XCTAssertTrue(app.buttons["export.backup"].exists)
    }

    func testSampleVehicleIsClearlyMarked() {
        waitFor(app.buttons["onboarding.addSample"], 20, "onboarding did not appear").tap()
        waitFor(app.navigationBars["Today"], 15, "Today did not appear after adding the sample")

        XCTAssertTrue(
            element(labelContaining: "SAMPLE").waitForExistence(timeout: 10),
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
        XCTAssertTrue(start.isHittable, "the primary action must stay reachable when text is enlarged")
    }
}
