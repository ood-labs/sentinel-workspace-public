// BR_Render / probes.hlsl -- the irradiance volume (multi-bounce GI) in REST space.
//
// One 64-thread group per probe. The light arriving at a probe is split into three parts that
// never overlap, so none of them is counted twice:
//
//   WINDOWS   the outside world seen through each opening. Added ANALYTICALLY: each opening is
//             three stacked area lights (street, canopy/skyline, sky -- aperture.hlsl measures
//             them), projected onto L1 SH from the exact solid angle and irradiance vector of the
//             rectangle, times one soft visibility cone per opening. No noise at all.
//   SUN PATCH the bright parallelograms the low sun throws on the floor, projected from the light
//             tunnel each opening makes through a 30 cm wall. 16 rays IMPORTANCE-SAMPLE them
//             (area-uniform on the patch, pdf converted to solid angle) and count only the direct
//             sun at what they hit -- the rug, a sofa, the floor.
//   THE REST  44 stratified rays (spherical Fibonacci, rotated per frame): bounce light from
//             every surface (fed back from the volume itself, so one bounce becomes many) plus
//             direct sun at hits OUTSIDE the patch cones. Rays that leave the room return
//             nothing: the window term already holds the outside.
//
// The volume is traced in rest space on purpose: under a trip warp the bounce light travels with
// the surfaces that produced it, while direct light and shadows stay live in warped space.
#include "render_common.hlsli"

StructuredBuffer<float4> SkyLut : register(t1);
StructuredBuffer<float4> Aper : register(t2);
RWStructuredBuffer<ProbeRec> Probes : register(u0);

#define NU 32           // stratified bounce rays
#define NP 28           // sun-patch rays (the high-variance part gets the most samples)
#define NV 4            // window visibility cones (first four openings that let light in)
#define NT 64

groupshared float4 gsR[NT];
groupshared float4 gsG[NT];
groupshared float4 gsB[NT];
groupshared float gsBack[NT];
groupshared float gsVis[NV];

float3 sphFib(int i, int n)
{
    float k = ((float)i + 0.5) / (float)n;
    float phi = (float)i * 2.39996323;
    float z = 1.0 - 2.0 * k;
    float r = sqrt(saturate(1.0 - z * z));
    return float3(r * cos(phi), z, r * sin(phi));
}

float3x3 frameRotation(uint seed)
{
    float a = brHash01(seed) * 6.2831853, b = brHash01(seed * 3u + 1u) * 2.0 - 1.0, c = brHash01(seed * 7u + 5u) * 6.2831853;
    float3 axis = float3(sqrt(1.0 - b * b) * cos(a), b, sqrt(1.0 - b * b) * sin(a));
    float s = sin(c), co = cos(c), t = 1.0 - co;
    return float3x3(t * axis.x * axis.x + co, t * axis.x * axis.y - s * axis.z, t * axis.x * axis.z + s * axis.y,
                    t * axis.x * axis.y + s * axis.z, t * axis.y * axis.y + co, t * axis.y * axis.z - s * axis.x,
                    t * axis.x * axis.z - s * axis.y, t * axis.y * axis.z + s * axis.x, t * axis.z * axis.z + co);
}

float3 probeIrr(float3 x, float3 n)
{
    ProbeGrid g = probeGrid();
    float3 gc = (x + n * 0.12 - g.origin) / g.spacing;
    int3 c0 = clamp((int3)floor(gc), int3(0, 0, 0), g.n - 2);
    float3 f = saturate(gc - (float3)c0);
    float3 sum = 0; float ws = 0;
    [loop] for (int k = 0; k < 8; k++)
    {
        int3 o = int3(k & 1, (k >> 1) & 1, k >> 2);
        int3 c = c0 + o;
        float3 w3 = lerp(1.0 - f, f, (float3)o);
        ProbeRec pr = Probes[probeIndex(g, c)];
        float3 dir = normalize(probePos(g, c) - x + 1e-5);
        float back = saturate(dot(dir, n) * 0.5 + 0.5);
        // an invalid probe (inside a solid) keeps a sliver of weight, so a surface whose every
        // neighbour is invalid is dim, never black
        float w = w3.x * w3.y * w3.z * (saturate(pr.meta.x) * 0.97 + 0.03) * (back * back + 0.05);
        if (!(abs(pr.r.x) < 1e5)) w = 0.0;
        sum += shIrradiance(pr, n) * w; ws += w;
    }
    return (ws > 1e-4) ? sum / ws : 0.0;
}

