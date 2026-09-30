// Show monitor: five lanes as 48-cell chase strips (what a chase with width .5 / spread .45 on that
// lane would do across the rig right now), each lane's phase cursor and trigger count, the build ramp,
// palettes in their own colour, strobe gate, and which source is driving the rig.
#include "../_shared/phage_show.hlsli"
StructuredBuffer<float4>S:register(t0);
RWTexture2D<float4>OutputUAV:register(u0);
#include "../_shared/plan_theme.hlsli"
#include "../_shared/ui/sui3_core.hlsli"
#include "../_shared/ui/sui3_text.hlsli"
#include "labels.hlsli"
void over(inout float3 c,float3 k,float a){c=lerp(c,k,saturate(a));}
#include "../_shared/ph_textq.hlsli"
[numthreads(8,8,1)]void main(uint3 id:SV_DispatchThreadID){uint W,H;OutputUAV.GetDimensions(W,H);if(id.x>=W||id.y>=H)return;
 float2 P=id.xy+.5;float3 c=PT_FIELD;gTN=0;gTP=P;bool ok=S[2].w==260934;
 float4 s2=S[2];bool prog=s2.x>.5;float beatNow=s2.y;
 if(P.y<40){
  txt(float2(14,11),2,0,PT_INK);
  // bpm + four beat lamps (the current beat is the live reading)
  float x=W-330;txt(float2(x,15),1,6,PT_DIM);num(float2(x+30,11),2,s2.z,PT_INK,3);
  uint cur=(uint)floor(beatNow)%4;[loop]for(uint k=0;k<4;k++){float4 r=float4(W-150+k*30,12,W-128+k*30,28);
   over(c,k==cur&&S[12].w>.5?PT_ACCENT:PT_RULE,sui3RectIn(P,r)*(k==cur?1:.6));}
  txt(float2(W-150,31),1,S[12].w>.5?7:23,PT_DIM);
 }else if(P.y<370){
  // lanes
  uint lane=(uint)((P.y-44)/64);float y0=44+lane*64.0;
  if(lane<5&&ok){float4 l=S[3+lane];float2 q=P-float2(0,y0);
   txt(float2(18,y0+10),1,1+lane,PT_DIM);
   over(c,l.y>.001?PT_INK:PT_RULE,sui3Disc(P,float2(24,y0+36),5)*(l.y>.001?max(.35,lane==3?l.y:1):1));
   float x0=130,x1=W-120,cw=(x1-x0)/48;
   if(P.x>=x0&&P.x<x1&&q.y>=18&&q.y<=50){uint cell=(uint)((P.x-x0)/cw);float rank=(cell+.5)/48;
    float v=(lane==3?l.y:1)*phPulse(l.x,rank,.5,.45)*(l.y>.001?1:0);
    float inCell=step(1,P.x-x0-cell*cw)*step(P.x-x0-cell*cw,cw-2);
    c=lerp(c,lerp(PT_WELL,PT_INK,v),inCell);}
   // phase cursor (a live reading) and, for BUILD, the ramp under the strip
   float px=lerp(x0,x1,saturate(l.x));if(q.y>=14&&q.y<=54)over(c,PT_ACCENT,sui3Hair(abs(P.x-px))*(l.y>.001?1:.3));
   if(lane==3){over(c,PT_RULE,sui3Frame(P,float4(x0,y0+55,x1,y0+60)));over(c,PT_MID,sui3RectIn(P,float4(x0,y0+56,lerp(x0,x1,l.y),y0+59)));}
   num(float2(W-100,y0+26),1,fmod(l.z,100000),PT_MID,5);
  }
 }else{
  // palettes / strobe / source
  float y0=390;
  txt(float2(18,y0),1,8,PT_DIM);
  [loop]for(uint k=0;k<3;k++){float4 r=float4(18+k*96,y0+22,98+k*96,y0+102);float3 col=S[8+k].rgb;
   over(c,ptSampleFill(col),sui3RectIn(P,r));over(c,PT_RULE,sui3Frame(P,r));txt(float2(r.x,y0+110),1,9+k,PT_DIM);}
  float x=350;txt(float2(x,y0),1,12,PT_DIM);
  float4 s11=S[11],s12=S[12];
  num(float2(x,y0+22),2,s12.x,PT_INK,-1);txt(float2(x+sui3FixedWidth(2,1)+8,y0+30),1,21,PT_DIM);
  txt(float2(x,y0+60),1,22,PT_DIM);num(float2(x+50,y0+56),1,s12.y,PT_INK,-1);
  over(c,s11.y>.5?PT_INK:PT_RULE,sui3RectIn(P,float4(x+200,y0+22,x+240,y0+50))*(s11.y>.5?1:.5));
  if(s11.x>.5)txt(float2(x+200,y0+60),1,18,PT_INK);
  if(s11.z>.5)txt(float2(x,y0+90),2,13,PT_INK);
  float x2=720;txt(float2(x2,y0),1,prog?14:15,PT_DIM);
  txt(float2(x2,y0+26),2,prog?14:(S[0].y>.5?15:24),PT_INK);
  txt(float2(x2,y0+62),1,16,PT_DIM);txt(float2(x2+90,y0+62),1,s12.z>.5?(prog?14:24):24,s12.z>.5?PT_INK:PT_DIM);
  txt(float2(x2,y0+90),1,S[1].w>.5?19:20,PT_DIM);
 }
 phDrawText(c);
 OutputUAV[id.xy]=float4(c,1);}
