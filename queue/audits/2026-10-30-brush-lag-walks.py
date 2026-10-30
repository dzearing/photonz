import json,sys,argparse
p=argparse.ArgumentParser()
p.add_argument('--w',type=int,default=4000); p.add_argument('--h',type=int,default=3000)
p.add_argument('--media',default='watercolour,oil,pencil,charcoal,chalk,crayon,marker,airbrush')
p.add_argument('--sizes',default='20,50,150,300,500')
p.add_argument('--pre',type=int,default=50); p.add_argument('--reps',type=int,default=1)
p.add_argument('--out',default='bl'); p.add_argument('--steps',type=int,default=120)
a=p.parse_args()
W,H=a.w,a.h
s=[{"do":"blank","canvasWidth":W,"canvasHeight":H,"width":1500,"height":1000,"pixelScale":1},
   {"do":"wait","seconds":1.5},{"do":"key","key":"b"},{"do":"waitFor","condition":"tool","value":"brush"},
   {"do":"action","action":"zoomToFit"},{"do":"wait","seconds":0.6},{"do":"action","action":"paintToolColor"}]
pre=['watercolour','pencil','oil','marker','charcoal']
for i in range(a.pre):
    if i%10==0: s.append({"do":"pickBrush","medium":pre[(i//10)%5],"size":40*W/4000})
    y=H*0.05+i*(H*0.9/max(1,a.pre))
    s.append({"do":"drag","from":[W*0.075,y],"to":[W*0.925,y+H*0.01],"steps":20,"wobble":1.5})
s.append({"do":"wait","seconds":2})
rows=[0.15,0.45,0.75]; k=0
for m in a.media.split(','):
  for z in a.sizes.split(','):
    for r in range(a.reps):
      s.append({"do":"pickBrush","medium":m,"size":float(z)*W/4000 if False else float(z)})
      s.append({"do":"wait","seconds":1})
      y=H*rows[k%3]; k+=1
      # 10 pt a move
      length=10*a.steps
      x0=max(W*0.05,(W-length*0.97)/2)
      s.append({"do":"drag","from":[x0,y],"to":[x0+length*0.97,y+min(length*0.24,H*0.2)],"steps":a.steps,"wobble":1.5})
      s.append({"do":"expectBrushResponsive"})
      s.append({"do":"wait","seconds":0.8})
json.dump({"out":"/tmp/photonz-playtest/"+a.out,"seed":"brush lag measurement","setup":{"forget":["tools","panel"]},"steps":s},open(f"/tmp/brushlag/{a.out}.walk","w"),indent=1)
print(f"/tmp/brushlag/{a.out}.walk", len(s))
