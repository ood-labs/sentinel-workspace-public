// FM_Scope / comp.hlsl — the overlay over the beauty.
//
// Kept separate from the mark drawing so the marks have a real coverage lane. A draw pass
// leaves untouched pixels at alpha 0, which is exactly what is wanted here — but it also means
// the marks target cannot be shown on its own without being composited, and putting the
// composite inside the draw pass would have required reading the beauty as a render target.
#include "../_shared/formic.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);
// _Tex0 — the beauty from FM_Render. _Tex1 — the marks target.

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;

    float3 beauty = _Tex0.SampleLevel(PointSampler, uv, 0).rgb;
    float4 marks = _Tex1.SampleLevel(PointSampler, uv, 0);

    float a = saturate(marks.a) * saturate(scope_mix);

    // The beauty recedes as the instrument OPENS, globally, so the linework has something to
    // sit against once the layers are lifted apart. Tied to `explode` rather than to per-pixel
    // mark coverage: dimming only underneath the marks put a halo round every line, and at
    // explode = 0 the photograph must be completely untouched — being able to CLOSE the
    // instrument is what makes the open state trustworthy, because it proves the same picture
    // is being described.
    float dim = lerp(1.0, saturate(beauty_dim), saturate(explode) * saturate(scope_mix));

    OutputUAV[pixel] = float4(beauty * dim * (1.0 - a) + marks.rgb * a, 1.0);
}
