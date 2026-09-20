import SwiftUI
import OdomindCore

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationRouter.self) private var router

    @State private var searchText = ""
    @State private var scope: Scope = .thisVehicle
    @State private var showingLogService = false

    enum Scope: String, CaseIterable, Identifiable {
        case thisVehicle
        case allVehicles
        var id: String { rawValue }
        var title: String {
            switch self {
            case .thisVehicle: return "This vehicle"
            case .allVehicles: return "All vehicles"
            }
        }
    }

    var body: some View {
        @Bindable var router = router

        NavigationStack(path: $router.historyPath) {
            Group {
                if model.selectedVehicle == nil {
                    NoVehicleView()
                } else {
                    content
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    VehiclePickerBar()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingLogService = true
                        } label: {
                            Label("Log a service", systemImage: "plus")
                        }
                        Button {
                            router.historyPath.append(.export)
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .accessibilityLabel(Text("History options"))
                    }
                }
            }
            .navigationDestination(for: HistoryRoute.self) { route in
                switch route {
                case .record(let id):
                    ServiceRecordDetailView(recordID: id)
                case .export:
                    ExportView()
                }
            }
            .sheet(isPresented: $showingLogService) {
                if let vehicle = model.selectedVehicle {
                    LogServiceView(vehicle: vehicle)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        let records = filteredRecords
        let spending = model.spending(for: records)

        List {
            if model.snapshot.vehicles.count > 1 {
                Section {
                    Picker("Scope", selection: $scope) {
                        ForEach(Scope.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            if records.isEmpty {
                Section {
                    if searchText.isEmpty {
                        ContentUnavailableView {
                            Label("No service recorded yet", systemImage: "clock.arrow.circlepath")
                        } description: {
                            Text("Log work as you have it done, and Odomind keeps the record, the cost and the receipt.")
                        } actions: {
                            Button("Log a service") { showingLogService = true }
                                .buttonStyle(.borderedProminent)
                        }
                    } else {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
            } else {
                ForEach(groupedByYear(records)) { group in
                    Section {
                        ForEach(group.records) { record in
                            NavigationLink(value: HistoryRoute.record(record.id)) {
                                ServiceRecordRow(record: record, showVehicle: scope == .allVehicles)
                            }
                        }
                    } header: {
                        Text(String(group.year))
                    }
                }

                Section {
                    ValueRow(label: "Records", value: "\(records.count)")
                    ValueRow(label: "Total spent", value: Format.moneyTotal(spending))
                    if spending.isMixedCurrency {
                        InlineNotice(
                            message: "These records use more than one currency, so Odomind shows each currency separately rather than adding them together."
                        )
                    }
                } header: {
                    Text("Summary")
                } footer: {
                    Text("Only visits with a recorded cost are counted.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Search notes, tasks and shops")
    }

    private var filteredRecords: [ServiceRecord] {
        let base: [ServiceRecord]
        switch scope {
        case .thisVehicle:
            base = model.selectedVehicle.map { model.serviceRecords(for: $0.id) } ?? []
        case .allVehicles:
            base = model.snapshot.serviceRecords.sorted { $0.performedOn > $1.performedOn }
        }

        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return base }
        return base.filter { record in
            record.items.contains { $0.title.lowercased().contains(needle) }
                || (record.notes ?? "").lowercased().contains(needle)
                || record.performer.displayName.lowercased().contains(needle)
        }
    }

    private func groupedByYear(_ records: [ServiceRecord]) -> [ServiceYearGroup] {
        var buckets: [Int: [ServiceRecord]] = [:]
        for record in records {
            let year = model.calendar.component(.year, from: record.performedOn)
            buckets[year, default: []].append(record)
        }
        return buckets.keys.sorted(by: >).map { ServiceYearGroup(year: $0, records: buckets[$0] ?? []) }
    }
}

/// Service records grouped under one year heading.
struct ServiceYearGroup: Identifiable {
    var id: Int { year }
    let year: Int
    let records: [ServiceRecord]
}

struct ServiceRecordRow: View {
    @Environment(AppModel.self) private var model
    let record: ServiceRecord
    var showVehicle: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            HStack(alignment: .firstTextBaseline) {
                Text(record.title)
                    .font(.body)
                Spacer()
                if let cost = record.totalCost {
                    Text(Format.money(cost))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            HStack(spacing: Theme.Spacing.small) {
                Text(Format.date(record.performedOn))
                if let odometer = record.odometer {
                    Text("·")
                    Text(Format.distance(odometer))
                }
                Text("·")
                Text(record.performer.displayName)
                if !record.attachmentIDs.isEmpty {
                    Image(systemName: "paperclip")
                        .accessibilityLabel(Text("\(record.attachmentIDs.count) attachments"))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if showVehicle, let vehicle = model.snapshot.vehicle(id: record.vehicleID) {
                Text(vehicle.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if record.isDemo {
                Text("SAMPLE DATA")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
