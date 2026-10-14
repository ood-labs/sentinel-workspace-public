// One line emitter per pixel-run piece, so the battens light the truss, the floor and the crowd: each averages the
// live LED texture (one row per run, u along the whole run) over its piece's u range.
#include "../_shared/ss_venue.hlsli"
#include "../_shared/ss_layout.hlsli"
struct SsPiece{float4 a;float4 b;float4 n;float4 w;};
StructuredBuffer<SsPiece> Q:register(t0);
Texture2D<float4> LED:register(t1);
struct Emitter{float4 a,b,radiance;};RWStructuredBuffer<Emitter> O:register(u0);
[numthreads(64,1,1)]void main(uint3 id:SV_DispatchThreadID){uint e=id.x;if(e>=PV_EMITTERS)return;Emitter o=(Emitter)0;
 if(e<SS_BARS*SS_BAR_SEGS&&e<_Data0_Count){SsPiece q=Q[e];if(q.w.z>.5){float3 r=0;uint run=(uint)round(q.n.w);
  uint lw,lh;LED.GetDimensions(lw,lh);[unroll]for(uint s=0;s<8;s++){float u=lerp(q.a.w,q.b.w,(s+.5)/8);r+=LED.SampleLevel(LinearSampler,float2(u,(run+.5)/max(1,lh)),0).rgb/8;}
  o.a=float4(q.a.xyz+q.n.xyz*.05,.08);o.b=float4(q.b.xyz+q.n.xyz*.05,1);o.radiance=float4(r,1);}}
 O[e]=o;}
