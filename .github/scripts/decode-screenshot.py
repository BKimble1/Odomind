#!/usr/bin/env python3
"""Rebuild a screenshot from the `Screenshots` workflow's job log.

The Screenshots workflow writes each capture into the log of its own small job
as base64, because artifact downloads are not reachable from every environment
this repository gets worked on from. Save that job's log to a file and run:

    .github/scripts/decode-screenshot.py today.log today.jpg

Lines look like `IMG:0001:<base64>`, optionally behind the timestamp that
GitHub prefixes to every log line. `IMGMISS:<name>` means the capture was not
produced, which is worth knowing rather than silently decoding to nothing.
"""

import base64
import binascii
import pathlib
import re
import sys

CHUNK = re.compile(r"IMG:(\d+):([A-Za-z0-9+/=]{16,})")
MISSING = re.compile(r"IMGMISS:([A-Za-z0-9._-]+)")
ANSI = re.compile(r"\x1b\[[0-9;]*m")


def normalise(text: str) -> str:
    """Make a log readable whether it was downloaded or fetched as JSON.

    A log pulled through the API arrives as one long line with newlines
    escaped, colour codes intact and a timestamp on every line. None of that
    changes the base64, but it does stop a line-by-line parse finding it.
    """
    if "\\n" in text and text.count("\n") < 5:
        text = text.replace("\\n", "\n")
    text = ANSI.sub("", text)
    return text


def main(log_path: pathlib.Path, out_path: pathlib.Path) -> int:
    text = normalise(log_path.read_text(errors="replace"))

    chunks: dict[int, str] = {}
    for line in text.split("\n"):
        # The log echoes the script that produced these lines, so skip
        # anything that is quoting the marker rather than emitting it.
        if "printf" in line or "echo " in line:
            continue
        match = CHUNK.search(line)
        if match:
            chunks[int(match.group(1))] = match.group(2)

    if not chunks:
        missing = MISSING.search(text)
        if missing:
            print(f"the log says {missing.group(1)} was not captured")
        else:
            print(f"no image chunks found in {log_path}")
        return 1

    order = sorted(chunks)
    expected = list(range(1, len(order) + 1))
    if order != expected:
        gaps = sorted(set(expected) - set(order))
        print(f"the log is missing chunk(s) {gaps}; the image would be corrupt")
        return 1

    payload = "".join(chunks[index] for index in order)
    try:
        data = base64.b64decode(payload, validate=True)
    except binascii.Error as error:
        print(f"could not decode the image: {error}")
        return 1

    out_path.write_bytes(data)
    print(f"wrote {out_path} ({len(data)} bytes from {len(order)} chunks)")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__)
        raise SystemExit(2)
    raise SystemExit(main(pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])))
