#!/usr/bin/env python3
"""A small App Store Connect client for the TestFlight workflow.

Three jobs, each one thing the deploy would otherwise have to guess at:

  preflight            the key works, the app record exists, and this key is
                       allowed to do what the deploy needs — checked before a
                       twenty-minute archive rather than after it
  next-build-number    the highest build Apple has already seen, plus one, so
                       an upload is never rejected as a duplicate
  wait-for-build       what Apple did with the upload, polled until it stops
                       being PROCESSING

Credentials come from the environment (ASC_KEY_ID, ASC_ISSUER_ID,
ASC_PRIVATE_KEY) and are never printed. Failures name the missing thing
precisely, because the person fixing them does not have a Mac to check on.
"""

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1"
AUDIENCE = "appstoreconnect-v1"


def die(message, code=1):
    print(f"::error::{message}", file=sys.stderr)
    sys.exit(code)


def bearer():
    # Env first, import second. A broken crypto stack raises on import and
    # buries the one message that actually helps — "you have not set this
    # secret" — under a stack trace from three libraries down.
    missing = [
        name for name in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY")
        if not os.environ.get(name)
    ]
    if missing:
        die(
            "missing GitHub secret(s): " + ", ".join(missing)
            + ". Add them under Settings -> Secrets and variables -> Actions."
        )

    key = normalise_key(os.environ["ASC_PRIVATE_KEY"])

    try:
        import jwt
    except BaseException as error:  # noqa: BLE001 - a broken crypto stack panics
        die(f"could not load PyJWT ({error}); the workflow installs it first")

    now = int(time.time())
    return jwt.encode(
        {
            "iss": os.environ["ASC_ISSUER_ID"],
            "iat": now,
            "exp": now + 15 * 60,
            "aud": AUDIENCE,
        },
        key,
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )


def normalise_key(raw):
    """Accepts the .p8 as PEM text or base64, since both are widely advised."""
    key = raw.strip()
    if "BEGIN PRIVATE KEY" in key:
        return key

    # Plenty of setup guides say to base64 the .p8 so it survives a one-line
    # secret field. Decoding it here means both shapes work rather than one
    # of them failing deep inside the crypto layer with nothing useful said.
    import base64
    import binascii

    try:
        decoded = base64.b64decode("".join(key.split()), validate=True).decode("utf-8")
    except (binascii.Error, UnicodeDecodeError, ValueError):
        decoded = ""
    if "BEGIN PRIVATE KEY" in decoded:
        return decoded

    die(
        "ASC_PRIVATE_KEY is neither a .p8 key nor base64 of one. Paste the "
        "whole AuthKey_XXXXXXXX.p8 file, including its "
        "-----BEGIN PRIVATE KEY----- and -----END PRIVATE KEY----- lines."
    )


