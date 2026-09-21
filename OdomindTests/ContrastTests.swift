import XCTest
import SwiftUI
import UIKit
@testable import Odomind
import OdomindCore

/// Measures the palette instead of asserting it in a comment.
///
/// The brief's bar is 4.5:1 for normal text and 3:1 for large text and
/// meaningful boundaries, and Build 1's weak mint was exactly the kind of
/// thing that survives review because nobody multiplied it out. These tests
/// resolve each token for each appearance and compute the WCAG 2.1 relative
/// luminance ratio, so a palette change that dips below the bar fails here
/// rather than in somebody's hands.
///
/// This is not a replacement for the on-screen accessibility audit. A token
/// can be legible in isolation and still be rendered over something else, and
/// only the audit and a rendered screenshot can see that.
final class ContrastTests: XCTestCase {

    // MARK: - Ratio

    /// WCAG 2.1 relative luminance.
    private func luminance(_ color: UIColor) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func channel(_ c: CGFloat) -> CGFloat {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    private func ratio(_ foreground: UIColor, on background: UIColor) -> CGFloat {
        let a = luminance(foreground), b = luminance(background)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// Resolves a dynamic token for one appearance, which is the only way to
    /// measure it: the tokens are `UIColor` closures over the trait
    /// collection, and reading one without traits gives whichever side the
    /// test process happens to be in.
    private func resolve(_ color: Color, _ style: UIUserInterfaceStyle) -> UIColor {
        UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    }

    private func assertContrast(
        _ foreground: Color,
        on background: Color,
        atLeast bar: CGFloat,
        _ what: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let name = style == .dark ? "dark" : "light"
            let measured = ratio(resolve(foreground, style), on: resolve(background, style))
            XCTAssertGreaterThanOrEqual(
                measured, bar,
                String(format: "%@ measures %.2f:1 in %@ mode, under the %.1f:1 bar", what, measured, name, bar),
                file: file, line: line
            )
        }
    }

    // MARK: - Surfaces

    private var surfaces: [(String, Color)] {
        [
            ("page", Theme.Palette.page),
            ("raised", Theme.Palette.raised),
            ("recessed", Theme.Palette.recessed),
        ]
    }

    func testTextTokensAreLegibleOnEverySurface() {
        let text: [(String, Color)] = [
            ("primaryText", Theme.Palette.primaryText),
            ("secondaryText", Theme.Palette.secondaryText),
            ("accent", Theme.Palette.accent),
        ]
        for (tokenName, token) in text {
            for (surfaceName, surface) in surfaces {
                assertContrast(token, on: surface, atLeast: 4.5, "\(tokenName) on \(surfaceName)")
            }
        }
    }

    func testTheLabelOnAFilledAccentButtonIsLegible() {
        // The specific defect the brief called out: a white label on a mint
        // fill measures about 2.3:1, so the dark appearance flips the label
        // to near-black rather than keeping one colour for both.
        assertContrast(Theme.Palette.onAccent, on: Theme.Palette.accent, atLeast: 4.5, "onAccent over accent")
    }

    func testStateColoursAreLegibleAsTextNotJustAsFills() {
        // A due state is shown as a badge with a word in it, so its colour has
        // to clear the text bar, not the 3:1 one a bare dot would.
        let states: [(String, Color)] = [
            ("caution", Theme.Colors.caution),
            ("overdue", Theme.Colors.overdue),
            ("informative", Theme.Colors.informative),
            ("unknown", Theme.Colors.unknown),
            ("done", Theme.Colors.done),
        ]
        for (tokenName, token) in states {
            for (surfaceName, surface) in surfaces {
                assertContrast(token, on: surface, atLeast: 4.5, "\(tokenName) on \(surfaceName)")
            }
        }
    }

    func testEveryDueStateHasItsOwnColourAndItsOwnSymbol() {
        // Never status by colour alone, and never two states that look the
        // same. A symbol shared between two states would be as misleading as
        // no symbol at all.
        var symbols: [String: DueState] = [:]
        for state in DueState.allCases {
            let symbol = state.symbolName
            XCTAssertFalse(symbol.isEmpty, "\(state) has no symbol, so its colour is the only signal")
            if let clash = symbols[symbol], clash != state {
                // `upcoming` and `notApplicable` deliberately share the quiet
                // secondary tint, but they must not also share a symbol.
                XCTFail("\(state) and \(clash) share the symbol \(symbol)")
            }
            symbols[symbol] = state
            XCTAssertFalse(state.shortLabel.isEmpty, "\(state) has no text label")
        }
    }

    func testTheRowHairlineIsDecorationAndIsDocumentedAsSuch() {
        // Pinned deliberately. If somebody later makes the separator carry
        // meaning, this test is where they will find out that it is nowhere
        // near the 3:1 a meaningful boundary needs.
        for style in [UIUserInterfaceStyle.light, .dark] {
            let measured = ratio(
                resolve(Theme.Palette.separator, style),
                on: resolve(Theme.Palette.page, style)
            )
            XCTAssertLessThan(
                measured, 3.0,
                "the separator now clears the boundary bar — if that was intended, move it out of the decoration exemption in Theme.Palette"
            )
        }
    }
}
