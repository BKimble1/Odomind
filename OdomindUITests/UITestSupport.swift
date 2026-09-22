import XCTest

extension XCUIApplication {

    /// Answers the first-run tracking question, if it is on screen.
    ///
    /// Build 4 puts it on launch rather than behind the welcome screen's
    /// button, because it decides what a new owner's plan starts as and
    /// asking after the vehicle flow means asking somebody who has just
    /// finished. That means every test that starts from a fresh install meets
    /// it first, and has to answer it before the welcome screen underneath is
    /// reachable — `onboarding.addVehicle` exists in the tree while the sheet
    /// covers it, so waiting on it succeeds and the tap lands on the sheet.
    ///
    /// Skipping is the answer used here: it is the fastest path and it leaves
    /// the starter plan exactly as every existing test expects it.
    @discardableResult
    func skipTheTrackingQuestion(timeout: TimeInterval = 10) -> Bool {
        let button = buttons["interests.continue"]
        guard button.waitForExistence(timeout: timeout) else { return false }
        button.tap()
        return true
    }

    /// Chooses one interest and continues, for the tests that care what the
    /// answer does.
    @discardableResult
    func answerTheTrackingQuestion(_ interest: String, timeout: TimeInterval = 10) -> Bool {
        let option = element(withIdentifier: "interest.\(interest)")
        guard option.waitForExistence(timeout: timeout) else { return false }
        option.tap()
        let button = buttons["interests.continue"]
        guard button.waitForExistence(timeout: 5) else { return false }
        button.tap()
        return true
    }

