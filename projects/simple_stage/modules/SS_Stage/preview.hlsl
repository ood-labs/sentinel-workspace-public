// SS_Stage / preview - the axonometric of the ACTUAL generated tubes (chords bright, lacing dim), solids and fixtures,
// so the drawing is exactly what the renderer gets. Marks arrive projected and binned into tiles (marks.hlsl,
// bins.hlsl); a pixel expands only its tile's members, and of each member only the bays its position along the axis
// can touch. While the pointer is on a member or a fixture (hover.hlsl) it steps up to ink and the rest steps down.
// The title, counts, key, slot numbers and the card are recorded by layout.hlsl and drawn over this (ui.hlsl).
#include "assembly.hlsli"
#include "../_shared/ss_marks.hlsli"
#include "axo.hlsli"
#include "../_shared/plan_theme.hlsli"
StructuredBuffer<SsMember> Mem:register(t0);
StructuredBuffer<Tube> T:register(t1);
StructuredBuffer<SsMark> Marks:register(t2);
StructuredBuffer<uint> Bins:register(t3);
StructuredBuffer<float4> Hover:register(t4);
StructuredBuffer<SsMount> Mounts:register(t5);
SsSolid solidRec(uint j){Tube t=T[TUBE_COUNT+j];SsSolid s;s.c=t.a;s.x=t.b;s.y=t.cutA;s.z=t.cutB;return s;}
RWTexture2D<float4> OutputUAV:register(u0);
static float2 gR;
static int gHm;      // the member under the pointer, -1 none
static int gHf;      // the fixture slot under the pointer, -1 none
float2 axo(float3 p){return axoAt(p,gR);}
float segDist(float2 p,float2 a,float2 b){float2 d=b-a;return length(p-a-d*saturate(dot(p-a,d)/max(dot(d,d),1e-5)));}
float ink(float d,float w){return saturate(w*.5+.5-d);}
void over(inout float3 c,float3 k,float a){c=lerp(c,k,saturate(a));}
float quiet(){return gHm<0&&gHf<0?1.0:.42;}
void tube(inout float3 c,float2 P,uint m,uint t){Tube q=T[m*TUBES_PER+t];if(q.a.w<=0)return;
 float d=segDist(P,axo(q.a.xyz),axo(q.b.xyz));
 if((int)m==gHm)over(c,t<4?PT_INK:PT_INK*.8,ink(d,t<4?2.0:1.2));
 else over(c,(t<4?PT_MID:PT_RULE)*quiet(),ink(d,t<4?1.4:1.0));}
void member(inout float3 c,float2 P,SsMark mk){
 float2 a2=mk.geo.xy,b2=mk.geo.zw,ab=b2-a2;float band=mk.shape.y;if(segDist(P,a2,b2)>band)return;
 uint m=(uint)mk.fill.x;int bays=(int)mk.fill.y;
 if(round(mk.fill.z)==KIND_BLOCK){[loop]for(uint e=0;e<12;e++)tube(c,P,m,e);return;}
 float len=max(length(ab),1e-3),u=dot(P-a2,ab)/(len*len);
 // Corner offsets can shift a bay along the projected axis by up to the band width.
 int q0=clamp((int)floor(u*bays),0,bays-1),mb=(int)ceil(band*bays/len)+1;
 [loop]for(uint t=0;t<4;t++)tube(c,P,m,t);
 [loop]for(uint f=0;f<4;f++)[loop]for(int q=max(q0-mb,0);q<=min(q0+mb,bays-1);q++)tube(c,P,m,4+f*15+(uint)q);
 if(length(P-a2)<band*1.5+2){[loop]for(uint e=64;e<68;e++)tube(c,P,m,e);}
 if(length(P-b2)<band*1.5+2){[loop]for(uint e=68;e<72;e++)tube(c,P,m,e);}}
void solid(inout float3 c,float2 P,uint s){SsSolid o=solidRec(s);uint kind=(uint)o.c.w%10;if(kind!=1)return;float k=quiet();
 uint mat=(uint)(o.c.w/10);float3 col=(mat==2?PT_DIM:PT_RULE)*k;
 [loop]for(uint e=0;e<12;e++){uint ax=e/4,j=e%4;float2 s0=float2(j&1?1:-1,j&2?1:-1);
  float3 A0,A1;if(ax==0){A0=float3(-1,s0.x,s0.y);A1=float3(1,s0.x,s0.y);}else if(ax==1){A0=float3(s0.x,-1,s0.y);A1=float3(s0.x,1,s0.y);}else{A0=float3(s0.x,s0.y,-1);A1=float3(s0.x,s0.y,1);}
  float3 p0=o.c.xyz+o.x.xyz*o.x.w*A0.x+o.y.xyz*o.y.w*A0.y+o.z.xyz*o.z.w*A0.z,p1=o.c.xyz+o.x.xyz*o.x.w*A1.x+o.y.xyz*o.y.w*A1.y+o.z.xyz*o.z.w*A1.z;
  over(c,col,ink(segDist(P,axo(p0),axo(p1)),1));}}
// A head: a stalk from its mount to a round body; a strobe: a bar along its tube; a pixel run: a thin bar its length.
void fixture(inout float3 c,float2 P,SsMark mk){
 uint slot=(uint)mk.fill.x,kind=(uint)mk.fill.y;bool hot=(int)slot==gHf;float k=hot?1.0:quiet();float r=mk.shape.y;
 float3 body=hot?PT_INK:PT_MID*k,edge=hot?PT_INK:PT_INK*.85*k;
 if(kind==0){over(c,edge,ink(segDist(P,mk.geo.xy,mk.geo.zw),1.4));float d=length(P-mk.geo.zw);
  over(c,body*.55,saturate(r-d));over(c,edge,ink(abs(d-r),1.2));}
 else{float d=segDist(P,mk.geo.xy,mk.geo.zw);over(c,body*(kind==1?.55:.8),saturate(r-d));over(c,edge,ink(abs(d-r),1.0));}}
[numthreads(8,8,1)]void main(uint3 id:SV_DispatchThreadID){
 uint W,H;OutputUAV.GetDimensions(W,H);if(id.x>=W||id.y>=H)return;float2 P=id.xy+.5;float3 c=IL_FIELD;gR=float2(W,H);
 gHm=(int)round(Hover[0].x);gHf=(int)round(Hover[0].z);
 if(P.y<axoHead(gR)){OutputUAV[id.xy]=float4(c,1);return;}   // the header strip: the kit draws the title and counts
 // floor grid lines, members (real tubes), solids, fixtures: in mark order, only this tile's marks
 uint base=ssmTileOf(P,gR)*SSM_PER_TILE,h=Bins[base];bool all_=(h>>31)!=0;uint count=all_?AM_MARKS:(h&0x7fffffffu);
 [loop]for(uint k=0;k<count;k++){uint idx=all_?k:Bins[base+1+k];SsMark mk=Marks[idx];uint kind=(uint)mk.shape.x;
  if(kind==SSM_HIDDEN)continue;
  if(kind==AM_MEMBER_KIND)member(c,P,mk);else if(kind==AM_SOLID_KIND)solid(c,P,(uint)mk.fill.x);
  else if(kind==AM_FIX_KIND)fixture(c,P,mk);else ssmDraw(c,P,mk);}
 OutputUAV[id.xy]=float4(c,1);
}
