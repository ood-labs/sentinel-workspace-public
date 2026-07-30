// AUTOPSIA — performance deck surface.
//
// Three macro pads and a look bank. Each pad is a real host-owned xypad control;
// this shader draws it, the host owns capture and commit. Nothing here is a
// duplicate of a Properties slider: each pad moves several parameters at once
// along a curated creative axis, which a single numeric row cannot express.
//
// ALL pad geometry is computed in PIXELS, not normalized units. This panel is
// `follow_panel`, so its extent and aspect change with the dock; normalized
// drawing stretched the reticles into ellipses and made stroke weights drift.
// Pixel space keeps circles circular and every rule exactly one pixel.
#include "../_shared/au_hud/au_text.hlsli"

RWTexture2D<float4> Out : register(u0);
StructuredBuffer<float4> Deck : register(t0);

float aa(float d, float w) { return 1.0 - smoothstep(w * 0.5 - 0.5, w * 0.5 + 0.5, d); }

float rectInPx(float2 P, float4 rp) {
    return step(rp.x, P.x) * step(P.x, rp.z) * step(rp.y, P.y) * step(P.y, rp.w);
}

// 1px hairline frame with short corner brackets
float3 frameAndBrackets(float2 P, float4 rp, float3 line_, float3 bracket) {
    float2 d = min(P - rp.xy, rp.zw - P);
    float edge = rectInPx(P, rp) * step(min(d.x, d.y), 1.0);
    float3 c = line_ * edge;

    float bl = 14.0;
    float nearX = min(P.x - rp.x, rp.z - P.x);
    float nearY = min(P.y - rp.y, rp.w - P.y);
    float corner = rectInPx(P, rp)
                 * (step(nearX, 1.0) * step(nearY, bl) + step(nearY, 1.0) * step(nearX, bl));
    return c + bracket * saturate(corner);
}

