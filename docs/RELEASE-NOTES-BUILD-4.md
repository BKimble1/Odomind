# Odomind 1.3 — Build 4

Paste the **What to test** section into App Store Connect's TestFlight notes.

---

## What to test

**The whole app looks different.** One light surface runs under every screen,
with white cards floating on it. Nothing should look like a grey box sitting on
a lit background — if a panel reads as a patch rather than a surface, that is a
bug worth reporting with a screenshot.

**Your car is on the dashboard, and you did not have to pick it.** With one
car there is no switcher at all. With several, pin one in the garage — long
press its card, or use the switch on the vehicle's own screen — and every
screen follows it. Switching cars from the picker moves the pin with you, so
the dashboard and Jobs can never end up on different cars.

**Odomind asks what you track before anything else.** On a fresh install the
first screen is five options. Pick any, or skip. What you pick decides which
jobs your starter plan begins with — say "tyres and brakes" and you should not
get eighteen ticked jobs. Everything else is still there to add in one tap, so
tell us if something you wanted was missing rather than merely unticked.

**Parts no longer asks where you are.** Set your shopping area once, from the
chip at the top right. After that, opening Parts lists shops near you without
a single tap. The postal-code field and the "Near me" button are gone. If Parts
ever asks for your location without you tapping "Use current location", that is
a bug.

**Parts knows something about your specific car.** Pick a configuration when
you add a vehicle and Odomind records the fuel grade from that configuration,
attributed to fueleconomy.gov. Anything else — oil viscosity, capacities, tyre
sizes — is a row that offers to record what your manual says. Enter it once and
it goes into every retailer search from then on.

**Fewer words everywhere.** The prose across the app is a quarter shorter than
1.2. Tell us where something now says too little.

## What is still not here, on purpose

**Manufacturer studio photos.** The images a dealership publishes are licensed
— Evox, Chrome Data, IMAGIN.studio, all quote-required. Odomind shows your own
photo first, then a properly credited photograph where one exists, then its own
drawing. The drawing is the only level that covers every car, which is why it
is there.

**Part numbers and fitment.** There is no free source. The government's own
parts endpoint returns regulatory letters, not fitment. Odomind opens a
retailer's search with the best terms it has and says plainly that it cannot
confirm a part fits. It will not invent a part number.

**Prices and stock.** Odomind holds neither, and does not estimate.

## Known gaps

- The bundled catalog carries one vehicle profile and no published
  specifications, so "what it takes" will be mostly empty until you fill it in
  or a licensed dataset arrives.
- The iPhone SE capture still does not produce the parts-from-a-job screenshot.
  The app behaves correctly there; the capture does not. See
  `docs/BUILD-3-NOTES.md`.

## Privacy, unchanged

Everything stays on your device. Your VIN, mileage and service history are
never sent to a retailer. Location is used only to list shops, only when you
ask for it, and never for maintenance.
