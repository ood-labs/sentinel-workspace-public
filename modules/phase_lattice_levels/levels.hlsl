RWTexture2D<float4> OutputUAV : register(u0);

float levels_luma(float3 c)
{
    return dot(c, float3(0.299, 0.587, 0.114));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y)
        return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float2 texel = 1.0 / max(_Resolution.xy, float2(1.0, 1.0));
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = (uv - float2(0.5, 0.5) - level_core) * float2(aspect, 1.0);
    float radius = length(p);

    float3 source = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float lum = levels_luma(source);
    float lumL = levels_luma(_Tex0.SampleLevel(LinearSampler, uv - float2(texel.x, 0.0), 0).rgb);
    float lumR = levels_luma(_Tex0.SampleLevel(LinearSampler, uv + float2(texel.x, 0.0), 0).rgb);
    float lumU = levels_luma(_Tex0.SampleLevel(LinearSampler, uv - float2(0.0, texel.y), 0).rgb);
    float lumD = levels_luma(_Tex0.SampleLevel(LinearSampler, uv + float2(0.0, texel.y), 0).rgb);

    float levels = max(3.0, floor(level_count + 0.5));
    float levelSteps = max(2.0, levels - 1.0);
    float quantized = floor(saturate(lum) * levelSteps + 0.5) / levelSteps;
    float focalMask = 1.0 - smoothstep(0.30, 0.82, radius);
    float coreMask = (1.0 - smoothstep(0.045, 0.24, radius)) * core_preserve;

    float tonal = lerp(lum, quantized, quantize_strength * (1.0 - coreMask));
    tonal = pow(saturate(tonal), 1.18);

    float phase = frac(saturate(lum) * levels);
    float phaseDistance = min(phase, 1.0 - phase);
    float gradient = length(float2(lumR - lumL, lumD - lumU));
    float adaptiveWidth = min(0.24, contour_width + gradient * levels * 0.55);
    float shell = 1.0 - smoothstep(adaptiveWidth, adaptiveWidth + 0.025, phaseDistance);
    float activity = smoothstep(0.018, 0.11, lum + gradient * 1.8);
    shell *= activity * lerp(0.32, 1.0, focalMask) * (1.0 - coreMask * 0.78);

    float base = tonal * lerp(0.34, 0.92, focalMask);
    base = lerp(base, pow(saturate(lum), 1.32), underlay);
    float relief = saturate(base + shell * shell_gain * lerp(0.45, 1.0, tonal));
    float3 neutral = relief * float3(0.91, 0.93, 0.89);

    float hotDistance = abs(quantized - hot_level);
    float hotBand = 1.0 - smoothstep(0.0, 0.72 / levels, hotDistance);
    float hot = hotBand * shell * focalMask * (1.0 - coreMask * 0.86) * hot_strength;
    float3 color = lerp(neutral, float3(1.0, 0.105, 0.022), saturate(hot));

    float2 corePx = p * _Resolution.y;
    float coreMark =
        (1.0 - smoothstep(0.0, 0.68, abs(corePx.x))) * step(abs(corePx.y), 8.0) +
        (1.0 - smoothstep(0.0, 0.68, abs(corePx.y))) * step(abs(corePx.x), 8.0);
    color += saturate(coreMark) * float3(0.11, 0.11, 0.10);

    OutputUAV[pixel] = float4(saturate(color), 1.0);
}
