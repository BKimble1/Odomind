import SwiftUI
import OdomindCore

/// Schedule changes a catalog update wants to make, waiting for a decision.
///
/// Nothing here has been applied. The schedules currently in force are the ones
/// that were in force before the update, which is the whole point of showing
/// this screen at all.
struct ProposalsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            if model.pendingProposals.isEmpty {
                ContentUnavailableView(
                    "Nothing to review",
                    systemImage: "checkmark.circle",
                    description: Text("Odomind will show proposed schedule changes here when a new version of the app ships an updated catalog.")
                )
            } else {
                Section {
                    InlineNotice(
                        message: "Your current schedules are still running. Nothing changes until you accept it here."
                    )
                }
                ForEach(model.pendingProposals) { item in
                    Section {
                        if let proposal = item.pendingProposal {
                            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                                Text(item.title)
                                    .font(.headline)
                                ValueRow(label: "Now", value: item.effectiveRule?.summary ?? "No schedule")
                                ValueRow(label: "Proposed", value: proposal.proposedRule.summary)
                                ProvenanceLabel(provenance: proposal.proposedProvenance)
                                if item.isOwnerOverridden {
                                    InlineNotice(
                                        kind: .caution,
                                        message: "You set this schedule yourself. Accepting replaces it with the published one."
                                    )
                                }
                            }
                            .padding(.vertical, 2)

                            Button("Use the proposed schedule") {
                                model.acceptProposal(planItemID: item.id)
                            }
                            Button("Keep mine") {
                                model.dismissProposal(planItemID: item.id)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Schedule changes")
        .navigationBarTitleDisplayMode(.inline)
    }
}
