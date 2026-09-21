import SwiftUI
import OdomindCore

/// What is known about this vehicle's fluids, tires and parts — and, just as
/// importantly, what is not.
///
/// Every kind Odomind supports appears. A value that exists shows its source; a
/// value that does not shows how to supply it. There is no third state where a
/// plausible-looking number appears with nothing behind it.
struct SpecificationsView: View {
    @Environment(AppModel.self) private var model
    let vehicleID: UUID

    @State private var editingKind: SpecificationEdit?

    private var vehicle: Vehicle? { model.snapshot.vehicle(id: vehicleID) }

    var body: some View {
        Group {
            if let vehicle {
                content(vehicle)
            } else {
                ContentUnavailableView("Vehicle not found", systemImage: "car.side")
            }
        }
        .navigationTitle("Specifications")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingKind) { edit in
            if let vehicle {
                SpecificationEditor(vehicle: vehicle, kind: edit.kind)
            }
        }
    }

    @ViewBuilder
    private func content(_ vehicle: Vehicle) -> some View {
        let resolved = model.resolvedSpecifications(for: vehicle)
        let byKind = Dictionary(resolved.map { ($0.kind, $0) }, uniquingKeysWith: { first, _ in first })

        List {
            Section {
                // Read from what the catalog actually resolved rather than
                // asserting a fixed claim, so this stays true if a later
                // catalog does carry values for some vehicles.
                let shipped = resolved.filter { !$0.isOwnerOverride }.count
                InlineNotice(
                    message: shipped == 0
                        ? "Odomind ships no fluid, tire or pressure values for this vehicle. Each row below says where that particular value is written on your car. Add it once and it appears everywhere it is relevant."
                        : "Odomind has \(shipped) value\(shipped == 1 ? "" : "s") for this vehicle and shows where each came from. Each row marked Not available says where to find that particular value."
                )
            }

            ForEach(SpecificationGroup.allCases, id: \.self) { group in
                let kinds = relevantKinds(in: group, for: vehicle)
                if !kinds.isEmpty {
                    Section {
                        ForEach(kinds, id: \.self) { kind in
                            if let match = byKind[kind] {
                                Button {
                                    editingKind = SpecificationEdit(kind: kind)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        ValueRow(
                                            label: kind.displayName,
                                            value: match.active.value.displayString,
                                            secondary: match.active.basis == .factory ? nil : match.active.basis.displayName
                                        )
                                        ProvenanceLabel(provenance: match.active.provenance, sourceName: match.sourceName)
                                        if let superseded = match.supersededCatalogValue {
                                            Text("Catalog value: \(superseded.value.displayString)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        if let note = match.active.appliesToNote {
                                            Text(note)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                                .foregroundStyle(.primary)
                            } else {
                                UnavailableValueRow(
                                    label: kind.displayName,
                                    explanation: kind.sourceHint
                                ) {
                                    editingKind = SpecificationEdit(kind: kind)
                                }
                            }
                        }
                    } header: {
                        Label(group.displayName, systemImage: group.symbolName)
                    } footer: {
                        if group == .tiresAndWheels {
                            Text("Use the placard in the driver's door opening for cold tire pressure. The number moulded into the tire sidewall is that tire's maximum, not your vehicle's operating pressure.")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    /// Only shows specification kinds that can apply to this vehicle.
    private func relevantKinds(in group: SpecificationGroup, for vehicle: Vehicle) -> [SpecificationKind] {
        SpecificationKind.allCases
            .filter { $0.group == group }
            .filter { kind in
                switch kind {
                case .engineOilViscosity, .engineOilCapacityWithFilter, .engineOilStandard,
                     .engineOilFilterPartNumber, .sparkPlugType, .sparkPlugGap,
                     .engineAirFilterPartNumber, .fuelGrade, .fuelTankCapacity:
                    return vehicle.configuration.powertrain.hasCombustionEngine
                case .transferCaseFluidType:
                    return vehicle.configuration.effectiveTransferCase != .notFitted
                case .frontDifferentialFluidType:
                    return vehicle.configuration.effectiveFrontDifferential != .notFitted
                case .rearDifferentialFluidType:
                    return vehicle.configuration.effectiveRearDifferential != .notFitted
                default:
                    return true
                }
            }
    }

}

/// Identifies which specification the editor sheet is editing, without
/// retroactively conforming a domain enum to `Identifiable`.
struct SpecificationEdit: Identifiable {
    var id: String { kind.rawValue }
    let kind: SpecificationKind
}
