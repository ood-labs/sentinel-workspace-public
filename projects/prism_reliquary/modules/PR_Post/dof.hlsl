// PR_Post / dof.hlsl — the lens.
//
// A real gather-bokeh defocus, not a gaussian blur. The difference is entirely in what
// happens to highlights: a gaussian smears a bright specular into a dim smudge, while a
// disc gather spreads it into a BOKEH DISC that keeps its energy. In an image that is
// mostly black with a few very bright speculars, that is the whole effect.
//
// It works because the renderer hands us linear depth in alpha and the image is RGBA16F,
// so a 40-unit-bright chip highlight is still 40 when it lands in the kernel.
//
// Sampling is a golden-angle spiral: uniform-density on the disc with no ring artefacts and
// no random jitter, so it does not crawl between frames the way a noise-offset kernel does.

#include "../_shared/prmath.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

// Circle of confusion in pixels, signed so near and far can be told apart if needed.
float cocPixels(float z)
{
    // z == 1000 is the renderer's "ray missed everything" sentinel. The void has no
    // geometry to be out of focus, so it must not be dragged into the blur.
    if (z > 900.0) return dof_far_void * dof_amount;
    float d = z - focus_dist;
    float k = (d > 0.0) ? (d / max(focus_far, 1e-3)) : (-d / max(focus_near, 1e-3));
    return saturate(k) * dof_amount;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv  = ((float2)pixel + 0.5) / _Resolution.xy;
    float4 ctr = _Tex0.SampleLevel(LinearSampler, uv, 0);

    float coc = cocPixels(ctr.a);
    if (dof_amount < 0.01 || coc < 0.75)
    {
        OutputUAV[pixel] = ctr;
        return;
    }

    int   taps = clamp(dof_taps, 8, 96);
    float2 texel = 1.0 / _Resolution.xy;

    float3 acc = ctr.rgb;
    float  wsum = 1.0;

    [loop] for (int i = 1; i <= taps; i++)
    {
        float fi = (float)i;
        // golden angle spiral
        float a = fi * 2.39996323;
        float r = sqrt(fi / (float)taps);

        float2 dir = float2(cos(a), sin(a));

        // BOKEH SHAPE. A real aperture is not a perfect circle, and the shape is the most
        // recognisable part of a lens's character.
        if (bokeh_shape == 1)
        {
            // Hexagonal — snap the radius to a 6-sided polygon boundary.
            float seg = PR_TAU / 6.0;
            float ang = atan2(dir.y, dir.x);
            float hexr = cos(seg * 0.5) / max(cos(fmod(ang + seg * 0.5, seg) - seg * 0.5), 1e-3);
            r *= hexr;
        }
        else if (bokeh_shape == 2)
        {
            // Anamorphic — squeeze the disc into a vertical oval.
            dir.x *= 0.42;
        }

        float2 off = dir * r * coc * texel;
        float4 s   = _Tex0.SampleLevel(LinearSampler, saturate(uv + off), 0);

        // Scatter-as-gather: a sample only bleeds onto this pixel if its OWN circle of
        // confusion is wide enough to reach here. Without this test, sharp foreground
        // objects leak a halo onto blurred backgrounds behind them.
        float scoc = cocPixels(s.a);
        float reach = saturate((scoc - r * coc) * 0.5 + 1.0);

        // Bright samples weighted up a little, which is what makes highlights round out
        // into discs rather than dissolving.
        float lum = dot(s.rgb, float3(0.2126, 0.7152, 0.0722));
        float w = reach * (1.0 + bokeh_highlight * saturate(lum - 1.0));

        acc  += s.rgb * w;
        wsum += w;
    }

    OutputUAV[pixel] = float4(acc / max(wsum, 1e-4), ctr.a);
}
