import Foundation

public enum BackupIssue: Error, Hashable, Sendable {
    case unsupportedFormatVersion(found: Int, supported: Int)
    case malformed(String)
    case readingForUnknownVehicle(UUID)
    case serviceRecordForUnknownVehicle(UUID)
    case planItemForUnknownVehicle(UUID)
    case specificationForUnknownVehicle(UUID)
    case missingAttachment(UUID)
    case corruptAttachment(UUID)
    case duplicateVehicle(UUID)
    case duplicateServiceRecord(UUID)
    case futureDatedRecord(UUID)
    case attachmentWithoutData(UUID)

    /// Blocking issues stop the import entirely. Odomind applies a backup as a
    /// single unit, so a partial restore can never leave the store in a state
    /// the app cannot explain.
    public var isBlocking: Bool {
        switch self {
        case .unsupportedFormatVersion, .malformed, .corruptAttachment:
            return true
        case .readingForUnknownVehicle, .serviceRecordForUnknownVehicle, .planItemForUnknownVehicle,
             .specificationForUnknownVehicle, .missingAttachment, .duplicateVehicle,
             .duplicateServiceRecord, .futureDatedRecord, .attachmentWithoutData:
            return false
        }
    }

    public var message: String {
        switch self {
        case .unsupportedFormatVersion(let found, let supported):
            return "This backup uses format version \(found). This version of Odomind reads version \(supported)."
        case .malformed(let detail):
            return "The backup file could not be read: \(detail)"
        case .readingForUnknownVehicle:
            return "A mileage reading refers to a vehicle that is not in the backup. It will be skipped."
        case .serviceRecordForUnknownVehicle:
            return "A service record refers to a vehicle that is not in the backup. It will be skipped."
        case .planItemForUnknownVehicle:
            return "A maintenance task refers to a vehicle that is not in the backup. It will be skipped."
        case .specificationForUnknownVehicle:
            return "A specification refers to a vehicle that is not in the backup. It will be skipped."
        case .missingAttachment:
            return "A service record refers to an attachment that is not in the backup. The record will be restored without it."
        case .corruptAttachment:
            return "An attachment in this backup is damaged. Restoring would lose data, so the import was stopped."
        case .duplicateVehicle:
            return "A vehicle in this backup is already in your garage."
        case .duplicateServiceRecord:
            return "A service record in this backup is already in your history."
        case .futureDatedRecord:
            return "A service record is dated in the future."
        case .attachmentWithoutData:
            return "This backup was exported without attachments, so receipts and photos will not be restored."
        }
    }
}

/// How to combine a backup with what is already stored.
public enum BackupMergeStrategy: String, Sendable, Hashable, CaseIterable {
    /// Delete everything currently stored and restore the backup exactly.
    case replaceEverything
    /// Keep what is stored and add only records that are not already present.
    case addMissingOnly

    public var displayName: String {
        switch self {
        case .replaceEverything: return "Replace everything"
        case .addMissingOnly: return "Add missing records only"
        }
    }

    public var explanation: String {
        switch self {
        case .replaceEverything:
            return "Your current vehicles, history and settings are deleted and replaced with this backup."
        case .addMissingOnly:
            return "Your current data is kept. Only records that are not already in Odomind are added."
        }
    }
}

/// What an import would do, shown before anything is written.
public struct BackupImportPlan: Hashable, Sendable {
    public var strategy: BackupMergeStrategy
    public var vehiclesToAdd: [Vehicle]
    public var vehiclesAlreadyPresent: [Vehicle]
    public var readingCount: Int
    public var planItemCount: Int
    public var serviceRecordCount: Int
    public var specificationCount: Int
    public var attachmentCount: Int
    public var issues: [BackupIssue]
    public var exportedOn: Date

    public var canApply: Bool { !issues.contains(where: \.isBlocking) }

    public var blockingIssues: [BackupIssue] { issues.filter(\.isBlocking) }
    public var warnings: [BackupIssue] { issues.filter { !$0.isBlocking } }

