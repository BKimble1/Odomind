import Foundation

public struct CatalogValidationIssue: Hashable, Sendable {
    public enum Severity: String, Sendable, Hashable {
        case error
        case warning
    }

    public var severity: Severity
    /// Where in the catalog the problem is, e.g. `taskDefinitions[engine-oil]`.
    public var path: String
    public var message: String

    public init(severity: Severity, path: String, message: String) {
        self.severity = severity
        self.path = path
        self.message = message
    }

    public var description: String {
        "\(severity.rawValue.uppercased()) \(path): \(message)"
    }
}

/// Checks a catalog for the mistakes that would make it dishonest or unusable.
///
/// This runs in CI, in the app on every load, and in tests. The rules it
/// enforces are the ones that keep provenance meaningful — in particular that
/// nothing can claim a manufacturer source without a citation and a review date.
public enum CatalogValidator {

    public static func validate(_ catalog: MaintenanceCatalog) -> [CatalogValidationIssue] {
        var issues: [CatalogValidationIssue] = []

        issues.append(contentsOf: validateHeader(catalog))
        issues.append(contentsOf: validateSources(catalog))
        issues.append(contentsOf: validateDefinitions(catalog))
        issues.append(contentsOf: validateProfiles(catalog))
        issues.append(contentsOf: validateDemoContent(catalog))

        return issues
    }

    // MARK: - Header

