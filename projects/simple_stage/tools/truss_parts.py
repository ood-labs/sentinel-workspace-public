"""Dependency-closed copy of truss_lab/build_catalog.py (profiles, Part, rail, straight, elbow, base, Rig, clamp, junction).
Vendored for Small Stage on 2026-10-03; truss_lab stays the source. Metres, +Y up. Never scales a stock section.
Small Stage changes nothing below except dropping the unused yaml import and the demo rigs."""
from pathlib import Path
import json, math
import numpy as np
ROOT = Path(__file__).resolve().parent
V=lambda x: np.asarray(x,dtype=float)
def unit(v): return V(v)/np.linalg.norm(v)
def frame(n, up=(0,1,0)):
    n=unit(n); up=V(up)
    if abs(np.dot(n,up))>.99: up=V((0,0,1))
    u=unit(np.cross(up,n)); return np.column_stack((u,np.cross(n,u),n))
def rz(a):
    a=math.radians(a); c,s=math.cos(a),math.sin(a)
    return np.array([[c,-s,0],[s,c,0],[0,0,1.]])
PROFILES={
 'F24':dict(size=.22,od=.035,wall=.0016,brace=.008,brace_wall=None,shape=4,alloy='6061-T6',connector='F23/F24',source='https://globaltruss.de/F24-100cm/F24100'),
 'F32':dict(size=.29,od=.05,wall=.002,brace=.02,brace_wall=.002,shape=2,alloy='6082-T6',connector='F3x',source='https://globaltruss.de/F32-100cm/F32100'),
 'F33':dict(size=.29,od=.05,wall=.002,brace=.02,brace_wall=.002,shape=3,alloy='6082-T6',connector='F3x',source='https://globaltruss.de/NetiMedia/download?mediaId=20a0ec9e1d0b47c6bfbe8e6cc7ed0a5b'),
 'F34':dict(size=.29,od=.05,wall=.002,brace=.02,brace_wall=.002,shape=4,alloy='6082-T6',connector='F3x',source='https://www.globaltruss.com/sq-4112'),
 'F44P':dict(size=.4,od=.05,wall=.003,brace=.025,brace_wall=.003,shape=4,alloy='6082-T6',connector='F3x',source='https://globaltruss.de/en/F44-P-50cm/F44050P')}
def section(series):
    p=PROFILES[series]; d=p['size']-p['od']
    if p['shape']==4: return [V((x,y,0)) for x,y in [(-d/2,-d/2),(d/2,-d/2),(d/2,d/2),(-d/2,d/2)]]
    if p['shape']==2: return [V((-d/2,0,0)),V((d/2,0,0))]
    return [V((-d/2,-d*math.sqrt(3)/6,0)),V((d/2,-d*math.sqrt(3)/6,0)),V((0,d*math.sqrt(3)/3,0))]
class Part:
    def __init__(self,sku,series,source='',verified='Published profile; brace layout and small fittings approximate'):
        self.sku,self.series,self.source,self.verified=sku,series,source,verified
        self.segments=[]; self.ports={}; self.mounts=[]
    def tube(self,a,b,r,wall=0,material=0,start_cut=(0,0,0),end_cut=(0,0,0)):
        if np.linalg.norm(V(b)-V(a))>1e-6: self.segments.append([*V(a),r,*V(b),wall,material,*start_cut,*end_cut])
    def box(self,center,half,material=1): self.segments.append([*V(center),-1,*V(half),0,material,1,0,0,0,1,0])
    def port(self,name,p,n,up=(0,1,0)):
        self.ports[name]=dict(p=V(p),F=frame(n,up),series=self.series)
    def transformed(self,R=np.eye(3),t=(0,0,0)):
        q=Part(self.sku,self.series,self.source,self.verified); t=V(t)
        for s in self.segments:
            a,b=R@V(s[:3])+t,R@V(s[4:7])+t
            if s[3]<0:
                b=V(s[4:7]) # Half extents stay local; cutA/cutB carry box axes.
            q.segments.append([*a,s[3],*b,*s[7:9],*(R@V(s[9:12])),*(R@V(s[12:15]))])
        q.ports={k:dict(p=R@v['p']+t,F=R@v['F'],series=v['series']) for k,v in self.ports.items()}
        q.mounts=[dict(a=(R@V(m['a'])+t).tolist(),b=(R@V(m['b'])+t).tolist(),diameter=m['diameter']) for m in self.mounts]
        return q
