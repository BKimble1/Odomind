import Foundation
import OdomindCore

/// Builds and reads Odomind backup files.
///
/// A backup is one self-contained JSON document: vehicles, readings, tasks,
/// history, specifications, settings, and the receipt files themselves encoded
/// inside it. One file means a restore never depends on unzip support or on
/// files staying next to each other in whatever the owner saved them to.
struct BackupService {
    static let fileExtension = "odomindbackup"

    let attachments: AttachmentStore

    init(attachments: AttachmentStore) {
        self.attachments = attachments
    }

    /// Assembles an archive from the current snapshot.
    ///
    /// - Parameter includeAttachments: when false the document carries the
    ///   metadata but not the file bytes, which keeps a backup small at the
    ///   cost of losing receipts. The restore screen says so before applying.
    func makeArchive(
        from snapshot: GarageSnapshot,
        includeAttachments: Bool,
        includeDemoContent: Bool,
        appVersion: String,
        now: Date
    ) -> BackupArchive {
        let vehicles = snapshot.vehicles.filter { includeDemoContent || !$0.isDemo }
        let vehicleIDs = Set(vehicles.map(\.id))

        let records = snapshot.serviceRecords.filter {
            vehicleIDs.contains($0.vehicleID) && (includeDemoContent || !$0.isDemo)
        }

        var referencedAttachmentIDs = Set<UUID>()
        for record in records { referencedAttachmentIDs.formUnion(record.attachmentIDs) }
        for vehicle in vehicles {
            if let photo = vehicle.photoAttachmentID { referencedAttachmentIDs.insert(photo) }
        }

        var archiveAttachments: [BackupAttachment] = []
        for metadata in snapshot.attachments where referencedAttachmentIDs.contains(metadata.id) {
            if includeAttachments, let data = try? attachments.data(for: metadata) {
                archiveAttachments.append(
                    BackupAttachment.make(
                        id: metadata.id,
                        fileName: metadata.fileName,
                        contentType: metadata.contentType,
                        data: data
                    )
                )
            } else {
                archiveAttachments.append(
                    BackupAttachment(
                        id: metadata.id,
                        fileName: metadata.fileName,
                        contentType: metadata.contentType,
                        byteCount: metadata.byteCount,
                        checksum: "",
                        base64Data: nil
                    )
                )
            }
        }

        var specifications: [VehicleSpecificationRecord] = []
        for vehicle in vehicles {
            for specification in snapshot.specifications(for: vehicle.id) {
                specifications.append(
                    VehicleSpecificationRecord(vehicleID: vehicle.id, specification: specification)
                )
            }
        }

        return BackupArchive(
            generatedBy: "Odomind \(appVersion)",
            exportedOn: now,
            vehicles: vehicles,
            readings: snapshot.readings.filter { vehicleIDs.contains($0.vehicleID) },
            planItems: snapshot.planItems.filter { vehicleIDs.contains($0.vehicleID) },
            serviceRecords: records,
            specifications: specifications,
            attachments: archiveAttachments,
            settings: BackupSettings(
                reminderSettings: snapshot.settings.reminders,
                selectedVehicleID: snapshot.settings.selectedVehicleID,
                catalogVersion: snapshot.settings.catalogVersionLastSeen
            )
        )
    }

    /// Writes an archive to a file the share sheet can hand to the owner.
    func write(_ archive: BackupArchive, named fileName: String, in directory: URL) throws -> URL {
        let data = try archive.encoded()
        let url = directory.appendingPathComponent("\(fileName).\(Self.fileExtension)", isDirectory: false)
        try data.write(to: url, options: [.atomic])
        return url
    }

    func read(from url: URL) throws -> Result<BackupArchive, BackupIssue> {
        // A file picked from Files or iCloud Drive needs a security scope held
        // for the duration of the read.
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        return BackupImporter.decode(data)
    }

    /// Writes an attachment out of an archive and back onto disk during restore.
    func restoreAttachment(_ attachment: BackupAttachment) throws -> AttachmentMetadata {
        guard let data = attachment.decodedData() else {
            throw StoreError.saveFailed("An attachment in the backup failed its integrity check.")
        }
        return try attachments.store(
            data: data,
            contentType: attachment.contentType,
            id: attachment.id
        )
    }

    /// A default file name that does not leak anything about the vehicles.
    static func suggestedFileName(now: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        let year = components.year ?? 2000
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "Odomind-backup-%04d-%02d-%02d", year, month, day)
    }
}
