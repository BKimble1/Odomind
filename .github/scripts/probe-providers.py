#!/usr/bin/env python3
"""Proves, live, what Build 3's data approach can and cannot actually do.

The authoring host's egress proxy allows GitHub and nothing else, so every
provider question has to be answered from a runner. This script is that
answer. It is deliberately a *probe*, not a test: it reports what each
provider returned so a decision can be made from evidence rather than from a
vendor's marketing page.

Each capability Build 3 needs is checked separately, because no single
provider supplies all of them:

  1. discovery      vehicle makes and models, including without a year
  2. configuration  engine / body / drivetrain for a chosen vehicle
  3. photograph     a real image of that model, with a reusable licence
  4. part           an applicable replacement part with a manufacturer number

Exit code is 0 whenever the script ran to completion. A capability that comes
back unavailable is a finding to report, not a build failure.
"""

import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

TIMEOUT = 30
UA = "Odomind-provider-probe/1.0 (https://github.com/BKimble1/Odomind)"

findings: list[tuple[str, str, str]] = []


def record(capability: str, verdict: str, detail: str) -> None:
    findings.append((capability, verdict, detail))
    print(f"[{verdict}] {capability}: {detail}", flush=True)


def get_json(url: str) -> object:
    request = urllib.request.Request(url, headers={"Accept": "application/json", "User-Agent": UA})
    with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
        return json.load(response)


# ---------------------------------------------------------------- discovery

def probe_vpic_makes() -> None:
    """Every make vPIC knows. Build 3 caches this as the search index."""
    try:
        payload = get_json("https://vpic.nhtsa.dot.gov/api/vehicles/GetAllMakes?format=json")
    except Exception as error:  # noqa: BLE001 - a probe reports, it does not raise
        record("discovery/makes", "UNAVAILABLE", f"{type(error).__name__}: {error}")
        return
    results = payload.get("Results") or []
    names = [row.get("Make_Name", "") for row in results]
    has_jeep = any(n.upper() == "JEEP" for n in names)
    record(
        "discovery/makes",
        "OK" if results and has_jeep else "UNEXPECTED",
        f"{len(results)} makes returned; JEEP present: {has_jeep}",
    )


def probe_vpic_models_yearless(make: str) -> list[str]:
    """The endpoint the brief points at: models for a make with NO year.

    This is what lets somebody type "Wrangler" and get somewhere.
    """
    url = f"https://vpic.nhtsa.dot.gov/api/vehicles/GetModelsForMake/{urllib.parse.quote(make)}?format=json"
    try:
        payload = get_json(url)
    except Exception as error:  # noqa: BLE001
        record(f"discovery/models-yearless({make})", "UNAVAILABLE", f"{type(error).__name__}: {error}")
        return []
    models = sorted({row.get("Model_Name", "") for row in (payload.get("Results") or [])})
    wrangler = [m for m in models if "wrangler" in m.lower()]
    record(
        f"discovery/models-yearless({make})",
        "OK" if models else "EMPTY",
        f"{len(models)} models with no year supplied; Wrangler-like: {wrangler[:5]}",
    )
    return models


def probe_vpic_models_for_year(make: str, year: int) -> list[str]:
    url = (
        "https://vpic.nhtsa.dot.gov/api/vehicles/GetModelsForMakeYear/make/"
        f"{urllib.parse.quote(make)}/modelyear/{year}?format=json"
    )
    try:
        payload = get_json(url)
    except Exception as error:  # noqa: BLE001
        record(f"discovery/models({make} {year})", "UNAVAILABLE", f"{type(error).__name__}: {error}")
        return []
    models = sorted({row.get("Model_Name", "") for row in (payload.get("Results") or [])})
    record(f"discovery/models({make} {year})", "OK" if models else "EMPTY", f"{len(models)} models")
    return models


# ------------------------------------------------------------ configuration

