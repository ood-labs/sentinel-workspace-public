// Four connected trails. All plotting geometry comes from sui3_trace.hlsli.

#include "layout.hlsli"
#include "../_shared/ui/sui3_text.hlsli"
#include "../_shared/ui/sui3_theme.hlsli"

StructuredBuffer<float4> Trace     : register(t0);
RWTexture2D<float4>      OutputUAV : register(u0);

float stTypeH(float u) { return max(floor(u), 1.0); }
float stTypeB(float u) { return max(floor(u * 0.9), 1.0); }

// Gutter sized from the widest thing printed in it, never a fixed multiple of u.
float stGutter(float u) {
    float sB = stTypeB(u);
    return 6.0 * u + sui3TextWidth(3, sB) + sui3FixedWidth(sB, 2) + 6.0 * u;
}

float4 stLaneRect(float2 R, uint ch) {
    float u      = stUI(R.y);
    float top    = 11.0 * stTypeH(u) + 6.0 * u;
    float bottom = R.y - (11.0 * stTypeB(u) + 6.0 * u);
    float h      = (bottom - top) / (float)ST_CHANS;
    float y0     = top + (float)ch * h;
    return float4(stGutter(u), y0 + 2.0 * u, R.x - 6.0 * u, y0 + h - 4.0 * u);
}

float stSample(uint ch, int i, float writeIdx) {
    i = sui3TraceClampIndex(i, writeIdx);
    if (i < 0) return 0.0;
    return Trace[sui3TraceAt(stTraceBase(ch), ST_CAP, (uint)i)].x;
}

