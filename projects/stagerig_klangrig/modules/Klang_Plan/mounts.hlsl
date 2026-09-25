
#include "../_shared/rig.hlsli"
StructuredBuffer<RigRecord>R:register(t0);RWStructuredBuffer<MountRecord>M:register(u0);
[numthreads(64,1,1)]void main(uint3 id:SV_DispatchThreadID){uint f=id.x;if(f>=FIXTURES)return;bool spine=f<64||f>=256;uint wing=spine?0:1+(f-64)/16;uint local=f>=256?f-192:f<64?f:(f-64)%16;RigRecord r=R[wing==0?0:2+(wing-1)*4];uint count=(uint)r.shape.z;
 MountRecord m=(MountRecord)0;float t=((float)local+.5)/max(1,count);float3 a=r.a.xyz,b=r.b.xyz;
 m.position=lerp(a,b,t)+float3(0,-r.shape.x*.5-.04,0);m.fixture_id=f;m.mount_pitch=3.14159265;m.base_visible=1;m.active=local<count?1:0;m.content_origin=float2((float)f/288,0);m.content_extent=float2(1./288,1);m.reserved=float4(wing,r.meta.z,local,r.meta.w);M[f]=m;}
