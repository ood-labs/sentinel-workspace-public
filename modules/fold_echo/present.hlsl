RWTexture2D<float4> OutputUAV : register(u0);

float luminance(float3 c)
{
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float2 texel = 1.0 / max(_Resolution.xy, float2(1.0, 1.0));
    float3 center = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 horizontal = _Tex0.SampleLevel(LinearSampler, uv + float2(texel.x * 2.0, 0.0), 0).rgb;
    float ridge = saturate(abs(luminance(center) - luminance(horizontal)) * 2.8);

    float3 mapped = center / (1.0 + center);
    mapped = pow(saturate(mapped), 1.0 / 1.08);
    mapped += ridge * float3(0.13, 0.135, 0.13);

    float2 p = uv - 0.5;
    float vignette = 1.0 - smoothstep(0.38, 0.74, length(p * float2(_Resolution.x / _Resolution.y, 1.0)));
    mapped *= 0.70 + 0.30 * vignette;
    mapped += float3(0.002, 0.0025, 0.0027);

    OutputUAV[pixel] = float4(saturate(mapped), 1.0);
}
