// ---------------------------------------------------------------------------
// CLOTH LAB - metrics reduction.
//
// Reduces the solved cloth into a handful of scalars that become control
// outputs, so strain and energy can be read as numbers (and driven into the
// desk's telemetry traces) instead of inferred from the picture.
// ---------------------------------------------------------------------------

#include "cloth_common.hlsli"

StructuredBuffer<ClothPoint> Points : register(t0);
RWStructuredBuffer<float4>   Metrics : register(u0);

#define RED_GROUP 1024u

groupshared float rStrainSum[RED_GROUP];
groupshared float rStrainMax[RED_GROUP];
groupshared float rSpeedSum[RED_GROUP];
groupshared float rSpeedMax[RED_GROUP];
groupshared float rEnergy[RED_GROUP];
groupshared float rTorn[RED_GROUP];
groupshared float rClear[RED_GROUP];

float3 colliderCenterM(uint s)
{
    if (s == 0u) return sphere_a_pos;
    if (s == 1u) return sphere_b_pos;
    return sphere_c_pos;
}

float colliderRadiusM(uint s)
{
    if (s == 0u) return sphere_a_radius;
    if (s == 1u) return sphere_b_radius;
    return sphere_c_radius;
}

// Signed clearance to the nearest collider surface. Negative means the cloth is
// inside a sphere, which is the one thing collision handling must never allow;
// reporting it as a number beats squinting at the render.
float clearanceOf(float3 p)
{
    float best = 1e9;
    [loop]
    for (uint s = 0u; s < 3u; ++s)
    {
        if ((int)s >= collider_count) break;
        best = min(best, length(p - colliderCenterM(s)) - colliderRadiusM(s));
    }
    return best;
}

[numthreads(1024, 1, 1)]
void main(uint3 gtid : SV_GroupThreadID)
{
    uint t = gtid.x;

    ClothPoint a = Points[t];
    ClothPoint b = Points[t + RED_GROUP];

    float sa = a.strain, sb = b.strain;
    float va = length(a.velocity), vb = length(b.velocity);
    uint  ta = countbits((a.flags >> 8u) & 0xFu);
    uint  tb = countbits((b.flags >> 8u) & 0xFu);

    rStrainSum[t] = sa + sb;
    rStrainMax[t] = max(sa, sb);
    rSpeedSum[t]  = va + vb;
    rSpeedMax[t]  = max(va, vb);
    rEnergy[t]    = 0.5 * (va * va + vb * vb);
    rTorn[t]      = (float)(ta + tb);
    rClear[t]     = min(clearanceOf(a.position), clearanceOf(b.position));
    GroupMemoryBarrierWithGroupSync();

    [loop]
    for (uint stride = RED_GROUP / 2u; stride > 0u; stride >>= 1u)
    {
        if (t < stride)
        {
            rStrainSum[t] += rStrainSum[t + stride];
            rStrainMax[t]  = max(rStrainMax[t], rStrainMax[t + stride]);
            rSpeedSum[t]  += rSpeedSum[t + stride];
            rSpeedMax[t]   = max(rSpeedMax[t], rSpeedMax[t + stride]);
            rEnergy[t]    += rEnergy[t + stride];
            rTorn[t]      += rTorn[t + stride];
            rClear[t]      = min(rClear[t], rClear[t + stride]);
        }
        GroupMemoryBarrierWithGroupSync();
    }

    if (t != 0u) return;

    float inv = 1.0 / (float)PCOUNT;
    Metrics[0] = float4(rStrainSum[0] * inv, rStrainMax[0],
                        rSpeedSum[0] * inv,  rSpeedMax[0]);
    // Torn edges are counted once per owning vertex, so the sum is already the
    // edge count, not double it.
    Metrics[1] = float4(rEnergy[0] * inv, rTorn[0], (float)PCOUNT, _DeltaTime);
    Metrics[2] = float4(rClear[0], 0.0, 0.0, 0.0);
}
