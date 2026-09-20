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

    OPTIONS
      --strict   Treat warnings as failures.
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
