# Odomind

**Know your car. Know what's next.**

An iPhone-first vehicle maintenance app: add a vehicle, tell it your odometer,
and get a maintenance workspace that is honest about what it knows.

Odomind is built by Idlery Services LLC. This repository is public for review;
see [LICENSE](LICENSE).

> This README is being expanded as the app is built. See
> [docs/](docs/) for the product brief, architecture and data-source assessment.

## Repository layout

| Path | What it is |
| --- | --- |
| `OdomindCore/` | Portable Swift package: domain models, the scheduling engine, the catalog, reminder planning and transfer formats. No UIKit, SwiftUI, SwiftData or EventKit, so it builds and tests anywhere Foundation does. |
| `OdomindCore/Sources/OdomindCore/Resources/odomind-catalog.json` | The versioned, schema-validated maintenance catalog. |
| `.github/workflows/` | Continuous integration. |
| `docs/` | Product brief, architecture, data sources, catalog authoring. |

## Build and test the domain core

```bash
swift build --package-path OdomindCore
swift test  --package-path OdomindCore
```

## Validate the catalog

```bash
swift run --package-path OdomindCore odomind-catalog validate \
  OdomindCore/Sources/OdomindCore/Resources/odomind-catalog.json --strict

swift run --package-path OdomindCore odomind-catalog summary \
  OdomindCore/Sources/OdomindCore/Resources/odomind-catalog.json
```

The validator is a CI gate. It rejects a catalog that claims a manufacturer
source without a citation and a review date, duplicates a task identifier,
references a task that does not exist, ships a schedule from a source that does
not permit redistribution, or puts a cold tire pressure behind a general
template.

## What Odomind does not claim

- It does not ship manufacturers' maintenance schedules, fluid specifications,
  capacities or tire pressures. Where it has no value it says so and offers to
  store the one from your owner's manual.
- "Verified" means a person checked the value against a citable manufacturer
  source and recorded when. A VIN decoder's output is not verified.
- Mileage projections are labelled as estimates and never turn into a confirmed
  odometer reading or a confirmed overdue status.
