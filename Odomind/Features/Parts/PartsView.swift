import CoreLocation
import SwiftUI
import UIKit
import OdomindCore

/// Parts: what this car takes, and where to get it.
///
/// Opened from a job with that job's specifications already filled in, or on
/// its own from the dashboard. Everything here leads into somebody else's
/// search — Odomind holds no prices and no stock, and says so once.
///
/// Two things changed in Build 4. The screen follows the dashboard's car
/// rather than a separate selection, so looking up a part for the car on the
/// dashboard is not a two-step. And the shop list searches from the area
/// already chosen instead of a postal-code field and a "Near me" button that
/// appeared on every visit: where you shop is a standing answer, not a
/// question per screen.
struct PartsView: View {
    @Environment(AppModel.self) private var model

    /// What this screen was opened for: the job, the typed query, the
    /// category. Build 2 took only the job id, so a search typed on Home
    /// arrived here as nothing at all.
    let destination: PartsDestination

    /// Kept for the call sites that only ever had a job.
    var planItemID: UUID? { destination.planItemID }

    @State private var partText = ""
    @State private var finder = NearbyStoreFinder()
    @State private var copied: String?
    @State private var didSeedQuery = false

    var body: some View {
        Group {
            if let vehicle = model.dashboardVehicle {
                content(for: vehicle)
            } else {
                NoVehicleView()
            }
        }
        .navigationTitle("Parts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { ShoppingLocationControl() }
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
            } else if let planItemID, let item = model.planItem(id: planItemID) {
                partText = item.title
            }
        }
        .task {
            // Opening Parts with an area already chosen should show shops,
            // not a prompt to say where you are for the fourth time.
            model.shoppingLocation.resolve()
        }
        // Whenever there is somewhere to search, search it — on open, and
        // again the moment the owner changes area. Nothing to tap.
        .task(id: searchKey) { searchNearby() }
    }

    @ViewBuilder
    private func content(for vehicle: Vehicle) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.large) {
                searchCard(for: vehicle)
                specificationsCard(for: vehicle)
                retailersCard(for: vehicle)
                nearbyCard

                Text("Odomind opens a search. It has no parts catalogue, so check fit on the retailer's site. Your VIN and history are never sent.")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Spacing.tight)
            }
            .padding(Theme.Spacing.large)
            .padding(.bottom, Theme.Spacing.section)
        }
        .background(LuminousField(strength: 0.55))
        .overlay(alignment: .bottom) { copiedNote }
    }

    // MARK: - What you are looking for

    private func searchCard(for vehicle: Vehicle) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            HStack(spacing: Theme.Spacing.medium) {
                IconChip(symbol: "magnifyingglass")
                TextField("What do you need?", text: $partText)
                    .font(.body)
                    .accessibilityIdentifier("parts.query")
            }
            Divider().overlay(Theme.Palette.separator)
            HStack(spacing: Theme.Spacing.small) {
                Image(systemName: "car.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .accessibilityHidden(true)
                Text(vehicle.identity.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.Palette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Searching for \(vehicle.identity.displayName)"))
        }
        .padding(Theme.Spacing.large - 1)
        .cardSurface()
    }

    // MARK: - What this vehicle takes

    /// The specification worth putting in a retailer search.
    ///
    /// Build 2 built the query from year, make, model and the typed part and
    /// stopped there — even when the owner had already recorded the exact
    /// value that identifies the part, like a battery group size or a tyre
    /// size. Searching "2010 Jeep Wrangler battery" when "group 34" is known
    /// is throwing away the one detail that makes the result right.
    private func specificationForQuery(_ vehicle: Vehicle) -> (label: String, value: String)? {
        let kinds = relevantSpecificationKinds
        guard !kinds.isEmpty else { return nil }
        let resolved = model.resolvedSpecifications(for: vehicle)
        for kind in kinds {
            guard let match = resolved.first(where: { $0.kind == kind }) else { continue }
            let value = match.active.value.displayString
            guard !value.isEmpty else { continue }
            return (kind.displayName, value)
        }
        return nil
    }

    private func retailerQuery(for vehicle: Vehicle) -> String {
        PartsQueryBuilder.query(
            for: vehicle,
            part: partText,
            specification: specificationForQuery(vehicle)?.value
        )
    }

    /// The specifications that actually matter for what is being bought.
    @ViewBuilder
    private func specificationsCard(for vehicle: Vehicle) -> some View {
        let kinds = relevantSpecificationKinds
        if !kinds.isEmpty {
            let resolved = model.resolvedSpecifications(for: vehicle)
            PanelCard(symbol: "list.bullet.rectangle", title: "What it takes") {
                VStack(spacing: 0) {
                    ForEach(kinds, id: \.self) { kind in
                        if let match = resolved.first(where: { $0.kind == kind }) {
                            let value = match.active.value.displayString
                            Button {
                                UIPasteboard.general.string = value
                                copied = value
                            } label: {
                                SpecRow(label: kind.displayName, value: value)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("parts.spec.\(kind.rawValue)")
                        } else {
                            // Not a dead row. Odomind has no licensed
                            // specification data, so for most vehicles this is
                            // the normal case — and the owner's manual on the
                            // passenger seat has the answer. One tap to record
                            // it, and it is used in every search from then on.
                            NavigationLink(value: VehicleRoute.specifications(vehicle.id)) {
                                SpecRow(label: kind.displayName, value: nil, hint: kind.sourceHint)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("parts.addSpec.\(kind.rawValue)")
                        }
                    }
                }
                .padding(.top, Theme.Spacing.small)
            }
        }
    }

    // MARK: - Where to buy

    private func retailersCard(for vehicle: Vehicle) -> some View {
        let query = retailerQuery(for: vehicle)
        return PanelCard(symbol: "bag", title: "Buy online") {
            VStack(spacing: 0) {
                ForEach(Retailer.all) { retailer in
                    RetailerRow(retailer: retailer, query: query) { text in
                        UIPasteboard.general.string = text
                        copied = text
                    }
                }
            }
            .padding(.top, Theme.Spacing.small)
        }
    }

    // MARK: - Shops

    /// Changes whenever there is a different place to search from, or a
    /// different thing to search for. Used as a `task(id:)` key so the list
    /// refreshes itself instead of waiting to be asked.
    private var searchKey: String {
        guard case .ready(let latitude, let longitude, _) = model.shoppingLocation.resolution else {
            return "none"
        }
        return "\(latitude),\(longitude)|\(mapTerm)"
    }

    /// A tyre shop for tyres, a parts shop for everything else. The retailer
    /// entries already carry this, so it is read from the best match rather
    /// than kept in a second list here.
    private var mapTerm: String {
        let kinds = relevantSpecificationKinds
        if kinds.contains(where: { $0.group == .tiresAndWheels }) { return "tire shop" }
        return "auto parts store"
    }

    private func searchNearby() {
        guard let coordinate = model.shoppingLocation.resolution.coordinate else { return }
        finder.search(term: mapTerm, near: coordinate)
    }

    @ViewBuilder
    private var nearbyCard: some View {
        PanelCard(symbol: "mappin.and.ellipse", title: nearbyTitle) {
            VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                if !hasArea {
                    // The one tap left, and it is made once rather than on
                    // every visit. A refused location is the same case: there
                    // is nowhere to search, and typing a town fixes it.
                    if model.shoppingLocation.resolution == .denied {
                        Text("Location is off. Pick a town instead.")
                            .font(.footnote)
                            .foregroundStyle(Theme.Palette.secondaryText)
                    }
                    ShoppingLocationControl(style: .prominent)
                        .padding(.top, Theme.Spacing.tight)
                } else {
                    switch finder.state {
                    case .idle:
                        EmptyView()
                    case .searching:
                        HStack(spacing: Theme.Spacing.small) {
                            ProgressView().controlSize(.small)
                            Text("Looking…").foregroundStyle(Theme.Palette.secondaryText)
                        }
                        .font(.footnote)
                    case .failed(let message):
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(Theme.Palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    case .results(let stores):
                        VStack(spacing: 0) {
                            ForEach(stores.prefix(5)) { store in
                                NearbyStoreRow(store: store)
                            }
                        }
                    }
                }
            }
            .padding(.top, Theme.Spacing.small)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var nearbyTitle: String {
        if let label = model.shoppingLocation.resolution.label { return "Near \(label)" }
        return "Nearby"
    }

    private var hasArea: Bool { model.shoppingLocation.resolution.coordinate != nil }

    @ViewBuilder
    private var copiedNote: some View {
        if let copied {
            Text("Copied “\(copied)”")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.Palette.onAccent)
                .padding(.horizontal, Theme.Spacing.large)
                .padding(.vertical, Theme.Spacing.medium)
                .background(Theme.Palette.accent, in: Capsule())
                .padding(.bottom, Theme.Spacing.section)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityIdentifier("parts.copied")
        }
    }

    /// Specifications worth showing, driven by what is actually being looked
    /// for.
    ///
    /// Three sources, in order of how much they know. A job says which
    /// specifications it needs, and that is the best answer there is. Failing
    /// that, what the owner typed is read for a part category — so "cabin air
    /// filter" shows the cabin filter and not a tyre size. Only when neither
    /// says anything does the general set appear.
    ///
    /// Build 2 had the last of those three and nothing else, which is why
    /// looking up a filter put a battery group size on the screen.
    private var relevantSpecificationKinds: [SpecificationKind] {
        if let planItemID, let item = model.planItem(id: planItemID), !item.relatedSpecifications.isEmpty {
            return item.relatedSpecifications
        }
        return PartCategoryMatch.specifications(for: partText, categoryHint: destination.category)
    }
}

/// One specification: what it is, and the value to copy.
private struct SpecRow: View {
    let label: String
    let value: String?
    var hint: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.medium) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.secondaryText)
            Spacer(minLength: Theme.Spacing.small)
            if let value {
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.primaryText)
                    .multilineTextAlignment(.trailing)
                Image(systemName: "doc.on.doc")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.accent)
                    .accessibilityHidden(true)
            } else {
                // Never a guess, and never a blank that reads as zero.
                Text("Add")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.Palette.accent)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, Theme.Spacing.medium - 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text(value == nil ? "Odomind has no value for this. \(hint ?? "")" : "Copies this value"))
    }
}

