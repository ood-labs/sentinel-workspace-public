// FM_Colony / shad_out.hlsl — publish the contact shadow field to the rest of the show.
//
// WHY THIS PASS HAS TO EXIST, even though it does nothing but copy.
//
// `shad` writes its result into a BUFFER (`output: "buffer:shadf"`). A pass that writes a buffer
// has no shader resource view of its own, so naming it directly in `outputs:` produces an output
// pin that is permanently hollow — `capture_data_port` on it reports "no SRV (0x0 or not
// rendered yet)" and every consumer downstream samples whatever texture the device had bound
// last.
//
// That failure is silent and it does not look like a missing texture. In this project it looked
// like the GAIT CHART painted across the studio sweep in perspective: FM_Render's `_Tex4` fell
// through to FM_Colony's own canvas, which the sweep then dutifully sampled through
// fmWorldToFieldUV and shaded as a shadow. Nothing errored, the module compiled 11 of 11 passes,
// health was green, and the graph was correctly wired by pin name.
//
// So the buffer-writing pass stays a buffer-writing pass, and this trivial blit is what the
// module actually publishes — exactly the arrangement `field_out` already uses for `pher`.
#include "../_shared/formic.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);
// _Tex0 — the shadow buffer, auto-declared.

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;

    // Bilinear: the shadow buffer is half this pass's resolution, and a point sample would hand
    // the renderer a shadow with a visible texel lattice on a perfectly flat white plane, which
    // reads as a rendering fault rather than as a resolution limit.
    float s = _Tex0.SampleLevel(LinearSampler, uv, 0).r;
    OutputUAV[pixel] = float4(s, s, s, 1.0);
}
