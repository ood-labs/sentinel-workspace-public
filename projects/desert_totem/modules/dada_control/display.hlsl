// Desert Warp Deck — sui3 port.
//
// Four live deformation axes remain on Canvas because they are performance
// gestures coupled directly to the field plot. Exact assembly, twist, surface,
// palette, haze, and accent setup remains in Properties.
#include "../_shared/ui/sui3_controls.hlsli"
#include "_ui.generated.hlsli"

struct Ctrl {
    float style; float melt; float sag; float spread;
    float explode; float primary; float secondary; float twist;
    float painterly; float facet; float hue; float heat;
    float scatter; float primary_mode; float secondary_mode; float marker;
};
StructuredBuffer<Ctrl> _Tex0 : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

float4 pxRect(float4 r, float2 R) {
    return float4(r.x * R.x, r.y * R.y, r.z * R.x, r.w * R.y);
}

float liveAxis(int i, Ctrl d) {
    return i == 0 ? d.melt / 0.6 : i == 1 ? d.sag / 0.6
         : i == 2 ? d.primary / 1.2 : d.secondary;
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

    Ctrl d = _Tex0[0];
    Sui3Theme T = sui3Theme(SUI3_AMBER);
    float3 col = T.field;
    col += T.rule * 0.13 * sui3Graticule(P, float4(0.0, 0.0, R.x, R.y), float2(16.0, 9.0));
    col += T.rule * 0.75 * sui3Registration(P, R, 14.0 * sB);

    if (R.x >= 700.0) {
        col += T.ink * sui3TextLong(P, float2(pad, pad), sT,
            S_T,S_O,S_T,S_E,S_M,S_SP,S_D,S_E,S_F,S_O,S_R,S_M,
            S_SP,S_D,S_E,S_C,S_K,0,0,0,0,0,0,0);
    } else {
        col += T.ink * sui3Text(P, float2(pad, pad), sT,
            S_D,S_E,S_F,S_O,S_R,S_M,S_SP,S_D,S_E,S_C,S_K,0);
    }
    col += T.dim * sui3TextLong(P, float2(pad, pad + 36.0 * sB), sB,
        S_D,S_E,S_F,S_O,S_R,S_M,S_A,S_T,S_I,S_O,S_N,S_SP,
        S_F,S_I,S_E,S_L,S_D,S_SP,S_SL,S_SP,S_L,S_I,S_V,S_E);

    if (R.x >= 700.0) {
        col += T.accent * sui3DigitsRight(P, R.x - pad, pad + 2.0 * sB, sN,
                                          (int)round(d.scatter), 2);
        col += T.dim * sui3Text(P, float2(R.x - pad - 58.0 * sB, pad + 27.0 * sB), sB,
            S_A,S_C,S_C,S_E,S_N,S_T,S_S,0,0,0,0,0);
    }

    float yRule = pad + 54.0 * sB;
    col += sui3Rule(P, R, yRule, pad, T);

    // Compact Properties readbacks: they remain live but are not duplicated
    // as Canvas widgets.
    float statusTop = yRule + 16.0 * sB;
    col += T.dim * sui3Text(P, float2(pad, statusTop), sB,
        S_S,S_P,S_R,S_E,S_A,S_D,0,0,0,0,0,0);
    col += T.ink * sui3Fixed(P, float2(pad + 55.0 * sB, statusTop), sB, d.spread, 2);
    col += T.dim * sui3Text(P, float2(pad + 122.0 * sB, statusTop), sB,
        S_E,S_X,S_P,S_L,S_O,S_D,S_E,0,0,0,0,0);
    col += T.ink * sui3Fixed(P, float2(pad + 187.0 * sB, statusTop), sB, d.explode, 2);
    col += T.dim * sui3Text(P, float2(pad + 254.0 * sB, statusTop), sB,
        S_R,S_O,S_T,0,0,0,0,0,0,0,0,0);
    col += T.ink * sui3Fixed(P, float2(pad + 302.0 * sB, statusTop), sB, d.twist, 2);

    // Deformation field: the four live axes alter amplitude, direction,
    // density, and the live markers from the same resolved record.
    float plotTop = statusTop + 28.0 * sB;
    float plotBottom = 0.565 * R.y;
    float4 plot = float4(pad, plotTop, R.x - pad, plotBottom);
    if (sui3RectIn(P, plot) > 0.5 || sui3Frame(P, plot) > 0.0) {
        col += T.well * sui3RectIn(P, plot);
        col += T.rule * 0.20 * sui3Graticule(P, plot, float2(12.0, 4.0));
        col += T.rule * sui3Frame(P, plot);
        col += T.mid * 0.55 * sui3Brackets(P, plot, 16.0 * sB);
    }

    float2 center = float2((plot.x + plot.z) * 0.5, (plot.y + plot.w) * 0.5);
    float2 span = float2((plot.z - plot.x) * 0.43, (plot.w - plot.y) * 0.38);
    float meltV = saturate(d.melt / 0.6);
    float sagV = saturate(d.sag / 0.6);
    float pV = saturate(d.primary / 1.2);
    float sV = saturate(d.secondary);
    float u = saturate((P.x - plot.x) / max(plot.z - plot.x, 1.0));
    float envelope = sin(u * 12.56637 + d.twist * 2.4) * span.y
                   * (0.10 + 0.40 * pV);
    float ripple = sin(u * 31.41593 + d.hue * 6.28318) * span.y
                 * (0.04 + 0.18 * sV);
    float sagCurve = sagV * span.y * (0.15 + 0.85 * abs(u - 0.5) * 2.0);
    float fieldY = center.y + envelope + ripple + sagCurve;
    float inPlot = sui3RectIn(P, plot);
    col += T.mid * (0.55 + 0.25 * meltV) * sui3HairAt(P.y, fieldY) * inPlot;
    col += T.rule * 0.65 * sui3HairAt(P.y, center.y) * inPlot;

    [loop] for (int i = 0; i < 4; ++i) {
        float v = saturate(liveAxis(i, d));
        float x = lerp(plot.x + 0.12 * (plot.z - plot.x),
                       plot.z - 0.12 * (plot.z - plot.x), (float)i / 3.0);
        float y = lerp(plot.w - 6.0 * sB, plot.y + 6.0 * sB, v);
        col += T.rule * 0.55 * sui3HairAt(P.x, x) * inPlot;
        col += T.accent * sui3Disc(P, float2(x, y), 2.4 * sB);
        col += T.accent * sui3Fixed(P, float2(x - 17.0 * sB, plot.y + 5.0 * sB),
                                    sB, v, 2);
    }

    // Surface telemetry, still editable in Properties.
    float surfaceY = plot.w + 17.0 * sB;
    if (R.x >= 700.0) {
        col += T.dim * sui3Text(P, float2(pad, surfaceY), sB,
            S_P,S_A,S_I,S_N,S_T,0,0,0,0,0,0,0);
        col += T.ink * sui3Fixed(P, float2(pad + 50.0 * sB, surfaceY), sB, d.painterly, 2);
        col += T.dim * sui3Text(P, float2(pad + 117.0 * sB, surfaceY), sB,
            S_F,S_A,S_C,S_E,S_T,0,0,0,0,0,0,0);
        col += T.ink * sui3Fixed(P, float2(pad + 167.0 * sB, surfaceY), sB, d.facet, 2);
        col += T.dim * sui3Text(P, float2(pad + 234.0 * sB, surfaceY), sB,
            S_H,S_U,S_E,0,0,0,0,0,0,0,0,0);
        col += T.ink * sui3Fixed(P, float2(pad + 264.0 * sB, surfaceY), sB, d.hue, 2);
        col += T.dim * sui3Text(P, float2(pad + 331.0 * sB, surfaceY), sB,
            S_H,S_E,S_A,S_T,0,0,0,0,0,0,0,0);
        col += T.ink * sui3Fixed(P, float2(pad + 370.0 * sB, surfaceY), sB, d.heat, 2);
    }

    float4 rMelt = pxRect(UI_RECT_MELT_MACRO, R);
    float4 rSag = pxRect(UI_RECT_SAG_MACRO, R);
    float4 rPrimary = pxRect(UI_RECT_WARP_PRIMARY, R);
    float4 rSecondary = pxRect(UI_RECT_WARP_SECONDARY, R);

    col += T.dim * sui3Text(P, float2(rMelt.x, rMelt.y - 14.0 * sB), sB,
        S_M,S_E,S_L,S_T,0,0,0,0,0,0,0,0);
    col += T.dim * sui3Text(P, float2(rSag.x, rSag.y - 14.0 * sB), sB,
        S_S,S_A,S_G,0,0,0,0,0,0,0,0,0);
    col += T.dim * sui3Text(P, float2(rPrimary.x, rPrimary.y - 14.0 * sB), sB,
        S_P,S_R,S_I,S_M,S_A,S_R,S_Y,0,0,0,0,0);
    col += T.dim * sui3Text(P, float2(rSecondary.x, rSecondary.y - 14.0 * sB), sB,
        S_S,S_E,S_C,S_O,S_N,S_D,S_A,S_R,S_Y,0,0,0);

    col += sui3Rail(P, rMelt, d.melt / 0.6, T);
    col += sui3Rail(P, rSag, d.sag / 0.6, T);
    col += sui3Rail(P, rPrimary, d.primary / 1.2, T);
    col += sui3Rail(P, rSecondary, d.secondary, T);
    col += T.accent * sui3Fixed(P, float2(rMelt.z - sui3FixedWidth(sB, 2) - 5.0 * sB,
                                          rMelt.y + 7.0 * sB), sB, d.melt, 2);
    col += T.accent * sui3Fixed(P, float2(rSag.z - sui3FixedWidth(sB, 2) - 5.0 * sB,
                                          rSag.y + 7.0 * sB), sB, d.sag, 2);
    col += T.accent * sui3Fixed(P, float2(rPrimary.z - sui3FixedWidth(sB, 2) - 5.0 * sB,
                                          rPrimary.y + 7.0 * sB), sB, d.primary, 2);
    col += T.accent * sui3Fixed(P, float2(rSecondary.z - sui3FixedWidth(sB, 2) - 5.0 * sB,
                                          rSecondary.y + 7.0 * sB), sB, d.secondary, 2);

    float footY = R.y - pad - 11.0 * sB;
    col += T.dim * sui3TextLong(P, float2(pad, footY), sB,
        S_S,S_E,S_T,S_U,S_P,S_SP,S_I,S_N,S_SP,S_P,S_R,S_O,
        S_P,S_E,S_R,S_T,S_I,S_E,S_S,0,0,0,0,0);

    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
