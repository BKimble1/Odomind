import Foundation
import SwiftData
import OdomindCore

/// App-level settings, kept as a value type like everything else.
struct AppSettings: Hashable, Sendable {
    var selectedVehicleID: UUID?
    var hasCompletedOnboarding: Bool
    var catalogVersionLastSeen: String?
    var reminders: ReminderSettings
    /// Everything Build 2 added, carried as one tolerant JSON blob. See
    /// `AppPreferences` for why it is shaped that way.
    var preferences: AppPreferences

    static let initial = AppSettings(
        selectedVehicleID: nil,
        hasCompletedOnboarding: false,
        catalogVersionLastSeen: nil,
        reminders: .default,
        preferences: .default
    )
}

struct AttachmentMetadata: Hashable, Sendable, Identifiable {
    var id: UUID
    var fileName: String
    var contentType: String
    var byteCount: Int
    var createdAt: Date
    var caption: String?
}

/// Everything the app needs, read in one pass.
///
/// Screens render from this snapshot rather than querying the store, which
/// keeps the scheduling results consistent within a frame and makes every view
/// trivially previewable and testable with hand-built data.
struct GarageSnapshot: Sendable {
    var vehicles: [Vehicle] = []
    var declaredTypicalDistances: [UUID: Distance] = [:]
    var readings: [OdometerReading] = []
    var planItems: [MaintenancePlanItem] = []
    var serviceRecords: [ServiceRecord] = []
    var specifications: [UUID: [Specification]] = [:]
    var attachments: [AttachmentMetadata] = []
    var appointments: [Appointment] = []
    var settings: AppSettings = .initial
    var problems: [StoreProblem] = []

    func vehicle(id: UUID) -> Vehicle? { vehicles.first { $0.id == id } }
    func readings(for vehicleID: UUID) -> [OdometerReading] { readings.filter { $0.vehicleID == vehicleID } }
    func planItems(for vehicleID: UUID) -> [MaintenancePlanItem] { planItems.filter { $0.vehicleID == vehicleID } }
    func serviceRecords(for vehicleID: UUID) -> [ServiceRecord] {
        serviceRecords.filter { $0.vehicleID == vehicleID }
    }
    func specifications(for vehicleID: UUID) -> [Specification] { specifications[vehicleID] ?? [] }
    func appointments(for vehicleID: UUID) -> [Appointment] { appointments.filter { $0.vehicleID == vehicleID } }
    func attachment(id: UUID) -> AttachmentMetadata? { attachments.first { $0.id == id } }
}

enum StoreError: Error, LocalizedError {
    case notFound(String)
    case saveFailed(String)
    case loadFailed(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let what):
            return "\(what) could not be found."
        case .saveFailed(let detail):
            return "Odomind could not save your change: \(detail)"
        case .loadFailed(let detail):
            return "Odomind could not read your data: \(detail)"
        }
    }
}

/// The persistence boundary.
///
/// Deliberately not a SwiftUI `@Query`: the app reads a whole snapshot, works
/// with domain values and writes explicitly. That trades a little convenience
/// for behaviour that can be exercised in a test with an in-memory container.
@MainActor
final class OdomindStore {
    let container: ModelContainer

    private var context: ModelContext { container.mainContext }

