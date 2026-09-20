#!/usr/bin/env python3
"""Checks that NHTSA vPIC is reachable and still returns the fields Odomind reads.

Run by the optional provider smoke workflow, never by the pull-request gate.
Exits 0 when the API answered with a usable response, 1 when it answered with
something Odomind could not parse, and 2 when it could not be reached at all —
which the workflow reports without failing the build, because Odomind is
designed to work without it.
"""

import json
import sys
import urllib.error
import urllib.request

URL = (
    "https://vpic.nhtsa.dot.gov/api/vehicles/decodevinvalues/"
    "1J4BA3H14AL139999?format=json&modelyear=2010"
)

# The fields the app's decoder reads. If vPIC stops returning one of these,
# Odomind's VIN flow degrades, and this is where we find out.
REQUIRED_FIELDS = [
    "Make",
    "Model",
    "ModelYear",
    "ErrorCode",
    "ErrorText",
    "VehicleType",
    "BodyClass",
    "DisplacementL",
    "EngineCylinders",
    "FuelTypePrimary",
    "TransmissionStyle",
    "DriveType",
]


def main() -> int:
    request = urllib.request.Request(URL, headers={"Accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = json.load(response)
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        print("vPIC unreachable: %s" % error, file=sys.stderr)
        return 2

    results = payload.get("Results") or []
    if not results:
        print("vPIC returned no Results array.", file=sys.stderr)
        return 1

    record = results[0]
    missing = [field for field in REQUIRED_FIELDS if field not in record]
    if missing:
        print("vPIC response is missing expected fields: %s" % ", ".join(missing), file=sys.stderr)
        return 1

    print(
        "vPIC reachable. Make=%r Model=%r ModelYear=%r ErrorCode=%r"
        % (
            record.get("Make"),
            record.get("Model"),
            record.get("ModelYear"),
            record.get("ErrorCode"),
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
