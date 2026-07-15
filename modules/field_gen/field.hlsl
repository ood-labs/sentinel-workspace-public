// field_gen — master height/region/slope/detail field for the topographic-HUD scene.
// Output RGBA16F: R = elevation (0..1), G = region/basin id (banded 0..1),
//                 B = slope magnitude (0..1), A = fine detail (0..1).
// Self-contained noise (no features:[noise] to avoid injected-symbol collisions).

RWTexture2D<float4> OutputUAV : register(u0);

float hash21(float2 p)
{
    p = frac(p * float2(123.34, 345.45));
    p += dot(p, p + 34.345);
    return frac(p.x * p.y);
}

float valueNoise(float2 p)
{
    float2 i = floor(p);
    float2 f = frac(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    return lerp(lerp(a, b, u.x), lerp(c, d, u.x), u.y);
}

float fbm(float2 p, int oct, float lac, float gn)
{
    float sum = 0.0;
    float amp = 0.5;
    float tot = 0.0;
    [loop]
    for (int i = 0; i < 8; i++)
    {
        if (i >= oct) break;
        sum += amp * valueNoise(p);
        tot += amp;
        p *= lac;
        amp *= gn;
    }
    return sum / max(tot, 1e-4);
}

// Elevation function, sampled a few times for gradient/slope.
float elevF(float2 p)
{
    float t = _Time * flow_speed;
    // UI point2D is Cartesian; this field is sampled in texture-oriented space.
    float2 fl = float2(flow_dir.x, -flow_dir.y) * t;

    // domain warp
    float2 warp = float2(
        fbm(p * frequency + fl, octaves, lacunarity, gain),
        fbm(p * frequency + fl + float2(5.2, 1.3), octaves, lacunarity, gain));
    float2 q = p + (warp - 0.5) * 2.0 * warp_amount;

    float e = fbm(q * frequency + fl, octaves, lacunarity, gain);

    // multi-center basins / ridges / islands
    [loop]
    for (int i = 0; i < 8; i++)
    {
        if (i >= center_count) break;
        float fi = (float)i + (float)seed * 3.17;
        float2 c = (float2(hash21(float2(fi, 1.7)), hash21(float2(fi, 4.3))) * 2.0 - 1.0) * 0.8;
        float d = length(p - c);
        float g = exp(-d * d * 2.5);
        float s = (field_mode == 0) ? 1.0 : (field_mode == 1) ? -1.0
                : (field_mode == 2) ? ((frac(fi * 0.5) < 0.5) ? 1.0 : -1.0) : sin(fi * 1.7);
        e += g * 0.5 * s;
    }

    return e + elevation_bias;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float asp = (_Resolution.x / _Resolution.y) * aspect;
    float2 p = (uv * 2.0 - 1.0) * float2(asp, 1.0);

    float eps = 0.0025;
    float e0 = elevF(p);
    float ex = elevF(p + float2(eps, 0.0));
    float ey = elevF(p + float2(0.0, eps));
    float slope = length(float2(ex - e0, ey - e0)) / eps;

    float t = _Time * flow_speed;
    float2 fl = float2(flow_dir.x, -flow_dir.y) * t;
    float detail = fbm(p * frequency * 4.0 + fl * 2.0, octaves, lacunarity, gain) * detail_gain;

    float elev = saturate(e0 * 0.5 + 0.5);
    float region = frac(e0 * region_split);

    OutputUAV[pixel] = float4(elev, region, saturate(slope * 0.15), saturate(detail));
}
