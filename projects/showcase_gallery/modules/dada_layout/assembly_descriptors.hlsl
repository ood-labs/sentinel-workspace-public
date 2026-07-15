#include "dada_edit_types.hlsli"

StructuredBuffer<DadaPart> _Tex0 : register(t0);

struct ViewportObjectDescriptor {
    uint object_id; uint parent_id; float4x4 world_transform;
    float3 bounds_min; float3 bounds_max; float3 pivot;
    uint capability_flags; uint visible; uint selectable;
};
RWStructuredBuffer<ViewportObjectDescriptor> OutputBuffer : register(u0);

[numthreads(4, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint groupId = tid.x + 1u;
    float2 lo = 1e9.xx, hi = -1e9.xx;
    uint count = 0u;
    [loop] for (uint i = 0u; i < 29u; ++i) {
        DadaPart d = _Tex0[i];
        if (d.active < 0.5 || (uint)round(d.group) != groupId) continue;
        float r = max(max(d.sc_xy.x, d.sc_xy.y), 0.12);
        float2 uv = dadaWorldToUv(d.pos_xy);
        float2 uvRadius = float2(r / (DADA_W_MAX.x - DADA_W_MIN.x), r / (DADA_W_MAX.y - DADA_W_MIN.y));
        lo = min(lo, uv - uvRadius); hi = max(hi, uv + uvRadius); count++;
    }
    float2 center = (lo + hi) * 0.5;
    float2 halfSize = max((hi - lo) * 0.5, 0.035.xx);
    ViewportObjectDescriptor d = (ViewportObjectDescriptor)0;
    d.object_id = groupId;
    d.world_transform = float4x4(halfSize.x,0,0,0, 0,halfSize.y,0,0, 0,0,1,0, center.x,center.y,0,1);
    d.bounds_min = float3(-halfSize, -0.01);
    d.bounds_max = float3( halfSize,  0.01);
    d.pivot = float3(center, 0.0);
    d.capability_flags = 7u;
    d.visible = count > 0u ? 1u : 0u;
    d.selectable = d.visible;
    OutputBuffer[tid.x] = d;
}