    public init(
        strategy: BackupMergeStrategy,
        vehiclesToAdd: [Vehicle],
        vehiclesAlreadyPresent: [Vehicle],
        readingCount: Int,
        planItemCount: Int,
        serviceRecordCount: Int,
        specificationCount: Int,
        attachmentCount: Int,
        issues: [BackupIssue],
        exportedOn: Date
    ) {
        self.strategy = strategy
        self.vehiclesToAdd = vehiclesToAdd
        self.vehiclesAlreadyPresent = vehiclesAlreadyPresent
        self.readingCount = readingCount
        self.planItemCount = planItemCount
        self.serviceRecordCount = serviceRecordCount
        self.specificationCount = specificationCount
        self.attachmentCount = attachmentCount
        self.issues = issues
        self.exportedOn = exportedOn
    }
}

/// The exact set of records an import will write.
///
/// Produced only after validation passes, so the persistence layer can apply it
/// in one transaction without making decisions of its own.
public struct BackupApplySet: Sendable {
    public var vehicles: [Vehicle]
    public var readings: [OdometerReading]
    public var planItems: [MaintenancePlanItem]
    public var serviceRecords: [ServiceRecord]
    public var specifications: [VehicleSpecificationRecord]
    public var attachments: [BackupAttachment]
    public var settings: BackupSettings?
    public var removesExistingData: Bool

    public init(
        vehicles: [Vehicle],
        readings: [OdometerReading],
        planItems: [MaintenancePlanItem],
        serviceRecords: [ServiceRecord],
        specifications: [VehicleSpecificationRecord],
        attachments: [BackupAttachment],
        settings: BackupSettings?,
        removesExistingData: Bool
    ) {
        self.vehicles = vehicles
        self.readings = readings
        self.planItems = planItems
        self.serviceRecords = serviceRecords
        self.specifications = specifications
        self.attachments = attachments
        self.settings = settings
        self.removesExistingData = removesExistingData
    }

    public var isEmpty: Bool {
        vehicles.isEmpty && readings.isEmpty && planItems.isEmpty
            && serviceRecords.isEmpty && specifications.isEmpty
    }
}

/// Validates and prepares a backup for restore.
public enum BackupImporter {

    /// Decodes a backup file, turning any failure into a reportable issue
    /// rather than an opaque error.
    public static func decode(_ data: Data) -> Result<BackupArchive, BackupIssue> {
        do {
            let archive = try BackupArchive.decode(data)
            guard archive.formatVersion == BackupArchive.currentFormatVersion else {
                return .failure(
                    .unsupportedFormatVersion(
                        found: archive.formatVersion,
                        supported: BackupArchive.currentFormatVersion
                    )
                )
            }
            return .success(archive)
        } catch {
            return .failure(.malformed(CatalogLoader.describe(error)))
        }
    }

    /// Describes what restoring `archive` would do.
    public static func plan(
        archive: BackupArchive,
        existingVehicleIDs: Set<UUID>,
        existingServiceRecordIDs: Set<UUID>,
        strategy: BackupMergeStrategy,
        now: Date
    ) -> BackupImportPlan {
        var issues: [BackupIssue] = []
        let archiveVehicleIDs = Set(archive.vehicles.map(\.id))

        for reading in archive.readings where !archiveVehicleIDs.contains(reading.vehicleID) {
            issues.append(.readingForUnknownVehicle(reading.vehicleID))
        }
        for record in archive.serviceRecords where !archiveVehicleIDs.contains(record.vehicleID) {
            issues.append(.serviceRecordForUnknownVehicle(record.vehicleID))
        }
        for item in archive.planItems where !archiveVehicleIDs.contains(item.vehicleID) {
            issues.append(.planItemForUnknownVehicle(item.vehicleID))
        }
        for specification in archive.specifications where !archiveVehicleIDs.contains(specification.vehicleID) {
            issues.append(.specificationForUnknownVehicle(specification.vehicleID))
        }

        let attachmentIDs = Set(archive.attachments.map(\.id))
        var referencedAttachmentIDs = Set<UUID>()
        for record in archive.serviceRecords {
            referencedAttachmentIDs.formUnion(record.attachmentIDs)
        }
        for vehicle in archive.vehicles {
            if let photo = vehicle.photoAttachmentID { referencedAttachmentIDs.insert(photo) }
        }
        for missing in referencedAttachmentIDs.subtracting(attachmentIDs).sorted(by: { $0.uuidString < $1.uuidString }) {
            issues.append(.missingAttachment(missing))
        }

        for attachment in archive.attachments {
            if attachment.base64Data == nil {
                issues.append(.attachmentWithoutData(attachment.id))
            } else if attachment.decodedData() == nil {
                issues.append(.corruptAttachment(attachment.id))
            }
        }

        for record in archive.serviceRecords where record.performedOn > now {
            issues.append(.futureDatedRecord(record.id))
        }

        var vehiclesToAdd: [Vehicle] = []
        var vehiclesAlreadyPresent: [Vehicle] = []
        for vehicle in archive.vehicles {
            if existingVehicleIDs.contains(vehicle.id) {
                vehiclesAlreadyPresent.append(vehicle)
                if strategy == .addMissingOnly {
                    issues.append(.duplicateVehicle(vehicle.id))
                }
            } else {
                vehiclesToAdd.append(vehicle)
            }
        }

        if strategy == .addMissingOnly {
            for record in archive.serviceRecords where existingServiceRecordIDs.contains(record.id) {
                issues.append(.duplicateServiceRecord(record.id))
            }
        }

        let applySet = makeApplySet(
            archive: archive,
            existingVehicleIDs: existingVehicleIDs,
            existingServiceRecordIDs: existingServiceRecordIDs,
            strategy: strategy
        )

        return BackupImportPlan(
            strategy: strategy,
            vehiclesToAdd: vehiclesToAdd,
            vehiclesAlreadyPresent: vehiclesAlreadyPresent,
            readingCount: applySet.readings.count,
            planItemCount: applySet.planItems.count,
            serviceRecordCount: applySet.serviceRecords.count,
            specificationCount: applySet.specifications.count,
            attachmentCount: applySet.attachments.count,
            issues: issues,
            exportedOn: archive.exportedOn
        )
    }

