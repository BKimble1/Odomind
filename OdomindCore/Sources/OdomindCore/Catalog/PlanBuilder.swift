import Foundation

/// A task the catalog offers for a particular vehicle, with the schedule and
/// provenance already resolved.
public struct SuggestedTask: Hashable, Sendable, Identifiable {
    public var id: String { definition.id }
    public var definition: MaintenanceTaskDefinition
    public var rule: ScheduleRule?
    public var provenance: Provenance
    public var applicability: TaskApplicability
    /// Whether onboarding pre-selects this task.
    public var isRecommendedByDefault: Bool
    /// Where the schedule came from, for the source line under the task.
    public var sourceNote: String?

    public init(
        definition: MaintenanceTaskDefinition,
        rule: ScheduleRule?,
        provenance: Provenance,
        applicability: TaskApplicability,
        isRecommendedByDefault: Bool,
        sourceNote: String? = nil
    ) {
        self.definition = definition
        self.rule = rule
        self.provenance = provenance
        self.applicability = applicability
        self.isRecommendedByDefault = isRecommendedByDefault
        self.sourceNote = sourceNote
    }

    public var isVehicleSpecific: Bool { provenance.origin == .manufacturerSourced }
}

/// One change a catalog update wants to make, shown to the owner before it is
/// applied.
public struct CatalogChange: Hashable, Sendable, Identifiable {
    public enum Kind: String, Sendable, Hashable {
        case newScheduleProposed
        case scheduleChanged
        case newTaskAvailable
    }

    public var id: String { "\(kind.rawValue)|\(definitionID)" }
    public var kind: Kind
    public var definitionID: String
    public var title: String
    public var detail: String

    public init(kind: Kind, definitionID: String, title: String, detail: String) {
        self.kind = kind
        self.definitionID = definitionID
        self.title = title
        self.detail = detail
    }
}

/// Builds and updates a vehicle's maintenance plan from the catalog.
public enum PlanBuilder {

    /// Every task the catalog can offer this vehicle.
    ///
    /// Tasks the configuration rules out are dropped entirely. Tasks that depend
    /// on something unconfirmed are kept and flagged, so the owner is asked
    /// rather than quietly given or denied a service.
    public static func suggestions(
        for vehicle: Vehicle,
        catalog: MaintenanceCatalog,
        includeAdvanced: Bool = true
    ) -> [SuggestedTask] {
        let profile = catalog.bestProfile(for: vehicle.identity, configuration: vehicle.configuration)

        return catalog.taskDefinitions.compactMap { definition in
            if definition.isAdvanced, !includeAdvanced { return nil }

            let applicability = definition.applicability.evaluate(for: vehicle.configuration)
            if case .doesNotApply = applicability { return nil }

            let resolved = resolveRule(for: definition, vehicle: vehicle, profile: profile, catalog: catalog)

            return SuggestedTask(
                definition: definition,
                rule: resolved.rule,
                provenance: resolved.provenance,
                applicability: applicability,
                isRecommendedByDefault: !definition.isAdvanced && applicability.isApplicable && resolved.rule != nil,
                sourceNote: resolved.sourceNote
            )
        }
    }

    /// The schedule for one task on one vehicle.
    ///
    /// A vehicle profile beats the general template, and a schedule published
    /// for the owner's chosen usage profile beats an unqualified one.
    static func resolveRule(
        for definition: MaintenanceTaskDefinition,
        vehicle: Vehicle,
        profile: VehicleProfile?,
        catalog: MaintenanceCatalog
    ) -> (rule: ScheduleRule?, provenance: Provenance, sourceNote: String?) {
        if let profile {
            let candidates = profile.scheduleRules.filter { $0.definitionID == definition.id }
            let usage = vehicle.configuration.usageProfile

            let exact = candidates.first { $0.usageProfile == usage && usage != .unspecified }
            let general = candidates.first { $0.usageProfile == nil }

            if let chosen = exact ?? general {
                let source = catalog.source(id: chosen.sourceID)
                return (chosen.rule, chosen.provenance, source?.name)
            }
        }

        if let rule = definition.defaultRule {
            let provenance = definition.defaultRuleProvenance ?? Provenance(origin: .generalTemplate)
            return (rule, provenance, provenance.attribution?.sourceName)
        }

        return (nil, Provenance(origin: .generalTemplate), nil)
    }

    /// Creates a plan item for a chosen task.
    public static func makePlanItem(
        from suggestion: SuggestedTask,
        vehicle: Vehicle,
        baseline: HistoryBaseline = .notProvided,
        dueSoonThreshold: DueSoonThreshold? = nil,
        createdAt: Date = Date()
    ) -> MaintenancePlanItem {
        MaintenancePlanItem(
            vehicleID: vehicle.id,
            definitionID: suggestion.definition.id,
            title: suggestion.definition.title,
            purpose: suggestion.definition.purpose,
            category: suggestion.definition.category,
            action: suggestion.definition.action,
            catalogRule: suggestion.rule,
            catalogProvenance: suggestion.provenance,
            baseline: baseline,
            dueSoonThreshold: dueSoonThreshold ?? defaultThreshold(for: vehicle),
            relatedSpecifications: suggestion.definition.relatedSpecifications,
            safetyNote: suggestion.definition.safetyNote,
            createdAt: createdAt
        )
    }

