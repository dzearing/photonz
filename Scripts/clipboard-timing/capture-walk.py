#!/usr/bin/env python3
"""Writes a walk that lands COUNT new screenshots the way a capture does
(written into history, put on the clipboard, toasted), GAP seconds apart.
Usage: capture-walk.py COUNT GAP OUT.json [captureLands|captureLandsAndStays]"""
import json, sys
count, gap, out = int(sys.argv[1]), float(sys.argv[2]), sys.argv[3]
action = sys.argv[4] if len(sys.argv) > 4 else "captureLands"
steps = [{"do": "clearClipboard"}, {"do": "wait", "seconds": 1}]
for i in range(count):
    steps += [{"do": "action", "action": action}, {"do": "wait", "seconds": gap, "onTheClock": True}]
walk = {"out": "/tmp/photonz-playtest/capture-paste-walk",
        "setup": {"forget": ["all"], "captures": ["/tmp/copy-timing/screenshot-3456x2234.png"]},
        "steps": steps}
json.dump(walk, open(out, "w"), indent=1)
