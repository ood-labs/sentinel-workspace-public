// Priority-node editor preview: all generated nodes remain visible, while the
// bounded editable set receives crisp host-selection rings and crosshairs.

#include "node_edit_types.hlsli"

StructuredBuffer<NodeRecord> Nodes : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float3 col = float3(0.003, 0.010, 0.014);

    float2 grid = abs(frac(uv * float2(24.0, 14.0)) - 0.5);
    float gridLine = 1.0 - smoothstep(0.485, 0.498, max(grid.x, grid.y));
    col += float3(0.015, 0.070, 0.082) * gridLine;

    [loop] for (uint i = 0u; i < 128u; i++) {
        NodeRecord n = Nodes[i];
        if (n.active < 0.5) continue;
        float2 dp = (uv - n.pos) * _Resolution.xy;
        float distPx = length(dp);
        float core = exp(-distPx * distPx / max(n.radius * n.radius * _Resolution.y * _Resolution.y * 0.08, 3.0));
        float3 tint = lerp(float3(0.24, 0.76, 0.88), float3(1.0, 0.45, 0.08), n.color_mix);
        col += tint * core * n.intensity;

        if (i < 12u) {
            bool selected = _ViewportSelectionMeta.y == i + 1u;
            float radius = max(14.0, n.radius * _Resolution.y * 1.5);
            float ring = 1.0 - smoothstep(0.7, 1.8, abs(distPx - radius));
            float cross = max(1.0 - smoothstep(0.7, 1.5, abs(dp.x)),
                              1.0 - smoothstep(0.7, 1.5, abs(dp.y))) * (1.0 - smoothstep(radius + 7.0, radius + 9.0, distPx));
            col = lerp(col, selected ? float3(1.0, 0.46, 0.08) : float3(0.10, 0.72, 0.84), saturate(ring + cross * 0.35));
        }
    }
    float vignette = saturate(1.0 - dot((uv - 0.5) * float2(1.0, 1.6), (uv - 0.5) * float2(1.0, 1.6)) * 1.15);
    OutputUAV[pixel] = float4(saturate(col * vignette), 1.0);
}
