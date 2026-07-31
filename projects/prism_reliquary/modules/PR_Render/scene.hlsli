// PR_Render / scene.hlsli — the SDF scene, assembled entirely from Cast records.
//
// Nothing in here invents a position, a size or a colour. Every primitive is a record read
// at a known slot, which is what makes the whole composition rearrangeable from one node.
//
// Cost discipline: the marcher never scans 96 records. Fixed slot ranges bound each family,
// and the gem lattice is a single indexed read because PR_Plan addresses chips BY CELL.

#ifndef PR_SCENE_HLSLI
#define PR_SCENE_HLSLI

#include "../_shared/relic.hlsli"

StructuredBuffer<CastRec> Cast : register(t0);

// ---------------------------------------------------------------------------
// The pelt.
//
// A fuzzy silhouette is a noise-displaced torus, but evaluating fbm at every march step
// anywhere in the scene is unaffordable. The shell test below is the whole trick: outside
// the pelt the function returns the plain torus minus the maximum fur length, which is a
// strictly conservative distance and costs one torus evaluation. Noise is only paid for
// inside the shell it can actually affect.
// ---------------------------------------------------------------------------
float pr_furLen(CastRec tr) { return tr.radius * 0.185 * tr.dims.y; }

// EXPLORATION AXIS: fur_style. Combed follows the ring, Radial stands the strands off the
// surface, Frizz warps the sample field into itself. All three are shipped presets.
//
// This is factored out because the SHADER also needs it: the strand texture in solids.hlsl
// must be the same field the SDF displaced with, or the colour slides over geometry that
// isn't there. Two copies of this expression would drift apart the first time a style
// changed.
float3 pr_furField(float3 lp, CastRec tr)
{
    if (fur_style == 1)
    {
        // Radial — isotropic 3D noise. Reads as moss or sponge rather than hair, because
        // the field is equally fine in every direction. Kept as a preset: it is the right
        // answer for a soft mineral mass, just not for this reference.
        return lp * (tr.p0 * 8.0);
    }

    // Toroidal coordinates: major angle, minor angle, and radial distance out of the tube.
    float2 pv = float2(length(lp.xz) - tr.radius, lp.y);
    float  u  = atan2(lp.z, lp.x);
    float  v  = atan2(pv.y, pv.x);
    float  r  = length(pv);

    // THE RADIAL AXIS IS DELIBERATELY UNDER-SCALED (2.0 against 9.0). Sampling noise finely
    // across the surface but coarsely along the outward direction STRETCHES each feature
    // into a strand pointing away from the body — which is what hair is. An isotropic field
    // at the same frequency gives evenly-sized lumps, i.e. sponge.
    float3 q = float3(u * tr.radius * tr.p0 * 9.0,
                      v * tr.dims.x * tr.p0 * 9.0,
                      r * tr.p0 * 2.0);

    if (fur_style == 2)
    {
        // Frizz — warp the strands into each other so they clump and kink.
        q += tr.dims.z * 2.2 * float3(pr_vnoise(lp * 5.3),
                                      pr_vnoise(lp * 5.3 + 19.0),
                                      pr_vnoise(lp * 5.3 + 37.0));
    }
    else
    {
        // Combed — a mild lean, so the pelt lies in a direction instead of standing.
        q += tr.dims.z * 0.85 * float3(pr_vnoise(lp * 2.7),
                                       pr_vnoise(lp * 2.7 + 11.0),
                                       pr_vnoise(lp * 2.7 + 23.0));
    }
    return q;
}

// Two octaves, not three. This function is inlined into the march loop, the normal (4x) and
// the AO probe, so every octave costs eight more hash calls in the hottest code in the
// project — the third octave pushed shader compilation past five minutes and was not
// visible at this scale. Fineness comes from fur_density instead.
float pr_strand(float3 lp, CastRec tr) { return pr_ridged(pr_furField(lp, tr), 2); }

float pr_fur(float3 p, CastRec tr, bool cheap)
{
    float3 lp   = pr_qinv(tr.rot, p - tr.pos);
    float  base = pr_torus(lp, tr.radius, tr.dims.x);

    // The editor can change what the hero is made of. A chrome torus is a SMOOTH torus —
    // and skipping the displacement also drops the most expensive field in the scene.
    if (tr.mat != MAT_FUR) return base;

    float  L    = pr_furLen(tr);
    if (base > L + 0.02 || cheap) return base - L;

    return base - L * saturate(pr_strand(lp, tr) * 1.18);
}

// True when p is inside the pelt shell, so the marcher can shorten its step there.
bool pr_inPelt(float3 p, CastRec tr)
{
    float3 lp = pr_qinv(tr.rot, p - tr.pos);
    return pr_torus(lp, tr.radius, tr.dims.x) < pr_furLen(tr) + 0.02;
}

// ---------------------------------------------------------------------------
// A lattice chip. Flattened toward the plate; the divide keeps the bound conservative.
// ---------------------------------------------------------------------------
float pr_chip(float3 p, CastRec g)
{
    float3 lp = pr_qinv(g.rot, p - g.pos);
    float  s  = g.radius;
    float3 q  = float3(lp.xy, lp.z * 2.6);

    if (g.p0 < 0.5) return pr_octa(q, s * 1.05) / 2.6;                       // diamond
    if (g.p0 < 1.5) return pr_rbox(q, float3(s * 0.60, s * 0.60, s * 0.55), s * 0.10) / 2.6;
    return (length(q) - s * 0.68) / 2.6;                                     // round
}

