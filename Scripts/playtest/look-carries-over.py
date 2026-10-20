#!/usr/bin/env python3
"""Reads what the-whole-look-carries-over-walk saved and says, for each kind of
thing drawn, which settings set on the first one the second one arrived with.

    python3 -I Scripts/playtest/look-carries-over.py [project.photonz]

The walk draws a first of each kind, styles it from the panel, draws a second
with nothing set on it, and saves. A setting "carries" when the second has the
value the first was given. Only the settings the walk set are listed.
"""
import json
import sys

PROJECT = sys.argv[1] if len(sys.argv) > 1 else \
    "/tmp/photonz-playtest/the-whole-look-carries-over-walk/project.photonz"

COMMON = ["Opacity", "Shadow", "Fade In", "Fade Out"]
# The kind, its first layer's name, and what the walk set on it.
PAIRS = [("arrow", "Arrow", COMMON + ["Thickness", "Arrow style", "Ends", "Head", "Head size"]),
         ("line", "Line", COMMON + ["Thickness", "Ends"]),
         ("box", "Rectangle", COMMON + ["Corner radius"]),
         ("oval", "Ellipse", COMMON),
         ("highlight", "Highlight", COMMON),
         ("Pen path", "Path", COMMON + ["Thickness", "Ends", "Dashes"]),
         ("words", "Text", COMMON),
         ("picture", "Plain white tile 200x140", COMMON)]

# What the panel set on the first one, and where to read it.
SETTINGS = [
    ("Opacity", lambda l: l["style"].get("opacity")),
    ("Shadow", lambda l: [e for e in l["style"].get("effects", []) if e.get("kind") == "shadow"]),
    ("Fade In", lambda l: (l.get("pictureFade") or {}).get("inMS", 0)),
    ("Fade Out", lambda l: (l.get("pictureFade") or {}).get("outMS", 0)),
    ("Thickness", lambda l: shape(l).get("strokeWidth")),
    ("Corner radius", lambda l: shape(l).get("cornerRadius") if shape(l).get("shape") == "rectangle" else None),
    ("Arrow style", lambda l: shape(l).get("arrowStyle")),
    ("Ends", lambda l: shape(l).get("lineEnd")),
    ("Head", lambda l: shape(l).get("arrowheadStyle")),
    ("Head size", lambda l: shape(l).get("arrowheadScale")),
    ("Dashes", lambda l: shape(l).get("linePattern")),
]


def shape(layer):
    content = layer.get("content", {})
    if "annotation" in content:
        return content["annotation"]["_0"]
    if "path" in content:
        return content["path"]["_0"]
    return {}


def main():
    with open(f"{PROJECT}/document.json") as handle:
        layers = {layer["name"]: layer for layer in json.load(handle)["layers"]}
    gaps = 0
    for kind, name, wanted in PAIRS:
        first, second = layers.get(name), layers.get(f"{name} 2")
        if not first or not second:
            print(f"{kind}: not both drawn")
            continue
        rows = []
        for setting, read in SETTINGS:
            if setting not in wanted:
                continue
            a, b = read(first), read(second)
            carried = a == b
            gaps += 0 if carried else 1
            rows.append(f"{setting} {'carries' if carried else f'DOES NOT carry ({a!r} -> {b!r})'}")
        print(f"{kind}: " + "; ".join(rows))
    print(f"{gaps} setting(s) did not carry")
    return 1 if gaps else 0


if __name__ == "__main__":
    sys.exit(main())
