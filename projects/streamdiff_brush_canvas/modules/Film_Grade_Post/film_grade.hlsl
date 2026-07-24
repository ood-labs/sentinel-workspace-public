RWTexture2D<float4> OutputUAV : register(u0);
StructuredBuffer<float4> GrainState : register(t3);

float pfHash21(float2 p)
{
    p = frac(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return frac(p.x * p.y);
}

float pfNoise(float2 p)
{
    float2 i = floor(p);
    float2 f = frac(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = pfHash21(i);
    float b = pfHash21(i + float2(1.0, 0.0));
    float c = pfHash21(i + float2(0.0, 1.0));
    float d = pfHash21(i + float2(1.0, 1.0));
    return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
}

float pfFbm(float2 p)
{
    float sum = 0.0;
    float amp = 0.5;
    [unroll]
    for (int i = 0; i < 4; ++i)
    {
        sum += pfNoise(p) * amp;
        p = p * 2.03 + float2(17.1, 11.7);
        amp *= 0.5;
    }
    return sum / 0.9375;
}

float3 pfFilmic(float3 x)
{
    x = max(x, 0.0.xxx);
    float3 a = x * (x * 2.51 + 0.03);
    float3 b = x * (x * 2.43 + 0.59) + 0.14;
    return saturate(a / max(b, 0.0001.xxx));
}

float3 pfSample(float2 uv)
{
    return _Tex0.SampleLevel(LinearSampler, saturate(uv), 0).rgb;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint outWidth, outHeight;
    OutputUAV.GetDimensions(outWidth, outHeight);
    uint2 pixel = DTid.xy;
    if (pixel.x >= outWidth || pixel.y >= outHeight) return;

    uint sourceWidth, sourceHeight;
    _Tex0.GetDimensions(sourceWidth, sourceHeight);
    float2 outputSize = float2(outWidth, outHeight);
    float2 sourceSize = float2(max(sourceWidth, 1u), max(sourceHeight, 1u));
    float2 uv = ((float2)pixel + 0.5) / outputSize;
    float aspect = outputSize.x / max(outputSize.y, 1.0);
    float2 centered = (uv - 0.5) * float2(aspect, 1.0);
    float radius = length(centered);
    float2 direction = centered / max(radius, 0.0001);

    // Subtle radial RGB separation, with green anchored to the original.
    float aberration = chromatic_aberration * radius * radius;
    float3 redSample = pfSample(uv + direction * aberration);
    float3 centerSample = pfSample(uv);
    float3 blueSample = pfSample(uv - direction * aberration);
    float3 color = float3(redSample.r, centerSample.g, blueSample.b);

    // Large-scale organic dirt breaks up repeated SDF/pattern structure
    // without introducing hard-edged floating flecks.
    float dirtField = pfFbm(uv * max(dirt_scale, 0.1) + float2(3.7, 9.1));
    float dirtMask = smoothstep(dirt_threshold - 0.16, dirt_threshold + 0.16, dirtField);
    float lensBias = smoothstep(0.24, 0.95, radius);
    float dirtLift = dirtMask * lens_dirt * (0.025 + 0.075 * lensBias);
    color += dirtLift;

    // A small neighborhood resolve softens the RGB split and keeps thin SDF
    // edges from turning brittle at high aberration values.
    float2 pixelStep = 1.0 / sourceSize;
    float3 neighborX = pfSample(uv + float2(pixelStep.x, 0.0));
    float3 neighborY = pfSample(uv + float2(0.0, pixelStep.y));
    float3 resolvedCenter = (centerSample + neighborX + neighborY) / 3.0;
    color = lerp(color, float3(redSample.r, resolvedCenter.g, blueSample.b), aa_strength);

    // These are real filtered highlight buffers: a separable two-axis bloom
    // and an independent long horizontal anamorphic convolution.
    float3 glow = _Tex1.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 flare = _Tex2.SampleLevel(LinearSampler, uv, 0).rgb;
    float dirtResponse = 1.0 + dirtMask * lens_dirt * 0.65;
    color += glow * glow_amount * 2.4 * dirtResponse;
    color += flare * flare_amount * 3.2;

    // Film grain is deliberately correlated and low-frequency. Do not add a
    // raw per-pixel hash here: it creates a fixed high-frequency lattice that
    // reads as repeating digital noise instead of changing film structure.
    float grainScale = 28.0 / max(grain_size, 0.25);
    float frameSeed = GrainState[0].x;
    float2 grainShift = float2(pfHash21(float2(frameSeed, 17.0)),
                               pfHash21(float2(frameSeed, 73.0))) * 97.0;
    float organic = pfFbm(uv * grainScale + grainShift);
    float macro = pfNoise(uv * grainScale * 0.42 + grainShift * 0.17 + 31.0);
    float grain = ((organic * 0.72 + macro * 0.28) - 0.5) * grain_amount;
    color += grain;

    color *= 1.0 - vignette * smoothstep(0.30, 0.92, radius);
    color *= exp2(exposure);
    color = max(color + lift, 0.0.xxx);
    color = pfFilmic(color);

    float luminance = dot(color, float3(0.2126, 0.7152, 0.0722));
    color = lerp(luminance.xxx, color, saturation);
    OutputUAV[pixel] = float4(saturate(color), 1.0);
}
