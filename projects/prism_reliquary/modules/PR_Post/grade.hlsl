// PR_Post / grade.hlsl — the finish.
//
// Order matters and is deliberate: aberration acts on the RENDERED image (it is a lens
// property, so it must displace the subject, not the glow), then bloom and flare are added
// as light, then the grade, then the tonemap, and grain last so it lives in display space
// where it reads as film grain rather than as noise multiplied by exposure.

#include "../_shared/prmath.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float2 d  = uv - 0.5;

    // ---- depth diagnostics --------------------------------------------------
    // The lens blur reads linear depth out of alpha, which is invisible in the final image:
    // if the depth ever stops arriving, the defocus degrades into a uniform blur that still
    // looks plausible. That exact failure shipped once — the renderer was publishing BGRA8,
    // alpha clamped to 1.0, and every pixel got an identical circle of confusion. These
    // views make the depth lane visible, and double as the practical way to set focus.
    if (debug_view > 0.5)
    {
        float z = _Tex0.SampleLevel(LinearSampler, uv, 0).a;
        if (debug_view < 1.5)
        {
            // Depth: near = white, far = black, magenta where the ray hit nothing.
            if (z > 900.0) { OutputUAV[pixel] = float4(0.7, 0.0, 0.7, 1.0); return; }
            float g = saturate(1.0 - (z - (focus_dist - 6.0)) / 12.0);
            OutputUAV[pixel] = float4(g, g, g, 1.0);
            return;
        }
        // Focus: green in focus, red out of focus, brightness = amount of blur.
        float dd = z - focus_dist;
        float k  = (z > 900.0) ? dof_far_void
                 : saturate((dd > 0.0) ? dd / max(focus_far, 1e-3) : -dd / max(focus_near, 1e-3));
        OutputUAV[pixel] = float4(k, 1.0 - k, 0.0, 1.0);
        return;
    }

    // ---- lateral chromatic aberration, strongest at the corners -------------
    float  ab = aberration * 0.006 * dot(d, d) * 4.0;
    float3 c;
    c.r = _Tex0.SampleLevel(LinearSampler, saturate(uv + d * ab), 0).r;
    c.g = _Tex0.SampleLevel(LinearSampler, uv, 0).g;
    c.b = _Tex0.SampleLevel(LinearSampler, saturate(uv - d * ab), 0).b;

    // ---- light added on top -------------------------------------------------
    c += _Tex1.SampleLevel(LinearSampler, uv, 0).rgb * bloom_gain;
    c += _Tex2.SampleLevel(LinearSampler, uv, 0).rgb * star_gain;

    // ---- grade ---------------------------------------------------------------
    c *= exposure_post;

    float l = dot(c, float3(0.2126, 0.7152, 0.0722));
    c = lerp(float3(l, l, l), c, saturation);
    c = lerp(c, c * c * (3.0 - 2.0 * c), contrast * 0.5);
    c = max(c + lift * 0.02, 0.0);

    // vignette — the reference falls off hard into the corners
    float vg = 1.0 - vignette * smoothstep(0.28, 0.92, length(d * float2(1.0, 0.82)) * 1.45);
    c *= vg;

    c = pr_aces(c);

    // ---- grain, in display space --------------------------------------------
    float g = pr_hash21(uv * _Resolution.xy + frac(_Time) * 311.7) - 0.5;
    c += g * grain * 0.055 * (0.35 + 0.65 * (1.0 - dot(c, float3(0.33, 0.34, 0.33))));

    OutputUAV[pixel] = float4(saturate(c), 1.0);
}