private struct RetailerRow: View {
    let retailer: Retailer
    let query: String
    let copy: (String) -> Void

    var body: some View {
        if retailer.acceptsPrefilledSearch, let url = retailer.url(for: query) {
            Link(destination: url) {
                row(symbol: "arrow.up.forward")
            }
            .accessibilityIdentifier("parts.retailer.\(retailer.id)")
            .accessibilityHint(Text("Opens \(retailer.name) with this search"))
        } else {
            // Honest about the limitation rather than shipping a link that
            // lands on an empty search and looks broken.
            Button {
                copy(query)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    row(symbol: "doc.on.doc")
                    Text("Picks the car in its own selector — copy and paste")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.secondaryText)
                        .padding(.bottom, Theme.Spacing.small)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("parts.retailer.\(retailer.id)")
            .accessibilityHint(Text("Copies the search for \(retailer.name)"))
        }
    }

    private func row(symbol: String) -> some View {
        HStack(spacing: Theme.Spacing.medium) {
            Text(retailer.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.Palette.primaryText)
            Spacer(minLength: Theme.Spacing.small)
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.accent)
                .accessibilityHidden(true)
        }
        .padding(.vertical, Theme.Spacing.medium - 2)
        .contentShape(Rectangle())
    }
}

private struct NearbyStoreRow: View {
    let store: NearbyStore

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.medium) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.Palette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let distance = store.distance {
                    Text(Format.distanceAway(metres: distance))
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
            }
            Spacer(minLength: Theme.Spacing.small)
            if let directions = store.directionsURL {
                Link(destination: directions) {
                    Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.Palette.accent)
                }
                .accessibilityLabel(Text("Directions to \(store.name)"))
            }
        }
        .padding(.vertical, Theme.Spacing.medium - 2)
        .accessibilityElement(children: .contain)
    }
}
