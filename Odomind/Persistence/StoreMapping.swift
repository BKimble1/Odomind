import Foundation
import OdomindCore

// Mapping between persistence models and the domain value types.
//
// Every conversion is explicit. Nothing in the app reads a `Stored*` object
// directly; screens and the scheduling engine only ever see domain values, so a
// change to the store cannot leak into the UI.

extension StoredVehicle {
    static func make(from vehicle: Vehicle, declaredTypicalDistance: Distance?) throws -> StoredVehicle {
        StoredVehicle(
            id: vehicle.id,
            nickname: vehicle.nickname,
            displayUnitRaw: vehicle.displayUnit.rawValue,
            acquiredOn: vehicle.acquiredOn,
            inServiceOn: vehicle.inServiceOn,
            photoAttachmentID: vehicle.photoAttachmentID,
            isDemo: vehicle.isDemo,
            createdAt: vehicle.createdAt,
            sortIndex: vehicle.sortIndex,
            identityData: try StoreCoding.encode(vehicle.identity),
            configurationData: try StoreCoding.encode(vehicle.configuration),
            replacementsData: try StoreCoding.encode(vehicle.odometerReplacements),
            declaredTypicalDistanceAmount: declaredTypicalDistance?.amount,
            declaredTypicalDistanceUnitRaw: declaredTypicalDistance?.unit.rawValue
        )
    }

    func apply(_ vehicle: Vehicle, declaredTypicalDistance: Distance?) throws {
        nickname = vehicle.nickname
        displayUnitRaw = vehicle.displayUnit.rawValue
        acquiredOn = vehicle.acquiredOn
        inServiceOn = vehicle.inServiceOn
        photoAttachmentID = vehicle.photoAttachmentID
        isDemo = vehicle.isDemo
        sortIndex = vehicle.sortIndex
        identityData = try StoreCoding.encode(vehicle.identity)
        configurationData = try StoreCoding.encode(vehicle.configuration)
        replacementsData = try StoreCoding.encode(vehicle.odometerReplacements)
        declaredTypicalDistanceAmount = declaredTypicalDistance?.amount
        declaredTypicalDistanceUnitRaw = declaredTypicalDistance?.unit.rawValue
    }

    func toDomain(problems: inout [StoreProblem]) -> Vehicle {
        let identity = StoreCoding.decodeOrFallback(
            VehicleIdentity.self,
            from: identityData,
            fallback: VehicleIdentity(make: "Unknown", model: "Vehicle"),
            context: "Vehicle \(id) identity",
            problems: &problems
        )
        let configuration = StoreCoding.decodeOrFallback(
            VehicleConfiguration.self,
            from: configurationData,
            fallback: VehicleConfiguration(),
            context: "Vehicle \(id) configuration",
            problems: &problems
        )
        let replacements = StoreCoding.decodeOrFallback(
            [OdometerReplacement].self,
            from: replacementsData,
            fallback: [],
            context: "Vehicle \(id) odometer replacements",
            problems: &problems
        )
        return Vehicle(
            id: id,
            nickname: nickname,
            identity: identity,
            configuration: configuration,
            displayUnit: DistanceUnit(rawValue: displayUnitRaw) ?? .miles,
            acquiredOn: acquiredOn,
            inServiceOn: inServiceOn,
            odometerReplacements: replacements,
            photoAttachmentID: photoAttachmentID,
            isDemo: isDemo,
            createdAt: createdAt,
            sortIndex: sortIndex
        )
    }

    var declaredTypicalDistance: Distance? {
        guard let amount = declaredTypicalDistanceAmount,
              let raw = declaredTypicalDistanceUnitRaw,
              let unit = DistanceUnit(rawValue: raw) else { return nil }
        return Distance(amount, unit)
    }
}

extension StoredOdometerReading {
    static func make(from reading: OdometerReading) -> StoredOdometerReading {
        StoredOdometerReading(
            id: reading.id,
            vehicleID: reading.vehicleID,
            recordedOn: reading.recordedOn,
            amount: reading.value.amount,
            unitRaw: reading.value.unit.rawValue,
            sourceRaw: reading.source.rawValue,
            note: reading.note
        )
    }

    func apply(_ reading: OdometerReading) {
        vehicleID = reading.vehicleID
        recordedOn = reading.recordedOn
        amount = reading.value.amount
        unitRaw = reading.value.unit.rawValue
        sourceRaw = reading.source.rawValue
        note = reading.note
    }

