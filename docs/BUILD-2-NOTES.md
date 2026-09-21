# Build 2 — what changed, and why

Build 2 is the second product milestone, not Apple build number 2. Build
numbers still come from App Store Connect.

## The problem Build 1 had

Build 1 was correct and unwelcoming. It knew exactly what it did not know and
said so on every screen, which produced a home screen offering a green
all-clear above fifteen "Needs setup" alerts, a maintenance list where nearly
every row repeated the same sentence, a job screen that pushed the action below
the fold behind three explanatory cards, and a Garage that was mostly links to
Settings under a bank icon.

None of that was dishonest. It was just unusable, and the fix was not to claim
more — it was to say the same true things once, quietly, next to something the
owner can do about them.

## What changed

**Four tabs: Home, Jobs, Garage, Calendar.** History folded into Calendar,
because past work and future work are the same question asked in two
directions. The gear moved to Calendar's top right, which is what the brief
asked for and what leaves Garage free to be a garage.

**Home leads with the vehicle, then search, then a short agenda.** No all-clear
while history is unknown. When nothing is actionable it says the plan is ready
and offers the one action — record the last oil change — that would make it
useful.

**Jobs separates "my plan" from the library.** Setup state lives on the job,
where it can be acted on, instead of being repeated down a list.

**A job screen leads with its status and "Mark as done".** Schedule provenance
and full history collapse underneath. A checkmark opens a confirmation sheet:
the date and the mileage both have to be said, and the last reading is shown
with the date it was taken rather than pre-filled as today's.

**Calendar shows four visibly distinct things** — recorded work, appointments,
real deadlines, estimates — with icons and words, never colour alone. A job due
at a mileage with no defensible date goes in a named list rather than on an
invented square.

**Appointments are a new concept, deliberately not service records.** Booking a
visit records an intention. It does not move a deadline and is never counted as
work done.

**Vehicles are drawn.** Nine body-style silhouettes and two matched Jeep JK
drawings, authored in one coordinate space so every vehicle shares a ground
line, a wheel style and a stroke weight.

**Vehicle search is real.** "2010 Jeep Wrangler" is parsed and the models come
from vPIC.

**Odomind Pro exists**, as one entitlement with two durations, built on
StoreKit 2.

## Decisions worth recording

### Side profile, not three-quarter

The brief asked for three-quarter illustrations. What it asked those
illustrations to *achieve* was that a four-door Wrangler look like a four-door
Wrangler — the brief says so itself: body shape, generation and door count
matter more than the angle.

Profile is where all three read most reliably, and it is the only view in which
nine body styles could be drawn to one consistent scale, ground line and stroke
weight by hand. A hand-authored three-quarter set would have been nine separate
perspective problems and would have come out less consistent, not more
impressive. The Wrangler's flat screen, hard top, square arches, round headlamp
and tailgate spare are all profile cues.

The geometry was rendered and looked at before it was committed, which is what
caught a front overhang far too long for a JK and a generic off-roader that was
indistinguishable from the matched Jeep drawing.

### Managed calendar sync is deferred, and not advertised

Section 8 of the brief describes Pro managed calendar updates; section 12's
capability table does not list them, and section 12 says not to put anything on
the paywall that is not implemented and tested.

Managed sync needs full calendar access, an Odomind-owned calendar, a stored
event mapping per plan item, idempotent reconciliation after every service,
schedule and mileage change, detection of calendars and events the owner
deleted, and a clear choice about what happens to existing events when sync is
turned off. Half of that is worse than none: an app that overwrites a calendar
entry somebody edited, or recreates an event they deleted, is a bug that
follows them around.

So it is not built and it is not on the paywall. What *is* built and free: a
single event through the system editor, which needs no permission at all, and a
reviewed batch export that asks only for write-only access and says plainly
that it cannot update or remove what it added.

### No AI assistant

Not built, and no disabled "coming soon" button left behind. A local model
cannot fetch a live price or a current recall, and an on-device model carries a
download and a device requirement. The questions it would have answered are
answered by the job screen, the specifications and the parts links.

### Prices are a hypothesis

$2.99 and $19.99 are a starting point to validate, not a researched optimum.
Every price an owner sees comes from StoreKit, so changing it in App Store
Connect changes the app with no new build.

## Feature status

