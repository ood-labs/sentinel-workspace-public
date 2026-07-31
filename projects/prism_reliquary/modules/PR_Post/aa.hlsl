// PR_Post / aa.hlsl — edge antialiasing, first iteration.
//
// Runs after the grade because edge detection wants perceptual contrast, not linear
// radiance — the same filter on HDR misjudges which edges matter and smears the speculars.
//
// SCOPE. This fixes EDGES. There are two other aliasing sources in this show that a post
// filter cannot reach, and reaching for more AA instead of the right tool is a trap:
//   * the pelt is high-frequency geometric noise — that needs PR_Render's "Rays Per Axis";
//   * the membrane silhouette is a one-ray-per-pixel hit test — that is fixed analytically
//     in film.hlsl by turning the march's closest approach into sub-pixel coverage.

#include "_aa_common.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;

    if (aa_mode < 0.5)
    {
        OutputUAV[pixel] = float4(_Tex0.SampleLevel(LinearSampler, uv, 0).rgb, 1.0);
        return;
    }

    OutputUAV[pixel] = float4(pr_edgeAA(_Tex0, uv, _Resolution.xy,
                                        pr_aaSpan(), (int)aa_search), 1.0);
}