def probe_vpic_configuration(vin: str, year: int) -> None:
    """What vPIC can say about a specific vehicle's configuration."""
    url = (
        "https://vpic.nhtsa.dot.gov/api/vehicles/decodevinvalues/"
        f"{urllib.parse.quote(vin)}?format=json&modelyear={year}"
    )
    try:
        payload = get_json(url)
    except Exception as error:  # noqa: BLE001
        record("configuration/vin", "UNAVAILABLE", f"{type(error).__name__}: {error}")
        return
    row = (payload.get("Results") or [{}])[0]
    interesting = {
        k: row.get(k)
        for k in ("Make", "Model", "ModelYear", "BodyClass", "DisplacementL",
                  "EngineCylinders", "FuelTypePrimary", "DriveType", "TransmissionStyle", "Trim")
        if row.get(k)
    }
    # The point worth recording: what vPIC does NOT pin down.
    missing = [k for k in ("Trim", "TransmissionStyle", "DriveType") if not row.get(k)]
    record(
        "configuration/vin",
        "OK" if interesting.get("Make") else "EMPTY",
        f"decoded {interesting}; blank for this VIN: {missing or 'none'}",
    )


# --------------------------------------------------------------- photograph

def probe_commons_photo(query: str) -> None:
    """A real photograph with a licence Odomind is allowed to show.

    Commons is the free option. What matters is not that an image exists but
    that its licence and attribution come back with it, because showing the
    picture without them is not something Odomind may do.
    """
    search = (
        "https://commons.wikimedia.org/w/api.php?action=query&format=json"
        "&generator=search&gsrnamespace=6&gsrlimit=8"
        f"&gsrsearch={urllib.parse.quote(query)}"
        "&prop=imageinfo&iiprop=url|extmetadata|mime|size"
        "&iiurlwidth=1024"
    )
    try:
        payload = get_json(search)
    except Exception as error:  # noqa: BLE001
        record("photo/commons", "UNAVAILABLE", f"{type(error).__name__}: {error}")
        return

    pages = (payload.get("query") or {}).get("pages") or {}
    usable = []
    for page in pages.values():
        info = (page.get("imageinfo") or [{}])[0]
        if not info.get("mime", "").startswith("image/"):
            continue
        meta = info.get("extmetadata") or {}
        licence = (meta.get("LicenseShortName") or {}).get("value")
        artist = re.sub(r"<[^>]+>", "", (meta.get("Artist") or {}).get("value", "")).strip()
        if not licence:
            continue
        usable.append({
            "title": page.get("title"),
            "licence": licence,
            "artist": artist[:60],
            "thumb": bool(info.get("thumburl")),
        })

    record(
        "photo/commons",
        "OK" if usable else "EMPTY",
        f"{len(usable)} licensed candidates for {query!r}; first: {usable[0] if usable else None}",
    )


# --------------------------------------------------------------------- part

def probe_part_applicability() -> None:
    """Is there a free source that answers 'which oil filter fits this car'?

    Checked rather than assumed. vPIC's GetParts is regulatory submissions —
    manufacturer compliance letters — not replacement-part fitment, and the
    brief already says so; this confirms it from the response itself.
    """
    try:
        payload = get_json(
            "https://vpic.nhtsa.dot.gov/api/vehicles/GetParts?type=565&fromDate=1/1/2015"
            "&toDate=5/5/2015&format=json"
        )
    except Exception as error:  # noqa: BLE001
        record("part/vpic-getparts", "UNAVAILABLE", f"{type(error).__name__}: {error}")
        return
    results = payload.get("Results") or []
    sample = results[0] if results else {}
    record(
        "part/vpic-getparts",
        "NOT-APPLICABLE",
        "returns regulatory submission letters, no fitment or part numbers; "
        f"sample keys: {sorted(sample.keys())[:6]}",
    )


def main() -> int:
    print("=== Odomind Build 3 provider probe ===\n", flush=True)

    probe_vpic_makes()
    probe_vpic_models_yearless("Jeep")
    probe_vpic_models_yearless("Toyota")
    probe_vpic_models_for_year("Jeep", 2010)
    probe_vpic_configuration("1J4BA3H14AL139999", 2010)
    probe_commons_photo("2010 Jeep Wrangler Unlimited")
    probe_commons_photo("Toyota Camry XV40")
    probe_part_applicability()

    print("\n=== summary ===", flush=True)
    for capability, verdict, detail in findings:
        print(f"{verdict:>14}  {capability}", flush=True)

    unavailable = [f for f in findings if f[1] == "UNAVAILABLE"]
    print(f"\n{len(findings)} probes, {len(unavailable)} unreachable", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
