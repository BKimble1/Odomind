import Foundation
import SwiftData
import OdomindCore

// Persistence models.
//
// Two deliberate choices keep this layer small and predictable:
//
// 1. No SwiftData relationships. Records carry a plain `vehicleID` and the store
//    joins in Swift. A household's garage is a handful of vehicles and a few
//    hundred records, so the cost is nil, and it removes a whole class of
//    inverse-relationship and delete-rule surprises.
//
// 2. Rich value types — configuration, schedule rules, provenance — are stored
//    as JSON produced by the same `Codable` conformances the backup format
//    uses. Scalars that the app actually sorts or filters on stay native
//    columns. This means the domain types in OdomindCore remain the single
//    definition of the data, and a schema change is a Codable change with a
//    version bump rather than a store migration for every enum case.

@Model
final class StoredVehicle {
    var id: UUID = UUID()
    var nickname: String?
    var displayUnitRaw: String = DistanceUnit.miles.rawValue
    var acquiredOn: Date?
    var inServiceOn: Date?
    var photoAttachmentID: UUID?
    var isDemo: Bool = false
    var createdAt: Date = Date()
    var sortIndex: Int = 0

    /// `VehicleIdentity` as JSON.
    var identityData: Data = Data()
    /// `VehicleConfiguration` as JSON.
    var configurationData: Data = Data()
    /// `[OdometerReplacement]` as JSON.
    var replacementsData: Data = Data()

    /// Owner's stated typical distance per month, used for estimates when their
    /// readings are too sparse.
    var declaredTypicalDistanceAmount: Int?
    var declaredTypicalDistanceUnitRaw: String?

    init(
        id: UUID,
        nickname: String?,
        displayUnitRaw: String,
        acquiredOn: Date?,
        inServiceOn: Date?,
        photoAttachmentID: UUID?,
        isDemo: Bool,
        createdAt: Date,
        sortIndex: Int,
        identityData: Data,
        configurationData: Data,
        replacementsData: Data,
        declaredTypicalDistanceAmount: Int?,
        declaredTypicalDistanceUnitRaw: String?
    ) {
        self.id = id
        self.nickname = nickname
        self.displayUnitRaw = displayUnitRaw
        self.acquiredOn = acquiredOn
        self.inServiceOn = inServiceOn
        self.photoAttachmentID = photoAttachmentID
        self.isDemo = isDemo
        self.createdAt = createdAt
        self.sortIndex = sortIndex
        self.identityData = identityData
        self.configurationData = configurationData
        self.replacementsData = replacementsData
        self.declaredTypicalDistanceAmount = declaredTypicalDistanceAmount
        self.declaredTypicalDistanceUnitRaw = declaredTypicalDistanceUnitRaw
    }
}

@Model
final class StoredOdometerReading {
    var id: UUID = UUID()
    var vehicleID: UUID = UUID()
    var recordedOn: Date = Date()
    var amount: Int = 0
    var unitRaw: String = DistanceUnit.miles.rawValue
    var sourceRaw: String = OdometerSource.manualEntry.rawValue
    var note: String?

    init(
        id: UUID,
        vehicleID: UUID,
        recordedOn: Date,
        amount: Int,
        unitRaw: String,
        sourceRaw: String,
        note: String?
    ) {
        self.id = id
        self.vehicleID = vehicleID
        self.recordedOn = recordedOn
        self.amount = amount
        self.unitRaw = unitRaw
        self.sourceRaw = sourceRaw
        self.note = note
    }
}

@Model
final class StoredPlanItem {
    var id: UUID = UUID()
    var vehicleID: UUID = UUID()
    var definitionID: String = ""
    var title: String = ""
    var summaryText: String = ""
    var categoryRaw: String = MaintenanceCategory.other.rawValue
    var actionRaw: String = ServiceAction.replace.rawValue
    var isEnabled: Bool = true
    var isCustom: Bool = false
    var snoozedUntil: Date?
    var notes: String?
    var safetyNote: String?
    var createdAt: Date = Date()

    /// `ScheduleRule?` as JSON (empty when absent).
    var catalogRuleData: Data = Data()
    /// `Provenance?` as JSON.
    var catalogProvenanceData: Data = Data()
    /// `ScheduleRule?` as JSON — the owner's override, never written by a
    /// catalog update.
    var ownerRuleData: Data = Data()
    /// `RuleChangeProposal?` as JSON.
    var pendingProposalData: Data = Data()
    /// `HistoryBaseline` as JSON.
    var baselineData: Data = Data()
    /// `DueSoonThreshold` as JSON.
    var thresholdData: Data = Data()
    /// `ReminderPreference` as JSON.
    var reminderData: Data = Data()
    /// `[SpecificationKind]` as JSON.
    var relatedSpecificationsData: Data = Data()

