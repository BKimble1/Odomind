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

    /// The screens Build 3 added or changed, which the walk above does not
    /// reach: the permission step, a search with no year typed, the
    /// configuration step, parts opened from a job, and the shopping area.
    ///
    /// Separate from `walk` on purpose. These need a fresh install and a
    /// different sequence, and folding them in would make one long test whose
    /// failure tells you less.
    func testCaptureBuildThreeScreens() {
        let fresh = XCUIApplication()
        fresh.launchArguments = [
            "-odomind-ui-testing",
            "-odomind-exercise-permissions",
            // The one capture allowed to reach the real providers. Every
            // other UI test stays stubbed so the pull-request gate does not
            // go red when somebody else's service is slow — but the brief is
            // explicit that "fixture-only screenshots do not prove a live
            // provider works", and a recorded answer photographs identically
            // to a real one. If a provider is down when this runs, the
            // screenshot shows Odomind's honest fallback and is reported as
            // that rather than retaken until it looks better.
            "-odomind-live-providers",
            "-odomind-appearance", "light",
        ]
        XCUIDevice.shared.appearance = .light
        fresh.launch()

        func shot(_ name: String) {
            let attachment = XCTAttachment(screenshot: fresh.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        XCTAssertTrue(fresh.buttons["onboarding.addVehicle"].waitForExistence(timeout: 25))
        fresh.buttons["onboarding.addVehicle"].tap()

        // 1. First use: the two questions, before either prompt fires.
        XCTAssertTrue(
            fresh.buttons["permissions.reminders"].waitForExistence(timeout: 10),
            "the permission step is missing"
        )
        shot("build3-01-permissions")

        fresh.buttons["permissions.reminders.skip"].tap()
        fresh.buttons["permissions.location.skip"].tap()
        fresh.buttons["permissions.continue"].tap()

        // 2. A search with no year typed at all — the thing Build 2 refused.
        let search = fresh.textFields["addVehicle.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 15), "the search field is missing")
        search.tap()
        search.typeText("wrangler")
        // The index answers without a network, so this is a screenshot of
        // real results rather than of a spinner.
        let firstResult = fresh.descendants(matching: .any)
            .matching(identifier: "addVehicle.result").firstMatch
        XCTAssertTrue(
            firstResult.waitForExistence(timeout: 15),
            "a bare model name should find something without a year typed"
        )
        shot("build3-02-yearless-search")

        // 3. The year, asked after the vehicle rather than before it.
        //
        //    This is the half of the yearless search that was missing. A
        //    model picked with no year typed reached the confirm step with no
        //    year at all, and the configuration lookup — which is keyed on
        //    year, make and model — could only report that it needed one, on
        //    a screen that offered nowhere to give it. The first capture of
        //    this screen is what showed it: every identifier was present and
        //    every element existed, so nothing failed.
        // Before the tap, not after. On an iPhone SE the keyboard covers the
        // matches themselves, so the tap landed on a key, nothing was
        // selected, and the next step reported the year strip missing — with
        // "saw []", which was the tell: not one row was visible.
        fresh.dismissKeyboard()
        XCTAssertTrue(
            fresh.scrollTo(firstResult, hittable: true),
            "the first match should be tappable — saw \(fresh.visibleRowLabels())"
        )
        firstResult.tap()

        let year = fresh.element(withIdentifier: "addVehicle.modelYear.2023")
        XCTAssertTrue(
            fresh.scrollTo(year, hittable: true),
            "the year strip should be reachable after choosing a model — saw \(fresh.visibleRowLabels())"
        )
        year.tap()

        // find -> confirm. The flow has three steps, not two; walking it as
        // though tapping a result finished the job is how this capture would
        // have come back as the search screen twice.
        let next = fresh.buttons["addVehicle.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10), "the Next button is missing")
        next.tap()
        // Same rule for everything below: scroll, do not wait.

        XCTAssertTrue(
            fresh.textFields["addVehicle.odometer"].waitForExistence(timeout: 10),
            "choosing a result should reach the confirmation step"
        )

        // The mileage first, before anything below pushes it off the top.
        //
        // `scrollTo` only ever scrolls *down*, because a List's unrealised
        // rows are below the viewport — a row above it is a different problem
        // and not one this helper can solve. Typing the reading last worked
        // while the confirmation step was short enough to fit on one screen.
        // The moment a live provider put three configurations on it, scrolling
        // to those put the odometer above the fold, and "the odometer field is
        // missing" cost this capture four screens.
        let odometer = fresh.textFields["addVehicle.odometer"]
        XCTAssertTrue(fresh.scrollTo(odometer, hittable: true), "the odometer field is missing")
        odometer.tap()
        odometer.typeText("58000")
        fresh.dismissKeyboard()

        // Wait for the lookup to settle instead of photographing a spinner.
        // Either outcome is a real screenshot: the configurations
        // fueleconomy.gov publishes for a 2023 Wrangler, or Odomind saying it
        // has no published list and asking the two questions instead.
        let option = fresh.firstElement(withIdentifierPrefix: "confirm.option.")
        let powertrain = fresh.element(withIdentifier: "confirm.powertrain")
        let settled = fresh.waitUntil(timeout: 30) { option.exists || powertrain.exists }
        XCTAssertTrue(
            settled,
            "the configuration step settled on neither published options nor the fallback questions"
        )
        fresh.scrollTo(option.exists ? option : powertrain)
        shot("build3-03-configuration")

        // Whichever of the two appeared, the powertrain has to end up
        // answered: it is what makes the engine oil job exist, and that job
        // is how the parts capture below is reached.
        if option.exists, fresh.scrollTo(option, hittable: true) {
            option.tap()
        }
        // Scrolled to, not waited for. On an iPhone SE this question sits
        // below the fold, and a row a Form has not realised is not in the
        // accessibility tree — so waiting skipped it, the powertrain went
        // unanswered, and the app then correctly left engine oil out of the
        // plan. The failure read as "the oil job is missing" and the app was
        // right. This is the same mistake as the one in the journey helper,
        // made again in the test written alongside the fix for it.
        //
        // Conditional now, because a published configuration answers it and
        // the question then correctly disappears.
        if fresh.scrollTo(powertrain, hittable: true, maxSwipes: 6) {
            powertrain.tap()
            let gasoline = fresh.buttons["Gasoline"]
            XCTAssertTrue(gasoline.waitForExistence(timeout: 5), "Gasoline was not offered")
            gasoline.tap()
        }

        next.tap()          // confirm -> plan
        XCTAssertTrue(
            fresh.buttons["addVehicle.finish"].waitForExistence(timeout: 15),
            "the Add vehicle button is missing"
        )
        fresh.buttons["addVehicle.finish"].tap()

        guard fresh.navigationBars["Home"].waitForExistence(timeout: 20) else {
            XCTFail("Home did not appear after adding a vehicle")
            return
        }
        shot("build3-04-home")

        // 4. The garage, with whatever Wikimedia Commons actually has for
        //    this vehicle. Waited for, never asserted: Commons is a volunteer
        //    archive and a miss is a real outcome the owner will see. Failing
        //    the capture on it would only teach me to stop asking.
        fresh.tabBars.buttons["Garage"].tap()
        XCTAssertTrue(fresh.navigationBars["Garage"].waitForExistence(timeout: 15), "Garage did not open")
        fresh.waitUntil(timeout: 25) { fresh.element(withIdentifier: "vehicle.photo").exists }
        shot("build3-07-garage")

        // 5. Parts, reached from a job rather than typed again.
        //
        // Queried by identifier rather than by element type throughout. A
        // NavigationLink in a List is reported as a button on one OS version
        // and as a cell on another, and `app.buttons[...]` quietly not
        // existing would make this capture go missing rather than fail —
        // which is the harder kind of wrong to notice in a screenshot run.
        fresh.tabBars.buttons["Jobs"].tap()
        let job = fresh.element(withIdentifier: "jobs.task.engine-oil-and-filter")
        XCTAssertTrue(
            fresh.scrollTo(job, hittable: true),
            "the oil job is missing from Jobs — saw \(fresh.visibleRowLabels())"
        )
        job.tap()

        let parts = fresh.element(withIdentifier: "task.findParts")
        XCTAssertTrue(
            fresh.scrollTo(parts, hittable: true),
            "Find parts should be reachable on a job — saw \(fresh.visibleRowLabels())"
        )
        parts.tap()
        XCTAssertTrue(fresh.navigationBars["Parts"].waitForExistence(timeout: 10), "Parts did not open")
        shot("build3-05-parts-from-a-job")

        // 6. The shopping area control, and what it offers.
        let area = fresh.element(withIdentifier: "shopping.location")
        XCTAssertTrue(area.waitForExistence(timeout: 8), "the shopping area control is missing from Parts")
        area.tap()
        XCTAssertTrue(
            fresh.navigationBars["Shopping area"].waitForExistence(timeout: 8),
            "the area picker did not open"
        )
        shot("build3-06-location")
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
