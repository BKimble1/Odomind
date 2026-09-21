import Foundation

/// One configuration a vehicle was actually sold in, as a provider describes
/// it.
///
/// Build 2 asked "runs on?" and "driven wheels?" with the full enum in a
/// picker — every powertrain ever built, offered for every car. That is a
/// question the owner has to answer from memory, and an owner who picks wrong
/// gets a plan for a vehicle they do not have.
///
/// This is the alternative the brief asks for: "confirm year and necessary
/// engine/body/trim choices using provider-backed options". The options are
/// the ones a source says exist for that year, make and model. Two rules hold
/// everything else together:
///
/// - **`label` is the provider's own words, unedited.** It is what the owner
///   reads and recognises, and paraphrasing it would put Odomind's guess in
///   front of the source's statement.
/// - **A field the provider did not state stays unset.** The mapping below
///   refuses anything it does not recognise rather than picking the nearest
///   case, because a wrong drivetrain silently adds or removes whole jobs.
public struct VehicleConfigurationOption: Codable, Hashable, Sendable, Identifiable {
    /// The provider's own identifier for this configuration.
    public var id: String
    public var providerName: String
    /// Where a person can read the same statement.
    public var providerURL: URL?
    /// The provider's description, verbatim: "2.5 L, 4 cyl, Automatic (S6),
    /// Regular Gasoline".
    public var label: String

    public var engineDisplacementLiters: Double?
    public var cylinders: Int?
    /// The provider's transmission wording, kept alongside the mapped case
    /// because "Automatic (S6)" says more than `.automatic`.
    public var transmissionDescription: String?
    public var driveDescription: String?
    public var fuelDescription: String?
    public var vehicleClass: String?
    public var engineDescription: String?
    public var retrievedOn: Date

    public init(
        id: String,
        providerName: String,
        providerURL: URL? = nil,
        label: String,
        engineDisplacementLiters: Double? = nil,
        cylinders: Int? = nil,
        transmissionDescription: String? = nil,
        driveDescription: String? = nil,
        fuelDescription: String? = nil,
        vehicleClass: String? = nil,
        engineDescription: String? = nil,
        retrievedOn: Date = Date()
    ) {
        self.id = id
        self.providerName = providerName
        self.providerURL = providerURL
        self.label = label
        self.engineDisplacementLiters = engineDisplacementLiters
        self.cylinders = cylinders
        self.transmissionDescription = transmissionDescription
        self.driveDescription = driveDescription
        self.fuelDescription = fuelDescription
        self.vehicleClass = vehicleClass
        self.engineDescription = engineDescription
        self.retrievedOn = retrievedOn
    }

    // MARK: - Mapping onto Odomind's own configuration

    /// The powertrain this option's fuel description states, or `.unknown`.
    ///
    /// Deliberately narrow. "Regular Gasoline" is gasoline; "Premium and
    /// Electricity" is a plug-in hybrid only because that phrasing is the
    /// provider's own way of saying so. Anything unrecognised is left unknown
    /// and the owner is asked, which is the outcome Build 2 had for every
    /// vehicle and is still the right one where a source is silent.
    public var powertrain: PowertrainKind {
        let text = (fuelDescription ?? "").lowercased()
        guard !text.isEmpty else { return .unknown }
        if text.contains("electricity") {
            // "Premium and Electricity" / "Regular Gas and Electricity" are
            // the plug-in wordings; "Electricity" alone is battery-electric.
            let alsoBurnsFuel = text.contains("gas") || text.contains("premium")
                || text.contains("regular") || text.contains("diesel")
            return alsoBurnsFuel ? .pluginHybrid : .batteryElectric
        }
        if text.contains("diesel") { return .diesel }
        if text.contains("hydrogen") { return .hydrogenFuelCell }
        if text.contains("gas") || text.contains("premium") || text.contains("regular")
            || text.contains("e85") || text.contains("midgrade") {
            return .gasoline
        }
        return .unknown
    }

    /// The drivetrain the provider's wording states, or `.unknown`.
    ///
    /// "4-Wheel or All-Wheel Drive" is a real value in this vocabulary and it
    /// means the source does not distinguish them, so neither does Odomind: it
    /// stays unknown rather than being resolved by coin toss. A transfer case
    /// task hangs on that distinction.
    public var drivetrain: DrivetrainLayout {
        let text = (driveDescription ?? "").lowercased()
        guard !text.isEmpty else { return .unknown }
        if text.contains("or all-wheel") || text.contains("or all wheel") { return .unknown }
        if text.contains("part-time") || text.contains("part time") { return .fourWheelDrivePartTime }
        if text.contains("all-wheel") || text.contains("all wheel") { return .allWheelDrive }
        if text.contains("front-wheel") || text.contains("front wheel") { return .frontWheelDrive }
        if text.contains("rear-wheel") || text.contains("rear wheel") { return .rearWheelDrive }
        if text.contains("4-wheel") || text.contains("4 wheel") || text.contains("4wd") {
            // No sub-type stated. `.fourWheelDrive` exists for exactly this.
            return .fourWheelDrive
        }
        return .unknown
    }

    /// The transmission the provider's wording states, or `.unknown`.
    public var transmission: TransmissionKind {
        let text = (transmissionDescription ?? "").lowercased()
        guard !text.isEmpty else { return .unknown }
        if text.contains("variable gear ratios") || text.contains("cvt") { return .continuouslyVariable }
        if text.contains("automated manual") || text.contains("am-s") || text.contains("dual clutch") {
            return .dualClutch
        }
        if text.contains("automatic") { return .automatic }
        if text.contains("manual") { return .manual }
        return .unknown
    }

    /// Applies only what the provider stated, leaving everything else alone.
    ///
    /// A value the owner has already confirmed is never overwritten: they were
    /// looking at their own car and the provider was looking at a table.
    public func applied(to configuration: VehicleConfiguration) -> VehicleConfiguration {
        var updated = configuration

        if powertrain != .unknown, !configuration.confirmedFields.contains("powertrain") {
            updated.powertrain = powertrain
        }
        if drivetrain != .unknown, !configuration.confirmedFields.contains("drivetrain") {
            updated.drivetrain = drivetrain
        }
        if transmission != .unknown, !configuration.confirmedFields.contains("transmission") {
            updated.transmission = transmission
        }
        if let litres = engineDisplacementLiters,
           !configuration.confirmedFields.contains("engineDisplacementLiters") {
            updated.engineDisplacementLiters = litres
        }
        if let cylinders, !configuration.confirmedFields.contains("engineCylinders") {
            updated.engineCylinders = cylinders
        }
        return updated
    }

    /// The line under the option, naming where it came from.
    public var sourceLine: String {
        "From \(providerName), retrieved \(Self.dayFormatter.string(from: retrievedOn))"
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM yyyy"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}
