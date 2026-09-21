import SwiftUI
import OdomindCore

/// Where every value in the app comes from, and what it is not.
///
/// Published in the app rather than buried in a repository, because the honest
/// answer to "how do you know that?" is part of the product.
struct DataSourcesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section {
                switch model.catalogService.updateStatus {
                case .bundled(let version, let publishedOn):
                    ValueRow(label: "Version", value: version)
                    ValueRow(label: "Published", value: Format.date(publishedOn))
                case .unavailable(let message):
                    InlineNotice(kind: .caution, message: message)
                }
                Text(model.catalogService.updateStatus.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Maintenance catalog")
            }

            if let catalog = model.catalogService.catalog {
                Section {
                    Text(catalog.coverageNotice)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text("What Odomind covers")
                }

                ForEach(catalog.sources) { source in
                    Section {
                        if let url = source.url, let link = URL(string: url) {
                            Link(destination: link) {
                                Label(url, systemImage: "link")
                                    .font(.caption)
                            }
                        }
                        ValueRow(
                            label: "Redistribution",
                            value: source.allowsRedistribution ? "Permitted" : "Not permitted"
                        )
                        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                            labelled("Covers", source.coverage)
                            labelled("Terms", source.terms)
                            labelled("Known limits", source.limitations)
                            if let attribution = source.attributionText {
                                labelled("Attribution", attribution)
                            }
                        }
                        .padding(.vertical, 2)
                    } header: {
                        Text(source.name)
                    }
                }

                if !catalog.vehicleProfiles.isEmpty {
                    ForEach(catalog.vehicleProfiles) { profile in
                        Section {
                            ForEach(Array(profile.coverageNotes.enumerated()), id: \.offset) { _, note in
                                Text(note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } header: {
                            Text(profile.displayName)
                        }
                    }
                }
            }

            Section {
                Text("""
                Odomind sends nothing anywhere unless you ask it to. The one external request it can make is a \
                VIN lookup to \(model.identificationProvider.contactedHost), and it asks before the first one. \
                Everything else — your mileage, your history, your receipts — stays on this device.
                """)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Vehicle identification")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Data sources")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func labelled(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct PrivacyView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section {
                Text("""
                Odomind keeps your records on your device. There is no account, no sign-in, no analytics and no \
                advertising SDK. Nothing about your vehicles is uploaded.
                """)
                .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Text("""
                If you decode a VIN, that VIN is sent to \(model.identificationProvider.contactedHost) — the U.S. \
                National Highway Traffic Safety Administration's public vehicle catalog — to look up what the \
                vehicle is. Odomind asks before the first lookup and you can always add a vehicle by hand instead. \
                Nothing else is sent with it: no name, no account, no other vehicle details.
                """)
                .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("The one request Odomind makes")
            }

            Section {
                Text("""
                Your VIN is stored locally and shown only as its last six characters unless you open the field. \
                It is never written to a log, an error report or a screenshot, and it is left out of exports \
                unless you switch it on.
                """)
                .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("VIN handling")
            }

            Section {
                Text("""
                Receipts and photos you attach are stored in Odomind's own folder on this device. Deleting a \
                record deletes its files. "Delete all data" removes everything, including every pending reminder.
                """)
                .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Receipts and photos")
            }

            Section {
                Text("""
                Notification permission is requested when you turn a reminder on, not at launch. Camera access is \
                requested when you scan a VIN, not before. Odomind never asks for calendar access: the system's own \
                event editor handles adding an event, outside Odomind's process.
                """)
                .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Permissions")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AboutView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                    Text("Odomind")
                        .font(.title2.weight(.semibold))
                    Text("Know your car. Know what's next.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Version \(model.appVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, Theme.Spacing.small)
            }

            Section {
                Text("""
                Odomind is built by Idlery Services LLC. It tracks what you tell it: your mileage, the work you \
                have had done, and the specifications you record from your owner's manual.
                """)
                .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Text("""
                Odomind is not a source of mechanical, safety or repair advice, and it is not a substitute for \
                your manufacturer's maintenance schedule. Where it does not have a value it says so rather than \
                showing a number it cannot stand behind.
                """)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("What this app is not")
            }

            Section {
                NavigationLink(value: SettingsRoute.dataSources) {
                    Label("Where the data comes from", systemImage: "doc.text.magnifyingglass")
                }
                NavigationLink(value: SettingsRoute.privacy) {
                    Label("Privacy", systemImage: "hand.raised")
                }
            }

            Section {
                Text("Support is handled through the project's public repository. There is no separate support site.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Support")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// What Odomind has actually scheduled, and anything it could not read.
struct DiagnosticsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section {
                ValueRow(label: "Vehicles", value: "\(model.snapshot.vehicles.count)")
                ValueRow(label: "Mileage readings", value: "\(model.snapshot.readings.count)")
                ValueRow(label: "Tracked tasks", value: "\(model.snapshot.planItems.count)")
                ValueRow(label: "Service records", value: "\(model.snapshot.serviceRecords.count)")
                ValueRow(label: "Attachments", value: "\(model.snapshot.attachments.count)")
            } header: {
                Text("Stored")
            }

            Section {
                ValueRow(label: "Permission", value: model.reminderReport.authorization.rawValue)
                ValueRow(label: "Planned", value: "\(model.reminderReport.plannedCount)")
                ValueRow(label: "Scheduled last run", value: "\(model.reminderReport.scheduled)")
                ValueRow(label: "Cancelled last run", value: "\(model.reminderReport.cancelled)")
                ValueRow(label: "Left alone", value: "\(model.reminderReport.unchanged)")
                if model.reminderReport.ranAt != .distantPast {
                    ValueRow(label: "Last run", value: Format.dateAndTime(model.reminderReport.ranAt))
                }
                ForEach(model.reminderReport.failures, id: \.self) { failure in
                    InlineNotice(kind: .caution, message: failure)
                }
            } header: {
                Text("Reminders")
            }

            Section {
                if model.snapshot.problems.isEmpty {
                    Label("Everything read cleanly", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                } else {
                    ForEach(model.snapshot.problems) { problem in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(problem.context).font(.callout.weight(.medium))
                            Text(problem.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            } header: {
                Text("Data health")
            } footer: {
                Text("If anything here looks wrong, export a backup before making changes.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
    }
}