float3 drawPad(float2 P, float4 rp, float2 val, float3 ink, float3 dim, float3 accent) {
    float3 c = float3(0.0125, 0.0135, 0.0145);

    float2 size = rp.zw - rp.xy;
    float2 l = (P - rp.xy) / max(size, 1.0);

    // graticule: quarters, drawn as exact hairlines
    float2 q = abs(frac(l * 4.0) - 0.5) * (size / 4.0);
    c += float3(0.038, 0.039, 0.037) * aa(min(q.x, q.y), 1.0);
    // centre axes, slightly stronger
    c += float3(0.058, 0.060, 0.056) * aa(abs(P.x - (rp.x + rp.z) * 0.5), 1.0);
    c += float3(0.058, 0.060, 0.056) * aa(abs(P.y - (rp.y + rp.w) * 0.5), 1.0);

    // The stored value is already Y-up. Pixel Y grows downward, so value 1 maps
    // to the top edge and value 0 to the bottom edge.
    float2 vpx = lerp(rp.xy, rp.zw, float2(val.x, 1.0 - val.y));
    float2 dp = P - vpx;
    float dist = length(dp);

    // reticle: gapped crosshair, thin ring, centre dot
    float gap = 5.0, arm = 24.0;
    float hx = aa(abs(dp.y), 1.0) * step(gap, abs(dp.x)) * step(abs(dp.x), arm);
    float hy = aa(abs(dp.x), 1.0) * step(gap, abs(dp.y)) * step(abs(dp.y), arm);
    c += ink * saturate(hx + hy) * 0.85;

    c += accent * aa(abs(dist - 8.5), 1.2) * 0.95;          // thin, not a donut
    c += float3(0.10, 0.102, 0.098) * aa(abs(dist - 17.0), 1.0);
    c += ink * aa(dist, 2.0) * 0.9;

    // edge readout: where the value sits on each axis
    c += accent * aa(abs(P.x - vpx.x), 1.0) * step(P.y, rp.y + 5.0) * 0.9;
    c += accent * aa(abs(P.y - vpx.y), 1.0) * step(P.x, rp.x + 5.0) * 0.9;

    // measurement ticks along the top and left edges
    float tickX = aa(abs(frac((P.x - rp.x) / size.x * 16.0) - 0.5) * size.x / 16.0, 1.0)
                * step(P.y, rp.y + 3.0);
    float tickY = aa(abs(frac((P.y - rp.y) / size.y * 10.0) - 0.5) * size.y / 10.0, 1.0)
                * step(P.x, rp.x + 3.0);
    c += dim * (tickX + tickY) * 0.5;

    return c;
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float2 P = uv * _Resolution.xy;
    float2 R = _Resolution.xy;

    float3 ink = float3(0.90, 0.905, 0.88);
    float3 dim = float3(0.38, 0.385, 0.37);
    float3 line_ = float3(0.22, 0.225, 0.215);
    float3 col = float3(0.0055, 0.006, 0.0065);

    float4 d0 = Deck[0];
    float4 d1 = Deck[1];
    int look = (int)round(clamp(d1.z, 0.0, 3.0));

    // rects mirror viewport.controls exactly
    float4 padsN[3] = {
        float4(0.040, 0.200, 0.320, 0.760),
        float4(0.355, 0.200, 0.635, 0.760),
        float4(0.670, 0.200, 0.950, 0.760)
    };
    float2 vals[3] = { d0.xy, d0.zw, d1.xy };

    [unroll] for (int i = 0; i < 3; ++i) {
        float4 rp = float4(padsN[i].xy * R, padsN[i].zw * R);
        if (rectInPx(P, rp) > 0.5) col = drawPad(P, rp, vals[i], ink, dim, accent_color);
        col += frameAndBrackets(P, rp, line_, float3(0.62, 0.625, 0.60));
    }

    // ---- look bank: underline the active look, never fill it ---------------
    float4 looksN[4] = {
        float4(0.040, 0.845, 0.255, 0.930),
        float4(0.275, 0.845, 0.490, 0.930),
        float4(0.510, 0.845, 0.725, 0.930),
        float4(0.745, 0.845, 0.950, 0.930)
    };
    [unroll] for (int b = 0; b < 4; ++b) {
        float4 rp = float4(looksN[b].xy * R, looksN[b].zw * R);
        bool active = (b == look);
        if (rectInPx(P, rp) > 0.5) col = float3(0.0105, 0.0112, 0.0120);
        col += frameAndBrackets(P, rp, active ? accent_color * 0.85 : line_,
                                active ? accent_color : float3(0.45, 0.455, 0.44));
        if (active) {
            col += accent_color * rectInPx(P, rp) * step(rp.w - 3.0, P.y) * 0.9;
        }
    }

    // ---- header --------------------------------------------------------------
    col += ink * auText(P, float2(22.0, 20.0), 2.0, G_D,G_E,G_C,G_K, 0,0,0,0,0,0,0,0);
    col += dim * auText(P, float2(98.0, 27.0), 1.0,
        G_M,G_A,G_C,G_R,G_O,G_SP,G_P,G_A,G_D,G_S, 0,0);
    col += line_ * aa(abs(P.y - 52.0), 1.0) * step(20.0, P.x) * step(P.x, R.x - 20.0);

    // ---- pad labels ----------------------------------------------------------
    int titles[3][7] = {
        { G_F,G_I,G_E,G_L,G_D, 0, 0 },
        { G_R,G_E,G_L,G_I,G_E,G_F, 0 },
        { G_P,G_R,G_I,G_N,G_T, 0, 0 }
    };
    int axes[3][11] = {
        { G_S,G_P,G_R,G_E,G_A,G_D,G_SL,G_C,G_E,G_L,G_L },
        { G_H,G_E,G_I,G_G,G_H,G_T,G_SL,G_L,G_I,G_N,G_E },
        { G_G,G_H,G_O,G_S,G_T,G_SL,G_M,G_I,G_X, 0, 0 }
    };
    [unroll] for (int t = 0; t < 3; ++t) {
        float x = padsN[t].x * R.x;
        col += ink * auText(P, float2(x, padsN[t].y * R.y - 14.0), 1.0,
            titles[t][0], titles[t][1], titles[t][2], titles[t][3],
            titles[t][4], titles[t][5], titles[t][6], 0, 0, 0, 0, 0);
        // Caption and values share ONE line: the gap between the pad and the
        // section rule shrinks with the panel, and two stacked lines collided
        // with the rule once the dock got short.
        float capY = padsN[t].w * R.y + 6.0;
        col += dim * auText(P, float2(x, capY), 1.0,
            axes[t][0], axes[t][1], axes[t][2], axes[t][3], axes[t][4], axes[t][5],
            axes[t][6], axes[t][7], axes[t][8], axes[t][9], axes[t][10], 0);
        col += ink * auFixed(P, float2(x + 92.0, capY), 1.0, vals[t].x);
        col += ink * auFixed(P, float2(x + 136.0, capY), 1.0, vals[t].y);
    }

    // ---- look labels ---------------------------------------------------------
    // centred in the button rect, so it never rides the border
    float lbY = (0.845 + 0.930) * 0.5 * R.y - 5.5;
    col += (look == 0 ? accent_color : dim) * auText(P, float2(looksN[0].x * R.x + 14.0, lbY), 1.0,
        G_I,G_M,G_P,G_R,G_E,G_S,G_S, 0,0,0,0,0);
    col += (look == 1 ? accent_color : dim) * auText(P, float2(looksN[1].x * R.x + 14.0, lbY), 1.0,
        G_I,G_N,G_S,G_P,G_E,G_C,G_T, 0,0,0,0,0);
    col += (look == 2 ? accent_color : dim) * auText(P, float2(looksN[2].x * R.x + 14.0, lbY), 1.0,
        G_R,G_E,G_G,G_I,G_S,G_T,G_E,G_R, 0,0,0,0);
    col += (look == 3 ? accent_color : dim) * auText(P, float2(looksN[3].x * R.x + 14.0, lbY), 1.0,
        G_S,G_E,G_C,G_T,G_I,G_O,G_N, 0,0,0,0,0);

    col += line_ * aa(abs(P.y - (0.845 * R.y - 16.0)), 1.0)
         * step(20.0, P.x) * step(P.x, R.x - 20.0);

    // outer frame
    float2 e = min(P, R - P);
    col += line_ * step(min(e.x, e.y), 1.0) * step(4.0, min(e.x, e.y));

    Out[tid.xy] = float4(saturate(col), 1.0);
}
