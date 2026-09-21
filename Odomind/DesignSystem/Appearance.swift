import SwiftUI
import UIKit

/// Applies the owner's appearance choice to the whole app, sheets included.
///
/// `preferredColorScheme` covers the view hierarchy it is attached to, but a
/// sheet, a confirmation dialog and StoreKit's own purchase sheet are presented
/// by UIKit outside that hierarchy — which is how an app ends up with a dark
/// home screen and a stubbornly light paywall. Setting
/// `overrideUserInterfaceStyle` on the window covers every presentation in it,
/// because they all live in the same window.
///
/// Both are applied: the window override does the work, and
/// `preferredColorScheme` keeps SwiftUI's own `colorScheme` environment value
/// in step so views that read it directly agree with what is on screen.
struct AppearanceModifier: ViewModifier {
    let preference: AppearancePreference

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(preference.colorScheme)
            .onAppear { apply() }
            .onChange(of: preference) { _, _ in apply() }
    }

    private func apply() {
        let style: UIUserInterfaceStyle
        switch preference {
        case .system: style = .unspecified
        case .light: style = .light
        case .dark: style = .dark
        }
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where window.overrideUserInterfaceStyle != style {
                window.overrideUserInterfaceStyle = style
            }
        }
    }
}

extension View {
    func odomindAppearance(_ preference: AppearancePreference) -> some View {
        modifier(AppearanceModifier(preference: preference))
    }
}