    func toDomain() -> OdometerReading {
        OdometerReading(
            id: id,
            vehicleID: vehicleID,
            recordedOn: recordedOn,
            value: Distance(amount, DistanceUnit(rawValue: unitRaw) ?? .miles),
            source: OdometerSource(rawValue: sourceRaw) ?? .manualEntry,
            note: note
        )
    }
}

extension StoredPlanItem {
    static func make(from item: MaintenancePlanItem) throws -> StoredPlanItem {
        StoredPlanItem(
            id: item.id,
            vehicleID: item.vehicleID,
            definitionID: item.definitionID,
            title: item.title,
            summaryText: item.purpose,
            categoryRaw: item.category.rawValue,
            actionRaw: item.action.rawValue,
            isEnabled: item.isEnabled,
            isCustom: item.isCustom,
            snoozedUntil: item.snoozedUntil,
            notes: item.notes,
            safetyNote: item.safetyNote,
            createdAt: item.createdAt,
            catalogRuleData: try StoreCoding.encodeOptional(item.catalogRule),
            catalogProvenanceData: try StoreCoding.encodeOptional(item.catalogProvenance),
            ownerRuleData: try StoreCoding.encodeOptional(item.ownerRule),
            pendingProposalData: try StoreCoding.encodeOptional(item.pendingProposal),
            baselineData: try StoreCoding.encode(item.baseline),
            thresholdData: try StoreCoding.encode(item.dueSoonThreshold),
            reminderData: try StoreCoding.encode(item.reminder),
            relatedSpecificationsData: try StoreCoding.encode(item.relatedSpecifications)
        )
    }

    func apply(_ item: MaintenancePlanItem) throws {
        vehicleID = item.vehicleID
        definitionID = item.definitionID
        title = item.title
        summaryText = item.purpose
        categoryRaw = item.category.rawValue
        actionRaw = item.action.rawValue
        isEnabled = item.isEnabled
        isCustom = item.isCustom
        snoozedUntil = item.snoozedUntil
        notes = item.notes
        safetyNote = item.safetyNote
        catalogRuleData = try StoreCoding.encodeOptional(item.catalogRule)
        catalogProvenanceData = try StoreCoding.encodeOptional(item.catalogProvenance)
        ownerRuleData = try StoreCoding.encodeOptional(item.ownerRule)
        pendingProposalData = try StoreCoding.encodeOptional(item.pendingProposal)
        baselineData = try StoreCoding.encode(item.baseline)
        thresholdData = try StoreCoding.encode(item.dueSoonThreshold)
        reminderData = try StoreCoding.encode(item.reminder)
        relatedSpecificationsData = try StoreCoding.encode(item.relatedSpecifications)
    }

    func toDomain(problems: inout [StoreProblem]) -> MaintenancePlanItem {
        MaintenancePlanItem(
            id: id,
            vehicleID: vehicleID,
            definitionID: definitionID,
            title: title,
            purpose: summaryText,
            category: MaintenanceCategory(rawValue: categoryRaw) ?? .other,
            action: ServiceAction(rawValue: actionRaw) ?? .replace,
            catalogRule: StoreCoding.decodeOptionalOrFallback(
                ScheduleRule.self,
                from: catalogRuleData,
                context: "Task \(title) catalog schedule",
                problems: &problems
            ),
            catalogProvenance: StoreCoding.decodeOptionalOrFallback(
                Provenance.self,
                from: catalogProvenanceData,
                context: "Task \(title) provenance",
                problems: &problems
            ),
            ownerRule: StoreCoding.decodeOptionalOrFallback(
                ScheduleRule.self,
                from: ownerRuleData,
                context: "Task \(title) custom schedule",
                problems: &problems
            ),
            pendingProposal: StoreCoding.decodeOptionalOrFallback(
                RuleChangeProposal.self,
                from: pendingProposalData,
                context: "Task \(title) proposed change",
                problems: &problems
            ),
            baseline: StoreCoding.decodeOrFallback(
                HistoryBaseline.self,
                from: baselineData,
                fallback: .notProvided,
                context: "Task \(title) history",
                problems: &problems
            ),
            isEnabled: isEnabled,
            snoozedUntil: snoozedUntil,
            dueSoonThreshold: StoreCoding.decodeOrFallback(
                DueSoonThreshold.self,
                from: thresholdData,
                fallback: .standard,
                context: "Task \(title) due-soon window",
                problems: &problems
            ),
            reminder: StoreCoding.decodeOrFallback(
                ReminderPreference.self,
                from: reminderData,
                fallback: .disabled,
                context: "Task \(title) reminder",
                problems: &problems
            ),
            relatedSpecifications: StoreCoding.decodeOrFallback(
                [SpecificationKind].self,
                from: relatedSpecificationsData,
                fallback: [],
                context: "Task \(title) related specifications",
                problems: &problems
            ),
            notes: notes,
            isCustom: isCustom,
            safetyNote: safetyNote,
            createdAt: createdAt
        )
    }
}

