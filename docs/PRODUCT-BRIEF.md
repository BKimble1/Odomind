# Odomind — product brief

**Know your car. Know what's next.**

## The problem

Car maintenance apps fail in one of two directions. Either they know nothing
about your specific vehicle and give you a generic checklist, or they claim to
know everything and quietly make things up — an oil capacity that is wrong for
your engine, a tyre pressure taken from the sidewall instead of the door
placard, a "due now" derived from mileage nobody actually recorded.

The second failure is worse, because it looks like the first one working.

## What Odomind is

An iPhone app that holds one household's vehicle records and tells them what
maintenance is coming, based only on what it actually knows.

It is approachable for someone who has never thought about a transfer case, and
capable enough for someone who tracks differential fluid by axle.

## What it does

- **Add a vehicle** by year/make/model, or by VIN — typed or scanned. The VIN
  lookup is optional and asks before it sends anything.
- **Confirm the configuration** that changes which tasks apply: powertrain,
  transmission, drivetrain, and whether the engine is belt- or chain-driven.
  Any of these can be left unconfirmed, and doing so keeps the dependent tasks
  out of the plan rather than guessing either way.
- **Record mileage** in one field, whenever you think of it, with an optional
  reminder to do so.
- **Track maintenance** from a catalog of common and advanced tasks, or from
  tasks you define yourself. Six kinds of schedule are supported, including
  fixed odometer milestones that do not reset when you do the work early.
- **Log service** as a visit: one date, one odometer reading, one total, and as
  many tasks as were actually done.
- **Keep specifications** you transcribe from your owner's manual and door
  placard, used everywhere they are relevant.
- **Get reminders** for deadlines it is confident about, and clearly-labelled
  estimates for the ones it is projecting.
- **Take your records with you** as CSV, as a PDF for a buyer or a shop, or as
  a complete backup file.

## What it deliberately does not do

- It does not ship manufacturers' maintenance schedules, fluid specifications,
  capacities or tyre pressures. Those are either not redistributable or not
  verifiable, and a wrong one is worse than none.
- It does not infer operating tyre pressure from a sidewall maximum.
- It does not turn an estimate into a fact. A projection can warn you early; it
  can never mark something overdue.
- It does not assume unrecorded work was recently done, and it does not call
  everything overdue on day one. "I don't know" is a first-class answer that
  gets its own group on the Today screen.
- It does not read your vehicle. Where a manufacturer's own oil-life monitor is
  the real schedule, Odomind asks you to record the message rather than
  pretending to see it.
- It does not tell you the car is healthy. It says "nothing currently due based
  on your records", which is the only claim it can support.

## Non-goals for this release

No account, no sign-in, no backend, no subscription, no advertising, no AI key,
no social features, no repair marketplace, no GPS tracking, no OBD hardware.
The app works offline after setup and holds everything on the device.

## Who it is for

The first release targets US-market passenger vehicles, in miles or kilometres,
with the regional structure in place to extend. Multiple vehicles are supported;
a single vehicle never pays for that support — the picker disappears entirely
when there is only one.

## How success is measured

An owner can add their car, understand what is known about it, record mileage
and completed work, see reliable next-due information, get appropriate
reminders, and retrieve their records — without ever being shown a number the
app cannot stand behind.