    init(
        id: UUID,
        vehicleID: UUID,
        definitionID: String,
        title: String,
        summaryText: String,
        categoryRaw: String,
        actionRaw: String,
        isEnabled: Bool,
        isCustom: Bool,
        snoozedUntil: Date?,
        notes: String?,
        safetyNote: String?,
        createdAt: Date,
        catalogRuleData: Data,
        catalogProvenanceData: Data,
        ownerRuleData: Data,
        pendingProposalData: Data,
        baselineData: Data,
        thresholdData: Data,
        reminderData: Data,
        relatedSpecificationsData: Data
    ) {
        self.id = id
        self.vehicleID = vehicleID
        self.definitionID = definitionID
        self.title = title
        self.summaryText = summaryText
        self.categoryRaw = categoryRaw
        self.actionRaw = actionRaw
        self.isEnabled = isEnabled
        self.isCustom = isCustom
        self.snoozedUntil = snoozedUntil
        self.notes = notes
        self.safetyNote = safetyNote
        self.createdAt = createdAt
        self.catalogRuleData = catalogRuleData
        self.catalogProvenanceData = catalogProvenanceData
        self.ownerRuleData = ownerRuleData
        self.pendingProposalData = pendingProposalData
        self.baselineData = baselineData
        self.thresholdData = thresholdData
        self.reminderData = reminderData
        self.relatedSpecificationsData = relatedSpecificationsData
    }
}

@Model
final class StoredServiceRecord {
    var id: UUID = UUID()
    var vehicleID: UUID = UUID()
    var performedOn: Date = Date()
    var odometerAmount: Int?
    var odometerUnitRaw: String?
    /// Stored as a string so the exact decimal survives; `Decimal` round-trips
    /// through its own description without binary floating point.
    var totalCostAmount: String?
    var totalCostCurrency: String?
    var isDemo: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var notes: String?

    /// `[ServiceLineItem]` as JSON.
    var itemsData: Data = Data()
    /// `ServicePerformer` as JSON.
    var performerData: Data = Data()
    /// `[UUID]` as JSON.
    var attachmentIDsData: Data = Data()

    init(
        id: UUID,
        vehicleID: UUID,
        performedOn: Date,
        odometerAmount: Int?,
        odometerUnitRaw: String?,
        totalCostAmount: String?,
        totalCostCurrency: String?,
        isDemo: Bool,
        createdAt: Date,
        updatedAt: Date,
        notes: String?,
        itemsData: Data,
        performerData: Data,
        attachmentIDsData: Data
    ) {
        self.id = id
        self.vehicleID = vehicleID
        self.performedOn = performedOn
        self.odometerAmount = odometerAmount
        self.odometerUnitRaw = odometerUnitRaw
        self.totalCostAmount = totalCostAmount
        self.totalCostCurrency = totalCostCurrency
        self.isDemo = isDemo
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.notes = notes
        self.itemsData = itemsData
        self.performerData = performerData
        self.attachmentIDsData = attachmentIDsData
    }
}

@Model
final class StoredSpecification {
    var id: UUID = UUID()
    var vehicleID: UUID = UUID()
    var kindRaw: String = ""
    var updatedAt: Date = Date()
    /// `Specification` as JSON.
    var specificationData: Data = Data()

    init(id: UUID, vehicleID: UUID, kindRaw: String, updatedAt: Date, specificationData: Data) {
        self.id = id
        self.vehicleID = vehicleID
        self.kindRaw = kindRaw
        self.updatedAt = updatedAt
        self.specificationData = specificationData
    }
}

@Model
final class StoredAttachment {
    var id: UUID = UUID()
    /// Name of the file inside the managed attachments directory.
    var fileName: String = ""
    var contentType: String = "application/octet-stream"
    var byteCount: Int = 0
    var createdAt: Date = Date()
    /// Optional caption the owner typed.
    var caption: String?

    init(id: UUID, fileName: String, contentType: String, byteCount: Int, createdAt: Date, caption: String?) {
        self.id = id
        self.fileName = fileName
        self.contentType = contentType
        self.byteCount = byteCount
        self.createdAt = createdAt
        self.caption = caption
    }
}

@Model
final class StoredSettings {
    /// There is exactly one settings row; this constant identifies it.
    var id: UUID = StoredSettings.singletonID
    var selectedVehicleID: UUID?
    var hasCompletedOnboarding: Bool = false
    var catalogVersionLastSeen: String?
    /// `ReminderSettings` as JSON.
    var reminderSettingsData: Data = Data()

    static let singletonID = UUID(uuidString: "0D0E0D0E-0000-4000-8000-000000000001")!

    init(
        id: UUID,
        selectedVehicleID: UUID?,
        hasCompletedOnboarding: Bool,
        catalogVersionLastSeen: String?,
        reminderSettingsData: Data
    ) {
        self.id = id
        self.selectedVehicleID = selectedVehicleID
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.catalogVersionLastSeen = catalogVersionLastSeen
        self.reminderSettingsData = reminderSettingsData
    }
}
