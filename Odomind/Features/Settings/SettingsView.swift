import SwiftUI
import UIKit
import OdomindCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationRouter.self) private var router

    @State private var showingDeleteAll = false

    var body: some View {
        List {
            Section {
                NavigationLink(value: SettingsRoute.appearance) {
                    LabeledContent {
                        Text(model.appearance.displayName)
                            .foregroundStyle(Theme.Palette.secondaryText)
                    } label: {
                        Label("Appearance", systemImage: "circle.lefthalf.filled")
                    }
                }
                .accessibilityIdentifier("settings.appearance")
                NavigationLink(value: SettingsRoute.reminders) {
                    Label("Notifications", systemImage: "bell")
                }
                .accessibilityIdentifier("settings.reminders")
                NavigationLink(value: SettingsRoute.calendar) {
                    Label("Calendar", systemImage: "calendar")
                }
                NavigationLink(value: SettingsRoute.units) {
                    Label("Units", systemImage: "ruler")
                }
            }

            Section {
                NavigationLink(value: SettingsRoute.pro) {
                    LabeledContent {
                        Text(model.isPro ? "Active" : "Free plan")
                            .foregroundStyle(Theme.Palette.secondaryText)
                    } label: {
                        Label("Odomind Pro", systemImage: "checkmark.seal")
                    }
                }
                .accessibilityIdentifier("settings.pro")
                NavigationLink(value: SettingsRoute.catalogUpdates) {
                    Label("Maintenance updates", systemImage: "arrow.triangle.2.circlepath")
                }
            }

            Section {
                NavigationLink(value: SettingsRoute.backup) {
                    Label("Backup and export", systemImage: "arrow.down.doc")
                }
                NavigationLink(value: SettingsRoute.dataSources) {
                    Label("Where the data comes from", systemImage: "doc.text.magnifyingglass")
                }
                NavigationLink(value: SettingsRoute.privacy) {
                    Label("Privacy", systemImage: "hand.raised")
                }
                Link(destination: SupportLinks.terms) {
                    Label("Terms of use", systemImage: "doc.text")
                }
                .accessibilityIdentifier("settings.terms")
                NavigationLink(value: SettingsRoute.about) {
                    Label("About Odomind", systemImage: "info.circle")
                }
                Link(destination: SupportLinks.support) {
                    Label("Support", systemImage: "lifepreserver")
                }
            }

            Section {
                NavigationLink(value: SettingsRoute.sampleData) {
                    LabeledContent {
                        Text(model.hasDemoContent ? "On" : "Off")
                            .foregroundStyle(Theme.Palette.secondaryText)
                    } label: {
                        Label("Sample vehicle", systemImage: "car.side")
                    }
                }
                NavigationLink(value: SettingsRoute.diagnostics) {
                    Label("Diagnostics", systemImage: "stethoscope")
                }
            } footer: {
                Text("What Odomind has scheduled, and anything it could not read.")
            }

            // Kept in its own section at the bottom, well away from anything
            // anyone taps routinely.
            Section {
                Button("Delete all data", role: .destructive) { showingDeleteAll = true }
                    .accessibilityIdentifier("settings.deleteAll")
            } footer: {
                Text("Removes everything from this device and cancels every reminder. Cannot be undone.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(LuminousField(strength: 0.5))
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete everything?", isPresented: $showingDeleteAll, titleVisibility: .visible) {
            Button("Delete all data", role: .destructive) {
                Task { await model.deleteAllData() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every vehicle, mileage reading, job, service record and receipt is deleted from this device. Export a backup first if you want to keep any of it.")
        }
    }
}

struct ReminderSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let settings = model.snapshot.settings.reminders

        List {
            Section {
                Toggle(
                    "Reminders",
                    isOn: Binding(
                        get: { settings.remindersEnabled },
                        set: { newValue in
                            Task {
                                if newValue {
                                    _ = await model.enableReminders()
                                } else {
                                    await model.disableReminders()
                                }
                            }
                        }
                    )
                )
            } footer: {
                Text("Asks for permission when you turn this on, not before.")
            }

            if settings.remindersEnabled {
                Section {
                    DatePicker(
                        "Preferred time",
                        selection: Binding(
                            get: {
                                var components = DateComponents()
                                components.hour = settings.preferredHour
                                components.minute = settings.preferredMinute
                                return model.calendar.date(from: components) ?? Date()
                            },
                            set: { newValue in
                                let components = model.calendar.dateComponents([.hour, .minute], from: newValue)
                                Task {
                                    await model.updateReminderSettings {
                                        $0 = ReminderSettings(
                                            remindersEnabled: $0.remindersEnabled,
                                            mileageUpdateRemindersEnabled: $0.mileageUpdateRemindersEnabled,
                                            mileageUpdateIntervalDays: $0.mileageUpdateIntervalDays,
                                            preferredHour: components.hour ?? 9,
                                            preferredMinute: components.minute ?? 0,
                                            includeEstimatedMileageReminders: $0.includeEstimatedMileageReminders
                                        )
                                    }
                                }
                            }
                        ),
                        displayedComponents: .hourAndMinute
                    )

                    Toggle(
                        "Estimated mileage reminders",
                        isOn: Binding(
                            get: { settings.includeEstimatedMileageReminders },
                            set: { newValue in
                                Task {
                                    await model.updateReminderSettings {
                                        $0 = ReminderSettings(
                                            remindersEnabled: $0.remindersEnabled,
                                            mileageUpdateRemindersEnabled: $0.mileageUpdateRemindersEnabled,
                                            mileageUpdateIntervalDays: $0.mileageUpdateIntervalDays,
                                            preferredHour: $0.preferredHour,
                                            preferredMinute: $0.preferredMinute,
                                            includeEstimatedMileageReminders: newValue
                                        )
                                    }
                                }
                            }
                        )
                    )
                } header: {
                    Text("Delivery")
                } footer: {
                    Text("An estimated reminder says so. Odomind cannot watch your odometer.")
                }

                Section {
                    Toggle(
                        "Remind me to update my mileage",
                        isOn: Binding(
                            get: { settings.mileageUpdateRemindersEnabled },
                            set: { newValue in
                                Task {
                                    await model.updateReminderSettings { $0.mileageUpdateRemindersEnabled = newValue }
                                }
                            }
                        )
                    )
                    if settings.mileageUpdateRemindersEnabled {
                        Stepper(
                            "Every \(settings.mileageUpdateIntervalDays) days",
                            value: Binding(
                                get: { settings.mileageUpdateIntervalDays },
                                set: { newValue in
                                    Task {
                                        await model.updateReminderSettings { $0.mileageUpdateIntervalDays = newValue }
                                    }
                                }
                            ),
                            in: 7...180,
                            step: 7
                        )
                    }
                } header: {
                    Text("Mileage")
                } footer: {
                    Text("A current reading is what keeps next-due information accurate.")
                }

                Section {
                    ValueRow(label: "Scheduled now", value: "\(model.reminderReport.unchanged + model.reminderReport.scheduled)")
                    if model.reminderReport.wasTruncated {
                        InlineNotice(
                            kind: .caution,
                            message: "iOS limits how many reminders an app can have pending, so Odomind keeps the nearest \(ReminderPlanner.maximumPendingRequests) and schedules the rest as those fire."
                        )
                    }
                    if model.reminderReport.authorization == .denied {
                        InlineNotice(
                            kind: .caution,
                            message: "Notifications are turned off for Odomind in iOS Settings, so nothing will be delivered."
                        )
                        // iOS only lets an app ask once. After a refusal the
                        // only way back is Settings, so saying so without
                        // offering the way there is a dead end.
                        if let settings = URL(string: UIApplication.openSettingsURLString) {
                            Link(destination: settings) {
                                Label("Open Odomind's settings", systemImage: "arrow.up.forward.app")
                            }
                            .accessibilityIdentifier("reminders.openSettings")
                        }
                    }
                } header: {
                    Text("Status")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(LuminousField(strength: 0.5))
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
    }
}
