#include "../_shared/scan.hlsli"
#include "quad.hlsli"
#define CAL_N 577
#define MASK_BASE 32
#define MASK_MAX 16
#define POLY_BASE 65
#define POLY_MAX 32
#define CUT_MAX 72
float2 mapUV(float2 uv){uint b=DEST*CAL_N;float3x3 m=float3x3(_Data1[b+1].value.xyz,_Data1[b+2].value.xyz,_Data1[b+3].value.xyz);
float2 z=saturate(uv)*4;int2 k=min((int2)floor(z),3);float2 t=z-k;float4 wx=weights(t.x),wy=weights(t.y);float2 d=0;
[unroll]for(int y=0;y<4;y++)[unroll]for(int x=0;x<4;x++){int2 p=clamp(k+int2(x-1,y-1),0,4);d+=_Data1[b+4+p.y*5+p.x].value.xy*wx[x]*wy[y];}
return applyQuad(m,uv)+d;}
// Scan Signals are ILDA scanner space (+y up); the editor and its Calibration are screen space
// (+y down, like every image). Convert on the way into the warp and back out of it.
// Scanner correction, modelled in the laser's own field (centred on its optical axis, in slot-extent
// units), so an off-centre mapping gets more correction on the side further from the axis.
//   spacing: atan/tan per axis. Evens out line spacing that drifts progressively across the field.
//   bow:     x pulled by y^2, y by x^2. Positive bows lines outward, cancelling a pincushion bow.
// Corner-anchored: the correction's value at the four mapped corners is removed bilinearly, so the
// corners stay exactly where the handles put them and only the lines between them move.
// tan's argument is clamped under pi/2 so a strong negative Spacing can't reach the pole at the field edge.
float spacingAxis(float v,float s){return abs(s)<1e-4?v:(s>0?atan(v*s)/s:tan(clamp(v*-s,-1.45,1.45))/-s);}
// c = the laser's straight-on point in the field, the centre the distortion is measured from.
float2 scannerShape(float2 q,float4 k,float2 c){q-=c;q=float2(spacingAxis(q.x,k.z),spacingAxis(q.y,k.w));return float2(q.x*(1-k.x*q.y*q.y),q.y*(1-k.y*q.x*q.x))+c;}
// Calibration 29 = (bow x, bow y, spacing x, spacing y); 4.zw = distortion centre (scanner space);
// 30/31 = the correction at the four mapped
// corners, precomputed once by the editor. Old calibrations carry zeros there: no correction.
float2 warp(float2 p){float extent=_Data1[DEST*CAL_N].value.y;const float2 f=float2(1,-1);
 float2 uv=(p*f/extent+1)*.5,q=(mapUV(uv)*2-1)*extent;float4 k=_Data1[DEST*CAL_N+29].value;
 if(any(k!=0)){float4 c0=_Data1[DEST*CAL_N+30].value,c1=_Data1[DEST*CAL_N+31].value;float2 ctr=_Data1[DEST*CAL_N+4].value.zw;
  q=scannerShape(q,k,ctr)-lerp(lerp(c0.xy,c0.zw,uv.x),lerp(c1.xy,c1.zw,uv.x),uv.y);}
 return q*f;}