// ---------------------------------------------------------------------------
// The opaque scene. Returns (distance, material, record index).
// The membrane is deliberately absent — it is transmissive and gets its own pass.
// ---------------------------------------------------------------------------
float3 pr_map(float3 p, bool cheap)
{
    // Floor plane at y = 0. The stage record owns it.
    float3 best = float3(p.y, MAT_FLOOR, (float)SLOT_STAGE);

    // ---- hero -------------------------------------------------------------
    CastRec tr = Cast[SLOT_TORUS];
    if (tr.active > 0.5)
    {
        float d = pr_fur(p, tr, cheap);
        if (d < best.x) best = float3(d, tr.mat, (float)SLOT_TORUS);
    }

    // ---- glyph ------------------------------------------------------------
    [loop] for (uint g = 0u; g < (uint)GLYPH_MAX; g++)
    {
        CastRec b = Cast[SLOT_GLYPH + g];
        if (b.active < 0.5) continue;
        float d = pr_rbox(p - b.pos, b.dims, b.radius);
        if (d < best.x) best = float3(d, b.mat, (float)(SLOT_GLYPH + g));
    }

    // ---- support post ------------------------------------------------------
    [loop] for (uint o = 0u; o < (uint)POST_MAX; o++)
    {
        CastRec b = Cast[SLOT_POST + o];
        if (b.active < 0.5) continue;
        float d = pr_rbox(p - b.pos, b.dims, b.radius);
        if (d < best.x) best = float3(d, b.mat, (float)(SLOT_POST + o));
    }

    // ---- gem lattice -------------------------------------------------------
    CastRec pl = Cast[SLOT_PLATE];
    if (pl.active > 0.5)
    {
        float3 lp = p - pl.pos;

        float dPl = pr_rbox(lp, pl.dims, pl.radius);
        if (dPl < best.x) best = float3(dPl, pl.mat, (float)SLOT_PLATE);

        // O(1) chip lookup: invert the emitter's own cell placement to get the nearest
        // cell, then read exactly one record. This is why chips are cell-addressed.
        uint cols = (uint)max(pl.p0, 1.0);
        uint rows = (uint)max(pl.p1, 1.0);
        float2 t  = float2(lp.x / max(pl.dims.x * 0.84, 1e-4),
                          -lp.y / max(pl.dims.y * 0.84, 1e-4));
        float2 cf = (t * 0.5 + 0.5) * float2((float)cols, (float)rows) - 0.5;
        int2   ci = clamp(int2(round(cf)), int2(0, 0), int2((int)cols - 1, (int)rows - 1));

        CastRec gm = Cast[SLOT_GEM + (uint)ci.y * cols + (uint)ci.x];
        if (gm.active > 0.5)
        {
            float d = pr_chip(p, gm);
            if (d < best.x) best = float3(d, gm.mat, (float)(SLOT_GEM + (uint)ci.y * cols + (uint)ci.x));
        }
    }

    // ---- spheres -----------------------------------------------------------
    [loop] for (uint s = 0u; s < (uint)SPHERE_MAX; s++)
    {
        CastRec sp = Cast[SLOT_SPHERE + s];
        if (sp.active < 0.5) continue;
        float d = length(p - sp.pos) - sp.radius;
        if (d < best.x) best = float3(d, sp.mat, (float)(SLOT_SPHERE + s));
    }

    // ---- light ring --------------------------------------------------------
    CastRec rg = Cast[SLOT_RING];
    if (rg.active > 0.5)
    {
        float d = pr_torus(p - rg.pos, rg.radius, rg.dims.x);
        if (d < best.x) best = float3(d, rg.mat, (float)SLOT_RING);
    }

    return best;
}

float3 pr_normal(float3 p, float eps)
{
    float2 e = float2(1.0, -1.0) * eps;
    return normalize(e.xyy * pr_map(p + e.xyy, false).x + e.yyx * pr_map(p + e.yyx, false).x +
                     e.yxy * pr_map(p + e.yxy, false).x + e.xxx * pr_map(p + e.xxx, false).x);
}

// ---------------------------------------------------------------------------
// March. Steps shorten inside the pelt, where the noise displacement makes the field
// non-Lipschitz and a full step walks straight through the fur.
// ---------------------------------------------------------------------------
float3 pr_march(float3 ro, float3 rd, int steps, float eps, float maxT, bool cheap)
{
    float t = 0.02;
    CastRec tr = Cast[SLOT_TORUS];
    bool hasFur = tr.active > 0.5;

    [loop] for (int i = 0; i < steps; i++)
    {
        float3 p = ro + rd * t;
        float3 m = pr_map(p, cheap);

        if (m.x < eps * max(1.0, t * 0.35)) return float3(t, m.y, m.z);

        float sc = step_scale;
        if (hasFur && !cheap && pr_inPelt(p, tr)) sc *= 0.42;

        t += max(m.x * sc, eps * 0.5);
        if (t > maxT) break;
    }
    return float3(-1.0, 0.0, -1.0);
}

float pr_ao(float3 p, float3 n, float amt)
{
    float occ = 0.0, sca = 1.0;
    [unroll] for (int i = 0; i < 5; i++)
    {
        float h = 0.012 + 0.11 * (float)i / 4.0;
        occ += (h - pr_map(p + n * h, true).x) * sca;
        sca *= 0.72;
    }
    return saturate(1.0 - amt * 2.4 * occ);
}

#endif // PR_SCENE_HLSLI
