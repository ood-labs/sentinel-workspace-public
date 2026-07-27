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
    float3 c = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float l = luminance(c);
    float lL = luminance(_Tex0.SampleLevel(LinearSampler, uv - float2(texel.x, 0.0), 0).rgb);
    float lR = luminance(_Tex0.SampleLevel(LinearSampler, uv + float2(texel.x, 0.0), 0).rgb);
    float lU = luminance(_Tex0.SampleLevel(LinearSampler, uv - float2(0.0, texel.y), 0).rgb);
    float lD = luminance(_Tex0.SampleLevel(LinearSampler, uv + float2(0.0, texel.y), 0).rgb);

    float smoothLum = (l * 4.0 + lL + lR + lU + lD) / 8.0;
    float edge = abs(lR - lL) + abs(lD - lU);
    float orange = saturate((c.r - max(c.g, c.b)) * 3.0);

    float shaped = saturate((smoothLum - 0.12) * analysis_contrast + 0.12);
    shaped = saturate(shaped + edge * edge_gain + orange * signal_weight);
    shaped = smoothstep(0.015, 0.97, shaped);

    OutputUAV[pixel] = float4(shaped.xxx, 1.0);
}
