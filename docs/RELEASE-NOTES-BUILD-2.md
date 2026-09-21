# Odomind 1.1 — Build 2

Paste the **What to test** section into App Store Connect's TestFlight notes.

---

## What to test

Odomind has been rebuilt around four tabs: **Home**, **Jobs**, **Garage** and
**Calendar**. History has moved into Calendar, and Settings now lives under the
gear at the top right of Calendar.

**Your records are untouched.** Vehicles, mileage, service history, receipts and
schedules all carry over, and so do your backups.

Worth a look:

- **Home.** Your vehicle, a search that covers both jobs and parts, what is
  coming up, and one tap to record work. It no longer tells you everything is
  fine while it has no history to go on.
- **Jobs.** Your plan first, the rest of the library underneath. Try searching
  for "oil", "lube" or "tires".
- **A job screen.** "Mark as done" is near the top now. The schedule and the
  full history are collapsed underneath.
- **Recording work.** Tap the checkmark beside a job. It asks for the date and
  the mileage rather than assuming today for both, and you can tick several jobs
  from one visit.
- **Calendar.** Work you recorded, appointments you booked, real deadlines and
  estimates, told apart by icon and by label. Jobs due at a mileage that Odomind
  cannot date yet are listed separately rather than dropped on a made-up day.
- **Garage.** Your car, drawn. Tap a vehicle, then **Change the picture** to
  pick a colour, correct the body shape, or use your own photo.
- **Adding a vehicle.** Type "2010 Jeep Wrangler" into the search. Typing it in
  by hand and scanning a VIN both still work, and both work offline.
- **Appearance.** Settings → Appearance. System, Light or Dark, and it should
  hold everywhere — sheets and the subscription screen included.
- **Parts.** From a job, **Find parts**. It fills in what it knows about your
  vehicle and opens a retailer's own search. **Near me** asks for location at
  that moment and never before, and a postal code works just as well.
- **Odomind Pro.** Settings → Odomind Pro. Everything you already have stays
  free and stays yours.

Please report:

- Anything that reads as though Odomind is claiming to know something it does
  not.
- A vehicle illustration that looks wrong for your car — say which car.
- Anything unreadable, clipped, or too small to hit, particularly at larger text
  sizes.

## Known and deliberate

- **Specifications are mostly blank**, including for the Jeep. Odomind ships a
  value only when it has one from a source it can cite and redistribute, and it
  will not invent one. Each blank row now tells you where that particular value
  actually lives — the battery label, the filler cap, the capacities table —
  rather than sending everyone to the door placard.
- **No prices.** Odomind links to retailers' own searches. It does not carry
  prices, stock or "best price" claims, because it has no licensed source for
  any of them. What it does show is what you have actually paid.
- **Calendar export is a copy, not a sync.** Odomind can add dates to your
  calendar and says plainly that it cannot update or remove them afterwards. It
  never reads your calendar.
- **No AI assistant.** The questions one would answer are answered by the job
  screens, and there is no disabled button left behind pretending otherwise.

## For the release manager

`docs/BUILD-2-NOTES.md` has the feature status table and the device-only tester
checklist. `docs/PRO-SETUP.md` has the App Store Connect steps that are still
outstanding — **until they are done, the Pro screen will correctly report that
subscription details are unavailable**, which is the intended behaviour and not
a bug to file.
