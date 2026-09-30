// Motion-control monitor: live plan, live front elevation, and one meter row per axis
// (position bar, target tick, velocity). Rest pose ghosted underneath. Legs and members arrive as
// projected marks (marks.hlsl) drawn through tile bins.
StructuredBuffer<float4> DesignIn:register(t0);
StructuredBuffer<float4> A:register(t1);
float4 phD(uint i){return DesignIn[i];}
#include "../_shared/phage_anatomy.hlsli"
#include "kin_common.hlsli"
StructuredBuffer<PhMember> Mem:register(t2);
RWTexture2D<float4> OutputUAV:register(u0);
#include "../_shared/plan_theme.hlsli"
#include "../_shared/ui/sui3_core.hlsli"
#include "../_shared/ui/sui3_text.hlsli"
#include "labels.hlsli"
#include "../_shared/ph_marks.hlsli"
#include "kin_view.hlsli"
StructuredBuffer<PhMark> Marks:register(t3);
StructuredBuffer<uint> Bins:register(t4);
#define PHM_MARKS_BUF Marks
#define PHM_BINS_BUF Bins
#define PHM_MARKS KM_MARKS
#include "../_shared/ph_marks.hlsli"
float ink(float d,float w){return saturate(w*.5+.5-d);}
float segDist(float2 p,float2 a,float2 b){float2 d=b-a;return length(p-a-d*saturate(dot(p-a,d)/max(dot(d,d),1e-5)));}
void over(inout float3 c,float3 k,float a){c=lerp(c,k,saturate(a));}
bool inRect(float2 p,float4 r){return p.x>=r.x&&p.x<=r.z&&p.y>=r.y&&p.y<=r.w;}
float2 axisRange(uint k,uint c){if(k==0)return c==0?float2(-2.4,2.0):float2(-30,30);if(k==1)return c==0?float2(0,360):float2(-1.2,2.4);return c==0?float2(-2.5,2.5):float2(0,4.5);}
float limits_hint(uint k,uint c){return k==0?(c==0?1.0:14.0):k==1?(c==0?120.0:1.4):(c==0?2.6:3.8);}
uint axisLabel(uint k,uint c){return k==0?(c==0?4:5):k==1?(c==0?6:7):(c==0?9:8);}

[numthreads(8,8,1)]void main(uint3 id:SV_DispatchThreadID){
 uint W,H;OutputUAV.GetDimensions(W,H);if(id.x>=W||id.y>=H)return;float2 P=id.xy+.5;float3 c=PT_FIELD;
 bool ok=_Data0_Count>=17&&DesignIn[16].w==260929;
 float head=38,split=H*.6;
 if(P.y<head){over(c,PT_INK,phLabel(P,float2(14,8),2,0));uint mode=(uint)A[24].y;uint lab=mode==0?12:mode==1?18:mode==2?19:13;
  over(c,mode==0?PT_ACCENT:PT_INK,phLabel(P,float2(W-14-phLabelWidth(lab,1),14),1,lab));c+=PT_RULE*sui3HairAt(P.y,head-4)*.6;}
 if(!ok){OutputUAV[id.xy]=float4(c,1);return;}
 float2 RS=float2(W,H);float4 pr=kvPlanRect(RS),er=kvElevRect(RS);
 if(inRect(P,pr)){
  float s=min((pr.z-pr.x)/44,(pr.w-pr.y-20)/44);float2 o=(pr.xy+pr.zw)*.5+float2(0,8);
  c+=PT_RULE*sui3Frame(P,sui3SnapRect(pr))*.8;over(c,PT_DIM,phLabel(P,pr.xy+float2(8,6),1,21));
  float2 q=(P-o)/s,G=abs(frac(q/5+.5)-.5)*5*s;c+=PT_GRID*ink(min(G.x,G.y),1)*.8;
  phmDrawTile(c,P,RS,1);
 }
 if(inRect(P,er)){
  float s=min((er.z-er.x)/40,(er.w-er.y-24)/24);float2 o=float2((er.x+er.z)*.5,er.w-12);
  c+=PT_RULE*sui3Frame(P,sui3SnapRect(er))*.8;over(c,PT_DIM,phLabel(P,er.xy+float2(8,6),1,20));
  over(c,PT_MID,ink(abs(P.y-o.y),1.4));
  float2 q=(P-o)/s,G=abs(frac(q/5+.5)-.5)*5*s;c+=PT_GRID*ink(min(G.x,G.y),1)*.8;
  phmDrawTile(c,P,RS,2);
 }
 // axis meters
 if(P.y>split+8){
  float rowH=(H-split-16)/8.0;uint k=min(7u,(uint)((P.y-split-8)/rowH));float y0=split+8+k*rowH,yc=y0+rowH*.5;
  float lx=14;uint name=k==0?1:k==1?2:3;over(c,PT_INK,phLabel(P,float2(lx,yc-6),1,name));
  if(k>=2)over(c,PT_INK,sui3Digits(P,float2(lx+phLabelWidth(3,1)+7,yc-6),1,(int)k-1,1));
  float4 s0=A[3*k],s1=A[3*k+1];
  for(uint cc=0;cc<2;cc++){
   float x0=W*(cc==0?.13:.57),x1=W*(cc==0?.53:.97);float2 rg=axisRange(k,cc);
   over(c,PT_DIM,phLabel(P,float2(x0,y0+2),1,axisLabel(k,cc)));
   float pos=cc==0?s0.x:s0.y,tgt=cc==0?s1.x:s1.y,vel=cc==0?s0.z:s0.w;
   if(k==1&&cc==0){pos=frac(pos/360)*360;tgt=frac(tgt/360)*360;}
   float ty=yc+3,tx0=x0,tx1=x1-70;float u=saturate((pos-rg.x)/(rg.y-rg.x)),ut=saturate((tgt-rg.x)/(rg.y-rg.x)),uz=saturate((0-rg.x)/(rg.y-rg.x));
   float px=lerp(tx0,tx1,u),pt=lerp(tx0,tx1,ut),pz=lerp(tx0,tx1,uz);
   c+=PT_RULE*ink(segDist(P,float2(tx0,ty),float2(tx1,ty)),1);
   c+=PT_DIM*ink(segDist(P,float2(pz,ty-5),float2(pz,ty+5)),1);
   over(c,PT_MID,step(min(pz,px),P.x)*step(P.x,max(pz,px))*step(abs(P.y-ty),2.5));
   over(c,PT_INK,ink(segDist(P,float2(pt,ty-7),float2(pt,ty+7)),1.5));
   over(c,PT_ACCENT,saturate(3.5-length(P-float2(px,ty))));
   float vn=saturate(abs(vel)/max(1e-3,limits_hint(k,cc)));c+=PT_DIM*step(abs(P.y-(ty+8)),1)*step(tx0,P.x)*step(P.x,tx0+vn*(tx1-tx0)*.3);
   over(c,PT_INK,sui3Fixed(P,float2(x1-62,yc-6),1,pos,1));
  }
  c+=PT_GRID*sui3HairAt(P.y,y0+rowH)*.9;
 }
 OutputUAV[id.xy]=float4(c,1);
}
