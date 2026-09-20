import Foundation
import OdomindCore

/// A prepared file waiting for the share sheet.
struct ExportedFile: Identifiable, Hashable {
    let id = UUID()
    var url: URL
    var description: String
}

extension AppModel {

    var appVersion: String {
        let bundle = Bundle.main
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    private var exportDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
    }

    private func prepareExportDirectory() throws -> URL {
        let directory = exportDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // MARK: - Exports

    func exportHistoryCSV(vehicleIDs: Set<UUID>?, includeDemoContent: Bool) -> ExportedFile? {
        do {
            let directory = try prepareExportDirectory()
            let url = try exportService.writeCSV(
                snapshot: snapshot,
                vehicleIDs: vehicleIDs,
                includeDemoContent: includeDemoContent,
                calendar: calendar,
                to: directory,
                fileName: BackupService.suggestedFileName(now: clock.now, calendar: calendar)
                    .replacingOccurrences(of: "backup", with: "history")
            )
            return ExportedFile(url: url, description: "Service history (CSV)")
        } catch {
            alert = AppAlert(title: "Could not create the export", message: String(describing: error))
            return nil
        }
    }

    func exportHistoryPDF(vehicleID: UUID, includeVIN: Bool, includeDemoContent: Bool) -> ExportedFile? {
        guard let vehicle = snapshot.vehicle(id: vehicleID) else { return nil }
        do {
            let directory = try prepareExportDirectory()
            let url = try exportService.writePDF(
                vehicle: vehicle,
                records: snapshot.serviceRecords(for: vehicleID),
                readings: snapshot.readings(for: vehicleID),
                includeVIN: includeVIN,
                includeDemoContent: includeDemoContent,
                generatedOn: clock.now,
                locale: .current,
                calendar: calendar,
                to: directory,
                fileName: "Odomind-service-history"
            )
            return ExportedFile(url: url, description: "Service history (PDF)")
        } catch {
            alert = AppAlert(title: "Could not create the PDF", message: String(describing: error))
            return nil
        }
    }

    func exportBackup(includeAttachments: Bool, includeDemoContent: Bool) -> ExportedFile? {
        do {
            let directory = try prepareExportDirectory()
            let archive = backupService.makeArchive(
                from: snapshot,
                includeAttachments: includeAttachments,
                includeDemoContent: includeDemoContent,
                appVersion: appVersion,
                now: clock.now
            )
            let url = try backupService.write(
                archive,
                named: BackupService.suggestedFileName(now: clock.now, calendar: calendar),
                in: directory
            )
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = attributes?[.size] as? Int
            let sizeText = size.map { " · \(ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file))" } ?? ""
            return ExportedFile(url: url, description: "Odomind backup\(sizeText)")
        } catch {
            alert = AppAlert(
                title: "Could not create the backup",
                message: String(describing: error),
                recoverySuggestion: "Check that your device has free space and try again."
            )
            return nil
        }
    }

    /// Clears exported files from the temporary directory.
    ///
    /// Exports contain the owner's whole history, so they do not linger after
    /// the share sheet closes.
    func clearExports() {
        try? FileManager.default.removeItem(at: exportDirectory)
    }

    // MARK: - Import

    /// Reads a backup and describes what restoring it would do.
    ///
    /// Nothing is written at this stage. The owner sees the counts, the
    /// warnings and the strategy before anything changes.
    func previewImport(from url: URL, strategy: BackupMergeStrategy) -> (archive: BackupArchive, plan: BackupImportPlan)? {
        do {
            switch try backupService.read(from: url) {
            case .failure(let issue):
                alert = AppAlert(title: "Could not read that backup", message: issue.message)
                return nil
            case .success(let archive):
                let plan = BackupImporter.plan(
                    archive: archive,
                    existingVehicleIDs: Set(snapshot.vehicles.map(\.id)),
                    existingServiceRecordIDs: Set(snapshot.serviceRecords.map(\.id)),
                    strategy: strategy,
                    now: clock.now
                )
                return (archive, plan)
            }
        } catch {
            alert = AppAlert(
                title: "Could not open that file",
                message: String(describing: error),
                recoverySuggestion: "Make sure the file is an Odomind backup and try again."
            )
            return nil
        }
    }

    /// Applies a previewed import.
    ///
    /// The whole thing lands or none of it does: the store rolls back on any
    /// failure, so a half-restored garage is not a state Odomind can end up in.
    @discardableResult
    func applyImport(archive: BackupArchive, strategy: BackupMergeStrategy) async -> Bool {
        let plan = BackupImporter.plan(
            archive: archive,
            existingVehicleIDs: Set(snapshot.vehicles.map(\.id)),
            existingServiceRecordIDs: Set(snapshot.serviceRecords.map(\.id)),
            strategy: strategy,
            now: clock.now
        )
        guard plan.canApply else {
            alert = AppAlert(
                title: "This backup cannot be restored",
                message: plan.blockingIssues.map(\.message).joined(separator: "\n\n")
            )
            return false
        }

        let applySet = BackupImporter.makeApplySet(
            archive: archive,
            existingVehicleIDs: Set(snapshot.vehicles.map(\.id)),
            existingServiceRecordIDs: Set(snapshot.serviceRecords.map(\.id)),
            strategy: strategy
        )

        // Files are written first and old ones removed only once the store
        // write has landed. Deleting up front meant a failed write left the
        // receipts gone and the records rolled back — the one outcome a restore
        // must never produce.
        let existingFileNames = Set(snapshot.attachments.map(\.fileName))
        var writtenFileNames: Set<String> = []

        do {
            try store.apply(applySet) { attachment in
                let metadata = try backupService.restoreAttachment(attachment)
                writtenFileNames.insert(metadata.fileName)
                return metadata
            }
        } catch {
            // The store rolled itself back; undo the files this attempt wrote.
            for fileName in writtenFileNames.subtracting(existingFileNames) {
                attachments.delete(fileName: fileName)
            }
            alert = .saveFailed(error)
            refresh()
            return false
        }

        if applySet.removesExistingData {
            for fileName in existingFileNames.subtracting(writtenFileNames) {
                attachments.delete(fileName: fileName)
            }
        }

        refresh()
        sweepOrphanedAttachments()
        await syncReminders()
        return true
    }

    // MARK: - Deleting everything

    /// Removes every record, every file and every pending reminder.
    func deleteAllData() async {
        do {
            _ = try store.deleteEverything()
        } catch {
            alert = .saveFailed(error)
            return
        }
        attachments.deleteEverything()
        await reminderCoordinator.scheduler.cancelAll()
        clearExports()
        refresh()
        // Re-run the reconciliation rather than blanking the report by hand, so
        // the diagnostics screen shows what is actually scheduled: nothing.
        await syncReminders()
    }
}
