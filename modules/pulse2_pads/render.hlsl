// Four pads in a row. Bright = that lane just fired.

#include "../_shared/au_hud/au_text.hlsli"

StructuredBuffer<float4> Pads : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

static const float3 INK    = float3(0.94, 0.95, 0.96);
static const float3 EDGE   = float3(0.30, 0.32, 0.34);
// The warm accent is spent only on BEAT, the one lane that is inferred rather
// than detected. Giving all four a colour would make the set a palette to
// decode instead of three-the-same and one-different.
static const float3 ACCENT = float3(1.00, 0.62, 0.24);

// Rounded-box signed distance, negative inside.
float sdRound(float2 p, float2 half_, float r) {
    float2 d = abs(p) - half_ + r;
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0)) - r;
}

float padLabel(float2 p, float2 anchor, float s, uint lane) {
    if (lane == 0u) return auText(p, anchor, s, G_K, G_I, G_C, G_K, 0,0,0,0,0,0,0,0);
    if (lane == 1u) return auText(p, anchor, s, G_S, G_N, G_A, G_R, G_E, 0,0,0,0,0,0,0);
    if (lane == 2u) return auText(p, anchor, s, G_H, G_A, G_T, 0,0,0,0,0,0,0,0,0);
    return auText(p, anchor, s, G_B, G_E, G_A, G_T, 0,0,0,0,0,0,0,0);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID) {
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;

    float2 p = float2(px) + 0.5;
    float W = _Resolution.x, H = _Resolution.y;

    float3 col = float3(0.02, 0.021, 0.023);

    float cellW = W / 4.0;
    uint lane = (uint)clamp(floor(p.x / cellW), 0.0, 3.0);
    float2 centre = float2(((float)lane + 0.5) * cellW, H * 0.46);

    float side = min(cellW * 0.72, H * 0.62);
    float2 half_ = float2(side, side) * 0.5;
    float r = max(corner, 0.0) * side;

    float4 st = Pads[lane];
    float flash = saturate(st.y);
    float3 ink = (lane == 3u) ? ACCENT : INK;

    float d = sdRound(p - centre, half_, r);

    // Fill.
    float inside = saturate(-d);                 // 1px antialiased edge
    float level = max(idle_level, 0.0) + (1.0 - max(idle_level, 0.0)) * flash;
    col = lerp(col, ink * level, inside);

    // Border, always visible so an idle pad still reads as a pad.
    float edge = saturate(1.0 - abs(d)) * 0.9;
    col = max(col, lerp(EDGE, ink, flash) * edge);

    // Halo. Sells the flash at a glance without moving the pad's own edge,
    // which has to stay put or the four stop reading as a fixed row.
    //
    // Kept TIGHT and clipped to the pad's own cell. A wide glow spilled across
    // the divider and lit its neighbours, which is the one thing this view must
    // never do: the whole point is telling at a glance which lane fired, and a
    // bloom that crosses cells makes a silent pad look like it triggered.
    if (flash > 0.001 && d > 0.0) {
        float cellL = (float)lane * cellW;
        bool inCell = (p.x > cellL + 2.0) && (p.x < cellL + cellW - 2.0);
        if (inCell) col += ink * exp(-d / (side * 0.07)) * flash * 0.30;
    }

    // Label below the pad.
    float s = max(label_size, 1.0);
    float2 lab = float2(centre.x - 2.0 * 7.0 * s, centre.y + side * 0.5 + 16.0);
    float t = padLabel(p, lab, s, lane);
    if (t > 0.0) col = lerp(col, lerp(EDGE * 1.6, ink, flash), t);

    if (show_counts > 0.5) {
        float2 na = float2(centre.x - 2.0 * 7.0 * (s * 0.6), centre.y + side * 0.5 + 16.0 + 13.0 * s);
        float n = auNum(p, na, s * 0.6, (int)min(st.z, 99999.0), 5);
        if (n > 0.0) col = lerp(col, EDGE * 1.5, n);
    }

    OutputUAV[px] = float4(col, 1.0);
}
