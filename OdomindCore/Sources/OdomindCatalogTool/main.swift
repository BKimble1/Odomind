import Foundation
import OdomindCore

// odomind-catalog — validates a maintenance catalog file.
//
// Run by CI on every pull request so a catalog that claims an unverified
// manufacturer source, duplicates a task id, or references a task that does not
// exist can never reach a release.
//
//   swift run odomind-catalog validate <path-to-catalog.json> [--strict]
//
// Exit codes: 0 valid, 1 errors found, 2 usage or I/O problem.

func printUsage() {
    let text = """
    odomind-catalog — validate an Odomind maintenance catalog

    USAGE
      odomind-catalog validate <path> [--strict]
      odomind-catalog summary  <path>
      odomind-catalog vehicle  <path> --year N --make M --model M [options]

    OPTIONS
      --strict          Treat warnings as failures.

    VEHICLE OPTIONS
      --year N          Model year.
      --make NAME       Make, as the provider spells it.
      --model NAME      Model, as the provider spells it.
      --body TEXT       Body class from the provider.
      --powertrain K    gasoline | diesel | hybrid | pluginHybrid |
                        batteryElectric | hydrogenFuelCell | other | unknown
      --displacement L  Engine displacement in litres.
      --usage U         The owner's usage profile, if they chose one.

    `vehicle` prints exactly what Odomind would build for that vehicle: the
    profile it matched, the tasks it would offer with their schedules and
    sources, and the specifications it holds. It is the evidence behind the
    validation matrix in docs/BUILD-3-NOTES.md — the numbers there are this
    command's output, not a description of it.
    """
    print(text)
}

let arguments = Array(CommandLine.arguments.dropFirst())

guard let command = arguments.first else {
    printUsage()
    exit(2)
}

guard arguments.count >= 2 else {
    printUsage()
    exit(2)
}

let path = arguments[1]
let strict = arguments.contains("--strict")

/// The value after a named flag, or nil.
func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    let value = arguments[index + 1]
    return value.hasPrefix("--") ? nil : value
}

guard let data = FileManager.default.contents(atPath: path) else {
    FileHandle.standardError.write(Data("error: cannot read \(path)\n".utf8))
    exit(2)
}

let decoded: MaintenanceCatalog
do {
    decoded = try CatalogLoader.makeDecoder().decode(MaintenanceCatalog.self, from: data)
} catch {
    FileHandle.standardError.write(Data("error: \(CatalogLoader.describe(error))\n".utf8))
    exit(1)
}

switch command {
case "validate":
    let issues = CatalogValidator.validate(decoded)
    let errors = issues.filter { $0.severity == .error }
    let warnings = issues.filter { $0.severity == .warning }

    for issue in issues {
        print(issue.description)
    }

    print("")
    print("catalog \(decoded.catalogVersion) (schema \(decoded.schemaVersion))")
    print("  \(decoded.taskDefinitions.count) tasks, \(decoded.vehicleProfiles.count) vehicle profiles, \(decoded.sources.count) sources")
    print("  \(errors.count) error(s), \(warnings.count) warning(s)")

    if !errors.isEmpty {
        exit(1)
    }
    if strict, !warnings.isEmpty {
        print("failing because --strict was passed and warnings were found")
        exit(1)
    }
    print("OK")
    exit(0)

case "vehicle":
    let vehicle = Vehicle(
        identity: VehicleIdentity(
            modelYear: option("--year").flatMap(Int.init),
            make: option("--make") ?? "",
            model: option("--model") ?? "",
            bodyClass: option("--body")
        ),
        configuration: VehicleConfiguration(
            powertrain: option("--powertrain").flatMap(PowertrainKind.init(rawValue:)) ?? .unknown,
            engineDisplacementLiters: option("--displacement").flatMap(Double.init),
            usageProfile: option("--usage").flatMap(UsageProfile.init(rawValue:)) ?? .unspecified
        )
    )

    print("VEHICLE")
    print("  \(vehicle.identity.displayName)")
    print("  body class: \(vehicle.identity.bodyClass ?? "not supplied")")
    print("  powertrain: \(vehicle.configuration.powertrain.rawValue)", terminator: "")
    if let litres = vehicle.configuration.engineDisplacementLiters {
        print(", \(litres) L")
    } else {
        print(", displacement not supplied")
    }
    print("")

    let profile = decoded.bestProfile(for: vehicle.identity, configuration: vehicle.configuration)
    print("MATCHED PROFILE")
    if let profile {
        print("  \(profile.id): \(profile.displayName)")
        for note in profile.coverageNotes {
            print("  - \(note)")
        }
    } else {
        // Said plainly. A general template is a real answer, and pretending
        // it came from the manufacturer would be the exact failure the
        // provenance system exists to prevent.
        print("  none — every schedule below is a general template, not this vehicle's")
    }
    print("")

    let suggestions = PlanBuilder.suggestions(for: vehicle, catalog: decoded)
    print("TASKS OFFERED (\(suggestions.count))")
    for suggestion in suggestions.sorted(by: { $0.definition.id < $1.definition.id }) {
        let schedule = suggestion.rule?.summary ?? "no schedule — owner supplies the interval"
        print("  \(suggestion.definition.id): \(schedule)")
        print("    origin: \(suggestion.provenance.origin.rawValue), verified: \(suggestion.provenance.isVerified)")
        if let note = suggestion.sourceNote {
            print("    source: \(note)")
        }
    }
    print("")

    let specifications = PlanBuilder.resolvedSpecifications(
        vehicle: vehicle,
        catalog: decoded,
        ownerEntries: []
    )
    print("SPECIFICATIONS HELD (\(specifications.count))")
    if specifications.isEmpty {
        print("  none — Odomind has no published value for this vehicle and will say so")
    }
    for specification in specifications {
        print("  \(specification.kind.rawValue): \(specification.active.value.displayString)")
        print("    source: \(specification.sourceName ?? "none"), verified: \(specification.active.provenance.isVerified)")
    }
    exit(0)

case "summary":
    print("catalog \(decoded.catalogVersion) published \(decoded.publishedOn)")
    print("")
    print(decoded.coverageNotice)
    print("")
    print("SOURCES")
    for source in decoded.sources {
        print("  \(source.id): \(source.name)")
        print("    redistribution allowed: \(source.allowsRedistribution)")
        print("    \(source.limitations)")
    }
    print("")
    print("TASKS")
    for definition in decoded.taskDefinitions.sorted(by: { $0.id < $1.id }) {
        let schedule = definition.defaultRule?.summary ?? "no default schedule — owner supplies the interval"
        let flag = definition.isAdvanced ? " [advanced]" : ""
        print("  \(definition.id)\(flag): \(schedule)")
    }
    print("")
    print("VEHICLE PROFILES")
    for profile in decoded.vehicleProfiles {
        print("  \(profile.id): \(profile.displayName)")
        print("    \(profile.configurationFacts.count) configuration facts, \(profile.specifications.count) specifications, \(profile.scheduleRules.count) schedules")
        for note in profile.coverageNotes {
            print("    - \(note)")
        }
    }
    exit(0)

default:
    printUsage()
    exit(2)
}
