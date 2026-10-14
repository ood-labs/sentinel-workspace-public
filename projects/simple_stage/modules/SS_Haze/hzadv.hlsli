// SS_Haze / hzadv — MacCormack advection of the air (face velocities + centre temperature), included by
// hzadv1 (HZ_ADV_PASS 1: forward estimate U -> HAT) and hzadv2 (2: correction U, HAT -> NEW).
//
//   pass 1   phi_hat(x) = phi_n(x - dt u(x))                         (RK2 back-trace, trilinear)
//   pass 2   phi_chk(x) = phi_hat(x + dt u(x))                       (the same step run backwards)
//            phi_new(x) = phi_hat(x) + (phi_n(x) - phi_chk(x)) / 2      (second order in space and time)
//            a result outside the range of the 8 phi_n samples the back-trace landed between falls back
//            to phi_hat (Selle et al. 2008): no new extrema, so no ringing and no blow-up.
// The trace velocity is the start-of-frame air (pass:hzvpack, hardware trilinear).
#include "hz_grid.hlsli"
StructuredBuffer<float4> T : register(t0);
Texture2D<float4> Vel : register(t1);
RWStructuredBuffer<float4> A : register(u0);

static HzDomain gD;
float3 velAt(float3 x) { return atlasSample(Vel, LinearSampler, (x - gD.lo) / gD.h - 0.5, AX, AY, AZ, 0u).xyz; }
float3 trace(float3 p, float dt)
{
    float3 mid = p - 0.5 * dt * velAt(p);
    return p - dt * velAt(mid);
}
// one stored quantity (comp 0..2 = u, v, w on their faces; 3 = temperature at the centre) of the region at
// `base` at x, with the range of the 8 samples it was blended from
float compAt(uint base, float3 x, uint comp, out float mn, out float mx)
{
    float3 axis = float3(comp == 0u, comp == 1u, comp == 2u);
    float3 off = 0.5 - 0.5 * axis;
    float3 g = (x - gD.lo) / gD.h - off;
    float3 hi = float3(AX - 1, AY - 1, AZ - 1) + axis;      // faces run 0..N on their own axis
    g = clamp(g, 0.0, hi);
    int3 c0 = min((int3)floor(g), (int3)hi - 1);
    float3 f = g - (float3)c0;
    float acc[8];
    [unroll] for (uint k = 0; k < 8u; k++)
    {
        int3 c = c0 + int3(k & 1u, (k >> 1) & 1u, k >> 2);
        int3 cc = min(c, int3(AX - 1, AY - 1, AZ - 1));
        float4 q = A[base + aIdx(cc)];
        float v;
        if (comp < 3u)
        {
            // the faces on the hall's boundary (index 0 and N on their axis) are walls: always 0
            int ca = (int)dot((float3)c, axis), ha = (int)dot(hi, axis);
            v = (ca <= 0 || ca >= ha) ? 0.0 : dot(q.xyz, axis);
        }
        else v = q.w;
        acc[k] = v;
    }
    mn = min(min(min(acc[0], acc[1]), min(acc[2], acc[3])), min(min(acc[4], acc[5]), min(acc[6], acc[7])));
    mx = max(max(max(acc[0], acc[1]), max(acc[2], acc[3])), max(max(acc[4], acc[5]), max(acc[6], acc[7])));
    return lerp(lerp(lerp(acc[0], acc[1], f.x), lerp(acc[2], acc[3], f.x), f.y),
                lerp(lerp(acc[4], acc[5], f.x), lerp(acc[6], acc[7], f.x), f.y), f.z);
}
float3 compPos(int3 c, uint comp) { return aCentre(gD, c) - 0.5 * gD.h * float3(comp == 0u, comp == 1u, comp == 2u); }

[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint i = id.x;
    if (i >= AN) return;
    gD = hzDomain(T[1], T[2], T[3]);
    float dt = T[0].w;
    int3 c = aCoord(i);
#if HZ_ADV_PASS == 2
    float4 hat4 = A[RA_HAT + i], now4 = A[RA_U + i];
#endif
    float outv[4] = { 0.0, 0.0, 0.0, 0.0 };
    [unroll] for (uint comp = 0; comp < 4u; comp++)
    {
        if (comp < 3u && c[min(comp, 2u)] == 0) { outv[comp] = 0.0; continue; }   // boundary face
        float3 p = compPos(c, comp);
        float3 src = trace(p, dt);
        float mn, mx;
#if HZ_ADV_PASS == 1
        outv[comp] = compAt(RA_U, src, comp, mn, mx);
#else
        float hat = comp == 0u ? hat4.x : (comp == 1u ? hat4.y : (comp == 2u ? hat4.z : hat4.w));
        float now = comp == 0u ? now4.x : (comp == 1u ? now4.y : (comp == 2u ? now4.z : now4.w));
        float m0, m1;
        compAt(RA_U, src, comp, mn, mx);                              // the range for the limiter
        float chk = compAt(RA_HAT, trace(p, -dt), comp, m0, m1);
        float r = hat + 0.5 * (now - chk);
        outv[comp] = (r < mn || r > mx) ? hat : r;
#endif
    }
#if HZ_ADV_PASS == 1
    A[RA_HAT + i] = fin4(float4(outv[0], outv[1], outv[2], outv[3]));
#else
    A[RA_NEW + i] = fin4(float4(outv[0], outv[1], outv[2], outv[3]));
#endif
}
