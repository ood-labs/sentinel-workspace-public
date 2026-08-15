// FM_Post / dof.hlsl — the macro lens.
//
// This is the pass that decides whether the image reads as a PHOTOGRAPH of ants or as a render
// of ants. At the reference's magnification the depth of field is a few millimetres deep: one
// worker is sharp, the one a body length behind it is already soft, and the one at the top of
// the frame is dissolved. Nothing else in this chain can produce that, and without it a
// technically perfect render still looks synthetic, because no real lens has ever behaved that
// way at this scale.
//
// Gather bokeh, not a gaussian. A gaussian blur is the wrong shape: real defocus spreads a
// point into the aperture's disc, which is what makes a specular highlight on a gaster bloom
// into a soft circle instead of a smear.
#include "../_shared/formic.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);
// _Tex0 — the composited scene. _Tex1 — FM_Render's linear depth, in millimetres.

// Circle of confusion in pixels, signed: negative in front of the focal plane, positive behind.
// Signed because a foreground tap must not be allowed to sample a sharp background pixel, which
// is what produces the hard halo around out-of-focus foreground objects.
float cocPx(float z, float2 res)
{
    float f = max(focus_mm, 0.1);
    // The thin-lens relation, in the form where aperture is the one control: how much the
    // circle grows per unit of relative depth error. Expressed against the frame height so the
    // look survives a resolution change.
    float rel = (z - f) / max(z, 0.1);
    return clamp(rel * aperture * res.y * 0.02, -max_coc, max_coc);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    float2 res = _Resolution.xy;
    if (pixel.x >= (uint)res.x || pixel.y >= (uint)res.y) return;
    float2 uv = ((float2)pixel + 0.5) / res;

    float3 centre = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float zc = _Tex1.SampleLevel(PointSampler, uv, 0).r;
    float cc = cocPx(zc, res);

    // Diagnostic views. In a chain where the depth lane is invisible bookkeeping, these are the
    // only way to tell a wrong lane from a dead one — and the first version of this node blurred
    // the entire frame uniformly, which looks identical whether the depth is zero, saturated, or
    // simply scaled wrong.
    if (view_mode == 1)
    {
        // Depth banded every 10 mm, so the value can be READ off the image rather than guessed
        // from a gradient. A smooth grey ramp cannot distinguish 70 from 700.
        float band = frac(zc / 10.0);
        OutputUAV[pixel] = float4(saturate(zc / 200.0), band, saturate(zc / 1000.0), 1.0);
        return;
    }
    if (view_mode == 2)
    {
        // Signed circle of confusion: red behind the focal plane, blue in front, black sharp.
        OutputUAV[pixel] = float4(saturate(cc / max_coc), 0.0, saturate(-cc / max_coc), 1.0);
        return;
    }

    if (dof_on < 0.5 || abs(cc) < 1.0)
    {
        OutputUAV[pixel] = float4(centre, 1.0);
        return;
    }

    uint taps = (uint)clamp((float)dof_taps, 4.0, 64.0);
    float3 sum = centre;
    float wsum = 1.0;

    // Golden-angle spiral: the cheapest tap set that fills a disc evenly without banding at any
    // count, so the quality ladder can change `taps` without changing the SHAPE of the bokeh.
    for (uint i = 0u; i < taps; i++)
    {
        float fi = (float)i + 0.5;
        float r = sqrt(fi / (float)taps);
        float a = fi * 2.39996323;
        float2 off = float2(cos(a), sin(a)) * r * abs(cc);
        float2 suv = uv + off / res;
        if (suv.x < 0.0 || suv.x > 1.0 || suv.y < 0.0 || suv.y > 1.0) continue;

        float3 s = _Tex0.SampleLevel(LinearSampler, suv, 0).rgb;
        float zs = _Tex1.SampleLevel(PointSampler, suv, 0).r;
        float cs = cocPx(zs, res);

        // A tap only contributes if ITS OWN circle of confusion reaches this pixel. Without
        // this test a sharp foreground ant bleeds into the blurred background behind it, which
        // is the single most recognisable artefact of a naive depth blur and reads immediately
        // as "this is a post effect", not "this is out of focus".
        float reach = abs(cs) * r;
        float w = saturate((reach - length(off) + 1.5) * 0.7);
        // Never let a tap that is much closer to the camera dominate a far pixel.
        if (zs < zc - 0.5 && abs(cs) < abs(cc) * 0.5) w *= 0.15;

        sum += s * w;
        wsum += w;
    }

    OutputUAV[pixel] = float4(sum / max(wsum, 1e-4), 1.0);
}
