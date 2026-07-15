#include "label_edit_types.hlsli"

struct ViewportPickResult {
    uint object_id; uint hit; float3 world_position; float3 world_normal;
    float distance; uint sub_element_id;
};

StructuredBuffer<LabelRecord> _Tex0 : register(t0);
RWStructuredBuffer<ViewportPickResult> OutputBuffer : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (_ViewportPickQuery.w == 0u) return;
    float2 query = float2(_ViewportPickRayOrigin.w, _ViewportPickRayDirection.w);
    float2 viewport = max(_Resolution.xy, 1.0.xx);
    float best = 1e9;
    uint bestId = 0u;
    float2 bestPos = 0.0;
    uint count = min((uint)label_count, 12u);
    [loop] for (uint i = 0u; i < count; ++i) {
        LabelRecord L = _Tex0[i];
        if (L.active < 0.5) continue;
        float2 deltaPixels = abs(query - L.pos) * viewport;
        float2 halfSize = float2(70.0, 24.0) * max(L.scale, 0.5);
        if (deltaPixels.x <= halfSize.x && deltaPixels.y <= halfSize.y) {
            float score = length(deltaPixels / halfSize);
            if (score < best) { best = score; bestId = i + 1001u; bestPos = L.pos; }
        }
    }
    ViewportPickResult result = (ViewportPickResult)0;
    result.object_id = bestId;
    result.hit = bestId > 0u ? 1u : 0u;
    result.world_position = float3(bestPos, 0.0);
    result.world_normal = float3(0.0, 0.0, 1.0);
    result.distance = result.hit != 0u ? 0.0 : -1.0;
    result.sub_element_id = 0xffffffffu;
    OutputBuffer[0] = result;
}
