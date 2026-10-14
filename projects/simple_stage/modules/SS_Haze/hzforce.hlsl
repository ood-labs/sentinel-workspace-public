// SS_Haze / hzforce — everything that pushes the air, and the heat in it. NEW (advected) -> U.
//
//   heat        the rig (a moving head is ~0.6 kW, all of it heat, just above where it hangs), the crowd
//               (~150 W per square metre of floor, in a layer from shoulder to head height) and the
//               hazers' warm vapour, each as dT/dt = P / (rho c_p) over a small kernel; the air gives it
//               back to the hall over ~40 s. Heat Plumes scales it (1 = physical).
//   buoyancy    Boussinesq: warm air rises at beta (T - T_amb), beta = g / 293 K, on the v faces
//   swirl       vorticity confinement (Fedkiw, Stam & Jensen 2001): f = eps h (N x w). Swirl sets eps
//   hazers      a fan-driven jet out of each nozzle
//   stage fans  two turbine fans on the deck blowing the haze out over the booth into the front row
//   the house   supply air low at the back of the hall, extract in the roof: a slow turn over the crowd
//   drafts      a slowly evolving noise force (the projection keeps only its divergence-free part)
// Then every face touching a solid or the hall's boundary is zeroed: no flow through walls.
#include "hz_grid.hlsli"
StructuredBuffer<float4> T : register(t0);
RWStructuredBuffer<float4> A : register(u0);
#define SS_FIX_ACTIVE 1u                    // ss_rig.hlsli: a renderable type with an engine mode
#define RHO_CP 1206.0                       // air: 1.2 kg/m3 x 1005 J/(kg K)

static HzDomain gD;
// The fixtures whose heat can reach this group's cells (a group is 64 consecutive cells: part of one row of x, or
// the end of one and the start of the next). Gathered once per group, so a cell tests a handful, not the rig.
#define FIX_CAP 256u
groupshared float3 gsFix[FIX_CAP];
groupshared uint gsFixN;
bool solidAt(int3 c) { return !aIn(c) || A[RA_MG + aIdx(c)].z > 0.5; }
float4 curlAt(int3 c) { return A[RA_CURL + aIdx(clamp(c, 0, int3(AX - 1, AY - 1, AZ - 1)))]; }

float3 vcForce(int3 c)
{
    if (!aIn(c)) return 0;
    float gx = curlAt(c + int3(1, 0, 0)).w - curlAt(c - int3(1, 0, 0)).w;
    float gy = curlAt(c + int3(0, 1, 0)).w - curlAt(c - int3(0, 1, 0)).w;
    float gz = curlAt(c + int3(0, 0, 1)).w - curlAt(c - int3(0, 0, 1)).w;
    float3 g = float3(gx, gy, gz);
    float gl = length(g);
    if (gl < 1e-5) return 0;
    return cross(g / gl, curlAt(c).xyz) * gD.h;
}

// a fan or jet: the air in a disc-shaped region is pulled toward the device's outflow
void jet(inout float3 tv, inout float tw, float3 x, float3 p, float3 d, float speed, float radius, float depth)
{
    float3 r = x - p;
    float along = dot(r, d);
    float3 perp = r - d * along;
    float w = exp(-dot(perp, perp) / (radius * radius)) * exp(-(along * along) / (depth * depth));
    if (w < 1e-3) return;
    tv += d * speed * w;
    tw += w;
}

// the heat put into the air at x, kelvin per second
float heatAt(float3 x)
{
    float q = 0.0;
    // the rig: every placed fixture's head and electronics, just above where it hangs (the group's shortlist)
    uint nf = min(gsFixN, FIX_CAP);
    [loop] for (uint k = 0; k < nf; k++)
    {
        float3 r = x - gsFix[k];
        float d2 = dot(r, r);
        const float s = 0.35;
        if (d2 <= 1.0) q += 600.0 * exp(-d2 / (s * s)) / (5.5683 * s * s * s) / RHO_CP;
    }
    // the crowd: a warm layer from shoulder to head height over the floor in front of the stage
    float yb = x.y - gD.floorY;
    if (yb > 0.7 && yb < 2.0)
    {
        float back = x.z - (HZ_DECK_HD + 0.6);
        float hallBack = gD.zc + 0.5 * gD.L - (HZ_DECK_HD + 0.6);
        float inside = 1.0 - smoothstep(0.5 * gD.W - 2.0, 0.5 * gD.W - 1.0, abs(x.x));
        float dens = smoothstep(0.0, 0.6, back) * (1.0 - smoothstep(hallBack - 6.0, hallBack - 2.0, back)) * lerp(1.0, 0.55, saturate(back / 15.0));
        q += 150.0 * dens * inside / 1.3 / RHO_CP;
    }
    return q;
}

