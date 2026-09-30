// Group-button state, one thread group per button: (members, whole group selected, mounts ready).
// 256 threads each test one fixture slot; groupshared counters reduce them in parallel.
#include "lighting.hlsli"
StructuredBuffer<PhMount> Mounts:register(t0);
StructuredBuffer<float4> Sel:register(t1);
RWStructuredBuffer<float4> Groups:register(u0);
groupshared uint gMembers,gMissing;
[numthreads(256,1,1)]void main(uint3 gid:SV_GroupID,uint gi:SV_GroupIndex){uint g=gid.x;
 bool ok=_Data0_Count>=PH_SLOTS&&Sel[0].w==SEL_MAGIC;
 if(gi==0){gMembers=0;gMissing=0;}
 GroupMemoryBarrierWithGroupSync();
 if(ok&&gi<PH_SLOTS&&inGroup(g,Mounts[gi])){InterlockedAdd(gMembers,1);if(Sel[SEL_SLOT0+gi].x<.5)InterlockedAdd(gMissing,1);}
 GroupMemoryBarrierWithGroupSync();
 if(gi==0)Groups[g]=float4(gMembers,ok&&gMembers>0&&gMissing==0?1:0,ok?1:0,0);}
