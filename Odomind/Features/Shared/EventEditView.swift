import EventKitUI
import SwiftUI

/// Presents the system's own event editor.
///
/// On iOS 17 and later this controller runs outside the app's process and has
/// its own calendar access, so Odomind never asks for calendar permission. The
/// owner sees exactly what will be saved and which calendar it goes to.
struct EventEditView: UIViewControllerRepresentable {
    let event: EKEvent
    /// Held by the caller for the lifetime of the sheet: EventKit objects must
    /// not outlive the store they came from.
    let eventStore: EKEventStore
    let onComplete: (EKEventEditViewAction) -> Void

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let controller = EKEventEditViewController()
        controller.eventStore = eventStore
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onComplete: (EKEventEditViewAction) -> Void

        init(onComplete: @escaping (EKEventEditViewAction) -> Void) {
            self.onComplete = onComplete
        }

        /// Called for saved, cancelled and deleted alike, so a cancel is handled
        /// as explicitly as a save and never leaves the sheet stuck.
        func eventEditViewController(
            _ controller: EKEventEditViewController,
            didCompleteWith action: EKEventEditViewAction
        ) {
            onComplete(action)
            controller.dismiss(animated: true)
        }
    }
}
