import XCTest

extension XCUIApplication {

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
    /// Two things this gets right that a bare `tap()` does not.
    ///
    /// The control has to be addressed *as a switch*. SwiftUI puts an
    /// identifier on the List row as well as on the control inside it, and a
    /// query across every descendant returns the row first — tapping that
    /// delivers a touch that changes nothing. That cost two full CI runs: the
    /// catalog test reported "the row is not there" and swiped through a list
    /// that was still filtered, because the toggle meant to unfilter it had
    /// never moved.
    ///
    /// And `tap()` returns when the touch is delivered, not when the app has
    /// acted on it, so the new value is waited for rather than read straight
    /// back off a busy runner.
    @discardableResult
    func setSwitch(_ identifier: String, on: Bool, timeout: TimeInterval = 10) -> Bool {
        let control = switches[identifier]
        guard control.waitForExistence(timeout: timeout) else { return false }

        let wanted = on ? "1" : "0"
        if control.value as? String == wanted { return true }
        control.tap()

        let settled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", wanted),
            object: control
        )
        return XCTWaiter().wait(for: [settled], timeout: timeout) == .completed
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