bool isAperture(BROpening o) { return o.active && (brOpenIsGlazed(o.kind) || o.kind == OPEN_ARCH); }

// The floor parallelogram P0 + u E1 + v E2 (u, v in 0..1) that the sun paints through opening o:
// the interior-face rectangle clipped by the street-face rectangle seen along the sun (the light
// tunnel), projected down the sun ray onto y = 0.
bool sunPatch(BROpening o, BRRoom R, float3 s, out float3 P0, out float3 E1, out float3 E2)
{
    P0 = 0; E1 = 0; E2 = 0;
    float2 n2 = brWallNormal(o.wall);
    float sn = s.x * n2.x + s.z * n2.y;          // sun must be on the street side
    if (sn > -0.02 || s.y < 0.03) return false;
    float3 ta = brWallAlongX(o.wall) ? float3(1, 0, 0) : float3(0, 0, 1);
    float k = R.T / -sn;
    float da = dot(s, ta) * k, dy = s.y * k;
    float hw = o.width * 0.5;
    float a0 = max(o.a - hw, o.a - hw - da), a1 = min(o.a + hw, o.a + hw - da);
    float y0 = max(o.sill, o.sill - dy), y1 = min(o.sill + o.height, o.sill + o.height - dy);
    if (a1 - a0 < 0.02 || y1 - y0 < 0.02) return false;
    float2 c = brWallPoint(R, o.wall, a0, 0.0);
    float3 C = float3(c.x, y0, c.y);
    P0 = C - s * (y0 / s.y);
    E1 = ta * (a1 - a0);
    E2 = -float3(s.x, 0.0, s.z) * ((y1 - y0) / s.y);
    return true;
}

// Is floor point q inside parallelogram (P0, E1, E2)?
bool inPatch(float2 q, float3 P0, float3 E1, float3 E2)
{
    float det = E1.x * E2.z - E1.z * E2.x;
    if (abs(det) < 1e-6) return false;
    float2 d = q - P0.xz;
    float u = (d.x * E2.z - d.y * E2.x) / det;
    float v = (E1.x * d.y - E1.z * d.x) / det;
    return u >= 0.0 && u <= 1.0 && v >= 0.0 && v <= 1.0;
}

// Arvo edge term for the irradiance vector of a spherical polygon.
float3 edgeTerm(float3 a, float3 b)
{
    float3 cr = cross(a, b);
    float l = length(cr);
    return (l > 1e-7) ? cr / l * acos(clamp(dot(a, b), -0.99999, 0.99999)) : float3(0, 0, 0);
}

// Solid angle (omega) and irradiance vector (F = integral of w dw) of a quad seen from x.
void quadSolid(float3 x, float3 q0, float3 q1, float3 q2, float3 q3, out float omega, out float3 F)
{
    float3 v0 = normalize(q0 - x), v1 = normalize(q1 - x), v2 = normalize(q2 - x), v3 = normalize(q3 - x);
    float t1 = abs(dot(v0, cross(v1, v2))), t2 = abs(dot(v0, cross(v2, v3)));
    float o1 = 2.0 * atan2(t1 + 1e-9, 1.0 + dot(v0, v1) + dot(v1, v2) + dot(v2, v0));
    float o2 = 2.0 * atan2(t2 + 1e-9, 1.0 + dot(v0, v2) + dot(v2, v3) + dot(v3, v0));
    omega = o1 + o2;
    F = 0.5 * (edgeTerm(v0, v1) + edgeTerm(v1, v2) + edgeTerm(v2, v3) + edgeTerm(v3, v0));
    if (dot(F, v0 + v1 + v2 + v3) < 0.0) F = -F;
}

