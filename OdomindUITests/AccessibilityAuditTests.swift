import XCTest

/// Runs XCTest's accessibility audit over each screen.
///
/// This is the automated half of "walk through the app and fix what is wrong".
/// The audit flags clipped text, elements with no usable description, controls
/// with a hit region too small to tap, contrast problems and layouts that break
/// at large text sizes — the failures that are invisible in a screenshot until
/// somebody with different eyes or different settings opens the app.
final class OdomindAccessibilityAuditTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-odomind-ui-testing", "-odomind-seed-sample"]
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    private func audit(_ screen: String, in application: XCUIApplication? = nil) {
        let target = application ?? app!
        do {
            try target.performAccessibilityAudit { issue in
                // Name what was found. "Contrast failed" on its own says
                // nothing about which element failed or by how much, which is
                // not enough to fix anything. Returning false keeps the issue
                // reported as a failure; this only adds the detail.
                let element = issue.element
                let label = element?.label ?? ""
                let identifier = element?.identifier ?? ""
                let described = [identifier, label]
                    .filter { !$0.isEmpty }
                    .joined(separator: " / ")
                print(
                    "AUDITISSUE | \(screen) | \(issue.compactDescription) | "
                        + (described.isEmpty ? "(unlabelled element)" : described)
                )
                return false
            }
        } catch {
            XCTFail("Accessibility audit could not run on \(screen): \(error)")
        }
    }

    private func waitFor(_ element: XCUIElement, _ seconds: TimeInterval = 20) -> Bool {
        element.waitForExistence(timeout: seconds)
    }

    func testOnboardingIsAccessible() {
        let fresh = XCUIApplication()
        fresh.launchArguments = ["-odomind-ui-testing"]
        fresh.launch()
        XCTAssertTrue(fresh.buttons["onboarding.addVehicle"].waitForExistence(timeout: 25))
        audit("Onboarding", in: fresh)
    }

    func testMainScreensAreAccessible() {
        app.launch()
        XCTAssertTrue(waitFor(app.navigationBars["Today"], 25), "Today did not appear")
        audit("Today")

        app.tabBars.buttons["Maintenance"].tap()
        XCTAssertTrue(waitFor(app.navigationBars["Maintenance"]))
        audit("Maintenance")

        let task = app.element(withIdentifier: "maintenance.task.engine-oil-and-filter")
        if waitFor(task, 10) {
            task.tap()
            _ = waitFor(app.navigationBars.firstMatch, 10)
            audit("Task detail")
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }

        app.tabBars.buttons["Garage"].tap()
        XCTAssertTrue(waitFor(app.navigationBars["Garage"]))
        audit("Garage")

        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(waitFor(app.navigationBars["History"]))
        audit("History")
    }

    func testSpecificationsScreenIsAccessible() {
        app.launch()
        XCTAssertTrue(waitFor(app.navigationBars["Today"], 25))

        app.tabBars.buttons["Garage"].tap()
        XCTAssertTrue(waitFor(app.navigationBars["Garage"]))
        guard waitFor(app.element(withIdentifier: "garage.vehicle"), 10) else {
            return XCTFail("the vehicle row is missing")
        }
        app.element(withIdentifier: "garage.vehicle").tap()
        guard waitFor(app.buttons["vehicle.specifications"], 10) else {
            return XCTFail("the specifications link is missing")
        }
        app.buttons["vehicle.specifications"].tap()
        XCTAssertTrue(waitFor(app.navigationBars["Specifications"]))
        audit("Specifications")
    }

    func testTodayIsAccessibleAtLargeTextSizes() {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        app.launch()
        XCTAssertTrue(waitFor(app.navigationBars["Today"], 25), "Today did not appear at a large text size")
        audit("Today at accessibility XL")

        app.tabBars.buttons["Maintenance"].tap()
        XCTAssertTrue(waitFor(app.navigationBars["Maintenance"]))
        audit("Maintenance at accessibility XL")
    }
}
