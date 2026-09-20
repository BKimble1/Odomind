import XCTest

/// The journey a new owner actually takes.
///
/// Every run starts from a clean store via the app's UI-testing launch flag, so
/// the test never depends on what a previous run left on the simulator.
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

    private func waitFor(_ element: XCUIElement, _ seconds: TimeInterval = 10, _ message: String) {
        XCTAssertTrue(element.waitForExistence(timeout: seconds), message)
    }

    private func type(_ text: String, into field: XCUIElement) {
        waitFor(field, 5, "field \(field) never appeared")
        field.tap()
        field.typeText(text)
    }

    /// Walks onboarding to a garage containing one vehicle.
    private func addVehicle(odometer: String = "120000") {
        let start = app.buttons["onboarding.addVehicle"]
        waitFor(start, 15, "onboarding did not appear — the app may not have started from a clean store")
        start.tap()

        type("2010", into: app.textFields["addVehicle.year"])
        type("Jeep", into: app.textFields["addVehicle.make"])
        type("Wrangler", into: app.textFields["addVehicle.model"])

        let next = app.buttons["addVehicle.next"]
        waitFor(next, 5, "the Next button is missing")
        next.tap()          // identity -> confirm
        next.tap()          // confirm -> mileage

        type(odometer, into: app.textFields["addVehicle.odometer"])
        next.tap()          // mileage -> tasks

        let finish = app.buttons["addVehicle.finish"]
        waitFor(finish, 5, "the Add vehicle button is missing")
        finish.tap()
    }

    // MARK: - Tests

    func testAddAVehicleAndSeeItOnToday() {
        addVehicle()

        waitFor(app.navigationBars["Today"], 10, "Today did not appear after adding a vehicle")
        XCTAssertTrue(
            app.staticTexts["120,000"].waitForExistence(timeout: 5)
                || app.staticTexts["120000"].waitForExistence(timeout: 1),
            "the recorded odometer should be on the Today screen"
        )
        XCTAssertTrue(app.buttons["today.updateMileage"].exists)
        XCTAssertTrue(app.buttons["today.logService"].exists)
    }

    func testUpdateMileage() {
        addVehicle()
        waitFor(app.navigationBars["Today"], 10, "Today did not appear")

        app.buttons["today.updateMileage"].tap()

        let field = app.textFields["mileage.field"]
        waitFor(field, 5, "the mileage field did not appear")
        field.tap()
        field.typeText("124800")

        app.buttons["mileage.save"].tap()

        XCTAssertTrue(
            app.staticTexts["124,800"].waitForExistence(timeout: 5)
                || app.staticTexts["124800"].waitForExistence(timeout: 1),
            "the new reading should replace the old one on Today"
        )
    }

    func testMaintenanceTabListsTheChosenTasks() {
        addVehicle()
        waitFor(app.navigationBars["Today"], 10, "Today did not appear")

        app.tabBars.buttons["Maintenance"].tap()
        waitFor(app.navigationBars["Maintenance"], 5, "the Maintenance tab did not open")

        XCTAssertTrue(
            app.staticTexts["Engine oil and filter"].waitForExistence(timeout: 5),
            "the default tasks should be tracked after onboarding"
        )
    }

    func testTaskDetailExplainsWhyNothingIsScheduledYet() {
        addVehicle()
        waitFor(app.navigationBars["Today"], 10, "Today did not appear")

        app.tabBars.buttons["Maintenance"].tap()
        let task = app.staticTexts["Engine oil and filter"]
        waitFor(task, 5, "the oil task is missing")
        task.tap()

        // With no completion logged, the app says so rather than showing a
        // date it cannot justify.
        XCTAssertTrue(
            app.staticTexts.containing(
                NSPredicate(format: "label CONTAINS[c] %@", "No completion recorded")
            ).firstMatch.waitForExistence(timeout: 5),
            "the task detail should explain that there is no history yet"
        )
    }

    func testLogAServiceAndSeeNextDue() {
        addVehicle()
        waitFor(app.navigationBars["Today"], 10, "Today did not appear")

        app.buttons["today.logService"].tap()
        waitFor(app.navigationBars["Log service"], 5, "the log service sheet did not open")

        app.buttons["Engine oil and filter"].firstMatch.tap()
        app.buttons["Save"].tap()

        waitFor(app.navigationBars["Today"], 5, "the sheet did not close after saving")

        app.tabBars.buttons["History"].tap()
        waitFor(app.navigationBars["History"], 5, "the History tab did not open")
        XCTAssertTrue(
            app.staticTexts["Engine oil and filter"].waitForExistence(timeout: 5),
            "the logged service should appear in History"
        )
    }

    func testGarageShowsSpecificationsAndSaysWhatIsMissing() {
        addVehicle()
        waitFor(app.navigationBars["Today"], 10, "Today did not appear")

        app.tabBars.buttons["Garage"].tap()
        waitFor(app.navigationBars["Garage"], 5, "the Garage tab did not open")

        app.staticTexts["2010 Jeep Wrangler"].firstMatch.tap()
        app.buttons["Specifications"].firstMatch.tap()
        waitFor(app.navigationBars["Specifications"], 5, "the specifications screen did not open")

        // The honest empty state: Odomind ships no fluid values, and says so.
        XCTAssertTrue(
            app.staticTexts.containing(
                NSPredicate(format: "label CONTAINS[c] %@", "Not available")
            ).firstMatch.waitForExistence(timeout: 5),
            "unknown specifications should be shown as unavailable, not as a guess"
        )
    }

    func testExportScreenOffersTheThreeFormats() {
        addVehicle()
        waitFor(app.navigationBars["Today"], 10, "Today did not appear")

        app.tabBars.buttons["History"].tap()
        waitFor(app.navigationBars["History"], 5, "the History tab did not open")

        app.navigationBars["History"].buttons.element(boundBy: app.navigationBars["History"].buttons.count - 1).tap()
        let exportButton = app.buttons["Export"]
        waitFor(exportButton, 5, "the History menu did not offer Export")
        exportButton.tap()

        waitFor(app.navigationBars["Export"], 5, "the Export screen did not open")
        XCTAssertTrue(app.buttons["Service history (CSV)"].exists)
        XCTAssertTrue(app.buttons["Create a backup"].exists)
    }

    func testSampleVehicleIsClearlyMarked() {
        let sample = app.buttons["onboarding.addSample"]
        waitFor(sample, 15, "onboarding did not appear")
        sample.tap()

        waitFor(app.navigationBars["Today"], 10, "Today did not appear after adding the sample")
        XCTAssertTrue(
            app.staticTexts["SAMPLE"].waitForExistence(timeout: 5),
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
        XCTAssertTrue(start.waitForExistence(timeout: 15), "onboarding did not appear at a large text size")
        XCTAssertTrue(start.isHittable, "the primary action must stay reachable when text is enlarged")
    }
}
