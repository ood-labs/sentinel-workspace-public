RWTexture2D<float4> OutputUAV : register(u0);

float hash21(float2 p)
{
    p = frac(p * float2(123.34, 345.45));
    p += dot(p, p + 34.345);
    return frac(p.x * p.y);
}

float3 samplePoster(float2 uv)
{
    return _Tex0.SampleLevel(LinearSampler, saturate(uv), 0).rgb;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)px + 0.5) / _Resolution;
    float2 p = uv - 0.5;
    float2 texel = 1.0 / _Resolution;

    float split = chromatic_offset * 2.5;
    float3 color;
    color.r = samplePoster(uv + float2(texel.x * split, 0.0)).r;
    color.g = samplePoster(uv).g;
    color.b = samplePoster(uv - float2(texel.x * split, 0.0)).b;

    float3 blur = 0.0;
    blur += samplePoster(uv + float2(texel.x * 2.0, 0.0));
    blur += samplePoster(uv - float2(texel.x * 2.0, 0.0));
    blur += samplePoster(uv + float2(0.0, texel.y * 2.0));
    blur += samplePoster(uv - float2(0.0, texel.y * 2.0));
    blur *= 0.25;
    float3 edge = abs(color - blur);
    color -= edge * ink_outline * 0.42;

    float lum = dot(color, float3(0.299, 0.587, 0.114));
    color = lerp(lum.xxx, color, saturation);
    color = (color - 0.5) * contrast + 0.5;
    color *= exposure;

    float levels = lerp(28.0, 6.0, posterize);
    color = floor(saturate(color) * levels + 0.5) / levels;

    float grain = hash21((float2)px + floor(_Time * 12.0) * 17.0) - 0.5;
    color += grain * paper_grain * 0.09;

    float vignetteMask = 1.0 - saturate(dot(p * float2(1.10, 0.84), p * float2(1.10, 0.84)) * 2.2);
    color *= lerp(1.0, vignetteMask, vignette);

    float frame = smoothstep(0.0, 0.012, min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y)));
    color *= lerp(0.72, 1.0, frame);
    OutputUAV[px] = float4(saturate(color), 1.0);
}
