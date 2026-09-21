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


def fuel_economy_options(vehicle):
    """fueleconomy.gov: a US government dataset, public domain.

    The question this answers is the one Build 3's configuration step needs:
    which engines was this year/make/model actually sold with? A hand-typed
    list of engine choices is exactly the kind of invention the brief bars.
    """
    url = (
        "https://www.fueleconomy.gov/ws/rest/vehicle/menu/options"
        f"?year={vehicle['year']}&make={urllib.parse.quote(vehicle['make'])}"
        f"&model={urllib.parse.quote(vehicle['model'])}"
    )
    request = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            payload = json.loads(response.read())
    except Exception as error:  # noqa: BLE001
        print(f"    fueleconomy.gov: FAILED {type(error).__name__}: {error}")
        return None

    items = payload.get("menuItem", [])
    if isinstance(items, dict):
        items = [items]
    print(f"    fueleconomy.gov: {len(items)} configuration option(s)")
    for item in items[:12]:
        print(f"      {item.get('value')}: {item.get('text')}")
    return [{"id": i.get("value"), "text": i.get("text")} for i in items]


def fuel_economy_detail(option_id):
    """The engine facts behind one configuration option."""
    url = f"https://www.fueleconomy.gov/ws/rest/vehicle/{option_id}"
    request = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            payload = json.loads(response.read())
    except Exception as error:  # noqa: BLE001
        print(f"      detail {option_id}: FAILED {type(error).__name__}: {error}")
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
        record["vpic"] = vpic_models(vehicle)
        options = fuel_economy_options(vehicle)
        record["fuelEconomyOptions"] = options
        if options:
            record["fuelEconomyDetail"] = [
                fuel_economy_detail(option["id"]) for option in options[:3] if option.get("id")
            ]
        record["commons"] = commons_photo(vehicle)
        record["parts"] = parts(vehicle)
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
