// SS_Haze / hzcheck — the divergence left in each open cell after the projection, into MG level 0 .w (the
// proof hzstats reads: how much of the flow survives the solve). Reads the faces, writes only .w.
#include "hz_grid.hlsli"
RWStructuredBuffer<float4> A : register(u0);

[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint i = id.x;
    if (i >= AN) return;
    int3 c = aCoord(i);
    float4 m = A[RA_MG + i];
    float D = 0.0;
    if (m.z < 0.5)
    {
        float4 a = A[RA_U + i];
        float ux = c.x + 1 < AX ? A[RA_U + aIdx(c + int3(1, 0, 0))].x : 0.0;
        float vy = c.y + 1 < AY ? A[RA_U + aIdx(c + int3(0, 1, 0))].y : 0.0;
        float wz = c.z + 1 < AZ ? A[RA_U + aIdx(c + int3(0, 0, 1))].z : 0.0;
        D = (ux - a.x) + (vy - a.y) + (wz - a.z);
    }
    m.w = D;
    A[RA_MG + i] = fin4(m);
}
// rev 3 (headers changed: the shader cache keys on this file)
