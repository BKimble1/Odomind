#!/usr/bin/env python3
"""Renders Odomind's app icon.

The mark is an odometer sweep: a 250-degree track with the travelled portion
filled, and a needle at the current position. Drawn analytically from signed
distance fields so the edges are properly anti-aliased at any size, with no
image library needed.

    python3 Tools/make-app-icon.py

Writes Odomind/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png.
Re-run after changing any constant below; the PNG is committed so a clone
builds without running this.
"""

import math
import pathlib
import struct
import sys
import zlib

SIZE = 1024

# Deep petrol, warming slightly towards the lower right.
BG_TOP_LEFT = (0x0B, 0x27, 0x30)
BG_BOTTOM_RIGHT = (0x16, 0x46, 0x54)
TRACK = (0xFF, 0xFF, 0xFF)
TRACK_ALPHA = 0.15
PROGRESS = (0xF2, 0xA6, 0x3C)
NEEDLE = (0xF7, 0xF9, 0xF8)

CENTRE_X = SIZE / 2
# The gap sits at the bottom, so the mark's mass is above the geometric centre.
# Nudging it down puts it where the eye expects it.
CENTRE_Y = SIZE / 2 + SIZE * 0.052
RADIUS = SIZE * 0.270
THICKNESS = SIZE * 0.072
APERTURE = math.radians(125.0)
PROGRESS_FRACTION = 0.62
NEEDLE_LENGTH = RADIUS - THICKNESS - SIZE * 0.018
NEEDLE_HALF_WIDTH = SIZE * 0.022
HUB_RADIUS = SIZE * 0.038


def arc_distance(px, py, aperture, radius, thickness):
    """Signed distance to an arc centred on +y, after Inigo Quilez's sdArc."""
    ax = abs(px)
    sin_a = math.sin(aperture)
    cos_a = math.cos(aperture)
    # Outside the wedge the nearest point is a rounded cap; inside it is the
    # circle itself. The test is cos(aperture)*x > sin(aperture)*y.
    if cos_a * ax > sin_a * py:
        # Outside the angular span: measure to the nearer rounded cap.
        dx = ax - sin_a * radius
        dy = py - cos_a * radius
        outside = math.hypot(dx, dy)
    else:
        outside = abs(math.hypot(px, py) - radius)
    return outside - thickness


def capsule_distance(px, py, ax, ay, bx, by, half_width):
    """Signed distance to a rounded line segment from a to b."""
    pax, pay = px - ax, py - ay
    bax, bay = bx - ax, by - ay
    denominator = bax * bax + bay * bay
    h = 0.0 if denominator == 0 else max(0.0, min(1.0, (pax * bax + pay * bay) / denominator))
    return math.hypot(pax - bax * h, pay - bay * h) - half_width


def coverage(distance, feather=1.1):
    """Anti-aliased coverage from a signed distance, 1 inside and 0 outside."""
    if distance <= -feather:
        return 1.0
    if distance >= feather:
        return 0.0
    t = (feather - distance) / (2.0 * feather)
    return t * t * (3.0 - 2.0 * t)


def blend(base, colour, alpha):
    return tuple(base[i] + (colour[i] - base[i]) * alpha for i in range(3))


def render():
    needle_angle = -APERTURE + 2.0 * APERTURE * PROGRESS_FRACTION
    needle_tip = (math.sin(needle_angle) * NEEDLE_LENGTH, math.cos(needle_angle) * NEEDLE_LENGTH)

    rows = []
    for y in range(SIZE):
        row = bytearray()
        row.append(0)  # PNG filter type 0 for this scanline
        py = CENTRE_Y - (y + 0.5)
        for x in range(SIZE):
            px = (x + 0.5) - CENTRE_X

            # Background: a gentle diagonal ramp, not a showy gradient.
            ramp = ((x / SIZE) * 0.55 + (y / SIZE) * 0.45)
            colour = [
                BG_TOP_LEFT[i] + (BG_BOTTOM_RIGHT[i] - BG_TOP_LEFT[i]) * ramp
                for i in range(3)
            ]

            arc = arc_distance(px, py, APERTURE, RADIUS, THICKNESS)
            arc_alpha = coverage(arc)
            if arc_alpha > 0.0:
                angle = math.atan2(px, py)
                travelled = angle <= needle_angle
                if travelled:
                    colour = list(blend(colour, PROGRESS, arc_alpha))
                else:
                    colour = list(blend(colour, TRACK, arc_alpha * TRACK_ALPHA))

            needle = capsule_distance(px, py, 0.0, 0.0, needle_tip[0], needle_tip[1], NEEDLE_HALF_WIDTH)
            hub = math.hypot(px, py) - HUB_RADIUS
            mark = min(needle, hub)
            mark_alpha = coverage(mark)
            if mark_alpha > 0.0:
                colour = list(blend(colour, NEEDLE, mark_alpha))

            row.extend(int(max(0.0, min(255.0, value)) + 0.5) for value in colour)
        rows.append(bytes(row))
    return b"".join(rows)


def write_png(path, raw, width, height):
    def chunk(tag, payload):
        body = tag + payload
        return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)  # 8-bit RGB, no alpha
    data = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return len(data)


def main():
    root = pathlib.Path(__file__).resolve().parent.parent
    destination = root / "Odomind/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
    written = write_png(destination, render(), SIZE, SIZE)
    print(f"wrote {destination.relative_to(root)} ({written} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
