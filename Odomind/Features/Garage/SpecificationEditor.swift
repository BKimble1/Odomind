import SwiftUI
import OdomindCore

/// Records one specification from the owner's manual or door placard.
///
/// What the owner types is stored as theirs: trusted, used everywhere, and
/// never badged as manufacturer-verified, because Odomind did not check it.
struct SpecificationEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let vehicle: Vehicle
    let kind: SpecificationKind

    @State private var text = ""
    @State private var numberText = ""
    @State private var volumeUnit: VolumeUnit = .usQuarts
    @State private var pressureUnit: PressureUnit = .psi
    @State private var torqueUnit: TorqueUnit = .poundFeet
    @State private var basis: EquipmentBasis = .factory
    @State private var note = ""
    @State private var didLoad = false

    private enum Shape {
        case text
        case volume
        case pressure
        case torque
    }

    private var shape: Shape {
        switch kind {
        case .engineOilCapacityWithFilter, .coolantCapacity, .transmissionFluidCapacity, .fuelTankCapacity:
            return .volume
        case .coldTirePressureFront, .coldTirePressureRear, .spareTirePressure:
            return .pressure
        case .lugNutTorque:
            return .torque
        default:
            return .text
        }
    }

    private var number: Double? { Double(numberText.replacingOccurrences(of: ",", with: ".")) }

    private var value: SpecificationValue? {
        switch shape {
        case .text:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : .text(trimmed)
        case .volume:
            return number.map { .volume(amount: $0, unit: volumeUnit) }
        case .pressure:
            return number.map { .pressure(amount: $0, unit: pressureUnit) }
        case .torque:
            return number.map { .torque(amount: $0, unit: torqueUnit) }
        }
    }

    private var existing: Specification? {
        model.snapshot.specifications(for: vehicle.id).first { $0.kind == kind }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    switch shape {
                    case .text:
                        TextField(placeholder, text: $text)
                            .autocorrectionDisabled()
                    case .volume:
                        HStack {
                            TextField(placeholder, text: $numberText)
                                .keyboardType(.decimalPad)
                            Picker("", selection: $volumeUnit) {
                                Text("qt").tag(VolumeUnit.usQuarts)
                                Text("L").tag(VolumeUnit.liters)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 120)
                        }
                    case .pressure:
                        HStack {
                            TextField(placeholder, text: $numberText)
                                .keyboardType(.decimalPad)
                            Picker("", selection: $pressureUnit) {
                                Text("psi").tag(PressureUnit.psi)
                                Text("kPa").tag(PressureUnit.kilopascals)
                                Text("bar").tag(PressureUnit.bar)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 160)
                        }
                    case .torque:
                        HStack {
                            TextField(placeholder, text: $numberText)
                                .keyboardType(.decimalPad)
                            Picker("", selection: $torqueUnit) {
                                Text("lb-ft").tag(TorqueUnit.poundFeet)
                                Text("N·m").tag(TorqueUnit.newtonMeters)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 140)
                        }
                    }
                } header: {
                    Text(kind.displayName)
                } footer: {
                    Text(guidance)
                }

                Section {
                    Picker("This describes", selection: $basis) {
                        ForEach(EquipmentBasis.allCases, id: \.self) { value in
                            Text(value.displayName).tag(value)
                        }
                    }
                    TextField("Note, e.g. 'Sport trim, 16-inch wheels'", text: $note)
                } footer: {
                    Text("Keeping factory specification separate from what is fitted now matters when you have changed wheels, tires or fluids.")
                }

                if existing != nil {
                    Section {
                        Button("Remove this value", role: .destructive) {
                            model.deleteSpecification(kind: kind, for: vehicle.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(kind.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(value == nil)
                }
            }
            .onAppear(perform: load)
        }
    }

    private var placeholder: String {
        switch shape {
        case .text: return "Value"
        case .volume: return "Amount"
        case .pressure: return "Pressure"
        case .torque: return "Torque"
        }
    }

    private var guidance: String {
        if kind.isVehiclePlacardOnly {
            return "Read this from the placard in your driver's door opening. The number on the tire sidewall is that tire's maximum, not your vehicle's operating pressure."
        }
        switch kind {
        case .engineOilViscosity:
            return "For example 5W-20 or 0W-16, exactly as your manual writes it."
        case .engineOilCapacityWithFilter:
            return "The capacity with a filter change, as your manual states it."
        case .tireSizeFront, .tireSizeRear, .spareTireSize:
            return "For example P225/75R16, as moulded on the sidewall or listed on the placard."
        case .wheelSizeFront, .wheelSizeRear:
            return "For example 16x7. This is the wheel, not the tire."
        default:
            return "Copy this from your owner's manual. Odomind stores it against this vehicle as a value you entered."
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let existing else { return }
        basis = existing.basis
        note = existing.appliesToNote ?? ""
        switch existing.value {
        case .text(let value):
            text = value
        case .volume(let amount, let unit):
            numberText = SpecificationValue.format(amount)
            volumeUnit = unit
        case .pressure(let amount, let unit):
            numberText = SpecificationValue.format(amount)
            pressureUnit = unit
        case .torque(let amount, let unit):
            numberText = SpecificationValue.format(amount)
            torqueUnit = unit
        case .length(let amount, _):
            numberText = SpecificationValue.format(amount)
        }
    }

    private func save() {
        guard let value else { return }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let specification = Specification(
            id: existing?.id ?? UUID(),
            kind: kind,
            value: value,
            provenance: .userEntered,
            basis: basis,
            appliesToNote: trimmedNote.isEmpty ? nil : trimmedNote,
            updatedAt: model.clock.now
        )
        model.saveSpecification(specification, for: vehicle.id)
        dismiss()
    }
}
