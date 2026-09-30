// Pixel-bar monitor: every live bar as one strip of its real pixels (inset colour), grouped by where it
// hangs on the phage, with the LOOK each bar is running. The raw texture goes to the renderer.
#include "../_shared/phage_slots.hlsli"
#include "../_shared/phage_show.hlsli"
StructuredBuffer<float4> Show:register(t1);
StructuredBuffer<PhProgram> Program:register(t2);
StructuredBuffer<PhMount> Mounts:register(t3);
RWTexture2D<float4> OutputUAV:register(u0);
#include "../_shared/plan_theme.hlsli"
#include "../_shared/ui/sui3_core.hlsli"
#include "../_shared/ui/sui3_text.hlsli"
#include "labels.hlsli"
void over(inout float3 c,float3 k,float a){c=lerp(c,k,saturate(a));}
#include "../_shared/ph_textq.hlsli"
uint famOf(uint b){return b<24?0:b<30?1:b<35?2:b<37?3:b<46?4:5;}
float rowY(uint b){return 46+b*12.0+famOf(b)*10.0;}
[numthreads(8,8,1)]void main(uint3 id:SV_DispatchThreadID){uint W,H;OutputUAV.GetDimensions(W,H);if(id.x>=W||id.y>=H)return;
 float2 P=id.xy+.5;float3 c=PT_FIELD;gTN=0;gTP=P;bool ok=_Data2_Count>=PH_SLOTS&&_Data0_Count>=PH_SHOW_COUNT;
 bool prog=ok&&_Data1_Count>=PH_SLOTS&&Show[2].x>.5;float peak=max(1e-3,(ok?Show[1].z:1)*level);
 uint tw,th;_Tex0.GetDimensions(tw,th);float x0=150,x1=W-190;
 if(P.y<38){txt(float2(14,11),2,0,PT_INK);txt(float2(W-300,15),1,prog?23:24,PT_MID);
  if(ok&&P.x>W-150){uint lit=0;[loop]for(uint b=0;b<47;b++){float e=0;[loop]for(uint k=0;k<8;k++)e+=dot(_Tex0.SampleLevel(PointSampler,float2((k+.5)/8,(b+.5)/th),0).rgb,1);if(e>.02)lit++;}
   txt(float2(W-140,15),1,25,PT_DIM);num(float2(W-100,15),1,lit,PT_INK,2);}}
 else if(ok){
  uint b=99;[loop]for(uint k=0;k<47;k++){float y=rowY(k);if(P.y>=y&&P.y<y+12){b=k;break;}}
  if(b<47){float y=rowY(b);PhMount m=Mounts[PH_BAR0+b];
   if(b==0||famOf(b)!=famOf(b-1))txt(float2(18,y+1),1,1+famOf(b),PT_DIM);
   if(m.active>.5&&P.y<y+9){
    if(P.x>=x0&&P.x<x1){float u=(P.x-x0)/(x1-x0);float3 rgb=_Tex0.SampleLevel(PointSampler,float2(u,(b+.5)/th),0).rgb;
     c=lerp(PT_WELL,ptInset(saturate(rgb/peak)),saturate(dot(rgb/peak,1)*4));}
    over(c,PT_RULE,sui3Frame(P,float4(x0-1,y-1,x1+1,y+9)));
    if(prog)txt(float2(x1+14,y+1),1,7+min(15u,(uint)round(Program[PH_BAR0+b].timing.w)),PT_DIM);}}
 }
 phDrawText(c);
 OutputUAV[id.xy]=float4(c,1);}