def get(path, params=None, token=None):
    url = API + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    request = urllib.request.Request(
        url, headers={"Authorization": f"Bearer {token or bearer()}"}
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", "replace")[:800]
        if error.code == 401:
            die(
                "App Store Connect rejected the API key (401). Check that "
                "ASC_KEY_ID and ASC_ISSUER_ID match the key in "
                "ASC_PRIVATE_KEY, and that the key has not been revoked."
            )
        if error.code == 403:
            die(
                "App Store Connect refused the request (403). The API key "
                "most likely lacks the role this needs — App Manager is "
                f"required to create signing assets and upload. Body: {body}"
            )
        die(f"App Store Connect returned {error.code} for {path}: {body}")
    except urllib.error.URLError as error:
        die(f"could not reach App Store Connect: {error.reason}")


def find_app(bundle_id, token):
    payload = get("/apps", {"filter[bundleId]": bundle_id, "limit": 200}, token)
    for app in payload.get("data", []):
        if app["attributes"].get("bundleId") == bundle_id:
            return app
    return None


def builds_for(app_id, token, version=None):
    params = {
        "filter[app]": app_id,
        "limit": 200,
        "sort": "-version",
        "fields[builds]": "version,processingState,uploadedDate,expired",
    }
    if version:
        params["filter[preReleaseVersion.version]"] = version
    return get("/builds", params, token).get("data", [])


def as_int(text):
    """Build numbers are usually plain integers; treat anything else as 0."""
    try:
        return int(str(text).strip())
    except (TypeError, ValueError):
        return 0


def cmd_preflight(args):
    token = bearer()
    app = find_app(args.bundle_id, token)
    if app is None:
        die(
            f"no app with bundle identifier {args.bundle_id} exists in App "
            "Store Connect. Create it once at "
            "https://appstoreconnect.apple.com/apps -> + -> New App "
            f"(platform iOS, bundle ID {args.bundle_id}); an upload cannot "
            "create the app record for you."
        )
    name = app["attributes"].get("name", "(unnamed)")
    print(f"App Store Connect app found: {name} ({args.bundle_id}), id {app['id']}")
    existing = builds_for(app["id"], token)
    print(f"builds already uploaded: {len(existing)}")
    if existing:
        newest = existing[0]["attributes"]
        print(
            f"newest build: {newest.get('version')} "
            f"({newest.get('processingState')})"
        )
    return 0


def cmd_next_build_number(args):
    fallback = os.environ.get("GITHUB_RUN_NUMBER", "1")
    try:
        token = bearer()
        app = find_app(args.bundle_id, token)
        if app is None:
            print(
                f"::warning::no app record for {args.bundle_id}; "
                f"falling back to run number {fallback}",
                file=sys.stderr,
            )
            print(fallback)
            return 0
        highest = max(
            (as_int(b["attributes"].get("version")) for b in builds_for(app["id"], token)),
            default=0,
        )
        # Apple requires the build number to be unique within a marketing
        # version, and rejects a re-used one outright. Taking the highest
        # across every version and adding one is monotonic whatever the
        # marketing version does next.
        print(max(highest + 1, as_int(fallback)))
        return 0
    # Everything, SystemExit included. Credentials are already gated by the
    # preflight step, so anything reaching here is a transient App Store
    # Connect problem, and a deploy should not die on the way to picking a
    # number it has a perfectly good fallback for.
    except BaseException as error:  # noqa: BLE001 - must not block the deploy
        print(
            f"::warning::could not read build numbers ({error}); "
            f"falling back to run number {fallback}",
            file=sys.stderr,
        )
        print(fallback)
        return 0


def cmd_wait_for_build(args):
    token = bearer()
    app = find_app(args.bundle_id, token)
    if app is None:
        die(f"no app record for {args.bundle_id}")

    deadline = time.time() + args.timeout
    last = None
    while time.time() < deadline:
        for build in builds_for(app["id"], token, version=args.version):
            attributes = build["attributes"]
            if as_int(attributes.get("version")) != as_int(args.build):
                continue
            state = attributes.get("processingState")
            if state != last:
                print(f"build {args.build}: {state}")
                last = state
            if state == "VALID":
                print(f"::notice::TestFlight build {args.build} is processed and VALID")
                return 0
            if state in ("INVALID", "FAILED"):
                die(
                    f"Apple finished processing build {args.build} and marked "
                    f"it {state}. App Store Connect will have emailed the "
                    "reason; it is also on the build's page in TestFlight."
                )
            break
        else:
            if last is None:
                print("build not visible to the API yet…")
        time.sleep(args.interval)

    # Not a failure. Apple's own processing time is not this workflow's to
    # promise, and saying "still processing" is the truthful answer.
    print(
        f"::warning::build {args.build} was still "
        f"{last or 'not visible'} after {args.timeout}s. "
        "That is normal — Apple processing often takes longer. "
        "Check TestFlight for the final state."
    )
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    check = sub.add_parser("preflight")
    check.add_argument("--bundle-id", required=True)
    check.set_defaults(func=cmd_preflight)

    nxt = sub.add_parser("next-build-number")
    nxt.add_argument("--bundle-id", required=True)
    nxt.set_defaults(func=cmd_next_build_number)

    wait = sub.add_parser("wait-for-build")
    wait.add_argument("--bundle-id", required=True)
    wait.add_argument("--version", required=True)
    wait.add_argument("--build", required=True)
    wait.add_argument("--timeout", type=int, default=900)
    wait.add_argument("--interval", type=int, default=30)
    wait.set_defaults(func=cmd_wait_for_build)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
