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

    /// Everything below depends on a token still being dynamic after the
    /// round trip through `Color`. If SwiftUI ever flattens it to whichever
    /// appearance the test process happens to be in, every ratio would be
    /// measured against the wrong background and the failures would name
    /// contrast rather than the actual cause. This says the actual cause.
    func testTokensStayDynamicThroughTheRoundTripToColor() {
        for (name, token) in [
            ("page", Theme.Palette.page),
            ("primaryText", Theme.Palette.primaryText),
            ("accent", Theme.Palette.accent),
        ] {
            let light = resolve(token, .light)
            let dark = resolve(token, .dark)
            XCTAssertNotEqual(
                light, dark,
                "\(name) resolves to the same colour in both appearances — the dynamic provider was lost converting Color back to UIColor, so nothing below is measuring what it says it is"
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

    // MARK: - Build 4's chips and surfaces

    /// A chip is a coloured circle with a glyph in it, so the glyph has to
    /// clear the bar against **its own ground**, not against the page. Build 4
    /// added five such grounds and the Theme comment claimed this test covered
    /// them; it did not, so nothing measured a single one.
    ///
    /// 3:1 rather than 4.5:1, and deliberately: a chip glyph is a large
    /// graphical object — an SF Symbol at 19 points, semibold — which is the
    /// case WCAG's non-text bar is for. The words beside it carry the meaning
    /// and are measured at 4.5:1 elsewhere.
    func testEveryChipGlyphClearsItsOwnGround() {
        assertContrast(Theme.Palette.accent, on: Theme.Palette.chipAccent,
                       atLeast: 3, "accent glyph on the accent chip")
        assertContrast(Theme.Colors.informative, on: Theme.Palette.chipInformative,
                       atLeast: 3, "informative glyph on its chip")
        assertContrast(Theme.Colors.overdue, on: Theme.Palette.chipOverdue,
                       atLeast: 3, "overdue glyph on its chip")
        assertContrast(Theme.Colors.caution, on: Theme.Palette.chipCaution,
                       atLeast: 3, "caution glyph on its chip")
    }

    /// The status pill puts a word on a chip ground, not just a glyph, so that
    /// pairing is text and takes the 4.5:1 bar.
    func testStatusPillTextClearsItsGround() {
        assertContrast(Theme.Palette.accent, on: Theme.Palette.chipAccent,
                       atLeast: 4.5, "pill text on the accent chip")
        assertContrast(Theme.Colors.overdue, on: Theme.Palette.chipOverdue,
                       atLeast: 4.5, "pill text on the overdue chip")
        assertContrast(Theme.Colors.caution, on: Theme.Palette.chipCaution,
                       atLeast: 4.5, "pill text on the caution chip")
    }

    /// AttentionCard tints the whole card, so every word on it is measured
    /// against that tint rather than against `raised`.
    func testTextOnTheAttentionCardClearsItsWarmGround() {
        assertContrast(Theme.Palette.primaryText, on: Theme.Palette.cautionSurface,
                       atLeast: 4.5, "attention card title")
        assertContrast(Theme.Palette.secondaryText, on: Theme.Palette.cautionSurface,
                       atLeast: 4.5, "attention card detail")
    }

    /// The luminous field is drawn under every screen, so `page` is no longer
    /// the darkest thing a card sits on. The tint is faint by design — 17% and
    /// 13% at full strength — but "faint" is an intention, not a measurement.
    ///
    /// Composited at full strength over the page, the field must still leave
    /// body text on a card clearing the bar. A card is opaque `raised`, so the
    /// pairing that actually matters is unchanged; what this guards is the
    /// text Odomind draws directly on the field, which the dashboard header
    /// does.
    func testTextDrawnStraightOnTheFieldStaysLegible() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let name = style == .dark ? "dark" : "light"
            let page = resolve(Theme.Palette.page, style)
            for (tint, strength, which) in [
                (Theme.Palette.fieldPrimary, 0.17, "primary"),
                (Theme.Palette.fieldSecondary, 0.13, "secondary"),
            ] {
                let lit = blend(resolve(tint, style), over: page, alpha: strength)
                for (token, label) in [
                    (Theme.Palette.primaryText, "primary text"),
                    (Theme.Palette.secondaryText, "secondary text"),
                ] {
                    let measured = ratio(resolve(token, style), on: lit)
                    XCTAssertGreaterThanOrEqual(
                        measured, 4.5,
                        String(
                            format: "%@ over the %@ field measures %.2f:1 in %@ mode",
                            label, which, measured, name
                        )
                    )
                }
            }
        }
    }

    /// Source-over compositing, so the field can be measured at the strength
    /// it is actually drawn at rather than at full opacity.
    private func blend(_ top: UIColor, over bottom: UIColor, alpha: CGFloat) -> UIColor {
        var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        top.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)
        bottom.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return UIColor(
            red: tr * alpha + br * (1 - alpha),
            green: tg * alpha + bg * (1 - alpha),
            blue: tb * alpha + bb * (1 - alpha),
            alpha: 1
        )
    }
}
