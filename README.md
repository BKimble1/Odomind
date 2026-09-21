# Odomind

**Know your car. Know what's next.**

An iPhone app that tracks vehicle maintenance and is honest about what it knows.

Odomind holds your mileage, your service history and the specifications you
record from your owner's manual, and tells you what is coming up. Where it does
not have a value, it says so and offers to store the real one — instead of
showing a plausible-looking number nobody checked.

No account. No sign-in. No backend. Works offline. Everything stays on your
phone.

Built by Idlery Services LLC. This repository is public for review; see
[LICENSE](LICENSE).

---

## What it does

- **Add a vehicle** by year/make/model, or by VIN — typed or scanned with the
  camera. The VIN lookup is optional and asks before it sends anything.
- **Confirm the configuration** that decides which tasks apply. Anything left
  unconfirmed keeps the dependent tasks out of your plan rather than guessing.
- **Record mileage** in one field, whenever you think of it.
- **Track maintenance** from a catalog of 32 common and advanced tasks, or from
  tasks you write yourself, across seven kinds of schedule — including fixed
  odometer milestones, which doing the work early does not move, and condition
  checks, which schedule a look rather than a replacement.
- **Log service** as a visit: one date, one reading, one total, and every task
  that was actually done.
- **Keep specifications** from your manual and door placard, used everywhere.
- **Get reminders** for deadlines it is confident about, and clearly-labelled
  estimates for the ones it is projecting.
- **Give a vehicle a photo**, so a two-car garage is readable at a glance. It
  stays on the phone, travels in the backup, and is never read for anything.
- **Take your records with you** — CSV, a printable PDF, or a complete backup.

## What it will not do

| It will not | Because |
| --- | --- |
| Ship manufacturers' fluid specs, capacities or tyre pressures | They could not be both verified and legally redistributed. A wrong oil capacity is worse than none. |
| Infer tyre pressure from a sidewall maximum | That is the tyre's limit, not your vehicle's operating pressure. |
| Turn an estimate into a fact | A projection can warn you early. It can never mark something overdue. |
| Assume unrecorded work was recently done | "I don't know" is a real answer with its own place on the Today screen. |
| Claim your car is healthy | It says "nothing currently due based on your records", which is the only claim it can support. |
| Read your vehicle | Where the car's own oil-life monitor is the real schedule, Odomind asks you to record the message. |

"Verified" means one thing, enforced in code and gated in CI: a person checked
the value against manufacturer documentation, recorded a citation, and recorded
the date. A VIN decoder's output is not verified.

---

## Getting it onto your iPhone

1. **Requirements.** macOS with Xcode 16 or later, and an Apple ID. A free
   account is enough to run on your own device.
2. **Clone and open.**
   ```bash
   git clone https://github.com/BKimble1/Odomind.git
   cd Odomind
   open Odomind.xcodeproj
   ```
   Xcode resolves the local `OdomindCore` package on open. There is nothing to
   install.
3. **Set your team.** Select the **Odomind** target → **Signing & Capabilities**
   → **Team**. Pick your Apple ID. The repository ships no team, certificate or
   provisioning profile, by design.
4. **Change the bundle identifier** if `com.idlery.odomind` is taken on your
   account: same pane, **Bundle Identifier**.
5. **Run.** Plug in your iPhone, select it as the destination, press ⌘R. The
   first run needs **Settings → General → VPN & Device Management** on the phone
   to trust your developer certificate.

To try it in the simulator instead, pick any iPhone destination and press ⌘R —
no signing needed.

**If you used a free Apple ID**, the provisioning profile Xcode creates lasts
seven days. After that the app refuses to launch until you connect the phone
and press ⌘R again. Your records are untouched — they live in the app's
container, not the signature. A paid Apple Developer account raises that to a
year. This catches people out because it looks like a crash rather than an
expiry.

### TestFlight, later

Nothing here blocks distribution; it simply has not been set up.

1. Create the App ID and app record in App Store Connect.
2. Set `DEVELOPMENT_TEAM` and a unique `PRODUCT_BUNDLE_IDENTIFIER` (both in
   `Tools/generate-xcodeproj.py` so they survive regeneration).
3. Archive and upload, or add a CI job using an App Store Connect API key held
   in GitHub secrets.
4. Keep that job off pull-request triggers. CI here is deliberately read-only
   and receives no signing secrets, so contributed code can never reach one.

---

## Repository layout

| Path | What it is |
| --- | --- |
| `OdomindCore/` | Portable Swift package: domain models, the schedule engine, the catalog, reminder planning, transfer formats. No UIKit, SwiftUI, SwiftData or EventKit. |
| `OdomindCore/Sources/OdomindCore/Resources/odomind-catalog.json` | The versioned, schema-validated maintenance catalog. |
| `Odomind/` | The app: persistence, providers, services, design system, screens. |
| `OdomindTests/` | App-level tests against in-memory stores and recorded fixtures. |
| `OdomindUITests/` | The principal journey, driven through the UI. |
| `Tools/` | Reproducible generators for the Xcode project and the app icon. |
| `docs/` | Product brief, implementation plan, data sources, architecture, catalog authoring. |

