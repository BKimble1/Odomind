# Implementation plan and decision log

Written before implementation and kept current as decisions were made. Where a
decision was forced by the environment rather than chosen, it says so.

## Environment assessment

| Question | Answer |
| --- | --- |
| Repository state | Empty. No prior work to preserve. |
| Swift toolchain on the build host | **None.** Linux host, no Swift, `download.swift.org` blocked by network policy. |
| Can the app be compiled locally? | No. |
| Can it be compiled anywhere? | Yes — GitHub Actions macOS runners with real Xcode and a real simulator. |
| Is NHTSA vPIC reachable from the build host? | **No.** `vpic.nhtsa.dot.gov` is blocked by egress policy. |
| Are manufacturer sites reachable? | No. |
| Is `developer.apple.com` reachable? | Yes — used to confirm current EventKit and UserNotifications behaviour. |

Two of these shaped the whole build.

**No local compiler** meant CI had to become the compiler. The domain core was
written, committed and pushed first, on its own, so that a real `swiftc` could
report on it before the app layer was written on top. The loop that followed
was the whole build: small commits, read the compiler, fix, push. Several
classes of mistake only a compiler catches — access levels across module
boundaries, actor isolation in default arguments, `await` inside an
autoclosure — were found that way rather than by review.

**No reachable vehicle data** meant the catalog could not honestly ship
manufacturer values. Rather than fill it with plausible numbers, the app was
built so that absence is a well-handled, useful state — see
[DATA-SOURCES.md](DATA-SOURCES.md#what-is-deliberately-missing).

## Sequence

1. **Assessment and data sourcing.** Establish what is reachable and what each
   source permits, before writing anything that depends on it.
2. **Domain core.** Units, clock, provenance, models, schedule engine, estimator,
   reminder planner, transfer formats — with tests. Push, compile, fix.
3. **Catalog and validator.** Versioned JSON, a validator that enforces the
   honesty rules, a CLI for CI.
4. **App layer.** Persistence, providers, services, app model.
5. **Screens.** Onboarding, Today, Maintenance, Garage, History, Settings.
6. **Project and CI.** Generated Xcode project, iOS build and test jobs.
7. **Walkthrough and repair.** Read every screen as a new owner; fix what is
   wrong.

## Decisions

### Toolchain

- **iOS 18 deployment target.** `@Observable`, `ContentUnavailableView`, the
  out-of-process event editor and `DataScannerViewController` all land cleanly,
  and nothing here needs a beta SDK.
- **Swift 5 language mode on a Swift 6 toolchain.** Strict concurrency is worth
  adopting deliberately, with a compiler to hand. Migrating is tracked as future
  work rather than done blind.
- **SwiftData, used narrowly.** No relationships, no `#Predicate`, no `@Query`.
  Rationale in [ARCHITECTURE.md](ARCHITECTURE.md#persistence).

### Product

- **"Verified" is a load-bearing word.** One definition, enforced in code and in
  the catalog validator. A decoder's output is not verified.
- **Absence is a designed state.** Every specification the app does not have
  shows as "Not available" with a path to record the real one. This is the
  single most important interaction in the app, because it is the one every
  competitor gets wrong.
- **"I don't know" is a first-class answer.** It gets its own due state, its own
  group on Today, and its own wording. It is neither "up to date" nor "overdue".
- **Estimates warn, never accuse.** Asserted directly in the test suite.
- **Fixed milestones do not reset.** A separate rule shape rather than a flag,
  because the behaviour is genuinely different and worth being unable to confuse.
- **Least permission, latest moment.** Notifications when a reminder is switched
  on. Camera when a VIN is scanned. Calendar: never.

### Improvements added beyond the brief

Each one reduces setup effort or prevents a wrong answer; none expands scope.

1. **A separately-serviceable differential model.** A front-wheel-drive car has
   a differential, but it is inside the transaxle and shares its fluid. Treating
   it as fitted would invent a service that does not exist. `Fitment` is derived
   from the drivetrain, and all-wheel drive resolves to "ask" rather than a guess.
2. **The odometer ledger.** Instrument-cluster replacement is recorded
   explicitly and folded into a cumulative scale, so a swap does not reset
   anyone's maintenance schedule — and an ordinary typo stays a typo.
3. **Calendar snapshot honesty.** The app records what it wrote to the calendar
   and when, so it can warn before creating a duplicate and say plainly when the
   schedule has moved since. It never implies it keeps the event in step.
4. **A `fourWheelDrive` case with no sub-type.** vPIC reports "4WD/4x4" without
   saying part-time or full-time. Rather than pick one, the model carries the
   general case, which is enough for task applicability and does not assert
   something unknown.
5. **The service visit owns its reading.** The odometer reading a visit produces
   carries that record's identifier, so editing the visit updates the reading
   and deleting it takes the reading with it. (This was found by a test that
   caught a stale reading being left behind.)
6. **A reproducible Xcode project.** Generated by a committed script and checked
   in CI, so the project file cannot drift from the files on disk.

## What was cut, and why

- **A hosted catalog.** The plumbing is built and tested; the blocker is source
  terms, not engineering. Documented rather than faked.
- **Manufacturer specification values.** Could not be verified and redistributed
  from this environment. Omitted rather than invented.
- **Automatic extraction from an owner's manual PDF.** Out of scope for a first
  release, and any proposed value would need review anyway.
- **Swift 6 strict concurrency.** Deliberate, not incidental; wants a compiler
  in the loop.
