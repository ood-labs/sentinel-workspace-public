// The stage as world-space line segments for the club drawing, copied on one thread from the outline tools/ss_stage.py
// generates (ss_stage.hlsli SS_OUTLINE), so the per-pixel preview never loops the stage tables and the drawing follows
// whatever the plot is. V[0]=(rig top, rig top, segments, magic) V[1]=(front truss height, the structure's half depth,
// -, -). Segment k: V[2+2k]=(a, style) V[3+2k]=(b, view); view 0 plan, 1 section; style 0 ink, 1 mid, 2 dim.
#include "venue_view.hlsli"
RWStructuredBuffer<float4> V:register(u0);
#define SEGS 128
static uint gN;
void seg(float3 a,float3 b,float style,float view){if(gN>=SEGS)return;V[2+2*gN]=float4(a,style);V[3+2*gN]=float4(b,view);gN++;}
[numthreads(1,1,1)]void main(uint3 id:SV_DispatchThreadID){
 gN=0;
 // the outline's plan (1) and section (2) views; its styles: 0 truss (ink), 1 the deck and the booth (dim), 2 hoists
 // and chains (mid)
 [loop]for(uint k=0;k<(uint)SS_OUTLINE_N;k++){float4 a=SS_OUTLINE[2*k],b=SS_OUTLINE[2*k+1];uint view=(uint)round(b.w);
  if(view==0)continue;uint st=(uint)round(a.w);seg(a.xyz,b.xyz,st==0?0:(st==1?2:1),view-1);}
 float top=SS_BOUNDS.y;
 V[0]=float4(top,top,gN,260932);V[1]=float4(SS_TRUSS_Y,SS_BOUNDS.z,0,0);
}
