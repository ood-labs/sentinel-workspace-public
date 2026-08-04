// TP_Render / render.hlsl — the optics of a glass tank full of water.
//
// Owns Sentinel's internal camera. Every ray comes from the injected _InvViewProjMatrix; there
// is no shader-local camera equation anywhere in this project.
//
// This is NOT a sphere-tracer. Everything in the scene is either an axis-aligned box or a
// height field over a plane, and both have exact intersections — so the tank is two slab tests
// and the water is a short bracketed march, which is both sharper and an order of magnitude
// cheaper than marching a distance field would be. The cost that remains is all in the water.
//
// THE PATH, in the order a ray meets things:
//
//   1  the glass shell.   A PARALLEL slab does not bend a ray, it only offsets it sideways, and
//                         at this wall thickness that offset is a fraction of a pixel. So the
//                         wall costs a Fresnel reflection on the way in and one on the way out
//                         and nothing else. What the glass actually contributes visually is its
//                         RIM — the end-grain annulus on the top face — and its grazing-angle
//                         darkening, and both survive this simplification exactly.
//   2  the air inside.    March the height field for the water surface.
//   3  the water surface. Fresnel split. The reflection is traced one bounce (sky, or the dry
//                         tiles above the waterline); the refraction goes into the body.
//   4  the water body.    Straight to the tank lining, with Beer-Lambert absorption over the
//                         distance travelled and the caustic atlas multiplying what it lands on.
//
// A ray entering below the waterline through a side wall skips straight to 4, which is what
// makes the near face read as a slab of tinted water rather than as a window.
#include "../_shared/tessera.hlsli"

StructuredBuffer<TpRec> Plan : register(t0);
StructuredBuffer<float4> Pick : register(t1);
RWTexture2D<float4> OutputUAV : register(u0);

// _Tex2 = TP_Sim Field (h, v, dh/dx, dh/dz)   _Tex3 = TP_Caustics atlas

static float3 gHalf;          // (hx, depth, hz)
static float  gThick;
static float  gFree;
static float3 gSun;
static float3 gSunCol;
static float3 gPal[6];
static float3 gGrout;
static float  gPitch, gGroutW, gVar, gGloss, gTileSeed;
static int    gPattern;
static float  gSteps;

// ---------------------------------------------------------------------------
// Environment. A soft studio gradient, cool above and warmer below, with a broad highlight the
// water can find at grazing angles — a flat colour gives a mirror nothing to reflect and the
// surface goes dead.
// ---------------------------------------------------------------------------
float3 envAt(float3 d)
{
    float up = saturate(d.y * 0.5 + 0.5);
    float3 c = lerp(sky_low, sky_high, pow(up, 0.85));
    // the key, as a broad soft disc rather than a point
    float s = saturate(dot(normalize(d), gSun));
    c += gSunCol * pow(s, 12.0) * sky_key * 0.5;
    c += gSunCol * pow(s, 900.0) * sky_key * 6.0;
    return c;
}

float sampleH(float2 xz)
{
    float2 uv = xz / max(gHalf.xz, 1e-4) * 0.5 + 0.5;
    return _Tex2.SampleLevel(LinearSampler, uv, 0).x;
}

// Surface normal from the STORED gradients. Differencing an interpolated height instead would
// give a normal that is constant across each texel and jumps at every cell boundary, which
// reads as faceted foil rather than water.
float3 surfaceN(float2 xz)
{
    float2 uv = xz / max(gHalf.xz, 1e-4) * 0.5 + 0.5;
    float2 g = _Tex2.SampleLevel(LinearSampler, uv, 0).zw;
    return normalize(float3(-g.x * slope_gain, 1.0, -g.y * slope_gain));
}

float3 causticAt(float3 p, int face)
{
    if (p.y > 0.0) return 1.0.xxx;                   // nothing above the waterline is lit by it
    float2 uv = tpAtlasUV(p, face, gHalf);
    float3 e = _Tex3.SampleLevel(LinearSampler, uv, 0).rgb;
    return lerp(1.0.xxx, e, saturate(caustic_mix));
}

