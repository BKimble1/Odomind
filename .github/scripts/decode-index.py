#!/usr/bin/env python3
"""Reassembles the vehicle index from the generator job's log.

    .github/scripts/decode-index.py index-job.log OdomindCore/Sources/OdomindCore/Resources/vehicle-index.json
"""

import base64
import gzip
import json
import pathlib
import re
import sys

CHUNK = re.compile(r"INDEX:(\d+):([A-Za-z0-9+/=]+)")
ANSI = re.compile(r"\x1b\[[0-9;]*m")


def main(log_path: pathlib.Path, out_path: pathlib.Path) -> int:
    text = log_path.read_text(errors="replace")
    if "\\n" in text and text.count("\n") < 5:
        text = text.replace("\\n", "\n")
    text = ANSI.sub("", text)

    chunks = sorted(
        ((int(number), payload) for number, payload in CHUNK.findall(text)),
        key=lambda pair: pair[0],
    )
    if not chunks:
        print("no INDEX: chunks in that log", file=sys.stderr)
        return 1

    expected = list(range(1, len(chunks) + 1))
    if [n for n, _ in chunks] != expected:
        print(f"chunks are not contiguous: got {len(chunks)}, gaps present", file=sys.stderr)
        return 1

    raw = gzip.decompress(base64.b64decode("".join(payload for _, payload in chunks)))
    index = json.loads(raw)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(index, indent=2, sort_keys=True) + "\n")
    print(
        f"wrote {out_path} — {len(index['makes'])} makes, "
        f"{len(index['models'])} with models, "
        f"{sum(len(v) for v in index['models'].values())} models"
    )
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])))
