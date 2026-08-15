// FM_Post / bloom.hlsl — the glow off wet chitin.
//
// A quarter-scale pass, so this is a SCALED PASS: every extent comes from GetDimensions on the
// target and never from _Resolution, which is the root pipeline size and would put the whole
// gather in one corner.
//
// Thresholded above white on purpose. The sweep is exposed to sit just under 1.0, so a
// threshold at 1.0 catches only the specular highlights on the gasters and nothing of the
// ground — which is correct: a white paper background does not glow, and a threshold low enough
// to include it turns the whole frame into fog.
#include "../_shared/formic.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);
// _Tex0 — the defocused scene at full resolution.

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint bw, bh;
    OutputUAV.GetDimensions(bw, bh);
    if (DTid.x >= bw || DTid.y >= bh) return;
    float2 uv = ((float2)DTid.xy + 0.5) / float2(bw, bh);

    float3 sum = 0.0;
    float wsum = 0.0;

    // 24 taps on a golden-angle spiral, in units of the QUARTER-SCALE target, which is why the
    // radius is small here and still covers a wide area of the final image.
    for (uint i = 0u; i < 24u; i++)
    {
        float fi = (float)i + 0.5;
        float r = sqrt(fi / 24.0);
        float a = fi * 2.39996323;
        float2 suv = uv + float2(cos(a), sin(a)) * r * bloom_radius / float2(bw, bh) * 8.0;

        float3 s = _Tex0.SampleLevel(LinearSampler, saturate(suv), 0).rgb;
        float lum = dot(s, float3(0.2126, 0.7152, 0.0722));
        float3 bright = s * saturate((lum - bloom_threshold) / max(bloom_threshold, 1e-3));

        float w = 1.0 - r * 0.7;
        sum += bright * w;
        wsum += w;
    }

    OutputUAV[DTid.xy] = float4(sum / max(wsum, 1e-4), 1.0);
}
