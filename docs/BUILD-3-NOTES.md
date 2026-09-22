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
| Year asked for after selection, not before searching | Implemented and verified — **but this row was wrong until `01e2887`.** The year came out of the precondition and nothing was added to ask for it afterwards. See "What the first screenshots showed". |
| Request invalidation on every input transition and on dismissal | Implemented and verified |
| Atomic vehicle selection — no VIN, trim or configuration carried over | Implemented and verified |
| Real photographs with licence and attribution | Implemented, **device check needed** — the simulator run does not reach Commons |
| Photo match level shown, never implying the owner's own car | Implemented and verified |
| Shared, persisted shopping area with a control on Home and Parts | Implemented, **device check needed** |
| Location lifecycle: timeouts, cancellation, repeated taps, denial vs error | Implemented and verified (unit, `ShoppingLocationTests`); **device check needed** for real prompts |
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
| Engine/trim options from a provider rather than a picker | Implemented; unit-verified against recorded responses. Two live defects fixed since the row was first written: unreachable on the yearless path, and an empty answer for every make vPIC spells in capitals. Live evidence is the capture run and the validation matrix, not the unit tests. |
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

## What the first screenshots showed

Thirty screens were captured on a simulator and looked at, one at a time,
because the brief asks for exactly that: *"Review them visually; fixture-only
screenshots do not prove a live provider works."* Five defects came out of it.
**None of them could have failed a test.** In every case the accessibility
identifier was present, the element existed, and the accessibility label read
correctly — the only thing that could tell something was wrong was an eye.

**A vehicle called "Sa…".** The single most important piece of context on
Home — which car any of this is about — rendered as three characters on an
iPhone SE, and as "JE…" on a full-size phone. Two toolbar items competing for
one bar's width, and the leading one loses. Fixed on Home first, then found
again on Jobs and on Calendar, which still had it in their toolbars: a toolbar
item gets one bar's height, so neither `lineLimit(2)` nor a minimum scale
factor can save it. All four tabs now carry the name in their content.

**A location prompt nobody asked for.** Opening Parts from a job put the iOS
location dialogue on screen, with Odomind's own permission string visible
inside it saying the app uses your location *"only when you ask"*. Opening a
screen is not asking. Parts now stops at the permission check and leaves the
area empty until the owner taps "Use current location".

**A year the search had stopped asking for.** The configuration step said
"Vehicle: JEEP Wrangler" over "Odomind needs a year before it can look up
which engines this was sold with" — and offered nowhere to give one. Removing
the year from the *precondition* for searching is what makes "wrangler" work
at all; nothing had been added to ask for it afterwards, so the headline path
produced a vehicle the provider-backed lookup could never answer for. There is
a year strip on the find step now.

**"JEEP" is not "Jeep".** Chasing the above turned up a second one, the same
shape as the model-name mismatch a probe caught earlier and one level up.
vPIC answers `JEEP`, in capitals, and that is what Odomind carries because it
is what the source said. fueleconomy.gov's menu says `Jeep`, and answers a
make it does not recognise with an empty model menu — which would have read as
"no published configurations for this vehicle", for every Jeep, every RAM and
every MINI a search produced. The client resolves the make against the
service's own menu now, the way it already did for model names.

**A row hyphenated against itself.** At an accessibility text size the Jobs
list read "Engine oil / and filter" beside "Over- / due". The title and the
due badge stack at those sizes now.

### The make-spelling fix, proved against the live services

The validation matrix was asking fueleconomy.gov about `"Jeep"` — a spelling
the app never uses — so it would have passed whether or not the bug existed.
It asks with vPIC's own spelling now. Run `35667542913`, on `ef5a2bb`, against
the real services:

```
fueleconomy.gov spells 'JEEP' as 'Jeep' — asking it verbatim returns an empty model menu
  no exact name; this service spells it ['Wrangler 2WD', 'Wrangler 4WD']
fueleconomy.gov lists 'Toyota' verbatim
  exact name match: 'Camry'
fueleconomy.gov lists 'Ford' verbatim
  no exact name; this service spells it ['F150 Pickup 2WD', 'F150 Pickup 4WD', ... 20 names]
```

and the resulting coverage:

| Vehicle | vPIC identity | fueleconomy.gov configurations | Commons photos with a licence | Part number |
| --- | --- | --- | --- | --- |
| 2010 JEEP Wrangler | confirmed | **2** | 5 / 5 | **BLOCKED** |
| 2015 Toyota Camry | confirmed | **2** | 5 / 5 | **BLOCKED** |
| 2018 Ford F-150 | confirmed | **13** | 5 / 5 | **BLOCKED** |

Before the fix the Jeep row would have read `0`, and so would every RAM, MINI,
BMW and GMC — vPIC capitalises a lot of marques. The two Wrangler rows are the
2WD and 4WD variants offered side by side, which is the behaviour a probe
caught earlier: the owner picks, rather than Odomind picking one of their cars
for them.

### Two more the capture run found, after the first five

Running the capture against live providers turned up two defects that no
amount of fixture work would have.

**A photograph with nobody's name on it.** The first real Commons photograph
Odomind ever displayed went out with no credit. `aspectRatio(contentMode:
.fill)` reports a layout size that *covers* the proposal rather than fitting
inside it, so a landscape photograph in a 124-point card laid out more than
twice as tall as the card — and the bottom-trailing credit sat below the
card's bottom edge, where the `.clipped()` further out removed it. The
attribution had been written, reviewed and shipped, and was never once on
screen. A licence is a condition of showing the picture, so this is not a
cosmetic bug. The picture is sized and clipped before the credit goes on now,
the credit is in the portrait's spoken label as well, and the capture asserts
that a photograph on screen has one.

