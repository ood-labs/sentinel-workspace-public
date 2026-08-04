// SC_Corridor / march.hlsl — the program image.
//
// One ray-marched corridor. It re-decides nothing about shape, aperture, palette, mass
// placement, sun geometry or travel: every one of those is read off SC_Plan's records. What
// lives here is light, surface, the checker material and the internal camera.
//
// THE INFINITE ZOOM, in two sentences. The camera never moves; the corridor scrolls through
// it, because every field below is sampled at (world z + travel) and every one of them is
// periodic with SC_LOOP_Z. Travel wraps at exactly that period, so the frame at travel = 0 and
// the frame at travel = SC_LOOP_Z are the same frame down to the bit — there is no crossfade
// and no teleport to hide.
//
// The far opening is a deliberate piece of dream logic. A genuinely endless straight tube
// converges to a vanishing POINT, and a sun at infinity seen down one would be a dot. So the
// tube is cut by a plane a fixed distance ahead of the eye and the sky is shown through the
// hole. You fly forever and the sun never gets closer — which is the thing the reference is
// actually about.
#include "../_shared/corridor.hlsli"

StructuredBuffer<ScRec> Plan : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

// The whole plan is read ONCE per thread group into groupshared. Re-reading the SRV inside the
// march would cost four structured-buffer loads per step per ray for the corridor alone.
groupshared ScRec  gBay[SC_BAYS];
groupshared float4 gMassA[SC_MASSES];   // xy centre in the cross-section, zw inward normal
groupshared float4 gMassB[SC_MASSES];   // corridor z, radius, elongation, squash
groupshared float4 gMassC[SC_MASSES];   // softness, kind, sheen, active
groupshared ScRec  gSky;
groupshared float  gTravel;

ScProfile profileShared(float zc)
{
    int i0, i1, i2, i3; float t;
    sc_bayFrame(sc_wrapZ(zc), i0, i1, i2, i3, t);
    return sc_profileFrom(gBay[i0], gBay[i1], gBay[i2], gBay[i3], t);
}

// ---------------------------------------------------------------------------
// Wall relief. THE EXPLORATION AXIS: each style is a different structural answer to "what is
// this corridor made of", not a grade. Swept, judged, and the loser presets repaired rather
// than deleted.
// ---------------------------------------------------------------------------
float wallField(float2 q, float2 h, float zc, int style)
{
    if (style == 1) return -sc_roundBox2(q, h, min(h.x, h.y) * 0.55);      // Rounded

    float d = -sc_roundBox2(q, h, 0.05);
    if (style == 0) return d;                                               // Box

    // Relief styles. Each pays for its OWN Lipschitz bill with a local scale factor rather
    // than forcing Step Scale down for every style — a wall profile of amplitude A and
    // angular frequency f adds A*f to the gradient, and stepping as if it did not is exactly
    // how relief turns into surface acne.
    if (style == 2)
    {
        // Colonnade — piers standing proud of the SIDE walls on the station pitch, which
        // divides SC_LOOP_Z exactly so they cannot drift across the seam. Gating on sideness
        // is what makes them columns; applied to the whole section they read as rings.
        float ax = abs(q.x) / max(h.x, 1e-3);
        float ay = abs(q.y) / max(h.y, 1e-3);
        float sideness = smoothstep(0.0, 0.30, ax - ay);
        float c = 0.5 - 0.5 * cos(zc * (6.2831853 / SC_BAY_Z));
        float prof = c * c * 0.30 * sideness;
        return (d - prof) * 0.58;
    }
    // Ribbed — courses running around the whole tunnel, four to the bay.
    float rib = (0.5 - 0.5 * cos(zc * (6.2831853 * 4.0 / SC_BAY_Z))) * 0.085;
    return (d - rib) * 0.52;
}

