#!/usr/bin/env python3
"""Lays out the launch-screen emblem from the same approved artwork.

    python3 Tools/make-launch-logo.py [source.png]

Reads Tools/app-icon-source.png and writes LaunchEmblem at 1x, 2x and 3x into
Odomind/Resources/Assets.xcassets/LaunchEmblem.imageset/. The PNGs are
committed, so a clone builds without running this.

This is deliberately *not* the app icon. The icon is the mark laid out to fill
a tile the system then rounds off; the launch emblem is the mark on its own,
with no tile, no border and no baked-in shadow, sized to sit comfortably in the
middle of a white screen. Reusing icon-1024.png here would put the icon's tile
proportions on the launch screen, which is the thing the brief asked not to
happen.

The PNG decoding, trimming, resampling and encoding are the app icon
generator's, imported rather than copied so the two cannot drift.
"""

import importlib.util
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Tools" / "app-icon-source.png"
DESTINATION = ROOT / "Odomind" / "Resources" / "Assets.xcassets" / "LaunchEmblem.imageset"

# Point width of the emblem on screen. Wide enough to be the subject of the
# launch screen, short of the "giant logo" the brief warned about.
POINT_WIDTH = 168
SCALES = (1, 2, 3)
BACKGROUND = (0xFF, 0xFF, 0xFF)

CONTENTS = """{
  "images" : [
    {
      "filename" : "launch-emblem.png",
      "idiom" : "universal",
      "scale" : "1x"
    },
    {
      "filename" : "launch-emblem@2x.png",
      "idiom" : "universal",
      "scale" : "2x"
    },
    {
      "filename" : "launch-emblem@3x.png",
      "idiom" : "universal",
      "scale" : "3x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""


def load_icon_tools():
    """Imports the app-icon generator, whose name is not a Swift identifier."""
    path = ROOT / "Tools" / "make-app-icon.py"
    spec = importlib.util.spec_from_file_location("odomind_make_app_icon", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main(argv):
    source = pathlib.Path(argv[1]) if len(argv) > 1 else SOURCE
    if not source.exists():
        raise SystemExit(f"no artwork at {source}")

    tools = load_icon_tools()
    width, height, pixels = tools.read_png(source)
    left, top, right, bottom = tools.content_bounds(pixels, width, height)
    mark_w, mark_h = right - left + 1, bottom - top + 1
    print(f"source {width}x{height}, mark {mark_w}x{mark_h} at ({left}, {top})")

    DESTINATION.mkdir(parents=True, exist_ok=True)
    for scale in SCALES:
        target_w = POINT_WIDTH * scale
        # Keep the mark's own proportions. Forcing a square here is what would
        # reintroduce the tile look.
        target_h = max(1, round(mark_h * target_w / mark_w))
        scaled = tools.resample(pixels, width, (left, top, right, bottom), target_w, target_h)

        # Opaque white, matching the launch background, so the emblem's
        # anti-aliased edges composite exactly as they were drawn.
        canvas = bytearray(bytes(BACKGROUND) * (target_w * target_h))
        canvas[:] = scaled

        suffix = "" if scale == 1 else f"@{scale}x"
        out = DESTINATION / f"launch-emblem{suffix}.png"
        tools.write_png(out, target_w, target_h, canvas)
        print(f"wrote {out.relative_to(ROOT)} — {target_w}x{target_h}")

    (DESTINATION / "Contents.json").write_text(CONTENTS)
    print(f"wrote {(DESTINATION / 'Contents.json').relative_to(ROOT)}")


if __name__ == "__main__":
    main(sys.argv)
