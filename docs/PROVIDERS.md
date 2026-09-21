# Provider decision, Build 3

Six capabilities, and no provider supplies all six. This records which source
answers each one, what it actually returned when asked, and — for the one that
is blocked — exactly what would unblock it.

Everything below was verified live on a GitHub runner, because the authoring
host's egress proxy allows GitHub and refuses `vpic.nhtsa.dot.gov`,
`commons.wikimedia.org` and every other provider host. That is an access
limitation of the authoring environment, not evidence about the data.

**Evidence:** `provider-smoke` run
[35652317866](https://github.com/BKimble1/Odomind/actions/runs/35652317866),
2026-09-21, via `.github/scripts/probe-providers.py`. Re-runnable on demand.

## The six capabilities

| # | Capability | Source | Status |
| --- | --- | --- | --- |
| 1 | Vehicle discovery — makes and models, with or without a year | NHTSA vPIC | **Implemented** |
| 2 | Configuration — engine, body, drivetrain, trim | NHTSA vPIC VIN decode, **fueleconomy.gov configuration options**, owner confirmation | **Implemented, with stated gaps** |
| 3 | Maintenance schedules and specifications | Odomind's own versioned catalog | **Partial** — intervals yes, manufacturer fluid values no |
| 4 | Replacement-part applicability and manufacturer part numbers | — | **Blocked. Needs licensed data.** |
| 5 | Retail price, availability, store location | MapKit for stores; no offer source | **Partial** — stores yes, offers no |
| 6 | Photographs and vehicle matching | Wikimedia Commons | **Implemented** |

## 1 & 2 — vPIC, and what it does not tell you

`GetAllMakes` returned **12,364 makes**. Most are trailer, bus and equipment
manufacturers, which is why the bundled index keeps the full list for
recognition but suggests only from the 57 passenger makes.

`GetModelsForMake/Jeep` returned **24 models with no year supplied**,
including `Wrangler` and `Wrangler JK`. This is the endpoint that makes a bare
"wrangler" answerable, and it is the reason Build 2's year-first requirement
was unnecessary rather than unavoidable.

A VIN decode of a real 2010 Wrangler returned:

```
Make JEEP · Model Wrangler · ModelYear 2010
BodyClass Sport Utility Vehicle [SUV]/Multipurpose Vehicle [MPV]
DisplacementL 3.8 · EngineCylinders 6 · FuelTypePrimary Gasoline
DriveType 4WD/4-Wheel Drive/4x4 · Trim "Unlimited X"
```

and left **TransmissionStyle blank**. That blank is the point: a VIN decode is
a strong start and not a complete configuration, so Odomind asks the owner for
what the decode did not establish rather than presenting a guess as decoded
fact.

## 2 — fueleconomy.gov, for the configurations a vehicle was sold in

**What it is.** The US Department of Energy and EPA's fuel economy database,
with a documented REST API at `https://www.fueleconomy.gov/ws/rest/`. Its data
is a work of the United States Government and therefore in the public domain.
No key, so nothing secret has to travel in the shipped client.

**Why Odomind uses it.** The brief asks for "engine/body/trim choices using
provider-backed options". Build 2 asked the owner to pick their powertrain
from an enum containing every powertrain ever built, and their drivetrain from
every layout — a memory test, where a wrong answer silently adds or removes
whole jobs from the plan. This answers the question properly: which engine,
transmission and drivetrain combinations were this year, make and model
actually sold in.

**How it is used.** One `vehicle/menu/options` call per vehicle the owner is
adding, plus up to eight `vehicle/{id}` detail calls for the configurations
offered. Documented API, per-vehicle, on demand. Not scraped, not harvested in
bulk, and the response is cached by `URLCache` for the session.

**What it does not carry.** No maintenance schedules, no fluid capacities, no
part numbers. Nothing in the app suggests otherwise.

**How its vocabulary is mapped.** Conservatively, and the refusals matter more
than the matches:

| Provider value | Odomind reads it as | Note |
| --- | --- | --- |
| `Regular Gasoline`, `Premium Gasoline`, `Gasoline or E85` | gasoline | |
| `Diesel` | diesel | |
| `Electricity` | battery electric | |
| `Premium and Electricity`, `Regular Gas and Electricity` | plug-in hybrid | The provider's own way of saying so |
| `Front-Wheel Drive`, `Rear-Wheel Drive`, `All-Wheel Drive` | the same | |
| `Part-time 4-Wheel Drive` | part-time four-wheel drive | |
| `4-Wheel Drive` | four-wheel drive, sub-type unestablished | Odomind has a case for exactly this |
| **`4-Wheel or All-Wheel Drive`** | **unknown** | A real value, and it means the source does not distinguish them. That distinction decides whether a transfer-case job exists, so Odomind asks rather than guesses. |
| Anything unrecognised | unset, owner asked | |

A value the owner has confirmed is never overwritten by a provider value.
They were looking at their own car; the provider was looking at a table.

**Escape hatch.** Every such list is one market's list. "None of these is
mine" returns to the generic questions, because an import or a conversion is
not a reason to pick the closest wrong answer.

## 4 — Parts applicability is blocked, and here is the proof

`vPIC GetParts` is named in a way that invites the assumption that it answers
"which oil filter fits this car". It does not. Asked directly, it returned
records keyed:

```
CoverLetterURL · LetterDate · ManufacturerId · ManufacturerName ·
ModelYearFrom · ModelYearTo
```

These are manufacturer regulatory submission letters under 49 CFR Part 565/566.
There is no part number, no category and no fitment in the response. No free
public source of replacement-part applicability was found.

### What would unblock it

Part applicability at consumer scope is licensed data. The candidates, in the
order I would pursue them for a US-market consumer app:

| Candidate | Product to ask for | Why this one | Cost |
| --- | --- | --- | --- |
| **Auto Care Association** | ACES (applicability) + PIES (product attributes) reference data | The US standard both other vendors encode to. Membership-based; the standard itself is the vocabulary every US catalog speaks. | Membership + data subscription — **quote required** |
| **MOTOR Information Systems** | Parts data API | Sells parts data through an API rather than as a bulk drop, which suits an app; US coverage is their core market. | **Quote required** |
| **TecAlliance / TecDoc** | Consumer catalogue lookup service | Strong catalogue lookup, but verify it is the consumer lookup product and confirm **US** coverage — TecDoc's depth is European. | **Quote required** |

None of these publishes public pricing, so the next action is a scoping
enquiry, not a signup. **I have not contacted any vendor, created any account,
or accepted any agreement** — that is the owner's to do.

Until one is in place, Odomind does not pretend otherwise:
`ShoppingCapability.current` stays below `licensedOffers`, results are labelled
for what they are, and no part number is ever invented.

## 6 — Photographs from Wikimedia Commons

Two searches, both answered with usable, licensed images:

| Query | First result | Licence | Attribution |
| --- | --- | --- | --- |
| 2010 Jeep Wrangler Unlimited | `File:'10 Jeep Wranger Sahara Unlimited (MIAS '10).jpg` | Public domain | Bull-Doser |
| Toyota Camry XV40 | `File:TOYOTA CAMRY (XV40, ASIA) China (3).jpg` | CC BY-SA 4.0 | Dinkun Chen |

Eight licensed candidates each, with thumbnail URLs. The CC BY-SA result is
the instructive one: that licence **requires attribution**, so the resolver
carries licence and author with every image and the app shows them. An image
whose `extmetadata` has no licence is discarded rather than displayed.

Commons coverage and framing vary, so a match is labelled for what it is — this
exact model and generation, or a representative photo of the right generation
and body style — and never presented as a photograph of the owner's own car.

**EVOX** remains the paid alternative for consistent studio imagery keyed to
vehicle identifiers. Worth evaluating if the owner wants uniform photography;
it needs a commercial agreement and is **quote required**. Not pursued here for
the same reason as the parts vendors.

## What Odomind sends, and to whom

| Request | Carries | Never carries |
| --- | --- | --- |
| Model lookup | Year and make | VIN, location, history |
| Configuration options | Year, make and model | VIN, location, history, mileage |
| VIN decode | The VIN, after a disclosure naming the host | Anything else |
| Photograph | Year, make, model, generation | VIN, location, history |
| Nearby stores | A coarse location or a typed postal code | VIN, vehicle, history |
| Catalog update | Nothing about the owner or the vehicle | — |
