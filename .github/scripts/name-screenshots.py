#!/usr/bin/env python3
"""Give exported test attachments back their readable names.

`xcresulttool export attachments` writes files under opaque names and records
the readable one in a manifest beside them. Screenshots are only useful if you
can tell which screen each one is, so this puts the names back and flattens
everything into the top of the export directory.

Usage: name-screenshots.py <export-directory>
"""

import json
import os
import pathlib
import sys


def main(root: pathlib.Path) -> int:
    if not root.is_dir():
        print(f"{root} is not a directory")
        return 0

    renamed = 0
    for manifest in sorted(root.rglob("manifest.json")):
        try:
            entries = json.loads(manifest.read_text())
        except (OSError, json.JSONDecodeError) as error:
            print(f"could not read {manifest}: {error}")
            continue

        if isinstance(entries, dict):
            entries = [entries]

        for entry in entries:
            for attachment in entry.get("attachments", []):
                exported = attachment.get("exportedFileName")
                readable = attachment.get("suggestedHumanReadableName")
                if not exported or not readable:
                    continue

                source = manifest.parent / exported
                if not source.is_file():
                    continue

                target = root / pathlib.Path(readable).name
                stem, suffix = target.stem, target.suffix
                attempt = 2
                while target.exists():
                    target = root / f"{stem}-{attempt}{suffix}"
                    attempt += 1

                os.replace(source, target)
                renamed += 1

    print(f"named {renamed} attachment(s)")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        raise SystemExit(2)
    raise SystemExit(main(pathlib.Path(sys.argv[1])))
