#!/usr/bin/env python3
"""Builds Odomind's bootstrap make/model index from NHTSA vPIC.

Why this exists. Build 2 gated every search on a hand-typed list of 43 makes:
a query whose make was not in the list never reached the provider at all, and
a query with no make could not be answered because nothing mapped a model name
back to its make. Replacing one hand-typed list with a slightly longer one
would be the same mistake, so the index is *generated* from the public vPIC
endpoints and can be regenerated whenever this script is run.

What the index is for. Instant suggestions and routing only — "which make
should I ask vPIC about for the word 'wrangler'". Authoritative model lists
still come from the provider at search time, so a vehicle missing from the
index is never blocked, only slower to suggest.

Emitted gzipped and base64-encoded so the whole thing fits in a job log, which
is the only channel out of a runner that the authoring host can read.
"""

import base64
import gzip
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

TIMEOUT = 30
UA = "Odomind-index-builder/1.0 (https://github.com/BKimble1/Odomind)"

# vPIC's all-makes endpoint returns thousands of entries, most of them trailer,
# bus and equipment manufacturers. Restricting the *model fetch* to makes that
# sell passenger vehicles keeps the index a useful size; the full make list is
# still carried so an unusual make can be recognised and asked about.
PASSENGER_MAKES = [
    "ACURA", "ALFA ROMEO", "ASTON MARTIN", "AUDI", "BENTLEY", "BMW", "BUICK",
    "CADILLAC", "CHEVROLET", "CHRYSLER", "DODGE", "FERRARI", "FIAT", "FISKER",
    "FORD", "GENESIS", "GMC", "HONDA", "HUMMER", "HYUNDAI", "INFINITI",
    "ISUZU", "JAGUAR", "JEEP", "KIA", "LAMBORGHINI", "LAND ROVER", "LEXUS",
    "LINCOLN", "LOTUS", "LUCID", "MASERATI", "MAYBACH", "MAZDA", "MCLAREN",
    "MERCEDES-BENZ", "MERCURY", "MINI", "MITSUBISHI", "NISSAN", "OLDSMOBILE",
    "PLYMOUTH", "POLESTAR", "PONTIAC", "PORSCHE", "RAM", "RIVIAN",
    "ROLLS-ROYCE", "SAAB", "SATURN", "SCION", "SMART", "SUBARU", "SUZUKI",
    "TESLA", "TOYOTA", "VOLKSWAGEN", "VOLVO",
]

# Typed shorthand that no provider knows about. Kept small and obvious; the
# index itself supplies the long tail.
ALIASES = {
    "chevy": "CHEVROLET",
    "vw": "VOLKSWAGEN",
    "mercedes": "MERCEDES-BENZ",
    "benz": "MERCEDES-BENZ",
    "merc": "MERCEDES-BENZ",
    "beemer": "BMW",
    "bimmer": "BMW",
    "volkswagon": "VOLKSWAGEN",
    "landrover": "LAND ROVER",
    "rangerover": "LAND ROVER",
    "range rover": "LAND ROVER",
    "alfa": "ALFA ROMEO",
    "gm": "GMC",
    "gmc truck": "GMC",
    "gen": "GENESIS",
    "gti": "VOLKSWAGEN",
    "mb": "MERCEDES-BENZ",
    "gle": "MERCEDES-BENZ",
}


def get_json(url: str, attempts: int = 3) -> dict:
    last: Exception | None = None
    for attempt in range(attempts):
        try:
            request = urllib.request.Request(
                url, headers={"Accept": "application/json", "User-Agent": UA}
            )
            with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
                return json.load(response)
        except Exception as error:  # noqa: BLE001
            last = error
            time.sleep(1.5 * (attempt + 1))
    raise RuntimeError(f"{url} failed after {attempts} attempts: {last}")


def main() -> int:
    makes_payload = get_json("https://vpic.nhtsa.dot.gov/api/vehicles/GetAllMakes?format=json")
    all_makes = sorted({
        (row.get("Make_Name") or "").strip().upper()
        for row in makes_payload.get("Results", [])
        if (row.get("Make_Name") or "").strip()
    })
    print(f"vPIC knows {len(all_makes)} makes", file=sys.stderr)

    known = set(all_makes)
    models: dict[str, list[str]] = {}
    for make in PASSENGER_MAKES:
        if make not in known:
            print(f"  ! {make} not in vPIC's make list, skipping", file=sys.stderr)
            continue
        url = (
            "https://vpic.nhtsa.dot.gov/api/vehicles/GetModelsForMake/"
            f"{urllib.parse.quote(make)}?format=json"
        )
        try:
            payload = get_json(url)
        except RuntimeError as error:
            print(f"  ! {make}: {error}", file=sys.stderr)
            continue
        names = sorted({
            (row.get("Model_Name") or "").strip()
            for row in payload.get("Results", [])
            if (row.get("Model_Name") or "").strip()
        })
        if names:
            models[make] = names
        print(f"  {make}: {len(names)} models", file=sys.stderr)
        time.sleep(0.25)  # deliberate: a public service, asked politely

    index = {
        "schemaVersion": 1,
        "source": "NHTSA vPIC GetAllMakes + GetModelsForMake",
        "sourceURL": "https://vpic.nhtsa.dot.gov/api/",
        "generatedOn": time.strftime("%Y-%m-%d", time.gmtime()),
        "note": (
            "Suggestion and routing index only. Authoritative model lists are "
            "fetched from the provider at search time, so a vehicle absent "
            "from this file is never blocked."
        ),
        "aliases": ALIASES,
        "makes": all_makes,
        "passengerMakes": sorted(models.keys()),
        "models": models,
    }

    raw = json.dumps(index, separators=(",", ":"), sort_keys=True).encode()
    packed = base64.b64encode(gzip.compress(raw, 9)).decode()
    total_models = sum(len(v) for v in models.values())
    print(
        f"index: {len(all_makes)} makes, {len(models)} with models, "
        f"{total_models} models, {len(raw)} bytes raw, {len(packed)} base64",
        file=sys.stderr,
    )

    print(f"INDEXSTART:{len(raw)}")
    for number, offset in enumerate(range(0, len(packed), 2400), start=1):
        print(f"INDEX:{number:04d}:{packed[offset:offset + 2400]}")
    print("INDEXEND")
    return 0


if __name__ == "__main__":
    sys.exit(main())
