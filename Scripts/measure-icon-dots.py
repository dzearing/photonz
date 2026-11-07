#!/usr/bin/env python3
"""Counts the dots on an icon's unit crossings, from two window captures.

The bar on `icon-snapping-reaches-what-the-icon-mock-draws`: with the Grid on and
Snap in Icons Grid on, a capture of a 24 unit artboard shows a dot on each of the
441 crossings of the live area and on none in the margin. It reads the pictures,
not the app's report of what it drew, so it can fail where the report cannot.

The second capture is the same window with Snap in Icons Grid off. A dot is what
changed at a crossing between the two, which is the only honest way to find one
on a dashed keyline: the keyline is in both.

Usage: Scripts/measure-icon-dots.py <with-dots.png> <without-dots.png> <left> <top> <right> <bottom>
The box is the artboard in the capture's pixels, edge to edge. It is asked for
because the margin wash `measure-icon-units.py` finds stops short of the frame's
own edge, and the crossings are counted from that edge.
"""
import json
import sys

from PIL import Image, ImageChops

WANTED = 441
CHANGED = 10


def main():
    args = sys.argv[1:]
    dotted = Image.open(args[0]).convert("RGB")
    plain = Image.open(args[1]).convert("RGB")
    box = tuple(int(v) for v in args[2:6])
    left, top, right, _ = box
    gap = (right - left) / 24
    pixels = ImageChops.difference(dotted, plain).load()

    def changed(x, y):
        return max(pixels[x, y][:3]) >= CHANGED

    live, margin, crossings = 0, 0, set()
    for row in range(1, 24):
        for column in range(1, 24):
            x, y = round(left + column * gap), round(top + row * gap)
            near = [(x + dx, y + dy) for dx in range(-4, 5) for dy in range(-4, 5)]
            crossings.update(near)
            if any(changed(*spot) for spot in near):
                if 2 <= row <= 22 and 2 <= column <= 22:
                    live += 1
                else:
                    margin += 1
    stray = sum(1 for x in range(box[0], box[2]) for y in range(box[1], box[3])
                if (x, y) not in crossings and changed(x, y))
    print(json.dumps({"artboard": box, "live_area_dots": live, "margin_dots": margin,
                      "pixels_changed_off_a_crossing": stray}))
    good = live == WANTED and margin == 0 and stray == 0
    print(f"PASS: {live} dots, one on every crossing of the live area" if good
          else f"FAIL: {live} dots against {WANTED}, {margin} in the margin, {stray} stray pixels")
    return 0 if good else 1


if __name__ == "__main__":
    sys.exit(main())
