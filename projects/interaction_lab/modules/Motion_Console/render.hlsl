// Motion Console v3.
//
// COST IS A PASS CRITERION HERE, not an afterthought. 3A measured the v1 desk at
// 14.66 ms -- 98% of the entire graph's pipeline time -- traced to the 4-tap
// bilinear glyph lookup at sui_typography.hlsli:63. This renderer uses the
// single-tap sui3 face and evaluates each lane's waveform ANALYTICALLY per pixel
// column rather than walking a history buffer, so the whole sheet is O(1) per
// pixel with no inner loops over samples.
#include "../_shared/ui/sui3_controls.hlsli"
#include "layout.hlsli"

RWTexture2D<float4> Out : register(u0);

struct LFOData {
    float lfo1, lfo2, lfo3, lfo4;
    float bias_x, bias_y;
    float energy, pulse;
};
StructuredBuffer<LFOData> Lfo : register(t0);
StructuredBuffer<float4>  UI  : register(t1);

static const float TWO_PI = 6.28318530718;

float evalLFO(float t, float speed, float amplitude, float shapeValue) {
    float phase = t * speed;
    float p = frac(phase);
    uint shape = (uint)clamp(round(shapeValue), 0.0, 3.0);
    float raw = shape == 0u ? sin(phase * TWO_PI) * 0.5 + 0.5
              : shape == 1u ? 1.0 - abs(p * 2.0 - 1.0)
              : shape == 2u ? p
              :               step(0.5, p);
    return saturate(raw * amplitude);
}

void laneParams(int i, out float spd, out float amp, out float shp) {
    spd = i == 0 ? lfo1_speed : i == 1 ? lfo2_speed : i == 2 ? lfo3_speed : lfo4_speed;
    amp = i == 0 ? lfo1_amp   : i == 1 ? lfo2_amp   : i == 2 ? lfo3_amp   : lfo4_amp;
    shp = i == 0 ? lfo1_shape : i == 1 ? lfo2_shape : i == 2 ? lfo3_shape : lfo4_shape;
}

