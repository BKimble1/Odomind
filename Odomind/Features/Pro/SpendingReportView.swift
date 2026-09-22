import SwiftUI
import OdomindCore

/// What has been spent on recorded maintenance, and a dossier worth handing
/// to a buyer.
///
/// Careful wording throughout: this is *recorded maintenance spending*, not
/// cost of ownership. Fuel, insurance, tyres bought without a record and every
/// visit nobody entered are all missing, and a total that called itself
/// "what this car costs you" would be wrong by a wide margin.
struct SpendingReportView: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationRouter.self) private var router

    let vehicleID: UUID

    @State private var showingExport = false

    var body: some View {
        Group {
            if model.isPro {
                report
            } else {
                locked
            }
        }
        .navigationTitle("Spending")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var locked: some View {
        ContentUnavailableView {
            Label("Spending trends are part of Pro", systemImage: "chart.bar.xaxis")
        } description: {
            Text("See what you have spent by job, by month and by vehicle, and produce a service dossier. Everything you have already recorded stays exactly where it is either way.")
        } actions: {
            Button("See what Pro adds") { router.presentPaywall = true }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("spending.openPaywall")
        }
    }

    private var report: some View {
        let records = model.serviceRecords(for: vehicleID, includingDemo: false)
        let byCategory = spendByJob(records)
        let byYear = spendByYear(records)

        return List {
            Section {
                ValueRow(
                    label: "Recorded spending",
                    value: Format.moneyTotal(model.spending(for: records)),
                    secondary: "\(records.count) visit\(records.count == 1 ? "" : "s")"
                )
            } header: {
                Text("Total")
            } footer: {
                // The honest caveat, once, where the number is.
                Text("This is what you have recorded in Odomind. It is not the cost of owning this vehicle: fuel, insurance and anything you did not log are not here.")
            }

            if !byJob(byCategory).isEmpty {
                Section("By job") {
                    ForEach(byJob(byCategory)) { line in
                        ValueRow(label: line.label, value: Format.moneyTotal(line.total))
                    }
                }
            }

            if !byYear.isEmpty {
                Section("By year") {
                    ForEach(byYear) { line in
                        ValueRow(label: line.label, value: Format.moneyTotal(line.total))
                    }
                }
            }

            Section {
                NavigationLink(value: RecordRoute.export) {
                    Label("Service dossier and exports", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("A dated record of every service, with receipts attached if you want them included.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(LuminousField(strength: 0.5))
    }

    private func spendByJob(_ records: [ServiceRecord]) -> [String: [Money]] {
        var buckets: [String: [Money]] = [:]
        for record in records {
            // A visit covering several jobs is attributed to the visit, not
            // split between them: Odomind has no basis for a split and a
            // guessed one would be a fabricated number.
            guard let cost = record.totalCost else { continue }
            let key = record.items.count == 1 ? (record.items.first?.title ?? record.title) : "Multi-job visits"
            buckets[key, default: []].append(cost)
        }
        return buckets
    }

    private func byJob(_ buckets: [String: [Money]]) -> [SpendingLine] {
        buckets
            .map { SpendingLine(label: $0.key, total: MoneyTotal.total(of: $0.value)) }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    private func spendByYear(_ records: [ServiceRecord]) -> [SpendingLine] {
        var buckets: [Int: [Money]] = [:]
        for record in records {
            guard let cost = record.totalCost else { continue }
            let year = model.calendar.component(.year, from: record.performedOn)
            buckets[year, default: []].append(cost)
        }
        return buckets.keys.sorted(by: >).map {
            SpendingLine(label: String($0), total: MoneyTotal.total(of: buckets[$0] ?? []))
        }
    }
}

/// One row of a spending breakdown. A named type rather than a tuple, because
/// `ForEach` needs an identity and Swift has no key path into a tuple element.
struct SpendingLine: Identifiable, Hashable {
    var id: String { label }
    var label: String
    var total: MoneyTotal
}
