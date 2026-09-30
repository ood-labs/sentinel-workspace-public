// Rest-pose pixel-bar pieces: two records per piece (a.xyz+valid, b.xyz+family).
StructuredBuffer<float4> E:register(t0);
#include "plan_design.hlsli"
#include "../_shared/phage_anatomy.hlsli"
RWStructuredBuffer<float4> Q:register(u0);
[numthreads(64,1,1)]void main(uint3 id:SV_DispatchThreadID){uint i=id.x;if(i>=PH_BARS*PH_BAR_SEGS)return;uint b=i/PH_BAR_SEGS,k=i%PH_BAR_SEGS;
 PhDesign D=phLoad();float3 a=0,c=0,n=0;bool ok=k<phBarSegCount(b);if(ok)phBarPiece(D,phRest(),b,k,a,c,n);
 Q[i*2]=float4(a,ok?1:0);Q[i*2+1]=float4(c,phBarFamily(b));}