// ---------------------------------------------------------------------------
// The tank lining.
// ---------------------------------------------------------------------------
// World width of one pixel's footprint after travelling `dist`, spread by `spread`.
//
// A primary ray's footprint is just distance times the per-pixel angle. A ray that has been
// refracted through a wavy surface is far wider than that: neighbouring rays diverge according
// to how curved the surface was where they crossed it, which is exactly the quantity that makes
// caustics, and exactly the quantity that makes an unfiltered mosaic boil underneath them.
float tpFootprint(float dist, float spread)
{
    float perPixel = 2.0 * tan(radians(max(_CameraFOV, 1.0)) * 0.5) / max(_Resolution.y, 1.0);
    return max(dist, 0.0) * perPixel * max(spread, 1.0) * max(filter_gain, 0.0);
}

float3 shadeLining(float3 p, int face, float3 rd, bool submerged, float filt)
{
    float3 n = tpFaceNormal(face);
    float2 q = tpFaceCoord(p, face, gHalf);
    TpTile t = tpTile(q, gPitch, gGroutW, gVar, gTileSeed, gPattern, gPal, gGrout, filt);

    // A tile is a glazed ceramic square: a diffuse body plus a broad specular off its slightly
    // domed face. The dome is what makes a mosaic read as thousands of little objects instead
    // of as a printed grid, so the normal is bent toward the tile edges.
    float3 bevel = normalize(n + float3(0, 0, 0) + (face == TP_FACE_FLOOR
                    ? float3(t.local.x, 0, t.local.y)
                    : (face <= TP_FACE_PX ? float3(0, t.local.y, t.local.x) : float3(t.local.x, t.local.y, 0)))
                    * tile_dome * (1.0 - t.grout));
    bevel = normalize(bevel);

    float3 amb = envAt(bevel) * ambient_gain;
    float ndl = saturate(dot(bevel, gSun));
    float3 dir = gSunCol * sun_gain * ndl;

    float3 caus = submerged ? causticAt(p, face) : 1.0.xxx;

    float3 c = t.albedo * (amb + dir * caus);

    // gloss
    float3 r = reflect(rd, bevel);
    float f = 0.03 + 0.20 * pow(saturate(1.0 + dot(bevel, rd)), 5.0);
    c += envAt(r) * f * gGloss * t.gloss;

    return c;
}

// ---------------------------------------------------------------------------
// Water body: from a point already in the water, straight to the lining.
// ---------------------------------------------------------------------------
float3 traceWater(float3 ro, float3 rd, float entryDist, float spread)
{
    float tN, tF;
    if (!tpBox(ro, rd, float3(-gHalf.x, -gHalf.y, -gHalf.z), float3(gHalf.x, gFree, gHalf.z), tN, tF))
        return envAt(rd);

    float3 hit = ro + rd * tF;
    int face = tpInteriorFace(hit, gHalf);
    float3 lining = shadeLining(hit, face, rd, hit.y < 0.0, tpFootprint(entryDist + tF, spread));

    // Beer-Lambert over the path actually travelled, and a depth-proportional in-scatter. The
    // absorption is what turns the far wall teal and the near wall almost unchanged; the
    // in-scatter is what stops deep water going black instead of going blue.
    float dist = max(tF, 0.0);
    float3 sigma = (1.0 - saturate(water_tint)) * water_density;
    float3 tr = exp(-sigma * dist);
    float3 scat = water_tint * water_scatter * (1.0 - tr);

    return lining * tr + scat;
}

// ---------------------------------------------------------------------------
// The height-field intersection.
//
// The surface only exists inside a thin band around y = 0, so the ray is clipped to that band
// before anything is sampled and the march never spends a step where there is nothing to find.
// The band half-height is the FREEBOARD, which is the same number the plan draws its alarm
// against: if the waves ever exceed it the plan says so in red, and here they would start being
// missed. One number, two consequences, no second definition.
// ---------------------------------------------------------------------------
bool hitSurface(float3 ro, float3 rd, float tMax, out float tHit, out float steps)
{
    tHit = 0.0;
    steps = 0.0;

    float band = gFree;
    float t0 = 0.0, t1 = tMax;

    if (abs(rd.y) > 1e-5)
    {
        float ta = (band - ro.y) / rd.y;
        float tb = (-band - ro.y) / rd.y;
        t0 = max(t0, min(ta, tb));
        t1 = min(t1, max(ta, tb));
    }
    else if (abs(ro.y) > band) return false;

    if (t1 <= t0) return false;

    int n = clamp((int)march_steps, 4, 192);
    float dt = (t1 - t0) / (float)n;
    float tPrev = t0;
    float dPrev = ro.y + rd.y * t0 - sampleH(ro.xz + rd.xz * t0);

    [loop]
    for (int i = 1; i <= 192; i++)
    {
        if (i > n) break;
        float t = t0 + dt * (float)i;
        float3 p = ro + rd * t;
        float d = p.y - sampleH(p.xz);
        steps += 1.0;

        if (d * dPrev < 0.0)
        {
            // bracketed: bisect. Five halvings take the residual below a thousandth of a step,
            // which at this band height is far under a pixel.
            float a = tPrev, b = t;
            [unroll]
            for (int k = 0; k < 5; k++)
            {
                float m = 0.5 * (a + b);
                float3 pm = ro + rd * m;
                float dm = pm.y - sampleH(pm.xz);
                if (dm * dPrev < 0.0) b = m; else { a = m; dPrev = dm; }
            }
            tHit = 0.5 * (a + b);
            return true;
        }
        tPrev = t;
        dPrev = d;
    }
    return false;
}

