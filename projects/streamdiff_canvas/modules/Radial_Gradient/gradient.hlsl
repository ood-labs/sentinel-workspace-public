RWTexture2D<float4> OutputUAV : register(u0);

float rgHash21(float2 p)
{
    float3 p3 = frac(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.x + p3.y) * p3.z);
}

float rgValueNoise(float2 p)
{
    float2 cell = floor(p);
    float2 local = frac(p);
    float2 blend = local * local * (3.0 - 2.0 * local);
    float a = rgHash21(cell);
    float b = rgHash21(cell + float2(1.0, 0.0));
    float c = rgHash21(cell + float2(0.0, 1.0));
    float d = rgHash21(cell + 1.0.xx);
    return lerp(lerp(a, b, blend.x), lerp(c, d, blend.x), blend.y);
}

float rgFractalNoise(float2 p)
{
    float value = 0.0;
    float amplitude = 0.5;
    [unroll] for (int octave = 0; octave < 5; ++octave) {
        value += rgValueNoise(p) * amplitude;
        p = p * 2.03 + float2(17.17, 9.23);
        amplitude *= 0.5;
    }
    return saturate(value / 0.96875);
}

float gradientNoise(float2 p)
{
    if (noise_type == 0) return rgValueNoise(p);
    if (noise_type == 1) return rgFractalNoise(p);
    return rgHash21(floor(p * 4.0));
}

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint width, height;
    OutputUAV.GetDimensions(width, height);
    if (id.x >= width || id.y >= height) return;

    float2 resolution = float2(width, height);
    float2 uv = (float2(id.xy) + 0.5) / resolution;
    float2 delta = uv - saturate(center);
    delta.x *= resolution.x / max(resolution.y, 1.0);

    float outerRadius = max(radius, 0.0001);
    float innerRadius = outerRadius * saturate(hardness);
    float mask = 1.0 - smoothstep(innerRadius, outerRadius, length(delta));

    float2 noiseUv = uv * max(noise_scale, 0.001);
    float baseNoise = gradientNoise(noiseUv);
    float3 noiseRgb = baseNoise.xxx;
    if (colored_noise != 0) {
        noiseRgb = float3(
            baseNoise,
            gradientNoise(noiseUv + float2(19.17, 7.43)),
            gradientNoise(noiseUv + float2(-11.31, 23.89)));
    }

    // Keep the original gradient bit-for-bit when amount is zero. At full
    // amount the noise is a true multiplicative guide, with a small floor so
    // it shapes the mask without erasing broad regions completely.
    float3 multiplier = lerp(1.0.xxx, 0.08.xxx + noiseRgb * 0.92,
                             saturate(noise_amount));
    OutputUAV[id.xy] = float4(color.rgb * mask * multiplier, 1.0);
}
