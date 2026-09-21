#!/usr/bin/env python3
"""Lays out Odomind's app icon from the supplied artwork.

    python3 Tools/make-app-icon.py [source.png]

Reads Tools/app-icon-source.png and writes the 1024pt icon to
Odomind/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png. The PNG is
committed, so a clone builds without running this.

The artwork arrives as a mark floating in a large white margin — 69% of the
frame wide and 39% tall, with 371px of empty space above it. Scaled straight
down that reads as a small logo lost in a white square at home-screen size, so
this trims to the mark and lays it back out to fill a set fraction of the
canvas. The mark itself is never cropped.

The output is opaque RGB on purpose: iOS rejects an app icon with an alpha
channel, and the system applies its own rounded-rectangle mask, so the icon is
drawn square and edge to edge.

This replaced a procedural generator that drew an odometer sweep. The artwork
is the owner's design and supersedes it; the command is unchanged so the
documented workflow still holds.

No image library is available on the authoring host, so the PNG is decoded,
resampled and re-encoded here.
"""

import pathlib
import struct
import sys
import zlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Tools" / "app-icon-source.png"
DESTINATION = (
    ROOT / "Odomind" / "Resources" / "Assets.xcassets"
    / "AppIcon.appiconset" / "icon-1024.png"
)

SIZE = 1024
# How much of the canvas width the mark spans. A wide, short mark sized to the
# full width would crowd the corners the system mask rounds off.
FILL = 0.78
# Anything at or above this on every channel counts as background.
WHITE = 240
BACKGROUND = (0xFF, 0xFF, 0xFF)


def read_png(path):
    """Returns (width, height, RGB bytes) for an 8-bit non-interlaced PNG."""
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"{path} is not a PNG")

    position, compressed, header = 8, b"", None
    while position < len(data):
        length = struct.unpack(">I", data[position:position + 4])[0]
        kind = data[position + 4:position + 8]
        chunk = data[position + 8:position + 8 + length]
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", chunk)
        elif kind == b"IDAT":
            compressed += chunk
        position += 12 + length

    width, height, depth, colour, _, _, interlace = header
    if depth != 8 or colour not in (2, 6) or interlace != 0:
        raise SystemExit(
            f"{path}: expected an 8-bit RGB or RGBA non-interlaced PNG, "
            f"got depth {depth}, colour type {colour}, interlace {interlace}"
        )

    channels = 3 if colour == 2 else 4
    stride = width * channels
    raw = zlib.decompress(compressed)

    pixels = bytearray(width * height * 3)
    previous = bytearray(stride)
    offset = 0
    for y in range(height):
        method = raw[offset]
        offset += 1
        line = bytearray(raw[offset:offset + stride])
        offset += stride
        unfilter(method, line, previous, channels, stride)
        if channels == 3:
            pixels[y * width * 3:(y + 1) * width * 3] = line
        else:
            # Flatten onto white, since the icon must end up opaque anyway.
            for x in range(width):
                r, g, b, a = line[x * 4:x * 4 + 4]
                base = (y * width + x) * 3
                pixels[base] = (r * a + 255 * (255 - a)) // 255
                pixels[base + 1] = (g * a + 255 * (255 - a)) // 255
                pixels[base + 2] = (b * a + 255 * (255 - a)) // 255
        previous = line
    return width, height, pixels


def unfilter(method, line, previous, bpp, stride):
    if method == 0:
        return
    if method == 1:
        for x in range(bpp, stride):
            line[x] = (line[x] + line[x - bpp]) & 0xFF
    elif method == 2:
        for x in range(stride):
            line[x] = (line[x] + previous[x]) & 0xFF
    elif method == 3:
        for x in range(stride):
            left = line[x - bpp] if x >= bpp else 0
            line[x] = (line[x] + ((left + previous[x]) >> 1)) & 0xFF
    elif method == 4:
        for x in range(stride):
            left = line[x - bpp] if x >= bpp else 0
            up = previous[x]
            corner = previous[x - bpp] if x >= bpp else 0
            estimate = left + up - corner
            da, db, dc = (
                abs(estimate - left), abs(estimate - up), abs(estimate - corner)
            )
            if da <= db and da <= dc:
                predictor = left
            elif db <= dc:
                predictor = up
            else:
                predictor = corner
            line[x] = (line[x] + predictor) & 0xFF
    else:
        raise SystemExit(f"unknown PNG filter {method}")


