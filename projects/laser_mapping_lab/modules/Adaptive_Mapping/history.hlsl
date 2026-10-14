// Adaptive_Mapping / history - feeds the canvas's records-out trace. It reads only the stats record
// and writes only its own ring (am_hist.hlsli); nothing it does reaches the Mapped Scan.
// _DeltaTime-correct and catch-up safe: the clock advances by the real frame time (clamped), a cook
// writes at most 8 samples, and a longer stall skips ahead rather than replaying.
#include "am_hist.hlsli"
StructuredBuffer<float4> St:register(t0);
RWStructuredBuffer<float4> H:register(u0);
[numthreads(1,1,1)]void main(uint3 tid:SV_DispatchThreadID){
 float4 h=H[0];
 // a persistent buffer can arrive with anything in it: start clean unless it is ours and finite
 if(h.w!=AM_HIST_MAGIC||!all(abs(h.xyz)<1e9)){[loop]for(uint k=1u;k<=AM_HIST_N;k++)H[k]=0;h=float4(0,0,0,AM_HIST_MAGIC);}
 float4 s0=St[0],s1=St[1],s2=St[2];
 float4 v=float4(s0.y,s1.w,s0.z,s2.y*1000.0);
 uint head=(uint)h.x%AM_HIST_N;float clock=h.y+clamp(_DeltaTime,0.0,0.1);float held=h.z;
 [loop]for(uint step=0u;step<8u&&clock>=AM_HIST_DT;step++){clock-=AM_HIST_DT;head=(head+1u)%AM_HIST_N;H[1u+head]=v;held=min(held+1.0,(float)AM_HIST_N);}
 H[0]=float4(head,min(clock,AM_HIST_DT),held,AM_HIST_MAGIC);
}
