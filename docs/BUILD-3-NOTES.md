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
