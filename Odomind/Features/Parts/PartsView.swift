import SwiftUI
import UIKit
import OdomindCore

/// Parts: what this vehicle takes, where to look, and what Odomind will not
/// claim about either.
///
/// Opened from a job (with that job's specifications already filled in) or on
/// its own from Home. Everything here is a link into somebody else's search.
/// Odomind holds no prices and no stock, and says so once rather than in three
/// places.
struct PartsView: View {
    @Environment(AppModel.self) private var model

    /// What this screen was opened for: the job, the typed query, the
    /// category. Build 2 took only the job id, so a search typed on Home
    /// arrived here as nothing at all.
    let destination: PartsDestination

    /// Kept for the call sites that only ever had a job.
    var planItemID: UUID? { destination.planItemID }

    @State private var partText = ""
    @State private var place = ""
    @State private var finder = NearbyStoreFinder()
    @State private var copied: String?
    @State private var didSeedQuery = false

    var body: some View {
        Group {
            if let vehicle = model.selectedVehicle {
                content(for: vehicle)
            } else {
                NoVehicleView()
            }
        }
        .task {
            // Once: re-seeding on every appearance would undo the owner's own
            // edits when they come back from a retailer.
            guard !didSeedQuery else { return }
            didSeedQuery = true
            if let query = destination.query, !query.isEmpty {
                partText = query
            } else if let category = destination.category, !category.isEmpty {
                partText = category
            }
        }
        .navigationTitle("Parts")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: prefill)
    }

    @ViewBuilder
    private func content(for vehicle: Vehicle) -> some View {
        List {
            Section {
                TextField("What do you need?", text: $partText)
                    .accessibilityIdentifier("parts.query")
                ValueRow(label: "Vehicle", value: vehicle.identity.displayName)
            } header: {
                Text("Search")
            } footer: {
                Text(PartsQueryBuilder.fitmentCaveat)
            }

            specificationsSection(for: vehicle)

            Section {
                ForEach(Retailer.all) { retailer in
                    RetailerRow(
                        retailer: retailer,
                        query: PartsQueryBuilder.query(for: vehicle, part: partText)
                    ) { text in
                        UIPasteboard.general.string = text
                        copied = text
                    }
                }
            } header: {
                Text("Shop online")
            } footer: {
                Text("Odomind opens the retailer's own search in your browser. It does not hold prices or stock, and it never sends your VIN, your mileage or your service history to a retailer.")
            }

            nearbySection

            if let copied {
                Section {
                    QuietNote(text: "Copied “\(copied)”. Paste it into the retailer's search.", symbolName: "doc.on.doc")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    /// The specifications that actually matter for what is being bought.
    @ViewBuilder
    private func specificationsSection(for vehicle: Vehicle) -> some View {
        let kinds = relevantSpecificationKinds
        if !kinds.isEmpty {
            let resolved = model.resolvedSpecifications(for: vehicle)
            Section {
                ForEach(kinds, id: \.self) { kind in
                    if let match = resolved.first(where: { $0.kind == kind }) {
                        let value = match.active.value.displayString
                        Button {
                            UIPasteboard.general.string = value
                            copied = value
                        } label: {
                            ValueRow(
                                label: kind.displayName,
                                value: value,
                                secondary: "Tap to copy"
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("parts.spec.\(kind.rawValue)")
                    } else {
                        UnavailableValueRow(label: kind.displayName, explanation: kind.sourceHint)
                    }
                }
            } header: {
                Text("What this vehicle takes")
            } footer: {
                Text("Odomind shows a value only when it has one it can stand behind. Anything missing you can add against this vehicle and it will be used everywhere.")
            }
        }
    }

    @ViewBuilder
    private var nearbySection: some View {
        Section {
            HStack {
                TextField("Postal code or town", text: $place)
                    .accessibilityIdentifier("parts.place")
                Button("Search") {
                    finder.search(term: "auto parts store", place: place)
                }
                .disabled(place.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("parts.searchPlace")
            }

            Button {
                finder.searchNearMe(term: "auto parts store")
            } label: {
                Label("Near me", systemImage: "location")
            }
            .accessibilityIdentifier("parts.nearMe")

            switch finder.state {
            case .idle:
                EmptyView()
            case .searching:
                HStack { ProgressView(); Text("Searching…").foregroundStyle(Theme.Palette.secondaryText) }
            case .locationDenied:
                VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                    Text("Odomind does not have your location.")
                        .font(.subheadline)
                    Text("You can type a postal code above instead — Odomind never needs your location to track maintenance.")
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.secondaryText)
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        Link("Open Odomind's settings", destination: url)
                    }
                }
            case .failed(let message):
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.secondaryText)
            case .results(let stores):
                ForEach(stores) { store in
                    NearbyStoreRow(store: store)
                }
            }
        } header: {
            Text("Nearby")
        } footer: {
            Text("These are businesses a map search returned. Odomind has no way to know what any of them has in stock or what they charge.")
        }
    }

    /// Specifications worth showing, driven by the job when there is one.
    private var relevantSpecificationKinds: [SpecificationKind] {
        if let planItemID, let item = model.planItem(id: planItemID) {
            return item.relatedSpecifications
        }
        return [.engineOilViscosity, .engineOilCapacityWithFilter, .tireSizeFront, .batteryGroupSize]
    }

    private func prefill() {
        guard partText.isEmpty, let planItemID, let item = model.planItem(id: planItemID) else { return }
        partText = item.title
    }
}

private struct RetailerRow: View {
    let retailer: Retailer
    let query: String
    let copy: (String) -> Void

    var body: some View {
        if retailer.acceptsPrefilledSearch, let url = retailer.url(for: query) {
            Link(destination: url) {
                LabeledContent {
                    Image(systemName: "arrow.up.forward.app")
                        .foregroundStyle(Theme.Palette.secondaryText)
                } label: {
                    Text(retailer.name)
                }
            }
            .accessibilityIdentifier("parts.retailer.\(retailer.id)")
            .accessibilityHint(Text("Opens \(retailer.name) with this search"))
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                if let url = retailer.url(for: "") {
                    Link(destination: url) {
                        LabeledContent {
                            Image(systemName: "arrow.up.forward.app")
                                .foregroundStyle(Theme.Palette.secondaryText)
                        } label: {
                            Text(retailer.name)
                        }
                    }
                }
                // Honest about the limitation rather than shipping a link that
                // lands on an empty search and looks broken.
                Text("This site picks the vehicle in its own selector, so Odomind cannot fill the search in for you.")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
                Button("Copy “\(query)”") { copy(query) }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.Palette.accent)
            }
            .accessibilityIdentifier("parts.retailer.\(retailer.id)")
        }
    }
}

private struct NearbyStoreRow: View {
    let store: NearbyStore

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            Text(store.name)
                .foregroundStyle(Theme.Palette.primaryText)
            if let address = store.address {
                Text(address)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
            HStack(spacing: Theme.Spacing.large) {
                if let distance = store.distance {
                    Text(Format.distanceAway(metres: distance))
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
                if let directions = store.directionsURL {
                    Link("Directions", destination: directions)
                        .font(.caption.weight(.medium))
                }
                if let website = store.website {
                    Link("Website", destination: website)
                        .font(.caption.weight(.medium))
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }
}
