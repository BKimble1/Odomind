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
    /// in the Log service sheet, and an alignment check is a long way into the
    /// catalog.
    @discardableResult
    func scrollTo(_ element: XCUIElement, maxSwipes: Int = 8) -> Bool {
        if element.waitForExistence(timeout: 3) { return true }
        for _ in 0..<maxSwipes {
            swipeUp()
            if element.exists { return true }
        }
        return element.exists
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
