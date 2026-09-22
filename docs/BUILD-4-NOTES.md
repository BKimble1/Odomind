# Odomind Build 4 — implementation notes

The whole interface rebuilt on one surface, the app narrowed to one car at a
time, and Parts given something true to say about a specific vehicle.

Provider evidence is in [`PROVIDERS.md`](PROVIDERS.md); the licence position on
vehicle images and parts fitment is in [`DATA-SOURCES.md`](DATA-SOURCES.md).

## The headline

Build 3 had five slightly different card treatments, a vehicle switcher on
every screen for people who mostly own one car, and a Parts screen that asked
where you were on every visit and then had nothing per-car to tell you. All
three were the same mistake in different clothes: the app asking the owner to
do work it could have done itself.

## What changed

### One surface

`Dashboard.swift` holds the kit every screen now draws from — `LuminousField`,
`.cardSurface()`, `IconChip`, `StatusPill`, `StatTile`, `AttentionCard`,
`PanelCard`, `DateChip`. The shared `Card` was moved onto the same treatment,
which carried the change into every screen that already used it.

The field is two soft radials over the page colour, each fading to **the same
colour at zero opacity** rather than to `.clear`. `.clear` is transparent
black, so a gradient running into it passes through grey and leaves the dirty
edge that makes a blend look cheap.

### One car

`dashboardVehicle` is what every screen reads. One vehicle means that one and
no switcher at all. Several means the pinned one, and failing that the
selection.

Pinning and selection used to be two names for "the car this is about" and
could disagree, so the dashboard could sit on one car while Jobs sat on another
with nothing on screen to explain it. Pinning now selects, and picking from the
switcher moves the pin.

### One answer to "where do you shop"

`NearbyStoreFinder` no longer owns a `CLLocationManager`. There is exactly one
object in the app that can raise a location prompt —
`ShoppingLocationService` — and it only does so when somebody taps "Use
current location". Parts searches from the coordinate that service already
holds, on open and again whenever the area changes. The postal-code field and
the "Near me" button are gone.

### The first question

A new owner is asked what they want to keep an eye on before anything else.
The answer narrows which jobs the starter plan ticks, via
`AppModel.recommendedTaskIDs(from:)`. Skipping is recorded as an answer, so
the question is put once; an empty stored set was previously
indistinguishable from never having been asked.

Two guardrails. An answer that would leave nothing ticked falls back to the
ordinary recommended set, because an empty starting plan reads as "Odomind
found nothing to track". And nothing is hidden — every job the catalog offers
the vehicle stays on the selection screen, so a wrong answer costs a tap.

## Parts for a specific car

The bundled catalog ships **one** vehicle profile (2007–2011 Jeep Wrangler
3.8 L) carrying **zero** specifications and **zero** schedule rules. That is
the real reason parts lookup did not feel specific to anything: "what this
vehicle takes" was empty for every car, and every retailer search went out as
bare year-make-model.

What Build 4 does about it, within what Odomind is allowed to state:

| Source | What it gives | Status |
| --- | --- | --- |
| fueleconomy.gov configuration | Fuel grade | **Implemented.** Recorded against the vehicle when the owner picks a configuration, attributed, `referenceSourced` |
| Owner's own entry | Any specification | Already worked; now one tap from the Parts row that lacks it |
| ACES / PIES, MOTOR, TecDoc | Part numbers, fitment | **Blocked.** Licensed |
| Manufacturer service data | Viscosity, capacities, torques | **Blocked.** Licensed |

Exactly one specification comes from the free tier because that provider states
exactly one. Viscosity, capacities, tyre sizes and part numbers are not in this
data and are not inferable from it — a 3.8 L V6 does not imply an oil grade,
and guessing one would put a number the owner might buy against a source that
never said it. `testNothingBeyondTheFuelGradeIsInvented` fails if a later edit
starts inferring them.

A specification Odomind does not have is now a row that leads to the editor
rather than a dead "Not known". For most vehicles that is the normal case, and
the answer is in the manual in the glovebox. Once recorded it goes into every
retailer search from then on.

## Vehicle images

The brief asked for the image the dealership puts out, on every car, placed
like the reference.

**Placement and lighting: done.** `StudioVehicleImage` presents the vehicle cut
out, lit from above, floating on a soft elliptical ground shadow, with nothing
framing it. Build 3 drew the car on a grey plate inside a white card inside a
grouped background — three nested frames around one vehicle. There is no plate
now; the only thing under the vehicle is its own shadow, which is what makes a
cut-out read as an object rather than a sticker. It is the single image
component in the app: `VehiclePortrait` and `RemoteVehiclePhoto` are gone.

**The manufacturer studio image itself: blocked, and not by effort.**
Manufacturer press and configurator renders are licensed. The three vendors
that supply them by year/make/model/trim — Evox Images, Chrome Data (J.D.
Power), IMAGIN.studio — are all quote-required commercial agreements. None has
been contacted, because the standing constraint is not to purchase services or
accept agreements on the owner's behalf.

`LicensedVehicleImageProvider` is the seam. It is a protocol with one
conformance, `UnlicensedVehicleImageProvider`, which returns `nil` for every
vehicle. The day there is a licence, one type conforms and the ladder picks it
up; nothing else changes. A protocol is not a feature, and nothing in the app
claims an image it does not have.

So every vehicle gets something, in this order:

1. The owner's own photo.
2. A licensed studio image — unreachable in this build.
3. A photograph from Wikimedia Commons, with the credit its licence requires.
4. Odomind's own drawing.

Levels 3 and 4 are what ships. Level 4 is a vector side profile rather than a
photographic three-quarter: it is the only level with **100% coverage**, which
is what "every single car should have one" requires.

## Verified

- Build, unit tests, domain tests, catalog validation and the full UI suite
  green in CI.
- The tracking question, the pin, the dashboard vehicle, distance this month
  and the parts chain covered by tests in `DashboardAndInterestsTests` and
  `ConfigurationOptionSpecificationTests`.
- The first-run flow covered by a UI test that starts from a fresh install.

## Not verified from here

Live provider calls. The authoring host's egress proxy allows GitHub and
nothing else — `vpic.nhtsa.dot.gov` and `www.fueleconomy.gov` both return
`CONNECT tunnel failed, response 403`. Live evidence comes from the
`provider-smoke` workflow on a runner, not from this machine, and is recorded
in `PROVIDERS.md` rather than asserted here.

## Tooling

`check-ui-identifiers.py` could not see an identifier written as a conditional
and reported `shopping.location` — which the app does set — as missing. It now
reads every string literal inside an `accessibilityIdentifier` call, counting
parentheses so an interpolated identifier's own closing paren does not
truncate it.
