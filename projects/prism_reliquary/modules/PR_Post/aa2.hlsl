// PR_Post / aa2.hlsl — edge antialiasing, second iteration.
//
// Passes through untouched unless "AA Iterations" is 2 or more. A second run over the
// already-filtered image is what "more antialiasing" genuinely means for an edge filter:
// the first pass turns a hard step into a two-pixel ramp, and the second smooths that ramp
// into something closer to true coverage. Cranking a single pass's strength instead just
// blends the original step further toward its own neighbours and goes blurry without ever
// getting smoother.

#include "_aa_common.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;

    if (aa_mode < 0.5 || aa_iterations < 1.5)
    {
        OutputUAV[pixel] = float4(_Tex0.SampleLevel(LinearSampler, uv, 0).rgb, 1.0);
        return;
    }

    // Slightly shorter span on the second pass: the edge is already a ramp, so a long
    // search would start pulling in genuinely unrelated pixels.
    OutputUAV[pixel] = float4(pr_edgeAA(_Tex0, uv, _Resolution.xy,
                                        pr_aaSpan() * 0.6, (int)aa_search), 1.0);
}