// ---------------------------------------------------------------------------
// One camera ray.
// ---------------------------------------------------------------------------
float3 traceEye(float3 ro, float3 rd, out float outDepth, out float outSteps)
{
    outDepth = 1e6;
    outSteps = 0.0;

    float3 oMin = float3(-gHalf.x - gThick, -gHalf.y - gThick, -gHalf.z - gThick);
    float3 oMax = float3( gHalf.x + gThick,  gFree,             gHalf.z + gThick);
    float3 iMin = float3(-gHalf.x, -gHalf.y, -gHalf.z);
    float3 iMax = float3( gHalf.x,  gFree + 1e-4,  gHalf.z);

    float tN, tF;
    if (!tpBox(ro, rd, oMin, oMax, tN, tF)) return envAt(rd);

    float tEnter = max(tN, 0.0);
    float3 pe = ro + rd * tEnter;
    outDepth = tEnter;

    // --- the rim: the top face of the glass, outside the interior footprint. End-grain glass,
    // and the brightest thing in the reference's frame after the specular glints.
    bool topFace = abs(pe.y - gFree) < 1e-3;
    bool overWell = (abs(pe.x) < gHalf.x) && (abs(pe.z) < gHalf.z);
    if (topFace && !overWell)
    {
        // Glass END-GRAIN. It reflects the studio at its own Fresnel AND passes most of what is
        // behind it, so it reads as a bright bevel. Shading it as reflection alone makes it
        // DARKER than the backdrop it sits against, which turns the rim into a black bar
        // outlining the tank — the single most conspicuous way to make glass look like plastic.
        float3 n = float3(0, 1, 0);
        float f = tpFresnel(dot(-rd, n), 1.0, glass_ior);
        float3 c = envAt(rd) * (1.0 - f) + envAt(reflect(rd, n)) * f;
        c = lerp(envAt(rd), c, 1.0) + envAt(reflect(rd, n)) * 0.35 * rim_gain;
        c += gSunCol * pow(saturate(dot(reflect(rd, n), gSun)), 220.0) * rim_gain * 4.0;
        return c;
    }

    // --- entering through a wall (or through the open top)
    float3 wallN = float3(0, 0, 0);
    float wallF = 0.0;
    if (!topFace)
    {
        wallN = -tpFaceNormal(tpInteriorFace(pe, gHalf + gThick));
        wallF = tpFresnel(dot(-rd, wallN), 1.0, glass_ior);
    }

    // Inside the shell. Find where the interior begins.
    float iN, iF;
    float3 body;
    if (!tpBox(pe + rd * 1e-4, rd, iMin, iMax, iN, iF))
    {
        // Grazed the shell without entering the well — the vertical corner posts. Same rule as
        // the rim: a piece of glass with nothing behind it transmits the backdrop and adds its
        // reflection on top; it does not subtract light from the frame.
        float3 c = envAt(rd) * (1.0 - wallF) + envAt(reflect(rd, wallN)) * (wallF + 0.10) * rim_gain;
        c += gSunCol * pow(saturate(dot(reflect(rd, wallN), gSun)), 260.0) * rim_gain * 2.0;
        return c;
    }

    float3 pi = pe + rd * (max(iN, 0.0) + 1e-4);
    float travel = max(iF - max(iN, 0.0), 0.0);

    if (pi.y < sampleH(pi.xz))
    {
        // entered below the waterline: the ray is already in the water
        body = traceWater(pi, rd, tEnter + max(iN, 0.0), 1.0);
    }
    else
    {
        float tHit, st;
        if (hitSurface(pi, rd, travel, tHit, st))
        {
            outSteps += st;
            float3 ps = pi + rd * tHit;
            float3 n = surfaceN(ps.xz);
            if (dot(n, rd) > 0.0) n = -n;             // seen from below

            float fr = tpFresnel(dot(-rd, n), 1.0, 1.333);

            // reflection, one bounce: the sky, or the dry lining above the waterline
            float3 rdir = reflect(rd, n);
            float3 refl;
            float rN, rF;
            if (rdir.y < 0.0 || !tpBox(ps + n * 1e-3, rdir, iMin, iMax, rN, rF))
                refl = envAt(rdir);
            else
            {
                float3 rp = ps + rdir * rF;
                int rface = tpInteriorFace(rp, gHalf);
                refl = (rp.y > 0.0) ? shadeLining(rp, rface, rdir, false, tpFootprint(tEnter + rF, 1.5)) : envAt(rdir);
            }

            // refraction into the body
            // The refracted footprint spread grows with how tilted the surface is: a steep
            // ripple fans neighbouring rays apart, and that fan is what has to be filtered out
            // of the lining underneath it.
            float2 g2 = _Tex2.SampleLevel(LinearSampler, ps.xz / max(gHalf.xz, 1e-4) * 0.5 + 0.5, 0).zw;
            float spread = 1.0 + length(g2) * slope_gain * refract_spread;

            float3 tdir = refract(rd, n, 1.0 / 1.333);
            float3 refr = (dot(tdir, tdir) < 1e-6) ? refl
                        : traceWater(ps + tdir * 1e-3, normalize(tdir), tEnter + max(iN, 0.0) + tHit, spread);

            body = lerp(refr, refl, fr * fresnel_gain);

            // the glint. Small, tight and very bright — it is what says "water" before anything
            // else in the image does.
            float3 hv = normalize(gSun - rd);
            float sp = pow(saturate(dot(n, hv)), max(glint_power, 1.0));
            body += gSunCol * sp * glint_gain;

            outDepth = tEnter + max(iN, 0.0) + tHit;
        }
        else
        {
            // missed the water entirely: dry lining above the waterline, or straight through
            float3 pl = pi + rd * travel;
            int face = tpInteriorFace(pl, gHalf);
            bool inside = (abs(pl.x) <= gHalf.x + 1e-3) && (abs(pl.z) <= gHalf.z + 1e-3) && (pl.y <= gFree - 1e-3);
            body = inside ? shadeLining(pl, face, rd, false, tpFootprint(tEnter + max(iN,0.0) + travel, 1.0)) : envAt(rd);
        }
    }

    // --- back out through the glass. Two interfaces, so the wall darkens what it transmits at
    // grazing angles and adds its own reflection of the room on top.
    float3 c = body * (1.0 - wallF * glass_reflect);
    c += envAt(reflect(rd, wallN)) * wallF * glass_reflect;
    c *= exp(-glass_absorb * gThick * 2.0);

    return c;
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;

    TpRec tank = Plan[TP_TANK];
    TpRec lamp = Plan[TP_LIGHT];

    gHalf     = tpTankHalf(tank);
    gThick    = tpTankThick(tank);
    gFree     = tpTankFree(tank);
    gPitch    = tpTankPitch(tank);
    gGroutW   = tpTankGrout(tank);
    gVar      = tank.pos.y;
    gGloss    = tank.pos.z;
    gPattern  = (int)tank.pos.x;
    gTileSeed = tank.seed;
    gGrout    = tank.tint;
    gSun      = normalize(lamp.pos);
    gSunCol   = lamp.tint * lamp.p0;

    [unroll]
    for (int i = 0; i < 6; i++) gPal[i] = Plan[TP_PAL_0 + i].tint;

    int aa = clamp((int)aa_samples, 1, 3);
    float3 acc = float3(0, 0, 0);
    float depth = 1e6, steps = 0.0;
    float3 firstN = float3(0, 1, 0);

    [loop]
    for (int sy = 0; sy < aa; sy++)
    {
        for (int sx = 0; sx < aa; sx++)
        {
            float2 off = (float2(sx, sy) + 0.5) / (float)aa;
            float2 screenUV = ((float2)tid.xy + off) / _Resolution.xy;
            float2 ndc = float2(screenUV.x * 2.0 - 1.0, 1.0 - screenUV.y * 2.0);

            float4 nearW = mul(_InvViewProjMatrix, float4(ndc, 0.0, 1.0));
            float4 farW  = mul(_InvViewProjMatrix, float4(ndc, 1.0, 1.0));
            nearW /= nearW.w;
            farW  /= farW.w;

            float3 ro = _CameraPos;
            float3 rd = normalize(farW.xyz - nearW.xyz);

            float d, st;
            acc += traceEye(ro, rd, d, st);
            depth = min(depth, d);
            steps = max(steps, st);
        }
    }
    acc /= (float)(aa * aa);

    // ---- shipped diagnostic views. In a renderer that is almost entirely invisible
    // bookkeeping these are the only way to tell a dark lane from a dead one.
    int vm = (int)view_mode;
    if (vm != 0)
    {
        float2 screenUV = ((float2)tid.xy + 0.5) / _Resolution.xy;
        float2 ndc = float2(screenUV.x * 2.0 - 1.0, 1.0 - screenUV.y * 2.0);
        float4 nearW = mul(_InvViewProjMatrix, float4(ndc, 0.0, 1.0));
        float4 farW  = mul(_InvViewProjMatrix, float4(ndc, 1.0, 1.0));
        nearW /= nearW.w; farW /= farW.w;
        float3 ro = _CameraPos;
        float3 rd = normalize(farW.xyz - nearW.xyz);

        if (vm == 1)                                   // Surface height
        {
            float3 iMin = float3(-gHalf.x, -gHalf.y, -gHalf.z);
            float3 iMax = float3( gHalf.x,  gFree,    gHalf.z);
            float a, b, th, st;
            if (tpBox(ro, rd, iMin, iMax, a, b) && hitSurface(ro + rd * max(a, 0.0), rd, b - max(a, 0.0), th, st))
            {
                float3 p = ro + rd * (max(a, 0.0) + th);
                float h = sampleH(p.xz) / max(gFree, 1e-4);
                acc = float3(saturate(0.5 + h * 2.0), saturate(0.5 - h * 2.0), 0.35);
            }
            else acc = float3(0.02, 0.02, 0.03);
        }
        else if (vm == 2)                              // Surface normal
        {
            float3 iMin = float3(-gHalf.x, -gHalf.y, -gHalf.z);
            float3 iMax = float3( gHalf.x,  gFree,    gHalf.z);
            float a, b, th, st;
            if (tpBox(ro, rd, iMin, iMax, a, b) && hitSurface(ro + rd * max(a, 0.0), rd, b - max(a, 0.0), th, st))
            {
                float3 p = ro + rd * (max(a, 0.0) + th);
                acc = surfaceN(p.xz) * 0.5 + 0.5;
            }
            else acc = float3(0.02, 0.02, 0.03);
        }
        else if (vm == 3)                              // Caustic atlas, straight
        {
            acc = _Tex3.SampleLevel(LinearSampler, ((float2)tid.xy + 0.5) / _Resolution.xy, 0).rgb * 0.5;
        }
        else if (vm == 4)                              // March steps
        {
            float t = saturate(steps / max(step_budget, 1.0));
            acc = float3(t, t * t, 1.0 - t);
        }
        else                                           // Depth
        {
            float t = saturate((depth - depth_near) / max(depth_far - depth_near, 1e-3));
            acc = float3(1.0 - t, 1.0 - t, 1.0 - t);
        }
    }

    // The live pointer ring, drawn where the pick actually landed on the water plane rather
    // than where the mouse is on screen — so it is a readout of the state the sim is being
    // driven with, not a cursor.
    if (vm == 0 && Pick[0].z > 0.5 && cursor_show > 0.5)
    {
        float3 wp = float3((Pick[0].x * 2.0 - 1.0) * gHalf.x, 0.0, (Pick[0].y * 2.0 - 1.0) * gHalf.z);
        float4 cp = mul(_ViewProjMatrix, float4(wp, 1.0));
        if (cp.w > 0.0)
        {
            float2 sp = float2(cp.x / cp.w * 0.5 + 0.5, 0.5 - cp.y / cp.w * 0.5) * _Resolution.xy;
            float d = abs(length((float2)tid.xy + 0.5 - sp) - 16.0);
            acc = lerp(acc, float3(1.0, 0.55, 0.16), saturate(1.5 - d) * 0.75);
        }
    }

    OutputUAV[tid.xy] = float4(max(acc * exposure, 0.0), min(depth, 1e4));
}
