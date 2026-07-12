struct FractalSeed {
    float4 orbit;
    float4 color;
    float4 rule;
    float4 warp;
};

RWStructuredBuffer<FractalSeed> OutputBuffer : register(u0);

#define PI 3.14159265359
#define TWO_PI 6.28318530718

float hash11(float n)
{
    return frac(sin(n * 127.1 + seed * 19.13) * 43758.5453);
}

float3 palette(float h)
{
    float3 a = palette_a;
    float3 b = palette_b;
    float3 c = palette_c;
    float3 pulse = 0.5 + 0.5 * sin(TWO_PI * (h + float3(0.0, 0.33, 0.67)));
    float3 ab = lerp(a, b, saturate(pulse.x * 0.9 + 0.05));
    return lerp(ab, c, saturate(pulse.z * 0.72));
}

[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint i = id.x;
    if (i >= 64) return;

    float n = (float)i;
    float active = step(n, (float)seed_count - 0.5);
    float t = _Time * spin_rate;
    float mode = (float)designer_mode;
    float golden = 2.39996323;
    float h0 = hash11(n + 1.0);
    float h1 = hash11(n + 11.0);
    float h2 = hash11(n + 23.0);

    float arm = frac(n * 0.381966 + h0 * 0.15 + mode * 0.071);
    float ring = floor(n / 8.0);
    float angle = n * golden + t * (0.18 + h1 * 0.35) + burst * sin(t * 0.7 + n);
    float radius = 0.08 + sqrt(arm) * (0.62 + 0.18 * sin(mode + ring));
    float2 center = float2(cos(angle), sin(angle)) * radius;
    center += float2(sin(t * 0.39 + n * 1.7), cos(t * 0.31 + n * 2.1)) * turbulence * 0.08;

    FractalSeed s;
    s.orbit = float4(center, 0.035 + h1 * 0.12 + 0.015 * ring, angle);
    s.color = float4(palette(arm + mode * 0.13 + h2 * 0.17), active);
    s.rule = float4(1.35 + h0 * 4.4 + mode * 0.35, fold_bias + h1 * 1.7, h2 * 2.0 - 1.0, active);
    s.warp = float4(h0 * TWO_PI, 0.4 + h1 * 1.8, ring, n);
    OutputBuffer[i] = s;
}
