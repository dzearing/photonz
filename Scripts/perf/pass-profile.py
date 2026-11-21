#!/usr/bin/env python3
"""What each pass of an edit spends its time on, from `PassSampler`.

Reads the folder `pass-profile.sh` filled (passes.txt: every main thread pass
of 6 ms or more the speed walk's edits made, with the main thread's stack
sampled every half millisecond inside it; syms.txt: each return address named
by lldb against the live probe) and prints, for each kind of edit and each
pass in order after it (the edit's own pass first), how its milliseconds
split into SwiftUI's phases, and the app's own functions that took the most.

    Scripts/perf/pass-profile.py [folder] [--match "trim, picked"] [--top 12]

Phases are read from the root of each sample down, first match wins, so a
body built inside a layout counts as layout. Shares of a pass are shares of
its samples; milliseconds are those shares of the pass's measured length.
"""
import collections
import re
import sys

args = sys.argv[1:]
folder = "/tmp/photonz-pass-sampler"
match = None
top = 12
while args:
    a = args.pop(0)
    if a == "--match":
        match = args.pop(0)
    elif a == "--top":
        top = int(args.pop(0))
    else:
        folder = a

names = {}
for line in open(f"{folder}/syms.txt"):
    address, _module, name = line.rstrip("\n").split("\t")
    names[int(address, 16)] = name

passes, current = [], None
for line in open(f"{folder}/passes.txt"):
    if line.startswith("pid"):
        continue
    if line.startswith("PASS"):
        label, ms, start, _count = [x.strip() for x in line[5:].split("|")]
        current = {"label": label, "ms": float(ms), "start": float(start), "samples": []}
        passes.append(current)
    elif current is not None:
        current["samples"].append([names.get(int(x, 16), "?") for x in line.split()])

# "3 trim, picked" -> every pass of that one edit, in order.
by_edit = collections.defaultdict(list)
for p in passes:
    by_edit[p["label"]].append(p)

# Edit kind -> pass position -> passes.
kinds = collections.defaultdict(lambda: collections.defaultdict(list))
for label, ps in by_edit.items():
    kind = label.split(" ", 1)[1]
    if match and match not in kind:
        continue
    ps.sort(key=lambda p: p["start"])
    for i, p in enumerate(ps):
        kinds[kind][i].append(p)

# Never a phase: a merged SwiftUI symbol that sits near the root of every
# sample and mentions a responder.
noise = re.compile(r"TestingAppDelegate")
phases = [
    ("the edit itself", r"SpeedWalkProbe\.perform"),
    ("playback tick or a frame landing", r"documentMomentChanged|movieFrameLanded|restartDocumentClock"),
    ("title bar drag regions", r"DragMargin|StructuralRegions"),
    ("accessibility", r"Accessibility(?!Core\.textRes)"),
    ("focus", r"Focus"),
    ("AppKit views updated", r"PlatformViewChild\.updateValue|updateNSView"),
    ("view bodies", r"ViewBodyAccessor\.updateBody|StaticBody\.updateValue"),
    ("layout", r"sizeThatFits|placeSubviews|childGeometries|LayoutComputer|lengthThatFits|NSHostingView\.layout|_layoutViewTree"),
    ("drawing", r"DisplayList|RBLayer|render\(interval|display_if_needed|RB::"),
    ("Core Animation commit", r"CA::Transaction|CA::Context"),
    ("observation", r"Observation"),
    ("SwiftUI graph, other", r"GraphHost|AG::"),
]
app = re.compile(r"^(Photonz|PhotonzCore|PhotonzRender|PhotonzMedia)\.")

for kind in sorted(kinds):
    positions = kinds[kind]
    print(f"\n{kind}")
    for i in sorted(positions):
        ps = positions[i]
        mean = sum(p["ms"] for p in ps) / len(ps)
        shares = collections.Counter()
        funcs = collections.Counter()
        for p in ps:
            per = p["ms"] / max(1, len(p["samples"])) / len(ps)
            for s in p["samples"]:
                root_first = [f for f in reversed(s) if not noise.search(f)]
                got = "other"
                for name, pattern in phases:
                    if any(re.search(pattern, f) for f in root_first):
                        got = name
                        break
                shares[got] += per
                for f in set(s):
                    if app.search(f) and "SpeedWalkProbe" not in f:
                        funcs[f] += per
        print(f"  pass {i + 1}: {mean:.1f} ms on average over {len(ps)}")
        for name, ms in shares.most_common():
            if ms >= 0.2:
                print(f"    {ms:5.1f} ms  {name}")
        for f, ms in funcs.most_common(top):
            if ms >= 0.2:
                print(f"      {ms:5.1f} ms  {f[:140]}")
