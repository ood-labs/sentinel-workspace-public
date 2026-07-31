// PR_Post / _aa_common.hlsli — the edge filter, shared by both AA passes.
//
// Factored out so `aa` and `aa2` are the same filter run twice rather than two
// implementations that can drift apart. Two chained passes is what "more AA" actually
// means here: one pass resolves a step into a ramp, a second smooths the ramp.

#ifndef PR_AA_COMMON_HLSLI
#define PR_AA_COMMON_HLSLI

#include "../_shared/prmath.hlsli"

float pr_luma(float3 c) { return dot(c, float3(0.299, 0.587, 0.114)); }

// Edge-directed filter with an explicit end-of-edge search. The cheap FXAA variant just
// blends along the gradient over a fixed span; searching for where the edge actually ENDS
// is what lets it fix long, shallow, high-contrast boundaries — which is exactly what the
// glyph bars, the ring rim and the membrane silhouette are.
float3 pr_edgeAA(Texture2D<float4> tex, float2 uv, float2 res, float span, int searchSteps)
{
    float2 t = 1.0 / res;

    float3 rgbM  = tex.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 rgbNW = tex.SampleLevel(LinearSampler, uv + float2(-t.x, -t.y), 0).rgb;
    float3 rgbNE = tex.SampleLevel(LinearSampler, uv + float2( t.x, -t.y), 0).rgb;
    float3 rgbSW = tex.SampleLevel(LinearSampler, uv + float2(-t.x,  t.y), 0).rgb;
    float3 rgbSE = tex.SampleLevel(LinearSampler, uv + float2( t.x,  t.y), 0).rgb;

    float lNW = pr_luma(rgbNW), lNE = pr_luma(rgbNE);
    float lSW = pr_luma(rgbSW), lSE = pr_luma(rgbSE);
    float lM  = pr_luma(rgbM);

    float lMin = min(lM, min(min(lNW, lNE), min(lSW, lSE)));
    float lMax = max(lM, max(max(lNW, lNE), max(lSW, lSE)));
    float range = lMax - lMin;

    // Local contrast gate. An absolute threshold alone destroys subtle gradients in the dark
    // two thirds of this image, so the relative term is what keeps the void clean.
    if (range < max(aa_threshold, lMax * aa_relative)) return rgbM;

    float2 dir = float2(-((lNW + lNE) - (lSW + lSE)),
                         ((lNW + lSW) - (lNE + lSE)));

    float reduce = max((lNW + lNE + lSW + lSE) * 0.25 * 0.20, 1.0 / 128.0);
    float rcpMin = 1.0 / (min(abs(dir.x), abs(dir.y)) + reduce);
    dir = clamp(dir * rcpMin, -span, span) * t;

    // Short filter — two taps inside the edge.
    float3 a0 = 0.5 * (tex.SampleLevel(LinearSampler, uv + dir * (1.0 / 3.0 - 0.5), 0).rgb +
                       tex.SampleLevel(LinearSampler, uv + dir * (2.0 / 3.0 - 0.5), 0).rgb);

    // Long filter — walk outward along the edge until the luma leaves the local range, and
    // average what was crossed. This is the part that actually softens a long diagonal.
    float3 acc = a0 * 2.0;
    float  wsum = 2.0;
    int steps = clamp(searchSteps, 0, 16);
    // REACH IS DELIBERATELY SHORT and out-of-range samples are given ZERO weight.
    // The first version walked 1.5x the full span with a 0.25 floor on rejected samples,
    // which averaged across unrelated geometry and softened the entire frame — the pelt
    // lost its strand detail. An edge filter that reaches too far stops being an edge
    // filter and becomes a blur.
    [loop] for (int i = 1; i <= steps; i++)
    {
        float f = (float)i / (float)max(steps, 1);
        float3 sp = tex.SampleLevel(LinearSampler, uv + dir * ( f * 0.6 - 0.5), 0).rgb;
        float3 sn = tex.SampleLevel(LinearSampler, uv + dir * (-f * 0.6 - 0.5), 0).rgb;
        float wp = (pr_luma(sp) >= lMin && pr_luma(sp) <= lMax) ? 1.0 : 0.0;
        float wn = (pr_luma(sn) >= lMin && pr_luma(sn) <= lMax) ? 1.0 : 0.0;
        acc += sp * wp + sn * wn;
        wsum += wp + wn;
    }
    float3 b0 = acc / max(wsum, 1e-4);

    // Reject the long filter if it wandered outside the neighbourhood's luma range —
    // that means it crossed onto unrelated geometry and would smear detail.
    float lB = pr_luma(b0);
    float3 res3 = (lB < lMin || lB > lMax) ? a0 : b0;

    return lerp(rgbM, res3, saturate(aa_strength));
}

// Off / Standard / High / Ultra -> filter span in texels.
float pr_aaSpan()
{
    if (aa_mode < 1.5) return 6.0;
    if (aa_mode < 2.5) return 12.0;
    return 22.0;
}

#endif // PR_AA_COMMON_HLSLI
