RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)px + 0.5) / _Resolution.xy;
    float2 texel = 1.0 / _Resolution.xy;
    float3 src = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 glow = 0.0;
    float wsum = 0.0;
    [unroll]
    for (int i = -4; i <= 4; ++i)
    {
        float fi = (float)i;
        float w = 1.0 - abs(fi) / 5.0;
        float3 a = _Tex0.SampleLevel(LinearSampler, uv + float2(fi, 0.0) * texel * bloom_radius, 0).rgb;
        float3 b = _Tex0.SampleLevel(LinearSampler, uv + float2(0.0, fi) * texel * bloom_radius, 0).rgb;
        glow += (max(a - bloom_threshold, 0.0) + max(b - bloom_threshold, 0.0)) * w;
        wsum += 2.0 * w;
    }
    glow /= max(wsum, 0.001);
    float vig = pow(saturate(16.0 * uv.x * uv.y * (1.0 - uv.x) * (1.0 - uv.y)), vignette);
    float scan = 1.0 - scanlines * (0.5 + 0.5 * sin(uv.y * _Resolution.y * 3.14159));
    float3 col = (src + glow * bloom_gain) * vig * scan;
    col = lerp(dot(col, float3(0.299, 0.587, 0.114)).xxx, col, saturation);
    OutputUAV[px] = float4(saturate(col), 1.0);
}
