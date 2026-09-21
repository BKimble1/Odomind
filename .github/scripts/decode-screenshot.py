#!/usr/bin/env python3
"""Rebuild the screenshots in a Screenshots-workflow job log.

The capture jobs write every screen into their own log as base64, because a
job log is the only channel out of a runner this repository can read from —
artifact downloads are not reachable here, and a finalize call returning 403
once took all thirty images with it. Save the job's log to a file and run:

    .github/scripts/decode-screenshot.py today.log screenshots/

One log holds many images now, so this splits on the `IMGSTART:<name>:<bytes>`
and `IMGEND:<name>` markers before decoding, and writes one file per screen.
The earlier version kept chunks in a single dict keyed by sequence number:
each image restarts its numbering at 1, so later chunks silently overwrote
earlier ones and the result still passed the contiguity check. It wrote a
corrupt file and reported success.

Each image is also checked against the byte count the emitter recorded, so a
truncated log is refused rather than written out half-size.
`IMGMISS:<name>` means a capture was not produced, which is worth saying.
"""

import base64
import binascii
import pathlib
import re
import sys

START = re.compile(r"IMGSTART:([A-Za-z0-9._-]+):(\d+)")
END = re.compile(r"IMGEND:([A-Za-z0-9._-]+)")
CHUNK = re.compile(r"IMG:(\d+):([A-Za-z0-9+/=]{16,})")
MISSING = re.compile(r"IMGMISS:([A-Za-z0-9._-]+)")
ANSI = re.compile(r"\x1b\[[0-9;]*m")


def normalise(text: str) -> str:
    if "\\n" in text and text.count("\n") < 5:
        text = text.replace("\\n", "\n")
    return ANSI.sub("", text)


def main(log_path: pathlib.Path, out_dir: pathlib.Path) -> int:
    text = normalise(log_path.read_text(errors="replace"))
    out_dir.mkdir(parents=True, exist_ok=True)

    current = None
    expected_bytes = 0
    chunks: dict[int, str] = {}
    written = 0

    for line in text.split("\n"):
        if "printf" in line or "echo " in line:
            continue

        for name in MISSING.findall(line):
            print(f"  MISSING: {name}")

        begin = START.search(line)
        if begin:
            current, expected_bytes = begin.group(1), int(begin.group(2))
            chunks = {}
            continue

        finish = END.search(line)
        if finish and current:
            order = sorted(chunks)
            if order != list(range(1, len(order) + 1)):
                print(f"  {current}: missing chunks, refusing to write a corrupt file")
            else:
                data = b""
                try:
                    data = base64.b64decode("".join(chunks[i] for i in order), validate=True)
                except binascii.Error as error:
                    print(f"  {current}: {error}")
                if data:
                    if expected_bytes and len(data) != expected_bytes:
                        print(f"  {current}: expected {expected_bytes} bytes, got {len(data)} — not writing")
                    else:
                        path = out_dir / f"{current}.jpg"
                        path.write_bytes(data)
                        print(f"  wrote {path} ({len(data)} bytes, {len(order)} chunks)")
                        written += 1
            current, chunks = None, {}
            continue

        match = CHUNK.search(line)
        if match and current:
            chunks[int(match.group(1))] = match.group(2)

    if written == 0:
        print(f"  no images decoded from {log_path}")
        return 1
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__)
        raise SystemExit(2)
    raise SystemExit(main(pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])))
