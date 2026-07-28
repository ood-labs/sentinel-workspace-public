// Strata Composition Desk — sui3 port.
//
// Four live plate rails remain on Canvas because their coupled balance is a
// performance gesture. Exact seed, palette, deformation, layout, and feature
// setup remain in Properties.
#include "../_shared/ui/sui3_controls.hlsli"
#include "_ui.generated.hlsli"

struct Ctrl {
    float seed; float melt; float twist; float marble_warp;
    float spread; float wire_scale; float palette; float blob_mix;
    float marble_mix; float wire_mix; float marks_mix; float feature_enabled;
    float feature_gain; float feature_count; float marker; float pad;
};

StructuredBuffer<Ctrl> _Tex0 : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

float4 pxRect(float4 r, float2 R) {
    return float4(r.x * R.x, r.y * R.y, r.z * R.x, r.w * R.y);
}

float plateValue(int i, Ctrl d) {
    return i == 0 ? d.blob_mix : i == 1 ? d.marble_mix
         : i == 2 ? d.wire_mix : d.marks_mix;
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;

    float2 R = _Resolution.xy;
    float2 P = (float2)tid.xy + 0.5;
    float k = min(R.x / 1280.0, R.y / 720.0);
    float sB = k >= 2.6 ? 3.0 : k >= 1.7 ? 2.0 : 1.0;
    float sN = 2.0 * sB;
    float sT = 3.0 * sB;
    float pad = max(12.0, 0.026 * R.x);
    bool compactHeight = R.y < 320.0;

    Ctrl d = _Tex0[0];
    Sui3Theme T = sui3Theme(SUI3_AMBER);
    float3 col = T.field;
    col += T.rule * 0.13 * sui3Graticule(P, float4(0.0, 0.0, R.x, R.y), float2(16.0, 9.0));
    col += T.rule * 0.75 * sui3Registration(P, R, 14.0 * sB);

    if (R.x >= 700.0) {
        col += T.ink * sui3TextLong(P, float2(pad, pad), sT,
            S_S,S_T,S_R,S_A,S_T,S_A,S_SP,S_C,S_O,S_M,S_P,S_O,
            S_S,S_I,S_T,S_I,S_O,S_N,S_SP,S_D,S_E,S_S,S_K,0);
    } else {
        col += T.ink * sui3Text(P, float2(pad, pad), sT,
            S_S,S_T,S_R,S_A,S_T,S_A,0,0,0,0,0,0);
    }
    if (!compactHeight) {
        col += T.dim * sui3TextLong(P, float2(pad, pad + 36.0 * sB), sB,
            S_P,S_R,S_E,S_M,S_U,S_L,S_T,S_I,S_P,S_L,S_I,S_E,
            S_D,S_SP,S_P,S_L,S_A,S_T,S_E,S_S,0,0,0,0);
    }

    if (R.x >= 700.0) {
        float countX = R.x - pad - sui3FixedWidth(sN, 0);
        col += T.accent * sui3DigitsRight(P, R.x - pad, pad + 2.0 * sB, sN,
                                          (int)round(d.feature_count), 3);
        col += T.dim * sui3Text(P, float2(countX, pad + 27.0 * sB), sB,
            S_C,S_O,S_R,S_N,S_E,S_R,S_S,0,0,0,0,0);
    }

    float yRule = pad + (compactHeight ? 30.0 : 54.0) * sB;
    col += sui3Rule(P, R, yRule, pad, T);

    // Compact setup readbacks. These values remain editable in Properties.
    float statusTop = yRule + 16.0 * sB;
    if (!compactHeight) {
    col += T.dim * sui3Text(P, float2(pad, statusTop), sB,
        S_S,S_E,S_E,S_D,0,0,0,0,0,0,0,0);
    col += T.ink * sui3Fixed(P, float2(pad + 38.0 * sB, statusTop), sB, d.seed, 1);
    col += T.dim * sui3Text(P, float2(pad + 100.0 * sB, statusTop), sB,
        S_P,S_A,S_L,0,0,0,0,0,0,0,0,0);
    col += T.ink * sui3Digits(P, float2(pad + 127.0 * sB, statusTop), sB,
                              (int)round(d.palette), 1);
    col += T.dim * sui3Text(P, float2(pad + 162.0 * sB, statusTop), sB,
        S_M,S_E,S_L,S_T,0,0,0,0,0,0,0,0);
    col += T.ink * sui3Fixed(P, float2(pad + 197.0 * sB, statusTop), sB, d.melt, 2);
    col += T.dim * sui3Text(P, float2(pad + 264.0 * sB, statusTop), sB,
        S_T,S_W,S_I,S_S,S_T,0,0,0,0,0,0,0);
    col += T.ink * sui3Fixed(P, float2(pad + 306.0 * sB, statusTop), sB, d.twist, 2);
    }

    // Plate composition plot. Each layer owns one vertical slot; thickness,
    // bracket reach, and live marker all derive from the same resolved mix.
    float plotTop = compactHeight ? yRule + 12.0 * sB : statusTop + 28.0 * sB;
    float plotBottom = (compactHeight ? 0.55 : 0.565) * R.y;
    float4 plot = float4(pad, plotTop, R.x - pad, plotBottom);
    if (sui3RectIn(P, plot) > 0.5 || sui3Frame(P, plot) > 0.0) {
        col += T.well * sui3RectIn(P, plot);
        col += T.rule * 0.20 * sui3Graticule(P, plot, float2(12.0, 4.0));
        col += T.rule * sui3Frame(P, plot);
        col += T.mid * 0.55 * sui3Brackets(P, plot, 16.0 * sB);
    }

    float centerX = (plot.x + plot.z) * 0.5;
    float laneH = (plot.w - plot.y) * 0.25;
    [loop] for (int i = 0; i < 4; ++i) {
        float raw = plateValue(i, d);
        float v = saturate(raw * 0.5);
        float y0 = plot.y + laneH * (float)i;
        float yc = y0 + laneH * 0.5;
        float halfW = (plot.z - plot.x) * (0.12 + 0.36 * v);
        float wobble = sin((P.x - plot.x) * 0.018 + d.seed * 0.17 + (float)i)
                     * laneH * (0.05 + 0.11 * d.melt);
        float band = step(abs(P.y - (yc + wobble)), 1.0 + 2.0 * v)
                   * step(abs(P.x - centerX), halfW);
        col += T.mid * (0.35 + 0.35 * v) * band;
        col += T.rule * 0.55 * sui3HairAt(P.y, y0)
             * step(plot.x, P.x) * step(P.x, plot.z);
        col += T.accent * sui3Disc(P, float2(centerX + halfW, yc), 2.3 * sB);
        col += T.accent * sui3Fixed(P, float2(plot.x + 7.0 * sB, y0 + 4.0 * sB),
                                    sB, raw, 2);
    }

    // Feature status is telemetry, not a duplicate toggle.
    float featureY = plot.w + 17.0 * sB;
    if (!compactHeight) {
    col += T.dim * sui3Text(P, float2(pad, featureY), sB,
        S_F,S_E,S_A,S_T,S_U,S_R,S_E,S_SP,S_T,S_H,S_R,S_D);
    float enabled = d.feature_enabled > 0.5 ? 1.0 : 0.0;
    col += (enabled > 0.5 ? T.accent : T.rule)
         * sui3HairAt(P.x, pad + 93.0 * sB)
         * step(featureY, P.y) * step(P.y, featureY + 11.0 * sB);
    col += T.ink * sui3Digits(P, float2(pad + 108.0 * sB, featureY), sB,
                              (int)round(d.feature_count), 3);
    col += T.dim * sui3Text(P, float2(pad + 151.0 * sB, featureY), sB,
        S_G,S_A,S_I,S_N,0,0,0,0,0,0,0,0);
    col += T.ink * sui3Fixed(P, float2(pad + 190.0 * sB, featureY), sB,
                             d.feature_gain, 2);
    }

    float4 rBlob = pxRect(UI_RECT_BLOB_MIX, R);
    float4 rMarble = pxRect(UI_RECT_MARBLE_MIX, R);
    float4 rWire = pxRect(UI_RECT_WIRE_MIX, R);
    float4 rMarks = pxRect(UI_RECT_MARKS_MIX, R);

    col += T.dim * sui3Text(P, float2(rBlob.x, rBlob.y - 14.0 * sB), sB,
        S_S,S_C,S_U,S_L,S_P,S_T,S_U,S_R,S_E,0,0,0);
    col += T.dim * sui3Text(P, float2(rMarble.x, rMarble.y - 14.0 * sB), sB,
        S_M,S_A,S_R,S_B,S_L,S_E,0,0,0,0,0,0);
    col += T.dim * sui3Text(P, float2(rWire.x, rWire.y - 14.0 * sB), sB,
        S_W,S_I,S_R,S_E,0,0,0,0,0,0,0,0);
    col += T.dim * sui3Text(P, float2(rMarks.x, rMarks.y - 14.0 * sB), sB,
        S_M,S_A,S_R,S_K,S_S,0,0,0,0,0,0,0);

    col += sui3Rail(P, rBlob, d.blob_mix * 0.5, T);
    col += sui3Rail(P, rMarble, d.marble_mix * 0.5, T);
    col += sui3Rail(P, rWire, d.wire_mix * 0.5, T);
    col += sui3Rail(P, rMarks, d.marks_mix * 0.5, T);

    col += T.accent * sui3Fixed(P, float2(rBlob.z - sui3FixedWidth(sB, 2) - 5.0 * sB,
                                          rBlob.y + 7.0 * sB), sB, d.blob_mix, 2);
    col += T.accent * sui3Fixed(P, float2(rMarble.z - sui3FixedWidth(sB, 2) - 5.0 * sB,
                                          rMarble.y + 7.0 * sB), sB, d.marble_mix, 2);
    col += T.accent * sui3Fixed(P, float2(rWire.z - sui3FixedWidth(sB, 2) - 5.0 * sB,
                                          rWire.y + 7.0 * sB), sB, d.wire_mix, 2);
    col += T.accent * sui3Fixed(P, float2(rMarks.z - sui3FixedWidth(sB, 2) - 5.0 * sB,
                                          rMarks.y + 7.0 * sB), sB, d.marks_mix, 2);

    float footY = R.y - pad - 11.0 * sB;
    if (!compactHeight) {
    col += T.dim * sui3TextLong(P, float2(pad, footY), sB,
        S_S,S_E,S_T,S_U,S_P,S_SP,S_I,S_N,S_SP,S_P,S_R,S_O,
        S_P,S_E,S_R,S_T,S_I,S_E,S_S,0,0,0,0,0);
    }

    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