// Calibration = mapping (0..31) + zoning masks (32..64) + polygon points (65..576). A Calibration
// without a readable mask block is refused outright, so the laser blanks rather than drawing unmasked.
// Masks are in screen space (+y down); scan records are ILDA (+y up), so chords flip y first.
bool calOK(){return _Data1_Count==CAL_N&&_Data1[DEST*CAL_N].value.x>.5&&_Data1[DEST*CAL_N+MASK_BASE].value.y==5151;}
float4 mInfo(uint j){return _Data1[DEST*CAL_N+MASK_BASE+1+2*j].value;}
float4 mRect(uint j){return _Data1[DEST*CAL_N+MASK_BASE+2+2*j].value;}
float2 mPt(uint j,uint i){return _Data1[DEST*CAL_N+POLY_BASE+POLY_MAX*j+i].value.xy;}
float2 rot(float2 v,float a){float c=cos(a),s=sin(a);return float2(c*v.x-s*v.y,s*v.x+c*v.y);}
bool maskInside(uint j,float2 p){float4 k=mInfo(j),r=mRect(j);
 if(k.x>1.5){uint n=(uint)clamp(r.x,0,POLY_MAX);bool in_=false;if(n<3)return false;float2 a=mPt(j,n-1);
  [loop]for(uint i=0;i<n;i++){float2 b=mPt(j,i);if((a.y>p.y)!=(b.y>p.y)&&p.x<a.x+(p.y-a.y)*(b.x-a.x)/(b.y-a.y))in_=!in_;a=b;}return in_;}
 float2 l=rot(p-r.xy,-k.w);
 if(k.x<.5)return all(abs(l)<=r.zw);
 return all(r.zw>0)&&dot(l/r.zw,l/r.zw)<=1;}
// Lit only inside the field, outside every Block, and inside some Only-In when any exist.
// p is in screen space.
bool litAt(float2 p){
 if(any(abs(p)>1))return false;
 float4 h=_Data1[DEST*CAL_N+MASK_BASE].value;uint n=(uint)clamp(h.x,0,MASK_MAX);bool allowed=h.w<.5;
 [loop]for(uint j=0;j<n;j++){bool in_=maskInside(j,p);if(mInfo(j).y<.5){if(in_)return false;}else if(in_)allowed=true;}
 return allowed;}
// Where the chord a->b (t 0..1, screen space) crosses mask j's boundary.
void maskCrossings(uint j,float2 a,float2 b,inout float ts[CUT_MAX],inout uint nt,inout bool full){
 float4 k=mInfo(j),r=mRect(j);float2 d=b-a;
 if(k.x>1.5){
  uint n=(uint)clamp(r.x,0,POLY_MAX);if(n<3)return;
  [loop]for(uint i=0;i<n;i++){float2 p=mPt(j,i),e=mPt(j,(i+1)%n)-p;float den=d.x*e.y-d.y*e.x;if(abs(den)<1e-14)continue;
   float2 w=p-a;float t=(w.x*e.y-w.y*e.x)/den,s=(w.x*d.y-w.y*d.x)/den;
   if(s>=0&&s<=1&&t>0&&t<1){if(nt<CUT_MAX)ts[nt++]=t;else full=true;}}
  return;
 }
 // Rectangles and ellipses: into the shape's own frame (affine, so t is unchanged).
 float2 la=rot(a-r.xy,-k.w),ld=rot(d,-k.w),h=r.zw;
 float en=-1e30,ex=1e30;bool hit=true;
 if(k.x<.5){[unroll]for(uint ax=0;ax<2;ax++){if(abs(ld[ax])>1e-12){float t0=(-h[ax]-la[ax])/ld[ax],t1=(h[ax]-la[ax])/ld[ax];en=max(en,min(t0,t1));ex=min(ex,max(t0,t1));}else if(abs(la[ax])>h[ax])hit=false;}}
 else if(all(h>0)){float2 u=la/h,v=ld/h;float A=dot(v,v),B=2*dot(u,v),C=dot(u,u)-1,disc=B*B-4*A*C;
  if(A>1e-20&&disc>0){float s=sqrt(disc);en=(-B-s)/(2*A);ex=(-B+s)/(2*A);}else hit=false;}
 else hit=false;
 if(hit&&ex>en){[unroll]for(uint q=0;q<2;q++){float t=q==0?en:ex;if(t>0&&t<1){if(nt<CUT_MAX)ts[nt++]=t;else full=true;}}}
}
// Splits one chord (ILDA a->b) into alternating lit / blank pieces at the field edge and every
// mask edge. count and emit both call this, so the planned record count always matches what is
// written. Piece p runs from cut[p] to cut[p+1] and is lit when lit[p]. If a chord ever crosses
// more edges than the arrays hold, the whole chord is blanked: it can lose light, never leak it.
uint chordPieces(float2 a,float2 b,out float cut[CUT_MAX+1],out bool lit[CUT_MAX]){
 [loop]for(uint z=0;z<=CUT_MAX;z++)cut[z]=1;[loop]for(uint w=0;w<CUT_MAX;w++)lit[w]=false;cut[0]=0;
 float2 sa=a*float2(1,-1),sb=b*float2(1,-1);
 float ts[CUT_MAX];uint nt=0;bool full=false;
 [unroll]for(uint ax=0;ax<2;ax++){float d=sb[ax]-sa[ax];if(abs(d)>1e-12){[unroll]for(uint s=0;s<2;s++){float t=((s==0?-1:1)-sa[ax])/d;if(t>0&&t<1)ts[nt++]=t;}}}
 uint n=(uint)clamp(_Data1[DEST*CAL_N+MASK_BASE].value.x,0,MASK_MAX);
 [loop]for(uint j=0;j<n;j++)maskCrossings(j,sa,sb,ts,nt,full);
 if(full)return 1;
 // Sort the crossings in place, then walk the gaps between them.
 [loop]for(uint i=1;i<nt;i++){float v=ts[i];int k=(int)i-1;[loop]while(k>=0&&ts[k]>v){ts[k+1]=ts[k];k--;}ts[k+1]=v;}
 uint np=0;float last=0;
 [loop]for(uint g=0;g<=nt;g++){
  float next=g<nt?ts[g]:1;if(next-last<1e-7&&g<nt)continue;
  bool s=litAt(lerp(sa,sb,(last+next)*.5));
  if(np>0&&lit[np-1]==s)cut[np]=next;else{lit[np]=s;cut[np+1]=next;np++;}
  last=next;
 }
 return max(np,1u);
}
bool clipSegment(float2 a,float2 b,out float enter,out float leave){enter=0;leave=1;float2 d=b-a;
[unroll]for(int axis=0;axis<2;axis++){if(abs(d[axis])<1e-12){if(abs(a[axis])>1)return false;}else{float t0=(-1-a[axis])/d[axis],t1=(1-a[axis])/d[axis];enter=max(enter,min(t0,t1));leave=min(leave,max(t0,t1));}}return leave>enter;}

