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
        XCTAssertTrue(waitFor(app.navigationBars["Home"], 25), "Home did not appear")
        capture("\(prefix)-01-home")

        app.tabBars.buttons["Jobs"].tap()
        XCTAssertTrue(waitFor(app.navigationBars["Jobs"]))
        capture("\(prefix)-02-jobs")

        let task = app.element(withIdentifier: "jobs.task.engine-oil-and-filter")
        if waitFor(task, 8) {
            task.tap()
            capture("\(prefix)-03-job-detail")
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }

        app.tabBars.buttons["Garage"].tap()
        XCTAssertTrue(waitFor(app.navigationBars["Garage"]))
        capture("\(prefix)-04-garage")

        let vehicle = app.element(withIdentifier: "garage.vehicle")
        if waitFor(vehicle, 8) {
            vehicle.tap()
            capture("\(prefix)-05-vehicle")

            // The picture is the part most likely to be wrong and least
            // likely to be caught by a test, so it gets its own capture.
            //
            // Both links are below the fold on this screen, and a List does
            // not realise a row until it is near the viewport — waiting on
            // one without moving the list is how a capture comes back
            // missing rather than wrong, which is the harder kind to notice.
            let artwork = app.element(withIdentifier: "vehicle.artwork")
            if app.scrollTo(artwork, hittable: true) {
                artwork.tap()
                if waitFor(app.navigationBars["Picture"], 8) {
                    capture("\(prefix)-06-artwork")
                }
                app.navigationBars.buttons.element(boundBy: 0).tap()
            } else {
                XCTFail("the artwork link was not reachable — saw \(app.visibleRowLabels())")
            }

            let specifications = app.element(withIdentifier: "vehicle.specifications")
            if app.scrollTo(specifications, hittable: true) {
                specifications.tap()
                if waitFor(app.navigationBars["Specifications"], 8) {
                    capture("\(prefix)-07-specifications")
                }
                app.navigationBars.buttons.element(boundBy: 0).tap()
            } else {
                XCTFail("the specifications link was not reachable — saw \(app.visibleRowLabels())")
            }
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }

        app.tabBars.buttons["Calendar"].tap()
        XCTAssertTrue(waitFor(app.navigationBars["Calendar"]))
        capture("\(prefix)-08-calendar")

        // Settings, and the appearance screen that decides how all of this
        // looks — worth a capture in both appearances for exactly that reason.
        let settings = app.buttons["calendar.settings"]
        if waitFor(settings, 8) {
            settings.tap()
            if waitFor(app.navigationBars["Settings"], 8) {
                capture("\(prefix)-09-settings")
                let pro = app.element(withIdentifier: "settings.pro")
                if app.scrollTo(pro, hittable: true) {
                    pro.tap()
                    if waitFor(app.navigationBars["Odomind Pro"], 8) {
                        capture("\(prefix)-10-pro")
                    }
                    app.navigationBars.buttons.element(boundBy: 0).tap()
                }
            }
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
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

        XCTAssertTrue(waitFor(app.navigationBars["Home"], 25), "Home did not appear at a large text size")
        capture("large-text-01-home")

        app.tabBars.buttons["Jobs"].tap()
        XCTAssertTrue(waitFor(app.navigationBars["Jobs"]))
        capture("large-text-02-jobs")
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

        // The search step, which is the first thing anybody adding a car
        // actually sees now.
        fresh.buttons["onboarding.addVehicle"].tap()
        if fresh.textFields["addVehicle.search"].waitForExistence(timeout: 10) {
            let step = XCTAttachment(screenshot: fresh.screenshot())
            step.name = "light-00b-find-vehicle"
            step.lifetime = .keepAlways
            add(step)
        }
    }
}
