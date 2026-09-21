# Data sources, terms and coverage

This is the honest account of where every value in Odomind comes from, what it
is used under, and what Odomind refuses to claim.

The same information is in the app, under **Garage → Where the data comes
from**, because the answer to "how do you know that?" belongs in front of the
person relying on it.

## Summary

| Source | Used for | Redistributable | Ships in the app |
| --- | --- | --- | --- |
| NHTSA vPIC | VIN decoding, make/model lookup | Not established | No — queried at runtime, cached on device |
| Odomind make list | Routing a search to the right make | Yes | Yes — 43 names, written for Odomind |
| Odomind maintenance templates | Vehicle-independent task templates | Yes | Yes |
| Odomind engine notes | Task-applicability facts (e.g. belt vs chain) | Yes | Yes |

**Odomind ships no manufacturer maintenance schedules, fluid specifications,
capacities, viscosities or tyre pressures.** This is not an oversight; see
[What is deliberately missing](#what-is-deliberately-missing).

## NHTSA vPIC

**What it is.** The U.S. National Highway Traffic Safety Administration's
Product Information Catalog and Vehicle Listing, at
<https://vpic.nhtsa.dot.gov/api/>.

**What Odomind uses it for.** Identification only: decoding a VIN into year,
make, model, body class, engine displacement, cylinder count, fuel type,
transmission style and drive type, and listing models for a make and year.

**Endpoints used.**

- `GET /api/vehicles/decodevinvalues/{vin}?format=json&modelyear={year}`
- `GET /api/vehicles/getmodelsformakeyear/make/{make}/modelyear/{year}?format=json`

`GetParts` is **not** used and is not an aftermarket parts catalog: it returns
manufacturer regulatory document submissions under 49 CFR Parts 565 and 566.

**What vPIC does not solve, and Odomind does not pretend it does.** Complete
manufacturer service schedules, oil grades and capacities, replacement-part
fitment, and every trim and option combination are all outside it. A vPIC match
identifies a vehicle. It does not say what fluid that vehicle takes, when it is
due for anything, or which filter fits it. The app's copy is written to that
boundary, and the type system helps: `VehicleIdentificationProvider` cannot
return a specification, because identification and specification are different
problems with different sources.

**The make list is Odomind's own.** vPIC's all-makes endpoint returns thousands
of entries, including trailer and industrial-equipment manufacturers, which is
accurate and useless as a suggestion list. Odomind carries a list of 43 common
consumer makes, written for this app, purely to decide which make to *ask vPIC
about*. Every model name the owner sees comes from the provider. A make that is
not on the list is not blocked: typing it still reaches the provider, and manual
entry always works.

**Terms — reviewed for Build 2.** Build 1's note here said vPIC carried no
public-use permission. That was too strong, and it is corrected.

What is established: the API is free, public, and needs no registration and no
API key. NHTSA's own FAQ says so, asks that large batch jobs run outside US
business hours, and applies automated rate control rather than a quota. Those
are operating conditions, not a licence restriction, and Odomind's use — a
handful of requests while somebody adds a car — is nowhere near them. NHTSA
also publishes standalone VIN-decoding databases for download, which is not
the behaviour of an agency withholding public use.

What is **not** established, and what Build 1 conflated with it: an explicit
open-data licence granting **redistribution**. Works of the U.S. federal
government are generally outside domestic copyright (17 U.S.C. § 105), and that
is a reasonable basis for believing redistribution would be fine — but it is an
inference, not a published grant, and it says nothing about other jurisdictions.

So the behaviour is unchanged and the reasoning is now accurate: Odomind queries
vPIC at runtime and caches on the owner's device. It does not ship a vPIC
dataset, because no published term says it may. If NHTSA publishes an explicit
licence, this becomes a straightforward change.

**Rechecked.** September 2026, against
<https://vpic.nhtsa.dot.gov/api/home/index/faq>. Recheck before relying on it:
terms change, and nothing here is legal advice.

**Attribution.** "Vehicle identification data from the NHTSA Product
Information Catalog and Vehicle Listing (vPIC)." Shown in the app.

**Known limitations.** No published service-level agreement, uptime guarantee
or documented rate limit. Coverage is strongest from model year 1981. Trim,
series, engine model and transmission fields are frequently blank or ambiguous;
`DriveType` reports "4WD/4-Wheel Drive/4x4" without distinguishing part-time
from full-time, and "4x2" without saying which axle. vPIC contains **no**
maintenance schedules, fluid specifications, capacities or fitment data.

**How Odomind handles that.** Anything vPIC leaves blank is reported to the
owner as missing rather than filled in. A "4WD" answer maps to a general
four-wheel-drive case, not to a guessed sub-type. Camshaft drive is never
inferred, because guessing it either invents a timing-belt service or wrongly
rules one out. Every decoded value is recorded with `referenceSourced`
provenance and is never shown as verified.

**Privacy.** The VIN is the only identifying value Odomind sends anywhere. The
app discloses the destination and asks for confirmation before the first
lookup, and every failure path leads back to typing the vehicle in by hand.
The VIN is never written to a log, an analytics event or a crash report.

## Odomind maintenance templates

Vehicle-independent starting points for common tasks, written for this app and
shipped with it. Every value carries `generalTemplate` provenance and is
labelled "General guidance" wherever it appears.

These are **not** a manufacturer's schedule. Your vehicle's published intervals
take precedence and can differ substantially.

## Odomind engine notes

A small set of engine-family attributes that decide whether a task applies at
all — principally whether an engine drives its camshafts by belt or by chain.
Carries `referenceSourced` provenance: useful, often correct, and **not**
checked against the manufacturer's own service documentation, so nothing
sourced here is marked verified.

## What "verified" means

Exactly one thing, enforced in code by `Provenance.isVerified` and by the
catalog validator:

> A person checked the value against manufacturer documentation, recorded a
> citation for it, and recorded the date they checked.

A value returned by a VIN decoder is not verified. A value a maintainer
believes to be right is not verified. A value generated by a model is not
verified. The app has no way to display a verified badge for anything else.

Provenance has four cases:

| Origin | Meaning |
| --- | --- |
| `manufacturerSourced` | Transcribed from manufacturer documentation, with a citation and a review date. The only origin that can be verified. |
| `referenceSourced` | From an identification or reference source. Useful, unverified. |
| `generalTemplate` | Vehicle-independent guidance. Never presented as a manufacturer's schedule. |
| `userEntered` | The owner transcribed it from their own manual or placard. Trusted, and never badged as manufacturer-verified. |

## What is deliberately missing

The bundled catalog contains a profile for the 2007–2011 Jeep Wrangler (JK)
with the 3.8 L V6. That profile carries the engine's identity and the fact that
it is **chain**-driven — enough to keep an expensive timing-belt service out of
a plan where it does not belong.

It carries **no** oil viscosity, oil capacity, tyre size, cold tyre pressure,
fluid specification or service interval.

That is because those values could not be both verified against an authoritative
source and legally redistributed within this app. Shipping a plausible-looking
number that nobody checked would be worse than shipping none: an owner who trusts
a wrong oil capacity ends up with a wrong oil level.

Instead, every one of those fields shows as "Not available" with a one-tap path
to record the real value, and the hint says **where that particular value
actually lives**. Build 1 told everyone to check the door placard, which is
right for original tyre size and cold pressures and wrong for a battery group
size, a filter part number or a fluid capacity. `SpecificationKind.sourceHint`
now carries a per-field answer. Once recorded, the value is used everywhere a
manufacturer value would be.

**Build 2 tried and failed to add sourced values for the owner's Jeep.** The
authoring host's network policy blocks manufacturer sites and NHTSA outright, so
no value could be retrieved, let alone checked against a citable source and
reviewed for redistribution. Inventing one was never an option. This is an
external dependency, recorded as one: it needs a session with reachable
manufacturer documentation, not more code.

**Installed equipment is separate from factory specification.** Every
`Specification` carries an `EquipmentBasis` — factory, installed now, or the
owner's preference — so a Jeep on aftermarket wheels and tyres can record what
is actually fitted without overwriting what the factory published. Owner entries
win where they exist and the superseded catalog value stays visible. And a cold
tyre pressure is never derived from a sidewall maximum: `isVehiclePlacardOnly`
marks the fields where that inference is forbidden, because a sidewall number is
a maximum and not an operating pressure.

Drivetrain is deliberately not pre-filled for that profile either: the JK
Wrangler was sold in both two- and four-wheel-drive forms, and that answer
decides whether transfer-case and differential service appear at all.

## Adding a verified value

The procedure — and what the validator will reject — is in
[CATALOG-AUTHORING.md](CATALOG-AUTHORING.md).

## Catalog updates

A catalog always ships inside the app binary and is the floor. On top of that,
`CatalogUpdateService` can fetch a newer reviewed one.

**The trust model, stated as what it is.** Authenticity comes from TLS to one
pinned host: Odomind fetches the manifest over HTTPS from a fixed URL and
refuses a catalog URL that is not HTTPS on that same host. The SHA-256 in the
manifest proves the downloaded file matches the manifest that described it —
that catches a truncated, corrupted or proxy-mangled download, and it is **not**
a signature. The manifest and the hash come from the same place, so anyone able
to serve a forged manifest could serve a matching hash. Making it a real
authenticity check means a detached signature verified against a public key
compiled into the app. That is not built, and the code says so where somebody
would otherwise assume otherwise.

**What an update has to survive before it is installed.** Schema version must
match this build's. Version must be strictly newer, compared numerically so
2026.10.2 beats 2026.9.10. The declared byte count must match and be plausible.
The checksum must match. It must parse. It must describe itself consistently.
And it must pass `CatalogValidator` with no errors — the same gate CI runs with
`--strict`. An update that would fail the project's own check does not get
installed on a phone.

**Failure leaves everything alone.** Installation writes to a staging file and
swaps it in with `replaceItemAt`, so there is no half-installed state to
recover from. A corrupt, unreadable, older or unreachable update leaves the
previous catalog in charge, and a stale installed file that is older than the
bundled one is ignored on load — a file on disk must not undo a fix that shipped
in the app.

**Nothing silently changes an owner's schedule.** `PlanBuilder.applyCatalogUpdate`
parks changed guidance as a **proposal**. The owner's active schedule keeps
running until they accept it, and an owner's own override is never overwritten.

**Source coverage is a separate question from whether the updater works.** The
updater works and is tested. It has nothing to publish yet, because the sourcing
problem above is unsolved. Those two facts are kept apart deliberately: the app
does not say it is checking for updates as a way of implying it has data.
