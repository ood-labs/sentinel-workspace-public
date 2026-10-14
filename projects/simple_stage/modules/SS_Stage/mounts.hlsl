// SS_Stage / mounts - every slot's fixture mount (SsMount): the plot's 26, and inactive slots a guest can take.
// The truss never moves, so a mount's rest is the mount itself.
#include "stage_types.hlsli"
#include "../_shared/ss_stage.hlsli"
RWStructuredBuffer<SsMount> O:register(u0);
[numthreads(64,1,1)]void main(uint3 id:SV_DispatchThreadID){uint s=id.x;if(s>=SS_SLOTS)return;
 float4 a=SS_MOUNT_DATA[s*5],b=SS_MOUNT_DATA[s*5+1],c=SS_MOUNT_DATA[s*5+2];SsMount m;
 m.position=a.xyz;m.fixture_id=a.w;m.up=b.xyz;m.kind=b.w;m.fwd=c.xyz;m.active=c.w;m.extra=SS_MOUNT_DATA[s*5+3];m.rest=SS_MOUNT_DATA[s*5+4];
 O[s]=m;}
