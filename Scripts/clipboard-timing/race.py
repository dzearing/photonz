import json,sys
from collections import defaultdict
rows=[json.loads(l) for l in open(sys.argv[1]) if l.startswith('{')]
print(len(rows),"pastes")
half=len(rows)//2
for name,part in [("screenshot",rows[:half]),("photo",rows[half:])]:
    by=defaultdict(list)
    for r in part: by[int(r['delayMs'])].append(r)
    for d in sorted(by):
        rs=by[d]; c=defaultdict(int)
        for r in rs: c[r['outcome']]+=1
        print(f"{name:10s} paste {d:3d} ms after the clipboard moved: {c['new']}/{len(rs)} new picture, {c['old']} old clipboard, {c['empty']} empty, {c['noPNG']} no PNG; longest wait for the read {max(r['waitedMs'] for r in rs):.0f} ms")
