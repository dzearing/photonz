#!/usr/bin/env python3
# Ranks where the main thread's time went in a Time Profiler trace of the
# probe, in the buckets the speed walk's audit reports (task
# a-speed-walk-measures-the-long-reference-edit-th):
#
#   xcrun xctrace record --template 'Time Profiler' --attach <probe pid> \
#       --time-limit 15s --output play.trace
#   python3 Scripts/perf/rank-trace.py play.trace
#
# Takes a .trace (exported here) or an already exported time-profile XML.
import sys, re, collections, subprocess, tempfile, os
import xml.etree.ElementTree as ET
path = sys.argv[1]
if path.rstrip('/').endswith('.trace'):
    exported = os.path.join(tempfile.mkdtemp(), 'time-profile.xml')
    with open(exported, 'w') as out:
        subprocess.run(['xcrun', 'xctrace', 'export', '--input', path, '--xpath',
                        '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]'],
                       stdout=out, stderr=subprocess.DEVNULL, check=True)
    path = exported
tree = ET.parse(path)
root = tree.getroot()
ids = {}
def resolve(el):
    r = el.get('ref')
    return ids[r] if r is not None else el
for el in root.iter():
    if el.get('id') is not None: ids[el.get('id')] = el
buckets = [
 ('look-ahead rebuilding edit points and track layout (MoviePlayLookahead)', ['MoviePlayLookahead']),
 ("preparing each picture's transitions (withEditPointTransitionsDrawn)", ['withEditPointTransitionsDrawn']),
 ('sound crossings at cuts (editPointSoundCrossings)', ['editPointSoundCrossings']),
 ('timeline lock checks rebuilding track layout (isCutLocked)', ['isCutLocked','isClipOnLockedTrack']),
 ('following the sound (followAudio)', ['followAudio']),
 ('undo history and document change (History/perform)', ['History.perform','EditorState.perform','registerUndo','History.']),
 ('splitting a clip (blade)', ['splitClipAtPlayhead']),
 ('other edit point arithmetic rebuilding track layout (editPointCut, trackLayout)', ['editPointCut','editPointMoments','trackLayout()']),
 ('SwiftUI view updates (AttributeGraph)', ['AG::','AttributeGraph','ViewGraph','GraphHost']),
 ('compositing and the renderer (DocumentRenderer, Core Image)', ['DocumentRenderer','CoreImage','CI::','RenderScheduler']),
 ('decoding frames (VideoToolbox, movie reads)', ['VideoToolbox','VTDecompression','MovieFrameRead','AVAssetReader','decode']),
 ('waveforms and thumbnails', ['aveform','humbnail','ilmstrip']),
 ('Core Animation commit and drawing', ['CA::Transaction','CA::Layer','CA::Render','drawRect','NSView display']),
]
main = collections.Counter(); total = 0; leafs = collections.Counter(); churn = 0
for row in root.iter('row'):
    th = row.find('thread')
    if th is None: continue
    th = resolve(th)
    if 'Main Thread' not in (th.get('fmt') or ''): continue
    st = row.find('thread-state'); st = resolve(st) if st is not None else None
    w = row.find('weight'); w = resolve(w) if w is not None else None
    ms = int(w.text)/1e6 if w is not None and w.text else 1.0
    bt = row.find('tagged-backtrace') if row.find('tagged-backtrace') is not None else row.find('backtrace')
    if bt is None: continue
    bt = resolve(bt)
    inner = bt.find('backtrace')
    if inner is not None: bt = resolve(inner)
    names = []
    for fr in bt.iter('frame'):
        fr = resolve(fr)
        names.append(fr.get('name') or '')
    total += ms
    joined = '\n'.join(names)
    hit = None
    for label, keys in buckets:
        if any(k in joined for k in keys):
            hit = label; break
    main[hit or 'other main thread work'] += ms
    if names: leafs[names[0][:90]] += ms
    if any(k in (names[0] if names else '') for k in ['initializeWithCopy','malloc','free','swift_release','swift_retain','_platform_memmove','swift_allocObject','swift_deallocObject','objc_release']):
        churn += ms
print(f'main thread: {total/1000:.1f}s of samples')
for label, ms in main.most_common():
    print(f'  {ms/total*100:5.1f}%  {ms/1000:6.2f}s  {label}')
print(f'  of all of it, {churn/total*100:.1f}% was copying, allocating and freeing (memory churn at the leaf)')
print('top leaf functions:')
for name, ms in leafs.most_common(8): print(f'  {ms/total*100:5.1f}%  {name}')

# What the "other" bucket is: the first app-looking frame up from the leaf.
other = collections.Counter()
for row in root.iter('row'):
    th = row.find('thread')
    if th is None or 'Main Thread' not in (resolve(th).get('fmt') or ''): continue
    w = row.find('weight'); w = resolve(w) if w is not None else None
    ms = int(w.text)/1e6 if w is not None and w.text else 1.0
    bt = row.find('tagged-backtrace') if row.find('tagged-backtrace') is not None else row.find('backtrace')
    if bt is None: continue
    bt = resolve(bt); inner = bt.find('backtrace')
    if inner is not None: bt = resolve(inner)
    names = [resolve(fr).get('name') or '' for fr in bt.iter('frame')]
    joined = '\n'.join(names)
    if any(any(k in joined for k in keys) for _, keys in buckets): continue
    app = [n for n in names if re.search(r'(EditorState|Photonz|Document|Timeline|Movie|Clip|Layer|History|Track)\w*[.(]', n)]
    key = ' < '.join(a[:60] for a in app[:3]) if app else (names[-8][:60] if len(names) > 8 else '?')
    other[key] += ms
print('the other main thread work, by the first app frames:')
for k, ms in other.most_common(12): print(f'  {ms/1000:6.2f}s  {k}')
