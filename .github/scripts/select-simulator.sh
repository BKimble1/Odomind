#!/bin/bash
# Prints an xcodebuild -destination string for an available iPhone simulator.
#
# Hard-coding "iPhone 15 Pro" breaks the moment GitHub updates its image, so the
# destination is discovered from what is actually installed. The minimum runtime
# matches the app's deployment target.
set -euo pipefail

MIN_IOS_MAJOR="${MIN_IOS_MAJOR:-18}"

json="$(xcrun simctl list devices available --json)"

destination="$(
  MIN_IOS_MAJOR="$MIN_IOS_MAJOR" python3 - "$json" <<'PY'
import json
import os
import re
import sys

data = json.loads(sys.argv[1])
minimum = int(os.environ.get("MIN_IOS_MAJOR", "18"))

candidates = []
for runtime, devices in data.get("devices", {}).items():
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not match:
        continue
    major, minor = int(match.group(1)), int(match.group(2))
    if major < minimum:
        continue
    for device in devices:
        if not device.get("isAvailable"):
            continue
        name = device.get("name", "")
        if not name.startswith("iPhone"):
            continue
        # Prefer a plain, current iPhone over a Pro Max or an SE.
        preference = 0
        if "Pro Max" in name:
            preference = 2
        elif "Pro" in name:
            preference = 1
        elif "SE" in name or "mini" in name or "Plus" in name:
            preference = 3
        candidates.append(((major, minor), -preference, name, device["udid"]))

if not candidates:
    sys.stderr.write("No available iPhone simulator with iOS %d or later.\n" % minimum)
    sys.exit(1)

candidates.sort(reverse=True)
_, _, name, udid = candidates[0]
sys.stderr.write("Selected simulator: %s (%s)\n" % (name, udid))
print("platform=iOS Simulator,id=%s" % udid)
PY
)"

echo "$destination"
