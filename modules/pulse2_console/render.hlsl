// Console render — display spectrogram, region bands, firing flash, mini-traces.
//
// Everything positional goes through the shared p2_* transform so the pixels a
// user sees and the coordinates the detector reduces are the same mapping.

#include "types.hlsli"
// Pixel-space Scientifica text. The full scientific_ui kit is deliberately not
// used: it pulls in viewport-control bindings this module does not declare.
#include "../_shared/au_hud/au_text.hlsli"

StructuredBuffer<DH> Hist : register(t0);
StructuredBuffer<RG> Rgn  : register(t1);
RWTexture2D<float4> OutputUAV : register(u0);

// ---- verdict card primitives ----------------------------------------------
// Pixel space, not UV: the panel is `follow_panel`, so a UV-sized card would
// change proportions with the dock and the text would stretch with it.
static const float VD_S    = 2.0;    // glyph scale; cell 8x11 -> 16x22 px
static const float VD_ADV  = 14.0;   // 7 * VD_S, one glyph advance
static const float VD_ROW  = 26.0;   // row pitch
static const float VD_VALX = 84.0;   // label column width (6 glyphs)
static const float VD_BX0  = 174.0;  // bar start, relative to card x
static const float VD_BX1  = 330.0;

// Horizontal 0..1 bar. Drawn beside every normalised feature because a number
// alone does not show where it sits in its range, and "is this centroid high?"
// is the whole question the card exists to answer.
void vd_bar(float2 p, float x0, float rowY, float v, inout float3 col) {
    float bx0 = x0 + VD_BX0, bx1 = x0 + VD_BX1;
    float by0 = rowY + 5.0,  by1 = rowY + 17.0;
    if (p.x < bx0 || p.x > bx1 || p.y < by0 || p.y > by1) return;
    float t = (p.x - bx0) / max(bx1 - bx0, 1.0);
    bool on = (t <= saturate(v));
    // Outline the empty part rather than leaving it black, so the full range is
    // visible and a value of zero still reads as "measured 0", not "no data".
    col = lerp(col, on ? P2_TRACE : P2_GRID, on ? 0.95 : 0.55);
}

void vd_text(float2 p, float2 anchor, float3 tint, inout float3 col,
             int c0, int c1, int c2, int c3, int c4, int c5) {
    float cov = auText(p, anchor, VD_S, c0, c1, c2, c3, c4, c5, 0, 0, 0, 0, 0, 0);
    if (cov > 0.0) col = lerp(col, tint, cov);
}

