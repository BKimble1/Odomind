# Odomind

[![CI](https://github.com/BKimble1/Odomind/actions/workflows/ci.yml/badge.svg)](https://github.com/BKimble1/Odomind/actions/workflows/ci.yml)

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

- **Find a vehicle** by typing something like "2010 Jeep Wrangler". The models
  come back from NHTSA's own lookup service. Typing it in by hand always works
  and works offline; a VIN — typed or scanned — also fills in the engine and
  drivetrain, and asks before it sends anything.
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
- **See your car**, drawn. Odomind has matched illustrations for some vehicles
  and a body-style drawing for the rest, in a colour you pick — or your own
  photo, which stays on the phone and travels in the backup.
- **Find parts** with what Odomind knows about your vehicle already filled in,
  and parts shops near you, without giving up your location if you would rather
  type a postal code.
- **See everything on one calendar**: work you recorded, appointments you
  booked, real deadlines and clearly-labelled estimates, told apart.
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

### Or take the TestFlight build

Odomind ships to TestFlight from CI, with no Mac involved. See
[Shipping to TestFlight without a Mac](#shipping-to-testflight-without-a-mac)
for how that works and how to run it.

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

A fourth workflow, `testflight.yml`, is manual and covered under
[Shipping to TestFlight without a Mac](#shipping-to-testflight-without-a-mac).

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

### Shipping to TestFlight without a Mac

`.github/workflows/testflight.yml` builds, signs, exports and uploads. Run it
from **Actions → Odomind TestFlight → Run workflow**; nothing else is needed,
and no Mac is involved at any point.

Signing is Xcode's own cloud signing. Given an App Store Connect API key and
`-allowProvisioningUpdates`, Xcode creates and downloads the distribution
certificate and the provisioning profile itself. That is why this needs no
`.p12`, no `.mobileprovision` and no base64 keychain blob — none of which
belong in source control, and all of which are the usual reason a deploy needs
a Mac to bootstrap.

| Secret | What it is |
| --- | --- |
| `ASC_KEY_ID` | The ~10-character key identifier beside the key in App Store Connect → Users and Access → Integrations |
| `ASC_ISSUER_ID` | The UUID shown above the key list on that page — one per team |
| `ASC_PRIVATE_KEY` | The whole `AuthKey_XXXXXXXXXX.p8`, PEM or base64 of it |
| `APPLE_TEAM_ID` | Optional. Looked up from the bundle ID's seed ID when absent |

**Build numbers look after themselves.** The workflow asks App Store Connect
for the highest build it already holds and adds one, so an upload is never
rejected as a duplicate. The marketing version stays at the project's unless
an input overrides it. Neither value is committed: both are passed to
`xcodebuild` on the command line, which is also how `DEVELOPMENT_TEAM` is
supplied without putting a team identifier in the repository.

Four things are checked before anything slow runs — the key parses, the app
record exists, the team resolves, and the project's bundle identifier matches
the one being shipped. After the archive it verifies the bundle identifier and
build number baked into the app, and that the icon carries no alpha channel,
which App Store Connect rejects. The IPA is validated with `altool` before it
is uploaded, and the build is then polled until Apple stops calling it
`PROCESSING`.

Inputs worth knowing:

- `unsigned_archive` — compiles and archives with signing off and no Apple
  credentials at all. Use it to prove the Release build independently of
  anything to do with certificates.
- `upload` — off builds and exports the IPA without shipping it.
- `run_ui_tests` — adds the UI suite, roughly 25 minutes.
- `skip_tests` — for re-uploading a build that already passed.

Dispatch-only on purpose: a deploy that ran on `pull_request` would hand
signing and upload credentials to code from a fork. The key is written with
owner-only permissions and deleted in an `always()` step.

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

Your records stay on your device. No account, no analytics, no advertising,
and nothing is uploaded.

Odomind can make five kinds of outbound request, every one of them started by
something you did:

| Request | When | What is sent |
| --- | --- | --- |
| Vehicle model lookup | You type a year and make into the search field | The year and the make |
| VIN decode | You ask for one, after a disclosure naming the destination | The VIN |
| Nearby parts shops | You tap **Near me** or type a postal code | A coarse location or the postal code, to Apple's map search |
| Opening a retailer | You tap a retailer | Nothing — your browser opens their search for the year, make, model and part |
| Maintenance catalog update | You tap **Check now**, or turn on automatic checks | Nothing about you |

App Store purchases go through Apple, which is the only party that ever sees
payment information.

What never leaves the device: your VIN outside a lookup you asked for, your
mileage, your service history, your receipts, your notes, your photos, and any
receipt text. Receipt scanning runs on the phone.

- Your VIN is stored locally, shown as its last six characters, never written to
  a log or an error report, and left out of exports unless you switch it on. It
  is never put in a retailer URL.
- Notification permission is asked for when you turn a reminder on. Camera
  permission when you scan a VIN. Location permission when you tap **Near me**,
  and never as a condition of tracking maintenance. Calendar permission is
  **write-only**, asked for when you export a batch of dates — a single event
  goes through the system's own editor, which needs no permission at all, and
  Odomind never reads your calendar.
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
