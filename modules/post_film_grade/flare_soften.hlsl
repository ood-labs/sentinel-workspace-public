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

    float3 sum = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb * 0.22702703;
    sum += _Tex0.SampleLevel(LinearSampler, uv + float2(texel.x * 1.38461538, 0.0), 0).rgb * 0.31621622;
    sum += _Tex0.SampleLevel(LinearSampler, uv - float2(texel.x * 1.38461538, 0.0), 0).rgb * 0.31621622;
    sum += _Tex0.SampleLevel(LinearSampler, uv + float2(texel.x * 3.23076923, 0.0), 0).rgb * 0.07027027;
    sum += _Tex0.SampleLevel(LinearSampler, uv - float2(texel.x * 3.23076923, 0.0), 0).rgb * 0.07027027;
    OutputUAV[pixel] = float4(sum, 1.0);
}
