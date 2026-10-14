// Haze for the fixture engine: a drifting, turbulent smoke density, the light grid that lights it, and the
// forward-scattering phase. Include after fe_tables.hlsli / fe_render.hlsli. Uses the module parameters
// fog_scale, fog_speed, fog_contrast and fog_forward.
#ifndef FE_FOG_HLSLI
#define FE_FOG_HLSLI

// Light grid over the stage (right-handed world, metres). Each cell holds the irradiance from every wash
// and strobe source at its centre.
#define FE_GRID_X 48u
#define FE_GRID_Y 20u
#define FE_GRID_Z 36u
static const float3 FE_GRID_LO = float3(-24.0, 0.0, -18.0);
static const float3 FE_GRID_HI = float3(24.0, 14.0, 18.0);

uint feHashU(uint x)
{
    x ^= x >> 16; x *= 0x7feb352du;
    x ^= x >> 15; x *= 0x846ca68bu;
    x ^= x >> 16;
    return x;
}

float feHash3(int3 p)
{
    uint h = feHashU(asuint(p.x) + feHashU(asuint(p.y) + feHashU(asuint(p.z) + 0x9e3779b9u)));
    return (float)(h & 0x00FFFFFFu) / 16777215.0;
}

float feValueNoise(float3 p)
{
    int3 i = (int3)floor(p);
    float3 f = frac(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = lerp(feHash3(i), feHash3(i + int3(1, 0, 0)), f.x);
    float b = lerp(feHash3(i + int3(0, 1, 0)), feHash3(i + int3(1, 1, 0)), f.x);
    float c = lerp(feHash3(i + int3(0, 0, 1)), feHash3(i + int3(1, 0, 1)), f.x);
    float d = lerp(feHash3(i + int3(0, 1, 1)), feHash3(i + int3(1, 1, 1)), f.x);
    return lerp(lerp(a, b, f.y), lerp(c, d, f.y), f.z);
}

// Smoke density relative to the mean haze (mean ~1): three octaves of value noise through a slow domain warp,
// drifting with the room air. fog_contrast 0 is perfectly even haze.
float feFog(float3 x)
{
    float3 p = x * fog_scale + float3(0.23, 0.035, -0.14) * (_Time * fog_speed);
    float3 w = float3(feValueNoise(p * 0.5 + 17.1), feValueNoise(p * 0.5 + 41.7), feValueNoise(p * 0.5 + 3.3));
    p += (w - 0.5) * 1.6;
    float n = 0.55 * feValueNoise(p) + 0.30 * feValueNoise(p * 2.03 + 7.7) + 0.15 * feValueNoise(p * 4.07 + 13.1);
    return max(0.0, 1.0 + fog_contrast * (2.2 * (n - 0.5)));
}

// A cheaper smoke density for the wide wash cones (sampled many times per pixel): two octaves, no warp.
float feFogLite(float3 x)
{
    float3 p = x * fog_scale + float3(0.23, 0.035, -0.14) * (_Time * fog_speed);
    float n = 0.65 * feValueNoise(p) + 0.35 * feValueNoise(p * 2.03 + 7.7);
    return max(0.0, 1.0 + fog_contrast * (2.2 * (n - 0.5)));
}

// Henyey-Greenstein, normalised so its mean over the sphere is 1. c = cos(angle between the light's travel
// and the direction toward the viewer): beams pointing at the camera read brighter, as they do in haze.
float fePhase(float c)
{
    float g = fog_forward;
    return (1.0 - g * g) / pow(max(1.0 + g * g - 2.0 * g * c, 1e-4), 1.5);
}

// Wide source (wash, strobe face) relative intensity toward unit direction v: cos^m about its axis s1.xyz, with
// m fitted so half peak falls at the documented beam angle (s2.w = 1 + m). s2.rgb carries the peak in kcd.
float feConeIntensity(float4 s1, float4 s2, float3 v)
{
    float c = dot(v, s1.xyz);
    return c > 0.0 ? pow(c, max(s2.w - 1.0, 0.0)) : 0.0;
}

#endif
