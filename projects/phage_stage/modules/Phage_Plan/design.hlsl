// Publishes the Design records every downstream node builds from.
StructuredBuffer<float4> E:register(t0);
RWStructuredBuffer<float4> Design:register(u0);
#include "plan_design.hlsli"
[numthreads(1,1,1)]void main(uint3 id:SV_DispatchThreadID){for(uint i=0;i<20;i++)Design[i]=phD(i);}
