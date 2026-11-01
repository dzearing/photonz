import json,sys
log=json.load(open(sys.argv[1])); done=json.load(open(sys.argv[2])); w=[json.loads(l) for l in open(sys.argv[3]) if l.startswith('{')]
start=done['startedAtMS']/1000
marks=[(e['stage'] if 'stage' in e else e.get('note'),start+e['t']) for e in log if e.get('do') and e.get('note')=='mark']
marks=[(e['do'],start+e['t']) for e in log if e.get('note')=='mark']
res=[]
for i,(name,t0) in enumerate(marks):
    t1 = marks[i+1][1] if i+1<len(marks) else t0+30
    bumps=[b for b in w if t0<=b['bump']<t1]
    if not bumps: print(name,'no bump'); continue
    b=bumps[0]
    clear=(b['bump']-t0)*1000
    png = clear + b['pngSeenMs'] if 'pngSeenMs' in b else None
    print(f"{name:24s} clipboard changed {clear:7.0f} ms after the press; png readable {png if png is None else round(png)} ms; typesAtBump {b['typesAtBump']}; png bytes {b.get('pngBytes')}; types {b.get('types','')}")
print("-- measured from the moment the copy itself began (the walk's own menu attempt left out):")
ents=[e for e in log if e.get('t') is not None]
for i,(name,t0) in enumerate(marks):
    t1 = marks[i+1][1] if i+1<len(marks) else t0+30
    bumps=[b for b in w if t0<=b['bump']<t1]
    if not bumps: continue
    # the last walk note written before the bump: the shortcut's "did not run" line, else the mark
    before=[start+e['t'] for e in ents if start+e['t']<=bumps[0]['bump'] and start+e['t']>=t0-0.0005]
    s=max(before) if before else t0
    print(f"{name:24s} {(bumps[0]['bump']-s)*1000:5.0f} ms")