float massField(int i, float3 p, float zc, out float sheen)
{
    float4 A = gMassA[i], B = gMassB[i], C = gMassC[i];
    sheen = C.z;

    float2 n = A.zw;
    float2 t2 = float2(-n.y, n.x);
    float2 rel = p.xy - A.xy;
    float a = dot(rel, n);                       // inward from the wall
    float b = dot(rel, t2);                      // along the wall
    float w = sc_wrapDZ(zc - B.x);               // along the corridor, seam-safe

    float r = B.y, el = B.z, sq = B.w;
    int k = (int)C.y;

    if (k == MK_WAVE)
    {
        // The reference's breaking fold: a long roll running with the corridor, drifting
        // sideways as it goes so it never reads as an extruded pipe.
        float L = r * el * 0.60;
        float bend = sin(w * 1.05) * r * 0.30;
        return sc_capsule(float3(b + bend, a * (1.0 / max(sq, 0.2)), w),
                          float3(0, 0, -L), float3(0, 0, L), r * 0.78) * min(sq, 1.0);
    }
    if (k == MK_LENS)
    {
        // Broad and shallow on purpose. Its job is to carry a stretched patch of checker, so
        // it needs width to read the distortion across; a tall dome just hides the grid behind
        // its own silhouette.
        return sc_ellipsoid(float3(b, a, w), float3(r * 2.10, r * 0.58 * sq, r * 1.90 * el));
    }
    if (k == MK_DRUM)
        return sc_ellipsoid(float3(b, a, w), float3(r * 1.55, r * 0.50 * sq, r * 1.45 * el));
    if (k == MK_KNUCKLE)
    {
        float o = r * 0.58 * el;
        float d1 = sc_ellipsoid(float3(b, a, w - o), float3(r * 0.82, r * 0.82 * sq, r * 0.82));
        float d2 = sc_ellipsoid(float3(b, a, w + o), float3(r * 0.68, r * 0.68 * sq, r * 0.68));
        return sc_fuse(d1, d2, r * 0.45);
    }
    return sc_ellipsoid(float3(b, a, w), float3(r, r * sq, r * el));        // MK_SWELL
}

// mat 0 = wall, 1 = mass
float mapScene(float3 p, out int mat, out float sheen)
{
    float zc = p.z + gTravel;
    ScProfile pf = profileShared(zc);
    float2 q = sc_rot2(p.xy - pf.c, -pf.roll);

    float d = wallField(q, pf.h, zc, (int)tunnel_style);
    mat = 0;
    sheen = 0.0;

    [loop]
    for (uint i = 0u; i < SC_MASSES; i++)
    {
        if (gMassC[i].w > 0.5)
        {
            float sh;
            float dm = massField((int)i, p, zc, sh);
            float k = max(gMassC[i].x, 0.02);
            float fused = sc_fuse(d, dm, k);
            // mat 2 = wears the checker rather than the solid mass tint
            if (dm < d) { mat = ((int)gMassC[i].y == MK_LENS) ? 2 : 1; sheen = sh; }
            d = fused;
        }
    }

    // Cut the tube with the sky plane. Intersection of solids is a max, which keeps this a
    // usable field: a ray approaching the opening is correctly told how far it may still step.
    return max(d, p.z - aperture_z);
}

float3 sceneNormal(float3 p, float e)
{
    int m; float s;
    float2 k = float2(1.0, -1.0);
    return normalize(k.xyy * mapScene(p + k.xyy * e, m, s) +
                     k.yyx * mapScene(p + k.yyx * e, m, s) +
                     k.yxy * mapScene(p + k.yxy * e, m, s) +
                     k.xxx * mapScene(p + k.xxx * e, m, s));
}

// ---------------------------------------------------------------------------
// Shared lighting terms. Both the walls and the masses go through these — the reference's
// shading is one room lit by one source, and giving the checker its own private flat
// treatment is exactly what made the folds look pasted on rather than sitting in the corridor.
// ---------------------------------------------------------------------------

// Field occlusion. This is the primary shadow cue in the frame: it darkens the tunnel corners
// and lays a soft halo wherever a mass meets the wall it is growing out of.
// `jit` dithers the tap distances per pixel. Fixed offsets put every sample at the same depth
// for every pixel, so a caster sitting near one of them prints a hard concentric ring — five
// taps, five rings, arcing across the wall behind every mass. Jittering trades those rings for
// noise that the AA pass and the grid quantizer both swallow.
float sdfAO(float3 p, float3 n, float jit)
{
    float occ = 0.0, sca = 1.0;
    [unroll]
    for (int i = 1; i <= 5; i++)
    {
        // Jitter is a fraction of the tap spacing, not a whole step. Enough to dissolve the
        // rings, small enough that the quantizer downstream does not amplify it into speckle.
        float hh = 0.015 + 0.10 * ((float)i - 1.0) + 0.055 * jit;
        int m; float s;
        occ += (hh - mapScene(p + n * hh, m, s)) * sca;
        sca *= 0.75;
    }
    return saturate(1.0 - 1.9 * occ);
}

