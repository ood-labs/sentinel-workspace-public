// SS_Haze / hzproj — subtract the pressure gradient from every face between two open cells. The result is
// the hall's air for this frame, divergence free, with no flow through a wall or a solid.
#include "hz_grid.hlsli"
RWStructuredBuffer<float4> A : register(u0);

[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint i = id.x;
    if (i >= AN) return;
    int3 c = aCoord(i);
    float4 v = A[RA_U + i];
    float4 m = A[RA_MG + i];
    bool sc = m.z > 0.5;
    float vv[3] = { v.x, v.y, v.z };
    [unroll] for (uint d = 0; d < 3u; d++)
    {
        int3 e = int3(d == 0u, d == 1u, d == 2u);
        if (c[d] == 0) { vv[d] = 0.0; continue; }
        float4 mn = A[RA_MG + aIdx(c - e)];
        vv[d] = (sc || mn.z > 0.5) ? 0.0 : vv[d] - (m.x - mn.x);
    }
    A[RA_U + i] = fin4(float4(vv[0], vv[1], vv[2], v.w));
}
// rev 3 (headers changed: the shader cache keys on this file)
