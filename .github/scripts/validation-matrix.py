#!/usr/bin/env python3
"""Gathers the evidence behind Build 3's validation matrix.

Runs on a GitHub runner, because that is the only place in this project that
can reach a provider. For each of three real configurations it records what
each source actually returns — not a description of what it should return.

Nothing here invents a value. Where a provider has nothing, the line says so,
and that absence is the finding.
"""

import json
import sys
import urllib.parse
import urllib.request

TIMEOUT = 30
UA = "Odomind-validation-matrix/1.0 (+https://github.com/BKimble1/Odomind)"

# The three the brief names: a 2010 Jeep Wrangler, a Toyota and a Ford.
# Chosen to be ordinary, high-volume vehicles rather than ones picked to make
# the matrix look good.
VEHICLES = [
    {"year": 2010, "make": "Jeep", "model": "Wrangler"},
    {"year": 2015, "make": "Toyota", "model": "Camry"},
    {"year": 2018, "make": "Ford", "model": "F-150"},
]


def get(url, label):
    request = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            body = response.read()
            return response.status, body
    except Exception as error:  # noqa: BLE001 — the failure is the evidence
        print(f"    {label}: FAILED {type(error).__name__}: {error}")
        return None, None


def vpic_models(vehicle):
    """Does vPIC agree this model exists for this year?"""
    url = (
        "https://vpic.nhtsa.dot.gov/api/vehicles/GetModelsForMakeYear/make/"
        f"{urllib.parse.quote(vehicle['make'])}/modelyear/{vehicle['year']}?format=json"
    )
    status, body = get(url, "vPIC GetModelsForMakeYear")
    if status != 200:
        return None
    data = json.loads(body)
    names = [row.get("Model_Name", "") for row in data.get("Results", [])]
    match = [n for n in names if n.lower() == vehicle["model"].lower()]
    print(f"    vPIC: {data.get('Count', 0)} models for {vehicle['make']} {vehicle['year']}")
    print(f"      '{vehicle['model']}' present: {'YES' if match else 'NO'}")
    return {"count": data.get("Count", 0), "present": bool(match)}


def fuel_json(path, label):
    """One call to fueleconomy.gov, with the raw body shown when it surprises us."""
    url = f"https://www.fueleconomy.gov/ws/rest/{path}"
    request = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            raw = response.read()
    except Exception as error:  # noqa: BLE001
        print(f"    {label}: FAILED {type(error).__name__}: {error}")
        return None
    try:
        payload = json.loads(raw)
    except Exception:  # noqa: BLE001
        print(f"    {label}: not JSON. First 300 bytes: {raw[:300]!r}")
        return None
    if payload is None:
        print(f"    {label}: JSON null. First 300 bytes: {raw[:300]!r}")
        return None
    return payload


def menu_items(payload):
    """The service answers with a list for several items and a bare object for
    one. Both shapes are the same question answered."""
    if payload is None:
        return []
    items = payload.get("menuItem", []) if isinstance(payload, dict) else []
    if isinstance(items, dict):
        items = [items]
    return [i for i in items if isinstance(i, dict)]


def fuel_economy_model_name(vehicle):
    """What fueleconomy.gov calls this model.

    vPIC says "Wrangler"; this service may say "Wrangler 4WD". Asking it for a
    name it does not use returns nothing, which would look like "no coverage"
    when the real problem is two vocabularies.
    """
    payload = fuel_json(
        "vehicle/menu/model?year={}&make={}".format(
            vehicle["year"], urllib.parse.quote(vehicle["make"])
        ),
        "fueleconomy.gov model menu",
    )
    names = [i.get("value", "") for i in menu_items(payload)]
    print(f"    fueleconomy.gov: {len(names)} model name(s) for {vehicle['make']} {vehicle['year']}")
    if names:
        print(f"      {names[:14]}")
    wanted = vehicle["model"].lower().replace("-", "").replace(" ", "")
    exact = [n for n in names if n.lower().replace("-", "").replace(" ", "") == wanted]
    if exact:
        print(f"      exact name match: {exact[0]!r}")
        return [exact[0]]
    starts = [n for n in names if n.lower().replace("-", "").replace(" ", "").startswith(wanted)]
    if starts:
        # Shortest first, matching the shipped client: the extra words are
        # qualifiers, so the plain name is the short one. A 2018 F-150 comes
        # back as twenty names and the alphabetical first three are all
        # payload and gross-weight variants.
        plainest = sorted(starts, key=lambda n: (len(n), n.lower()))
        print(f"      no exact name; this service spells it {starts!r}")
        print(f"      plainest first: {plainest[:4]!r}")
        return plainest[:4]
    print(f"      NO MATCH for {vehicle['model']!r} in this service's names")
    return None


