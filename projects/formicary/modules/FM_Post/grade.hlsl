// FM_Post / grade.hlsl — the print.
//
// Bloom back in, a filmic curve, a whisper of grain, and the frame's own falloff. Last pass in
// the chain and the only 8-bit one: everything upstream is RGBA16F precisely so the highlights
// on the chitin survive to be tone mapped here rather than being clipped at the first node that
// could not hold them.
#include "../_shared/formic.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);
// _Tex0 — the defocused scene. _Tex1 — the quarter-scale bloom.

// ACES, the Narkowicz fit. Chosen over Reinhard because the subject is a very bright field with
// small dark objects on it: Reinhard desaturates the shoulder badly and turns the warm mahogany
// grey exactly where the ants catch the light.
float3 aces(float3 x)
{
    const float a = 2.51, b = 0.03, c = 2.43, d = 0.59, e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    float2 res = _Resolution.xy;
    if (pixel.x >= (uint)res.x || pixel.y >= (uint)res.y) return;
    float2 uv = ((float2)pixel + 0.5) / res;

    float3 col = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    col += _Tex1.SampleLevel(LinearSampler, uv, 0).rgb * bloom_gain;

    col *= post_exposure;

    // Contrast about a mid pivot, in linear, before the curve. After the curve it crushes the
    // toe and the ants lose their leg separation against their own shadows.
    col = (col - 0.18) * contrast + 0.18;
    col = max(col, 0.0);

    float lum = dot(col, float3(0.2126, 0.7152, 0.0722));
    col = lerp(lum.xxx, col, saturation);

    // A cool lift in the shadows and a warm top: the reference was shot on a white sweep under
    // a big source, where the shadow side is filled by the room and reads a touch blue.
    col = lerp(col, col * shadow_tint, saturate(1.0 - lum * 2.2) * 0.5);

    col = aces(col * film_gain);

    // Frame falloff. Very slight — a macro lens wide open does vignette, but the reference is
    // nearly evenly lit and anything heavier reads as a filter rather than as a lens.
    float2 q = (uv - 0.5) * 2.0;
    col *= 1.0 - saturate(dot(q, q)) * vignette * 0.5;

    // Grain, added AFTER the curve in display space. Before it, the toe swallows the grain in
    // the shadows and amplifies it in the highlights, which is backwards for film.
    float g = frac(sin(dot(uv * res + _Time * 0.017, float2(12.9898, 78.233))) * 43758.5453);
    col += (g - 0.5) * grain * 0.06;

    // sRGB, approximated. The display path expects gamma-encoded output.
    col = pow(saturate(col), 1.0 / 2.2);

    OutputUAV[pixel] = float4(col, 1.0);
}
