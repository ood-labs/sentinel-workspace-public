// The whole interface in one image.
//
// Top: the live spectrum on a log-Hz axis, with each lane's band drawn as a
// shaded slab over it. The slab IS the set of bins that gets summed.
//
// Bottom: one strip per lane showing that lane's onset value at hop resolution
// with its threshold drawn across it, a tick where it fired, a flash block and
// a hit count.
//
// The point of putting the trace and the threshold on the same axes is that a
// missed hit becomes a thing you can see rather than a thing you guess at: the
// peak is either under the line or it is not.
//
// Colour carries exactly one meaning: the warm accent marks DETECTION — signal
// above threshold, accepted hits, the threshold line itself. Which lane is
// selected for editing is carried by brightness instead, so the two never have
// to be told apart by hue.
//
// LAYOUT: this is a Canvas panel at follow_panel resolution, so it is redrawn at
// whatever size the dock happens to be. There are no absolute pixel numbers
// below. Everything is a multiple of `u`, the UI unit from abUI(), including the
// text — a fixed layout would have put the Hz readouts off the edge of a narrow
// dock and left them as a stamp in the corner of a wide one.

#include "bands.hlsli"
#include "../_shared/au_hud/au_text.hlsli"

StructuredBuffer<float4> Cols  : register(t0);
StructuredBuffer<float4> Bands : register(t1);
StructuredBuffer<float4> Det   : register(t2);
RWTexture2D<float4> OutputUAV  : register(u0);

static const float3 BG     = float3(0.021, 0.022, 0.024);
static const float3 INK    = float3(0.93, 0.94, 0.95);
static const float3 DIM    = float3(0.33, 0.35, 0.37);
static const float3 GRID   = float3(0.13, 0.14, 0.15);
static const float3 ACCENT = float3(1.00, 0.62, 0.24);

// Smallest full scale a strip will use. Without a floor, a silent lane would
// autoscale its own noise up to full height and look like it was working.
static const float AB_FLUX_MIN_FS = 6.0;

static const float OCT_HZ[10] = {
    31.25, 62.5, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0
};

int abDigits(float v) {
    float av = max(v, 0.0);
    return (av < 10.0) ? 1 : (av < 100.0) ? 2 : (av < 1000.0) ? 3
         : (av < 10000.0) ? 4 : 5;
}

// Leading zeros on a frequency readout look like precision that is not there,
// so the digit count follows the magnitude.
float abNumAuto(float2 p, float2 a, float s, float v) {
    return auNum(p, a, s, (int)round(max(v, 0.0)), abDigits(v));
}

float abLaneLabel(float2 p, float2 a, float s, uint lane) {
    if (lane == 0u) return auText(p, a, s, G_K, G_I, G_C, G_K, 0,0,0,0,0,0,0,0);
    if (lane == 1u) return auText(p, a, s, G_S, G_N, G_A, G_R, G_E, 0,0,0,0,0,0,0);
    return auText(p, a, s, G_H, G_A, G_T, 0,0,0,0,0,0,0,0,0);
}

