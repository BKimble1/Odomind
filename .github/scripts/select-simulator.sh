#!/bin/bash
# Prints an xcodebuild -destination string for an available iPhone simulator,
# and writes it to $GITHUB_OUTPUT as `destination` when running in Actions.
#
# Hard-coding "iPhone 15 Pro" breaks the moment GitHub updates its image, so the
# destination is discovered from what is actually installed. The minimum runtime
# matches the app's deployment target.
#
# The GITHUB_OUTPUT write lives here rather than in each workflow because a
# caller that forgets it passes -destination "" to xcodebuild, which answers
# with four hundred lines of usage text and exit 64 — a long way from the real
# cause. One implementation, one place to get it wrong.
set -euo pipefail

MIN_IOS_MAJOR="${MIN_IOS_MAJOR:-18}"
# `small` picks the smallest iPhone available instead of a current one, for
# checking that nothing is clipped on the narrowest supported display. Build 3
# asks for a screenshot pass on one.
SIMULATOR_SIZE="${SIMULATOR_SIZE:-default}"

json="$(xcrun simctl list devices available --json)"

destination="$(
  MIN_IOS_MAJOR="$MIN_IOS_MAJOR" SIMULATOR_SIZE="$SIMULATOR_SIZE" python3 - "$json" <<'PY'
import json
import os
import re
import sys

data = json.loads(sys.argv[1])
minimum = int(os.environ.get("MIN_IOS_MAJOR", "18"))
prefer_small = os.environ.get("SIMULATOR_SIZE", "default") == "small"

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
        # Prefer a plain, current iPhone over a Pro Max or an SE — or, in
        # small mode, exactly the opposite.
        preference = 0
        if "Pro Max" in name:
            preference = 2
        elif "Pro" in name:
            preference = 1
        elif "SE" in name or "mini" in name or "Plus" in name:
            preference = 3
        if prefer_small:
            small = "SE" in name or "mini" in name
            preference = 0 if small else 3
        candidates.append(((major, minor), -preference, name, device["udid"]))

if not candidates:
    sys.stderr.write("No available iPhone simulator with iOS %d or later.\n" % minimum)
    sys.exit(1)

candidates.sort(reverse=True)
_, _, name, udid = candidates[0]
sys.stderr.write("Selected simulator: %s (%s)%s\n" % (name, udid, " [small]" if prefer_small else ""))
print("platform=iOS Simulator,id=%s" % udid)
PY
)"

if [ -z "$destination" ]; then
  echo "select-simulator.sh produced no destination" >&2
  exit 1
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "destination=$destination" >> "$GITHUB_OUTPUT"
fi
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  echo "Using destination: $destination" >> "$GITHUB_STEP_SUMMARY"
fi

echo "$destination"