The sequence is worth recording: I could not tell from the screenshot whether
the credit was there or merely too small to read, so I wrote an assertion
instead of deciding. It failed on its first run.

**A vehicle whose make was "wrangler".** The iPhone SE captured the
confirmation step reading `Vehicle: 2023 wrangler Wrangler`. An SE is slow
enough to finish typing before the bundled index finishes loading, and against
an empty index *every* query is unrecognised — which leaves one fallback,
treat the first word as a make. vPIC obliges: it lists a trailer manufacturer
called `WRANGLER`. The three-pass make resolution that exists to stop exactly
this is useless before there is an index to resolve against, so the bug it
fixed came back whenever the loader lost a race. An unrecognised query now
waits as a spinner until the index settles — loaded, or tried and failed — and
`loadIndex` re-plans whatever was typed while it loaded.

**And three failures that were the capture walk, not the app.** Worth naming
because each read as an app defect first: scrolling to a live configuration
list put the odometer field above the viewport and `scrollTo` only goes down;
a keyboard covered the matches on an SE so the tap meant for one landed on a
key; and `.idle` looked identical to "asked and got nothing" from outside, so
the walk photographed the generic questions before the request had left the
device. The last of those was half an app bug too — the owner saw the wrong
question flicker past — and is fixed in the app rather than worked around in
the test.

### The narrowest screen, and a claim I had to take back

The iPhone SE capture kept losing its last screen, and three theories went by
before the evidence did. Recording it because the sequence is the point.

The failure said "the oil job is missing from Jobs". It was: the Jobs
screenshot the capture now takes shows "My plan" holding Battery test, Brake
fluid, Brake inspection, Cabin air filter, Exterior lights and Suspension —
and no engine jobs at all, which is exactly what Odomind does when the
powertrain is unconfirmed. So the configuration had never been picked, three
screens earlier.

Why it had not been picked took one more run to establish, and the answer was
only visible because the walk now photographs the screen immediately after the
tap: **that screenshot came back byte-identical to the one before it.** The
scroll had reported success and the tap had been delivered, so the touch went
somewhere inert. The step bar floats over the bottom of the confirmation
screen, XCUI reports a row underneath it as hittable, and `scrollTo` therefore
stopped the moment the first configuration appeared at the bottom edge.

**The correction.** I wrote in a commit message that an iPhone SE owner "could
not pick the configuration their car was sold in". That is not true, and the
screenshot says so: the row's first line — the one naming the configuration —
sits above the bar and a finger lands on it. What is behind the blur is its
second line, the engine size and fuel. That is a legibility problem on the
narrowest screen, worth the bottom content margin it now has, but it is not a
blocker. The thing that could not tap the row was the test, and the test taps
the row's upper fifth now rather than its centre.

### What the screenshots confirmed was right

The yearless search returns "JEEP Wrangler" and "JEEP Wrangler JK" for
"wrangler" with no year typed, with "Type it in myself" visible without
scrolling. The permission step asks two optional questions and prompts only
after the matching tap, with "Not now" on each and "No account, and nothing
about you is uploaded" underneath. The shopping-area screen offers a town or
postal code when location is off, and says an area you pick stays selected.
Garage draws the artwork flush to the card's top edge with no nested grey
plate inside a white card, which was the brief's specific complaint. Dark mode
and the large-text pass are legible throughout.

### What they also showed, and is not a defect

The job detail for an engine oil change lists three specifications and all
three say **Not available**, each with a line saying where that value is
printed on the car. That is honest and it is also the real coverage position:
`odomind-catalog` run against a live runner reports `SPECIFICATIONS HELD (0)`
and `MATCHED PROFILE: none` for all three validation vehicles. Odomind ships
**no vehicle-specific fluid, tyre or pressure values at all** — every interval
it offers is a general template, labelled `verified: false`, and says so on
screen. Engine facts *are* vehicle-specific once a published configuration is
chosen, and live on the Configuration screen; the Specifications screen is for
the values that have no free, licence-clean source. Per the brief, this is
reported as partial rather than complete, and inventing a viscosity to fill
the row is the one thing that must not happen.

## What the capture does not produce, and why I stopped

The iPhone SE run captures six of the seven Build 3 screens. The missing one
is **parts opened from a job**, and the cause is the capture, not the app.

On a 375-point screen the configuration list ends underneath the step bar that
floats over the bottom of that screen. XCUI reports a row under that bar as
hittable, so `scrollTo` stops there and the tap goes to the bar. Five
approaches were tried: scrolling until hittable, an extra swipe, a coordinate
tap on the row's upper fifth, bottom content margin on the form, and finally
falling through the app's own "None of these is mine" — none of them selected
the row. Without a selected configuration the powertrain is unconfirmed, and
Odomind then correctly leaves engine oil out of the plan, which is what the
walk needs to reach parts.

**Every one of those runs had the app behaving correctly.** The screens that
did come back from the SE — Home, the configuration list, Jobs, the garage
with its photograph and credit — are all right, and the full-size run captures
all eight screens including parts. Chasing the seventh further was costing
more than it was proving, so it is recorded here instead: a known gap in the
capture on the narrowest display, with the app's behaviour at each step
verified from the screenshots that *were* taken.

## Device checks this release needs

CI cannot reach any of these.

1. **Search a real vehicle.** Type "wrangler" with no year. Confirm results
   appear, then that choosing one asks for the year afterwards.
2. **Change your mind.** Decode a VIN, then pick a different vehicle.
   Confirm the new one carries none of the old one's VIN, trim or engine.
3. **A real photograph.** Open Garage and confirm the car is a photo with a
   credit under it, and that the credit names an author for a CC licence.
   The screenshot pass now reaches Commons for real under
   `-odomind-live-providers`, so `build3-07-garage` is evidence too — but a
   miss there is a real outcome, not a failure, and is reported as one.
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
