# Authoring the maintenance catalog

The catalog is one JSON file:
`OdomindCore/Sources/OdomindCore/Resources/odomind-catalog.json`.

It is hand-edited, schema-validated on every load, and gated in CI.

## Validating

```bash
swift run --package-path OdomindCore odomind-catalog validate \
  OdomindCore/Sources/OdomindCore/Resources/odomind-catalog.json --strict

swift run --package-path OdomindCore odomind-catalog summary \
  OdomindCore/Sources/OdomindCore/Resources/odomind-catalog.json
```

`--strict` fails on warnings as well as errors. CI runs it that way, so the
catalog is warning-free at all times.

## Structure

```jsonc
{
  "schemaVersion": 1,
  "catalogVersion": "2026.09.1",   // bump on every content change
  "publishedOn": "2026-09-20T00:00:00Z",
  "coverageNotice": "…",           // shown in the app; must not overstate
  "sources": [ … ],                // every source, with its terms
  "taskDefinitions": [ … ],        // vehicle-independent tasks
  "vehicleProfiles": [ … ],        // per-vehicle facts, specs and schedules
  "demoContent": { … }             // fictional sample data
}
```

## Rules the validator enforces

These are not style preferences. Each one exists because breaking it would make
the app lie.

| Rule | Why |
| --- | --- |
| A `manufacturerSourced` value needs a `sourceReference` **and** a `reviewedOn` | "Verified" has to mean someone checked it and recorded when |
| A catalog-wide default rule cannot be `manufacturerSourced` | A default applies to every vehicle, so it cannot be one manufacturer's schedule |
| Cold tyre pressure cannot come from a `generalTemplate` | It is on the vehicle's placard. A general value would be unsafe |
| A `userEntered` value cannot appear in a published catalog | That origin means the owner typed it |
| Task ids are unique, lowercase kebab-case | Service history references them forever |
| A profile schedule cannot cite a source with `allowsRedistribution: false` | We may query such a source, not ship it |
| No two schedules for the same task and usage profile | One of them would silently win |
| Sample content carries no VIN and states that it is fictional | Sample data must never look like a real record |
| A check-only action should not use a `distance` or `distanceOrTime` rule | That reads as a replacement interval, which is the confusion this app exists to avoid |

## Adding a task

```jsonc
{
  "id": "cabin-air-filter",
  "title": "Cabin air filter",
  "purpose": "Filters the air coming into the passenger compartment…",
  "category": "climate",
  "action": "replace",
  "applicability": { "requiresCombustionEngine": true },
  "isAdvanced": false,
  "relatedSpecifications": ["cabinAirFilterPartNumber"],
  "searchKeywords": ["pollen filter", "hvac"],
  "defaultRule": {
    "type": "distanceOrTime",
    "distance": { "amount": 15000, "unit": "miles" },
    "time": { "count": 12, "unit": "months" }
  },
  "defaultRuleProvenance": {
    "origin": "generalTemplate",
    "attribution": { "sourceName": "Odomind maintenance templates" },
    "scope": {}
  }
}
```

**Leave `defaultRule` out** when the honest answer depends on the vehicle —
spark plugs, timing belts, gearbox and differential fluid. The app then shows
the task under "Needs setup" with a one-tap editor that takes the interval from
the owner's manual. That is a better outcome than a number that is wrong for
most vehicles.

`applicability` is how a task stays out of a plan it does not belong in. `null`
means "does not care". A condition that depends on a configuration field the
owner has not confirmed produces a question, never a silent yes or no.

## Adding a verified manufacturer value

This is the only way a value gets a verified badge.

1. **Find it in manufacturer documentation.** The owner's manual, the service
   manual, or the placard in the driver's door opening. Not a forum, not a parts
   site, not a model.
2. **Check the fitment.** Model year, engine, transmission, drivetrain, market
   and any relevant option. If the value differs by engine and you cannot tell
   which engine the profile covers, narrow the profile before adding the value.
3. **Record the citation.** A URL, a document number, or a manual and page.
4. **Record the review date and who did it.**