    init(inMemory: Bool = false) throws {
        let schema = OdomindSchema.current
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            container = try ModelContainer(
                for: schema,
                migrationPlan: OdomindMigrationPlan.self,
                configurations: configuration
            )
        } catch {
            throw StoreError.loadFailed(String(describing: error))
        }
    }

    // MARK: - Reading

    func snapshot() throws -> GarageSnapshot {
        var snapshot = GarageSnapshot()
        var problems: [StoreProblem] = []

        let storedVehicles = try fetch(
            StoredVehicle.self,
            sortBy: [SortDescriptor(\StoredVehicle.sortIndex), SortDescriptor(\StoredVehicle.createdAt)]
        )
        snapshot.vehicles = storedVehicles.map { $0.toDomain(problems: &problems) }
        for stored in storedVehicles {
            if let declared = stored.declaredTypicalDistance {
                snapshot.declaredTypicalDistances[stored.id] = declared
            }
        }

        snapshot.readings = try fetch(
            StoredOdometerReading.self,
            sortBy: [SortDescriptor(\StoredOdometerReading.recordedOn)]
        ).map { $0.toDomain() }

        snapshot.planItems = try fetch(
            StoredPlanItem.self,
            sortBy: [SortDescriptor(\StoredPlanItem.createdAt)]
        ).map { $0.toDomain(problems: &problems) }

        snapshot.serviceRecords = try fetch(
            StoredServiceRecord.self,
            sortBy: [SortDescriptor(\StoredServiceRecord.performedOn, order: .reverse)]
        ).map { $0.toDomain(problems: &problems) }

        for stored in try fetch(StoredSpecification.self, sortBy: [SortDescriptor(\StoredSpecification.kindRaw)]) {
            guard let specification = stored.toDomain(problems: &problems) else { continue }
            snapshot.specifications[stored.vehicleID, default: []].append(specification)
        }

        snapshot.attachments = try fetch(
            StoredAttachment.self,
            sortBy: [SortDescriptor(\StoredAttachment.createdAt)]
        ).map {
            AttachmentMetadata(
                id: $0.id,
                fileName: $0.fileName,
                contentType: $0.contentType,
                byteCount: $0.byteCount,
                createdAt: $0.createdAt,
                caption: $0.caption
            )
        }

        snapshot.appointments = try fetch(
            StoredAppointment.self,
            sortBy: [SortDescriptor(\StoredAppointment.scheduledOn)]
        ).map { $0.toDomain(problems: &problems) }

        snapshot.settings = try loadSettings(problems: &problems)
        snapshot.problems = problems
        return snapshot
    }

    private func fetch<T: PersistentModel>(_ type: T.Type, sortBy: [SortDescriptor<T>] = []) throws -> [T] {
        do {
            return try context.fetch(FetchDescriptor<T>(sortBy: sortBy))
        } catch {
            throw StoreError.loadFailed(String(describing: error))
        }
    }

    private func loadSettings(problems: inout [StoreProblem]) throws -> AppSettings {
        let rows = try fetch(StoredSettings.self)
        guard let row = rows.first else { return .initial }
        return AppSettings(
            selectedVehicleID: row.selectedVehicleID,
            hasCompletedOnboarding: row.hasCompletedOnboarding,
            catalogVersionLastSeen: row.catalogVersionLastSeen,
            reminders: StoreCoding.decodeOrFallback(
                ReminderSettings.self,
                from: row.reminderSettingsData,
                fallback: .default,
                context: "Reminder settings",
                problems: &problems
            ),
            // A Build 1 store has no value here at all, which decodes to the
            // defaults rather than reporting a problem.
            preferences: StoreCoding.decodeOrFallback(
                AppPreferences.self,
                from: row.preferencesData,
                fallback: .default,
                context: "App preferences",
                problems: &problems
            )
        )
    }

    // MARK: - Writing

    /// Commits pending changes.
    ///
    /// Save failures are surfaced, never swallowed: the caller keeps the owner's
    /// input on screen and shows what went wrong rather than pretending the
    /// change landed.
    private func commit() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw StoreError.saveFailed(String(describing: error))
        }
    }

    func save(vehicle: Vehicle, declaredTypicalDistance: Distance? = nil) throws {
        let existing = try fetch(StoredVehicle.self).first { $0.id == vehicle.id }
        if let existing {
            try existing.apply(vehicle, declaredTypicalDistance: declaredTypicalDistance ?? existing.declaredTypicalDistance)
        } else {
            context.insert(try StoredVehicle.make(from: vehicle, declaredTypicalDistance: declaredTypicalDistance))
        }
        try commit()
    }

    /// Deletes a vehicle and everything that belongs to it.
    ///
    /// Returns the attachment identifiers that are now unreferenced so the
    /// caller can remove the files too — a deleted vehicle must not leave
    /// receipts on disk.
    @discardableResult
    func deleteVehicle(id: UUID) throws -> [UUID] {
        var releasedAttachments: [UUID] = []
        var problems: [StoreProblem] = []

        // Anything another vehicle's record still points at stays. A restored
        // backup can legitimately share an attachment between records.
        var stillReferenced = Set<UUID>()
        for record in try fetch(StoredServiceRecord.self) where record.vehicleID != id {
            stillReferenced.formUnion(record.toDomain(problems: &problems).attachmentIDs)
        }
        for vehicle in try fetch(StoredVehicle.self) where vehicle.id != id {
            if let photo = vehicle.photoAttachmentID { stillReferenced.insert(photo) }
        }

        for record in try fetch(StoredServiceRecord.self) where record.vehicleID == id {
            releasedAttachments.append(contentsOf: record.toDomain(problems: &problems).attachmentIDs)
            context.delete(record)
        }
        for reading in try fetch(StoredOdometerReading.self) where reading.vehicleID == id {
            context.delete(reading)
        }
        for item in try fetch(StoredPlanItem.self) where item.vehicleID == id {
            context.delete(item)
        }
        for appointment in try fetch(StoredAppointment.self) where appointment.vehicleID == id {
            context.delete(appointment)
        }
        for specification in try fetch(StoredSpecification.self) where specification.vehicleID == id {
            context.delete(specification)
        }
        for vehicle in try fetch(StoredVehicle.self) where vehicle.id == id {
            if let photo = vehicle.photoAttachmentID { releasedAttachments.append(photo) }
            context.delete(vehicle)
        }

        let orphanedAttachments = releasedAttachments.filter { !stillReferenced.contains($0) }
        for attachmentID in orphanedAttachments {
            for attachment in try fetch(StoredAttachment.self) where attachment.id == attachmentID {
                context.delete(attachment)
            }
        }

        if let settings = try fetch(StoredSettings.self).first, settings.selectedVehicleID == id {
            settings.selectedVehicleID = try fetch(StoredVehicle.self).first { $0.id != id }?.id
        }

        try commit()
        return orphanedAttachments
    }

    func save(reading: OdometerReading) throws {
        if let existing = try fetch(StoredOdometerReading.self).first(where: { $0.id == reading.id }) {
            existing.apply(reading)
        } else {
            context.insert(StoredOdometerReading.make(from: reading))
        }
        try commit()
    }

    func deleteReading(id: UUID) throws {
        for reading in try fetch(StoredOdometerReading.self) where reading.id == id {
            context.delete(reading)
        }
        try commit()
    }

    func save(planItem: MaintenancePlanItem) throws {
        if let existing = try fetch(StoredPlanItem.self).first(where: { $0.id == planItem.id }) {
            try existing.apply(planItem)
        } else {
            context.insert(try StoredPlanItem.make(from: planItem))
        }
        try commit()
    }

    func save(planItems: [MaintenancePlanItem]) throws {
        let existing = try fetch(StoredPlanItem.self)
        for item in planItems {
            if let match = existing.first(where: { $0.id == item.id }) {
                try match.apply(item)
            } else {
                context.insert(try StoredPlanItem.make(from: item))
            }
        }
        try commit()
    }

    func deletePlanItem(id: UUID) throws {
        for item in try fetch(StoredPlanItem.self) where item.id == id {
            context.delete(item)
        }
        try commit()
    }

    func save(serviceRecord: ServiceRecord) throws {
        if let existing = try fetch(StoredServiceRecord.self).first(where: { $0.id == serviceRecord.id }) {
            try existing.apply(serviceRecord)
        } else {
            context.insert(try StoredServiceRecord.make(from: serviceRecord))
        }
        try commit()
    }

    /// Deletes a service record and reports attachments no other record uses.
    @discardableResult
    func deleteServiceRecord(id: UUID) throws -> [UUID] {
        var problems: [StoreProblem] = []
        let all = try fetch(StoredServiceRecord.self)
        guard let target = all.first(where: { $0.id == id }) else { return [] }

        let attachmentIDs = target.toDomain(problems: &problems).attachmentIDs
        context.delete(target)

        var stillReferenced = Set<UUID>()
        for record in all where record.id != id {
            stillReferenced.formUnion(record.toDomain(problems: &problems).attachmentIDs)
        }
        for vehicle in try fetch(StoredVehicle.self) {
            if let photo = vehicle.photoAttachmentID { stillReferenced.insert(photo) }
        }

        let orphaned = attachmentIDs.filter { !stillReferenced.contains($0) }
        for attachmentID in orphaned {
            for attachment in try fetch(StoredAttachment.self) where attachment.id == attachmentID {
                context.delete(attachment)
            }
        }

        try commit()
        return orphaned
    }

    func save(specification: Specification, for vehicleID: UUID) throws {
        let existing = try fetch(StoredSpecification.self).first {
            $0.vehicleID == vehicleID && $0.kindRaw == specification.kind.rawValue
        }
        if let existing {
            try existing.apply(specification)
        } else {
            context.insert(try StoredSpecification.make(vehicleID: vehicleID, specification: specification))
        }
        try commit()
    }

    func deleteSpecification(kind: SpecificationKind, for vehicleID: UUID) throws {
        for specification in try fetch(StoredSpecification.self)
        where specification.vehicleID == vehicleID && specification.kindRaw == kind.rawValue {
            context.delete(specification)
        }
        try commit()
    }

    func registerAttachment(_ metadata: AttachmentMetadata) throws {
        if let existing = try fetch(StoredAttachment.self).first(where: { $0.id == metadata.id }) {
            existing.fileName = metadata.fileName
            existing.contentType = metadata.contentType
            existing.byteCount = metadata.byteCount
            existing.caption = metadata.caption
        } else {
            context.insert(
                StoredAttachment(
                    id: metadata.id,
                    fileName: metadata.fileName,
                    contentType: metadata.contentType,
                    byteCount: metadata.byteCount,
                    createdAt: metadata.createdAt,
                    caption: metadata.caption
                )
            )
        }
        try commit()
    }

    func deleteAttachment(id: UUID) throws {
        for attachment in try fetch(StoredAttachment.self) where attachment.id == id {
            context.delete(attachment)
        }
        try commit()
    }

    func save(appointment: Appointment) throws {
        if let existing = try fetch(StoredAppointment.self).first(where: { $0.id == appointment.id }) {
            try existing.apply(appointment)
        } else {
            context.insert(try StoredAppointment.make(from: appointment))
        }
        try commit()
    }

    func deleteAppointment(id: UUID) throws {
        for appointment in try fetch(StoredAppointment.self) where appointment.id == id {
            context.delete(appointment)
        }
        try commit()
    }

    func save(settings: AppSettings) throws {
        let row = try fetch(StoredSettings.self).first
        let data = try StoreCoding.encode(settings.reminders)
        let preferencesData = try StoreCoding.encode(settings.preferences)
        if let row {
            row.selectedVehicleID = settings.selectedVehicleID
            row.hasCompletedOnboarding = settings.hasCompletedOnboarding
            row.catalogVersionLastSeen = settings.catalogVersionLastSeen
            row.reminderSettingsData = data
            row.preferencesData = preferencesData
        } else {
            context.insert(
                StoredSettings(
                    id: StoredSettings.singletonID,
                    selectedVehicleID: settings.selectedVehicleID,
                    hasCompletedOnboarding: settings.hasCompletedOnboarding,
                    catalogVersionLastSeen: settings.catalogVersionLastSeen,
                    reminderSettingsData: data,
                    preferencesData: preferencesData
                )
            )
        }
        try commit()
    }

    // MARK: - Bulk operations

    /// Removes every record. Used by "delete all data" and by a full restore.
    ///
    /// Returns the attachment identifiers whose files should now be deleted.
    @discardableResult
    func deleteEverything(keepSettings: Bool = false) throws -> [UUID] {
        let attachmentIDs = try fetch(StoredAttachment.self).map(\.id)

        for record in try fetch(StoredServiceRecord.self) { context.delete(record) }
        for reading in try fetch(StoredOdometerReading.self) { context.delete(reading) }
        for item in try fetch(StoredPlanItem.self) { context.delete(item) }
        for specification in try fetch(StoredSpecification.self) { context.delete(specification) }
        for attachment in try fetch(StoredAttachment.self) { context.delete(attachment) }
        for appointment in try fetch(StoredAppointment.self) { context.delete(appointment) }
        for vehicle in try fetch(StoredVehicle.self) { context.delete(vehicle) }
        if !keepSettings {
            for settings in try fetch(StoredSettings.self) { context.delete(settings) }
        } else if let settings = try fetch(StoredSettings.self).first {
            settings.selectedVehicleID = nil
        }

        try commit()
        return attachmentIDs
    }

    /// Removes only the fictional sample content.
    @discardableResult
    func deleteDemoContent() throws -> [UUID] {
        var orphaned: [UUID] = []
        for vehicle in try fetch(StoredVehicle.self) where vehicle.isDemo {
            orphaned.append(contentsOf: try deleteVehicle(id: vehicle.id))
        }
        return orphaned
    }

    /// Applies a validated backup in one transaction.
    ///
    /// The apply set has already been checked and pruned, so this method only
    /// writes. A failure at any point rolls the whole thing back rather than
    /// leaving half a garage behind.
    func apply(_ applySet: BackupApplySet, attachmentWriter: (BackupAttachment) throws -> AttachmentMetadata) throws {
        do {
            if applySet.removesExistingData {
                for record in try fetch(StoredServiceRecord.self) { context.delete(record) }
                for reading in try fetch(StoredOdometerReading.self) { context.delete(reading) }
                for item in try fetch(StoredPlanItem.self) { context.delete(item) }
                for specification in try fetch(StoredSpecification.self) { context.delete(specification) }
                for attachment in try fetch(StoredAttachment.self) { context.delete(attachment) }
                for appointment in try fetch(StoredAppointment.self) { context.delete(appointment) }
                for vehicle in try fetch(StoredVehicle.self) { context.delete(vehicle) }
            }

            for attachment in applySet.attachments {
                let metadata = try attachmentWriter(attachment)
                context.insert(
                    StoredAttachment(
                        id: metadata.id,
                        fileName: metadata.fileName,
                        contentType: metadata.contentType,
                        byteCount: metadata.byteCount,
                        createdAt: metadata.createdAt,
                        caption: metadata.caption
                    )
                )
            }
            for vehicle in applySet.vehicles {
                context.insert(try StoredVehicle.make(from: vehicle, declaredTypicalDistance: nil))
            }
            for reading in applySet.readings {
                context.insert(StoredOdometerReading.make(from: reading))
            }
            for item in applySet.planItems {
                context.insert(try StoredPlanItem.make(from: item))
            }
            for record in applySet.serviceRecords {
                context.insert(try StoredServiceRecord.make(from: record))
            }
            for specification in applySet.specifications {
                context.insert(
                    try StoredSpecification.make(
                        vehicleID: specification.vehicleID,
                        specification: specification.specification
                    )
                )
            }

            if let settings = applySet.settings {
                let row = try fetch(StoredSettings.self).first
                let data = try StoreCoding.encode(settings.reminderSettings)
                if let row {
                    row.selectedVehicleID = settings.selectedVehicleID
                    row.catalogVersionLastSeen = settings.catalogVersion
                    row.reminderSettingsData = data
                    row.hasCompletedOnboarding = true
                } else {
                    context.insert(
                        StoredSettings(
                            id: StoredSettings.singletonID,
                            selectedVehicleID: settings.selectedVehicleID,
                            hasCompletedOnboarding: true,
                            catalogVersionLastSeen: settings.catalogVersion,
                            reminderSettingsData: data
                        )
                    )
                }
            }

            try commit()
        } catch {
            context.rollback()
            throw StoreError.saveFailed(String(describing: error))
        }
    }
}
