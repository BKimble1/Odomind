# Odomind Build 3 — implementation notes

What changed, what is verified, and what is still blocked. The provider
evidence behind all of it is in [`PROVIDERS.md`](PROVIDERS.md).

## The headline

Build 2's search refused to make a request until it had a four-digit year and
a make from a list of 43 typed into a Swift file. "Wrangler" — how people
actually refer to their car — produced an instruction to type more. That
requirement turned out to be unnecessary rather than unavoidable: vPIC's
`GetModelsForMake` answers with no year at all, which a live probe confirmed
by returning 24 Jeep models.

## Feature status

| Feature | Status |
| --- | --- |
| Search by model alone — "wrangler", "camry", "f150" | Implemented and verified |
| Search by make alone, or part of a make | Implemented and verified |
| Either word order, and common shorthand (chevy, vw, mercedes) | Implemented and verified |
| Extra trim words narrow rather than eliminate | Implemented and verified |
| Year asked for after selection, not before searching | Implemented and verified |
| Request invalidation on every input transition and on dismissal | Implemented and verified |
| Atomic vehicle selection — no VIN, trim or configuration carried over | Implemented and verified |
| Real photographs with licence and attribution | Implemented, **device check needed** — the simulator run does not reach Commons |
| Photo match level shown, never implying the owner's own car | Implemented and verified |
| Shared, persisted shopping area with a control on Home and Parts | Implemented, **device check needed** |
| Location lifecycle: timeouts, cancellation, repeated taps, denial vs error | Implemented and verified (unit); **device check needed** for real prompts |
| Early permission setup, asked once, skippable | Implemented and verified |
| Upgrade catch-up for owners who never saw the questions | Implemented and verified |
| Search, category and job carried through navigation | Implemented and verified |
| Retailer search uses the recorded specification | Implemented and verified |
| Part reference modelled separately from an offer | Implemented and verified |
| "Fits your vehicle" requires confirmed applicability, no open questions, no supersession | Implemented and verified |
| **Applicable part numbers from a catalogue** | **Blocked** — no licensed data. See below. |
| **Retail price and availability** | **Blocked** — same dependency |
| Garage card without the nested frame | Implemented and verified |
| Baseline action suppressed where history exists | Implemented and verified |
| Home hierarchy simplification | Implemented and verified |
| Untracked job opens that job, not the catalog library | Implemented and verified |
| Parts specifications follow the category searched for | Implemented and verified |
| Engine/trim options from a provider rather than a picker | Implemented and verified |
| Catalog updates say "nothing published" rather than "service down" | Implemented and verified; **publishing is an owner action, see CATALOG-AUTHORING.md** |

## Validation matrix — three real configurations

Gathered on a macOS runner on **2026-09-21**, commit `e72cc9c`. Every line is
this run's output, not a description of it. `.github/scripts/validation-matrix.py`
asks the providers; `odomind-catalog vehicle` asks Odomind, through the same
code the app uses.

### What each provider actually had

| | 2010 Jeep Wrangler | 2015 Toyota Camry | 2018 Ford F-150 |
| --- | --- | --- | --- |
| vPIC knows the model | yes (7 models for Jeep 2010) | yes (20 for Toyota 2015) | yes (49 for Ford 2018) |
| fueleconomy.gov's name for it | **no exact match** — `Wrangler 2WD`, `Wrangler 4WD` | exact: `Camry` | **no exact match** — 20 names beginning `F150` |
| Engine options returned | 1 for `Wrangler 2WD` | 2 | 1 for the name probed |
| Engine, verbatim | `Auto 4-spd, 6 cyl, 3.8 L` | `Auto (S6), 4 cyl, 2.5 L`; `Auto (S6), 6 cyl, 3.5 L` | `Auto (S10), 6 cyl, 2.7 L, Turbo` |
| Drive, verbatim | `Rear-Wheel Drive` | `Front-Wheel Drive` | `Rear-Wheel Drive` |
| Fuel, verbatim | `Regular` | `Regular` | `Regular` |
| Licensed photograph | 5/5 candidates carry a licence | 5/5 | 5/5 |
| **Applicable part number** | **none** | **none** | **none** |
| **Price / availability** | **none** | **none** | **none** |

Photographs, by name and licence, so the attribution can be checked:

| Vehicle | File | Licence |
| --- | --- | --- |
| 2010 Jeep Wrangler | `File:Jeep Wrangler Islander -- 2010 DC.jpg` | Public domain |
| 2010 Jeep Wrangler | `File:2010 Jeep Wrangler Sahara 4WD, front left, 08-21-2026.jpg` | CC BY-SA 4.0 |
| 2015 Toyota Camry | `File:Toyota Camry XSE.jpg` | CC BY-SA 4.0 |
| 2018 Ford F-150 | `File:2018 Ford F-150 Crew Cab.jpg` | Public domain |

Part numbers: `vPIC GetParts` returned 1,000 rows keyed `CoverLetterURL`,
`LetterDate`, `ManufacturerId`, `ManufacturerName`, `ModelYearFrom`,
`ModelYearTo`, `Name`, `Type`, `URL`. Regulatory filing letters. No part
number, no category, no fitment — for any of the three. **Oil filters and
every other ordinary category are blocked equally**, which is why the brief's
"include oil filters and at least one other ordinary category" cannot be
satisfied and is reported rather than filled in.

### What Odomind itself builds for them

| | 2010 Jeep Wrangler | 2015 Toyota Camry | 2018 Ford F-150 |
| --- | --- | --- | --- |
| Vehicle profile matched | `jeep-wrangler-jk-2007-2011-3800` | **none** | **none** |
| Tasks offered | 31 | 31 | 31 |
| Schedules from a manufacturer | **0** — every one `generalTemplate`, `verified: false` | **0** | **0** |
| **Specifications held** | **0** | **0** | **0** |