// "45-110" with the separator placed by the first number's real width. Fixed
// offsets ran "6200" and "14000" together into an unreadable 620014000, and a
// panel that resizes would have produced that collision at some sizes only.
float abSpanLabel(float2 p, float2 a, float s, float lo, float hi) {
    float adv = 7.0 * s;
    float d0  = (float)abDigits(lo);
    float cov = abNumAuto(p, a, s, lo);
    cov = max(cov, auText(p, a + float2(d0 * adv + adv * 0.35, 0.0), s,
                          G_MI, 0,0,0,0,0,0,0,0,0,0,0));
    cov = max(cov, abNumAuto(p, a + float2((d0 + 1.0) * adv + adv * 0.7, 0.0),
                             s, hi));
    return cov;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID) {
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;

    float2 p = float2(px) + 0.5;
    float  W = _Resolution.x;
    float  H = _Resolution.y;

    float3 col = BG;

    // The single unit every size below is expressed in.
    float u   = abUI(H);
    float gw  = 7.0 * u;                 // glyph advance at text scale u
    float lw  = max(1.0, u * 0.5);       // stroke width

    float specBot = floor(H * AB_SPEC_BOT);
    float plotBot = abPlotBot(H);
    float plotTop = abPlotTop(H);

    float4 hdr   = Cols[AB_COL_HDR];
    float  hzMax = hdr.y;
    float  hopDt = hdr.z;

    // The highlight follows whatever is being dragged, and nothing otherwise.
    // With no lane selector there is no "current" band to mark: you point at
    // the one you mean, so marking one while your pointer is elsewhere would
    // only ever contradict the gesture.
    float4 dragS = Bands[AB_DRAG];
    float4 grabS = Bands[AB_GRAB];
    bool   editing = (dragS.x > 0.5) && (dragS.w < 3.5);
    int    eLane = editing ? (int)clamp(grabS.x, 0.0, 2.0) : -1;

    // ======================= SPECTRUM =======================================
    if (p.y < specBot) {
        [loop] for (int o = 0; o < 10; ++o) {
            if (OCT_HZ[o] > hzMax) break;
            float gx = abHzToX(OCT_HZ[o], hzMax) * W;
            if (abs(p.x - gx) < 0.5 && p.y < plotBot) col = GRID;
        }

        // Band slabs, drawn under the bars: the whole point is to see the
        // signal inside the band, not to cover it up.
        [loop] for (uint L = 0u; L < AB_LANES; ++L) {
            float4 b = Bands[L];
            if (b.z < 0.5 || b.y <= b.x) continue;
            float x0  = abHzToX(b.x, hzMax) * W;
            float x1  = abHzToX(b.y, hzMax) * W;
            bool  act = ((int)L == eLane);
            bool  inX = (p.x >= x0 && p.x <= x1);
            bool  inY = (p.y > plotTop && p.y < plotBot);

            if (inX && inY) col = lerp(col, INK * 0.5, act ? 0.15 : 0.07);
            if (inY && (abs(p.x - x0) < lw || abs(p.x - x1) < lw)) {
                col = max(col, INK * (act ? 0.85 : 0.30));
            }
            if (inX && abs(p.y - plotTop) < lw * (act ? 2.0 : 1.0)) {
                col = max(col, INK * (act ? 0.95 : 0.35));
            }

            // ---- threshold fader ----
            // Drawn as a bar plus a grab tab on the right edge, in the accent,
            // so it reads as a control rather than as a level on the spectrum's
            // dB axis. It is a flux threshold; the axis behind it is level, and
            // the two are not the same quantity.
            if (!inX || !inY) continue;
            float barY = abThreshToY(b.w, H);
            bool  grabbed = act && (dragS.w > 2.5) && (dragS.w < 3.5);

            if (abs(p.y - barY) < lw * (grabbed ? 2.0 : 1.0)) {
                col = max(col, ACCENT * (grabbed ? 1.0 : 0.62));
            }
            // Tab, sized so it is obviously grabbable at the band's right edge.
            if (p.x > x1 - 6.5 * u && abs(p.y - barY) < 2.5 * u) {
                col = max(col, ACCENT * (grabbed ? 1.0 : 0.80));
            }
        }

        // One reduced column per real pixel, so the spectrum gains detail as the
        // panel widens instead of stretching a fixed-width picture across it.
        // Past the reducer's capacity it degrades to a stretch rather than to a
        // frozen right-hand edge.
        float cw = min(W, (float)AB_COLS_MAX);
        uint  ci = (uint)clamp(floor(p.x / W * cw), 0.0, cw - 1.0);
        float4 cv = Cols[ci];
        float barTop = plotBot - cv.x * (plotBot - plotTop);
        float peakY  = plotBot - cv.y * (plotBot - plotTop);

        if (p.y >= barTop && p.y < plotBot) {
            col = max(col, INK * (0.26 + 0.26 * cv.x));
        }
        if (abs(p.y - peakY) < lw && cv.y > 0.004) col = max(col, INK * 0.85);
        if (abs(p.y - plotBot) < lw) col = max(col, DIM * 0.9);

        // Hz axis. Smaller than the band labels on purpose: these are tick
        // marks on a ruler, not readings, and at the same size as the lane
        // names they competed with them for attention.
        [loop] for (int o2 = 0; o2 < 10; ++o2) {
            if (OCT_HZ[o2] > hzMax) break;
            float gx = abHzToX(OCT_HZ[o2], hzMax) * W;
            if (abNumAuto(p, float2(gx + 1.5 * u, plotBot + 1.5 * u), u * 0.8,
                          OCT_HZ[o2]) > 0.0) {
                col = max(col, DIM * 1.15);
            }
        }

        // Band name and its measured span, under the bracket rail.
        [loop] for (uint L2 = 0u; L2 < AB_LANES; ++L2) {
            float4 b = Bands[L2];
            if (b.z < 0.5 || b.y <= b.x) continue;
            float x0  = abHzToX(b.x, hzMax) * W;
            bool  act = ((int)L2 == eLane);
            float3 tint = INK * (act ? 1.0 : 0.42);

            // A band near the top of the axis starts close to the right edge,
            // and the label block is far wider than the band itself, so
            // anchoring it to the band alone ran the span readout off the
            // panel. Clamp the BLOCK, not each row: clamping rows separately
            // would break their left alignment at exactly the sizes where the
            // clamp starts to matter.
            float labW = 12.0 * (7.0 * u * 0.9);   // widest row: "12390 - 16600"
            float labX = clamp(x0 + 2.5 * u, 2.0 * u, max(W - labW, 2.0 * u));

            // Threshold value, printed beside its bar so the fader is readable
            // as a number and not only as a height.
            float barY = abThreshToY(b.w, H);
            if (abNumAuto(p, float2(x0 + 3.5 * u, barY - 7.5 * u),
                          u * 0.95, b.w) > 0.0) {
                col = max(col, ACCENT * 0.9);
            }

            // Rows are spaced 11 units apart because that is the font's cell
            // height, not the 7-unit advance. Spacing them by the advance
            // overlapped each line into the one above it.
            if (abLaneLabel(p, float2(labX, plotTop + 3.0 * u), u, L2) > 0.0) {
                col = max(col, tint);
            }
            if (abSpanLabel(p, float2(labX, plotTop + 14.0 * u),
                            u * 0.9, b.x, b.y) > 0.0) {
                col = max(col, tint * 0.72);
            }

            // Band level, and a mark when it is under the signal gate. Without
            // this a gated lane is simply dead with no visible reason, which is
            // the worst possible failure for a detector you are trying to tune.
            float4 C = Det[abStateC(L2)];
            float lvl = C.x;
            bool  gated = (C.y > 0.5);
            float2 la = float2(labX, plotTop + 24.0 * u);
            float  ls = u * 0.9;
            if (auText(p, la, ls, G_MI, 0,0,0,0,0,0,0,0,0,0,0) > 0.0
                || abNumAuto(p, la + float2(7.0 * ls, 0.0), ls, -lvl) > 0.0
                || auText(p, la + float2(7.0 * ls * 3.6, 0.0), ls,
                          G_D, G_B, 0,0,0,0,0,0,0,0,0,0) > 0.0) {
                col = max(col, gated ? DIM * 0.75 : tint * 0.60);
            }
        }

        OutputUAV[px] = float4(col, 1.0);
        return;
    }

    // ======================= TRACE STRIPS ===================================
    float stripH = (H - specBot) / (float)AB_LANES;
    uint  lane   = (uint)clamp(floor((p.y - specBot) / stripH), 0.0,
                               (float)(AB_LANES - 1u));
    float sTop   = specBot + (float)lane * stripH;
    float sBot   = sTop + stripH;

    // Headroom for the scale readout: a full font cell (11 units at 0.75 scale
    // is 8.25) plus a little, so the number sits above the graph instead of
    // hanging into its first few rows.
    float gTop = sTop + 10.0 * u;
    float gBot = sBot - 2.5 * u;

    // Left gutter fits the widest lane name ("SNARE"); right gutter fits the
    // flash block, its gaps and a five-digit count. Both are derived from the
    // text metrics rather than measured off one screenshot, so nothing collides
    // when the panel and therefore the text size changes.
    float blockW = 13.0 * u;
    float pX0 = 4.0 * u + 5.0 * gw;
    float pX1 = W - (blockW + 12.0 * u + 5.0 * gw + 6.0 * u);

    if (abs(p.y - sTop) < lw * 0.5 && lane > 0u) col = max(col, GRID);

    float4 A = Det[abStateA(lane)];
    float4 B = Det[abStateB(lane)];
    float env   = saturate(A.w);
    float count = B.x;
    uint  wIdx  = (uint)max(B.z, 0.0);
    // The THRESHOLD is part of the scale, not just the signal. Without it, a
    // threshold above the recent peak pins its line to the top edge where it
    // reads as the strip border, and the one thing the strip has to show -- how
    // far under the line the peaks are falling -- becomes invisible.
    float thrFs = Bands[lane].w;
    float fs    = max(max(B.w, thrFs), AB_FLUX_MIN_FS) * 1.15;

    bool  active = ((int)lane == eLane);
    float sel    = active ? 1.0 : 0.55;

    // ---- lane name ----
    if (abLaneLabel(p, float2(4.0 * u, gTop + 3.0 * u), u, lane) > 0.0) {
        col = max(col, lerp(DIM * 1.5 * sel, ACCENT, env));
    }

    // ---- flash block + hit count ----
    float bx0 = pX1 + 7.0 * u, bx1 = bx0 + blockW;
    float by0 = gTop + 1.0 * u, by1 = gBot - 1.0 * u;
    if (p.x >= bx0 && p.x <= bx1 && p.y >= by0 && p.y <= by1) {
        col = max(col, ACCENT * (0.05 + 0.95 * env));
    } else if (p.x >= bx0 - lw && p.x <= bx1 + lw
            && p.y >= by0 - lw && p.y <= by1 + lw) {
        col = max(col, DIM * 0.8);
    }
    if (abNumAuto(p, float2(bx1 + 5.0 * u, gTop + 4.0 * u), u * 0.9, count) > 0.0) {
        col = max(col, DIM * 1.6);
    }

    // ---- scale readout: full scale left, threshold right ----
    if (abNumAuto(p, float2(pX0, sTop + 1.5 * u), u * 0.75, fs) > 0.0) {
        col = max(col, DIM * 1.1);
    }

    // ---- the trace ----
    if (p.x >= pX0 && p.x <= pX1 && hopDt > 0.0) {
        float nShow = clamp(trace_seconds / hopDt, 8.0, (float)AB_TRACE - 2.0);
        float plotW = pX1 - pX0;
        float u0 = (p.x - pX0) / plotW;
        float u1 = (p.x + 1.0 - pX0) / plotW;

        // A column can cover more than one hop at long spans. Take the max, so
        // a peak is never lost between two pixels — losing it is precisely the
        // failure that makes a threshold impossible to place.
        int kA = (int)floor(u0 * nShow);
        int kB = min((int)floor(u1 * nShow), kA + 8);

        float flux = 0.0, thr = 0.0, fired = 0.0;
        [loop] for (int k = kA; k <= kB; ++k) {
            float fk = (float)wIdx - nShow + (float)k;
            if (fk < 0.0) continue;
            float4 tv = Det[abTraceAt(lane, (uint)fk)];
            flux  = max(flux, tv.x);
            thr   = max(thr, tv.y);
            fired = max(fired, tv.z);
        }

        float gh   = gBot - gTop;
        float fy   = gBot - saturate(flux / fs) * gh;
        float thrY = gBot - saturate(thr  / fs) * gh;

        if (p.y >= fy && p.y <= gBot) {
            bool over = (p.y < thrY);
            col = max(col, over ? ACCENT * 0.80 : INK * (0.26 * sel + 0.10));
        }

        // Threshold line, dashed so it never reads as signal. The dash period
        // scales too, or it would close up into a solid line on a large panel.
        if (abs(p.y - thrY) < lw && frac(p.x * 0.18 / u) < 0.55) {
            col = max(col, ACCENT * 0.7);
        }

        // Accepted-hit tick, full strip height.
        if (fired > 0.5 && p.y >= gTop && p.y <= gBot) {
            col = max(col, ACCENT * 0.45);
        }

        if (abs(p.y - gBot) < lw * 0.5) col = max(col, GRID * 1.4);
    }

    OutputUAV[px] = float4(col, 1.0);
}
