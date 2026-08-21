import re, math, sys
def load_screens(path):
    scr=[]
    for line in open(path):
        if line.startswith('SCREEN['):
            f,v = re.findall(r'=\(([^)]*)\)', line)
            f=[float(x) for x in f.split(',')]; v=[float(x) for x in v.split(',')]
            scr.append((f,v))
        elif scr: break
    ph=[f[3] for f,v in scr if f[0]==0 and f[1]==0][0]
    return [((f[0], ph-(f[1]+f[3]), f[2], f[3]), (v[0], ph-(v[1]+v[3]), v[2], v[3])) for f,v in scr]
def cadre(c, vis, M=2.5):
    W,H,E=29.,22.,4.5
    x=min(max(math.floor(c[0]+0.6)-W/2, vis[0]+M), vis[0]+vis[2]-M-W)
    pl=vis[1]+vis[3]-M
    y=c[1]+c[3]+E
    if y+H>pl: y=min(c[1]-E-H, pl-H)
    return x,y
def parse(v): return [float(x) for x in v.replace(' ',',').replace('x',',').split(',')]
for M in (2.5, 0.5):
  tot=ok=0; bad=[]
  for path in sys.argv[1:]:
    scr=load_screens(path); prev=None
    for line in open(path):
        if 'caretCG=' not in line or 'caps=' not in line or 'SELECTEUR' in line: continue
        car=tuple(parse(re.search(r'caretCG=\(([^)]*)\)', line).group(1)))
        cap=tuple(parse(re.search(r'caps=\(([^)]*)\)', line).group(1)))
        if cap[2]!=29.0: continue
        if prev and prev==cap: continue          # relevé périmé (cadre identique au précédent)
        prev=cap
        s=next((v for f,v in scr if f[0]<=car[0]<f[0]+f[2] and f[1]<=car[1]<f[1]+f[3]), None)
        if s is None: continue
        px,py=cadre(car,s,M); tot+=1
        if abs(px-cap[0])<.01 and abs(py-cap[1])<.01: ok+=1
        else: bad.append((path.split('/')[-1], line.split('\t')[0], f"{py-cap[1]:+.1f}"))
  print(f"MARGE={M}: {ok}/{tot} conformes ; écarts: {bad}")
