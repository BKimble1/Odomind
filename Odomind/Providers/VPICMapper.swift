import Foundation
import OdomindCore

/// Turns a vPIC record into Odomind's own types.
///
/// Every mapping here is conservative. Where vPIC is ambiguous — "4x2" could be
/// front- or rear-wheel drive, "4WD/4-Wheel Drive/4x4" does not say part-time
/// or full-time — the result is `unknown` or a general case, and the owner is
/// asked. Nothing produced here is marked as confirmed; confirmation is
/// something only the owner can do.
enum VPICMapper {

    /// Fields the setup flow cares about, with the label shown when one is blank.
    private static let reportedFieldLabels: [(key: String, label: String)] = [
        ("Make", "Make"),
        ("Model", "Model"),
        ("ModelYear", "Model year"),
        ("Trim", "Trim"),
        ("Series", "Series"),
        ("BodyClass", "Body style"),
        ("VehicleType", "Vehicle type"),
        ("DisplacementL", "Engine size"),
        ("EngineCylinders", "Cylinders"),
        ("EngineModel", "Engine model"),
        ("FuelTypePrimary", "Fuel type"),
        ("ElectrificationLevel", "Electrification"),
        ("TransmissionStyle", "Transmission"),
        ("TransmissionSpeeds", "Transmission speeds"),
        ("DriveType", "Drivetrain"),
        ("Manufacturer", "Manufacturer"),
        ("PlantCountry", "Assembly country")
    ]

    /// Fields the app asks the owner to confirm when the decoder leaves them
    /// blank, because each one changes which tasks apply.
    private static let importantFields = ["Make", "Model", "ModelYear", "FuelTypePrimary", "TransmissionStyle", "DriveType"]

    static func map(
        record: [String: VPICField],
        requestedVIN: String,
        requestedYear: Int?
    ) -> VehicleDecodeResult {
        func text(_ key: String) -> String? { record[key]?.stringValue }

        var messages: [String] = []
        if let errorCode = text("ErrorCode"), errorCode != "0" {
            if let errorText = text("ErrorText") {
                messages.append(contentsOf: splitErrorText(errorText))
            } else {
                messages.append("The lookup service reported code \(errorCode).")
            }
        }
        if let additional = text("AdditionalErrorText") {
            messages.append(additional)
        }

        let identity = VehicleIdentity(
            modelYear: record["ModelYear"]?.intValue ?? requestedYear,
            make: (text("Make") ?? "").capitalizedMakeName,
            model: text("Model") ?? "",
            trim: text("Trim"),
            series: text("Series"),
            bodyClass: text("BodyClass"),
            vin: requestedVIN,
            identityProvenance: .referenceSourced
        )

        var configuration = VehicleConfiguration()
        configuration.powertrain = powertrain(
            fuelType: text("FuelTypePrimary"),
            electrification: text("ElectrificationLevel")
        )
        configuration.engineDisplacementLiters = record["DisplacementL"]?.doubleValue
        configuration.engineCylinders = record["EngineCylinders"]?.intValue
        configuration.engineCode = text("EngineModel")
        configuration.transmission = transmission(from: text("TransmissionStyle"))
        configuration.transmissionSpeeds = record["TransmissionSpeeds"]?.intValue
        configuration.drivetrain = drivetrain(from: text("DriveType"))
        configuration.market = market(from: text("PlantCountry"))
        // Camshaft drive is never reported by vPIC, and guessing it would either
        // invent a timing-belt service or wrongly rule one out.
        configuration.camshaftDrive = .unknown

        var reported: [VehicleDecodeResult.DecodedField] = []
        var missing: [String] = []
        for (key, label) in reportedFieldLabels {
            if let value = text(key), !value.isEmpty {
                reported.append(VehicleDecodeResult.DecodedField(name: label, value: value))
            } else if importantFields.contains(key) {
                missing.append(label)
            }
        }

        return VehicleDecodeResult(
            identity: identity,
            configuration: configuration,
            providerMessages: messages.filter { !$0.isEmpty },
            missingFields: missing,
            suggestedVIN: text("SuggestedVIN"),
            reportedFields: reported
        )
    }

    /// vPIC packs several messages into one field, separated by semicolons.
    static func splitErrorText(_ text: String) -> [String] {
        text
            .components(separatedBy: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.lowercased() != "0 - vin decoded clean. check digit (9th position) is correct" }
    }

    static func powertrain(fuelType: String?, electrification: String?) -> PowertrainKind {
        let electric = (electrification ?? "").lowercased()
        if electric.contains("bev") { return .batteryElectric }
        if electric.contains("phev") { return .pluginHybrid }
        if electric.contains("hev") { return .hybrid }
        if electric.contains("fcev") { return .hydrogenFuelCell }

        let fuel = (fuelType ?? "").lowercased()
        if fuel.isEmpty { return .unknown }
        if fuel.contains("electric") { return .batteryElectric }
        if fuel.contains("fuel cell") || fuel.contains("hydrogen") { return .hydrogenFuelCell }
        if fuel.contains("diesel") { return .diesel }
        if fuel.contains("gasoline") || fuel.contains("ethanol") || fuel.contains("flexible") { return .gasoline }
        if fuel.contains("natural gas") || fuel.contains("propane") || fuel.contains("lpg") { return .other }
        return .unknown
    }

    static func transmission(from style: String?) -> TransmissionKind {
        guard let style = style?.lowercased(), !style.isEmpty else { return .unknown }
        if style.contains("continuously variable") || style.contains("cvt") { return .continuouslyVariable }
        if style.contains("dual-clutch") || style.contains("dual clutch") || style.contains("dct") { return .dualClutch }
        // An automated manual shifts itself but is a manual gearbox mechanically.
        // Odomind leaves it unconfirmed rather than filing it under either.
        if style.contains("automated manual") || style.contains("amt") { return .unknown }
        if style.contains("manual") { return .manual }
        if style.contains("automatic") { return .automatic }
        return .unknown
    }

    static func drivetrain(from driveType: String?) -> DrivetrainLayout {
        guard let value = driveType?.lowercased(), !value.isEmpty else { return .unknown }
        if value.contains("front-wheel") || value.contains("fwd") { return .frontWheelDrive }
        if value.contains("rear-wheel") || value.contains("rwd") { return .rearWheelDrive }
        if value.contains("all-wheel") || value.contains("awd") { return .allWheelDrive }
        // "4WD/4-Wheel Drive/4x4" does not say part-time or full-time, so the
        // general case is used and the owner can refine it.
        if value.contains("4wd") || value.contains("4-wheel") || value.contains("4x4") { return .fourWheelDrive }
        // "4x2" tells you how many wheels are driven but not which ones.
        return .unknown
    }

    static func market(from plantCountry: String?) -> Market {
        guard let value = plantCountry?.uppercased(), !value.isEmpty else { return .unspecified }
        // Assembly country is where it was built, not where it was sold, so it
        // is only ever a starting suggestion the owner can change.
        if value.contains("UNITED STATES") { return .unitedStates }
        if value.contains("CANADA") { return .canada }
        return .unspecified
    }
}

private extension String {
    /// vPIC returns makes in capitals ("JEEP"). Title case reads better, while
    /// leaving genuinely capitalised names like "BMW" and "GMC" alone.
    var capitalizedMakeName: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        guard trimmed == trimmed.uppercased() else { return trimmed }
        if trimmed.count <= 3 { return trimmed }
        return trimmed
            .components(separatedBy: " ")
            .map { word -> String in
                guard word.count > 3 else { return word }
                return word.prefix(1) + word.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }
}
