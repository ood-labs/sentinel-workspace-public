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
    float stride = 0.55 + glow_radius * 0.12;

    float3 sum = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb * 0.19648255;
    sum += _Tex0.SampleLevel(LinearSampler, uv + float2(0.0, texel.y * stride * 1.0), 0).rgb * 0.17603266;
    sum += _Tex0.SampleLevel(LinearSampler, uv - float2(0.0, texel.y * stride * 1.0), 0).rgb * 0.17603266;
    sum += _Tex0.SampleLevel(LinearSampler, uv + float2(0.0, texel.y * stride * 2.0), 0).rgb * 0.12098177;
    sum += _Tex0.SampleLevel(LinearSampler, uv - float2(0.0, texel.y * stride * 2.0), 0).rgb * 0.12098177;
    sum += _Tex0.SampleLevel(LinearSampler, uv + float2(0.0, texel.y * stride * 3.0), 0).rgb * 0.06475880;
    sum += _Tex0.SampleLevel(LinearSampler, uv - float2(0.0, texel.y * stride * 3.0), 0).rgb * 0.06475880;
    sum += _Tex0.SampleLevel(LinearSampler, uv + float2(0.0, texel.y * stride * 4.0), 0).rgb * 0.02839769;
    sum += _Tex0.SampleLevel(LinearSampler, uv - float2(0.0, texel.y * stride * 4.0), 0).rgb * 0.02839769;

    OutputUAV[pixel] = float4(sum, 1.0);
}
