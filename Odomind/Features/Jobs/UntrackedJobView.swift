import SwiftUI
import OdomindCore

/// A job the catalog knows about but this vehicle is not tracking.
///
/// The brief's wording: "Browsing an untracked job should open that job's
/// details directly, not a generic add-task form that loses the selection."
/// Build 2 did exactly that — searching "brake fluid" on Home and tapping the
/// result pushed the whole catalog library with the query thrown away, so the
/// owner arrived at a list of ninety jobs and had to find theirs again.
///
/// This is the same screen a tracked job gets, minus the parts of it that need
/// a history: what the job is, what it is for, what schedule Odomind would put
/// it on and where that schedule came from, what specifications it needs, and
/// one action that starts tracking it. Adding it replaces this screen with the
/// real one rather than stacking a second copy behind it.
struct UntrackedJobView: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationRouter.self) private var router

    let definitionID: String

    private var vehicle: Vehicle? { model.dashboardVehicle }

    /// The suggestion as it stands for *this* vehicle, so the schedule and the
    /// applicability shown are the ones that would actually be used.
    private var suggestion: SuggestedTask? {
        guard let vehicle else { return nil }
        return model.allSuggestions(for: vehicle).first { $0.definition.id == definitionID }
    }

    /// Already tracked — which happens if the owner adds it, leaves and comes
    /// back through history.
    private var existingPlanItemID: UUID? {
        guard let vehicle else { return nil }
        return model.snapshot.planItems(for: vehicle.id).first { $0.definitionID == definitionID }?.id
    }

    var body: some View {
        Group {
            if let vehicle, let suggestion {
                content(suggestion: suggestion, vehicle: vehicle)
            } else if vehicle == nil {
                NoVehicleView()
            } else {
                ContentUnavailableView(
                    "Job not found",
                    systemImage: "questionmark.folder",
                    description: Text("Odomind's catalog has no job with this identifier.")
                )
            }
        }
        .navigationTitle(suggestion?.definition.title ?? "Job")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(suggestion: SuggestedTask, vehicle: Vehicle) -> some View {
        let definition = suggestion.definition

        List {
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                    Text("Not tracked for \(vehicle.displayName)")
                        .font(.headline)
                    Text("Odomind is not watching this job yet, so it has no due date for it. Adding it starts that.")
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, Theme.Spacing.tight)

                if let existingPlanItemID {
                    Button {
                        router.replaceTop(with: JobRoute.task(existingPlanItemID))
                    } label: {
                        Label("Open this job", systemImage: "arrow.forward")
                            .font(.body.weight(.medium))
                    }
                    .accessibilityIdentifier("untracked.open")
                } else {
                    Button {
                        guard let planItemID = model.addTask(suggestion, to: vehicle) else { return }
                        // Replaces rather than pushes: going back should land
                        // on the search that got here, not on a screen saying
                        // the job is untracked when it now is.
                        router.replaceTop(with: JobRoute.task(planItemID))
                    } label: {
                        Label("Track this job", systemImage: "plus.circle")
                            .font(.body.weight(.medium))
                    }
                    .accessibilityIdentifier("untracked.track")
                }
            } header: {
                Text("Status")
            }

            if !definition.purpose.isEmpty {
                Section("What this is for") {
                    Text(definition.purpose)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                if let rule = suggestion.rule {
                    ValueRow(label: "Interval", value: rule.summary)
                } else {
                    UnavailableValueRow(
                        label: "Interval",
                        explanation: "Odomind has no published interval for this job, so you would set one yourself."
                    )
                }
                ValueRow(label: "Category", value: definition.category.displayName)
            } header: {
                Text("Schedule")
            } footer: {
                // The same provenance line a tracked job carries. A general
                // template is not a manufacturer schedule and never says it is.
                Text(scheduleSource(suggestion))
            }

            if !definition.relatedSpecifications.isEmpty {
                Section {
                    ForEach(definition.relatedSpecifications, id: \.self) { kind in
                        if let match = model.resolvedSpecifications(for: vehicle).first(where: { $0.kind == kind }) {
                            ValueRow(label: kind.displayName, value: match.active.value.displayString)
                        } else {
                            UnavailableValueRow(label: kind.displayName, explanation: kind.sourceHint)
                        }
                    }
                    Button {
                        router.push(
                            JobRoute.parts(
                                PartsDestination(
                                    query: definition.title,
                                    category: definition.category.displayName
                                )
                            )
                        )
                    } label: {
                        Label("Find the parts", systemImage: "bag")
                    }
                    .accessibilityIdentifier("untracked.parts")
                } header: {
                    Text("What this job needs")
                }
            }

            if let safetyNote = definition.safetyNote {
                Section {
                    InlineNotice(kind: .caution, message: safetyNote)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func scheduleSource(_ suggestion: SuggestedTask) -> String {
        if let note = suggestion.sourceNote {
            return "From \(note)."
        }
        return "A general guideline, not a schedule published for this vehicle. You can change it once the job is tracked."
    }
}