// Short-range soft shadow toward the opening, for the directional cast the masses throw down
// the corridor. Deliberately NOT a full-length shadow ray.
float contactShadow(float3 p, float3 n, float3 L, float jit)
{
    float res = 1.0;
    float t = 0.05 + 0.04 * jit;
    float ph = 1e20;
    [loop]
    for (int i = 0; i < 26; i++)
    {
        // The normal bias GROWS with distance, which is the whole trick. A point on a wall
        // traces toward an opening that lies almost in that wall's own plane, so a constant
        // bias leaves the ray skimming its own surface and every wall shadows itself to black
        // — which reads as a filthy render, not as a shadow.
        float3 sp = p + n * (0.02 + shadow_bias * t) + L * t;
        int m; float s;
        float h = mapScene(sp, m, s);

        // Closest-approach penumbra rather than raw h/t. The naive form only ever samples the
        // field AT the step points, so a coarse march quantizes the penumbra into visible
        // concentric rings around every caster — which is exactly what a soft shadow must not
        // have. Interpolating the nearest approach BETWEEN steps removes the banding without
        // paying for more steps.
        float y = h * h / (2.0 * ph);
        float d = sqrt(max(h * h - y * y, 0.0));
        res = min(res, shadow_soft * d / max(t - y, 1e-4));
        ph = h;

        t += clamp(h, 0.03, 0.22);
        if (res < 0.005 || t > shadow_reach) break;
    }
    return saturate(res);
}

// ---------------------------------------------------------------------------
// The sky seen through the opening. Aperture space is normalized by the BASE half-height, not
// by the live one: the sun is a fixed object at a fixed distance, and the opening pinches and
// flares around it as stations pass. Normalizing by the live aperture would make the sun
// breathe, which reads as a bug rather than as architecture.
// ---------------------------------------------------------------------------
float3 skyThroughOpening(float3 ro, float3 rd, float px)
{
    if (rd.z <= 1e-4) return SC_SKY_LOW * 0.25;
    float t = (aperture_z - ro.z) / rd.z;
    float3 ps = ro + rd * t;
    ScProfile pf = profileShared(aperture_z + gTravel);
    float2 s = (ps.xy - pf.c * sun_track) / SC_BASE_H;
    return sc_skyPlate(s, gSky, px * t / SC_BASE_H);
}

// ---------------------------------------------------------------------------
// Checker material. Cells along z divide SC_LOOP_Z an EVEN number of times, so the parity
// matches across the wrap — an odd count would flip every tile at the seam and turn a seamless
// loop into a visible strobe once per period.
// ---------------------------------------------------------------------------
// Checker-coordinate displacement from every MK_LENS mass in range.
//
// This runs ONCE per shaded pixel, not per march step: it is a texture-space effect, so it must
// not touch the distance field. Pulling the SDF around instead would drag the silhouette, cost
// a Lipschitz bill on every step, and still not bend the grid on the flat wall beside the swell
// — which is the half of the reference effect that actually sells it.
//
// The offset is periodic: `w` comes through sc_wrapDZ, so adding it to zc before the seam wrap
// cannot reintroduce a loop seam.
float2 lensWarp(float3 p, float zc)
{
    float2 off = 0.0;
    [loop]
    for (uint i = 0u; i < SC_MASSES; i++)
    {
        if (gMassC[i].w > 0.5 && (int)gMassC[i].y == MK_LENS)
        {
            float4 A = gMassA[i], B = gMassB[i];
            float2 n = A.zw;
            float2 t2 = float2(-n.y, n.x);
            float2 rel = p.xy - A.xy;
            float b = dot(rel, t2);
            float w = sc_wrapDZ(zc - B.x);

            float r = max(B.y, 1e-3);
            float R = r * lens_reach;
            float2 v = float2(b, w);
            float d = length(v);
            if (d < R)
            {
                // Smooth bell, zero at the rim so the warp dissolves into the undistorted grid
                // instead of ending on a visible circular crease.
                float f = 1.0 - smoothstep(0.0, R, d);
                f = f * f;
                // Scaled by v ITSELF, not by a normalized direction. A normalized direction is
                // undefined at d = 0 while the bell is at its maximum there, which prints a
                // pinwheel singularity at the centre of every lens — it reads as crazy right
                // up until the angle where it reads as a bug. This form magnifies uniformly
                // near the centre and vanishes cleanly at it.
                //
                // The perpendicular term is the twist, added on purpose rather than harvested
                // from that artifact, and it vanishes at the centre for the same reason.
                float2 perp = float2(-v.y, v.x);
                off -= (v * lens_warp + perp * lens_swirl) * f;
            }
        }
    }
    return off;
}

