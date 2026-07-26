// Strip chart: four lane rows, time left to right, newest at the right edge.

#include "common.hlsli"
#include "../_shared/au_hud/au_text.hlsli"

StructuredBuffer<float4> Cols : register(t0);
StructuredBuffer<float4> TS   : register(t1);
RWTexture2D<float4> OutputUAV : register(u0);

#define GUTTER_PX 92.0

// Monochrome instrument palette. The warm accent is spent ONLY on the beat
// lane: it is the row you are comparing against the other three, and giving
// every lane its own hue would turn a comparison into a colour-matching task.
static const float3 INK_DIM   = float3(0.42, 0.44, 0.46);
static const float3 INK_BRIGHT= float3(0.94, 0.95, 0.96);
static const float3 ACCENT    = float3(1.00, 0.62, 0.24);

float3 laneInk(uint lane) {
    return (lane == HT_BEAT_LANE) ? ACCENT : INK_BRIGHT;
}

// Lane label: KICK / SNAR / HAT / BEAT.
float laneLabel(float2 p, float2 anchor, float s, uint lane) {
    if (lane == 0u) return auText(p, anchor, s, G_K, G_I, G_C, G_K, 0,0,0,0,0,0,0,0);
    if (lane == 1u) return auText(p, anchor, s, G_S, G_N, G_A, G_R, 0,0,0,0,0,0,0,0);
    if (lane == 2u) return auText(p, anchor, s, G_H, G_A, G_T, 0,0,0,0,0,0,0,0,0);
    return auText(p, anchor, s, G_B, G_E, G_A, G_T, 0,0,0,0,0,0,0,0);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID) {
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;

    float2 p = float2(px) + 0.5;
    float W = _Resolution.x;
    float H = _Resolution.y;

    float4 st = TS[0];
    float now = st.x;
    float win = max(window_s, 0.01) * sample_rate;

    float3 col = float3(0.02, 0.021, 0.023);

    float plotX0 = GUTTER_PX;
    float plotW  = max(W - GUTTER_PX, 1.0);
    float rowH   = H / (float)HT_LANES;
    uint  lane   = (uint)clamp(floor(p.y / rowH), 0.0, (float)HT_LANES - 1.0);
    float yInRow = p.y - (float)lane * rowH;

    // Alternating row wash, so four rows read as four rows without needing
    // rules between them.
    if ((lane & 1u) == 1u) col += 0.012;

    // Lane baseline.
    float baseY = rowH * 0.78;
    if (abs(yInRow - baseY) < 0.75) col = max(col, INK_DIM * 0.55);

    bool inPlot = (p.x >= plotX0);

    if (inPlot) {
        float fx = (p.x - plotX0) / plotW;                  // 0..1 across window
        float sampleHere = now - (1.0 - fx) * win;
        float colF = fx * (float)HT_COLS - 0.5;
        uint  cidx = (uint)clamp(colF, 0.0, (float)HT_COLS - 1.0);

        // One-second grid, counted back from the right edge so the ruling is
        // stable under scrolling instead of crawling.
        if (show_grid > 0.5) {
            float secs = (now - sampleHere) / sample_rate;
            float f = frac(secs);
            float d = min(f, 1.0 - f) * sample_rate / (win / plotW);   // px to line
            if (d < 0.6) col = max(col, float3(0.10, 0.105, 0.11));
        }

        // A NEIGHBOURHOOD, not the single column under this pixel.
        //
        // There are 1600 occupancy columns across ~1188 plot pixels, so a
        // pixel steps more than one column and roughly a quarter of the
        // columns are never sampled by any pixel at all. Looking up only
        // `cidx` therefore DROPPED about one mark in four outright and left
        // the rest as sub-pixel slivers -- the view looked nearly empty while
        // the counters correctly said otherwise. Scanning the columns that
        // fall within this pixel (plus the mark's own width) makes coverage
        // independent of the column-to-pixel ratio.
        float colsPerPx = (float)HT_COLS / plotW;
        int reach = (int)ceil(colsPerPx * (max(mark_width, 1.0) * 0.5 + 1.5)) + 1;

        float nearestPx = 1e9;      // this lane, px distance to nearest mark
        float beatNearPx = 1e9;     // beat lane, for the full-height rules
        int c0 = (int)floor(colF) - reach;
        int c1 = (int)floor(colF) + reach;
        [loop] for (int k = c0; k <= c1; ++k) {
            if (k < 0 || k >= (int)HT_COLS) continue;
            uint ku = (uint)k;

            float4 c = Cols[lane * HT_COLS + ku];
            if (c.x > 0.5) {
                float d = abs(colF - ht_sample_to_col(c.y, now, win));
                nearestPx = min(nearestPx, d / colsPerPx);
            }
            if (beat_rules > 0.5 && lane != HT_BEAT_LANE) {
                float4 b = Cols[HT_BEAT_LANE * HT_COLS + ku];
                if (b.x > 0.5) {
                    float d = abs(colF - ht_sample_to_col(b.y, now, win));
                    beatNearPx = min(beatNearPx, d / colsPerPx);
                }
            }
        }

        // Beat rules span every row, which is what makes beat-vs-drum alignment
        // a straight vertical read instead of an eye-traverse between rows.
        if (beatNearPx < 0.9) col = max(col, ACCENT * 0.22);

        if (nearestPx < 1e8) {
            float halfW = max(mark_width, 1.0) * 0.5;
            float topY = rowH * 0.22;
            if (yInRow >= topY && yInRow <= baseY) {
                float a = saturate(halfW + 0.5 - nearestPx);
                col = lerp(col, laneInk(lane), a);
            }
            // Bloom: a bare one-pixel tick on black is genuinely hard to track
            // in motion, and widening the mark itself would misreport WHEN.
            if (mark_glow > 0.0) {
                float g = exp(-nearestPx * 1.6) * mark_glow;
                float band = 1.0 - saturate(abs(yInRow - (topY + baseY) * 0.5) / (rowH * 0.42));
                col += laneInk(lane) * g * band * 0.5;
            }
        }

        // Cursor at the live edge.
        if (p.x > W - 2.0) col = max(col, INK_BRIGHT * 0.65);
    } else {
        // Gutter separator.
        if (abs(p.x - (plotX0 - 1.0)) < 0.75) col = max(col, INK_DIM * 0.4);
    }

    // ---- gutter labels -----------------------------------------------------
    float s = max(label_size, 1.0);
    float2 labelAnchor = float2(10.0, (float)lane * rowH + rowH * 0.30);
    float lab = laneLabel(p, labelAnchor, s, lane);
    if (lab > 0.0) col = lerp(col, laneInk(lane), lab);

    // Live count for the lane, directly under its name: a lane that has stopped
    // firing looks identical to a quiet passage until you can see whether the
    // counter is still moving. Counted once in the clock pass, not per pixel.
    float4 counts = TS[1];
    float lc = (lane == 0u) ? counts.x : (lane == 1u) ? counts.y
             : (lane == 2u) ? counts.z : counts.w;
    float num = auNum(p, labelAnchor + float2(0.0, 13.0 * s), s * 0.75, (int)lc, 3);
    if (num > 0.0) col = lerp(col, INK_DIM, num);

    OutputUAV[px] = float4(col, 1.0);
}