def fuel_economy_options(vehicle):
    """The configurations this year/make/model was sold in.

    Every matching name is asked about, not just the first, because the
    shipped client does the same — evidence that describes different
    behaviour from the app is not evidence about the app.
    """
    names = fuel_economy_model_name(vehicle)
    if not names:
        return None
    collected = []
    for name in names:
        payload = fuel_json(
            "vehicle/menu/options?year={}&make={}&model={}".format(
                vehicle["year"],
                urllib.parse.quote(vehicle["make"]),
                urllib.parse.quote(name),
            ),
            f"fueleconomy.gov options for {name!r}",
        )
        items = menu_items(payload)
        print(f"    fueleconomy.gov: {len(items)} configuration option(s) for {name!r}")
        for item in items[:12]:
            print(f"      {item.get('value')}: {item.get('text')}")
        collected.extend(
            {"id": i.get("value"), "text": f"{name} — {i.get('text')}"} for i in items
        )
    return collected


def fuel_economy_detail(option_id):
    """The engine facts behind one configuration option."""
    payload = fuel_json(f"vehicle/{option_id}", f"fueleconomy.gov detail {option_id}")
    if not isinstance(payload, dict):
        return None
    keys = ["displ", "cylinders", "drive", "trany", "fuelType", "VClass", "eng_dscr"]
    facts = {key: payload.get(key) for key in keys}
    print(f"      detail {option_id}: {json.dumps(facts)}")
    return facts


def commons_photo(vehicle):
    """Wikimedia Commons: is there a licensed photograph of this car?"""
    query = f"{vehicle['year']} {vehicle['make']} {vehicle['model']}"
    url = (
        "https://commons.wikimedia.org/w/api.php?action=query&format=json"
        "&generator=search&gsrnamespace=6&gsrlimit=5"
        f"&gsrsearch={urllib.parse.quote(query)}"
        "&prop=imageinfo&iiprop=url|extmetadata|mime|size&iiurlwidth=800"
    )
    status, body = get(url, "Commons")
    if status != 200:
        return None
    pages = json.loads(body).get("query", {}).get("pages", {})
    found = []
    for page in pages.values():
        info = (page.get("imageinfo") or [{}])[0]
        meta = info.get("extmetadata", {})
        found.append(
            {
                "title": page.get("title"),
                "licence": meta.get("LicenseShortName", {}).get("value"),
                "artist": meta.get("Artist", {}).get("value", "")[:60],
                "width": info.get("width"),
                "height": info.get("height"),
            }
        )
    print(f"    Commons: {len(found)} candidate(s) for '{query}'")
    for item in found:
        print(f"      {item['title']} — {item['licence']} — {item['width']}x{item['height']}")
    return found


def parts(vehicle):
    """Part numbers. The column the brief says to report as blocked if it is."""
    url = "https://vpic.nhtsa.dot.gov/api/vehicles/GetParts?type=565&format=json"
    status, body = get(url, "vPIC GetParts")
    if status == 200:
        data = json.loads(body)
        keys = sorted(data.get("Results", [{}])[0].keys()) if data.get("Results") else []
        print(f"    vPIC GetParts: {data.get('Count', 0)} rows, keys {keys}")
        print("      -> regulatory filings (manufacturer letters), not a fitment catalogue.")
    print("    applicable part number for this vehicle: NONE AVAILABLE — no licensed catalogue.")
    return None


def main():
    print("=== Build 3 validation matrix — live provider evidence ===")
    results = {}
    for vehicle in VEHICLES:
        label = f"{vehicle['year']} {vehicle['make']} {vehicle['model']}"
        print(f"\n--- {label} ---")
        record = {"vehicle": vehicle}
        for name, step in (
            ("vpic", lambda: vpic_models(vehicle)),
            ("fuelEconomyOptions", lambda: fuel_economy_options(vehicle)),
            ("commons", lambda: commons_photo(vehicle)),
            ("parts", lambda: parts(vehicle)),
        ):
            # One provider falling over must not take the rest of the matrix
            # with it. The first draft of this script did exactly that, and
            # the evidence for two vehicles was lost to a crash on the first.
            try:
                record[name] = step()
            except Exception as error:  # noqa: BLE001
                print(f"    {name}: CRASHED {type(error).__name__}: {error}")
                record[name] = None
        options = record.get("fuelEconomyOptions") or []
        if options:
            record["fuelEconomyDetail"] = []
            for option in options[:6]:
                if not option.get("id"):
                    continue
                try:
                    record["fuelEconomyDetail"].append(fuel_economy_detail(option["id"]))
                except Exception as error:  # noqa: BLE001
                    print(f"    detail: CRASHED {type(error).__name__}: {error}")
        results[label] = record

    print("\n=== summary ===")
    for label, record in results.items():
        vpic_ok = bool(record.get("vpic") and record["vpic"].get("present"))
        options = record.get("fuelEconomyOptions") or []
        commons = record.get("commons") or []
        licensed = [c for c in commons if c.get("licence")]
        print(f"{label}")
        print(f"  identity confirmed by vPIC: {'yes' if vpic_ok else 'NO'}")
        print(f"  engine/trim options from fueleconomy.gov: {len(options)}")
        print(f"  Commons candidates with a licence: {len(licensed)}/{len(commons)}")
        print("  applicable part number: BLOCKED — no licensed fitment catalogue")
    return 0


if __name__ == "__main__":
    sys.exit(main())