// Value plotted by the column at pixel x.
//
// Interpolates when the plot is upsampling and max-reduces when it is not. A
// cook-rate signal on a wide panel is almost always upsampling -- 481 samples
// across 1600 px here -- and max-reducing that draws a smooth LFO as a
// staircase with a three-pixel tread.
float stColumn(uint ch, float px, float4 r, float nShow, float writeIdx, float fs) {
    float v;
    if (sui3TraceUpsampling(r.x, r.z, nShow)) {
        float pos = sui3TraceFrac(px, r.x, r.z, nShow, writeIdx);
        int   i0  = (int)floor(pos);
        v = lerp(stSample(ch, i0, writeIdx),
                 stSample(ch, i0 + 1, writeIdx), frac(pos));
    } else {
        int i0, i1;
        sui3TraceSpan(px, r.x, r.z, nShow, writeIdx, i0, i1);
        v = 0.0;
        [loop] for (int i = i0; i <= i1; ++i) {
            v = max(v, stSample(ch, i, writeIdx));
        }
    }
    return saturate(v / max(fs, 1e-6));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    float2 R = _Resolution.xy;
    if (tid.x >= (uint)R.x || tid.y >= (uint)R.y) return;

    float2 P = float2(tid.xy) + 0.5;
    float  u = stUI(R.y);
    Sui3Theme T = sui3Theme(accent_color.rgb);
    float3 col = T.field;

    float sH = stTypeH(u);
    float sB = stTypeB(u);
    float gB = SUI3_ADVANCE * sB;

    // ---- header ----------------------------------------------------------
    float hy = 3.0 * u;
    col += T.ink * sui3TextLong(P, float2(6.0 * u, hy), sH,
                                S_S, S_I, S_G, S_N, S_A, S_L, S_SP, S_T, S_R, S_A, S_I, S_L,
                                S_S, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);

    float x = 6.0 * u + sui3TextWidth(15, sH);
    col += T.dim * sui3Text(P, float2(x, hy), sB, S_S, S_P, S_A, S_N, 0, 0, 0, 0, 0, 0, 0, 0);
    col += T.mid * sui3Fixed(P, float2(x + 5.0 * gB, hy), sB, span_seconds, 2);
    col += T.dim * sui3Text(P, float2(x + 11.0 * gB, hy), sB, S_S, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    x += 14.0 * gB;

    if (bipolar) {
        col += T.dim * sui3Text(P, float2(x, hy), sB,
                                S_B, S_I, S_P, S_O, S_L, S_A, S_R, 0, 0, 0, 0, 0);
    } else if (autoscale) {
        col += T.mid * sui3Text(P, float2(x, hy), sB,
                                S_A, S_U, S_T, S_O, S_S, S_C, S_A, S_L, S_E, 0, 0, 0);
    } else {
        col += T.dim * sui3Text(P, float2(x, hy), sB,
                                S_F, S_I, S_X, S_E, S_D, 0, 0, 0, 0, 0, 0, 0);
    }

    // ---- footer: the sample clock, which here is the COOK rate -------------
    float dt = Trace[stStateA(0u)].w;
    float nShow = Trace[stStateB(0u)].w;
    float fy = R.y - (11.0 * sB + 3.0 * u);
    float fx = 6.0 * u;
    col += T.dim * sui3Text(P, float2(fx, fy), sB,
                            S_C, S_O, S_O, S_K, S_SP, S_H, S_Z, 0, 0, 0, 0, 0);
    float hz = (dt > 0.0) ? (1.0 / dt) : 0.0;
    col += T.mid * sui3DigitsRight(P, fx + 12.0 * gB, fy, sB, (int)round(hz), 4);
    fx += 15.0 * gB;
    col += T.dim * sui3Text(P, float2(fx, fy), sB,
                            S_S, S_A, S_M, S_P, S_L, S_E, S_S, 0, 0, 0, 0, 0);
    col += T.mid * sui3DigitsRight(P, fx + 12.0 * gB, fy, sB, (int)round(nShow), 4);

    // ---- channels ----------------------------------------------------------
    [loop] for (uint ch = 0u; ch < ST_CHANS; ++ch) {
        float4 r = stLaneRect(R, ch);
        if (r.w - r.y < 4.0 || r.z - r.x < 4.0) continue;

        float4 A = Trace[stStateA(ch)];
        float4 B = Trace[stStateB(ch)];
        float writeIdx = A.y;
        float fs       = max(B.y, 1e-6);

        col = lerp(col, T.well, sui3RectIn(P, r) * 0.85);
        col += T.rule * 0.6 * sui3Graticule(P, r, float2(8.0, 2.0));

        // Zero line. In bipolar mode it is the real zero at mid height, and it
        // has to be visible or a signed trace cannot be read at all.
        if (bipolar) {
            col += T.rule * 1.4 * sui3StripRef(P, r, 0.5, 3.0 * u);
        }

        float ly = r.y + 1.0 * u;
        col += T.dim * sui3Text(P, float2(6.0 * u, ly), sH,
                                S_C, S_H, (int)(S_0 + 1 + (int)ch), 0, 0, 0, 0, 0, 0, 0, 0, 0);

        float fsy = ly + 12.0 * sH;
        col += T.dim * sui3Text(P, float2(6.0 * u, fsy), sB,
                                S_F, S_S, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
        col += T.mid * sui3Fixed(P, float2(6.0 * u + 3.0 * gB, fsy), sB, fs, 2);

        // The channel's current value, straight from the sampler rather than
        // re-derived from the plot, so the dot cannot disagree with the trail.
        float nowNorm = saturate(B.x / fs);

        if (P.x >= r.x && P.x <= r.z && nShow > 0.0) {
            float nHere = stColumn(ch, P.x,       r, nShow, writeIdx, fs);
            float nNext = stColumn(ch, P.x + 1.0, r, nShow, writeIdx, fs);

            // A faint area under the trail gives the curve a body to read
            // against without competing with it.
            col += T.mid * 0.14 * sui3StripFill(P, r, nHere);
            col += T.ink * 0.95 * sui3StripTrail(P, r, nHere, nNext, 1.0);

            // Accent marks the live value: a dot riding the right-hand edge of
            // the trail, which is the one point that is actually "now".
            // A 2px slice of the trail was the first attempt and was invisible
            // at every panel size.
            float2 live = float2(r.z - 2.0 * u, sui3StripY(r, nowNorm));
            col += T.accent * sui3Disc(P, live, 2.0 * u);
        }

        col += T.rule * sui3Frame(P, r);
    }

    col += T.rule * 0.5 * sui3Registration(P, R, 6.0 * u);

    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