Start with [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how it fits
together, and [docs/DATA-SOURCES.md](docs/DATA-SOURCES.md) for where every value
comes from.

---

## Building and testing

### The domain core — fast, no simulator

```bash
swift build --package-path OdomindCore
swift test  --package-path OdomindCore --parallel
```

This is where the scheduling rules live, and where most of the interesting tests
are: boundary conditions, month-end and leap-year arithmetic, time zones, unit
conversion, unknown history, odometer replacement, estimate suppression,
reminder de-duplication, backup round-trips.

### The catalog gate

```bash
swift run --package-path OdomindCore odomind-catalog validate \
  OdomindCore/Sources/OdomindCore/Resources/odomind-catalog.json --strict

swift run --package-path OdomindCore odomind-catalog summary \
  OdomindCore/Sources/OdomindCore/Resources/odomind-catalog.json
```

The validator rejects a catalog that claims a manufacturer source without a
citation and a review date, duplicates a task id, references a task that does
not exist, ships a schedule from a source that does not permit redistribution,
or puts a cold tyre pressure behind a general template.

### The app (macOS only)

```bash
DEST="$(MIN_IOS_MAJOR=18 ./.github/scripts/select-simulator.sh)"

xcodebuild build-for-testing \
  -project Odomind.xcodeproj -scheme Odomind \
  -destination "$DEST" CODE_SIGNING_ALLOWED=NO

xcodebuild test-without-building \
  -project Odomind.xcodeproj -scheme Odomind \
  -destination "$DEST" -only-testing:OdomindTests CODE_SIGNING_ALLOWED=NO

xcodebuild test-without-building \
  -project Odomind.xcodeproj -scheme Odomind \
  -destination "$DEST" -only-testing:OdomindUITests CODE_SIGNING_ALLOWED=NO
```

### After adding or moving files

```bash
python3 Tools/generate-xcodeproj.py
```

The project file is committed so a clone opens immediately, and CI fails if it
drifts from what is on disk.

---

## Continuous integration

`.github/workflows/ci.yml` runs on pull requests, pushes and manual dispatch:

| Job | Gate |
| --- | --- |
| `core` | Builds `OdomindCore` and runs the domain tests; validates the catalog with `--strict` and prints its coverage summary. |
| `project-is-reproducible` | Regenerates `Odomind.xcodeproj` and fails if it differs from the committed file. |
| `ios` | Builds the app for a **discovered** simulator destination, then runs the unit tests and the UI tests as separate steps. |

The UI tests include XCTest's accessibility audit over every screen. It runs in
full and prints every finding, but it fails the build only on what app code
controls — hit regions, element descriptions, element detection, traits,
ancestry. Contrast, clipped text and Dynamic Type are reported rather than
gated: once each finding was made to name its own element, those three turned
out to be flagging system-rendered chrome — text behind the translucent
floating tab bar mid-scroll, `UISearchBar` placeholders, List header and footer
fonts. Findings there are printed on every run marked `REPORTED`; the ones that
fail are marked `FAILING`. Real findings have come out of this — a 20pt tap
target and a caption-sized link inside a row that was already a button, both
fixed — so the gate is kept where it bites.

Workflow permissions are read-only. No job receives a signing or deployment
secret. Concurrency cancels superseded commits; result bundles upload on failure
with a seven-day retention and contain only this repository's fixtures.

`.github/workflows/provider-smoke.yml` checks weekly (and on demand) that NHTSA
vPIC is reachable and still returns the fields the decoder reads. It is
deliberately **not** a pull-request gate: a government API having a bad
afternoon must never turn every contributor's pull request red. The provider
tests in the main suite run against recorded fixtures.

Actions are pinned to major version tags. To pin to commit SHAs instead — the
stricter choice — resolve each tag once and record the SHA with the tag in a
trailing comment, then update on a schedule.

### Looking at the app without a Mac

`.github/workflows/screenshots.yml` is manual only. It drives the app through
onboarding, Today, Maintenance, a task, the Garage, a vehicle, its
specifications and History in light, dark and a large text size, and publishes
the captures two ways: as an artifact, and as base64 in the log of one small
job per screen. Where artifact downloads are not reachable, save a job's log
and rebuild the image:

```bash
.github/scripts/decode-screenshot.py today.log today.jpg
```

It refuses rather than writing a corrupt file if the log is missing a chunk,
and tells you when a screen was not captured at all. This workflow is a way to
see the app, never a gate — it does not run on a push and cannot fail a pull
request.

---

## Privacy

- Your records stay on your device. No account, no analytics, no advertising.
- The one external request Odomind can make is a VIN lookup to NHTSA vPIC. It
  names the destination and asks before the first one, and you can always skip
  it and type the vehicle in by hand.
- Your VIN is stored locally, shown as its last six characters, never written to
  a log or an error report, and left out of exports unless you switch it on.
- Notification permission is asked for when you turn a reminder on. Camera
  permission when you scan a VIN. **Calendar permission is never requested** —
  on iOS 17 and later the system's event editor runs outside the app with its
  own access.
- Delete-vehicle and delete-all-data remove the records, the receipt files on
  disk, and every pending reminder.

---

## Contributing

Run the core tests and the catalog validator before opening a pull request. If a
change requires loosening the validator, that is the signal to reconsider the
change rather than the rule.

---

## Disclaimer

Odomind is not a source of mechanical, safety or repair advice, and it is not a
substitute for the maintenance schedule and specifications published by your
vehicle's manufacturer. Always follow those.
