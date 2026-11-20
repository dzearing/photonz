#!/usr/bin/env python3
# Splits the main thread of a Time Profiler trace of the probe into bursts
# (runs of samples with no gap over --gap ms, one run-loop pass each, near
# enough) and says where the long ones spent their time.
#
#   xcrun xctrace record --template 'Time Profiler' --attach <probe pid> \
#       --time-limit 45s --output picks.trace
#   python3 Scripts/perf/trace-bursts.py picks.trace [--min 15] [--gap 1.6] [--top 25]
#       [--focus 'SymbolSubstring']   only bursts holding a frame with that in its name
#       [--without 'SymbolSubstring'] only bursts holding no frame with that in its name
#       [--list]                      one line per long burst, in time order
#       [--passes]                    cut by the probe's own pass marks instead of by gaps
#       [--from S] [--to S]           only passes starting in that window, seconds from
#                                     the first main thread sample
#       [--at S S ...]                only the passes starting within 3 ms of each time
#                                     (the second pass after each key, say, read off --list)
#       [--dump 'Symbol']             the stacks around that frame, heaviest first
#       [--below 'Symbol']            the app's own views, layouts and getters found under
#                                     that frame, heaviest first: which ScrollView or
#                                     GeometryReader a pass is measuring, say (a frame
#                                     counts as the app's when its type is one the app
#                                     declares, read from Sources/)
#       [--process Photonz]           only that process: for a trace recorded with
#                                     --all-processes instead of --attach, which is how
#                                     to catch a window's opening in a walk's setup
#
# --passes needs the trace recorded with the os_signpost instrument as well
# (`--instrument os_signpost` after the template): the probe's main thread
# meter leaves a Points of Interest mark at the end of every pass of 6 ms or
# more, saying how long it was and which piece of the dock landed in it
# (`MainThreadMeter.notePass`). Back to back passes have no gap between them,
# so cutting by gaps runs a panel's fifteen arrivals together into one burst.
#
# Passes 5 to 11 of a-long-edit-with-transitions-plays-scrubs-and-ed each wrote
# this in /tmp and lost it. The buckets are the ones those passes reported:
# window layout, AttributeGraph update, accessibility and focus, view bodies,
# Core Animation commit. A sample counts once, in the first bucket that
# matches anywhere in its stack, in the order listed.
import sys, collections, subprocess, tempfile, os, argparse
import xml.etree.ElementTree as ET

ap = argparse.ArgumentParser()
ap.add_argument('trace')
ap.add_argument('--min', type=float, default=15.0, help='shortest burst to report, ms')
ap.add_argument('--gap', type=float, default=1.6, help='a gap longer than this ends a burst, ms')
ap.add_argument('--top', type=int, default=25)
ap.add_argument('--focus', default=None)
ap.add_argument('--without', default=None)
ap.add_argument('--list', action='store_true')
ap.add_argument('--passes', action='store_true')
ap.add_argument('--process', default=None, help='only this process (a trace recorded with --all-processes), e.g. Photonz')
ap.add_argument('--share', nargs='*', default=[], help='say what share of the long passes has each of these in its stack')
ap.add_argument('--from', dest='frm', type=float, default=None, help='only passes starting at or after this, s')
ap.add_argument('--to', type=float, default=None, help='only passes starting at or before this, s')
ap.add_argument('--at', type=float, nargs='*', default=None, help='only passes starting within 3 ms of these, s')
ap.add_argument('--dump', default=None, help='print the stacks around this frame')
ap.add_argument('--below', default=None, help="name the app's own frames found under this frame, heaviest first")
args = ap.parse_args()

def export(trace, schema):
    out_path = os.path.join(tempfile.mkdtemp(), schema + '.xml')
    with open(out_path, 'w') as out:
        subprocess.run(['xcrun', 'xctrace', 'export', '--input', trace, '--xpath',
                        f'/trace-toc/run[@number="1"]/data/table[@schema="{schema}"]'],
                       stdout=out, stderr=subprocess.DEVNULL, check=True)
    return out_path

path = args.trace
if not path.rstrip('/').endswith('.trace') and args.passes:
    sys.exit('--passes reads the pass marks out of the .trace itself; hand it the .trace')
trace = path
if path.rstrip('/').endswith('.trace'):
    path = export(path, 'time-profile')