    /// The element carrying `identifier`, whatever type it resolves to.
    ///
    /// A row in a SwiftUI List surfaces as a button when it wraps a
    /// NavigationLink, as a cell otherwise, and as a plain element when its
    /// children are combined for VoiceOver. A Toggle is a switch, or the row
    /// around it. Which one you get is an implementation detail of SwiftUI's
    /// accessibility tree, not something a test should assert on, and pinning
    /// a query to `otherElements` is a coin flip the first full UI run lost on
    /// every row in the app.
    ///
    /// This resolves lazily, so it works with `waitForExistence` on something
    /// that has not appeared yet.
    func element(withIdentifier identifier: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Scrolls down until `element` exists, or gives up.
    ///
    /// A SwiftUI `List` only realises the rows near the viewport, so a row
    /// further down genuinely is not in the accessibility tree yet — waiting
    /// on it will never find it, however long the timeout. The list has to be
    /// moved. Three UI tests failed on this: the oil task sits well down
    /// Today's "Needs setup" group, the odometer field is below the task list
    /// in the Log service sheet, and a catalog row is a long way down
    /// thirty-two of them.
    ///
    /// Scrolling has a reach, though, and it is shorter than it looks: these
    /// rows are several lines tall. A test that needs a row a dozen swipes
    /// away is better off asking for a nearer one than asking for a bigger
    /// budget.
    /// - Parameter hittable: require the element to be tappable, not merely
    ///   present. Existing and being reachable are different things: a row can
    ///   be in the tree while still off-screen, which is how an onboarding
    ///   test reported the primary action as reached and then failed to tap it.
    @discardableResult
    func scrollTo(_ element: XCUIElement, hittable: Bool = false, maxSwipes: Int = 12) -> Bool {
        func satisfied() -> Bool {
            guard element.exists else { return false }
            return hittable ? element.isHittable : true
        }

        _ = element.waitForExistence(timeout: 3)
        if satisfied() { return true }

        // Stop once the list stops moving, rather than swiping into the
        // bottom stop for the rest of the budget. A blind loop turns "that
        // row is not here" into a seventy-eight second timeout that says
        // nothing about why, which is exactly how the catalog test failed.
        var previous = rowSignature()
        var stalls = 0
        for _ in 0..<maxSwipes {
            swipeUp()
            if satisfied() { return true }

            let current = rowSignature()
            stalls = current == previous ? stalls + 1 : 0
            previous = current
            // Two in a row, so one settling bounce does not read as the end.
            if stalls >= 2 { break }
        }
        return satisfied()
    }

    /// The rows on screen right now, for a failure message that says what the
    /// test saw instead of only what it wanted.
    func visibleRowLabels(limit: Int = 8) -> [String] {
        rows().prefix(limit).map(\.label).filter { !$0.isEmpty }
    }

    /// Whether the realised rows have changed, as a cheap "did that swipe do
    /// anything?" signal.
    ///
    /// Row identity rather than pixels: a list that has hit its stop still
    /// rubber-bands, and a frame that springs back is not progress.
    private func rowSignature() -> String {
        let realised = rows()
        guard let first = realised.first, let last = realised.last else { return "no rows" }
        return "\(realised.count)|\(first.label)|\(last.label)"
    }

    /// SwiftUI surfaces `List` rows as cells, but not always — a row whose
    /// children are combined for VoiceOver can come through as a plain
    /// element. Falling back keeps both the stall check and the failure
    /// message working either way.
    private func rows() -> [XCUIElement] {
        let cells = descendants(matching: .cell).allElementsBoundByIndex
        return cells.isEmpty ? descendants(matching: .staticText).allElementsBoundByIndex : cells
    }

    /// Sets a switch and waits for it to say it changed.
    ///
    /// Three things this gets right that a bare `tap()` does not.
    ///
    /// The control is addressed *as a switch*. SwiftUI puts an identifier on
    /// the List row as well as on the control inside it, and a query across
    /// every descendant returns the row first — tapping that delivers a touch
    /// that changes nothing.
    ///
    /// The touch waits for the control to be hittable, not merely to exist.
    /// This screen is pushed onto a navigation stack, and a tap delivered
    /// while that push is still animating is swallowed without trace.
    ///
    /// And the new value is polled in Swift rather than through an
    /// `XCTNSPredicateExpectation`. A predicate over an element's `value` is a
    /// bridged KVC lookup, and a nil out of it reads exactly like a condition
    /// that has not come true yet — indistinguishable, from the outside, from
    /// the tap having failed.
    ///
    /// On failure it says what it saw, because the alternative is another
    /// twenty-five minute run to learn one boolean.
    @discardableResult
    func setSwitch(_ identifier: String, on: Bool, timeout: TimeInterval = 10) -> Bool {
        let control = switches[identifier]
        guard control.waitForExistence(timeout: timeout) else {
            XCTFail("no switch is exposed with the identifier \(identifier)")
            return false
        }

        let wanted = on ? "1" : "0"
        func reading() -> String { (control.value as? String) ?? "nil" }
        if reading() == wanted { return true }

        guard poll(timeout: timeout, until: { control.exists && control.isHittable }) else {
            XCTFail("the switch \(identifier) never became tappable — frame \(control.frame)")
            return false
        }

        // A UISwitch is about 51 points wide. Anything much wider is the row
        // the control sits in, published as a switch because that is what the
        // row *means* to VoiceOver — and the middle of that row is its label,
        // which a tap does nothing to. That is exactly what happened here: a
        // 380x72 "switch", tapped dead centre, twice, reading "0" both times.
        // The control itself is at the trailing edge.
        let isWholeRow = control.frame.width > 120
        let centre = { control.tap() }
        let trailingEdge = {
            control.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        }

        for touch in isWholeRow ? [trailingEdge, centre] : [centre, trailingEdge] {
            touch()
            if poll(timeout: 3, until: { (control.value as? String) == wanted }) { return true }
        }

        XCTFail("""
            the switch \(identifier) would not go to "\(wanted)" — \
            value "\(reading())", frame \(control.frame), tried \
            \(isWholeRow ? "trailing edge then centre" : "centre then trailing edge")
            """)
        return false
    }

    /// Waits for a condition by asking in Swift, on a fixed cadence.
    private func poll(timeout: TimeInterval, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        return condition()
    }

    /// Puts the keyboard away.
    ///
    /// Tapping a navigation bar's title is inert and closes it. Worth having
    /// as its own step: a number pad has no return key at all, and on an
    /// iPhone SE a keyboard covers more than half the screen — including rows
    /// a later step is about to look for. A capture run failed with
    /// "saw []", which was not a missing row but a Form with nothing visible
    /// at all underneath a keyboard nobody had dismissed.
    func dismissKeyboard() {
        // The app's own Done button first. It is the only reliable target:
        // tapping a navigation bar does not resign first responder in a
        // Form, and the field that needed this most — the odometer — has a
        // number pad with no return key to press instead.
        let done = element(withIdentifier: "addVehicle.dismissKeyboard")
        if done.exists, done.isHittable {
            done.tap()
            return
        }
        guard keyboards.element.exists, navigationBars.firstMatch.exists else { return }
        navigationBars.firstMatch.tap()
    }

    /// The first element whose identifier *begins with* `prefix`.
    ///
    /// For rows whose identifier carries a provider's own key — a
    /// configuration option is `confirm.option.<fueleconomy.gov id>` — which a
    /// test cannot know without hard-coding somebody else's database.
    func firstElement(withIdentifierPrefix prefix: String) -> XCUIElement {
        descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
            .firstMatch
    }

    /// Waits until `condition` holds, asking in Swift rather than through an
    /// expectation, so a test can wait on "either of these two things".
    @discardableResult
    func waitUntil(timeout: TimeInterval = 20, _ condition: () -> Bool) -> Bool {
        poll(timeout: timeout, until: condition)
    }

    /// Any element whose accessibility label contains `text`.
    ///
    /// Rows combine their children for VoiceOver, so the individual labels
    /// inside one are not separately addressable and matching on the combined
    /// label is the only way to assert on what a row says.
    func element(labelContaining text: String) -> XCUIElement {
        descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", text))
            .firstMatch
    }
}
