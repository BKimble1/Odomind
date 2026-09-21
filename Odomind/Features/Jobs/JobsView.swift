import SwiftUI
import OdomindCore

/// Jobs: the searchable library of maintenance and repair work.
///
/// Two sections rather than one long list — "My plan" is what Odomind is
/// tracking, "All jobs" is everything else it knows about. Build 1 showed one
/// list where nearly every row said "Needs setup" and repeated the same
/// sentence, which read as an administrative backlog rather than a library.
/// Setup state now lives on the job itself, where it can be acted on.
struct JobsView: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationRouter.self) private var router

    @State private var searchText = ""
    @State private var showsAdvanced = false

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.jobsPath) {
            VStack(alignment: .leading, spacing: 0) {
                // Which car this is about, in the content rather than the
                // navigation bar. A toolbar item gets one bar's height and
                // one bar's share of its width, so it cannot wrap and cannot
                // shrink — which is how a screenshot of this screen showed
                // "Sa…" where the vehicle's name should be. Home was moved
                // out for the same reason and this is the same fix.
                if model.selectedVehicle != nil {
                    VehiclePickerBar()
                        .padding(.horizontal, Theme.Spacing.large)
                        .padding(.bottom, Theme.Spacing.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Group {
                    if let vehicle = model.selectedVehicle {
                        list(for: vehicle)
                    } else {
                        NoVehicleView()
                    }
                }
            }
            .navigationTitle("Jobs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            router.jobsPath.append(JobRoute.addTask)
                        } label: {
                            Label("Add from the library", systemImage: "text.book.closed")
                        }
                        .accessibilityIdentifier("jobs.addFromCatalog")
                        Button {
                            router.jobsPath.append(JobRoute.customTask)
                        } label: {
                            Label("Create a custom job", systemImage: "square.and.pencil")
                        }
                        .accessibilityIdentifier("jobs.createCustomTask")
                        Divider()
                        Toggle("Show advanced jobs", isOn: $showsAdvanced)
                        if model.openProposalCount > 0 {
                            Divider()
                            Button {
                                router.jobsPath.append(JobRoute.proposals)
                            } label: {
                                Label("Review schedule changes (\(model.openProposalCount))", systemImage: "bell.badge")
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                            .accessibilityLabel(Text("Add a job"))
                            .accessibilityIdentifier("jobs.addMenu")
                    }
                }
            }
            .odomindDestinations()
            .searchable(text: $searchText, prompt: "Search jobs")
        }
    }

    @ViewBuilder
    private func list(for vehicle: Vehicle) -> some View {
        let results = model.searchJobs(query: searchText, vehicle: vehicle)
        let tracked = results.filter(\.isTracked)
        let untracked = results.filter { !$0.isTracked && (showsAdvanced || !$0.isAdvanced) }

        if tracked.isEmpty && untracked.isEmpty {
            if searchText.isEmpty {
                ContentUnavailableView {
                    Label("No jobs tracked yet", systemImage: "wrench.and.screwdriver")
                } description: {
                    Text("Pick the maintenance you care about. You can add more at any time, and remove anything you do not want to see.")
                } actions: {
                    Button("Add from the library") { router.jobsPath.append(JobRoute.addTask) }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ContentUnavailableView.search(text: searchText)
            }
        } else {
            List {
                if !tracked.isEmpty {
                    Section {
                        ForEach(tracked) { result in
                            if let planItemID = result.planItemID {
                                NavigationLink(value: JobRoute.task(planItemID)) {
                                    TrackedJobRow(result: result)
                                }
                            }
                        }
                    } header: {
                        Text("My plan")
                    }
                }

                if !untracked.isEmpty {
                    Section {
                        ForEach(untracked) { result in
                            Button {
                                router.jobsPath.append(JobRoute.addTask)
                            } label: {
                                LibraryJobRow(result: result)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text(searchText.isEmpty ? "More jobs" : "Not tracked yet")
                    } footer: {
                        Text("Adding a job puts it in your plan. It does not record that the work was done.")
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }
}

/// A job in the owner's plan.
struct TrackedJobRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let result: JobSearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            // Side by side normally; stacked once the text is large enough
            // that they cannot share a line. At an accessibility size the
            // row read "Engine oil / and filter" beside "Over- / due", with
            // both halves hyphenated against each other. Stacked, each gets
            // the full width and neither breaks mid-word.
            if dynamicTypeSize.isAccessibilitySize {
                Text(result.title)
                if let state = result.state { DueBadge(state: state) }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text(result.title)
                    Spacer(minLength: Theme.Spacing.small)
                    if let state = result.state { DueBadge(state: state) }
                }
            }
            if let planItemID = result.planItemID,
               let evaluation = model.evaluation(planItemID: planItemID),
               let detail = DueSummary.compactText(
                   for: evaluation, calendar: model.calendar, now: model.clock.now
               ) {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(
                        evaluation.state == .overdue ? Theme.Colors.overdue : Theme.Palette.secondaryText
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let item = result.planItemID.flatMap({ model.planItem(id: $0) }) {
                HStack(spacing: Theme.Spacing.medium) {
                    if item.isOwnerOverridden {
                        Label("Your schedule", systemImage: "person.crop.circle")
                            .font(.caption2)
                            .foregroundStyle(Theme.Palette.secondaryText)
                    }
                    if item.hasPendingProposal {
                        Label("Change to review", systemImage: "bell.badge")
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.caution)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("jobs.task.\(result.definitionID)")
    }
}

/// A job Odomind knows about but is not tracking.
struct LibraryJobRow: View {
    let result: JobSearchResult

    var body: some View {
        HStack(spacing: Theme.Spacing.medium) {
            Image(systemName: result.category.symbolName)
                .foregroundStyle(Theme.Palette.secondaryText)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .foregroundStyle(Theme.Palette.primaryText)
                Text(result.purpose)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .lineLimit(2)
            }
            Spacer(minLength: Theme.Spacing.small)
            Image(systemName: "plus.circle")
                .foregroundStyle(Theme.Palette.accent)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Adds this job to your plan"))
        .accessibilityIdentifier("jobs.library.\(result.definitionID)")
    }
}
