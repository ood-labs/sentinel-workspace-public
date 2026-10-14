// SS_Haze / hzstats — the numbers the preview prints and the control outputs publish, reduced from the
// projections (hz_proj.hlsli) by one group:
//   S[0] = (mean haze in the hall, densest haze, fastest air m/s, divergence left after the solve / before it)
//   S[1] = each hazer's output now (hzOutput: 0.08 a trickle, ~1 a burst, more when all four go together)
//   S[2] = (all-together level 0..1, mean temperature above ambient K, 0, 1 = a live field)
//   S[3] = (cell size m, dt, 0, 0)
#include "hz_grid.hlsli"
#include "hz_proj.hlsli"
StructuredBuffer<float4> T : register(t0);
StructuredBuffer<float4> P : register(t1);
RWStructuredBuffer<float4> S : register(u0);

groupshared float4 gsA[256];
groupshared float4 gsB[256];

[numthreads(256, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    // a = (haze sum, haze cells, div before, div after)   b = (densest haze, fastest air, temperature sum, lines)
    float4 a = 0, b = 0;
    for (uint j = gi; j < P_FP; j += 256u) { float4 p = P[P_FE + j]; a.xy += p.zw; b.x = max(b.x, p.y); }
    for (uint k = gi; k < P_AP - P_AE; k += 256u) { float4 p = P[P_AE + k]; a.zw += p.zw; b.z += p.y; b.w += 1.0; }
    for (uint m = gi; m < P_END - P_AP; m += 256u) b.y = max(b.y, P[P_AP + m].z);
    gsA[gi] = a; gsB[gi] = b;
    GroupMemoryBarrierWithGroupSync();
    [unroll] for (uint s = 128u; s > 0u; s >>= 1)
    {
        if (gi < s)
        {
            float4 a2 = gsA[gi + s], b2 = gsB[gi + s];
            gsA[gi] += a2;
            gsB[gi] = float4(max(gsB[gi].xy, b2.xy), gsB[gi].zw + b2.zw);
        }
        GroupMemoryBarrierWithGroupSync();
    }
    if (gi == 0u)
    {
        a = gsA[0]; b = gsB[0];
        float t = T[0].y;
        float all = hzBurstAll(t, T[3].y);
        S[0] = fin4(float4(a.x / max(a.y, 1.0), b.x, b.y, a.w / max(a.z, 1e-6)));
        S[1] = fin4(float4(hzOutput(0u, t, haze_pump, all), hzOutput(1u, t, haze_pump, all), hzOutput(2u, t, haze_pump, all), hzOutput(3u, t, haze_pump, all)));
        S[2] = fin4(float4(all, b.z / max(b.w, 1.0), 0.0, T[0].x > 3.5 ? 1.0 : 0.0));
        S[3] = fin4(float4(T[1].w, T[0].w, 0.0, 0.0));
    }
}
// rev 3 (headers changed: the shader cache keys on this file)
