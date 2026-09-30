"""Offline model of Laser_Fixture's galvo projection: maps only the four frame corners (as a
first mapping pass does) and reports how far the wall grid still misses, i.e. how much Scanner
Correction the simulated laser needs. Keep it in step with modules/Laser_Fixture/project.hlsl."""
import math, numpy as np
FRAME_C=(0.0,1.5); FH=(1.5,0.9)
def wall(q,P):
    a=np.array([q[0]+P['zx'],q[1]+P['zy']]);a[1]*=P['gy'];a=a+P['nl']*a**3
    a=np.array([a[0]*(1+P.get('px',0)*a[1]**2),a[1]*(1+P.get('py',0)*a[0]**2)]);a[0]+=math.tan(math.radians(P['skew']))*a[1]
    ax=a[0]*math.radians(P['sx']/2);ay=a[1]*math.radians(P['sy']/2)
    d=np.array([math.sin(ax),math.cos(ax)*math.sin(ay),math.cos(ax)*math.cos(ay)])
    p=math.radians(P['pitch']);y=math.radians(P['yaw'])
    d=np.array([d[0],d[1]*math.cos(p)+d[2]*math.sin(p),d[2]*math.cos(p)-d[1]*math.sin(p)])
    d=np.array([d[0]*math.cos(y)+d[2]*math.sin(y),d[1],d[2]*math.cos(y)-d[0]*math.sin(y)])
    o=np.array(P['pos']);t=-o[2]/d[2];w=o+t*d;return np.array([w[0],w[1]])
def solve(target,P,guess):
    q=np.array(guess,float)
    for _ in range(60):
        f=wall(q,P)-target;J=np.zeros((2,2));h=1e-5
        for i in range(2):
            dq=np.zeros(2);dq[i]=h;J[:,i]=(wall(q+dq,P)-wall(q,P))/h
        q=q-np.linalg.solve(J,f)
    return q
def homog(src,dst):
    A=[]
    for (x,y),(u,v) in zip(src,dst):
        A.append([x,y,1,0,0,0,-u*x,-u*y,-u]);A.append([0,0,0,x,y,1,-v*x,-v*y,-v])
    _,_,V=np.linalg.svd(np.array(A));return V[-1].reshape(3,3)
def ap(H,p):
    r=H@np.array([p[0],p[1],1]);return r[:2]/r[2]
def report(name,P):
    corners=[(FRAME_C[0]-FH[0],FRAME_C[1]+FH[1]),(FRAME_C[0]+FH[0],FRAME_C[1]+FH[1]),(FRAME_C[0]+FH[0],FRAME_C[1]-FH[1]),(FRAME_C[0]-FH[0],FRAME_C[1]-FH[1])]
    uv=[(0,0),(1,0),(1,1),(0,1)]
    qc=[solve(np.array(c),P,(0,0)) for c in corners]
    H=homog(uv,[tuple(q) for q in qc])   # corner-only mapping: frame uv -> scan q, projective
    worst=0;bow=0;spc=0
    for i in range(5):
        for j in range(5):
            u,v=i/4,j/4
            want=np.array([FRAME_C[0]-FH[0]+u*2*FH[0],FRAME_C[1]+FH[1]-v*2*FH[1]])
            got=wall(ap(H,(u,v)),P);e=np.linalg.norm(got-want);worst=max(worst,e)
            if i==0 and j==2: bow=np.linalg.norm(got-want)
            if j==2 and i==1: spc=max(spc,np.linalg.norm(got-want))
    print("%-14s after corners only: worst error %.1f cm (%.1f%% of frame width), left-edge midpoint %.1f cm, inner line %.1f cm"%(name,worst*100,worst/3*100,bow*100,spc*100))
if __name__=="__main__":
    base=dict(zx=0.07,zy=-0.04,gy=0.97,skew=0.8)
    report("close pose",dict(base,nl=0.03,sx=80,sy=50,pos=(-0.5,1.3,2.6),yaw=169.11,pitch=4.32))
    stand=dict(base,sx=30,sy=20,pos=(1.35,1.55,6.3),yaw=-167.91,pitch=-0.44)
    report("stand, geometry only",dict(stand,nl=0.0))
    for nl,px,py in ((0.10,0.10,0.02),(0.12,0.12,0.03),(0.15,0.15,0.04)):
        report("nl %.2f px %.2f py %.2f"%(nl,px,py),dict(stand,nl=nl,px=px,py=py))
