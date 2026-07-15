#include "node_edit_types.hlsli"

struct ViewportPickResult {
    uint object_id; uint hit; float3 world_position; float3 world_normal;
    float distance; uint sub_element_id;
};

StructuredBuffer<NodeRecord> _Tex0 : register(t0);
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
    uint count = min((uint)node_count, 12u);
    [loop] for (uint i = 0u; i < count; ++i) {
        NodeRecord n = _Tex0[i];
        if (n.active < 0.5) continue;
        float radiusPixels = max(20.0, n.radius * viewport.y * 1.8);
        float distPixels = length((query - n.pos) * viewport);
        if (distPixels <= radiusPixels && distPixels / radiusPixels < best) {
            best = distPixels / radiusPixels;
            bestId = i + 1u;
            bestPos = n.pos;
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
