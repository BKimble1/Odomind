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
                    ValueRow(label: "Source", value: "Shipped with the app")
                case .installed(let version, let publishedOn):
                    ValueRow(label: "Version", value: version)
                    ValueRow(label: "Published", value: Format.date(publishedOn))
                    ValueRow(label: "Source", value: "Downloaded update")
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
                // The count comes from the list rather than from a number
                // typed into the sentence. This screen once said a VIN lookup
                // was the only request Odomind could make, and it was wrong
                // by the next release; a sentence that counts itself cannot
                // go stale the same way.
                let requests = outboundRequests
                let howMany = requests.count == 1
                    ? "is one request"
                    : "are " + Self.spelled(requests.count) + " requests"
                Text("""
                Odomind sends nothing anywhere unless you do something that asks it to. There \(howMany) \
                it can make, and each one is listed below with what it carries.
                """)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

                ForEach(requests) { request in
                    outboundRequest(request.title, when: request.when, sends: request.sends)
                }

                Text("""
                Your mileage, your service history, your receipts, your photos and your notes stay on this \
                device. App Store purchases go through Apple, which is the only party that ever sees payment \
                information.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("What leaves this device")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Data sources")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// One request, as data rather than as a call, so the sentence above can
    /// count them.
    struct OutboundRequest: Identifiable {
        var id: String { title }
        var title: String
        var when: String
        var sends: String
    }

    /// Every request Odomind can make, in one place.
    ///
    /// Listed rather than summarised because a summary is where an absolute
    /// creeps in: this screen used to say a VIN lookup was the only request
    /// Odomind could make, and by Build 2 that was no longer true. Build 3
    /// added two more — engine options and photographs — and this is the list
    /// that has to grow with them.
    private var outboundRequests: [OutboundRequest] {
        let identity = model.identificationProvider.contactedHost
        return [
            OutboundRequest(
                title: "Vehicle model lookup",
                when: "You type a year and make into the search field",
                sends: "The year and the make, to \(identity)"
            ),
            OutboundRequest(
                title: "VIN decode",
                when: "You ask for one, after a disclosure naming where it goes",
                sends: "The VIN, to \(identity)"
            ),
            OutboundRequest(
                title: "Which engines this model was sold with",
                when: "You choose a vehicle, on the step that asks which one is yours",
                sends: "The year, the make and the model, to www.fueleconomy.gov"
            ),
            OutboundRequest(
                title: "A photograph of a car like yours",
                when: "A vehicle is shown and Odomind has no picture for it yet",
                sends: "The year, make, model and body style, to commons.wikimedia.org"
            ),
            OutboundRequest(
                title: "Nearby parts shops",
                when: "You tap Near me, or type a postal code",
                sends: "A coarse location or the postal code, to Apple's map search"
            ),
            OutboundRequest(
                title: "Opening a retailer",
                when: "You tap a retailer",
                sends: "Nothing from Odomind — your browser opens their own search for the year, make, model and part"
            ),
            OutboundRequest(
                title: "Maintenance catalog update",
                when: "You tap Check now, or turn on automatic checks",
                sends: "Nothing about you or your vehicle"
            ),
        ]
    }

    /// Small numbers read better as words in a sentence.
    static func spelled(_ count: Int) -> String {
        let words = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        guard count >= 0, count < words.count else { return String(count) }
        return words[count]
    }

    /// One outbound request, named with what triggers it and what it carries.
    ///
    /// Listed rather than summarised because a summary is where an absolute
    /// creeps in: this screen used to say a VIN lookup was the only request
    /// Odomind could make, and by Build 2 that was no longer true.
    @ViewBuilder
    private func outboundRequest(_ title: String, when: String, sends: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.callout.weight(.medium))
            Text(when)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(sends)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
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
                advertising SDK. Your service history, your mileage, your receipts, your photos and your notes \
                are never uploaded.
                """)
                .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Text("""
                Every one of them is started by something you did, and none of them carries your history or your \
                identity. Data sources lists each one with exactly what it sends.
                """)
                .fixedSize(horizontal: false, vertical: true)

                Text("""
                Looking up a vehicle sends the year and make, or the VIN if you ask for a VIN decode, to \
                \(model.identificationProvider.contactedHost) — the U.S. National Highway Traffic Safety \
                Administration's public vehicle catalog. Odomind asks before the first lookup and you can always \
                add a vehicle by hand instead. Finding nearby parts shops sends a coarse location, or the postal \
                code you type, to Apple's map search. Checking for a maintenance catalog update sends nothing \
                about you or your vehicles.
                """)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

                Text("""
                Choosing a vehicle sends its year, make and model to www.fueleconomy.gov, the US Department of \
                Energy and EPA's public database, to ask which engines and drivetrains it was sold with. \
                Showing a photograph sends the year, make, model and body style to commons.wikimedia.org. \
                Neither carries your VIN, your mileage or anything about you.
                """)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

                Text("""
                Tapping a retailer opens their own search in your browser, for the year, make, model and part. \
                Odomind sends them nothing itself, and never your VIN, your mileage or your service history.
                """)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("The requests Odomind can make")
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
                Every permission is asked for at the moment it is needed, never at launch. Notifications when you \
                turn a reminder on. Camera when you scan a VIN. Location only if you ask for parts shops near \
                you, and you can type a postal code instead.
                """)
                .fixedSize(horizontal: false, vertical: true)

                Text("""
                Adding a single item to Apple Calendar asks for nothing at all: the system's own event editor \
                runs outside Odomind's process. Adding several at once does need calendar access, and Odomind \
                asks for the write-only kind — enough to add the items you reviewed, not enough to read what is \
                already in your calendar.
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
