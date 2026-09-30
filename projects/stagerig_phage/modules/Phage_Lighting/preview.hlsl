// Fixture canvas: every live fixture in a front elevation and a plan, drawn where it is right now.
// Movers are rings filled with their live beam colour, strobes short tubes in their plate colour,
// pixel bars their real pieces, kinetic axes diamonds. The selection is the only accent; a button
// is outlined when its whole group is selected (groups.hlsl). Fixtures arrive as projected marks
// (marks.hlsl), and each pixel visits only its tile's marks (bins.hlsl).
#include "lighting.hlsli"
StructuredBuffer<float4> Sel:register(t2);
StructuredBuffer<float4> Show:register(t4);
StructuredBuffer<float4> Groups:register(t3);
RWTexture2D<float4>OutputUAV:register(u0);
#include "../_shared/plan_theme.hlsli"
#include "../_shared/ui/sui3_core.hlsli"
#include "../_shared/ui/sui3_text.hlsli"
#include "labels.hlsli"
#include "../_shared/ph_marks.hlsli"
StructuredBuffer<PhMark> Marks:register(t0);
StructuredBuffer<uint> Bins:register(t1);
#define PHM_MARKS_BUF Marks
#define PHM_BINS_BUF Bins
#define PHM_MARKS 2032
#include "../_shared/ph_marks.hlsli"
void over(inout float3 c,float3 k,float a){c=lerp(c,k,saturate(a));}
float ink(float d,float w){return saturate(w*.5+.5-d);}
#include "../_shared/ph_textq.hlsli"
[numthreads(8,8,1)]void main(uint3 id:SV_DispatchThreadID){uint W,H;OutputUAV.GetDimensions(W,H);if(id.x>=W||id.y>=H)return;
 float2 P=id.xy+.5,R=float2(W,H);float3 c=PT_FIELD;gTN=0;gTP=P;
 bool ok=Groups[0].z>.5;float ts=R.x>=1500?1.5:1;
 txt(float2(.012*R.x,.004*R.y+2),ts,0,PT_INK);
 if(P.y<.16*R.y){
  [loop]for(uint b=0;b<GROUPS;b++){float4 r=buttonRect(b,R);if(any(P<r.xy)||any(P>r.zw))continue;
   bool on=ok&&Groups[b].y>.5;c=PT_WELL;over(c,on?PT_ACCENT:PT_RULE,sui3Frame(P,r));
   txt(float2(r.x+8,(r.y+r.w)*.5-4*ts),ts,1+b,on?PT_INK:PT_MID);break;}
 }else if(P.y<.935*R.y){
  if(!ok){txt(float2(.012*R.x,.2*R.y),ts,25,PT_DIM);}
  else{[loop]for(uint v=0;v<2;v++){float4 vr=viewRect(v,R);if(any(P<vr.xy-2)||any(P>vr.zw+2))continue;
   over(c,PT_RULE,sui3Frame(P,vr));txt(vr.xy+float2(8,8),ts,17+v,PT_DIM);float s=viewScale(v,R);
   if(v==0)over(c,PT_RULE,ink(abs(P.y-toView(0,float3(0,0,0),R).y),1));
   else{float2 o=toView(1,float3(0,0,0),R);float2 g=abs(frac((P-o)/(5*s)+.5)-.5)*5*s;over(c,PT_GRID,ink(min(g.x,g.y),1)*.6);}
   phmDrawTile(c,P,R,v+1);
   if(Sel[0].x>.5&&(uint)Sel[0].z==v&&length(Sel[1].xy-Sel[1].zw)>3){float4 dr=float4(min(Sel[1].xy,Sel[1].zw),max(Sel[1].xy,Sel[1].zw));
    over(c,PT_ACCENT,sui3Frame(P,dr));if(all(P>=dr.xy)&&all(P<=dr.zw))c=lerp(c,PT_ACCENT,.06);}
  }}
 }else{
  txt(float2(.012*R.x,.95*R.y),ts,20,PT_DIM);
  if(ok){float x=.72*R.x;txt(float2(x,.95*R.y),ts,19,PT_DIM);num(float2(x+phLabelWidth(19,ts)+8,.95*R.y),ts,Sel[3].x,PT_INK,3);
   bool prog=_Data1_Count>=PH_SHOW_COUNT&&Show[2].x>.5;txt(float2(.86*R.x,.95*R.y),ts,prog?21:22,PT_MID);
   if(highlight)txt(float2(.94*R.x,.95*R.y),ts,23,PT_INK);else if(solo_selected)txt(float2(.94*R.x,.95*R.y),ts,24,PT_INK);}
 }
 phDrawText(c);
 OutputUAV[id.xy]=float4(c,1);}
