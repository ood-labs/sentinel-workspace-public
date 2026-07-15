#include "node_edit_types.hlsli"

StructuredBuffer<NodeRecord> _Tex0 : register(t0);

struct ViewportObjectDescriptor {
    uint object_id; uint parent_id; float4x4 world_transform;
    float3 bounds_min; float3 bounds_max; float3 pivot;
    uint capability_flags; uint visible; uint selectable;
};

RWStructuredBuffer<ViewportObjectDescriptor> OutputBuffer : register(u0);

[numthreads(12, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint i = tid.x;
    if (i >= 12u) return;
    NodeRecord n = _Tex0[i];
    bool visible = i < (uint)node_count && n.active > 0.5;
    float r = max(n.radius, 0.018);
    ViewportObjectDescriptor d = (ViewportObjectDescriptor)0;
    d.object_id = i + 1u;
    d.world_transform = float4x4(r,0,0,0, 0,r,0,0, 0,0,1,0, n.pos.x,n.pos.y,0,1);
    d.bounds_min = float3(-r, -r, -0.01);
    d.bounds_max = float3( r,  r,  0.01);
    d.pivot = float3(n.pos, 0.0);
    d.capability_flags = 1u;
    d.visible = visible ? 1u : 0u;
    d.selectable = d.visible;
    OutputBuffer[i] = d;
}
