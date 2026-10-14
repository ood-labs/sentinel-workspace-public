// SS_Haze / hzsum — every projection line of hz_proj.hlsli, one thread each. Plan lines run with x fastest, so
// neighbouring threads read neighbouring cells on every step down the hall's height.
#include "hz_grid.hlsli"
#include "hz_proj.hlsli"
StructuredBuffer<float4> T : register(t0);
StructuredBuffer<float> D : register(t1);
StructuredBuffer<float4> A : register(t2);
RWStructuredBuffer<float4> P : register(u0);

static HzDomain gD;
float3 airVel(int3 c)
{
    float4 a = A[RA_U + aIdx(c)];
    float ux = c.x + 1 < AX ? A[RA_U + aIdx(c + int3(1, 0, 0))].x : 0.0;
    float vy = c.y + 1 < AY ? A[RA_U + aIdx(c + int3(0, 1, 0))].y : 0.0;
    float wz = c.z + 1 < AZ ? A[RA_U + aIdx(c + int3(0, 0, 1))].z : 0.0;
    return 0.5 * float3(a.x + ux, a.y + vy, a.z + wz);
}

[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint j = id.x;
    if (j >= P_END) return;
    gD = hzDomain(T[1], T[2], T[3]);
    uint cur = (1u - ((uint)T[0].x & 1u)) * FN;
    float4 o = 0;
    if (j < P_AE)
    {
        // the haze
        bool sect = j < P_FP;
        uint k = sect ? j : j - P_FP;
        int3 c = sect ? int3(0, k / FZ, k % FZ) : int3(k % FX, 0, k / FX);
        uint n = sect ? (uint)FX : (uint)FY;
        float s = 0.0, mx = 0.0, cnt = 0.0;
        [loop] for (uint i = 0; i < n; i++)
        {
            int3 q = c;
            if (sect) q.x = (int)i; else q.y = (int)i;
            if (inHall(gD, fCentre(gD, q)))
            {
                float d = D[cur + fIdx(q)];
                s += d; mx = max(mx, d); cnt += 1.0;
            }
        }
        o = float4(cnt > 0.5 ? s / cnt : 0.0, mx, s, cnt);
    }
    else
    {
        // the air
        bool sect = j < P_AP;
        uint k = sect ? j - P_AE : j - P_AP;
        int3 c = sect ? int3(0, k / AZ, k % AZ) : int3(k % AX, 0, k / AX);
        uint n = sect ? (uint)AX : (uint)AY;
        float sp = 0.0, tk = 0.0, top = 0.0, d0 = 0.0, d1 = 0.0, cnt = 0.0;
        [loop] for (uint i = 0; i < n; i++)
        {
            int3 q = c;
            if (sect) q.x = (int)i; else q.y = (int)i;
            float4 m = A[RA_MG + aIdx(q)];
            if (m.z < 0.5)                                                 // open air, not a solid or outside
            {
                float v = length(airVel(q));
                sp += v; top = max(top, v); tk += A[RA_U + aIdx(q)].w; cnt += 1.0;
                d0 += abs(m.y); d1 += abs(m.w);
            }
        }
        float inv = cnt > 0.5 ? 1.0 / cnt : 0.0;
        o = sect ? float4(sp * inv, tk * inv, d0, d1) : float4(sp * inv, tk * inv, top, 0.0);
    }
    P[j] = fin4(o);
}
// rev 3 (headers changed: the shader cache keys on this file)