def content_bounds(pixels, width, height):
    """The smallest box holding everything that is not background."""
    min_x, min_y, max_x, max_y = width, height, -1, -1
    for y in range(height):
        row = y * width * 3
        for x in range(width):
            base = row + x * 3
            if (
                pixels[base] < WHITE
                or pixels[base + 1] < WHITE
                or pixels[base + 2] < WHITE
            ):
                min_x = min(min_x, x)
                max_x = max(max_x, x)
                min_y = min(min_y, y)
                max_y = max(max_y, y)
    if max_x < 0:
        raise SystemExit("the source is entirely background")
    return min_x, min_y, max_x, max_y


def resample(pixels, width, box, target_w, target_h):
    """Area-averages the box down to the target size."""
    left, top, right, bottom = box
    source_w = right - left + 1
    source_h = bottom - top + 1
    out = bytearray(target_w * target_h * 3)

    for ty in range(target_h):
        y0 = top + ty * source_h / target_h
        y1 = top + (ty + 1) * source_h / target_h
        rows = range(int(y0), max(int(y0) + 1, min(int(y1 - 1e-9) + 1, bottom + 1)))
        for tx in range(target_w):
            x0 = left + tx * source_w / target_w
            x1 = left + (tx + 1) * source_w / target_w
            cols = range(
                int(x0), max(int(x0) + 1, min(int(x1 - 1e-9) + 1, right + 1))
            )
            r = g = b = count = 0
            for sy in rows:
                base_row = sy * width * 3
                for sx in cols:
                    base = base_row + sx * 3
                    r += pixels[base]
                    g += pixels[base + 1]
                    b += pixels[base + 2]
                    count += 1
            base = (ty * target_w + tx) * 3
            out[base] = r // count
            out[base + 1] = g // count
            out[base + 2] = b // count
    return out


def write_png(path, width, height, pixels):
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        raw += pixels[y * width * 3:(y + 1) * width * 3]

    def chunk(kind, payload):
        body = kind + payload
        return (
            struct.pack(">I", len(payload))
            + body
            + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)
        )

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )


def main(argv):
    source = pathlib.Path(argv[1]) if len(argv) > 1 else SOURCE
    if not source.exists():
        raise SystemExit(f"no artwork at {source}")

    width, height, pixels = read_png(source)
    left, top, right, bottom = content_bounds(pixels, width, height)
    mark_w, mark_h = right - left + 1, bottom - top + 1
    print(f"source {width}x{height}, mark {mark_w}x{mark_h} at ({left}, {top})")

    # Scale by whichever axis runs out first, so the mark is never cropped.
    scale = min(SIZE * FILL / mark_w, SIZE * FILL / mark_h)
    target_w = max(1, round(mark_w * scale))
    target_h = max(1, round(mark_h * scale))
    scaled = resample(pixels, width, (left, top, right, bottom), target_w, target_h)

    canvas = bytearray(bytes(BACKGROUND) * (SIZE * SIZE))
    offset_x = (SIZE - target_w) // 2
    offset_y = (SIZE - target_h) // 2
    for y in range(target_h):
        start = ((offset_y + y) * SIZE + offset_x) * 3
        canvas[start:start + target_w * 3] = scaled[y * target_w * 3:(y + 1) * target_w * 3]

    write_png(DESTINATION, SIZE, SIZE, canvas)
    print(
        f"wrote {DESTINATION.relative_to(ROOT)} — mark {target_w}x{target_h} "
        f"centred on {SIZE}x{SIZE}, opaque RGB"
    )


if __name__ == "__main__":
    main(sys.argv)
