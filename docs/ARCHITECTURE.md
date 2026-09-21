# Architecture

## Shape

```
OdomindCore/          Portable Swift package. No UIKit, SwiftUI, SwiftData or
                      EventKit. Domain models, the schedule engine, the
                      catalog, reminder planning, transfer formats.
                      Builds and tests anywhere Foundation does.

Odomind/              The iOS app.
  App/                AppModel — the single source of truth — plus routing.
  Persistence/        SwiftData models and the store boundary.
  Providers/          NHTSA vPIC client and its mapper.
  Services/           Notifications, calendar, attachments, backup, export.
  DesignSystem/       Theme, formatters, shared components.
  Features/           One folder per screen area.

OdomindTests/         App-level tests against in-memory stores and fixtures.
OdomindUITests/       The principal journey, driven through the UI.
Tools/                Reproducible generators: the Xcode project, the app icon.
```

## Why the core is a separate package

The scheduling rules are the part of this app most likely to be wrong and least
likely to be noticed. Keeping them in a package with no platform dependencies
means they can be exercised in seconds, in bulk, on any machine — including in
CI before the iOS build even starts. It also makes the boundary honest: if a
rule needs a view or a database to work, it is not a rule, it is a feature.

## The data flow

```
                  ┌────────────────────┐
  SwiftData ────► │ OdomindStore       │ ──► GarageSnapshot (value types)
                  └────────────────────┘              │
                                                      ▼
                                           ┌─────────────────────┐
                                           │ ScheduleContext     │
                                           │   .build(...)       │
                                           └─────────────────────┘
                                                      │
                                                      ▼
                                           ┌─────────────────────┐
                                           │ ScheduleEngine      │──► [ScheduleEvaluation]
                                           └─────────────────────┘              │
                                                                                ▼
                                              ┌──────────────┐        ┌────────────────────┐
                                              │ SwiftUI      │◄───────│ AppModel           │
                                              │ screens      │        │ (@Observable)      │
                                              └──────────────┘        └────────────────────┘
                                                                                │
                                                                                ▼
                                                                     ┌────────────────────┐
                                                                     │ ReminderCoordinator│
                                                                     └────────────────────┘
```

Every mutation goes through a method on `AppModel`, which writes, reloads the
whole snapshot, re-evaluates the schedule and re-syncs reminders — in that
order. Screens never touch the store or the engine. That is what makes it
impossible for the due date on screen and the reminder on the system to
disagree.

Reloading everything after every write is wasteful in the abstract and free in
practice: a household has a handful of vehicles and a few hundred records.

## Persistence

Two decisions keep SwiftData's surface small:

**No relationships.** Records carry a plain `vehicleID` and the store joins in
Swift. This removes a whole class of inverse-relationship and delete-rule
surprises, and at this data size costs nothing.

**No `#Predicate`, no `@Query`.** Fetches are unfiltered with a sort descriptor
and filtered in Swift. Screens read a snapshot rather than a live query. The
trade is a little convenience for behaviour that can be exercised in a test with
an in-memory container.

**Rich values as JSON.** Schedule rules, provenance, configuration and line items
are stored as the same `Codable` output the backup format uses. The domain types
in `OdomindCore` stay the single definition of the data, and a shape change is a
`Codable` change with a version bump rather than a store migration per enum case.

### Schema migration

`OdomindSchemaV1` lists the model types; `OdomindMigrationPlan` currently has no
stages. To add version 2:

1. Copy the current `@Model` class definitions into a `OdomindSchemaV1`
   namespace, so version 1's shape is frozen in code.
2. Add `OdomindSchemaV2` with the new shape.
3. Add a `MigrationStage` — lightweight where the change is additive, custom
   where data has to be reshaped.
4. Add `OdomindSchemaV2.self` to `OdomindMigrationPlan.schemas`.
5. Add a test that loads a version 1 store and asserts the result.

For anything stored as JSON, prefer a `Codable` change with a version field over
a store migration: it is testable without a simulator.

### The backup format

`BackupArchive.formatVersion` is checked for **exact** equality on import, and a
mismatch is reported to the owner as "This backup uses format version N. This
version of Odomind reads version M." rather than being read on a guess.
`testUnsupportedFormatVersionIsRejected` covers it.