That last row is the honest state of the data feature and it is not dressed
up. One profile exists, it carries the engine's identity and the fact that it
is chain-driven — enough to keep timing-belt service out of a Wrangler's plan,
which is a real saving — and it carries no oil viscosity, no capacity, no tyre
size and no interval. The other two vehicles match nothing.

So: **schedules are general guidance, honestly labelled; specifications are
absent; part numbers are blocked.** What Build 3 adds to this picture is
configuration — engine, drivetrain and transmission now come from a source
rather than from the owner's memory — and photographs, which are real and
licensed for all three.

### Two things the live run caught that no test could

**Two vocabularies for one car.** vPIC says `Wrangler`; fueleconomy.gov says
`Wrangler 2WD` and `Wrangler 4WD`. The first version of the client asked using
vPIC's spelling and would have got an empty menu — reported to the owner as
"no published configurations for this vehicle", for every car whose name is
not spelled identically in both services. Both now resolve the service's own
names first.

**A model spelled twenty ways.** The 2018 F-150 comes back as twenty names:
`F150 Pickup 2WD` and `F150 Pickup 4WD` alongside
`F150 2.7L 2WD GVWR>6649 LBS`, `F150 2WD FFV BASE PAYLOAD LT TIRE` and
sixteen more. Taking the first few alphabetically handed the owner the payload
and gross-weight variants and hid the two ordinary trucks. Names are now
ordered shortest-first — the extra words are qualifiers, so the plain name is
the short one — and capped at four, with "None of these is mine" as the way
out for anything the list misses.

## What is blocked, and exactly what unblocks it

Part applicability is the one thing in this brief that cannot be built from
free sources, and it was checked rather than assumed. `vPIC GetParts` sounds
like it answers "which oil filter fits this car". Asked directly, it returned
records keyed `CoverLetterURL`, `LetterDate`, `ManufacturerId`,
`ManufacturerName`, `ModelYearFrom`, `ModelYearTo` — manufacturer regulatory
submission letters under 49 CFR 565/566. No part number, no category, no
fitment.

**Next action, for the owner, in preference order for a US consumer app:**

1. **Auto Care Association** — ACES (applicability) and PIES (product
   attributes). The vocabulary every US catalogue speaks. Membership plus a
   data subscription; **quote required**.
2. **MOTOR Information Systems** — parts data through an API rather than a
   bulk drop, which suits an app; **quote required**.
3. **TecAlliance / TecDoc** — strong catalogue lookup, but confirm it is the
   consumer lookup product and that **US** coverage is adequate; TecDoc's
   depth is European. **Quote required.**

No vendor was contacted, no account created, no agreement accepted.

Until one is in place the app does not pretend otherwise:
`ShoppingCapability.current` stays below `licensedOffers` — with a test
pinning it there — the parts screen says it offers a search rather than a
matched product, and no part number is ever invented.

## Findings worth recording

**A model name can also be somebody's make.** vPIC lists 12,364 makes, and
`WRANGLER` is one of them: an equipment manufacturer. Resolving a query
against the full list before considering models turned a search for a Jeep
into a search for that company. Make resolution now runs in three passes —
makes that sell cars, then models, then the long tail — so an unusual make
still works without hijacking an ordinary model name. Found by running
against the real generated index; no fixture would have contained it.

**A VIN decode is a start, not a configuration.** The probe's decode of a real
2010 Wrangler returned the engine, cylinders, fuel type, drive type and trim —
and left `TransmissionStyle` blank. Odomind asks the owner for what the decode
did not establish rather than presenting a guess as decoded fact.

**A licence is a condition, not metadata.** Commons returned a public-domain
Wrangler and a CC BY-SA 4.0 Camry. The second requires attribution, so the
resolver carries licence and author with every record and `isDisplayable`
refuses anything that cannot be shown lawfully — no licence, or a share-alike
licence with no author to credit.

**Three compile errors, one mistake.** An `await` inside `Optional.map`, a
`@MainActor` default argument, and five `XCTAssertTrue` autoclosures — each
costing a round trip to a macOS runner, because there is no Swift toolchain on
the authoring host. `Tools/check-swift-shapes.py` now catches all of those
shapes on Linux in seconds and runs before the Mac build. It is verified
against a file containing each mistake rather than trusted because it reports
zero.

## Device checks this release needs

CI cannot reach any of these.

1. **Search a real vehicle.** Type "wrangler" with no year. Confirm results
   appear, then that choosing one asks for the year afterwards.
2. **Change your mind.** Decode a VIN, then pick a different vehicle.
   Confirm the new one carries none of the old one's VIN, trim or engine.
3. **A real photograph.** Open Garage and confirm the car is a photo with a
   credit under it, and that the credit names an author for a CC licence.
4. **Permissions, fresh install.** Confirm both questions are asked once,
   each after a tap, and that skipping both leaves the app usable.
5. **Permissions, upgrade.** Install Build 2, add a vehicle, install Build 3.
   Confirm one quiet catch-up row rather than the whole welcome sequence.
6. **Location.** Tap the area control, allow, confirm a town name appears.
   Then deny on a fresh install and confirm the postal-code path works and
   the Settings link is offered.
7. **Repeated taps.** Tap "Use current location" several times quickly. This
   is where Build 2 would have overwritten an unresolved continuation.
8. **Parts from a job.** Open an oil change, tap through to parts, and
   confirm the screen arrives knowing what it is for.
