// Survey-label editor preview with bounded selectable label boxes.

#include "label_edit_types.hlsli"

StructuredBuffer<LabelRecord> Labels : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float3 col = float3(0.003, 0.010, 0.014);
    float2 grid = abs(frac(uv * float2(24.0, 14.0)) - 0.5);
    col += float3(0.015, 0.070, 0.082) * (1.0 - smoothstep(0.485, 0.498, max(grid.x, grid.y)));

    [loop] for (uint i = 0u; i < 48u; i++) {
        LabelRecord L = Labels[i];
        if (L.active < 0.5) continue;
        float2 dp = (uv - L.pos) * _Resolution.xy;
        float2 halfSize = float2(62.0, 18.0) * max(L.scale, 0.5);
        float2 edge = abs(dp) - halfSize;
        float boxDistance = max(edge.x, edge.y);
        float box = 1.0 - smoothstep(0.0, 1.6, abs(boxDistance));
        float tick = (1.0 - smoothstep(0.0, 1.4, abs(dp.y))) * step(abs(dp.x), halfSize.x * 0.72);
        bool priority = i < 12u;
        bool selected = _ViewportSelectionMeta.y == i + 1001u;
        float3 tint = selected ? float3(1.0, 0.46, 0.08) : (priority ? float3(0.10, 0.72, 0.84) : float3(0.16, 0.32, 0.36));
        col = lerp(col, tint, saturate(box * (priority ? 1.0 : 0.35) + tick * 0.30));
    }
    OutputUAV[pixel] = float4(saturate(col), 1.0);
}