[numthreads(NT, 1, 1)]
void main(uint3 gid : SV_GroupID, uint3 gtid : SV_GroupThreadID)
{
    ProbeGrid g = probeGrid();
    float4 fr = scFrame();
    uint frame = (uint)fr.x;
    int budget = clamp(gi_budget, 64, 4096);
    int stride = max((g.count + budget - 1) / budget, 1);
    int pi = (int)gid.x * stride + (int)(frame % (uint)stride);
    bool valid = ((int)gid.x < budget) && (pi < g.count);
    // The dispatch is fixed at 4096 groups; this is what makes gi_budget the cost. Without it every
    // group past the budget still marched its 28 sun-patch rays (their `active` comes from the
    // patch weight alone), and GI cost the same at any budget. Uniform per group, before any barrier.
    if (!valid) return;
    int k = (int)gtid.x;
    BRSkyCtx S = scSkyCtx();
    // the bounce sees the canopy at rest: swaying leaves move the dapple on the floor, but the
    // total light through a crown hardly changes -- a live canopy here made the ceiling breathe
    S.wind = 0.0;
    BRRoom R = scRoom();
    float3 sd = S.sunDir;
    bool sunUp = sd.y > 0.03 && sun_direct != 0;
    float3 pp = probePos(g, probeCoord(g, min(pi, g.count - 1)));

    // ---- the openings that let light in, and the sun patches they throw
    int apSlot[NV] = { -1, -1, -1, -1 };
    int nAp = 0;
    int pSlot[NV] = { -1, -1, -1, -1 };
    float3 pP0[NV], pE1[NV], pE2[NV];
    int nPatch = 0;
    [unroll] for (int z = 0; z < NV; z++) { pP0[z] = 0; pE1[z] = 0; pE2[z] = 0; }
    [loop] for (int oi = 0; oi < SHELL_OPEN_MAX; oi++)
    {
        BROpening o = scOpen(oi);
        if (!isAperture(o)) continue;
        if (nAp < NV) { apSlot[nAp] = oi; nAp++; }
        float3 P0, E1, E2;
        if (sunUp && nPatch < NV && sunPatch(o, R, sd, P0, E1, E2))
        {
            pSlot[nPatch] = oi; pP0[nPatch] = P0; pE1[nPatch] = E1; pE2[nPatch] = E2; nPatch++;
        }
    }

    // ---- this thread's ray
    int kind = (k < NU) ? 0 : ((k < NU + NP) ? 1 : 2);         // 0 stratified, 1 sun patch, 2 window cone
    float3 dir = float3(0, 1, 0);
    float weight = 0.0;           // SH weight of this ray's radiance
    bool sunHere = true;          // may this ray's hit count direct sun?
    float tMax = 24.0;
    float coneK = 1.0;
    bool active = valid;
    if (kind == 0)
    {
        float3x3 rot = frameRotation(frame * 1664525u + 1013904223u);
        dir = normalize(mul(rot, sphFib(k, NU)));
        weight = 4.0 * 3.14159265 / (float)NU;
        // directions inside a patch cone belong to the patch rays
        if (dir.y < -1e-3 && nPatch > 0)
        {
            float2 q = pp.xz + dir.xz * (pp.y / -dir.y);
            bool inRoom = q.x > R.x0 && q.x < R.x1 && q.y > R.z0 && q.y < R.z1;
            [unroll] for (int pc = 0; pc < NV; pc++)
                if (pc < nPatch && inRoom && inPatch(q, pP0[pc], pE1[pc], pE2[pc])) sunHere = false;
        }
    }
    else if (kind == 1)
    {
        int p = k - NU;
        if (nPatch == 0) active = false;
        else
        {
            int j = p % nPatch;
            int idx = p / nPatch;
            int nj = (NP - 1 - j) / nPatch + 1;                    // rays that landed on patch j
            float h1 = brHash01((uint)(frame * 977u + (uint)pi * 131u + (uint)k * 7919u));
            float h2 = brHash01((uint)(frame * 613u + (uint)pi * 389u + (uint)k * 104729u + 17u));
            float3 P0 = pP0[0], E1 = pE1[0], E2 = pE2[0];
            [unroll] for (int pc2 = 1; pc2 < NV; pc2++) if (pc2 == j) { P0 = pP0[pc2]; E1 = pE1[pc2]; E2 = pE2[pc2]; }
            // jittered 2 x ceil(nj/2) grid: two columns across the window, rows down the patch.
            // When nj is odd one cell is skipped; which one rotates every frame, so no cell is
            // ever starved and the weight below stays unbiased over time.
            int rowsN = (nj + 1) / 2;
            int cells = rowsN * 2;
            int cell = (idx + (int)(frame % (uint)cells)) % cells;
            float3 P = P0 + E1 * (((float)(cell % 2) + h1) * 0.5) + E2 * (((float)(cell / 2) + h2) / (float)rowsN);
            bool inRoom = P.x > R.x0 && P.x < R.x1 && P.z > R.z0 && P.z < R.z1;
            float3 dv = P - pp;
            float d2 = dot(dv, dv);
            dir = dv * rsqrt(max(d2, 1e-6));
            float area = abs(E1.x * E2.z - E1.z * E2.x);
            // pdf (solid angle) = d^2 / (A cos) ; weight = 1 / (n_j pdf)
            weight = (inRoom && dir.y < -0.02) ? area * (-dir.y) / ((float)nj * max(d2, 1e-4)) : 0.0;
            active = weight > 0.0;
            tMax = sqrt(d2) + 0.05;
        }
    }
    else
    {
        int jv = k - NU - NP;
        active = valid && jv < nAp;
        if (active)
        {
            int slot = apSlot[0];
            [unroll] for (int a2 = 1; a2 < NV; a2++) if (a2 == jv) slot = apSlot[a2];
            BROpening o = scOpen(slot);
            float2 c2 = brWallPoint(R, o.wall, o.a, 0.0);
            float3 c = float3(c2.x, o.sill + o.height * 0.5, c2.y);
            float3 dv = c - pp;
            float dl = length(dv);
            dir = dv / max(dl, 1e-4);
            tMax = dl - 0.25;                 // stop short of the sashes: only the room may occlude
            coneK = dl / max(0.5 * min(o.width, o.height), 0.05);
        }
    }

    // phase 0: march, 1: normal taps, 2: sun shadow, 3: done -- one map call site
    const float3 TET[4] = { float3(1, -1, -1), float3(-1, -1, 1), float3(-1, 1, -1), float3(1, 1, 1) };
    int phase = active ? 0 : 3;
    float t = 0.02;
    int tap = 0;
    float3 hp = pp, hn = 0;
    SHit hh = shit(1e9, 0, 0, -1);
    bool hit = false, back = false;
    float sunT = 0.0, sunVis = 0.0;
    float coneRes = 1.0;
    int steps = 0;
    [loop] for (int i = 0; i < 140; i++)
    {
        if (phase == 3) break;
        float3 x = (phase == 0) ? pp + dir * t : ((phase == 1) ? hp + TET[tap] * 0.003 : hp + hn * 0.01 + sd * sunT);
        SHit h = mapCoarse(x);
        steps++;
        if (phase == 0)
        {
            if (i == 0 && h.d < 0.0 && kind == 0) { back = true; phase = 3; }
            else if (kind == 2)
            {
                coneRes = min(coneRes, coneK * h.d / max(t, 0.05));
                if (h.d < 0.002) { coneRes = 0.0; phase = 3; }
                else { t += max(h.d, 0.01); if (t >= tMax || steps > 64) phase = 3; }
            }
            else if (h.d < 0.004) { hit = true; hh = h; hp = x; phase = 1; }
            else
            {
                t += h.d;
                if (outsideBuilding(x) || t > tMax || steps > 80) phase = 3;
            }
        }
        else if (phase == 1)
        {
            hn += TET[tap] * h.d;
            tap++;
            if (tap >= 4)
            {
                hn = normalize(hn + 1e-9);
                if (dot(hn, dir) > 0.0 && kind == 0) { back = true; phase = 3; }      // inside a solid
                else phase = (sunUp && sunHere && dot(hn, sd) > 0.0) ? 2 : 3;
            }
        }
        else
        {
            if (h.d < 0.002) { sunVis = 0.0; phase = 3; }
            else
            {
                sunT += h.d;
                if (outsideBuilding(x)) { sunVis = 0.88 * brCanopyTransmitPen(x, sd, S, 0.0, sunT, scSunSoft()); phase = 3; }
                else if (sunT > 20.0 || steps > 136) { sunVis = 0.0; phase = 3; }
            }
        }
    }

    float3 L = 0;
    if (hit && !back && kind != 2)
    {
        BRMat m = scMat(hh.mat);
        float3 alb = m.base * (1.0 - m.metal * 0.5);
        if (m.family == FAM_PARQUET) alb = lerp(m.second, m.base, 0.6);
        float3 Esun = (sunHere && sunUp) ? S.sunRad * saturate(dot(hn, sd)) * sunVis : float3(0, 0, 0);
        if (kind == 0)
        {
            float3 Eind = probeIrr(hp, hn) * gi_bounce + lampIrradiance(hp + hn * 0.01, hn);
            L = alb * (1.0 / 3.14159265) * (Esun + Eind);
            if (m.family == FAM_EMISSIVE) L += m.base * 4.0;
        }
        else
        {
            L = alb * (1.0 / 3.14159265) * Esun;
        }
    }
    L = min(L, 200.0);
    float4 b = shBasis(dir) * weight;
    gsR[k] = L.r * b; gsG[k] = L.g * b; gsB[k] = L.b * b;
    gsBack[k] = (back && kind == 0) ? 1.0 : 0.0;
    if (kind == 2 && k - NU - NP < NV) gsVis[k - NU - NP] = active ? smoothstep(0.0, 1.0, saturate(coneRes)) : 1.0;
    GroupMemoryBarrierWithGroupSync();

    if (k == 0 && valid)
    {
        float4 sr = 0, sg = 0, sb = 0; float nb = 0;
        [loop] for (int j = 0; j < NT; j++) { sr += gsR[j]; sg += gsG[j]; sb += gsB[j]; nb += gsBack[j]; }

        // windows: three stacked area lights per opening, exact solid angle + irradiance vector
        [loop] for (int oi2 = 0; oi2 < SHELL_OPEN_MAX; oi2++)
        {
            BROpening o = scOpen(oi2);
            if (!isAperture(o)) continue;
            float vis = 1.0;
            [unroll] for (int a3 = 0; a3 < NV; a3++) if (apSlot[a3] == oi2) vis = gsVis[a3];
            float hw = o.width * 0.5;
            float2 w0 = brWallPoint(R, o.wall, o.a - hw, 0.0), w1 = brWallPoint(R, o.wall, o.a + hw, 0.0);
            [unroll] for (int row = 0; row < 3; row++)
            {
                float4 lr = Aper[oi2 * 3 + row];
                if (lr.w < 0.5) continue;
                float ya = o.sill + o.height * (float)row / 3.0, yb = o.sill + o.height * (float)(row + 1) / 3.0;
                float om; float3 F;
                quadSolid(pp, float3(w0.x, ya, w0.y), float3(w1.x, ya, w1.y), float3(w1.x, yb, w1.y), float3(w0.x, yb, w0.y), om, F);
                float4 c = float4(0.282095 * om, 0.488603 * F.y, 0.488603 * F.z, 0.488603 * F.x) * vis;
                float3 Lw = max(lr.rgb, 0.0);
                sr += Lw.r * c; sg += Lw.g * c; sb += Lw.b * c;
            }
        }

        ProbeRec old = Probes[pi];
        bool sane = abs(old.r.x) < 1e5 && abs(old.g.x) < 1e5 && abs(old.b.x) < 1e5 && abs(old.meta.y) < 1e7 && old.meta.y >= 0.0;
        bool fresh = abs(sr.x) < 1e5 && abs(sg.x) < 1e5 && abs(sb.x) < 1e5;
        if (!fresh) { sr = 0; sg = 0; sb = 0; }
        float n = (sane && reset_accum == 0) ? old.meta.y : 0.0;
        float alpha = max(1.0 / (n + 1.0), gi_hysteresis);
        ProbeRec nr;
        nr.r = sane ? lerp(old.r, sr, alpha) : sr;
        nr.g = sane ? lerp(old.g, sg, alpha) : sg;
        nr.b = sane ? lerp(old.b, sb, alpha) : sb;
        float vNow = (nb / (float)NU < 0.2) ? 1.0 : 0.0;
        float vOld = sane ? old.meta.x : vNow;
        nr.meta = float4(lerp(vOld, vNow, 0.25), min(n + 1.0, 1.0e6), 0.0, (float)frame);
        Probes[pi] = nr;
    }
}
