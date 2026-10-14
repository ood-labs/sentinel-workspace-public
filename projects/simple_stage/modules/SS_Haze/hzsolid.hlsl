// SS_Haze / hzsolid — which air cells are solid this frame, on every multigrid level (hzA MG .z = 1).
//
// Outside the hall (the walls, the floor, above the ceiling), the stage deck and the DJ's booth. The air
// goes round them. Level 0 is solid where its centre is; a coarser cell only where all of it is (a point
// in each octant), so a coarse level never closes a gap the air can pass through. On a fresh field the
// pressure warm start is cleared too.
#include "hz_grid.hlsli"
StructuredBuffer<float4> T : register(t0);
RWStructuredBuffer<float4> A : register(u0);


[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint i = id.x;
    if (i >= MG_N) return;
    HzDomain d = hzDomain(T[1], T[2], T[3]);
    uint l = i >= MG_OFF[3] ? 3u : (i >= MG_OFF[2] ? 2u : (i >= MG_OFF[1] ? 1u : 0u));
    uint j = i - MG_OFF[l];
    int3 dim = int3(AX >> l, AY >> l, AZ >> l);
    int3 c = int3(j % dim.x, (j / dim.x) % dim.y, j / (dim.x * dim.y));
    float size = d.h * (float)(1u << l);
    float3 ctr = d.lo + ((float3)c + 0.5) * size;
    bool s;
    if (l == 0u) s = hzSolidAt(d, ctr);
    else
    {
        s = true;
        [unroll] for (uint k = 0; k < 8u; k++)
        {
            float3 o = (float3(k & 1u, (k >> 1) & 1u, k >> 2) - 0.5) * 0.5 * size;
            s = s && hzSolidAt(d, ctr + o);
        }
    }
    float4 m = (T[0].z > 0.5) ? 0 : fin4(A[RA_MG + i]);
    m.z = s ? 1.0 : 0.0;
    A[RA_MG + i] = m;
}
// rev 3 (headers changed: the shader cache keys on this file)