extension StoredServiceRecord {
    static func make(from record: ServiceRecord) throws -> StoredServiceRecord {
        StoredServiceRecord(
            id: record.id,
            vehicleID: record.vehicleID,
            performedOn: record.performedOn,
            odometerAmount: record.odometer?.amount,
            odometerUnitRaw: record.odometer?.unit.rawValue,
            totalCostAmount: record.totalCost.map { "\($0.amount)" },
            totalCostCurrency: record.totalCost?.currencyCode,
            isDemo: record.isDemo,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            notes: record.notes,
            itemsData: try StoreCoding.encode(record.items),
            performerData: try StoreCoding.encode(record.performer),
            attachmentIDsData: try StoreCoding.encode(record.attachmentIDs)
        )
    }

    func apply(_ record: ServiceRecord) throws {
        vehicleID = record.vehicleID
        performedOn = record.performedOn
        odometerAmount = record.odometer?.amount
        odometerUnitRaw = record.odometer?.unit.rawValue
        totalCostAmount = record.totalCost.map { "\($0.amount)" }
        totalCostCurrency = record.totalCost?.currencyCode
        isDemo = record.isDemo
        updatedAt = record.updatedAt
        notes = record.notes
        itemsData = try StoreCoding.encode(record.items)
        performerData = try StoreCoding.encode(record.performer)
        attachmentIDsData = try StoreCoding.encode(record.attachmentIDs)
    }

    func toDomain(problems: inout [StoreProblem]) -> ServiceRecord {
        var odometer: Distance?
        if let odometerAmount, let raw = odometerUnitRaw, let unit = DistanceUnit(rawValue: raw) {
            odometer = Distance(odometerAmount, unit)
        }

        var cost: Money?
        if let totalCostAmount, let totalCostCurrency {
            if let decimal = Decimal(string: totalCostAmount) {
                cost = Money(amount: decimal, currencyCode: totalCostCurrency)
            } else {
                problems.append(
                    StoreProblem(
                        context: "Service record \(id) cost",
                        message: "Could not read the stored amount '\(totalCostAmount)'."
                    )
                )
            }
        }

        return ServiceRecord(
            id: id,
            vehicleID: vehicleID,
            performedOn: performedOn,
            odometer: odometer,
            items: StoreCoding.decodeOrFallback(
                [ServiceLineItem].self,
                from: itemsData,
                fallback: [],
                context: "Service record \(id) items",
                problems: &problems
            ),
            totalCost: cost,
            performer: StoreCoding.decodeOrFallback(
                ServicePerformer.self,
                from: performerData,
                fallback: .doItYourself,
                context: "Service record \(id) performer",
                problems: &problems
            ),
            notes: notes,
            attachmentIDs: StoreCoding.decodeOrFallback(
                [UUID].self,
                from: attachmentIDsData,
                fallback: [],
                context: "Service record \(id) attachments",
                problems: &problems
            ),
            isDemo: isDemo,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

extension StoredSpecification {
    static func make(vehicleID: UUID, specification: Specification) throws -> StoredSpecification {
        StoredSpecification(
            id: specification.id,
            vehicleID: vehicleID,
            kindRaw: specification.kind.rawValue,
            updatedAt: specification.updatedAt,
            specificationData: try StoreCoding.encode(specification)
        )
    }

    func apply(_ specification: Specification) throws {
        kindRaw = specification.kind.rawValue
        updatedAt = specification.updatedAt
        specificationData = try StoreCoding.encode(specification)
    }

    func toDomain(problems: inout [StoreProblem]) -> Specification? {
        StoreCoding.decodeOptionalOrFallback(
            Specification.self,
            from: specificationData,
            context: "Specification \(kindRaw)",
            problems: &problems
        )
    }
}