    /// The due-soon window, expressed in the vehicle's own unit.
    public static func defaultThreshold(for vehicle: Vehicle) -> DueSoonThreshold {
        switch vehicle.displayUnit {
        case .miles:
            return DueSoonThreshold(distance: Distance(500, .miles), days: 30)
        case .kilometers:
            return DueSoonThreshold(distance: Distance(800, .kilometers), days: 30)
        }
    }

    /// Reconciles an existing plan against a newer catalog.
    ///
    /// Nothing is silently rewritten. A changed schedule is parked on the plan
    /// item as a proposal and the old rule keeps running until the owner accepts
    /// it, and an owner override is never touched.
    public static func applyCatalogUpdate(
        to items: [MaintenancePlanItem],
        vehicle: Vehicle,
        catalog: MaintenanceCatalog,
        now: Date
    ) -> (items: [MaintenancePlanItem], changes: [CatalogChange]) {
        let profile = catalog.bestProfile(for: vehicle.identity, configuration: vehicle.configuration)
        var updated: [MaintenancePlanItem] = []
        var changes: [CatalogChange] = []

        for var item in items {
            guard !item.isCustom, let definition = catalog.definition(id: item.definitionID) else {
                updated.append(item)
                continue
            }

            let resolved = resolveRule(for: definition, vehicle: vehicle, profile: profile, catalog: catalog)
            guard let newRule = resolved.rule else {
                updated.append(item)
                continue
            }

            let before = item.catalogRule
            let beforeEffective = item.effectiveRule
            item.apply(
                catalogRule: newRule,
                provenance: resolved.provenance,
                catalogVersion: catalog.catalogVersion,
                now: now
            )

            if before == nil, item.catalogRule != nil {
                changes.append(
                    CatalogChange(
                        kind: .newScheduleProposed,
                        definitionID: item.definitionID,
                        title: item.title,
                        detail: "A schedule is now available: \(newRule.summary)."
                    )
                )
            } else if let proposal = item.pendingProposal {
                changes.append(
                    CatalogChange(
                        kind: .scheduleChanged,
                        definitionID: item.definitionID,
                        title: item.title,
                        detail: proposal.summaryOfChange
                    )
                )
            }

            // Defence in depth: the effective schedule must never move without
            // the owner accepting it. `apply` already guarantees this, but a
            // shipping app repairs the invariant rather than trusting it.
            if before != nil, item.effectiveRule != beforeEffective {
                item.catalogRule = before
                item.pendingProposal = RuleChangeProposal(
                    proposedRule: newRule,
                    proposedProvenance: resolved.provenance,
                    catalogVersion: catalog.catalogVersion,
                    proposedOn: now,
                    summaryOfChange: "\(beforeEffective?.summary ?? "No schedule") → \(newRule.summary)"
                )
            }

            updated.append(item)
        }

        let existingIDs = Set(items.map(\.definitionID))
        for suggestion in suggestions(for: vehicle, catalog: catalog, includeAdvanced: false)
        where !existingIDs.contains(suggestion.definition.id) && suggestion.isRecommendedByDefault {
            changes.append(
                CatalogChange(
                    kind: .newTaskAvailable,
                    definitionID: suggestion.definition.id,
                    title: suggestion.definition.title,
                    detail: suggestion.rule?.summary ?? "Available to add."
                )
            )
        }

        return (updated, changes)
    }

    /// Merges catalog specifications with the owner's own entries.
    ///
    /// The owner's value wins where both exist, and the catalog value stays
    /// visible underneath so nothing disappears silently.
    public static func resolvedSpecifications(
        vehicle: Vehicle,
        catalog: MaintenanceCatalog,
        ownerEntries: [Specification]
    ) -> [ResolvedSpecification] {
        let profile = catalog.bestProfile(for: vehicle.identity, configuration: vehicle.configuration)
        var byKind: [SpecificationKind: ResolvedSpecification] = [:]

        for published in profile?.specifications ?? [] {
            let specification = Specification(
                kind: published.kind,
                value: published.value,
                provenance: published.provenance,
                basis: published.basis,
                appliesToNote: published.appliesToNote
            )
            byKind[published.kind] = ResolvedSpecification(
                kind: published.kind,
                active: specification,
                supersededCatalogValue: nil,
                sourceName: catalog.source(id: published.sourceID)?.name
            )
        }

        for entry in ownerEntries {
            let existing = byKind[entry.kind]
            byKind[entry.kind] = ResolvedSpecification(
                kind: entry.kind,
                active: entry,
                supersededCatalogValue: existing?.active,
                sourceName: existing?.sourceName
            )
        }

        return byKind.values.sorted { lhs, rhs in
            if lhs.kind.group == rhs.kind.group {
                return lhs.kind.displayName < rhs.kind.displayName
            }
            return lhs.kind.group.rawValue < rhs.kind.group.rawValue
        }
    }
}

/// A specification as the app should present it: one active value, plus the
/// catalog value it replaced when the owner entered their own.
public struct ResolvedSpecification: Hashable, Sendable, Identifiable {
    public var id: String { kind.rawValue }
    public var kind: SpecificationKind
    public var active: Specification
    public var supersededCatalogValue: Specification?
    public var sourceName: String?

    public init(
        kind: SpecificationKind,
        active: Specification,
        supersededCatalogValue: Specification? = nil,
        sourceName: String? = nil
    ) {
        self.kind = kind
        self.active = active
        self.supersededCatalogValue = supersededCatalogValue
        self.sourceName = sourceName
    }

    public var isOwnerOverride: Bool { active.provenance.origin == .userEntered }
}
