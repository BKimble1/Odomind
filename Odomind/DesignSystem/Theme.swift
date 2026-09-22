import SwiftUI
import UIKit
import OdomindCore

/// Visual constants.
///
/// Odomind aims at a quiet automotive surface: warm off-white and charcoal,
/// one muted teal that carries the brand, and colour reserved for meaning.
/// Every value below is a semantic token. Screens name the role — "the page
/// behind everything", "text that supports the main text" — never a hex
/// literal, so the palette can be adjusted in one place and measured once.
enum Theme {
    enum Spacing {
        static let tight: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let section: CGFloat = 24
    }

    enum Radius {
        static let card: CGFloat = 20
        static let tile: CGFloat = 16
        static let badge: CGFloat = 6
        /// The vehicle card at the top of the dashboard, which is larger than
        /// everything under it and reads as the object the screen is about.
        static let hero: CGFloat = 24
        /// A circular icon chip.
        static let chip: CGFloat = 999
    }

    /// The smallest comfortable target, per Apple's Human Interface Guidelines.
    /// Named so a control that has to be measured against it says why.
    static let minimumTapTarget: CGFloat = 44

    /// The brand and surface palette.
    ///
    /// Every text token clears 4.5:1 against each surface it is used on, in
    /// both appearances:
    ///
    /// | Token | on page (light / dark) | on raised (light / dark) |
    /// | --- | --- | --- |
    /// | `primaryText` | 16.2 / 17.2 | 17.4 / 14.8 |
    /// | `secondaryText` | 6.0 / 9.4 | 6.4 / 8.1 |
    /// | `accent` | 5.7 / 8.2 | 6.1 / 7.1 |
    /// | `onAccent` over `accent` | 6.1 / 8.5 | — |
    ///
    /// `ContrastTests` recomputes this table from the tokens themselves and
    /// fails if any pair drops below its bar, so the numbers here cannot
    /// quietly go stale the way a comment normally does.
    ///
    /// `separator` is the one token deliberately below 3:1 — about 1.4:1
    /// either way. It draws the hairline between rows, which is decoration:
    /// rows are told apart by their own text, and nothing is lost if the line
    /// is not seen. WCAG's 3:1 non-text bar covers boundaries you need in
    /// order to understand or operate the content, and the places this app
    /// has those — a selected paint swatch, a focused field — carry `accent`
    /// and a matching accessibility trait rather than a hairline. Darkening a
    /// row divider to 3:1 would not help anyone read a row; it would just
    /// draw a grid.
    ///
    /// Computed ratios are not a substitute for looking at a rendered screen,
    /// which is why the accessibility audit still runs over every screen in
    /// CI and why light and dark screenshots are inspected before a release.
    enum Palette {
        /// The page behind everything.
        static let page = dynamic(light: 0xF6F7F7, dark: 0x101416)
        /// A card or row sitting on the page.
        static let raised = dynamic(light: 0xFFFFFF, dark: 0x1B2326)
        /// A surface one step further back than `raised` — a well, a field,
        /// the inside of a segmented control.
        static let recessed = dynamic(light: 0xECEEEF, dark: 0x161D20)
        static let primaryText = dynamic(light: 0x151B1D, dark: 0xF4F7F7)
        static let secondaryText = dynamic(light: 0x536166, dark: 0xAEBBBF)
        /// The brand teal, taken dark enough for light mode and light enough
        /// for dark mode to read as text in either.
        static let accent = dynamic(light: 0x146E68, dark: 0x73B9AF)
        /// Label colour on a filled `accent` button. White on the light teal,
        /// near-black on the dark teal — a white label on the dark-mode teal
        /// measures 2.3:1 and is exactly the weak-contrast mint the brief
        /// called out.
        static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x0B1012)
        /// A hairline between rows. A boundary, so 3:1 is the bar, not 4.5:1.
        static let separator = dynamic(light: 0xD3D9DA, dark: 0x303B3F)
        /// The quiet ground a vehicle illustration sits on.
        static let artworkGround = dynamic(light: 0xE9EDEE, dark: 0x192124)

        /// The hairline around a card. Lighter than `separator`, because a
        /// card is already told apart from the page by its fill; this only
        /// stops white-on-white disappearing.
        static let cardBorder = dynamic(light: 0xEBEEEF, dark: 0x1D2529)

        // The two tints in the luminous field behind the dashboard. Held as
        // tokens rather than written into the view so the field can be
        // measured and tuned in one place — it sits under every screen.
        static let fieldPrimary = dynamic(light: 0x146E68, dark: 0x34B2A2)
        static let fieldSecondary = dynamic(light: 0x7BA0D2, dark: 0x607EC6)