def rail(p,a,b,F):
    spec=PROFILES[p.series]; pts=section(p.series); a,b=V(a),V(b)
    for v in pts:
        aa,bb=a+F@v,b+F@v
        p.tube(aa,bb,spec['od']/2,spec['wall'])
        p.mounts.append(dict(a=aa.tolist(),b=bb.tolist(),diameter=spec['od']))
    L=np.linalg.norm(b-a); bays=max(1,round(L/.25)); inset=min(.07,L*.2)
    faces=len(pts) if len(pts)>2 else 1
    for f in range(faces):
        u,v=pts[f],pts[(f+1)%len(pts)]
        for end in [inset,L-inset]:
            c=a+(b-a)*(end/L); p.tube(c+F@u,c+F@v,spec['brace']/2)
        for j in range(bays):
            ta=inset+(L-2*inset)*j/bays; tb=inset+(L-2*inset)*(j+1)/bays
            x,y=(u,v) if j%2==0 else (v,u)
            p.tube(a+(b-a)*ta/L+F@x,a+(b-a)*tb/L+F@y,spec['brace']/2)
def straight(series,L,sku=None):
    p=Part(sku or f'{series}-{L:g}m',series,PROFILES[series]['source'],'Published section and nominal face-to-face length; repeated brace bays approximate')
    rail(p,(0,0,0),(0,0,L),np.eye(3)); p.port('A',(0,0,0),(0,0,-1)); p.port('B',(0,0,L),(0,0,1)); return p
def elbow(series,angle=90,roll=0):
    p=Part(f'{series}-C{angle:g}'+(f'-roll{roll}' if roll else ''),series,'https://www.globaltruss.com/trussing/f34-square-truss','90 degree F34 envelope verified 500x500x290 mm; other port offsets and brace layouts approximate')
    half=PROFILES[series]['size']/2; arm=.5-half
    if angle<=60: arm=1-half
    n0=V((0,0,-1)); a=math.radians(180-angle); n1=V((math.sin(a),0,math.cos(a)))
    F0=np.eye(3)@rz(roll); F1=frame(n1)@rz(roll)
    # Miter intersection in the horizontal plane, continuous per-chord centerline.
    for v in section(series):
        aa=F0@v; bb=F1@v
        A=np.column_stack((n0[[0,2]],-n1[[0,2]])); t=np.linalg.solve(A,(bb-aa)[[0,2]])
        joint=aa+n0*t[0]
        spec=PROFILES[series]
        cut=unit(n0-n1)
        p.tube(n0*arm+aa,joint,spec['od']/2,spec['wall'],end_cut=cut)
        p.tube(joint,n1*arm+bb,spec['od']/2,spec['wall'],start_cut=cut)
    # Cross braces stay inside each arm; no disconnected extra corner rails.
    for n,F in [(n0,F0),(n1,F1)]:
        tmp=Part('',series); rail(tmp,n*min(half*.8,arm*.45),n*arm,F)
        p.segments.extend(tmp.segments[len(section(series)):])
    p.port('A',n0*arm,n0); p.port('B',n1*arm,n1)
    # Preserve actual roll of non-square chord patterns in the mating frames.
    p.ports['A']['F']=frame(n0)@rz(-roll);p.ports['B']['F']=F1
    return p