[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID, uint3 gid : SV_GroupID, uint gi : SV_GroupIndex)
{
    gD = hzDomain(T[1], T[2], T[3]);
    // the group's shortlist, before anything returns (AN is a whole number of groups)
    if (gi == 0u) gsFixN = 0u;
    GroupMemoryBarrierWithGroupSync();
    {
        int3 ca = aCoord(gid.x * 64u), cb = aCoord(min(gid.x * 64u + 63u, AN - 1u));
        bool oneRow = ca.y == cb.y && ca.z == cb.z;
        int3 lo = int3(oneRow ? ca.x : 0, ca.z == cb.z ? min(ca.y, cb.y) : 0, ca.z);
        int3 hi = int3(oneRow ? cb.x : AX - 1, ca.z == cb.z ? max(ca.y, cb.y) : AY - 1, cb.z);
        float3 bmin = aCentre(gD, lo) - 1.0, bmax = aCentre(gD, hi) + 1.0;   // heat reaches 1 m
        uint nfix = min(_Data1_Count, 1024u);
        for (uint k = gi; k < nfix; k += 64u)
        {
            float3 hp = _Data1[k].o.xyz + float3(0, 0.25, 0);
            if ((_Data1[k].run[3] & SS_FIX_ACTIVE) != 0u && all(hp >= bmin) && all(hp <= bmax))
            {
                uint slot;
                InterlockedAdd(gsFixN, 1u, slot);
                if (slot < FIX_CAP) gsFix[slot] = hp;
            }
        }
    }
    GroupMemoryBarrierWithGroupSync();
    uint i = id.x;
    if (i >= AN) return;
    if (T[0].z > 0.5) { A[RA_U + i] = 0; return; }                   // a fresh field starts still
    float dt = T[0].w, t = T[0].y;
    float burst = hzBurstAll(t, T[3].y);
    int3 c = aCoord(i);
    float4 v = A[RA_NEW + i];
    float3 xc = aCentre(gD, c);

    // ---- temperature (cell centre): sources, then the slow loss to the hall
    float Tk = v.w;
    if (!solidAt(c))
    {
        Tk += dt * heatAt(xc) * haze_heat;
        [unroll] for (uint m = 0; m < HZ_MACHINES; m++)
        {
            float3 p, dir;
            hzMachine(m, gD.floorY, p, dir);
            float3 r = xc - (p + dir * 0.25);
            Tk += dt * 12.0 * hzOutput(m, t, haze_pump, burst) * exp(-dot(r, r) / 0.09);
        }
    }
    Tk *= exp(-dt / 40.0);
    Tk = clamp(Tk, -60.0, 60.0);
    float vv[3] = { v.x, v.y, v.z };
    float fanSpeed = 7.0 * haze_fans * (0.55 + 0.45 * burst);

    [unroll] for (uint d = 0; d < 3u; d++)
    {
        int3 e = int3(d == 0u, d == 1u, d == 2u);
        if (c[d] == 0 || solidAt(c) || solidAt(c - e)) { vv[d] = 0.0; continue; }
        float3 x = xc - 0.5 * gD.h * (float3)e;
        float f = 0.0;
        if (d == 1u) f += HZ_BETA * 0.5 * (Tk + A[RA_NEW + aIdx(c - e)].w);          // buoyancy
        f += haze_swirl * 0.3 * 0.5 * (vcForce(c)[d] + vcForce(c - e)[d]);         // vorticity confinement
        float3 q = x / 3.0 + float3(t * 0.021, -t * 0.013, t * 0.017) + (float)d * 17.3;
        f += (hzNoise(q) - 0.5) * 0.05 * haze_drift;                               // drafts
        float u = vv[d] + dt * f;

        // jets, fans and vents: the air in each relaxes toward the device's outflow
        float3 tv = 0; float tw = 0;
        [unroll] for (uint m = 0; m < HZ_MACHINES; m++)
        {
            float3 p, dir;
            hzMachine(m, gD.floorY, p, dir);
            float o = hzOutput(m, t, haze_pump, burst);
            if (o > 0.01) jet(tv, tw, x, p + dir * 0.3, dir, 4.5 * min(o, 2.0), 0.22, 0.25);
        }
        if (fanSpeed > 0.01)
        {
            [unroll] for (uint k = 0; k < 2u; k++)
            {
                float side = k == 0u ? -1.0 : 1.0;
                float3 fp = float3(side * (HZ_DECK_HW - 1.0), gD.floorY + HZ_DECK_TOP + 0.75, -HZ_DECK_HD + 2.2);
                jet(tv, tw, x, fp, normalize(float3(-side * 0.32, 0.12, 1.0)), fanSpeed, 0.45, 0.3);
            }
        }
        if (haze_drift > 0.001)
        {
            float back = gD.zc + 0.5 * gD.L - 1.0, top = gD.floorY + gD.Ht - 0.6, sx = 0.5 * gD.W - 2.0;
            jet(tv, tw, x, float3(-sx, gD.floorY + 0.6, back), float3(0, 0, -1), 1.2 * haze_drift, 1.2, 0.6);
            jet(tv, tw, x, float3(sx, gD.floorY + 0.6, back), float3(0, 0, -1), 1.2 * haze_drift, 1.2, 0.6);
            jet(tv, tw, x, float3(-5.0, top, gD.zc + 0.1 * gD.L), float3(0, 1, 0), 1.0 * haze_drift, 1.0, 0.6);
            jet(tv, tw, x, float3(5.0, top, gD.zc + 0.1 * gD.L), float3(0, 1, 0), 1.0 * haze_drift, 1.0, 0.6);
        }
        if (tw > 1e-3)
        {
            float target = tv[d] / tw;
            u = lerp(u, target, 1.0 - exp(-dt * 25.0 * saturate(tw)));
        }
        vv[d] = clamp(u * exp(-0.12 * dt), -30.0, 30.0);      // a little drag: a closed hall must not slosh forever
    }
    A[RA_U + i] = fin4(float4(vv[0], vv[1], vv[2], Tk));
}
// rev 3 (headers changed: the shader cache keys on this file)
