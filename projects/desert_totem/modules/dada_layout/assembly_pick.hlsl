#include "dada_edit_types.hlsli"

struct ViewportPickResult {
    uint object_id; uint hit; float3 world_position; float3 world_normal;
    float distance; uint sub_element_id;
};
StructuredBuffer<DadaPart> _Tex0 : register(t0);
RWStructuredBuffer<ViewportPickResult> OutputBuffer : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (_ViewportPickQuery.w == 0u) return;
    float2 query = float2(_ViewportPickRayOrigin.w, _ViewportPickRayDirection.w);
    float best = 1e9;
    uint bestId = 0u;
    float2 bestPos = 0.0;
    [unroll] for (uint groupId = 1u; groupId <= 4u; ++groupId) {
        float2 lo = 1e9.xx, hi = -1e9.xx;
        [loop] for (uint i = 0u; i < 29u; ++i) {
            DadaPart d = _Tex0[i];
            if (d.active < 0.5 || (uint)round(d.group) != groupId) continue;
            float r = max(max(d.sc_xy.x, d.sc_xy.y), 0.12);
            float2 uv = dadaWorldToUv(d.pos_xy);
            float2 uvRadius = float2(r / (DADA_W_MAX.x - DADA_W_MIN.x), r / (DADA_W_MAX.y - DADA_W_MIN.y));
            lo = min(lo, uv - uvRadius); hi = max(hi, uv + uvRadius);
        }
        float2 margin = 12.0 / max(_Resolution.xy, 1.0.xx);
        lo -= margin; hi += margin;
        bool inside = all(query >= lo) && all(query <= hi);
        float area = max((hi.x - lo.x) * (hi.y - lo.y), 1e-5);
        if (inside && area < best) { best = area; bestId = groupId; bestPos = (lo + hi) * 0.5; }
    }
    ViewportPickResult result = (ViewportPickResult)0;
    result.object_id = bestId; result.hit = bestId > 0u ? 1u : 0u;
    result.world_position = float3(bestPos, 0.0);
    result.world_normal = float3(0.0, 0.0, 1.0);
    result.distance = result.hit != 0u ? 0.0 : -1.0;
    result.sub_element_id = 0xffffffffu;
    OutputBuffer[0] = result;
}
