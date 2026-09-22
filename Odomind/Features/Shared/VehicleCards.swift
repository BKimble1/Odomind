import SwiftUI
import OdomindCore

/// Loads a vehicle's photo once and hands back the artwork decision.
///
/// The resolver is pure and lives in the core; this is the part that has to
/// touch the attachment store, so it is kept in one place rather than repeated
/// in every card.
@MainActor
struct VehicleArtworkLoader {
    static func resolution(for vehicle: Vehicle, model: AppModel) -> VehicleArtworkResolution {
        VehicleArtworkResolver.resolve(
            vehicle: vehicle,
            hasPhoto: vehicle.photoAttachmentID.flatMap { model.snapshot.attachment(id: $0) } != nil
        )
    }
}

/// A vehicle in the garage: a picture worth looking at, a name, the mileage,
/// and one line about what is coming.
struct GarageVehicleCard: View {
    @Environment(AppModel.self) private var model
    let vehicle: Vehicle
    let isSelected: Bool
    var isHero: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Flush to the card's own edges and square at the bottom, so the
            // picture *is* the top of the card. Build 2 drew a rounded grey
            // plate inside a rounded white card inside a grouped background —
            // three nested frames around one photograph.
            StudioVehicleImage(vehicle: vehicle, width: isHero ? 260 : 200)
                .frame(maxWidth: .infinity)
                .padding(.top, Theme.Spacing.large)
                .padding(.bottom, Theme.Spacing.small)

            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.small) {
                    Text(vehicle.displayName)
                        .font(isHero ? .title3.weight(.semibold) : .headline)
                        .foregroundStyle(Theme.Palette.primaryText)
                    if vehicle.isDemo { SampleBadge() }
                    Spacer(minLength: Theme.Spacing.small)
                    if isSelected {
                        // Never colour alone: the word is the signal and the
                        // mark is decoration.
                        Label("Pinned", systemImage: "pin.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.Palette.accent)
                            // Keeps its width against a long vehicle name;
                            // the name is the one that should wrap, and a
                            // truncated "Selec…" is what the audit saw.
                            .fixedSize()
                    }
                }

                if vehicle.displayName != vehicle.identity.displayName {
                    Text(vehicle.identity.displayName)
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.secondaryText)
                }

                Text(statusLine)
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.Spacing.medium)
        }
        .cardSurface()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("garage.vehicle")
    }

    /// Mileage and the single most useful thing about the plan — never a
    /// health score, and never an all-clear when history is unknown.
    private var statusLine: String {
        var parts: [String] = []
        if let reading = model.latestReading(for: vehicle.id) {
            parts.append(Format.distance(reading.value))
        } else {
            parts.append("No mileage yet")
        }

        let evaluations = model.evaluations(for: vehicle.id)
        let overdue = evaluations.filter { $0.state == .overdue }.count
        let dueSoon = evaluations.filter { $0.state == .dueSoon }.count
        let unknown = evaluations.filter { $0.state == .historyUnknown || $0.state == .needsSetup }.count

        if overdue > 0 {
            parts.append("\(overdue) overdue")
        } else if dueSoon > 0 {
            parts.append("\(dueSoon) due soon")
        } else if evaluations.contains(where: { $0.state.isScheduled }) {
            parts.append("nothing due")
        } else if unknown > 0 {
            parts.append("plan not started")
        }
        return parts.joined(separator: " · ")
    }
}