| Feature | Status |
| --- | --- |
| Four-tab navigation, shared route destinations | Implemented and verified |
| Semantic design tokens; System/Light/Dark, applied to sheets and the paywall | Implemented and verified |
| Branded launch screen — emblem on white, "Powered by Idlery", static, no delay | Implemented, device check needed |
| Home: vehicle header, Jobs/Parts search, week strip, agenda, logging | Implemented and verified |
| Jobs: my plan vs library, synonym search, advanced toggle | Implemented and verified |
| Job screen: action above the fold, collapsed schedule and history, per-field spec hints | Implemented and verified |
| Quick-log confirmation sheet, multi-job visits, double-submit guard | Implemented and verified |
| Calendar: month grid, day agenda, list view, four distinct kinds, Today, search | Implemented and verified |
| Appointments as a stored concept distinct from service records | Implemented and verified |
| Unscheduled "mileage based, date not yet estimated" list | Implemented and verified |
| Batch Apple Calendar export with review, write-only access, duplicate warning | Implemented, device check needed |
| Single-event Apple Calendar export through the system editor | Implemented, device check needed (unchanged from Build 1) |
| Managed two-way calendar sync | **Deferred by decision** — see above. Not advertised anywhere in the app |
| Garage: editorial vehicle cards, no settings links, garage symbol | Implemented and verified |
| Vehicle artwork: 9 body styles, 2 matched Jeep JK drawings, paint choice, photo mode | Implemented and verified |
| Artwork for other specific models | **External dependency** — each one is a drawing to author. Everything else falls back to a body style, labelled as one |
| Vehicle search backed by vPIC, debounced, cancelled, cached, stale-guarded | Implemented and verified against recorded fixtures; **external dependency** for live checks — vPIC is blocked from the authoring host, so the `provider-smoke` workflow is the only live proof |
| Three-step onboarding, reminders offered early, no camshaft question | Implemented and verified |
| Parts: specification prefill, retailer search links, copy-to-paste fallback | Implemented and verified |
| Nearby parts shops via MapKit, manual postal-code path | Implemented, device check needed |
| Live product offers, prices, stock | **External dependency** — needs a licensed provider with terms and credentials. `ShoppingCapability.current` is pinned to `retailerSearchLink` and the offer UI is unreachable |
| Regional cost estimates | **External dependency** — no source. The job screen shows what the owner actually paid and says it carries no regional estimate |
| Catalog update fetch, checksum, validation, atomic install, last-known-good | Implemented and verified |
| Reviewed catalog content to publish | **External dependency** — manufacturer sources are unreachable from the authoring host. The updater works; it has nothing to serve yet |
| Manufacturer specification values for the 2010 Jeep Wrangler JK | **External dependency** — see `docs/DATA-SOURCES.md`. No value was invented |
| Pro entitlement: purchase, pending, cancel, restore, renewal, revocation, grace | Implemented, **device check needed** — sandbox and TestFlight purchases are unverified |
| App Store Connect products and agreements | **External dependency** — owner-only. `docs/PRO-SETUP.md` has the exact values |
| Free plan is one vehicle; Pro removes the limit | Implemented and verified |
| Grandfathered vehicle allowance for Build 1 users | Implemented and verified |
| On-device receipt text extraction with a review step | Implemented, device check needed (parsing is unit-tested; Vision OCR is not exercised on a simulator) |
| Spending trends and service dossier | Implemented and verified |
| Build 1 store and backup compatibility | Implemented and verified |
| AI assistant | **Deferred by decision** — see above |

"Verified" above means exercised by the test suite or by a screenshot that was
actually looked at. "Device check needed" means it compiles and is covered by
whatever can be covered without hardware, and the hardware half is listed in
the tester checklist below.

## Tester checklist — the parts CI cannot reach

1. **Launch screen.** Cold launch. The emblem should be on white with "Powered
   by Idlery" near the bottom, with no visible seam as the app takes over and
   no pause once it has.
2. **Reminders.** Accept at onboarding; confirm iOS asks once. Let a reminder
   fire. Tap it and confirm it opens the right vehicle and job.
3. **Reminder refusal.** Decline, then check Settings → Notifications offers the
   iOS Settings link and that everything else still works.
4. **Calendar, single event.** From a job, **Add to Calendar**. Confirm the
   event is one day, not two.
5. **Calendar, batch.** Calendar → Add upcoming items. Confirm the permission
   prompt is write-only, that the review lists what you expect, and that running
   it twice warns rather than silently duplicating.
6. **Calendar refused.** Decline, and confirm the in-app calendar and the
   single-event path still work.
7. **VIN scan.** Camera permission, a real plate, and the confirm step.
8. **Receipt scan.** A real receipt. Check the date, shop and total it offers,
   and that nothing is saved until you tap **Use**.
9. **Nearby shops.** Tap **Near me** and confirm the permission prompt appears
   then and not before. Decline, and confirm the postal-code path works.
10. **Purchases.** With a sandbox account: buy monthly, cancel, restore, buy
    yearly. Let an accelerated renewal lapse and confirm records stay editable
    and reminders keep firing.
11. **Upgrade from Build 1.** Install Build 1, add vehicles and records, then
    install Build 2 over it. Garage, mileage, history, attachments and schedules
    should all still be there, and the vehicle allowance should match what was
    there before.
12. **Appearance.** Set Dark in Settings, then open the paywall and a sheet.
    Both should be dark. Relaunch and confirm it stuck.