    private static func validateHeader(_ catalog: MaintenanceCatalog) -> [CatalogValidationIssue] {
        var issues: [CatalogValidationIssue] = []
        if catalog.schemaVersion != MaintenanceCatalog.currentSchemaVersion {
            issues.append(
                CatalogValidationIssue(
                    severity: .error,
                    path: "schemaVersion",
                    message: "Expected \(MaintenanceCatalog.currentSchemaVersion), found \(catalog.schemaVersion)."
                )
            )
        }
        if catalog.catalogVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(
                CatalogValidationIssue(severity: .error, path: "catalogVersion", message: "Must not be empty.")
            )
        }
        if catalog.coverageNotice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(
                CatalogValidationIssue(
                    severity: .error,
                    path: "coverageNotice",
                    message: "The catalog must state what it does and does not cover."
                )
            )
        }
        if catalog.taskDefinitions.isEmpty {
            issues.append(
                CatalogValidationIssue(
                    severity: .error,
                    path: "taskDefinitions",
                    message: "A catalog with no tasks is not usable."
                )
            )
        }
        return issues
    }

    // MARK: - Sources

    private static func validateSources(_ catalog: MaintenanceCatalog) -> [CatalogValidationIssue] {
        var issues: [CatalogValidationIssue] = []
        var seen = Set<String>()
        for source in catalog.sources {
            let path = "sources[\(source.id)]"
            if !seen.insert(source.id).inserted {
                issues.append(
                    CatalogValidationIssue(severity: .error, path: path, message: "Duplicate source id.")
                )
            }
            if source.name.isEmpty {
                issues.append(
                    CatalogValidationIssue(severity: .error, path: path, message: "Source name must not be empty.")
                )
            }
            if source.terms.isEmpty {
                issues.append(
                    CatalogValidationIssue(
                        severity: .error,
                        path: path,
                        message: "Every source must record the terms it is used under."
                    )
                )
            }
            if source.coverage.isEmpty {
                issues.append(
                    CatalogValidationIssue(
                        severity: .error,
                        path: path,
                        message: "Every source must record what it covers."
                    )
                )
            }
            if source.limitations.isEmpty {
                issues.append(
                    CatalogValidationIssue(
                        severity: .warning,
                        path: path,
                        message: "No operational limitations recorded for this source."
                    )
                )
            }
            if source.attributionRequired, (source.attributionText ?? "").isEmpty {
                issues.append(
                    CatalogValidationIssue(
                        severity: .error,
                        path: path,
                        message: "Attribution is required but no attribution text was supplied."
                    )
                )
            }
        }
        return issues
    }

    // MARK: - Task definitions

    private static func validateDefinitions(_ catalog: MaintenanceCatalog) -> [CatalogValidationIssue] {
        var issues: [CatalogValidationIssue] = []
        var seen = Set<String>()

        for definition in catalog.taskDefinitions {
            let path = "taskDefinitions[\(definition.id)]"

            if !seen.insert(definition.id).inserted {
                issues.append(
                    CatalogValidationIssue(
                        severity: .error,
                        path: path,
                        message: "Duplicate task id. Ids are referenced by service history and must be unique."
                    )
                )
            }
            if !isValidIdentifier(definition.id) {
                issues.append(
                    CatalogValidationIssue(
                        severity: .error,
                        path: path,
                        message: "Task ids must be lowercase kebab-case so they stay stable across releases."
                    )
                )
            }
            if definition.title.isEmpty {
                issues.append(CatalogValidationIssue(severity: .error, path: path, message: "Title must not be empty."))
            }
            if definition.purpose.isEmpty {
                issues.append(
                    CatalogValidationIssue(
                        severity: .error,
                        path: path,
                        message: "Every task must explain what it is for."
                    )
                )
            }

            if let rule = definition.defaultRule {
                for problem in rule.validationProblems {
                    issues.append(CatalogValidationIssue(severity: .error, path: "\(path).defaultRule", message: problem))
                }
                guard let provenance = definition.defaultRuleProvenance else {
                    issues.append(
                        CatalogValidationIssue(
                            severity: .error,
                            path: "\(path).defaultRuleProvenance",
                            message: "A default rule must state where it came from."
                        )
                    )
                    continue
                }
                issues.append(contentsOf: validateProvenance(provenance, path: "\(path).defaultRuleProvenance"))

                // A definition-level rule is by construction not tied to one
                // vehicle, so it must never claim to be a manufacturer schedule.
                if provenance.origin == .manufacturerSourced {
                    issues.append(
                        CatalogValidationIssue(
                            severity: .error,
                            path: "\(path).defaultRuleProvenance",
                            message: "A catalog-wide default cannot be manufacturer-sourced. Put vehicle-specific schedules on a vehicle profile."
                        )
                    )
                }

                // An inspection action paired with a replacement-style interval
                // is the exact confusion this app is meant to avoid.
                if definition.action.isCheckOnly, !rule.isInspectionOnly, !rule.isOneTime {
                    issues.append(
                        CatalogValidationIssue(
                            severity: .warning,
                            path: "\(path).defaultRule",
                            message: "An inspect/test task should normally use a conditionCheck rule so it is not read as a replacement deadline."
                        )
                    )
                }
            } else if definition.defaultRuleProvenance != nil {
                issues.append(
                    CatalogValidationIssue(
                        severity: .warning,
                        path: path,
                        message: "Provenance is recorded but there is no default rule."
                    )
                )
            }

            if definition.applicability.camshaftDrives?.contains(.timingBelt) == true,
               definition.applicability.requiresCombustionEngine == nil {
                issues.append(
                    CatalogValidationIssue(
                        severity: .warning,
                        path: "\(path).applicability",
                        message: "A timing-belt task should also require a combustion engine."
                    )
                )
            }
        }

        return issues
    }

    // MARK: - Profiles

    private static func validateProfiles(_ catalog: MaintenanceCatalog) -> [CatalogValidationIssue] {
        var issues: [CatalogValidationIssue] = []
        var seenProfiles = Set<String>()
        let sourceIDs = Set(catalog.sources.map(\.id))
        let definitionIDs = Set(catalog.taskDefinitions.map(\.id))

        for profile in catalog.vehicleProfiles {
            let path = "vehicleProfiles[\(profile.id)]"
            if !seenProfiles.insert(profile.id).inserted {
                issues.append(CatalogValidationIssue(severity: .error, path: path, message: "Duplicate profile id."))
            }
            if profile.match.makes.isEmpty || profile.match.models.isEmpty {
                issues.append(
                    CatalogValidationIssue(
                        severity: .error,
                        path: "\(path).match",
                        message: "A profile must match at least one make and one model."
                    )
                )
            }
            if let earliest = profile.match.earliestModelYear,
               let latest = profile.match.latestModelYear,
               earliest > latest {
                issues.append(
                    CatalogValidationIssue(
                        severity: .error,
                        path: "\(path).match",
                        message: "earliestModelYear is after latestModelYear."
                    )
                )
            }

            var specKeys = Set<String>()
            for specification in profile.specifications {
                let specPath = "\(path).specifications[\(specification.kind.rawValue)]"
                if !sourceIDs.contains(specification.sourceID) {
                    issues.append(
                        CatalogValidationIssue(
                            severity: .error,
                            path: specPath,
                            message: "Unknown sourceID '\(specification.sourceID)'."
                        )
                    )
                }
                issues.append(contentsOf: validateProvenance(specification.provenance, path: specPath))

                let key = "\(specification.kind.rawValue)|\(specification.basis.rawValue)|\(specification.appliesToNote ?? "")"
                if !specKeys.insert(key).inserted {
                    issues.append(
                        CatalogValidationIssue(
                            severity: .error,
                            path: specPath,
                            message: "Two values for the same specification, basis and applicability. One of them is wrong."
                        )
                    )
                }

                // Cold tyre pressure comes off the vehicle's own placard. A
                // general template cannot know it, and inferring it from a tyre
                // sidewall maximum is unsafe.
                if specification.kind.isVehiclePlacardOnly,
                   specification.provenance.origin == .generalTemplate {
                    issues.append(
                        CatalogValidationIssue(
                            severity: .error,
                            path: specPath,
                            message: "\(specification.kind.displayName) must come from the vehicle placard or manual, never from a general template."
                        )
                    )
                }
            }

            var ruleKeys = Set<String>()
            for rule in profile.scheduleRules {
                let rulePath = "\(path).scheduleRules[\(rule.definitionID)]"
                if !definitionIDs.contains(rule.definitionID) {
                    issues.append(
                        CatalogValidationIssue(
                            severity: .error,
                            path: rulePath,
                            message: "References unknown task id '\(rule.definitionID)'."
                        )
                    )
                }
                if !sourceIDs.contains(rule.sourceID) {
                    issues.append(
                        CatalogValidationIssue(
                            severity: .error,
                            path: rulePath,
                            message: "Unknown sourceID '\(rule.sourceID)'."
                        )
                    )
                }
                for problem in rule.rule.validationProblems {
                    issues.append(CatalogValidationIssue(severity: .error, path: rulePath, message: problem))
                }
                issues.append(contentsOf: validateProvenance(rule.provenance, path: rulePath))

                let key = "\(rule.definitionID)|\(rule.usageProfile?.rawValue ?? "any")"
                if !ruleKeys.insert(key).inserted {
                    issues.append(
                        CatalogValidationIssue(
                            severity: .error,
                            path: rulePath,
                            message: "Conflicting schedules for the same task and usage profile."
                        )
                    )
                }

                if let source = catalog.source(id: rule.sourceID), !source.allowsRedistribution {
                    issues.append(
                        CatalogValidationIssue(
                            severity: .error,
                            path: rulePath,
                            message: "Source '\(source.id)' does not permit redistribution, so its schedule cannot ship in the catalog."
                        )
                    )
                }
            }

            for fact in profile.configurationFacts {
                let factPath = "\(path).configurationFacts[\(fact.field.rawValue)]"
                if !sourceIDs.contains(fact.sourceID) {
                    issues.append(
                        CatalogValidationIssue(
                            severity: .error,
                            path: factPath,
                            message: "Unknown sourceID '\(fact.sourceID)'."
                        )
                    )
                }
                issues.append(contentsOf: validateProvenance(fact.provenance, path: factPath))
                if !isValidConfigurationFactValue(fact) {
                    issues.append(
                        CatalogValidationIssue(
                            severity: .error,
                            path: factPath,
                            message: "'\(fact.value)' is not a valid value for \(fact.field.rawValue)."
                        )
                    )
                }
            }

            if profile.specifications.isEmpty, profile.scheduleRules.isEmpty, profile.configurationFacts.isEmpty {
                issues.append(
                    CatalogValidationIssue(
                        severity: .warning,
                        path: path,
                        message: "Profile carries no data."
                    )
                )
            }
        }
        return issues
    }

    // MARK: - Demo content

    private static func validateDemoContent(_ catalog: MaintenanceCatalog) -> [CatalogValidationIssue] {
        guard let demo = catalog.demoContent else { return [] }
        var issues: [CatalogValidationIssue] = []
        let definitionIDs = Set(catalog.taskDefinitions.map(\.id))

        if demo.disclaimer.isEmpty {
            issues.append(
                CatalogValidationIssue(
                    severity: .error,
                    path: "demoContent.disclaimer",
                    message: "Sample content must say that it is fictional."
                )
            )
        }
        if demo.identity.vin != nil {
            issues.append(
                CatalogValidationIssue(
                    severity: .error,
                    path: "demoContent.identity.vin",
                    message: "Sample content must never contain a VIN."
                )
            )
        }
        for (index, service) in demo.services.enumerated() {
            for id in service.definitionIDs where !definitionIDs.contains(id) {
                issues.append(
                    CatalogValidationIssue(
                        severity: .error,
                        path: "demoContent.services[\(index)]",
                        message: "References unknown task id '\(id)'."
                    )
                )
            }
            if service.totalCostMinorUnits != nil, service.currencyCode == nil {
                issues.append(
                    CatalogValidationIssue(
                        severity: .error,
                        path: "demoContent.services[\(index)]",
                        message: "A cost needs a currency code."
                    )
                )
            }
        }
        return issues
    }

    // MARK: - Shared rules

    static func validateProvenance(_ provenance: Provenance, path: String) -> [CatalogValidationIssue] {
        var issues: [CatalogValidationIssue] = []
        switch provenance.origin {
        case .manufacturerSourced:
            if !provenance.isVerified {
                issues.append(
                    CatalogValidationIssue(
                        severity: .error,
                        path: "\(path).provenance",
                        message: "Manufacturer-sourced values need a source reference and a review date. Use referenceSourced or generalTemplate if the value has not been checked against the manufacturer's documentation."
                    )
                )
            }
            if provenance.scope.isUnconstrained {
                issues.append(
                    CatalogValidationIssue(
                        severity: .warning,
                        path: "\(path).provenance.scope",
                        message: "A manufacturer-sourced value with no configuration scope will be applied to every configuration of the matched model."
                    )
                )
            }
        case .referenceSourced, .generalTemplate:
            if provenance.attribution?.sourceName.isEmpty ?? true {
                issues.append(
                    CatalogValidationIssue(
                        severity: .warning,
                        path: "\(path).provenance",
                        message: "No source name recorded."
                    )
                )
            }
        case .userEntered:
            issues.append(
                CatalogValidationIssue(
                    severity: .error,
                    path: "\(path).provenance",
                    message: "A published catalog cannot contain user-entered values."
                )
            )
        }
        return issues
    }

    static func isValidIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 64 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        guard value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        return !value.hasPrefix("-") && !value.hasSuffix("-")
    }

    static func isValidConfigurationFactValue(_ fact: ProfileConfigurationFact) -> Bool {
        switch fact.field {
        case .powertrain:
            return PowertrainKind(rawValue: fact.value) != nil
        case .transmission:
            return TransmissionKind(rawValue: fact.value) != nil
        case .drivetrain:
            return DrivetrainLayout(rawValue: fact.value) != nil
        case .camshaftDrive:
            return CamshaftDrive(rawValue: fact.value) != nil
        case .transferCase:
            return Fitment(rawValue: fact.value) != nil
        case .engineDisplacementLiters:
            guard let value = Double(fact.value) else { return false }
            return value > 0 && value < 20
        case .engineCylinders:
            guard let value = Int(fact.value) else { return false }
            return value > 0 && value <= 16
        case .engineCode:
            return !fact.value.isEmpty && fact.value.count <= 24
        }
    }
}