    /// Builds the exact record set to write.
    ///
    /// Records whose vehicle is missing are dropped here rather than written and
    /// cleaned up later, so the store never holds an orphan.
    public static func makeApplySet(
        archive: BackupArchive,
        existingVehicleIDs: Set<UUID>,
        existingServiceRecordIDs: Set<UUID>,
        strategy: BackupMergeStrategy
    ) -> BackupApplySet {
        let archiveVehicleIDs = Set(archive.vehicles.map(\.id))

        let vehicles: [Vehicle]
        switch strategy {
        case .replaceEverything:
            vehicles = archive.vehicles
        case .addMissingOnly:
            vehicles = archive.vehicles.filter { !existingVehicleIDs.contains($0.id) }
        }
        let acceptedVehicleIDs = Set(vehicles.map(\.id))

        func accepts(_ vehicleID: UUID) -> Bool {
            archiveVehicleIDs.contains(vehicleID) && acceptedVehicleIDs.contains(vehicleID)
        }

        let readings = archive.readings.filter { accepts($0.vehicleID) }
        let planItems = archive.planItems.filter { accepts($0.vehicleID) }
        let specifications = archive.specifications.filter { accepts($0.vehicleID) }
        var serviceRecords = archive.serviceRecords.filter { accepts($0.vehicleID) }
        if strategy == .addMissingOnly {
            serviceRecords = serviceRecords.filter { !existingServiceRecordIDs.contains($0.id) }
        }

        var neededAttachments = Set<UUID>()
        for record in serviceRecords { neededAttachments.formUnion(record.attachmentIDs) }
        for vehicle in vehicles {
            if let photo = vehicle.photoAttachmentID { neededAttachments.insert(photo) }
        }
        let attachments = archive.attachments.filter {
            neededAttachments.contains($0.id) && $0.base64Data != nil
        }

        // Strip references to attachments that are not coming with us, so a
        // restored record never points at a file that does not exist.
        let availableAttachmentIDs = Set(attachments.map(\.id))
        serviceRecords = serviceRecords.map { record in
            var copy = record
            copy.attachmentIDs = record.attachmentIDs.filter { availableAttachmentIDs.contains($0) }
            return copy
        }
        let repairedVehicles = vehicles.map { vehicle -> Vehicle in
            var copy = vehicle
            if let photo = vehicle.photoAttachmentID, !availableAttachmentIDs.contains(photo) {
                copy.photoAttachmentID = nil
            }
            return copy
        }

        return BackupApplySet(
            vehicles: repairedVehicles,
            readings: readings,
            planItems: planItems,
            serviceRecords: serviceRecords,
            specifications: specifications,
            attachments: attachments,
            settings: strategy == .replaceEverything ? archive.settings : nil,
            removesExistingData: strategy == .replaceEverything
        )
    }
}
