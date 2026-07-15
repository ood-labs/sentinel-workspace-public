#include "dada_edit_types.hlsli"

StructuredBuffer<DadaPart> Parts : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

float3 previewCol(float mat, int k)
{
    if (k == 7)  return float3(0.30, 0.62, 0.52);
    if (k == 6)  return float3(0.85, 0.30, 0.72);
    if (k == 5)  return float3(0.96, 0.96, 0.97);
    if (k == 10) return float3(0.92, 0.80, 0.16);
    if (mat < 2.5)  return float3(0.05, 0.05, 0.055);
    if (mat < 3.5)  return float3(0.88, 0.86, 0.80);
    if (mat < 10.5) return float3(0.72, 0.12, 0.06);
    if (mat < 11.5) return float3(0.90, 0.58, 0.06);
    if (mat < 12.5) return float3(0.80, 0.30, 0.04);
    if (mat < 13.5) return float3(0.44, 0.42, 0.20);
    if (mat < 14.5) return float3(0.45, 0.43, 0.40);
    if (mat < 15.5) return float3(0.08, 0.07, 0.065);
    if (mat < 16.5) return float3(0.90, 0.87, 0.78);
    return float3(0.76, 0.48, 0.13);
}

float linePx(float value, float widthPx) { return 1.0 - smoothstep(widthPx, widthPx + 1.0, abs(value)); }

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)px + 0.5) / _Resolution.xy;
    float2 w = lerp(DADA_W_MIN, DADA_W_MAX, float2(uv.x, 1.0 - uv.y));
    float pxw = (DADA_W_MAX.x - DADA_W_MIN.x) / _Resolution.x;
    float3 col = lerp(float3(0.025, 0.023, 0.020), float3(0.095, 0.070, 0.038), uv.y);

    float2 grid = abs(frac(uv * float2(16.0, 20.0)) - 0.5);
    float gridLine = 1.0 - smoothstep(0.485, 0.499, max(grid.x, grid.y));
    col += float3(0.11, 0.065, 0.025) * gridLine * 0.45;
    col = lerp(col, float3(0.28, 0.18, 0.07), smoothstep(pxw * 1.5, 0.0, abs(w.y)));

    uint selected = _ViewportSelectionMeta.y;
    float bestZ = -1e9;
    [loop] for (uint i = 0u; i < 29u; ++i) {
        DadaPart d = Parts[i];
        if (d.active < 0.5) continue;
        float rad = max(d.sc_xy.x, d.sc_xy.y) * (((int)d.kind >= 3 && (int)d.kind <= 6) ? 0.58 : 0.50);
        float dist = length(w - d.pos_xy);
        float edge = smoothstep(rad + pxw, rad - pxw, dist);
        if (edge > 0.01 && d.pos_z > bestZ) {
            bestZ = d.pos_z;
            float3 c = previewCol(d.mat, (int)d.kind);
            float shade = 0.68 + 0.32 * saturate(d.pos_z * 0.5 + 0.5);
            float rim = smoothstep(rad - pxw * 2.0, rad, dist);
            c = lerp(c * shade, c * 0.42, rim);
            if ((uint)round(d.group) == selected) c = lerp(c, float3(1.0, 0.56, 0.10), 0.34);
            col = lerp(col, c, edge);
        }
        if ((uint)round(d.group) == selected) {
            float ring = 1.0 - smoothstep(pxw * 1.5, pxw * 3.2, abs(dist - rad * 1.08));
            col = lerp(col, float3(1.0, 0.64, 0.13), ring);
        }
    }

    [unroll] for (uint groupId = 1u; groupId <= 4u; ++groupId) {
        float2 lo = 1e9.xx, hi = -1e9.xx;
        [loop] for (uint i = 0u; i < 29u; ++i) {
            DadaPart d = Parts[i];
            if ((uint)round(d.group) != groupId) continue;
            float r = max(max(d.sc_xy.x, d.sc_xy.y), 0.12);
            lo = min(lo, d.pos_xy - r.xx); hi = max(hi, d.pos_xy + r.xx);
        }
        float dx = min(abs(w.x - lo.x), abs(w.x - hi.x));
        float dy = min(abs(w.y - lo.y), abs(w.y - hi.y));
        bool withinX = w.x >= lo.x && w.x <= hi.x;
        bool withinY = w.y >= lo.y && w.y <= hi.y;
        float boxLine = max((withinY ? linePx(dx / pxw, 1.0) : 0.0),
                            (withinX ? linePx(dy / pxw, 1.0) : 0.0));
        float strength = groupId == selected ? 0.95 : 0.22;
        col = lerp(col, groupId == selected ? float3(1.0, 0.62, 0.12) : float3(0.60, 0.35, 0.12), boxLine * strength);
    }

    float toolX = 0.055 + (float)tool_mode * 0.055;
    float tool = step(abs(uv.x - toolX), 0.020) * step(abs(uv.y - 0.045), 0.012);
    col = lerp(col, float3(1.0, 0.61, 0.12), tool);
    float vignette = saturate(1.0 - dot((uv - 0.5) * float2(0.8, 1.2), (uv - 0.5) * float2(0.8, 1.2)) * 0.9);
    OutputUAV[px] = float4(saturate(col * vignette), 1.0);
}
