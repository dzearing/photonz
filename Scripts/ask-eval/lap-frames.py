# Draws a contact sheet of a landed Ask motion plan from the JSON LapDump
# writes (Tests/PhotonzCoreTests/AskMotionFadeKeptTests.swift): each drawn
# line where the contact checks have it, faded by its opacity. A look at a
# plan in seconds, without the model. Usage: lap-frames.py <lap.json> <out.png>
import json, sys
from PIL import Image, ImageDraw, ImageFont
d=json.load(open(sys.argv[1])); out=sys.argv[2]
vx,vy,vw,vh=d['view']; S=200; cols=8
frames=d['frames']; rows=(len(frames)+cols-1)//cols
img=Image.new('RGB',(cols*S,rows*S),'white'); dr=ImageDraw.Draw(img)
for i,f in enumerate(frames):
    ox,oy=(i%cols)*S,(i//cols)*S
    k=S/vw
    cell=Image.new('RGB',(S,S),'white'); cd=ImageDraw.Draw(cell); ox0,oy0=ox,oy; ox,oy=0,0
    for p in f['parts']:
        a=max(0,min(100,p['opacity']))/100
        if a<0.02: continue
        c=int(255-(255-29)*a); col=(c,c,c)
        pts=[(ox+(x-vx)*k, oy+(y-vy)*k) for x,y in p['points']]
        if p['closed']: pts=pts+[pts[0]]
        w=max(1,int(p['width']*k))
        if p['filled'] and len(pts)>2: cd.polygon(pts,fill=col)
        if len(pts)>1: cd.line(pts,fill=col,width=w,joint='curve')
        for q in (pts[0],pts[-1]): cd.ellipse([q[0]-w/2,q[1]-w/2,q[0]+w/2,q[1]+w/2],fill=col)
    cd.text((4,2),f"{f['t']:.2f}s",fill=(120,120,120)); cd.rectangle([0,0,S-1,S-1],outline=(210,210,210))
    img.paste(cell,(ox0,oy0))
img.save(out)
