// TP_Sim / relief.hlsl — the node's own instrument view of the surface.
//
// Full bleed on purpose: the preview IS the water plane seen from above, one preview pixel to
// one footprint position, which is what makes clicking and dragging in this preview an exact
// operation with no remapping to get wrong.
//
// Near-monochrome, from the shared instrument palette. The relief is shaded from the stored
// gradient and overlaid with contour lines, because a shaded relief alone reads as "something
// is happening" while contours say how much and where the crests are. Amber is spent only on
// the live pointer reading and the selected source; red only when the surface has cleared the
// tank rim, which is the one state that means the composition is broken.
#include "sim.hlsli"
#include "../_shared/plan_theme.hlsli"

StructuredBuffer<TpCtl> Ctl : register(t1);
StructuredBuffer<TpRec> Plan : register(t2);
StructuredBuffer<float4> Metrics : register(t3);
RWTexture2D<float4> OutputUAV : register(u0);

float aa(float d) { return saturate(0.5 - d); }
float cvRing(float2 p, float2 c, float r, float w) { return aa(abs(length(p - c) - r) - w * 0.5); }
float cvDisc(float2 p, float2 c, float r)          { return aa(length(p - c) - r); }
float cvSeg(float2 p, float2 a, float2 b, float w)
{
    float2 pa = p - a, ba = b - a;
    float t = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return aa(length(pa - ba * t) - w * 0.5);
}
void ink(inout float3 dst, float3 col, float cov) { dst = lerp(dst, col, saturate(cov)); }

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    if (tid.x >= W || tid.y >= H) return;

    float2 res = float2(W, H);
    float2 px = float2(tid.xy) + 0.5;
    float2 uv = px / res;

    TpRec tank = Plan[TP_TANK];
    float2 halfXZ = float2(tank.dims.x, tank.dims.z);
    float fb = tpTankFree(tank);

    float4 s = _Tex0.SampleLevel(LinearSampler, uv, 0);
    float h = s.x;
    float2 g = s.zw;

    float peak = Metrics[0].x;
    float rms = Metrics[0].y;
    float mPeak = Metrics[0].z;
    float mRms = Metrics[0].w;
    bool overRim = peak > fb;

    // MOTION VIEW. The whole point: a height relief cannot distinguish a standing wave from
    // still water, because both hold a steady height profile. This maps the local oscillation
    // ENVELOPE instead, so anything that is moving lights up and anything at rest goes black —
    // and a spot that stays lit while the tank is supposed to be calm is the fault, located.
    if ((int)view_mode == 1)
    {
        float invTau = 1.0 / max(motion_tau, 0.005);
        float env = sqrt(s.y * s.y + (s.x * invTau) * (s.x * invTau));
        float t = saturate(env / max(motion_scale, 1e-5));
        float3 mc = lerp(PT_FIELD, PT_MID, saturate(t * 3.0));
        mc = lerp(mc, PT_ACCENT, saturate((t - 0.33) * 1.5));
        mc = lerp(mc, PT_ALARM, saturate((t - 0.75) * 4.0));
        OutputUAV[tid.xy] = float4(mc, 1.0);
        return;
    }

    // relief: a raking light across the gradient, kept in the grey ladder
    float3 lit = normalize(float3(-0.55, 0.62, 1.0));
    float3 n = normalize(float3(-g.x, 1.0, -g.y));
    float lam = saturate(dot(n, lit));
    float spec = pow(saturate(dot(n, normalize(lit + float3(0, 1, 0)))), 46.0);

    // FIXED DISPLAY SCALE. NEVER THE RUNNING PEAK.
    //
    // This previously divided by the live peak, which made the preview auto-ranging — and an
    // auto-ranging display of a decaying signal is a microscope whose magnification rises as
    // the subject shrinks. A tank at an amplitude of 0.00001 rendered exactly as violently as
    // one at 0.05, so calm water looked like it was thrashing and NO physics change could ever
    // appear to help: halve the real amplitude and the display gain doubles, leaving the
    // picture identical. It confounded every attempt to judge whether the water had settled,
    // including mine.
    //
    // The reference is the FREEBOARD — the tank's own physical headroom, the same number the
    // plan draws its alarm against. Calm now looks calm, and a wave that fills the frame really
    // is a wave that nearly clears the rim.
    float scale = max(fb * max(relief_scale, 0.01), 1e-5);
    float t = clamp(h / scale, -1.0, 1.0);

    // FINITE-SLOPE CONTRAST. The old signed power curve used exponent 0.42. Its derivative
    // tends to infinity at zero, so the smallest harmless wave crossing still water produced
    // a large luminance jump. This curve keeps the useful mid-range contrast and maps +/-1
    // exactly, but has a bounded slope at rest.
    float shaped = t / (0.18 + 0.82 * abs(t));

    float3 c = lerp(PT_FIELD, PT_GRID, saturate(lam * 1.15));
    c = lerp(c, PT_MID, (shaped * 0.5 + 0.5) * 0.62);
    c += PT_INK * spec * 0.30;

    // contours every `contour_step` world units of height. This is the readout: a shaded
    // relief says "waves", contour spacing says how steep and how tall.
    {
        // No fwidth in a compute shader, so the per-pixel change in height is derived from the
        // stored world gradient and the world size of one pixel.
        //
        // The FLOOR on that width matters as much as the width. Derived from the live gradient
        // alone it shrinks with the waves, so on a nearly flat field every pixel sits within a
        // vanishing distance of a contour and the lines switch on across the ENTIRE screen —
        // the same auto-ranging failure as the height mapping above, and it made a settled tank
        // read as dense churn.
        float worldPerPx = (2.0 * halfXZ.x) / max(res.x, 1.0);
        float dPerPx = length(g) * worldPerPx;

        float st = max(contour_step, 0.0005);
        float d = abs(frac(h / st + 0.5) - 0.5) * st;                 // distance in height to a contour

        // The line half-width is the smaller of one pixel of slope and a quarter of the
        // contour interval. Without the second term a steep ripple — where one pixel spans a
        // large part of the interval — makes every pixel partially "on", and the plot
        // degenerates into a dither that reads as corruption rather than as contours.
        // A flat field equal to an isoline is mathematically all contour, but filling the
        // preview with that line is a useless and unstable reading. Only draw a contour once
        // its screen-space slope is resolvable; keep a tiny width floor solely to make the
        // smoothstep well-defined.
        float resolvable = smoothstep(st * 0.002, st * 0.020, dPerPx);
        float w = min(max(dPerPx * 1.1, st * 0.012), st * 0.22);
        ink(c, PT_RULE, (1.0 - smoothstep(0.0, w, d)) * 0.55 * resolvable);

        // the still-water zero crossing, one value heavier than the rest of the ladder
        ink(c, PT_DIM, (1.0 - smoothstep(0.0, w * 1.3, abs(h))) * 0.65 * resolvable);
    }

    // sources, in the same footprint space the solver injects them in
    uint sel = 0u;
    for (uint i = 0u; i < TP_SRCS; i++)
    {
        TpRec r = Plan[TP_SRC_0 + i];
        if (r.active > 0.5)
        {
            bool isSel = ((uint)r.flags & F_SELECTED) != 0u;
            float2 sp = (float2(r.pos.x, r.pos.z) * 0.5 + 0.5) * res;
            float3 col = isSel ? PT_ACCENT : PT_DIM;
            float rad = max(r.dims.x, 0.02) * 0.5 * res.x;
            if (r.kind == KIND_SWELL)
            {
                float2 dir = float2(cos(r.p3), sin(r.p3));
                float2 pp = float2(-dir.y, dir.x) * (0.10 * res.x);
                ink(c, col, cvSeg(px, sp - pp, sp + pp, isSel ? 2.0 : 1.2) * 0.9);
                ink(c, col, cvSeg(px, sp, sp + dir * (0.05 * res.x), isSel ? 2.0 : 1.2) * 0.9);
            }
            else
            {
                ink(c, col, cvRing(px, sp, max(rad, 4.0), isSel ? 2.0 : 1.2) * 0.9);
                if (r.kind == KIND_EMIT) ink(c, col, cvRing(px, sp, max(rad, 4.0) + 3.5, 1.0) * 0.9);
            }
        }
    }

    // the live pointer: an established reading, so it earns the accent
    TpCtl st = Ctl[0];
    if (st.d.x > 0.5 || st.d.y > 0.5)
    {
        float2 a = (st.d.x > 0.5 ? st.b.zw : st.c.zw) * res;
        float pr = max(pointer_radius, 0.005) * 0.5 * res.x;
        ink(c, PT_ACCENT, cvRing(px, a, pr, 1.6) * 0.85);
        ink(c, PT_ACCENT, cvDisc(px, a, 2.0));
    }

    // peak-against-rim bar down the left edge. The one number the arrangement can break.
    {
        float barX = 10.0;
        float top = res.y * 0.10, bot = res.y * 0.90;
        float frac01 = saturate(peak / max(fb, 1e-4));
        float y = lerp(bot, top, frac01);
        ink(c, PT_RULE, cvSeg(px, float2(barX, top), float2(barX, bot), 1.0));
        ink(c, PT_RULE, cvSeg(px, float2(barX - 4.0, top), float2(barX + 4.0, top), 1.0));       // the rim
        ink(c, overRim ? PT_ALARM : PT_ACCENT, cvSeg(px, float2(barX - 5.0, y), float2(barX + 5.0, y), 2.0));
        ink(c, PT_DIM, cvSeg(px, float2(barX - 3.0, lerp(bot, top, saturate(rms / max(fb, 1e-4)))),
                                 float2(barX + 3.0, lerp(bot, top, saturate(rms / max(fb, 1e-4)))), 1.0));
    }

    if (overRim)
    {
        float e = min(min(px.x, px.y), min(res.x - px.x, res.y - px.y));
        ink(c, PT_ALARM, (1.0 - smoothstep(0.0, 4.0, e)) * 0.9);
    }

    OutputUAV[tid.xy] = float4(c, 1.0);
}
