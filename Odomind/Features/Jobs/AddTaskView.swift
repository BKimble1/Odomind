import SwiftUI
import OdomindCore

/// The searchable catalog of tasks this vehicle can take.
///
/// Tasks the vehicle's configuration rules out never appear. Tasks that depend
/// on something unconfirmed appear with the question attached, so the owner is
/// asked rather than quietly given or denied a service.
struct AddTaskView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var showAdvanced = false
    @State private var addedIDs: Set<String> = []

    private var vehicle: Vehicle? { model.dashboardVehicle }

    var body: some View {
        Group {
            if let vehicle {
                list(for: vehicle)
            } else {
                NoVehicleView()
            }
        }
        .navigationTitle("Add a task")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search the catalog")
    }

    @ViewBuilder
    private func list(for vehicle: Vehicle) -> some View {
        let available = model.availableSuggestions(for: vehicle, includeAdvanced: true)
        let filtered = available.filter { suggestion in
            (showAdvanced || !suggestion.definition.isAdvanced)
                && suggestion.definition.matches(query: searchText)
        }

        List {
            Section {
                Toggle("Show advanced and less common tasks", isOn: $showAdvanced)
                    .accessibilityIdentifier("addTask.showAdvanced")
            } footer: {
                Text("Advanced tasks include differential and transfer-case service, timing belts, seasonal work and anything your manual lists that Odomind does not recommend by default.")
            }

            if filtered.isEmpty {
                Section {
                    if available.isEmpty {
                        ContentUnavailableView(
                            "Everything is already tracked",
                            systemImage: "checkmark.circle",
                            description: Text("You can still create a custom task for anything the catalog does not cover.")
                        )
                    } else {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
            }

            ForEach(byCategory(filtered)) { group in
                Section {
                    ForEach(group.items) { suggestion in
                        SuggestionRow(
                            suggestion: suggestion,
                            isAdded: addedIDs.contains(suggestion.definition.id)
                        ) {
                            if model.addTask(suggestion, to: vehicle) != nil {
                                addedIDs.insert(suggestion.definition.id)
                            }
                        }
                    }
                } header: {
                    Label(group.category.displayName, systemImage: group.category.symbolName)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(LuminousField(strength: 0.5))
    }

    private func byCategory(_ suggestions: [SuggestedTask]) -> [SuggestionCategoryGroup] {
        var buckets: [MaintenanceCategory: [SuggestedTask]] = [:]
        for suggestion in suggestions {
            buckets[suggestion.definition.category, default: []].append(suggestion)
        }
        return MaintenanceCategory.allCases.compactMap { category in
            guard let items = buckets[category], !items.isEmpty else { return nil }
            return SuggestionCategoryGroup(
                category: category,
                items: items.sorted { $0.definition.title < $1.definition.title }
            )
        }
    }
}

/// Catalog tasks grouped under one category heading.
struct SuggestionCategoryGroup: Identifiable {
    var id: MaintenanceCategory { category }
    let category: MaintenanceCategory
    let items: [SuggestedTask]
}

struct SuggestionRow: View {
    let suggestion: SuggestedTask
    let isAdded: Bool
    let add: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            HStack(alignment: .firstTextBaseline) {
                Text(suggestion.definition.title)
                    .font(.body)
                Spacer()
                if isAdded {
                    Label("Added", systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.green)
                        .accessibilityLabel(Text("Added"))
                } else {
                    Button("Add", action: add)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier("addTask.add.\(suggestion.definition.id)")
                }
            }

            Text(suggestion.definition.purpose)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let rule = suggestion.rule {
                Text(rule.summary)
                    .font(.caption.weight(.medium))
            } else {
                Text("No published interval — you supply it from your manual")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            ProvenanceLabel(provenance: suggestion.provenance, sourceName: suggestion.sourceNote)

            if case .needsConfirmation(_, let reason) = suggestion.applicability {
                InlineNotice(kind: .caution, message: reason)
            }

            if let safetyNote = suggestion.definition.safetyNote {
                InlineNotice(kind: .safety, message: safetyNote)
            }
        }
        .padding(.vertical, 2)
    }
}
