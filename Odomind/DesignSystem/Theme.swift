import SwiftUI
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
}

extension DueState {
    /// The one place a due state turns into colour, so the palette cannot drift
    /// between screens.
    var tint: Color {
        switch self {
        case .overdue: return .red
        case .dueSoon: return .orange
        case .upcoming: return .secondary
        case .historyUnknown: return .purple
        case .needsSetup: return .blue
        case .completed: return .green
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
