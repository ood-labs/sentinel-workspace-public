// Still Life / descriptors - what the HOST knows about each object: id, world transform, local
// bounds, pivot, and whether it is visible and selectable (viewport.selection.object_buffer).
// One thread per record; empty slots publish invisible and unselectable.
#include "../_shared/ui/il_core.hlsli"

#define SL_RECORD_ONLY
#include "still.hlsli"
#undef SL_RECORD_ONLY
StructuredBuffer<SlObject> Objs : register(t0);
#define SL_OBJECTS Objs
#include "still.hlsli"

struct ViewportObjectDescriptor
{
    uint object_id; uint parent_id;
    float4x4 world_transform;            // rows: the rotated basis, then the translation (row-vector convention)
    float3 bounds_min; float3 bounds_max; float3 pivot;
    uint capability_flags; uint visible; uint selectable;
};
RWStructuredBuffer<ViewportObjectDescriptor> OutputBuffer : register(u0);

[numthreads(SL_MAX, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint i = tid.x;
    if (i >= SL_MAX) return;
    SlObject o = Objs[i + 1u];
    bool live = o.kind != K_EMPTY && Objs[0].id == SL_MAGIC;
    float3 bx = qRot(o.rot, float3(1.0, 0.0, 0.0)) * o.scale;
    float3 by = qRot(o.rot, float3(0.0, 1.0, 0.0)) * o.scale;
    float3 bz = qRot(o.rot, float3(0.0, 0.0, 1.0)) * o.scale;
    ViewportObjectDescriptor d;
    d.object_id = live ? o.id : 0u;
    d.parent_id = 0u;
    d.world_transform = float4x4(bx.x, bx.y, bx.z, 0.0, by.x, by.y, by.z, 0.0, bz.x, bz.y, bz.z, 0.0, o.pos.x, o.pos.y, o.pos.z, 1.0);
    float3 b = slBounds(o.kind);
    d.bounds_min = -b;
    d.bounds_max = b;
    d.pivot = o.pos;
    d.capability_flags = 3u;              // translate | rotate
    d.visible = live ? 1u : 0u;
    d.selectable = d.visible;
    OutputBuffer[i] = d;
}