root = ET.parse(path).getroot()
ids = {}
for el in root.iter():
    if el.get('id') is not None: ids[el.get('id')] = el
def resolve(el):
    r = el.get('ref')
    return ids[r] if r is not None else el

marks = []  # (start ns, end ns, ms, what landed)
if args.passes:
    sroot = ET.parse(export(trace, 'os-signpost')).getroot()
    sids = {}
    for el in sroot.iter():
        if el.get('id') is not None: sids[el.get('id')] = el
    def sres(el): return sids[el.get('ref')] if el.get('ref') is not None else el
    for row in sroot.iter('row'):
        nm = row.find('signpost-name')
        if nm is None or sres(nm).get('fmt') != 'pass': continue
        sub = row.find('subsystem')
        if sub is None or 'photonz' not in (sres(sub).get('fmt') or ''): continue
        end = int(sres(row.find('event-time')).text)
        meta = row.find('os-log-metadata')
        text = (sres(meta).get('fmt') or '') if meta is not None else ''
        first, _, rest = text.strip().partition(' ')
        try: ms = float(first)
        except ValueError: continue
        marks.append((end - int(ms * 1e6), end, ms, rest.strip()))
    # Points of Interest and os_signpost can both carry the same mark.
    marks = sorted(set(marks))

samples = []  # (time ns, weight ms, [frame names leaf first])
for row in root.iter('row'):
    th = row.find('thread')
    if th is None or 'Main Thread' not in (resolve(th).get('fmt') or ''): continue
    if args.process:
        pr = row.find('process')
        if pr is None or args.process not in (resolve(pr).get('fmt') or ''): continue
    t = row.find('sample-time')
    if t is None: continue
    t = int(resolve(t).text)
    w = row.find('weight'); w = resolve(w) if w is not None else None
    ms = int(w.text) / 1e6 if w is not None and w.text else 1.0
    bt = row.find('tagged-backtrace') if row.find('tagged-backtrace') is not None else row.find('backtrace')
    if bt is None: continue
    bt = resolve(bt); inner = bt.find('backtrace')
    if inner is not None: bt = resolve(inner)
    names = [resolve(fr).get('name') or '' for fr in bt.iter('frame')]
    samples.append((t, ms, names))
samples.sort(key=lambda s: s[0])

bursts = []
landed_in = {}
if args.passes:
    import bisect
    times = [s[0] for s in samples]
    for start, end, ms, what in marks:
        lo, hi = bisect.bisect_left(times, start), bisect.bisect_right(times, end)
        if hi > lo:
            bursts.append(samples[lo:hi]); landed_in[id(bursts[-1])] = (ms, what)
else:
    cur = []
    for s in samples:
        if cur and (s[0] - cur[-1][0]) / 1e6 > args.gap + cur[-1][1]:
            bursts.append(cur); cur = []
        cur.append(s)
    if cur: bursts.append(cur)

# Leaf first: a sample counts in the bucket of the frame nearest its leaf that
# matches one, so SwiftUI's update run from inside Core Animation's commit is
# counted as SwiftUI's, and a sizeThatFits inside a body as layout.
buckets = [
    ('accessibility and focus', ['ccessibility', 'updateFocus', 'FocusNavigator', '_resetDragMargins', 'FocusStore', 'focusItem', 'AXElement']),
    ('view bodies', ['.body.getter', 'body.getter']),
    ('window layout', ['sizeThatFits', 'LayoutComputer', 'placeSubviews', 'ViewLayoutEngine', 'StackLayout', 'explicitAlignment',
                       'lengthThatFits', 'placement', 'NSHostingView.layout', 'layoutSubtreeIfNeeded', 'updateConstraints']),
    ('Core Animation and drawing', ['CA::Render', 'CA::Layer::display', 'CA::Context::commit', 'CA::Transaction::commit()', 'drawRect', 'drawLayer', 'RB::', 'CGContext']),
    ('AttributeGraph update', ['AG::', 'AttributeGraph', 'propagate_dirty']),
]
def bucket(names):
    for n in names:
        for label, keys in buckets:
            if any(k in n for k in keys): return label
    return 'other'

def dur(b):
    if id(b) in landed_in: return landed_in[id(b)][0]
    return (b[-1][0] - b[0][0]) / 1e6 + b[-1][1]
