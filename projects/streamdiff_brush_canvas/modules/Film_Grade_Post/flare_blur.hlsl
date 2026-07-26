RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint outWidth, outHeight;
    OutputUAV.GetDimensions(outWidth, outHeight);
    uint2 pixel = DTid.xy;
    if (pixel.x >= outWidth || pixel.y >= outHeight) return;

    uint inWidth, inHeight;
    _Tex0.GetDimensions(inWidth, inHeight);
    float2 uv = ((float2)pixel + 0.5) / float2(outWidth, outHeight);
    float2 texel = 1.0 / float2(max(inWidth, 1u), max(inHeight, 1u));
    float stride = 0.45 + flare_length * 0.105;

    float3 sum = 0.0.xxx;
    float weightSum = 0.0;
    [unroll]
    for (int i = -8; i <= 8; ++i)
    {
        float fi = (float)i;
        float normalizedDistance = abs(fi) / 8.0;
        float weight = exp2(-normalizedDistance * 3.4) * (1.0 - normalizedDistance * 0.18);
        float2 sampleUv = uv + float2(texel.x * stride * fi, 0.0);
        float3 sampleColor = _Tex0.SampleLevel(LinearSampler, sampleUv, 0).rgb;

        float3 edgeTint = (i < 0)
            ? float3(0.72, 0.88, 1.12)
            : float3(1.12, 0.86, 0.70);
        float3 tint = lerp(1.0.xxx, edgeTint, normalizedDistance * 0.24);
        sum += sampleColor * tint * weight;
        weightSum += weight;
    }

    float3 core = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 flare = sum / max(weightSum, 0.0001);
    OutputUAV[pixel] = float4(flare * 0.82 + core * 0.18, 1.0);
}
