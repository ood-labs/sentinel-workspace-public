#include "fruit_scene_types.hlsli"

struct ViewportPickResult { uint object_id; uint hit; float3 world_position; float3 world_normal; float distance; uint sub_element_id; };
StructuredBuffer<CardOverride> _Tex0 : register(t0);
RWStructuredBuffer<ViewportPickResult> OutputBuffer : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (_ViewportPickQuery.w == 0u) return;
    float2 query = float2(_ViewportPickRayOrigin.w, _ViewportPickRayDirection.w);
    float2 viewport = max(_Resolution.xy, 1.0.xx);
    float bestScore = 1e9;
    uint bestId = 0u;
    float3 bestPosition = 0.0;
    uint liveSlots = min(_Data0_Count, min((uint)slot_count, 64u));
    [loop] for (uint i = 0u; i < liveSlots; ++i) {
        _DataType_0 occ = _Data0[i];
        if (occ.occupied < 0.5) continue;
        uint slot = min((uint)round(occ.slot_index), max((uint)slot_count, 1u) - 1u);
        CardOverride edit = _Tex0[i];
        float life = fruitLife(i, occ.sequence, max(liveSlots, 1u));
        float3 position = fruitTrajectory(i, life, occ.age_rank) + edit.offset;
        float scale = fruitScale(slot, life, edit);
        float2 center = fruitProject(position);
        float2 edge = fruitProject(position + float3(scale * tile_width / max(tile_height, 1.0), 0.0, 0.0));
        float radiusPixels = max(14.0, length((edge - center) * viewport));
        float distancePixels = length((query - center) * viewport);
        if (distancePixels > radiusPixels) continue;
        float score = distancePixels / radiusPixels;
        if (score < bestScore) { bestScore = score; bestId = i + 1u; bestPosition = position; }
    }
    ViewportPickResult result = (ViewportPickResult)0;
    result.object_id = bestId;
    result.hit = bestId > 0u ? 1u : 0u;
    result.world_position = bestPosition;
    result.world_normal = normalize(_CameraPos - bestPosition);
    result.distance = result.hit != 0u ? length(_CameraPos - bestPosition) : -1.0;
    result.sub_element_id = 0xffffffffu;
    OutputBuffer[0] = result;
}