def junction(directions,sku):
    p=Part(sku,'F34','https://www.globaltruss.com/'+sku.lower(),'500 mm corner envelope; central framing simplified. UJB block is 290 mm; half-cone stand-off approximate.')
    d=.12
    for ax in range(3):
        others=[i for i in range(3) if i!=ax]
        for u in [-d,d]:
            for v in [-d,d]:
                a=np.zeros(3); b=np.zeros(3);a[ax]=-d;b[ax]=d
                a[others]=[u,v];b[others]=[u,v];p.tube(a,b,.025,.002)
    for i,n in enumerate(directions):
        n=V(n); L=.145 if sku=='ST-UJB-12' else .355
        if L>.145: rail(p,n*.145,n*L,frame(n))
        p.port(str(i),n*L,n)
    return p
def base(size=.762,thickness=.0095):
    p=Part('BASE-PLATE-30X30A','F34','https://www.globaltruss.com/base-plate-30x30a','Published 762 x 762 x 9.5 mm plate; mounting hole and half-cone details approximate')
    p.box((0,thickness/2,0),(size/2,thickness/2,size/2),0)
    p.port('top',(0,thickness,0),(0,1,0));return p
class Rig:
    def __init__(self,name):self.name=name;self.parts={};self.joints=[];self.used=set()
    def add(self,id,p,R=np.eye(3),t=(0,0,0)):
        if id in self.parts:raise ValueError('duplicate part '+id)
        self.parts[id]=p.transformed(R,t);return id
    def connect(self,parent,out,id,p,inp='A',twist=0):
        a=self.parts[parent].ports[out];b=p.ports[inp]
        if (parent,out) in self.used:raise ValueError('port already occupied')
        if a['series']!=b['series']:raise ValueError('incompatible end patterns: '+a['series']+' / '+b['series'])
        count=PROFILES[a['series']]['shape']; step=360/count
        if abs(twist/step-round(twist/step))>1e-6:raise ValueError('twist does not align chord pattern')
        # Triangular pattern mirrors across X, not Y (which would invert its apex).
        flip=np.diag((-1,1,-1) if count==3 else (1,-1,-1))
        R=a['F']@rz(twist)@flip@b['F'].T
        self.add(id,p,R,a['p']-R@b['p'])
        try:self.join(parent,out,id,inp)
        except Exception:
            del self.parts[id]
            raise
        return id
    def join(self,a,ap,b,bp):
        x,y=self.parts[a].ports[ap],self.parts[b].ports[bp]
        if (a,ap) in self.used or (b,bp) in self.used:raise ValueError('occupied connection')
        if x['series']!=y['series']:raise ValueError('incompatible end patterns')
        gap=np.linalg.norm(x['p']-y['p']);normal=np.linalg.norm(x['F'][:,2]+y['F'][:,2])
        # Verify complete chord pattern, not only coincident center/normal.
        def ends(v):return [v['p']+v['F']@q for q in section(v['series'])]
        chord=max(min(np.linalg.norm(u-v) for v in ends(y)) for u in ends(x))
        if max(gap,normal,chord)>1e-5:raise ValueError(f'joint mismatch: {gap=} {normal=} {chord=}')
        self.used.update([(a,ap),(b,bp)]);self.joints.append(dict(a=a,ap=ap,b=b,bp=bp,gap_m=float(gap),chord_error_m=float(chord)))
    def flatten(self):
        p=Part(self.name,'F34',verified='Port-connected demonstration; not a structural design')
        for id,q in self.parts.items():
            p.segments+=q.segments;p.mounts+=q.mounts
            for name,v in q.ports.items():p.ports[id+':'+name]=v
        return p
def clamp():
    p=Part('50mm clamp mount','F34','https://www.globaltruss.com/products/accessories/couplers','Generic visual clamp; nominal 50 mm grip, not a verified supplier SKU')
    for i in range(24):
        a,b=i*2*math.pi/24,(i+1)*2*math.pi/24
        p.tube((.031*math.cos(a),.08+.031*math.sin(a),0),(.031*math.cos(b),.08+.031*math.sin(b),0),.006,0,2)
    p.box((0,.024,0),(.025,.025,.018),2);p.tube((0,-.02,0),(0,.025,0),.005,0,2)
    return p
