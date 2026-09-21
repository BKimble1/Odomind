import SwiftUI
import UIKit
import OdomindCore

/// Visual constants.
///
/// Odomind leans on the system's own semantic colours and type styles. The
/// point is a quiet, native surface where the only colour that carries meaning
/// is the one attached to a due state — not a wall of tinted cards.
enum Theme {
    enum Spacing {
        static let tight: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let section: CGFloat = 24
    }

    enum Radius {
        static let card: CGFloat = 12
        static let badge: CGFloat = 6
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

extension DueState {
    /// The one place a due state turns into colour, so the palette cannot drift
    /// between screens.
    var tint: Color {
        switch self {
        case .overdue: return Theme.Colors.overdue
        case .dueSoon: return Theme.Colors.caution
        case .upcoming: return .secondary
        case .historyUnknown: return Theme.Colors.unknown
        case .needsSetup: return Theme.Colors.informative
        case .completed: return Theme.Colors.done
        case .notApplicable: return .secondary
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