That strictness is correct while there is only one version, but it means the
first bump makes every existing backup unreadable unless the reader is taught
about the old shape in the same change. So when bumping
`BackupArchive.currentFormatVersion`:

1. Keep a decodable description of the previous shape rather than deleting it.
2. Widen the import check to accept the versions you can actually read, and
   convert older archives forward on load.
3. Add a test that imports an archive at the previous version.

A refused import is a safe failure; a silently misread one is not. Do not
loosen the check without doing the work in step 2.

## The schedule engine

`ScheduleEngine` is an enum of static functions. It takes a `ScheduleContext`
(vehicle, odometer ledger, completions, optional estimate, the instant, the
calendar) and returns `ScheduleEvaluation` values. No clock, no locale, no
storage, no randomness.

Six rule shapes, each with a reason to exist:

| Rule | Counts from | Why it is separate |
| --- | --- | --- |
| `distance` | last completion | the ordinary case |
| `time` | last completion | brake fluid, coolant |
| `distanceOrTime` | last completion | whichever arrives first |
| `fixedMilestones` | the odometer | doing the work early must **not** move the next milestone |
| `oneTime` | the vehicle | happens once, then stops |
| `conditionCheck` | last completion | schedules a look, never a replacement deadline |
| `vehicleIndicator` | the owner's report | the vehicle computes it; Odomind cannot see it |

### The odometer ledger

`OdometerLedger` folds recorded instrument-cluster replacements back into a
single cumulative scale. The engine always works in cumulative distance; the UI
always shows the number on the dash. A decreasing reading is reported to the
owner as a question, never silently reinterpreted as a new unit.

### Estimates can warn, never accuse

`MileageEstimator` declines more often than it answers: it needs a usable span,
recent readings and plausible rates, and it excludes pairs that look like typos.
When it does produce a projection, the engine uses it for one thing — an
estimated date on a distance-based due point. A projection can escalate a task
to "due soon"; it can never make one overdue. Overdue comes only from a reading
the owner actually took, or a calendar deadline that has actually passed. This
is asserted directly in `EstimateAndDueStateTests`.

## Reminders

`ReminderPlanner` (pure, in the core) turns evaluations into requests with
identifiers of the form `task.<planItemID>.<kind>` — stable across
recomputation, so re-scheduling replaces a pending request instead of stacking a
second copy. `ReminderCoordinator` (app side) reconciles the desired set against
what the system already has and applies the difference.

The planner bounds the set to 56 nearest requests, comfortably under the
platform's pending-notification limit, and says so in Settings when it truncates.

Permission is requested when the owner turns a reminder on. Never at launch.

## Calendar

Odomind requests **no** calendar permission. On iOS 17 and later
`EKEventEditViewController` runs outside the app's process with its own access,
so the app builds an `EKEvent`, presents the system editor, and the owner
confirms. Odomind never reads the calendar.

What it cannot do is keep that event in step, so it does not pretend to. It
records when an event was created and for which due date, warns before creating
a duplicate, and says plainly when the schedule has moved since.

## Privacy boundaries

- The VIN is the only identifying value that ever leaves the device, only on an
  explicit lookup, after a disclosure naming the destination.
- No VIN is written to a log, an analytics event, a crash message, a test
  fixture or a CI artifact. Sample content is validated to contain none.
- Attachments live in a directory the app owns, named by identifier. Deleting a
  record deletes its files; a sweep on launch catches anything a crash left.
- Exports land in a temporary directory that is cleared after the share sheet
  closes.

## Future remote catalog

The versioning, validation and proposal machinery is already here and tested.
What a hosted catalog would additionally need:

1. A signed or checksummed manifest, and an HTTPS fetch with a bounded retry.
2. Last-known-good fallback: a failed or invalid download must leave the bundled
   catalog in place, not a partial one.
3. A visible review step — `PlanBuilder.applyCatalogUpdate` already produces
   `CatalogChange` values and parks changed rules as proposals, so the screen
   for this (`ProposalsView`) exists.
4. Sources whose terms actually permit redistribution. This is the real blocker,
   not the plumbing. See [DATA-SOURCES.md](DATA-SOURCES.md).
