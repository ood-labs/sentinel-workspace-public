RWTexture2D<float4> OutputUAV : register(u0);

float luminance(float3 c)
{
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float2 texel = 1.0 / _Resolution.xy;
    float center = luminance(_Tex0.SampleLevel(LinearSampler, uv, 0).rgb);
    float cross1 = 0.25 * (
        luminance(_Tex0.SampleLevel(LinearSampler, saturate(uv + float2(texel.x * 2.0, 0.0)), 0).rgb) +
        luminance(_Tex0.SampleLevel(LinearSampler, saturate(uv - float2(texel.x * 2.0, 0.0)), 0).rgb) +
        luminance(_Tex0.SampleLevel(LinearSampler, saturate(uv + float2(0.0, texel.y * 2.0)), 0).rgb) +
        luminance(_Tex0.SampleLevel(LinearSampler, saturate(uv - float2(0.0, texel.y * 2.0)), 0).rgb)
    );
    float cross2 = 0.25 * (
        luminance(_Tex0.SampleLevel(LinearSampler, saturate(uv + float2(texel.x * 8.0, 0.0)), 0).rgb) +
        luminance(_Tex0.SampleLevel(LinearSampler, saturate(uv - float2(texel.x * 8.0, 0.0)), 0).rgb) +
        luminance(_Tex0.SampleLevel(LinearSampler, saturate(uv + float2(0.0, texel.y * 8.0)), 0).rgb) +
        luminance(_Tex0.SampleLevel(LinearSampler, saturate(uv - float2(0.0, texel.y * 8.0)), 0).rgb)
    );

    float highBand = saturate(abs(center - cross1) * high_gain);
    float midBand = saturate(abs(cross1 - cross2) * mid_gain);
    float lowBand = saturate(cross2 * low_gain);
    float2 drift = archive_drift * texel;
    float4 previous = _Tex1.SampleLevel(LinearSampler, saturate(uv - drift), 0);
    float dtScale = min(_DeltaTime, 0.05) * 60.0;
    float3 decay = pow(saturate(float3(high_persistence, mid_persistence, low_persistence)), dtScale);
    float3 currentBands = float3(highBand, midBand, lowBand);
    float3 next = max(previous.rgb * decay, currentBands);
    OutputUAV[tid.xy] = float4(next, 1.0);
}
