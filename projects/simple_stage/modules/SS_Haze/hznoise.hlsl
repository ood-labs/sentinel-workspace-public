// SS_Haze / hznoise — the wisps' noise: a 64^3 volume of domain-warped fractal value noise that tiles every 64
// texels (his hznoise), baked once into hzN on the frames the field is fresh and copied into the Haze Field's
// padded atlas every frame (hzfield). The renderer erodes the simulated haze with it, carried by the air.
#include "hz_grid.hlsli"
StructuredBuffer<float4> T : register(t0);
RWStructuredBuffer<float> N : register(u0);

// value noise on a lattice that repeats every `per` cells
float vnP(float3 p, float per)
{
    float3 i = floor(p), f = frac(p);
    f = f * f * (3.0 - 2.0 * f);
    float3 i0 = fmod(i, per), i1 = fmod(i + 1.0, per);
    float a = hzHash(float3(i0.x, i0.y, i0.z)), b = hzHash(float3(i1.x, i0.y, i0.z));
    float c = hzHash(float3(i0.x, i1.y, i0.z)), d = hzHash(float3(i1.x, i1.y, i0.z));
    float e = hzHash(float3(i0.x, i0.y, i1.z)), g = hzHash(float3(i1.x, i0.y, i1.z));
    float h = hzHash(float3(i0.x, i1.y, i1.z)), k = hzHash(float3(i1.x, i1.y, i1.z));
    return lerp(lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y), lerp(lerp(e, g, f.x), lerp(h, k, f.x), f.y), f.z);
}

[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint i = id.x;
    if (i >= 262144u || T[0].z < 0.5) return;
    float3 c = float3(i & 63u, (i >> 6) & 63u, i >> 12);
    // a slow periodic offset field, so the billows curl instead of sitting on a lattice
    float3 w = float3(vnP(c / 16.0 + 3.1, 4.0), vnP(c / 16.0 + 9.7, 4.0), vnP(c / 16.0 + 17.3, 4.0)) - 0.5;
    float3 q = c + w * 14.0;
    N[i] = vnP(q / 8.0, 8.0) * 0.55 + vnP(q / 4.0 + 5.2, 16.0) * 0.3 + vnP(q / 2.0 + 11.7, 32.0) * 0.15;
}
// rev 3 (headers changed: the shader cache keys on this file)
