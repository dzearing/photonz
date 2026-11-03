#!/usr/bin/env python3
"""Counts what each paste got, by the way it read and how long after the
capture. Exits 1 when any paste missed the new screenshot."""
import json, sys
from collections import Counter, defaultdict
rows = [json.loads(l) for l in open(sys.argv[1]) if l.startswith("{")]
# The walk clears the clipboard before its first capture; that is not a paste.
rows = [r for r in rows if not (r["n"] == 1 and r["types"] == 0)]
by = defaultdict(Counter)
for r in rows:
    by[(r["style"], int(r["delayMs"]))][r["outcome"]] += 1
for (style, delay), c in sorted(by.items()):
    n = sum(c.values())
    misses = ", ".join(f"{k} {v}" for k, v in c.items() if k != "new")
    print(f"{style:9s} {delay:5d} ms after: {c['new']}/{n} got the new screenshot" + (f" ({misses})" if misses else ""))
bad = sum(1 for r in rows if r["outcome"] != "new")
print(f"{len(rows) - bad}/{len(rows)} pastes got it")
sys.exit(1 if bad else 0)
