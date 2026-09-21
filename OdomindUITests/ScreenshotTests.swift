import XCTest

/// Captures the app's main screens so there is visual evidence of what was
/// actually built, rather than a description of it.
///
/// Runs against the sample vehicle so the screens are populated, and attaches
/// each capture to the result bundle. CI extracts them and uploads them as an
/// artifact.
final class OdomindScreenshotTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-odomind-ui-testing", "-odomind-seed-sample"]
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    private func capture(_ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func waitFor(_ element: XCUIElement, _ seconds: TimeInterval = 15) -> Bool {
        element.waitForExistence(timeout: seconds)
    }

    private func walk(_ prefix: String) {
        XCTAssertTrue(waitFor(app.navigationBars["Today"], 25), "Today did not appear")
        capture("\(prefix)-01-today")

        app.tabBars.buttons["Jobs"].tap()
        XCTAssertTrue(waitFor(app.navigationBars["Maintenance"]))
        capture("\(prefix)-02-maintenance")

        let task = app.element(withIdentifier: "jobs.task.engine-oil-and-filter")
        if waitFor(task, 8) {
            task.tap()
            capture("\(prefix)-03-task-detail")
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }

        app.tabBars.buttons["Garage"].tap()
        XCTAssertTrue(waitFor(app.navigationBars["Garage"]))
        capture("\(prefix)-04-garage")

        let vehicle = app.element(withIdentifier: "garage.vehicle")
        if waitFor(vehicle, 8) {
            vehicle.tap()
            capture("\(prefix)-05-vehicle")
            let specifications = app.buttons["vehicle.specifications"]
            if waitFor(specifications, 8) {
                specifications.tap()
                if waitFor(app.navigationBars["Specifications"], 8) {
                    capture("\(prefix)-06-specifications")
                }
                app.navigationBars.buttons.element(boundBy: 0).tap()
            }
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }

        app.tabBars.buttons["Calendar"].tap()
        XCTAssertTrue(waitFor(app.navigationBars["History"]))
        capture("\(prefix)-07-history")
    }

    func testCaptureLightAppearance() {
        XCUIDevice.shared.appearance = .light
        app.launchArguments += ["-odomind-appearance", "light"]
        app.launch()
        walk("light")
    }

    func testCaptureDarkAppearance() {
        // Both, deliberately. Setting the device appearance alone produced a
        // "dark" capture that was identical to the light one, so the app is
        // asked directly as well.
        XCUIDevice.shared.appearance = .dark
        app.launchArguments += ["-odomind-appearance", "dark"]
        app.launch()
        walk("dark")
    }

    func testCaptureLargeTextSize() {
        XCUIDevice.shared.appearance = .light
        app.launchArguments += [
            "-odomind-appearance", "light",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"
        ]
        app.launch()

        XCTAssertTrue(waitFor(app.navigationBars["Today"], 25), "Today did not appear at a large text size")
        capture("large-text-01-today")

        app.tabBars.buttons["Jobs"].tap()
        XCTAssertTrue(waitFor(app.navigationBars["Maintenance"]))
        capture("large-text-02-maintenance")
    }

    func testCaptureOnboarding() {
        let fresh = XCUIApplication()
        fresh.launchArguments = ["-odomind-ui-testing", "-odomind-appearance", "light"]
        XCUIDevice.shared.appearance = .light
        fresh.launch()

        XCTAssertTrue(fresh.buttons["onboarding.addVehicle"].waitForExistence(timeout: 25))
        let screenshot = XCTAttachment(screenshot: fresh.screenshot())
        screenshot.name = "light-00-onboarding"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        fresh.buttons["onboarding.addVehicle"].tap()
        if fresh.textFields["addVehicle.year"].waitForExistence(timeout: 10) {
            let step = XCTAttachment(screenshot: fresh.screenshot())
            step.name = "light-00b-add-vehicle"
            step.lifetime = .keepAlways
            add(step)
        }
    }
}