float3 wallAlbedo(float3 p, float3 nrm, float zc, ScProfile pf, float2 warpOff, out float faceLift)
{
    float2 q = sc_rot2(p.xy - pf.c, -pf.roll);
    float ax = abs(q.x) / max(pf.h.x, 1e-3);
    float ay = abs(q.y) / max(pf.h.y, 1e-3);
    bool side = ax > ay;

    float cellsZ = max(2.0 * round((float)checker_cells * 0.5), 2.0);
    float cz = SC_LOOP_Z / cellsZ;
    // Only the TEXTURE coordinates are displaced; `side` above is decided from the undisplaced
    // geometry, so a warp can never flip a wall into reading as a floor mid-tile.
    float lat = ((side ? q.y : q.x) + warpOff.x) / max(cell_lateral * pf.chk, 0.02);
    zc += warpOff.y;

    // WRAP THE LONGITUDINAL CELL INDEX INTO ONE LOOP BEFORE IT REACHES THE HASH.
    //
    // Parity alone being periodic is not enough. The accent draw is keyed on the cell INDEX,
    // and at the seam that index jumps by cellsZ — so every vermilion and pale tile redrew and
    // the checker visibly reshuffled once per period while the geometry stayed put. Because
    // cellsZ is forced even, this wrap preserves parity exactly, and because it lands on an
    // integer it falls on a tile boundary and never cuts a tile in half.
    float zi = zc / cz;
    float ziw = zi - cellsZ * floor(zi / cellsZ);

    float3 col = sc_checker(float2(ziw, lat), pf.pal, pf.accent, (float)pf.pal * 3.0);

    // Face separation. The reference is flat graphic colour, so this is a nudge, not lighting:
    // just enough that a wall and the floor never read as one continuous plane.
    if (side)                 faceLift = (q.x > 0.0) ? 1.00 : 0.93;
    else                      faceLift = (q.y > 0.0) ? 1.07 : 0.86;
    return col;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID, uint GI : SV_GroupIndex)
{
    // ---- one thread stages the whole plan for the group -------------------------------
    if (GI == 0u)
    {
        for (uint b = 0u; b < SC_BAYS; b++) gBay[b] = Plan[SC_BAY_0 + b];
        gSky = Plan[SC_SKY];
        gTravel = Plan[SC_HEADER].phase;
    }
    GroupMemoryBarrierWithGroupSync();

    if (GI < SC_MASSES)
    {
        uint i = GI;
        ScRec m = Plan[SC_MASS_0 + i];
        // A mass is attached to the PERIMETER at its own station, so its frame comes from the
        // profile there — derived from the record, never given its own parallel position.
        ScProfile mp = profileShared(m.pos.x);
        float2 sec = sc_perimeter(mp.h, m.pos.y * 6.2831853);
        float ax = abs(sec.x) / max(mp.h.x, 1e-3);
        float ay = abs(sec.y) / max(mp.h.y, 1e-3);
        float2 n = (ax > ay) ? float2(-sign(sec.x), 0.0) : float2(0.0, -sign(sec.y));
        gMassA[i] = float4(mp.c + sc_rot2(sec, mp.roll), sc_rot2(n, mp.roll));
        gMassB[i] = float4(m.pos.x, m.size.x, max(m.size.y, 0.35), max(m.grp, 0.25));
        gMassC[i] = float4(max(m.phase, 0.04), m.kind, m.tone, m.active);
    }
    GroupMemoryBarrierWithGroupSync();

    uint2 pixel = DTid.xy;
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    if (pixel.x >= W || pixel.y >= H) return;

    int aa = clamp((int)aa_samples, 1, 3);
    int steps = clamp((int)march_steps, 24, 260);
    float maxD = aperture_z + 6.0;
    // No derivatives in a compute shader: pixel footprint comes from the resolution and FOV.
    // _CameraFOV arrives in DEGREES from the host camera rows; feeding that straight to tan()
    // silently poisons every epsilon in the march.
    float fovRad = (_CameraFOV > 3.2) ? radians(_CameraFOV) : _CameraFOV;
    float pxAngle = (2.0 * tan(fovRad * 0.5)) / max((float)H, 1.0);

    float3 acc = 0.0;
    float stepsAcc = 0.0, depthAcc = 0.0;
    float3 nAcc = 0.0;
    int vmode = (int)view_mode;

    for (int sy = 0; sy < aa; sy++)
    for (int sx = 0; sx < aa; sx++)
    {
        float2 jit = (float2(sx, sy) + 0.5) / (float)aa;
        float2 screenUV = ((float2)pixel + jit) / float2(W, H);
        float2 ndc = float2(screenUV.x * 2.0 - 1.0, 1.0 - screenUV.y * 2.0);

        float4 nearW = mul(_InvViewProjMatrix, float4(ndc, 0.0, 1.0));
        float4 farW  = mul(_InvViewProjMatrix, float4(ndc, 1.0, 1.0));
        nearW /= nearW.w;
        farW  /= farW.w;

        float3 ro = _CameraPos;
        float3 rd = normalize(farW.xyz - nearW.xyz);

        float3 bg = skyThroughOpening(ro, rd, pxAngle);

        float t = 0.02;
        int used = 0;
        bool hit = false;
        int mat = 0; float sheen = 0.0;
        // Sub-pixel coverage from the march's closest approach: an SDF already knows how near
        // it came to every surface it missed, and throwing that away is what makes hard-edged
        // graphic geometry alias badly.
        float nearest = 1e9;

        [loop]
        for (int i = 0; i < steps; i++)
        {
            float3 p = ro + rd * t;
            int m2; float sh;
            float d = mapScene(p, m2, sh);
            float eps = max(surface_eps, pxAngle * t * 0.5);
            nearest = min(nearest, d / max(t, 1e-3));
            used = i;
            if (d < eps) { hit = true; mat = m2; sheen = sh; break; }
            t += max(d * step_scale, eps * 0.75);
            if (t > maxD) break;
        }

        float3 col = bg;
        float cover = hit ? 1.0 : saturate(1.0 - nearest / (pxAngle * 0.75));

        if (cover > 0.001)
        {
            float3 p = ro + rd * t;
            float3 nrm = sceneNormal(p, max(normal_eps, pxAngle * t * 0.5));
            float zc = p.z + gTravel;
            ScProfile pf = profileShared(zc);

            // The sun is a real position in the room, not an abstract direction: it sits just
            // past the opening, so light arrives ALONG the corridor and every surface can be
            // asked whether it can see it. That single fact is what produces the reference's
            // shading — bright throats, shaded foreground, folds casting down the tunnel.
            ScProfile pfAp = profileShared(aperture_z + gTravel);
            float3 sunP = float3(pfAp.c * sun_track + gSky.pos * SC_BASE_H, aperture_z + 3.0);
            float3 L = normalize(sunP - p);

            float jit = frac(sin(dot((float2)pixel + float2(sx, sy) * 0.37,
                                     float2(12.9898, 78.233))) * 43758.5453);
            float aoRaw = sdfAO(p, nrm, jit);
            float shRaw = lerp(1.0, contactShadow(p, nrm, L, jit), shadow_amt);

            float3 alb;
            float3 lit;
            if (mat == 1)
            {
                // The organic masses carry the sculpted read. Wide-range diffuse, not a
                // half-lambert squeeze: the reference's fold has a genuine dark side, and
                // clamping the term into [0.5, 1] turns it into a flat white sticker.
                alb = mass_tint.rgb;
                float dif = saturate(dot(nrm, L)) * 0.86 + 0.14;
                // Floored, because every mass is attached to a wall and the raw term sees a
                // half-occluded hemisphere EVERYWHERE — unfloored it drives a white fold to mud.
                float occ = lerp(1.0, aoRaw * 0.55 + 0.45, ao_amt);

                float3 h = normalize(L - rd);
                float spec = pow(saturate(dot(nrm, h)), spec_tight) * spec_gain * sheen;
                float fres = pow(saturate(1.0 + dot(nrm, rd)), 3.0);
                float3 amb = lerp(sc_pal(pf.pal, 0), sc_pal(pf.pal, 1), 0.5) * ambient;
                lit = alb * (dif * key_gain * shRaw + amb) * occ
                    + spec * shRaw + fres * rim_gain * SC_SUN_MID;
                // Rolled off on the MAX channel: a per-channel curve would chalk the tint out
                // of the highlight and turn a warm mass grey at the sheen.
                float mx = max(max(lit.r, lit.g), lit.b);
                lit *= (mx > 1e-4) ? ((mx / (1.0 + mx)) * exposure / mx) : 1.0;
            }
            else if (mat == 2)
            {
                // A checker-wearing swell. Shaded as the smooth body it is, but painted with
                // the wall's own material through the same warped coordinates the surrounding
                // wall uses — so the grid runs continuously off the wall and across it.
                float faceLift;
                alb = wallAlbedo(p, nrm, zc, pf, lensWarp(p, zc), faceLift);
                float dif = saturate(dot(nrm, L)) * 0.62 + 0.38;
                float occ = lerp(1.0, aoRaw * 0.55 + 0.45, ao_amt);
                float3 h = normalize(L - rd);
                float spec = pow(saturate(dot(nrm, h)), spec_tight) * spec_gain * 0.30;

                float shade = ambient_floor + (1.0 - ambient_floor) * dif * shRaw;
                lit = alb * faceLift * shade * occ + spec * shRaw;
                lit = lerp(lit * shadow_tint.rgb, lit, smoothstep(0.05, 1.15, shade * occ));
            }
            else
            {
                float faceLift;
                alb = wallAlbedo(p, nrm, zc, pf, lensWarp(p, zc), faceLift);

                // The opening is a huge area source, so a wall receives it mostly as wash
                // rather than as N.L — the walls run nearly parallel to the light and a plain
                // lambert term would black them out. Visibility carries the shading; N.L only
                // leans it. The floor lift keeps the checker graphic instead of muddy.
                float ndl = saturate(dot(nrm, L));
                // Weighted toward the flat term on purpose. The reference's checker is bright
                // saturated paint that DIPS into shadow at the contacts and corners; leaning
                // on N.L pulls the whole frame down to a uniform grey and loses the graphic.
                float recv = (0.92 + 0.28 * ndl) * shRaw * lerp(1.0, aoRaw, wall_ao);
                float shade = ambient_floor + (1.0 - ambient_floor) * recv;

                lit = alb * faceLift * shade;
                // Shade WARM, not grey — unlit magenta paint in a red room does not desaturate
                // toward neutral. The gate runs past 1.0 on purpose: a plain multiply keeps hue
                // but drags a white tile toward NEUTRAL grey, and the reference's shaded whites
                // stay warm off-white. Letting a little tint reach the mid-tones is the whole
                // difference between "shaded" and "dirty".
                lit = lerp(lit * shadow_tint.rgb, lit, smoothstep(0.05, 1.15, shade));
            }

            // Foreground shade. The reference is darkest nearest the eye and opens up toward
            // the sun; without this the corridor reads as evenly lit tube rather than as depth.
            lit *= lerp(near_shade, 1.0, saturate(p.z / max(aperture_z, 1.0)));

            // The opening washes light back down the tube. Cheap, and it is the cue that makes
            // the corridor read as leading somewhere rather than as a lit box.
            float haze = saturate(p.z / max(aperture_z, 1.0));
            haze = pow(haze, max(haze_falloff, 0.05)) * haze_amount;
            lit = lerp(lit, SC_SUN_MID * 0.9 + SC_SKY_LOW * 0.2, haze);

            col = (vmode == 1) ? alb : lit;
            col = lerp(bg, col, cover);
        }

        acc += col;
        stepsAcc += (float)used / (float)steps;
        depthAcc += saturate(t / maxD);
        nAcc += (hit ? (sceneNormal(ro + rd * t, normal_eps) * 0.5 + 0.5) : 0.5);
    }

    float inv = 1.0 / (float)(aa * aa);
    float3 outc = acc * inv;

    // Ships as real controls, not debug defines: Material isolates a palette problem from a
    // lighting one, Steps finds the cost, Normals finds a broken field, Depth proves stacking.
    if (vmode == 2)      outc = lerp(float3(0.05, 0.12, 0.25), float3(1.0, 0.25, 0.15), saturate(stepsAcc * inv * 2.2));
    else if (vmode == 3) outc = nAcc * inv;
    else if (vmode == 4) outc = (1.0 - depthAcc * inv).xxx;

    OutputUAV[pixel] = float4(outc, 1.0);
}