float laneValue(int i, LFOData d) {
    return i == 0 ? d.lfo1 : i == 1 ? d.lfo2 : i == 2 ? d.lfo3 : d.lfo4;
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 R = _Resolution.xy;
    float2 P = ((float2)tid.xy) + 0.5;

    LFOData d = Lfo[0];
    float env = saturate(UI[0].x);
    int   fires = (int)UI[0].z;

    Sui3Theme T = sui3Theme(accent_color.rgb);

    // TEXT SCALE from the SMALLER of the two axis ratios, not from height alone.
    // Height alone picked sB=2 at 1600x900 -- text twice canonical size on a
    // canvas only 1.25x bigger -- which is what drove the header into lane 1.
    // The min() also keeps a wide-and-short dock from rendering giant glyphs in
    // a band too thin to hold them. Integer steps only: the bitmap font has no
    // fractional scale that stays crisp, and crisp is the whole look.
    float k  = min(R.x / 1280.0, R.y / 720.0);
    float sB = k >= 2.6 ? 3.0 : k >= 1.7 ? 2.0 : 1.0;
    // Left inset tracks the lane wells (x = 0.020) so the header, the wells and
    // the footer share one margin at every extent.
    float pad = 0.020 * R.x;

    float3 col = T.field;

    // ---- header -------------------------------------------------------------
    // Sized against the HEADROOM ABOVE LANE 1, not against a fixed pixel pad.
    // The lane bands are normalized and the header was not, so at 640x360 the
    // title crossed the lane-1 label and at 1600x900 the subtitle crossed the
    // band itself. Deriving the block from the space it actually has to live in
    // is the only version that survives Amendment 1's extent checks.
    float headTop = mcLaneBand(0).y * R.y;
    float labelH  = 11.0 * sB;                        // lane-1 label sits here
    float avail   = headTop - labelH - 4.0 * sB;
    float sT      = (avail >= 37.0 * sB) ? 2.0 * sB : sB;
    float subH    = 11.0 * sB;
    bool  showSub = avail >= 11.0 * sT + 4.0 * sB + subH;
    float blockH  = 11.0 * sT + (showSub ? 4.0 * sB + subH : 0.0);
    float headY   = max(4.0 * sB, floor((avail - blockH) * 0.5));

    col += T.ink * sui3TextLong(P, float2(pad, headY), sT,
        S_M,S_O,S_T,S_I,S_O,S_N,S_SP,S_C,S_O,S_N,S_S,S_O,
        S_L,S_E, 0,0,0,0,0,0,0,0,0,0);
    if (showSub) {
        col += T.dim * sui3TextLong(P, float2(pad, headY + 11.0 * sT + 4.0 * sB), sB,
            S_F,S_O,S_U,S_R,S_SP,S_L,S_A,S_N,S_E,S_SP,S_F,S_I,
            S_E,S_L,S_D, 0,0,0,0,0,0,0,0,0);
    }

    // master rate, mute, bias pad -- host controls, drawn from the host's rects
    float4 rMaster = mcPx(UI_RECT_MASTER_RATE, R);
    float4 rMute   = mcPx(UI_RECT_MUTE, R);
    float4 rBias   = mcPx(UI_RECT_BIAS, R);

    // Top-row labels sit in the gap between the panel edge and the control.
    if (mcLabelFits(rMaster.y, sB))
        col += T.dim * sui3Text(P, float2(rMaster.x, rMaster.y - 11.0 * sB), sB,
            S_M,S_A,S_S,S_T,S_E,S_R,0,0,0,0,0,0);
    if (sui3RectIn(P, rMaster) > 0.5 || sui3Frame(P, rMaster) > 0.0) {
        col = lerp(col, float3(0,0,0), sui3RectIn(P, rMaster));
        col += sui3Rail(P, rMaster, (master_rate - 0.10) / 2.90, T);
    }
    // Inside-left, matching the lane rate/amp readouts. Drawn OUTSIDE the right
    // edge it collided with the MUTE plate at 1280 and clipped to "01" -- and a
    // half-printed number is worse than none, because it still reads as a value.
    col += T.ink * sui3Fixed(P, float2(rMaster.x + 8.0 * sB,
                                       rMaster.y + (rMaster.w - rMaster.y) * 0.5 - 5.0 * sB),
                             sB, master_rate, 2);

    if (mcLabelFits(rMute.y, sB))
        col += T.dim * sui3Text(P, float2(rMute.x, rMute.y - 11.0 * sB), sB,
            S_M,S_U,S_T,S_E,0,0,0,0,0,0,0,0);
    if (sui3RectIn(P, rMute) > 0.5 || sui3Frame(P, rMute) > 0.0) {
        col = lerp(col, float3(0,0,0), sui3RectIn(P, rMute));
        col += sui3Toggle(P, rMute, mute > 0.5, T);
    }

    // BURST plate. Not a host control; hit-tested in events.hlsl against the
    // same MC_RECT_BURST constant drawn here.
    float4 rBurst = mcPx(MC_RECT_BURST, R);
    if (mcLabelFits(rBurst.y, sB))
        col += T.dim * sui3Text(P, float2(rBurst.x, rBurst.y - 11.0 * sB), sB,
            S_B,S_U,S_R,S_S,S_T,0,0,0,0,0,0,0);
    if (sui3RectIn(P, rBurst) > 0.5 || sui3Frame(P, rBurst) > 0.0) {
        col = lerp(col, float3(0,0,0), sui3RectIn(P, rBurst));
        col += T.well * sui3RectIn(P, rBurst);
        // The plate fills with the LIVE ENVELOPE, so the control shows its own
        // decay rather than a momentary flash you can miss between frames.
        float fillX = lerp(rBurst.x, rBurst.z, env);
        col += T.accent * 0.55 * sui3RectIn(P, float4(rBurst.x, rBurst.y, fillX, rBurst.w));
        col += (env > 0.01 ? T.accent : T.rule) * sui3Frame(P, rBurst);
        col += (env > 0.01 ? T.accent : T.mid * 0.6) * sui3Brackets(P, rBurst, 10.0);
    }
    // fire count: proves the click landed even after the envelope has decayed
    col += T.dim * sui3Digits(P, float2(rBurst.x, rBurst.w + 4.0 * sB), sB, fires, 3);

    if (mcLabelFits(rBias.y, sB))
        col += T.dim * sui3Text(P, float2(rBias.x, rBias.y - 11.0 * sB), sB,
            S_B,S_I,S_A,S_S,0,0,0,0,0,0,0,0);
    if (sui3RectIn(P, rBias) > 0.5 || sui3Frame(P, rBias) > 0.0) {
        col = lerp(col, float3(0,0,0), sui3RectIn(P, rBias));
        // The raw pad value, drawn straight. The readout below prints the same
        // number and lfo_compute publishes the same number: zero flips, per the
        // Y-DIRECTION CONTRACT in sui3_core.hlsli.
        col += sui3Pad(P, rBias, motion_bias, T);
    }
    // Readout INSIDE the pad, bottom-left. Below the pad it shared a row with
    // the lane-1 AMP label and collided with it at 1600x900 -- and the row below
    // a control is exactly where the next control's label wants to be, so this
    // was going to keep colliding at some extent no matter how it was nudged.
    {
        float nw   = sui3FixedWidth(sB, 2);
        float padW = rBias.z - rBias.x;
        // Side by side when the pad is wide enough, stacked when it is not. The
        // pad is its own control bank and 3B's rule says a bank owes the user a
        // printed number, so the pair degrades in arrangement, never in
        // presence -- at 640x360 the row is 93px inside a 96px pad and the
        // second number was crossing the frame.
        bool  wide = padW >= 2.0 * nw + 13.0 * sB;
        float2 ra  = float2(rBias.x + 4.0 * sB,
                            rBias.w - 3.0 * sB - (wide ? 11.0 * sB : 22.0 * sB));
        col += T.ink * sui3Fixed(P, ra, sB, d.bias_x, 2);
        col += T.accent * sui3Fixed(P, wide ? ra + float2(nw + 5.0 * sB, 0.0)
                                            : ra + float2(0.0, 11.0 * sB),
                                    sB, d.bias_y, 2);
    }

    // ---- four lanes ---------------------------------------------------------
    float t = _Time * master_rate;

    [loop] for (int i = 0; i < 4; ++i) {
        float4 band = mcPx(mcLaneBand(i), R);
        float spd, amp, shp;
        laneParams(i, spd, amp, shp);
        float v = laneValue(i, d);

        // lane name
        int c0 = i == 0 ? S_P : i == 1 ? S_E : i == 2 ? S_C : S_P;
        int c1 = i == 0 ? S_R : i == 1 ? S_N : i == 2 ? S_A : S_U;
        int c2 = i == 0 ? S_O : i == 1 ? S_E : i == 2 ? S_M : S_L;
        int c3 = i == 0 ? S_M : i == 1 ? S_R : i == 2 ? S_SP : S_S;
        int c4 = i == 0 ? S_P : i == 1 ? S_G : i == 2 ? 0    : S_E;
        int c5 = i == 0 ? S_T : i == 1 ? S_Y : i == 2 ? 0    : 0;
        // Lane 0's label lives under the header block; the rest live in the
        // 0.040 gutter between bands.
        float bandGap = band.y - (i == 0 ? headY + blockH : mcPx(mcLaneBand(i - 1), R).w);
        bool  nameFits = mcLabelFits(bandGap, sB);
        if (nameFits)
            col += T.dim * sui3Text(P, float2(band.x, band.y - 12.0 * sB), sB,
                c0,c1,c2,c3,c4,c5,0,0,0,0,0,0);

        // trace well
        if (sui3RectIn(P, band) > 0.5 || sui3Frame(P, band) > 0.0) {
            col = lerp(col, float3(0,0,0), sui3RectIn(P, band));
            col += T.well * sui3RectIn(P, band);
            col += T.rule * 0.22 * sui3Graticule(P, band, float2(8.0, 4.0));
            col += T.rule * sui3Frame(P, band);
            col += T.mid * 0.55 * sui3Brackets(P, band, 12.0);

            // ANALYTIC TRACE: evaluate the lane at the time this pixel column
            // represents. One evaluation per pixel, no history walk.
            if (sui3RectIn(P, band) > 0.5) {
                float span = 4.0;                       // seconds across the well
                float u  = (P.x - band.x) / max(band.z - band.x, 1.0);
                float tt = t - (1.0 - u) * span * master_rate;
                float wv = evalLFO(tt, spd, amp, shp);
                if (mute > 0.5) wv = 0.0;
                if (i == 3) wv = saturate(wv + env * saturate(1.0 - (1.0 - u) * 6.0));
                float yv = lerp(band.w - 2.0, band.y + 2.0, wv);
                col += T.ink * 0.95 * sui3HairAt(P.y, yv);
                // filled area under the curve, very dim, for readability
                col += T.mid * 0.10 * step(yv, P.y);
            }
            // live head marker at the right edge
            float yhead = lerp(band.w - 2.0, band.y + 2.0, v);
            col += T.accent * sui3Disc(P, float2(band.z - 3.0, yhead), 2.4);
        }

        // Live numeric readout, attached to the lane it describes. It moves
        // INSIDE the well when the gutter is too thin rather than being dropped:
        // 3B's rule is that every control bank owes the user one printed number,
        // and the lane value is that number.
        float2 ra = nameFits
            ? float2(band.z - sui3FixedWidth(sB, 2), band.y - 12.0 * sB)
            : float2(band.z - sui3FixedWidth(sB, 2) - 3.0 * sB, band.y + 3.0 * sB);
        col += T.accent * sui3Fixed(P, ra, sB, v, 2);

        // rate / amp / shape controls, drawn from the host's own rects
        float4 rS = mcLaneSpeed(i, R);
        float4 rA = mcLaneAmp(i, R);
        float4 rH = mcLaneShape(i, R);

        // Above lane 0's rail is the master row; above every other lane's rail
        // is the previous lane's shape bank.
        float rowGap = rS.y - (i == 0 ? rMaster.w : mcLaneShape(i - 1, R).w);
        if (mcLabelFits(rowGap, sB))
            col += T.dim * sui3Text(P, float2(rS.x, rS.y - 11.0 * sB), sB, S_R,S_A,S_T,S_E,0,0,0,0,0,0,0,0);
        if (sui3RectIn(P, rS) > 0.5 || sui3Frame(P, rS) > 0.0) {
            col = lerp(col, float3(0,0,0), sui3RectIn(P, rS));
            col += sui3Rail(P, rS, (spd - 0.05) / 3.95, T);
        }
        col += T.ink * sui3Fixed(P, float2(rS.x + 3.0 * sB, rS.y + (rS.w - rS.y) * 0.5 - 5.0 * sB), sB, spd, 2);

        if (mcLabelFits(rowGap, sB))
            col += T.dim * sui3Text(P, float2(rA.x, rA.y - 11.0 * sB), sB, S_A,S_M,S_P,0,0,0,0,0,0,0,0,0);
        if (sui3RectIn(P, rA) > 0.5 || sui3Frame(P, rA) > 0.0) {
            col = lerp(col, float3(0,0,0), sui3RectIn(P, rA));
            col += sui3Rail(P, rA, amp, T);
        }
        col += T.ink * sui3Fixed(P, float2(rA.x + 3.0 * sB, rA.y + (rA.w - rA.y) * 0.5 - 5.0 * sB), sB, amp, 2);

        // shape reads as a 4-cell bank so the discrete choice is legible
        // The tightest gap on the desk: 0.015 normalized, 6px at a 403px panel.
        if (mcLabelFits(rH.y - rS.w, sB))
            col += T.dim * sui3Text(P, float2(rH.x, rH.y - 11.0 * sB), sB, S_S,S_H,S_A,S_P,S_E,0,0,0,0,0,0,0);
        int shp_i = (int)clamp(round(shp), 0.0, 3.0);
        float cw = (rH.z - rH.x) / 4.0;
        [loop] for (int k = 0; k < 4; ++k) {
            float4 rc = float4(rH.x + (float)k * cw, rH.y, rH.x + (float)(k + 1) * cw - 3.0, rH.w);
            if (sui3RectIn(P, rc) > 0.5 || sui3Frame(P, rc) > 0.0) {
                col = lerp(col, float3(0,0,0), sui3RectIn(P, rc));
                col += sui3BankCell(P, rc, k == shp_i, T);
            }
            col += (k == shp_i ? T.accent : T.dim)
                 * sui3Digits(P, float2(rc.x + cw * 0.5 - 3.0 * sB,
                                        rc.y + (rc.w - rc.y) * 0.5 - 5.0 * sB), sB, k, 1);
        }
    }

    // ---- energy readout -----------------------------------------------------
    float ey = R.y - pad - 11.0 * sB;
    col += T.dim * sui3Text(P, float2(pad, ey), sB,
        S_E,S_N,S_E,S_R,S_G,S_Y,0,0,0,0,0,0);
    col += T.accent * sui3Fixed(P, float2(pad + sui3TextWidth(7, sB), ey), sB, d.energy, 2);
    col += T.dim * sui3Text(P, float2(pad + sui3TextWidth(14, sB), ey), sB,
        S_P,S_U,S_L,S_S,S_E,0,0,0,0,0,0,0);
    col += T.accent * sui3Fixed(P, float2(pad + sui3TextWidth(20, sB), ey), sB, d.pulse, 2);

    col += T.rule * 0.7 * sui3Registration(P, R, 14.0 * sB);

    Out[tid.xy] = float4(saturate(col), 1.0);
}
