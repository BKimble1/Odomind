import SwiftUI
import OdomindCore

struct MaintenanceView: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationRouter.self) private var router

    @State private var searchText = ""

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.maintenancePath) {
            Group {
                if let vehicle = model.selectedVehicle {
                    list(for: vehicle)
                } else {
                    NoVehicleView()
                }
            }
            .navigationTitle("Maintenance")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    VehiclePickerBar()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            router.maintenancePath.append(.addTask)
                        } label: {
                            Label("Add from catalog", systemImage: "text.book.closed")
                        }
                        .accessibilityIdentifier("maintenance.addFromCatalog")
                        Button {
                            router.maintenancePath.append(.customTask)
                        } label: {
                            Label("Create custom task", systemImage: "square.and.pencil")
                        }
                        .accessibilityIdentifier("maintenance.createCustomTask")
                        if model.openProposalCount > 0 {
                            Divider()
                            Button {
                                router.maintenancePath.append(.proposals)
                            } label: {
                                Label("Review schedule changes (\(model.openProposalCount))", systemImage: "bell.badge")
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                            .accessibilityLabel(Text("Add a maintenance task"))
                            .accessibilityIdentifier("maintenance.addMenu")
                    }
                }
            }
            .navigationDestination(for: MaintenanceRoute.self) { route in
                switch route {
                case .task(let id):
                    TaskDetailView(planItemID: id)
                case .addTask:
                    AddTaskView()
                case .customTask:
                    CustomTaskEditor()
                case .proposals:
                    ProposalsView()
                }
            }
        }
    }

    @ViewBuilder
    private func list(for vehicle: Vehicle) -> some View {
        let evaluations = model.evaluations(for: vehicle.id)
        let filtered = filter(evaluations)

        Group {
            if evaluations.isEmpty {
                ContentUnavailableView {
                    Label("No tasks tracked yet", systemImage: "wrench.and.screwdriver")
                } description: {
                    Text("Pick the maintenance you care about. You can add more at any time, and remove anything you do not want to see.")
                } actions: {
                    Button("Add from catalog") { router.maintenancePath.append(.addTask) }
                        .buttonStyle(.borderedProminent)
                }
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List {
                    ForEach(byCategory(filtered)) { group in
                        Section {
                            ForEach(group.items) { evaluation in
                                NavigationLink(value: MaintenanceRoute.task(evaluation.planItemID)) {
                                    MaintenanceRow(evaluation: evaluation)
                                }
                            }
                        } header: {
                            Label(group.category.displayName, systemImage: group.category.symbolName)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .searchable(text: $searchText, prompt: "Search your tasks")
    }

    private func filter(_ evaluations: [ScheduleEvaluation]) -> [ScheduleEvaluation] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return evaluations }
        return evaluations.filter { evaluation in
            if evaluation.title.lowercased().contains(needle) { return true }
            guard let item = model.planItem(id: evaluation.planItemID) else { return false }
            return item.purpose.lowercased().contains(needle)
                || item.category.displayName.lowercased().contains(needle)
        }
    }

    private func byCategory(_ evaluations: [ScheduleEvaluation]) -> [EvaluationCategoryGroup] {
        var buckets: [MaintenanceCategory: [ScheduleEvaluation]] = [:]
        for evaluation in evaluations {
            let category = model.planItem(id: evaluation.planItemID)?.category ?? .other
            buckets[category, default: []].append(evaluation)
        }
        return MaintenanceCategory.allCases.compactMap { category in
            guard let items = buckets[category], !items.isEmpty else { return nil }
            return EvaluationCategoryGroup(category: category, items: items)
        }
    }
}

/// Tracked tasks grouped under one category heading.
struct EvaluationCategoryGroup: Identifiable {
    var id: MaintenanceCategory { category }
    let category: MaintenanceCategory
    let items: [ScheduleEvaluation]
}

struct MaintenanceRow: View {
    @Environment(AppModel.self) private var model
    let evaluation: ScheduleEvaluation

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            HStack(alignment: .firstTextBaseline) {
                Text(evaluation.title)
                Spacer()
                DueBadge(state: evaluation.state)
            }
            Text(DueSummary.text(for: evaluation, calendar: model.calendar, now: model.clock.now))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let item = model.planItem(id: evaluation.planItemID) {
                HStack(spacing: Theme.Spacing.small) {
                    if item.isOwnerOverridden {
                        Label("Your schedule", systemImage: "person.crop.circle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if item.hasPendingProposal {
                        Label("Change to review", systemImage: "bell.badge")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("maintenance.task.\(evaluation.definitionID)")
    }
}
