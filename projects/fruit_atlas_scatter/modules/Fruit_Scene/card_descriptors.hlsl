#include "fruit_scene_types.hlsli"

StructuredBuffer<CardOverride> _Tex0 : register(t0);
struct ViewportObjectDescriptor {
    uint object_id; uint parent_id; float4x4 world_transform;
    float3 bounds_min; float3 bounds_max; float3 pivot;
    uint capability_flags; uint visible; uint selectable;
};
RWStructuredBuffer<ViewportObjectDescriptor> OutputBuffer : register(u0);

[numthreads(16, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint i = tid.x;
    if (i >= 64u) return;
    uint liveSlots = min(_Data0_Count, min((uint)slot_count, 64u));
    bool visible = i < liveSlots;
    uint slot = i;
    float sequence = (float)i;
    float ageRank = (float)i;
    if (visible) {
        _DataType_0 occ = _Data0[i];
        visible = occ.occupied > 0.5;
        slot = min((uint)round(occ.slot_index), max((uint)slot_count, 1u) - 1u);
        sequence = occ.sequence;
        ageRank = occ.age_rank;
    }
    CardOverride edit = _Tex0[i];
    float life = fruitLife(i, sequence, max(liveSlots, 1u));
    float3 position = fruitTrajectory(i, life, ageRank) + edit.offset;
    float scale = fruitScale(slot, life, edit);
    float cs = cos(edit.rotation), sn = sin(edit.rotation);

    ViewportObjectDescriptor d = (ViewportObjectDescriptor)0;
    d.object_id = i + 1u;
    d.parent_id = 0u;
    d.world_transform = float4x4(cs * scale, sn * scale, 0, 0, -sn * scale, cs * scale, 0, 0, 0, 0, scale, 0, position.x, position.y, position.z, 1);
    float aspect = tile_width / max(tile_height, 1.0);
    d.bounds_min = float3(-aspect * scale, -scale, -0.08);
    d.bounds_max = float3( aspect * scale,  scale,  0.08);
    d.pivot = position;
    d.capability_flags = 7u;
    d.visible = visible ? 1u : 0u;
    d.selectable = d.visible;
    OutputBuffer[i] = d;
}
