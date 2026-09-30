// Axonometric of the ACTUAL generated tubes (chords bright, lacing dim) and solids, so the preview
// shows exactly what the renderer will draw. Members and solids arrive as projected marks binned
// into tiles (marks.hlsl, bins.hlsl); a pixel expands only its tile's members, and of each member
// only the bays its position along the axis can touch.
#include "assembly_types.hlsli"
#include "../_shared/ph_marks.hlsli"
#include "axo.hlsli"
StructuredBuffer<Tube> T:register(t1);
StructuredBuffer<PhMark> Marks:register(t2);
StructuredBuffer<uint> Bins:register(t3);
PhSolid solidRec(uint j){Tube t=T[TUBE_COUNT+j];PhSolid s;s.c=t.a;s.x=t.b;s.y=t.cutA;s.z=t.cutB;return s;}
RWTexture2D<float4> OutputUAV:register(u0);
#include "../_shared/plan_theme.hlsli"
#include "../_shared/ui/sui3_core.hlsli"
#include "../_shared/ui/sui3_text.hlsli"
#include "labels.hlsli"
static float2 gR;
float2 axo(float3 p){return axoAt(p,gR);}
float segDist(float2 p,float2 a,float2 b){float2 d=b-a;return length(p-a-d*saturate(dot(p-a,d)/max(dot(d,d),1e-5)));}
float ink(float d,float w){return saturate(w*.5+.5-d);}
void over(inout float3 c,float3 k,float a){c=lerp(c,k,saturate(a));}
void tube(inout float3 c,float2 P,uint m,uint t){Tube q=T[m*TUBES_PER+t];if(q.a.w<=0)return;
 over(c,t<4?PT_INK:t<64?PT_MID*.8:PT_MID,ink(segDist(P,axo(q.a.xyz),axo(q.b.xyz)),t<4?1.4:1.0));}
void member(inout float3 c,float2 P,PhMark mk){
 float2 a2=mk.geo.xy,b2=mk.geo.zw,ab=b2-a2;float band=mk.shape.y;if(segDist(P,a2,b2)>band)return;
 uint m=(uint)mk.fill.x;int bays=(int)mk.fill.y;float len=max(length(ab),1e-3),u=dot(P-a2,ab)/(len*len);
 // Corner offsets can shift a bay along the projected axis by up to the band width.
 int q0=clamp((int)floor(u*bays),0,bays-1),mb=(int)ceil(band*bays/len)+1;
 [loop]for(uint t=0;t<4;t++)tube(c,P,m,t);
 [loop]for(uint f=0;f<4;f++)[loop]for(int q=max(q0-mb,0);q<=min(q0+mb,bays-1);q++)tube(c,P,m,4+f*15+(uint)q);
 if(length(P-a2)<band*1.5+2){[loop]for(uint e=64;e<68;e++)tube(c,P,m,e);}
 if(length(P-b2)<band*1.5+2){[loop]for(uint e=68;e<72;e++)tube(c,P,m,e);}}
void solid(inout float3 c,float2 P,uint s){PhSolid o=solidRec(s);uint kind=(uint)o.c.w%10;if(kind==0)return;
 if(kind==1){[loop]for(uint e=0;e<12;e++){uint ax=e/4,j=e%4;float3 s0=float3(j&1?1:-1,j&2?1:-1,0);
   float3 A0,A1;if(ax==0){A0=float3(-1,s0.x,s0.y);A1=float3(1,s0.x,s0.y);}else if(ax==1){A0=float3(s0.x,-1,s0.y);A1=float3(s0.x,1,s0.y);}else{A0=float3(s0.x,s0.y,-1);A1=float3(s0.x,s0.y,1);}
   float3 p0=o.c.xyz+o.x.xyz*o.x.w*A0.x+o.y.xyz*o.y.w*A0.y+o.z.xyz*o.z.w*A0.z,p1=o.c.xyz+o.x.xyz*o.x.w*A1.x+o.y.xyz*o.y.w*A1.y+o.z.xyz*o.z.w*A1.z;
   over(c,PT_DIM,ink(segDist(P,axo(p0),axo(p1)),1));}}
 else if(kind==2){float3 tip=o.c.xyz+o.y.xyz*o.y.w;[loop]for(uint e=0;e<4;e++){float an=e*1.5707963;float3 bp=o.c.xyz+(o.x.xyz*cos(an)+o.z.xyz*sin(an))*o.x.w;
   over(c,PT_MID,ink(segDist(P,axo(bp),axo(tip)),1.2));}}
 else{float3 top=o.c.xyz+o.y.xyz*o.y.w;over(c,PT_INK,ink(segDist(P,axo(o.c.xyz),axo(top-o.y.xyz*.25)),2.2));c+=PT_INK*sui3Ring(P,axo(top-o.y.xyz*.12),.12*axoScale(gR),1.2);}}
[numthreads(8,8,1)]void main(uint3 id:SV_DispatchThreadID){
 uint W,H;OutputUAV.GetDimensions(W,H);if(id.x>=W||id.y>=H)return;float2 P=id.xy+.5;float3 c=PT_FIELD;gR=float2(W,H);
 float gScale=axoScale(gR);float2 gOrigin=axoOrigin(gR);
 float2 G=abs(frac((P-gOrigin)/(gScale*5)+.5)-.5)*gScale*5;c+=PT_GRID*ink(min(G.x,G.y),1)*.5;
 if(P.y<34){over(c,PT_INK,phLabel(P,float2(14,8),2,0));
  if(P.x>W-330){float4 n=Marks[AM_REC].fill;
   float x=W-14-sui3TextWidth(5,1);over(c,PT_INK,sui3Digits(P,float2(x,14),1,(int)n.y,5));x-=phLabelWidth(2,1)+6;over(c,PT_DIM,phLabel(P,float2(x,14),1,2));
   x-=sui3TextWidth(5,1)+18;over(c,PT_INK,sui3Digits(P,float2(x,14),1,(int)n.x,5));x-=phLabelWidth(1,1)+6;over(c,PT_DIM,phLabel(P,float2(x,14),1,1));}
  OutputUAV[id.xy]=float4(c,1);return;}
 // floor grid lines, members (real tubes), solids: in mark order, only this tile's marks
 uint base=phmTileOf(P,gR)*PHM_PER_TILE,h=Bins[base];bool all_=(h>>31)!=0;uint count=all_?AM_MARKS:(h&0x7fffffffu);
 [loop]for(uint k=0;k<count;k++){uint idx=all_?k:Bins[base+1+k];PhMark mk=Marks[idx];uint kind=(uint)mk.shape.x;
  if(kind==PHM_HIDDEN)continue;
  if(kind==AM_MEMBER_KIND)member(c,P,mk);else if(kind==AM_SOLID_KIND)solid(c,P,(uint)mk.fill.x);else phmDraw(c,P,mk);}
 OutputUAV[id.xy]=float4(c,1);
}
