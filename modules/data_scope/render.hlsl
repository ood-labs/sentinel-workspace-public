// Draws three strip charts. Every mark comes from sui3_trace.hlsli; this pass
// contributes layout, type, and colour and nothing else.

#include "layout.hlsli"
#include "../_shared/ui/sui3_text.hlsli"
#include "../_shared/ui/sui3_theme.hlsli"

StructuredBuffer<float4> Trace     : register(t0);
RWTexture2D<float4>      OutputUAV : register(u0);

// Type scales. Integer, from the panel height, so the bitmap face is never
// resampled.
float dsTypeH(float u) { return max(floor(u), 1.0); }
float dsTypeB(float u) { return max(floor(u * 0.9), 1.0); }

// Left gutter, sized from the widest thing printed in it rather than as a fixed
// multiple of u. The first cut used 34u while the text scaled on its own: they
// agreed at one panel height and the FS readout overflowed its column at every
// larger one.
float dsGutter(float u) {
    float sB = dsTypeB(u);
    return 6.0 * u + sui3TextWidth(3, sB) + sui3FixedWidth(sB, 2) + 6.0 * u;
}

float4 dsLaneRect(float2 R, uint lane) {
    float u      = dsUI(R.y);
    float top    = 11.0 * dsTypeH(u) + 6.0 * u;
    float bottom = R.y - (11.0 * dsTypeB(u) + 6.0 * u);
    float h      = (bottom - top) / (float)DS_LANES;
    float y0     = top + (float)lane * h;
    return float4(dsGutter(u), y0 + 2.0 * u, R.x - 6.0 * u, y0 + h - 4.0 * u);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    float2 R = _Resolution.xy;
    if (tid.x >= (uint)R.x || tid.y >= (uint)R.y) return;

    float2 P = float2(tid.xy) + 0.5;
    float  u = dsUI(R.y);
    Sui3Theme T = sui3Theme(accent_color.rgb);
    float3 col = T.field;

    float sH = dsTypeH(u);
    float sB = dsTypeB(u);
    float gB = SUI3_ADVANCE * sB;   // one glyph advance, the header/footer unit

    // ---- header ----------------------------------------------------------
    float hy = 3.0 * u;
    col += T.ink * sui3Text(P, float2(6.0 * u, hy), sH,
                            S_D, S_A, S_T, S_A, S_SP, S_S, S_C, S_O, S_P, S_E, 0, 0);

    // Everything after the title is laid out on a glyph grid with explicit gaps.
    // Deriving each item's origin from the previous item's width is what packed
    // "03.00S" hard against "AUTO" on the first capture.
    float x = 6.0 * u + sui3TextWidth(12, sH);

    col += T.dim * sui3Text(P, float2(x, hy), sB, S_S, S_P, S_A, S_N, 0, 0, 0, 0, 0, 0, 0, 0);
    col += T.mid * sui3Fixed(P, float2(x + 5.0 * gB, hy), sB, span_seconds, 2);
    col += T.dim * sui3Text(P, float2(x + 11.0 * gB, hy), sB, S_S, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    x += 14.0 * gB;

    // Scale mode, stated rather than implied. Without it a viewer cannot tell a
    // rescaled plot from a signal that happened to fit.
    if (autoscale) {
        col += T.mid * sui3Text(P, float2(x, hy), sB,
                                S_A, S_U, S_T, S_O, S_S, S_C, S_A, S_L, S_E, 0, 0, 0);
    } else {
        col += T.dim * sui3Text(P, float2(x, hy), sB,
                                S_F, S_I, S_X, S_E, S_D, 0, 0, 0, 0, 0, 0, 0);
    }

    float hopDt = Trace[dsStateA(0u)].w;
    float nShow = Trace[dsStateB(0u)].w;

    // ---- footer: the sample clock, which is what the time axis actually is --
    float fy = R.y - (11.0 * sB + 3.0 * u);
    float fx = 6.0 * u;
    col += T.dim * sui3Text(P, float2(fx, fy), sB,
                            S_H, S_O, S_P, S_SP, S_H, S_Z, 0, 0, 0, 0, 0, 0);
    float hopHz = (hopDt > 0.0) ? (1.0 / hopDt) : 0.0;
    col += T.mid * sui3DigitsRight(P, fx + 11.0 * gB, fy, sB, (int)round(hopHz), 4);
    fx += 14.0 * gB;

    col += T.dim * sui3Text(P, float2(fx, fy), sB,
                            S_S, S_A, S_M, S_P, S_L, S_E, S_S, 0, 0, 0, 0, 0);
    col += T.mid * sui3DigitsRight(P, fx + 12.0 * gB, fy, sB, (int)round(nShow), 4);

    // ---- lanes -----------------------------------------------------------
    [loop] for (uint lane = 0u; lane < DS_LANES; ++lane) {
        float4 r = dsLaneRect(R, lane);
        if (r.w - r.y < 4.0 || r.z - r.x < 4.0) continue;

        float4 A = Trace[dsStateA(lane)];
        float4 B = Trace[dsStateB(lane)];
        float writeIdx = A.y;
        float fs       = max(B.y, 1e-6);

        col = lerp(col, T.well, sui3RectIn(P, r) * 0.85);
        col += T.rule * 0.6 * sui3Graticule(P, r, float2(8.0, 2.0));

        float ly = r.y + 1.0 * u;
        if (lane == 0u) {
            col += T.dim * sui3Text(P, float2(6.0 * u, ly), sH,
                                    S_L, S_O, S_W, 0, 0, 0, 0, 0, 0, 0, 0, 0);
        } else if (lane == 1u) {
            col += T.dim * sui3Text(P, float2(6.0 * u, ly), sH,
                                    S_M, S_I, S_D, 0, 0, 0, 0, 0, 0, 0, 0, 0);
        } else {
            col += T.dim * sui3Text(P, float2(6.0 * u, ly), sH,
                                    S_H, S_I, S_G, S_H, 0, 0, 0, 0, 0, 0, 0, 0);
        }

        // Full scale for THIS lane, under its label. This is the number that
        // proves the autoscale moved, and it belongs beside the plot it scales.
        float fsy = ly + 12.0 * sH;
        col += T.dim * sui3Text(P, float2(6.0 * u, fsy), sB,
                                S_F, S_S, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
        col += T.mid * sui3Fixed(P, float2(6.0 * u + 3.0 * gB, fsy), sB, fs, 2);

        if (P.x >= r.x && P.x <= r.z && nShow > 0.0) {
            // Mechanism 3: this column may cover many samples; take the maximum.
            int i0, i1;
            sui3TraceSpan(P.x, r.x, r.z, nShow, writeIdx, i0, i1);

            float v = 0.0, refAt = 0.0;
            [loop] for (int i = i0; i <= i1; ++i) {
                // writeIdx is the NEXT slot, still holding the sample from one
                // full ring ago; plotting it welds stale data to the live edge.
                int k = sui3TraceClampIndex(i, writeIdx);
                if (k < 0) continue;
                float4 t = Trace[sui3TraceAt(dsTraceBase(lane), DS_CAP, (uint)k)];
                v     = max(v, t.x);
                refAt = max(refAt, t.y);
            }

            float norm    = saturate(v / fs);
            float refNorm = saturate(refAt / fs);

            // The fill is plotted data, so it is T.mid. Only the part of a
            // column standing ABOVE the reference takes the accent.
            //
            // The first cut tinted the WHOLE column by whether its peak cleared
            // the reference, which on real material meant most of the frame was
            // accent and the sui3 accent contract was gone. Splitting at the
            // reference row keeps the accent to the excursion it is actually
            // reporting, and reads better besides: the eye sees how far over the
            // line a peak went, not merely that it went over.
            float fill  = sui3StripFill(P, r, norm);
            float above = fill * step(P.y, sui3StripY(r, refNorm));
            col += T.mid * 0.50 * (fill - above);
            col += T.accent * 0.90 * above;

            col += T.accent * 0.55 * sui3StripRef(P, r, refNorm, 3.0 * u);
        }

        // Frame LAST, over the data. Drawn before the fill it was overdrawn
        // wherever the plot saturated, so the strip lost its own boundary at
        // exactly the moment something was wrong with it -- and the pixel
        // measurement tool, which locates lanes by their hairlines, could not
        // read a clipping capture at all.
        col += T.rule * sui3Frame(P, r);
        col += T.rule * sui3StripBase(P, r);
    }

    col += T.rule * 0.5 * sui3Registration(P, R, 6.0 * u);

    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
