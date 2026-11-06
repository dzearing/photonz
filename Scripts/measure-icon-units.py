#!/usr/bin/env python3
"""Counts the lines crossing an icon's artboard in a window capture.

The bar on `a-24-unit-artboard-rules-itself-into-units`: in a crop of a 24 unit
artboard, 23 evenly spaced lines cross it each way. It reads the picture, not
the app's report of what it drew, so it can fail where the report cannot.

Usage: Scripts/measure-icon-units.py <capture.png> [left top right bottom]
With no box the artboard is found by the keylines' wash, the commonest violet
tint in the window. Sampled along the first unit row and column, where
the circle does not reach and only lines running edge to edge cross.
"""
import json
import sys
from collections import Counter
from statistics import median

from PIL import Image


def luminance(rgb):
    return 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]


def wash_box(image):
    """The bounding box of the margin wash: the commonest violet tint in the window."""
    width, height = image.size
    pixels = image.load()
    tints = Counter()
    for y in range(0, height, 2):
        for x in range(0, int(width * 0.8), 2):
            r, g, b = pixels[x, y][:3]
            if b - g >= 8 and b - r >= 3 and g > 150:
                tints[(r, g, b)] += 1
    wash = tints.most_common(1)[0][0]
    xs, ys = [], []
    for y in range(height):
        for x in range(int(width * 0.8)):
            if all(abs(pixels[x, y][i] - wash[i]) <= 2 for i in range(3)):
                xs.append(x)
                ys.append(y)
    return min(xs), min(ys), max(xs) + 1, max(ys) + 1


def profile(image, box, across):
    """Mean brightness along the artboard, averaged over a band in its first unit."""
    left, top, right, bottom = box
    pixels = image.load()
    side = right - left
    near, far = int(side / 24 * 0.25), int(side / 24 * 0.75)
    values = []
    if across:
        for x in range(left, right + 1):
            values.append(sum(luminance(pixels[x, top + d][:3]) for d in range(near, far)) / (far - near))
    else:
        for y in range(top, bottom + 1):
            values.append(sum(luminance(pixels[left + d, y][:3]) for d in range(near, far)) / (far - near))
    return values


def lines(values, edge):
    """Where the profile stands off its surroundings, a run of pixels counted once."""
    found = []
    run = []
    for i in range(edge, len(values) - edge):
        around = median(values[max(0, i - 12):i + 13])
        if abs(values[i] - around) >= 1.5:
            run.append(i)
        elif run:
            found.append(sum(run) / len(run))
            run = []
    if run:
        found.append(sum(run) / len(run))
    return found


def report(values, edge):
    found = lines(values, edge)
    gaps = [b - a for a, b in zip(found, found[1:])]
    return {
        "lines": len(found),
        "gap": round(median(gaps), 2) if gaps else None,
        "widest_gap": round(max(gaps), 2) if gaps else None,
        "narrowest_gap": round(min(gaps), 2) if gaps else None,
    }


def main():
    image = Image.open(sys.argv[1]).convert("RGB")
    box = tuple(int(v) for v in sys.argv[2:6]) if len(sys.argv) >= 6 else wash_box(image)
    edge = max(4, (box[2] - box[0]) // 24 // 6)
    result = {
        "artboard": box,
        "down": report(profile(image, box, True), edge),
        "across": report(profile(image, box, False), edge),
    }
    print(json.dumps(result))
    wanted = 23
    spread = [result[k]["widest_gap"] - result[k]["narrowest_gap"] for k in ("down", "across")
              if result[k]["gap"]]
    even = bool(spread) and max(spread) <= 2.5
    good = result["down"]["lines"] == wanted and result["across"]["lines"] == wanted and even
    print("PASS: 23 evenly spaced lines each way" if good else "FAIL: not 23 evenly spaced lines each way")
    return 0 if good else 1


if __name__ == "__main__":
    sys.exit(main())