void vd_value(float2 p, float2 anchor, float v, inout float3 col) {
    float cov = auFixed(p, anchor, VD_S, v);
    if (cov > 0.0) col = lerp(col, P2_TRACE, cov);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID) {
    uint2 px = DTid.xy;
    uint W = (uint)_Resolution.x, H = (uint)_Resolution.y;
    if (px.x >= W || px.y >= H) return;

    // Panel UV with y up, so the frequency axis rises like a spectrogram.
    float2 uv = float2(((float)px.x + 0.5) / (float)W,
                       1.0 - ((float)px.y + 0.5) / (float)H);

    float3 col = P2_INK;
    float nHops = (float)min(DISP_HOPS, (uint)max(hist_hops, 32.0));

    uint newest = (uint)max(Hist[CURSOR_IDX].v, 0.0);
    if (newest > 0u) {
        // uv.x -> hops back from newest; uv.y -> log frequency axis directly,
        // because the display rows ARE the log axis.
        float hopsBack = (1.0 - uv.x) * max(nHops - 1.0, 1.0);

        // A 768x192 history stretched over a ~1280x720 panel is a magnification
        // on both axes. Point sampling turns real audio into blocks and reads as
        // a synthetic pattern, so interpolate. The hop axis is only interpolated
        // where BOTH taps are inside the retained window, otherwise the pair
        // straddles the ring cursor and blends the newest hop against the oldest.
        float gf = (float)newest - hopsBack;
        uint  g0 = (uint)max(floor(gf), 0.0);
        uint  g1 = min(g0 + 1u, newest);
        float gt = (g1 > g0) ? frac(gf) : 0.0;

        float by = uv.y * (float)DISP_BINS - 0.5;
        uint  b0 = (uint)clamp(floor(by), 0.0, (float)(DISP_BINS - 1u));
        uint  b1 = min(b0 + 1u, DISP_BINS - 1u);
        float bt = saturate(by - floor(by));

        uint r0 = (g0 % DISP_HOPS) * DISP_BINS, r1 = (g1 % DISP_HOPS) * DISP_BINS;
        float e = lerp(lerp(Hist[r0 + b0].eq, Hist[r0 + b1].eq, bt),
                       lerp(Hist[r1 + b0].eq, Hist[r1 + b1].eq, bt), gt);
        col = p2_ramp(saturate(e), disp_hue);
    }

    // Decade gridlines, so the frequency axis is readable rather than implied.
    [unroll] for (int d = 0; d < 4; ++d) {
        float hz = 100.0 * pow(10.0, (float)d);
        if (hz < P2_AXIS_LO_HZ || hz > P2_AXIS_HI_HZ) continue;
        float t = log(hz / P2_AXIS_LO_HZ) / log(P2_AXIS_HI_HZ / P2_AXIS_LO_HZ);
        if (abs(uv.y - t) < (0.8 / (float)H)) col = lerp(col, P2_GRID, 0.85);
    }

    // ---- regions -----------------------------------------------------------
    float binHz = 0.0;
    uint capacity = max(_Data1_HopCapacity, 1u);
    {
        uint vc = max(_Data0_ValueCount, 1u);
        uint sb = (_Data0_Generation % max(_Data0_HopCapacity, 1u)) * vc;
        if (sb + vc <= (uint)_Data0_Count && _Data0[sb].fft_size != 0u)
            binHz = (float)_Data0[sb].sample_rate / (float)_Data0[sb].fft_size;
    }

    RG flash = Rgn[P2_FLASH_IDX];
    float fv[P2_MAXFLASH] = { flash.binLo, flash.binHi, flash.hopLo,
                              flash.hopHi, flash.profile, flash.gain };

    float pxH = 1.0 / max((float)H, 1.0);

    if (binHz > 0.0) {
        [loop] for (uint i = 0u; i < P2_MAXFLASH; ++i) {
            RG r = Rgn[i];
            if (r.enabled < 0.5) continue;

            float tLo = p2_bin_to_axis(r.binLo, binHz);
            float tHi = p2_bin_to_axis(r.binHi, binHz);
            if (uv.y < tLo || uv.y > tHi) continue;

            float fl = saturate(fv[i]);

            // Fill: a faint cool wash so the band is legible over the
            // spectrogram without hiding the evidence underneath it.
            col = lerp(col, P2_EDGE, 0.05 + 0.18 * fl);

            // Border, thickened and brightened by the firing flash.
            float edge = min(abs(uv.y - tLo), abs(uv.y - tHi));
            float wide = pxH * (1.2 + 2.5 * fl);
            // Flash drives toward white, not toward the accent: white is the one
            // value guaranteed to stand out against every stop of the ramp.
            float3 ec = lerp(P2_EDGE, float3(1.0, 1.0, 1.0), fl);
            if (edge < wide) col = lerp(col, ec, 0.60 + 0.40 * fl);

            // ---- mini-trace: flux against threshold ------------------------
            // Plotted inside the band, over the same time axis as the
            // spectrogram, so over- and under-triggering are visible without
            // any ground truth: the trace riding above its threshold line is
            // exactly what the picker acted on.
            uint tcursor = (uint)max(_Data1[0].f0, 0.0);
            if (tcursor > 1u && (tHi - tLo) > 0.02) {
                float hopsBack = (1.0 - uv.x) * max(nHops - 1.0, 1.0);
                float span = min(nHops, (float)P2_TRACE_SLOTS - 1.0);
                if (hopsBack < span) {
                    uint g = (uint)max((float)tcursor - 1.0 - hopsBack, 0.0);
                    uint ln = (uint)clamp(r.lane, 0.0, 2.0);
                    uint ti = p2_trace_index(g, ln);
                    if (ti < (uint)_Data1_Count) {
                        float o   = _Data1[ti].f0;
                        float thr = _Data1[ti].f1;

                        // Normalise against the threshold, so the crossing sits
                        // at a fixed height and the eye reads margin directly.
                        float ref = max(thr, 1e-6);
                        float yO   = saturate(0.5 * (o   / (2.0 * ref)));
                        float yT   = saturate(0.5 * (thr / (2.0 * ref)));

                        float base = tLo + 0.06 * (tHi - tLo);
                        float hgt  = 0.88 * (tHi - tLo);
                        float yv = base + yO * hgt;
                        float yt = base + yT * hgt;

                        if (abs(uv.y - yt) < pxH * 1.2)
                            col = lerp(col, P2_GRID * 3.0, 0.8);   // threshold
                        if (abs(uv.y - yv) < pxH * 1.6)
                            col = lerp(col, P2_TRACE, 0.95);       // flux
                    }
                }
            }

            // ---- verdict strip ---------------------------------------------
            // A tick per classifier decision, on the same time axis as the
            // spectrogram, so accept and reject can be read against the audio
            // that caused them. Suppressed candidates are drawn too: without
            // them a classifier that rejects everything and one that does
            // nothing at all look identical on screen.
            uint vlane = (uint)clamp(verdict_lane, 0.0, 2.0);
            uint tcur = (uint)max(_Data1[0].f0, 0.0);
            float stripHi = tHi - pxH * 2.0;
            float stripLo = stripHi - pxH * 13.0;
            if (show_verdict > 0.5 && tcur > 1u
                && (uint)clamp(r.lane, 0.0, 2.0) == vlane
                && uv.y >= stripLo && uv.y <= stripHi) {
                float hopsBack = (1.0 - uv.x) * max(nHops - 1.0, 1.0);
                if (hopsBack < min(nHops, (float)P2_TRACE_SLOTS - 1.0)) {
                    int g = (int)max((float)tcur - 1.0 - hopsBack, 0.0);

                    // Widened to +/-1 hop. A single hop is under two pixels at
                    // this history depth, which survives on screen but vanishes
                    // in a downscaled capture -- and the capture is the proof.
                    float st = 0.0;
                    [unroll] for (int dg = -1; dg <= 1; ++dg) {
                        int gg = g + dg;
                        if (gg < 0 || gg >= (int)tcur) continue;
                        uint ti2 = p2_trace_index((uint)gg, vlane);
                        if (ti2 >= (uint)_Data1_Count) continue;
                        float s = _Data1[ti2].f2;
                        if (s > 0.5) st = 1.0;                   // accept wins
                        else if (s < -0.5 && st == 0.0) st = -1.0;
                    }
                    if (st > 0.5)       col = float3(1.0, 1.0, 1.0);
                    else if (st < -0.5) col = P2_ACCENT;
                }
            }
        }
    }

    // ---- drag in progress --------------------------------------------------
    RG hdr = Rgn[P2_HDR_IDX];
    if (hdr.binHi > 0.5) {
        float t0 = min(hdr.hopHi, hdr.gain), t1 = max(hdr.hopHi, hdr.gain);
        if (uv.y >= t0 && uv.y <= t1) {
            col = lerp(col, P2_EDGE, 0.16);
            float edge = min(abs(uv.y - t0), abs(uv.y - t1));
            if (edge < pxH * 1.5) col = lerp(col, float3(1.0, 1.0, 1.0), 0.9);
        }
    }

    // ---- verdict card ------------------------------------------------------
    // Reports the newest classifier decision on the selected lane: the three
    // features it weighed, the score it produced, and whether the hit was kept.
    //
    // ALL of it is gated behind the card rectangle. Each label is a 12-iteration
    // loop over the font table, and running that per-pixel across the whole
    // panel is a large cost for a region occupying 7% of it.
    float2 p = float2((float)px.x + 0.5, (float)px.y + 0.5);
    float X0 = 18.0, Y0 = 16.0;
    float CW = 342.0, CH = 196.0;

    if (show_verdict > 0.5
        && p.x >= X0 - 8.0 && p.x <= X0 + CW && p.y >= Y0 - 8.0 && p.y <= Y0 + CH) {

        RG vd = Rgn[P2_VERDICT_IDX];

        // Panel: darken rather than fill flat, so the spectrogram stays faintly
        // visible behind the card and the card cannot hide evidence.
        col = lerp(col, P2_INK, 0.86);
        float ex = min(min(p.x - (X0 - 8.0), (X0 + CW) - p.x),
                       min(p.y - (Y0 - 8.0), (Y0 + CH) - p.y));
        if (ex < 1.5) col = lerp(col, P2_GRID * 2.2, 0.9);

        bool none   = (abs(vd.profile) < 0.5);
        bool accept = (vd.profile > 0.5);

        // Title. The lane is NAMED, not implied: in the shipped mode the
        // classifier gates lane 1 only, and a card that silently reported one
        // lane while looking like it covered all three would be a lie.
        vd_text(p, float2(X0, Y0), P2_TRACE, col, G_V, G_E, G_R, G_D, G_I, G_C);
        vd_text(p, float2(X0 + 6.0 * VD_ADV, Y0), P2_TRACE, col, G_T, 0, 0, 0, 0, 0);

        uint vl = (uint)clamp(vd.lane, 0.0, 2.0);
        float2 lp = float2(X0, Y0 + VD_ROW);
        if (vl == 0u)      vd_text(p, lp, P2_EDGE, col, G_K, G_I, G_C, G_K, 0, 0);
        else if (vl == 1u) vd_text(p, lp, P2_EDGE, col, G_S, G_N, G_A, G_R, G_E, 0);
        else               vd_text(p, lp, P2_EDGE, col, G_H, G_A, G_T, 0, 0, 0);

        // Three feature rows. Values are the picker's own numbers, read from the
        // trace it wrote when it decided -- not recomputed here, which could
        // disagree with the detector this card is meant to explain.
        float rows[3] = { vd.binLo, vd.binHi, vd.hopLo };
        float y1 = Y0 + VD_ROW * 2.0;
        float y2 = Y0 + VD_ROW * 3.0;
        float y3 = Y0 + VD_ROW * 4.0;

        vd_text(p, float2(X0, y1), P2_TRACE, col, G_C, G_E, G_N, G_T, 0, 0);
        vd_text(p, float2(X0, y2), P2_TRACE, col, G_F, G_L, G_A, G_T, 0, 0);
        vd_text(p, float2(X0, y3), P2_TRACE, col, G_D, G_E, G_C, G_A, G_Y, 0);

        if (!none) {
            vd_value(p, float2(X0 + VD_VALX, y1), rows[0], col);
            vd_value(p, float2(X0 + VD_VALX, y2), rows[1], col);
            vd_value(p, float2(X0 + VD_VALX, y3), rows[2], col);
            vd_bar(p, X0, y1, rows[0], col);
            vd_bar(p, X0, y2, rows[1], col);
            vd_bar(p, X0, y3, rows[2], col);
        }

        // Score and outcome. ACCEPT/REJECT is exactly the sign of the score, so
        // the two together are self-checking: a word that disagrees with its own
        // number would be visible immediately.
        float y4 = Y0 + VD_ROW * 5.0;
        float y5 = Y0 + VD_ROW * 6.0;
        vd_text(p, float2(X0, y4), P2_TRACE, col, G_S, G_C, G_O, G_R, G_E, 0);
        if (!none) vd_value(p, float2(X0 + VD_VALX, y4), vd.hopHi, col);

        if (none) {
            vd_text(p, float2(X0, y5), P2_GRID * 3.0, col, G_MI, G_MI, G_MI, G_MI, 0, 0);
        } else if (accept) {
            // Same colours as the timeline strip above, so the card doubles as
            // that strip's legend: white kept, accent suppressed.
            vd_text(p, float2(X0, y5), float3(1.0, 1.0, 1.0), col,
                    G_A, G_C, G_C, G_E, G_P, G_T);
        } else {
            vd_text(p, float2(X0, y5), P2_ACCENT, col,
                    G_R, G_E, G_J, G_E, G_C, G_T);
        }

        // Seconds since the latch. The card HOLDS its last verdict so a still
        // capture is not blank between hits; the age is what stops a held card
        // from being mistaken for a live one.
        if (!none) {
            vd_text(p, float2(X0 + 7.0 * VD_ADV, y5), P2_GRID * 3.2, col,
                    G_A, G_G, G_E, 0, 0, 0);
            vd_value(p, float2(X0 + 10.0 * VD_ADV, y5), vd.gain, col);
        }
    }

    OutputUAV[px] = float4(col, 1.0);
}
