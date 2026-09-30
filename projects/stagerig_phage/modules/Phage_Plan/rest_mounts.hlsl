// Rest-pose fixture mounts, for the plan's own drawing (Kinetics poses the live ones).
StructuredBuffer<float4> E:register(t0);
#include "plan_design.hlsli"
#include "../_shared/phage_anatomy.hlsli"
RWStructuredBuffer<PhMount> M:register(u0);
[numthreads(64,1,1)]void main(uint3 id:SV_DispatchThreadID){uint s=id.x;if(s>=PH_SLOTS)return;PhDesign D=phLoad();M[s]=phMountFull(D,phRest(),s);}
