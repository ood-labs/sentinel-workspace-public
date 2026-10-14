// One group: the stage bounds of every active fixture origin. Bounds[0] = (min x, min y, min z, fixtures),
// Bounds[1] = (max x, max y, max z, 0).
#include "probe.hlsli"

RWStructuredBuffer<float4> Bounds : register(u0);

groupshared float3 gLo[256];
groupshared float3 gHi[256];
groupshared uint gN[256];

[numthreads(256, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    float3 lo = 1e30, hi = -1e30;
    uint n = 0u;
    uint count = min(_Data0_Count, RP_FIXTURES);
    for (uint i = gi; i < count; i += 256u)
    {
        if (!gdtfFixtureActive(i)) continue;
        float3 p = gdtfFixtureOrigin(i);
        lo = min(lo, p);
        hi = max(hi, p);
        n++;
    }
    gLo[gi] = lo;
    gHi[gi] = hi;
    gN[gi] = n;
    GroupMemoryBarrierWithGroupSync();
    for (uint s = 128u; s > 0u; s >>= 1)
    {
        if (gi < s)
        {
            gLo[gi] = min(gLo[gi], gLo[gi + s]);
            gHi[gi] = max(gHi[gi], gHi[gi + s]);
            gN[gi] += gN[gi + s];
        }
        GroupMemoryBarrierWithGroupSync();
    }
    if (gi == 0u)
    {
        Bounds[0] = float4(gLo[0], (float)gN[0]);
        Bounds[1] = float4(gHi[0], 0.0);
    }
}
