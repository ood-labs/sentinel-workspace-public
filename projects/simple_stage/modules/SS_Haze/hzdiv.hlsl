// SS_Haze / hzdiv — the net outflow of every air cell, the right-hand side of the pressure equation (MG
// level 0 .y). Faces into solids and the hall's boundary are already 0 (hzforce). .w keeps the residual of
// last frame's pressure against this divergence (the warm start; hzstats compares it with what is left
// after the solve).
#include "hz_grid.hlsli"
RWStructuredBuffer<float4> A : register(u0);

[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint i = id.x;
    if (i >= AN) return;
    int3 c = aCoord(i);
    float4 m = A[RA_MG + i];
    float D = 0.0, rb = 0.0;
    if (m.z < 0.5)
    {
        float4 a = A[RA_U + i];
        float ux = c.x + 1 < AX ? A[RA_U + aIdx(c + int3(1, 0, 0))].x : 0.0;
        float vy = c.y + 1 < AY ? A[RA_U + aIdx(c + int3(0, 1, 0))].y : 0.0;
        float wz = c.z + 1 < AZ ? A[RA_U + aIdx(c + int3(0, 0, 1))].z : 0.0;
        D = (ux - a.x) + (vy - a.y) + (wz - a.z);
        float sum = 0.0, nn = 0.0;
        const int3 NBs[6] = { int3(1, 0, 0), int3(-1, 0, 0), int3(0, 1, 0), int3(0, -1, 0), int3(0, 0, 1), int3(0, 0, -1) };
        [unroll] for (uint k = 0; k < 6u; k++)
        {
            int3 q = c + NBs[k];
            if (!aIn(q)) continue;
            float4 mq = A[RA_MG + aIdx(q)];
            if (mq.z > 0.5) continue;
            sum += mq.x; nn += 1.0;
        }
        rb = D - (sum - (nn + 1e-4) * m.x);
    }
    m.y = D;
    m.w = rb;
    A[RA_MG + i] = fin4(m);
}
// rev 3 (headers changed: the shader cache keys on this file)
