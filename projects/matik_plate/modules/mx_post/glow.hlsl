// mx_post / glow.hlsl — bright-pass and disc blur, the first half of the plate's bloom.
//
// Split from the final pass so the blur radius is independent of the grade. A golden-angle
// spiral kernel rather than a separable gaussian: the linework is thin and high contrast, so
// what matters is even angular coverage around each stroke, not a mathematically ideal
// falloff, and one pass keeps the node simple.

RWTexture2D<float4> OutputUAV : register(u0);
// _Tex0 (composite) and LinearSampler are engine-injected.

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)px + 0.5) / _Resolution.xy;
    float2 texel = 1.0 / _Resolution.xy;

    float3 acc = float3(0.0, 0.0, 0.0);
    float wsum = 0.0;

    [unroll]
    for (int i = 0; i < 24; i++)
    {
        float fi = (float)i + 0.5;
        float ang = fi * 2.39996323;
        float rad = sqrt(fi / 24.0) * glow_radius;
        float2 o = float2(cos(ang), sin(ang)) * rad * texel * _Resolution.x / 1080.0;
        float3 s = _Tex0.SampleLevel(LinearSampler, uv + o, 0).rgb;
        float lum = dot(s, float3(0.299, 0.587, 0.114));
        float b = max(lum - glow_threshold, 0.0) / max(1.0 - glow_threshold, 1e-3);
        float w = 1.0 - sqrt(fi / 24.0);
        acc += s * b * w;
        wsum += w;
    }

    OutputUAV[px] = float4(acc / max(wsum, 1e-4), 1.0);
}
