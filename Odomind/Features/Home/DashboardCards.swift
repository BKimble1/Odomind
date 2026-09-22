import SwiftUI
import OdomindCore

/// Who this is, and the two things that are always available.
///
/// The vehicle switcher is here only when there is more than one vehicle. With
/// one car there is nothing to switch to, and a control that opens a menu
/// containing the thing you are already looking at is a decoy.
struct DashboardHeader: View {
    @Environment(AppModel.self) private var model
    @Environment(NavigationRouter.self) private var router
    let showsSwitcher: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.medium - 1) {
            IconChip(symbol: "car.fill", size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text("Odomind")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.Palette.primaryText)
                Text("Drive farther. Worry less.")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
            Spacer(minLength: Theme.Spacing.small)
            if showsSwitcher { VehiclePickerBar() }
            addButton
        }
        .accessibilityElement(children: .contain)
    }

    private var addButton: some View {
        Button {
            router.presentServiceLog = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Theme.Palette.onAccent)
                .frame(width: Theme.minimumTapTarget, height: Theme.minimumTapTarget)
                .background(Theme.Palette.accent, in: Circle())
        }
        .accessibilityLabel(Text("Log a service"))
        .accessibilityIdentifier("home.quickAdd")
    }
}

/// The car: what it is, how far it has gone, and one word about how it is.
struct HeroVehicleCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let vehicle: Vehicle
    var updateMileage: () -> Void

    var body: some View {
        let summary = model.dashboardSummary(for: vehicle.id)
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
                    picture
                    details(summary)
                }
            } else {
                HStack(alignment: .top, spacing: 0) {
                    details(summary)
                    Spacer(minLength: 0)
                    picture
                        .padding(.trailing, -18)
                        .padding(.top, Theme.Spacing.section)
                }
            }
        }
        .padding(Theme.Spacing.large + 2)
        .cardSurface(radius: Theme.Radius.hero)
    }

    private var picture: some View {
        StudioVehicleImage(vehicle: vehicle, width: 178)
    }

    private func details(_ summary: DashboardSummary) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Text(vehicle.displayName)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.Palette.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            if let spec = specLine {
                Text(spec)
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
            mileage
            StatusPill(
                text: summary.verdict,
                symbol: summary.verdictSymbol,
                ground: verdictGround(summary.worstState),
                tint: verdictTint(summary.worstState)
            )
        }
    }

    @ViewBuilder
    private var mileage: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.small) {
            if let reading = model.latestReading(for: vehicle.id) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Format.distanceNumber(reading.value))
                        .font(.system(size: 34, weight: .bold, design: .default))
                        .foregroundStyle(Theme.Palette.primaryText)
                    Text(reading.value.unit.abbreviation)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("home.odometer")
                .accessibilityLabel(Text("Recorded odometer \(Format.distance(reading.value))"))
            } else {
                Text("No mileage yet")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.Palette.primaryText)
                    .accessibilityIdentifier("home.odometer")
            }
            Button("Update", action: updateMileage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.accent)
                .buttonStyle(.tappableText)
                .accessibilityLabel(Text("Update mileage"))
                .accessibilityIdentifier("home.updateMileage")
        }
    }

    /// Body style, engine and fuel — only the parts Odomind actually knows.
    /// A line with three bullets and two blanks is worse than a shorter line.
    private var spec: [String] {
        var parts: [String] = []
        if let style = VehicleBodyStyle.classify(
            identity: vehicle.identity,
            configuration: vehicle.configuration
        ) {
            parts.append(style.displayName)
        }
        if let litres = vehicle.configuration.engineDisplacementLiters {
            parts.append("\(litres.formatted()) L")
        }
        if vehicle.configuration.powertrain != .unknown {
            parts.append(vehicle.configuration.powertrain.displayName)
        }
        return parts
    }

    private var specLine: String? {
        spec.isEmpty ? nil : spec.joined(separator: " · ")
    }

    private func verdictGround(_ state: DueState?) -> Color {
        switch state {
        case .overdue: return Theme.Palette.chipOverdue
        case .dueSoon: return Theme.Palette.chipCaution
        case .needsSetup, .historyUnknown: return Theme.Palette.chipInformative
        default: return Theme.Palette.chipAccent
        }
    }

    private func verdictTint(_ state: DueState?) -> Color {
        switch state {
        case .overdue: return Theme.Colors.overdue
        case .dueSoon: return Theme.Colors.caution
        case .needsSetup, .historyUnknown: return Theme.Colors.informative
        default: return Theme.Colors.done
        }
    }
}

/// Three numbers worth a glance.
struct StatTrio: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let vehicle: Vehicle

    var body: some View {
        let summary = model.dashboardSummary(for: vehicle.id)
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: Theme.Spacing.small + 2) { tiles(summary) }
            } else {
                HStack(spacing: Theme.Spacing.small + 2) { tiles(summary) }
            }
        }
    }

    @ViewBuilder
    private func tiles(_ summary: DashboardSummary) -> some View {
        StatTile(
            symbol: "drop.fill",
            ground: nextGround(summary),
            tint: nextTint(summary),
            label: "Next service",
            value: nextValue(summary).0,
            unit: nextValue(summary).1
        )
        StatTile(
            symbol: "chart.bar.fill",
            ground: Theme.Palette.chipInformative,
            tint: Theme.Colors.informative,
            label: "This month",
            value: summary.distanceThisMonth.map(Format.distanceNumber) ?? "—",
            unit: summary.distanceThisMonth.map { $0.unit.abbreviation }
        )
        StatTile(
            symbol: "checkmark.seal.fill",
            ground: Theme.Palette.chipAccent,
            tint: Theme.Palette.accent,
            label: "On track",
            value: "\(summary.onTrack)",
            unit: "of \(summary.tracked)"
        )
    }

    /// "Overdue", or how far away the next one is. Never a guess: with no
    /// schedule Odomind can run, this is a dash and the tile says nothing.
    private func nextValue(_ summary: DashboardSummary) -> (String, String?) {
        guard let headline = summary.headline else { return ("—", nil) }
        if headline.state == .overdue { return ("Over", "due") }
        if let remaining = headline.distanceRemaining, remaining.amount > 0 {
            return (Format.distanceNumber(remaining), remaining.unit.abbreviation)
        }
        if let days = headline.daysRemaining, days > 0 {
            return ("\(days)", days == 1 ? "day" : "days")
        }
        return ("—", nil)
    }

    private func nextGround(_ summary: DashboardSummary) -> Color {
        summary.worstState == .overdue ? Theme.Palette.chipOverdue : Theme.Palette.chipAccent
    }

    private func nextTint(_ summary: DashboardSummary) -> Color {
        summary.worstState == .overdue ? Theme.Colors.overdue : Theme.Palette.accent
    }
}