```jsonc
{
  "kind": "engineOilCapacityWithFilter",
  "value": { "kind": "volume", "amount": 4.7, "unit": "liters" },
  "basis": "factory",
  "appliesToNote": "3.8 L V6, with filter change",
  "sourceID": "some-manufacturer-source",
  "provenance": {
    "origin": "manufacturerSourced",
    "attribution": {
      "sourceName": "2010 Jeep Wrangler Owner's Manual",
      "sourceReference": "page 402",
      "reviewedOn": "2026-09-20T00:00:00Z",
      "reviewedBy": "your name",
      "datasetVersion": "2026.09.1"
    },
    "scope": { "modelYears": [2010], "engineDisplacementLiters": [3.8] }
  }
}
```

The `sourceID` must point at an entry in `sources` whose `allowsRedistribution`
is `true`. If it is not, the value cannot ship — query it at runtime instead, as
vPIC is.

**If any step cannot be completed, do not add the value.** The app already
handles absence well: it shows "Not available" with a path to record the real
value, which is correct and useful. A wrong oil capacity is not.

## Changing a schedule that owners already have

Bump `catalogVersion`. On next launch `PlanBuilder.applyCatalogUpdate` parks the
change as a proposal on each affected plan item and leaves the running schedule
alone. The owner sees it under Maintenance → Review schedule changes and decides.

An owner's own override is never touched by an update, accepted or not. This is
asserted in `CatalogUpdateTests`.

## Bumping the schema

`MaintenanceCatalog.currentSchemaVersion` gates loading: a catalog with a
different version is rejected with a readable message rather than partially
decoded. Bump it only when the decoded shape changes incompatibly, and add a
test that the old shape is refused.

## Publishing an update — not yet done, and what it takes

Verified on 2026-09-21 against the live repository:

```
$ curl -o /dev/null -w '%{http_code}' \
    https://raw.githubusercontent.com/BKimble1/Odomind/catalog/manifest.json
404
```

The `catalog` ref does not exist. The branch list is
`claude/laughing-franklin-89ryeu`, `claude/odomind-build-2-run4k8` and
`codex/testflight-windows` — no `catalog`, and no `main`. So the update
feature in the shipped app has never had anything to fetch, and never will
until somebody publishes.

The app no longer pretends otherwise. A 404, 410 or 403 on the manifest
returns `.notPublished` and says "No catalog updates have been published
yet"; only a genuine network failure or a 5xx is reported as the service
being unreachable. Settings says the same thing in the Updates footer
before you tap Check now, so it is not something you discover by reading
what looks like an error.

**This is the remaining owner action, and it is deliberately not taken
here**: publishing means pushing a branch this session has no permission to
create. To turn the feature on:

1. Create an orphan branch named `catalog` on `BKimble1/Odomind`
   (`git switch --orphan catalog`). It holds published data only — no code,
   so a bad catalog can never be a bad build.
2. Put the catalog file on it, at a stable path, e.g. `odomind-catalog.json`.
3. Beside it, `manifest.json`:

   ```json
   {
     "catalogVersion": "2026.10.1",
     "schemaVersion": 1,
     "publishedOn": "2026-10-01T00:00:00Z",
     "url": "https://raw.githubusercontent.com/BKimble1/Odomind/catalog/odomind-catalog.json",
     "sha256": "<lowercase hex sha256 of that exact file>",
     "byteCount": <its exact size in bytes>,
     "summary": "One line the owner will read."
   }
   ```

   `shasum -a 256 odomind-catalog.json` and `wc -c < odomind-catalog.json`
   produce the last two. Both are checked: a mismatch on either is refused,
   and the installed catalog is left alone.
4. `catalogVersion` must be numerically newer than the bundled one, the
   `url` must be HTTPS on `raw.githubusercontent.com`, and the file must
   pass `odomind-catalog validate --strict`. A downloaded catalog is held
   to exactly the bar CI holds the bundled one to — otherwise the easiest
   way to ship an unreviewed value would be to publish it rather than
   commit it.

Until step 1 happens, "Check now" correctly reports that nothing has been
published. That is an accurate description of the world, not a fault in the
build.