float distChord(float2 p,float2 a,float2 b){float2 d=b-a;return length(p-a-d*saturate(dot(p-a,d)/max(dot(d,d),1e-20)));}
float2 at(Scan r,float t){return warp(lerp(r.endpoints.xy,r.endpoints.zw,t));}
// Probe every intersected cell, not just the midpoint of the whole segment.
float deviation(Scan r,float lo,float hi){
 float knots[12];uint nk=2;knots[0]=lo;knots[1]=hi;
 float extent=_Data1[DEST*CAL_N].value.y;
 [loop]for(uint ax=0;ax<2;ax++){float delta=r.endpoints[ax+2]-r.endpoints[ax];if(abs(delta)>1e-12){
 [loop]for(uint k=0;k<5;k++){float t=((-1+.5*k)*extent-r.endpoints[ax])/delta;if(t>lo+1e-7&&t<hi-1e-7)knots[nk++]=t;}}}
 [loop]for(uint j=1;j<nk;j++){float v=knots[j];int k=j-1;[loop]while(k>=0&&knots[k]>v){knots[k+1]=knots[k];k--;}knots[k+1]=v;}
 float2 a=at(r,lo),b=at(r,hi);float err=0;
 [loop]for(uint j=1;j<nk;j++)[unroll]for(uint k=0;k<=4;k++)err=max(err,distChord(at(r,lerp(knots[j-1],knots[j],k*.25)),a,b));
 return err*1.25; // Conservative margin between finite probes.
}
uint nextNode(uint node){while(node>1&&(node&1)!=0)node>>=1;return node==1?0:node+1;}
uint pieceCount(Scan r,float lo,float hi){
 if(r.timing.w>.5)return 1;
 float cut[CUT_MAX+1];bool lit[CUT_MAX];return chordPieces(at(r,lo),at(r,hi),cut,lit);
}