T0 = samples[0][0] if samples else 0
def starts_at(b): return (b[0][0] - T0) / 1e9
long = [b for b in bursts if dur(b) >= args.min
        and (args.frm is None or starts_at(b) >= args.frm) and (args.to is None or starts_at(b) <= args.to)
        and (args.at is None or any(abs(starts_at(b) - a) < 0.003 for a in args.at))]
if args.focus:
    long = [b for b in long if any(args.focus in n for s in b for n in s[2])]
if args.without:
    long = [b for b in long if not any(args.without in n for s in b for n in s[2])]
print(f'{len(samples)} main thread samples, {len(bursts)} bursts, {len(long)} of {args.min:.0f} ms or more'
      + (f' holding {args.focus}' if args.focus else ''))
if not long: sys.exit(0)
t0 = samples[0][0]
if args.list:
    for b in long:
        kinds = collections.Counter()
        for s in b: kinds[bucket(s[2])] += s[1]
        top = ', '.join(f'{k} {v:.0f}' for k, v in kinds.most_common(4))
        what = landed_in.get(id(b), (0, ''))[1]
        print(f'  {(b[0][0]-t0)/1e9:7.3f}s {dur(b):6.1f} ms  {top}' + (f'  [{what}]' if what else ''))
total = sum(s[1] for b in long for s in b)
kinds = collections.Counter(); incl = collections.Counter(); leaf = collections.Counter()
for b in long:
    for t, ms, names in b:
        kinds[bucket(names)] += ms
        if names: leaf[names[0][:100]] += ms
        for n in set(names): incl[n[:110]] += ms
print(f'{total:.0f} ms in those bursts, mean {total/len(long):.1f} ms, longest {max(dur(b) for b in long):.1f} ms')
for k, v in kinds.most_common(): print(f'  {v/total*100:5.1f}%  {k}')
print('inclusive, top frames (app and SwiftUI, skipping the run loop):')
skip = ('start', 'main', 'NSApplicationMain', '-[NSApplication run]', 'CFRunLoop', '__CFRunLoop', '_DPS', '_NSHIToolbox',
        'RunCurrentEventLoop', 'ReceiveNextEvent', 'BlockUntilNext', '-[NSApplication(NSEvent)', 'static App.main', 'runApp', 'NSApplication')
shown = 0
for n, v in incl.most_common(400):
    if any(n.startswith(p) for p in skip): continue
    print(f'  {v/total*100:5.1f}%  {n}')
    shown += 1
    if shown >= args.top: break
for sym in args.share:
    hit = sum(ms for b in long for t, ms, names in b if any(sym in n for n in names))
    print(f'  share {hit/total*100:5.1f}%  {sym}')
print('leaf:')
for n, v in leaf.most_common(10): print(f'  {v/total*100:5.1f}%  {n}')
if args.dump:
    stacks = collections.Counter()
    for b in long:
        for t, ms, names in b:
            outer = list(reversed(names))
            hits = [j for j, n in enumerate(outer) if args.dump in n]
            if hits:
                i = hits[-1]
                stacks[' > '.join(n[:60] for n in outer[max(0, i - 6):i + 8])] += ms
    print(f'stacks through {args.dump}:')
    for st, v in stacks.most_common(8): print(f'{v:6.1f} ms  {st}\n')

if args.below:
    import glob, re
    here = os.path.dirname(os.path.abspath(__file__))
    ours = set()
    for f in glob.glob(os.path.join(here, '..', '..', 'Sources', '**', '*.swift'), recursive=True):
        for m in re.finditer(r'\b(?:struct|class|enum|extension|actor)\s+([A-Z][A-Za-z0-9_]*)', open(f, errors='ignore').read()):
            ours.add(m.group(1))
    word = re.compile(r'([A-Z][A-Za-z0-9_]*)[.<(]')
    found = collections.Counter()
    through = 0.0
    for b in long:
        for t, ms, names in b:
            outer = list(reversed(names))
            hits = [j for j, n in enumerate(outer) if args.below in n]
            if not hits: continue
            through += ms
            seen = set()
            for n in outer[hits[0] + 1:]:
                m = word.search(n.replace('protocol witness for ', '').replace('specialized ', ''))
                if m and m.group(1) in ours and n not in seen:
                    seen.add(n)
                    found[n[:110]] += ms
    print(f'under {args.below} ({through:.0f} ms), the app\'s own frames:')
    for n, v in found.most_common(args.top): print(f'{v:7.1f} ms  {n}')
