# Odomind 1.2 — Build 3

Paste the **What to test** section into App Store Connect's TestFlight notes.

---

## What to test

**Finding your car.** Type how you actually talk about it. "Wrangler" on its
own works now, and so does "camry", "f150", "chevy silverado" and "jeep
wrangler 2010". No year needed first — Odomind asks for the year *after* you
have chosen, when it knows which years that model was even built. Extra words
like "unlimited" or "sport" narrow the list rather than emptying it.

**Which engine is yours.** After you pick a vehicle, Odomind asks a service
which engine, gearbox and driven wheels that year, make and model was actually
sold with, and offers those. Pick the one that matches your car. If none of
them does — an import, a conversion, something the list misses — say so, and it
falls back to asking the two questions directly. Only the year, make and model
leave your phone for this. Not your VIN, not your mileage.

**A real photograph.** Your garage should show a photograph of a car like
yours, with the photographer credited underneath where the licence requires it.
The caption says what the match actually is: your model and year, your
generation, or a representative picture of the right body style. It never
claims to be your car, and it never tells you the colour or the wheels.

**Home, rebuilt.** Your vehicle at the top left, your shopping area at the top
right, the mileage and one way to change it, one search field with a clear
Jobs/Parts choice, the week ahead, what is due, and "Log service" pinned within
thumb reach. Gone: the vehicle's name printed twice within forty points, two
different "Update mileage" buttons, and the rounded box drawn around every one
of five sections.

**Tapping a job you are not tracking.** Search "brake fluid" on Home and tap the
result. You should land on that job — what it is, the interval Odomind would
use and where that came from, what it needs — with one button to start tracking
it. Previously this threw your search away and showed you the whole catalogue.

**Looking up a part.** Search "cabin air filter" and Odomind shows the cabin
filter, not a tyre size and a battery group. Open Parts from an oil change and
it arrives knowing what it is for.

**Permissions, once.** On a fresh install you are asked about reminders and
about location before the vehicle setup, each after a tap of your own, and both
skippable. If you already had Odomind, you get one quiet row offering to finish
that — not the whole welcome sequence again.

**Your shopping area.** The control at the top right of Home and Parts. Use
your current location or type a town or postal code. Whatever you choose stays
chosen across launches, and Parts looks for shops automatically once it has an
area.

---

## What Odomind still cannot do, and says so

**Part numbers.** Odomind has no licensed parts catalogue, so it cannot tell
you which oil filter fits your car. It builds the best search it can and hands
it to a retailer, whose own fitment check can answer. It will not invent a part
number, and it does not claim a price or stock it does not have. Getting past
this needs a paid data subscription — the candidates and the exact next action
are in `docs/PROVIDERS.md`.

**Fluid capacities, viscosities, tyre sizes.** Odomind ships none of these for
any vehicle, because it could not find them from a source it could both verify
and redistribute. Every screen that would show one says where that value is
written on your car instead — the manual, the door placard — and stores what
you enter with your name on it.

**Maintenance intervals** are general guidance, labelled as general guidance,
not your manufacturer's schedule.

**Catalog updates.** Nothing has been published to fetch yet. "Check now"
correctly reports that rather than claiming the service is down.