        // Pastel grounds for the icon chips. Each is paired with a foreground
        // from `Colors` or `accent`, and the pair is what the contrast test
        // measures — a chip is a coloured circle with a glyph in it, so the
        // glyph has to clear 3:1 against its own ground, not against the page.
        static let chipAccent = dynamic(light: 0xE4F1EF, dark: 0x13312E)
        static let chipInformative = dynamic(light: 0xE8EEFB, dark: 0x16223A)
        static let chipOverdue = dynamic(light: 0xFDEAE6, dark: 0x3A1B16)
        static let chipCaution = dynamic(light: 0xF8E7C8, dark: 0x3A2C11)
        /// The ground of the whole attention card, not just its chip.
        static let cautionSurface = dynamic(light: 0xFDF4E3, dark: 0x1D1710)

        private static func dynamic(light: UInt32, dark: UInt32) -> Color {
            Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
            })
        }
    }

    /// Colours that carry meaning, chosen to stay legible as text.
    ///
    /// The system colours — `.red`, `.orange`, `.green`, `.blue` — are fill
    /// colours. Measured as small text on a light grouped background they come
    /// in at roughly 3.5:1, 2.2:1, 2.2:1 and 4.0:1, against the 4.5:1 that
    /// WCAG asks for and that XCTest's accessibility audit checks. Used on a
    /// badge, which is exactly where a due state appears, they fail.
    ///
    /// Each of these is the same hue taken dark enough for light mode and
    /// light enough for dark mode to clear the threshold either way. They work
    /// for the matching icon too, so a state has one colour rather than two.
    enum Colors {
        static let caution = dynamic(light: (0.54, 0.31, 0.00), dark: (1.00, 0.76, 0.40))
        static let overdue = dynamic(light: (0.77, 0.16, 0.11), dark: (1.00, 0.54, 0.50))
        static let informative = dynamic(light: (0.04, 0.36, 0.77), dark: (0.44, 0.70, 1.00))
        static let unknown = dynamic(light: (0.42, 0.25, 0.63), dark: (0.79, 0.63, 0.94))
        static let done = dynamic(light: (0.11, 0.48, 0.24), dark: (0.37, 0.84, 0.54))

        private static func dynamic(
            light: (CGFloat, CGFloat, CGFloat),
            dark: (CGFloat, CGFloat, CGFloat)
        ) -> Color {
            Color(uiColor: UIColor { traits in
                let (r, g, b) = traits.userInterfaceStyle == .dark ? dark : light
                return UIColor(red: r, green: g, blue: b, alpha: 1)
            })
        }
    }
}

extension UIColor {
    /// Opaque colour from a 24-bit RGB literal, so the palette reads as the
    /// hex values it was designed and measured as.
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension DueState {
    /// The one place a due state turns into colour, so the palette cannot drift
    /// between screens.
    var tint: Color {
        switch self {
        case .overdue: return Theme.Colors.overdue
        case .dueSoon: return Theme.Colors.caution
        case .upcoming: return Theme.Palette.secondaryText
        case .historyUnknown: return Theme.Colors.unknown
        case .needsSetup: return Theme.Colors.informative
        case .completed: return Theme.Colors.done
        case .notApplicable: return Theme.Palette.secondaryText
        }
    }

    var symbolName: String {
        switch self {
        case .overdue: return "exclamationmark.triangle.fill"
        case .dueSoon: return "clock.fill"
        case .upcoming: return "calendar"
        case .historyUnknown: return "questionmark.circle"
        case .needsSetup: return "slider.horizontal.3"
        case .completed: return "checkmark.circle.fill"
        case .notApplicable: return "minus.circle"
        }
    }

    /// A short label for a calendar legend or a compact chip, where the full
    /// `displayName` is more words than the space deserves.
    var shortLabel: String {
        switch self {
        case .overdue: return "Overdue"
        case .dueSoon: return "Due soon"
        case .upcoming: return "Upcoming"
        case .historyUnknown: return "Unknown"
        case .needsSetup: return "Set up"
        case .completed: return "Done"
        case .notApplicable: return "N/A"
        }
    }

    /// The sentence under a group heading. Deliberately about the records
    /// Odomind holds, never about the mechanical condition of the vehicle.
    var groupExplanation: String {
        switch self {
        case .overdue:
            return "Past due based on your records."
        case .dueSoon:
            return "Coming up soon based on your records."
        case .upcoming:
            return "Scheduled, but not yet close."
        case .historyUnknown:
            return "You told Odomind you do not know when these were last done."
        case .needsSetup:
            return "Odomind needs something from you before it can schedule these."
        case .completed:
            return "One-time work that has been done."
        case .notApplicable:
            return "Does not apply to this vehicle."
        }
    }
}

extension DataOrigin {
    var symbolName: String {
        switch self {
        case .manufacturerSourced: return "checkmark.seal"
        case .referenceSourced: return "doc.text.magnifyingglass"
        case .generalTemplate: return "text.book.closed"
        case .userEntered: return "person.crop.circle"
        }
    }
}
