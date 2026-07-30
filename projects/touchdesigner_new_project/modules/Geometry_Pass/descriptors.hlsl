#include "types.hlsli"
StructuredBuffer<SceneObject> _Tex0:register(t0);
struct ViewportObjectDescriptor{uint object_id;uint parent_id;float4x4 world_transform;float3 bounds_min;float3 bounds_max;float3 pivot;uint capability_flags;uint visible;uint selectable;};
RWStructuredBuffer<ViewportObjectDescriptor> OutputBuffer:register(u0);
[numthreads(16,1,1)]void main(uint3 tid:SV_DispatchThreadID){uint i=tid.x;if(i>=16u)return;SceneObject o=_Tex0[i];float3x3 r=labRotation(o.rotation);ViewportObjectDescriptor d;d.object_id=o.object_id;d.parent_id=0;d.world_transform=float4x4(r[0].x,r[0].y,r[0].z,0,r[1].x,r[1].y,r[1].z,0,r[2].x,r[2].y,r[2].z,0,o.position.x,o.position.y,o.position.z,1);d.bounds_min=-o.scale;d.bounds_max=o.scale;d.pivot=o.position;d.capability_flags=7u;d.visible=o.object_id>0u?1u:0u;d.selectable=d.visible;OutputBuffer[i]=d;}
