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
#include "../_shared/fish.hlsli"

StructuredBuffer<TpRec> Plan : register(t0);
StructuredBuffer<float4> Pick : register(t1);
// Slot 4 -> t4. TP_School decides every value in here; this node only lights the shape.
StructuredBuffer<TpFish> School : register(t4);
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
// Environment. A small procedural studio HDRI rather than a gradient: a real horizon with a
// darker floor under it, a rectangular key softbox, a bank of ceiling strips, and a broad fill
// from the opposite side.
//
// A mirror can only show what the environment HAS. The old two-stop ramp had no shapes in it,
// so a rippled surface reflecting it produced smooth tonal wobble and nothing that read as a
// reflection. The strips are the load-bearing part.
//
// `detail` is how much of the STRUCTURE a ray may see. Reflections pass 1. The camera's own
// background ray passes 0, because a rack of ceiling lights hanging behind the tank is set
// dressing nobody asked for — the backdrop wants the dome and the horizon and nothing else.
// ---------------------------------------------------------------------------
// Yaw then tilt. Yaw spins the room; tilt leans it, which is what lets the horizon run off
// level — a dead-level horizon in every shot is one of the things that reads as "render".
float3 tpEnvRot(float3 d)
{
    float a = radians(env_rot);
    float ca = cos(a), sa = sin(a);
    float3 r = float3(d.x * ca - d.z * sa, d.y, d.x * sa + d.z * ca);

    float t = radians(env_tilt);
    float ct = cos(t), st = sin(t);
    return float3(r.x, r.y * ct - r.z * st, r.y * st + r.z * ct);
}

// The key's own direction. By default it is the LIGHT — the softbox is the thing casting the
// sun, so welding it there keeps the specular and the reflected source in agreement, which is
// the correct default and the reason it was built that way. But it also means Studio Rotation
// spins the room and leaves the key behind, so this allows the two to be separated when the
// composition wants the highlight somewhere the light is not.
float3 tpKeyDir(float3 sunDir)
{
    if (key_follow > 0.5) return sunDir;
    float y = radians(key_yaw), p = radians(key_pitch);
    return normalize(float3(cos(p) * cos(y), sin(p), cos(p) * sin(y)));
}

// Rounded-rect panel around an axis, measured in the gnomonic tangent plane so the shape stays
// rectangular instead of pinching to a bowtie at its corners.
float tpPanel(float3 d, float3 axis, float2 halfSize, float soft)
{
    float ca = dot(d, axis);
    if (ca <= 0.05) return 0.0;
    float3 up = abs(axis.y) > 0.9 ? float3(1, 0, 0) : float3(0, 1, 0);
    float3 tx = normalize(cross(up, axis));
    float3 ty = cross(axis, tx);
    float2 q = float2(dot(d, tx), dot(d, ty)) / ca;
    float2 e = abs(q) - halfSize;
    float sd = length(max(e, 0.0)) + min(max(e.x, e.y), 0.0);
    return 1.0 - smoothstep(0.0, max(soft, 1e-3), sd);
}

// A ceiling strip. u/v are literally where the ray lands on a ceiling one unit overhead, so the
// bank is laid out the way it would be in a room instead of as bands in angle space.
float tpCeilStrip(float3 e, float zoff, float halfW, float halfL, float soft)
{
    if (e.y < 0.06) return 0.0;
    float2 q = float2(e.x, e.z) / e.y;
    float2 v = abs(q - float2(0.0, zoff)) - float2(halfL, halfW);
    float sd = length(max(v, 0.0)) + min(max(v.x, v.y), 0.0);
    return (1.0 - smoothstep(0.0, max(soft, 1e-3), sd)) * smoothstep(0.06, 0.30, e.y);
}

float3 envAt(float3 dIn, float detail)
{
    float3 d = normalize(dIn);
    float3 e = tpEnvRot(d);

    // The dome: zenith -> horizon -> floor. A horizon is what gives a grazing reflection an
    // EDGE to break, which is most of why the old flat ramp read as dead.
    //
    // horizon_height slides that edge up or down the dome. Raising it puts more dark floor into
    // everything the water reflects at grazing angles and drops the whole image; lowering it
    // opens the room out. It is a stronger compositional control than its size suggests.
    float ey = e.y - horizon_height;

    float3 sky = lerp(sky_low, sky_high, pow(saturate(ey), 0.55));
    float3 gnd = lerp(sky_low, sky_ground, pow(saturate(-ey), 0.40));
    float3 c = lerp(gnd, sky, smoothstep(-horizon_soft, horizon_soft, ey));

    // broad fill, opposite the key
    float3 fillDir = normalize(float3(-0.75, 0.30, -0.58));
    float fd = saturate(dot(e, fillDir));
    c += sky_high * fill_gain * fd * fd;

    if (detail > 0.001)
    {
        float3 kd = tpKeyDir(gSun);
        float box = tpPanel(d, kd, float2(key_size, key_size * 0.62), key_size * 0.55);
        c += gSunCol * box * key_gain * detail;

        // The ceiling bank, laid out about its own centre so changing the count grows the rig
        // symmetrically instead of sliding it sideways across the reflection.
        int nS = clamp((int)strip_count, 0, 6);
        float strips = 0.0;
        [loop]
        for (int si = 0; si < 6; si++)
        {
            if (si >= nS) break;
            float off = ((float)si - (float)(nS - 1) * 0.5) * strip_gap;
            strips += tpCeilStrip(e, off, strip_w, strip_len, strip_soft);
        }
        c += strip_col * strips * strip_gain * detail;
    }

    // The tight core, kept small: it is what puts a hard sparkle in the glints. Anchored to the
    // LIGHT rather than to the key, always — this is the sun itself, not a fixture.
    float s = saturate(dot(d, gSun));
    c += gSunCol * pow(s, 5.0) * sky_key * 0.16;
    c += gSunCol * pow(s, 900.0) * sky_key * 5.0 * detail;

    return c * env_gain;
}

// ---------------------------------------------------------------------------
// THE MENISCUS. Capillary rise where the water meets the wall.
//
// Without it the surface is a plane intersecting a box, and the junction is a perfectly straight
// razor edge that no amount of shading can rescue — it is the single thing that makes a rendered
// waterline read as raw. Real water climbs its container over a few millimetres, and that curve
// does three jobs at once: it breaks the straight line, it tips the surface normal hard over
// through a narrow band so the contact catches a bright rim of its own, and it puts a soft
// gradient where there was a step.
//
// This lives in the RENDERER, not the solver, on purpose: it is a static property of the
// container, not a wave. Putting it in the field would send it through the caustic integrator as
// if it were a moving surface, and a permanent fixed lens all the way around the tank would
// print a permanent bright frame onto the lining.
//
// The gradient is analytic and returned alongside the height, because a meniscus whose SHAPE the
// march finds but whose SLOPE the shading does not know about is a visible seam.
float tpMeniscus(float2 xz, out float2 grad)
{
    grad = float2(0.0, 0.0);
    if (meniscus_h <= 1e-6) return 0.0;

    float w = max(meniscus_w, 1e-3);
    float2 dw = max(gHalf.xz - abs(xz), 0.0);      // distance to the wall on each axis
    float2 e  = exp(-dw / w);

    // The two axes ADD, so an inside corner rises higher than a flat wall does — which is what
    // a corner actually does, and it is what keeps the four corners from reading as seams.
    grad = meniscus_h * e / w * sign(xz);
    return meniscus_h * (e.x + e.y);
}

float sampleH(float2 xz)
{
    float2 uv = xz / max(gHalf.xz, 1e-4) * 0.5 + 0.5;
    float2 mg;
    return _Tex2.SampleLevel(LinearSampler, uv, 0).x + tpMeniscus(xz, mg);
}

// Surface normal from the STORED gradients. Differencing an interpolated height instead would
// give a normal that is constant across each texel and jumps at every cell boundary, which
// reads as faceted foil rather than water.
float3 surfaceN(float2 xz)
{
    float2 uv = xz / max(gHalf.xz, 1e-4) * 0.5 + 0.5;
    float2 g = _Tex2.SampleLevel(LinearSampler, uv, 0).zw;
    // slope_gain is an artistic exaggeration of the WAVES. The meniscus is a real shape the
    // march actually walks, so it is added at unit gain — scaling it would tilt the shading away
    // from the geometry and put the bright contact rim in the wrong place.
    float2 mg;
    tpMeniscus(xz, mg);
    return normalize(float3(-g.x * slope_gain - mg.x, 1.0, -g.y * slope_gain - mg.y));
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

// ---------------------------------------------------------------------------
// FISH SHADOWS.
//
// The school floated. Nothing in the frame stated that the fish were BETWEEN the light and the
// floor, so they read as decals on the water rather than as bodies in it — and a shadow is the
// cheapest possible statement of "this is above that".
//
// Underwater it is also the most forgiving kind to fake. Light down there arrives from a broad
// scattered hemisphere, so the shadow is soft, low in contrast, and grows blurrier the further
// the fish sits from whatever it lands on. That last property comes free from the penumbra
// estimate below — distance over travel widens on its own with height, which is exactly the cue
// that tells you how far off the tiles a fish is swimming.
//
// THE CAUSTICS MUST BE SHADOWED TOO. The atlas is a picture of the refracted sunlight, so this
// attenuates the direct term and the caustics together; darkening one and not the other would
// put a shadow under the fish with the bright caustic net still playing merrily across it.
//
// Cost is gated the same way the primary fish march is: a ray-sphere rejection per fish, and a
// march only for the ones actually standing in the light path.
// ---------------------------------------------------------------------------
float tpFishShadow(float3 p, float3 L, int skipIdx)
{
    if (fish_show < 0.5 || shadow_gain <= 0.001) return 1.0;
    if (L.y <= 0.02) return 1.0;                    // grazing sun casts nothing useful here

    // The sun ray leaves the water at the surface; there is no fish above that to occlude it.
    float maxT = (0.0 - p.y) / L.y;
    if (maxT <= 1e-3) return 1.0;

    int steps = clamp((int)shadow_steps, 4, 24);
    float res = 1.0;

    [loop]
    for (uint i = 0u; i < TP_FISH_MAX; i++)
    {
        // A fish must not shadow itself: the ray starts ON its surface, so without this every
        // fish comes out uniformly dark and the whole school turns to silhouette.
        if ((int)i == skipIdx) continue;

        TpFish f = School[i];
        if (f.active < 0.5) continue;

        float3 oc = p - f.pos;
        float  r  = tpFishRadius(f);
        float  b  = dot(oc, L);
        float  cq = dot(oc, oc) - r * r;
        float  disc = b * b - cq;
        if (disc < 0.0) continue;

        float sq = sqrt(disc);
        float t0 = max(-b - sq, 1e-3);
        float t1 = min(-b + sq, maxT);
        if (t1 <= t0) continue;

        float eps = max(f.len, 1e-4) * 0.004;
        float t = t0;

        [loop]
        for (int k = 0; k < 24; k++)
        {
            if (k >= steps || t > t1) break;
            float d = tpFishShadowSDF(p + L * t, f);
            // Penumbra: how nearly the ray grazed the body, softened by how far it had to travel.
            res = min(res, shadow_soft * d / t);
            if (res < 0.02) break;
            t += max(d * TP_FISH_SHADOW_STEP, eps);
        }
        if (res < 0.02) break;
    }

    return lerp(1.0, saturate(res), saturate(shadow_gain));
}

TpTileFinish tpFinish()
{
    TpTileFinish fin;
    fin.mottle   = tile_mottle;
    fin.tilt     = tile_tilt;
    fin.glossVar = tile_gloss_var;
    fin.edgeAO   = tile_ao;
    return fin;
}

// `sunShadow` is passed IN, not computed here.
//
// shadeLining has three call sites, and a fish shadow is a full bounded march over the school —
// so computing it inside meant the whole thing was inlined three times over, on top of the copies
// already inside the primary fish march and the four-tap normal. Compile time went from seconds
// to minutes and the register pressure would have followed. Only the submerged lining reached
// through the water body can be shadowed by a fish anyway, so exactly one call site needs it.
float3 shadeLining(float3 p, int face, float3 rd, bool submerged, float filt, float sunShadow)
{
    float3 n = tpFaceNormal(face);
    float2 q = tpFaceCoord(p, face, gHalf);
    TpTile t = tpTile(q, gPitch, gGroutW, gVar, gTileSeed, gPattern, gPal, gGrout, filt, tpFinish());

    // A tile is a glazed ceramic square: a diffuse body plus a broad specular off its slightly
    // domed face. Two separate terms bend the normal here and they mean different things —
    // `local` is the dome WITHIN one tile, `tilt` is the whole tile sitting off true. The dome
    // alone makes a grid of identical beads; the tilt is what makes it hand-laid.
    float2 lay = t.local * tile_dome * (1.0 - t.grout) + t.tilt;
    float3 bevel = normalize(n + tpFaceTangent(face, lay));

    // THE TIDE LINE. Lining above the water is wet for a few centimetres: darker, because a
    // film kills the diffuse scatter out of the glaze, and glossier, because the film is a
    // mirror. This is the other half of the meniscus — together they turn a one-pixel step from
    // dry ceramic to water mirror into a transition with a width.
    if (!submerged)
    {
        float wet = exp(-max(p.y, 0.0) / max(wet_height, 1e-4));
        t.albedo *= lerp(1.0, 1.0 - wet_dark, wet);
        t.gloss  *= lerp(1.0, wet_gloss, wet);
    }

    // DIFFUSE AMBIENT TAKES THE DOME ONLY — detail 0.
    //
    // A diffuse lobe integrates the whole hemisphere, so it should see the environment's average,
    // not its light fixtures. Letting the strips through here adds their full brightness to every
    // upward-facing texel at once: the floor washed out to white while the walls stayed correct,
    // which reads as a broken exposure rather than as a lit room. The strips belong in the GLOSS
    // lookup below, where a narrow lobe genuinely can see one.
    float3 amb = envAt(bevel, 0.0) * ambient_gain;
    float ndl = saturate(dot(bevel, gSun));
    float3 dir = gSunCol * sun_gain * ndl;

    float3 caus = submerged ? causticAt(p, face) : 1.0.xxx;

    // Direct sun and caustics are the same light, so one shadow term multiplies both. Ambient
    // takes a fraction of it as well — a fish hanging just off the tiles occludes some of the
    // scattered light too, and that little bit of contact darkening is what stops the shadow
    // reading as a sticker laid on the floor.
    float sh = submerged ? saturate(sunShadow) : 1.0;
    float3 c = t.albedo * (amb * lerp(1.0, sh, 0.35) + dir * caus * sh);

    // gloss
    float3 r = reflect(rd, bevel);
    float f = 0.03 + 0.20 * pow(saturate(1.0 + dot(bevel, rd)), 5.0);
    c += envAt(r, 1.0) * f * gGloss * t.gloss;

    return c;
}

// ---------------------------------------------------------------------------
// DRIED WATER SPOTS on the OUTSIDE of the glass.
//
// Perfectly clean glass is a giveaway. Nothing in a real room has a flawless surface, and a
// tank with an optically perfect wall reads as a render of a tank — the eye has no evidence the
// glass is a physical object with a history rather than a mathematical boundary.
//
// What mineral spotting actually does is NOT darken the glass. It leaves scattered patches that
// reflect slightly MORE and slightly less sharply — so the fix is two things at once: a small
// lift in reflectance, and a blur of what is being reflected. The blur is the important half;
// reflectance alone just looks like smudged dirt, whereas a reflection that goes soft in
// patches reads unmistakably as a surface with texture on it.
//
// Authored on the outer wall PLANE in world coordinates, so the spots belong to the glass and
// stay put while the camera moves. Screen-space or view-dependent placement would slide across
// the wall and read as a lens artefact instead of as the tank being dirty.
// ---------------------------------------------------------------------------
float tpGlassSpots(float3 pe, float3 n)
{
    if (spot_amount <= 1e-3) return 0.0;

    // Coordinates in the plane of whichever face was hit.
    float2 uv = (abs(n.x) > 0.5) ? pe.zy : ((abs(n.y) > 0.5) ? pe.xz : pe.xy);
    uv *= max(spot_scale, 0.1);

    float a = tpVNoise(uv);
    float b = tpVNoise(uv * 2.7 + 13.1);
    float v = a * 0.66 + b * 0.34;

    // Sparse and hard-ish edged: dried spots have rims, they are not a soft grime gradient.
    return smoothstep(0.58, 0.74, v) * saturate(spot_amount);
}

// ---------------------------------------------------------------------------
// The lip of the tank — the top face of the shell and the vertical corner posts, the two places
// the shell is seen with nothing behind it. `edge_style` decides what it is MADE of; see the
// manifest for why this is a material choice and not a brightness slider.
// ---------------------------------------------------------------------------
float3 shadeCoping(float3 p, float3 rd, float3 n, int style)
{
    if (style == 0)                                  // Glass end-grain
    {
        // AN ENERGY-CONSERVING SPLIT AND NOTHING PILED ON TOP.
        //
        // This is where the white halo came from. The original added a further 0.35 of the
        // reflection, and a 4x specular, to a transmit/reflect sum that was already complete —
        // so the lip came out brighter than anything else in the frame and drew a glowing
        // outline around the whole tank. Glass does not add light. It splits it.
        float f = tpFresnel(dot(-rd, n), 1.0, glass_ior);
        float3 c = envAt(rd, 0.0) * (1.0 - f) + envAt(reflect(rd, n), 1.0) * f;
        // One tight glint along the edge. This is what actually says "glass" — a narrow
        // catchlight that travels as the camera moves, not a permanent bright band.
        c += gSunCol * pow(saturate(dot(reflect(rd, n), gSun)), 300.0) * rim_gain * 0.8;
        return c;
    }

    float dist = length(p - _CameraPos);

    if (style == 2)                                  // Tiled: the mosaic runs over the lip
    {
        float2 q = (abs(n.y) > 0.5) ? float2(p.x, p.z)
                 : ((abs(n.x) > 0.5) ? float2(p.z, p.y) : float2(p.x, p.y));
        TpTile t = tpTile(q, gPitch, gGroutW, gVar, gTileSeed, gPattern, gPal, gGrout,
                          tpFootprint(dist, 1.0), tpFinish());
        float3 c = t.albedo * (envAt(n, 0.0) * ambient_gain
                             + gSunCol * sun_gain * saturate(dot(n, gSun)));
        c += envAt(reflect(rd, n), 1.0) * 0.05 * gGloss * t.gloss;
        return c;
    }

    // Cast Stone. Matte, faintly grained, and deliberately DARKER than the backdrop so the lip
    // reads as a shadow line around the tank instead of as a halo drawn on top of it. The grain
    // fades out with distance for the same reason the mosaic does — an unfiltered high-frequency
    // detail on a one-pixel-wide edge is pure crawl.
    float grainFade = saturate(1.0 - tpFootprint(dist, 1.0) * 26.0);
    float m = tpVNoise(float2(p.x * 13.0 + p.y * 4.0, p.z * 13.0 + p.y * 7.0));
    m += 0.5 * tpVNoise(float2(p.x * 41.0 - p.z * 6.0, p.z * 41.0 + p.x * 3.0));
    float3 alb = coping_col * (0.88 + 0.30 * (m / 1.5 - 0.5) * grainFade);

    float3 c = alb * (envAt(n, 0.0) * ambient_gain * 0.85
                    + gSunCol * sun_gain * saturate(dot(n, gSun)) * 0.70);
    c += envAt(reflect(rd, n), 0.35) * 0.030 * rim_gain;   // a sheen, not a mirror
    return c;
}

// ---------------------------------------------------------------------------
// THE SCHOOL.
//
// This is the only sphere-traced thing in the project, and it is deliberately fenced off from
// everything else: the tank and the water are exact intersections and stay that way. The fish
// are marched, but only inside a bounding sphere, so a ray that passes nowhere near one pays a
// dot product and leaves. That is what makes a marched body affordable inside a renderer whose
// whole design was to avoid marching.
//
// Note TP_FISH_STEP. The swimming wave bends the domain, which inflates reported distances along
// the bend, so a full step overshoots wherever the tail is hard over and punches holes straight
// through the fish. The march takes a fraction of each step instead.
// ---------------------------------------------------------------------------
bool tpFishHit(float3 ro, float3 rd, float tMax, out float tHit, out int outIdx)
{
    tHit = tMax;
    outIdx = -1;
    if (fish_show < 0.5) return false;

    int steps = clamp((int)fish_steps, 8, 64);

    [loop]
    for (uint i = 0u; i < TP_FISH_MAX; i++)
    {
        TpFish f = School[i];
        if (f.active < 0.5) continue;

        // Bounding sphere first, against the CURRENT nearest hit — so once a near fish is found
        // the ones behind it are rejected outright instead of being marched and discarded.
        float3 oc = ro - f.pos;
        float  r  = tpFishRadius(f);
        float  b  = dot(oc, rd);
        float  cq = dot(oc, oc) - r * r;
        float  disc = b * b - cq;
        if (disc < 0.0) continue;

        float sq = sqrt(disc);
        float t0 = max(-b - sq, 0.0);
        float t1 = min(-b + sq, tHit);
        if (t1 <= t0) continue;

        float eps = max(f.len, 1e-4) * 0.0035;
        float t = t0;

        [loop]
        for (int k = 0; k < 64; k++)
        {
            if (k >= steps || t > t1) break;
            float d = tpFishSDF(ro + rd * t, f, f.sweep);
            if (d < eps) { tHit = t; outIdx = (int)i; break; }
            t += max(d * TP_FISH_STEP, eps);
        }
    }
    return outIdx >= 0;
}

// Tetrahedral normal — four taps instead of the six a central difference needs, and the fish SDF
// is the most expensive evaluation in the frame.
float3 tpFishNormal(float3 p, TpFish f)
{
    float e = max(f.len, 1e-4) * 0.006;
    float2 k = float2(1.0, -1.0);
    return normalize(k.xyy * tpFishSDF(p + k.xyy * e, f, f.sweep) +
                     k.yyx * tpFishSDF(p + k.yyx * e, f, f.sweep) +
                     k.yxy * tpFishSDF(p + k.yxy * e, f, f.sweep) +
                     k.xxx * tpFishSDF(p + k.xxx * e, f, f.sweep));
}

float3 shadeFish(float3 p, float3 n, float3 rd, TpFish f, int selfIdx)
{
    // THE MARKINGS ARE THE ANIMAL.
    //
    // Countershading alone — dark back, pale belly — is what a generic fish wears, and it made
    // these read as leeches: a single tinted body with a gradient on it. A koi is a PATTERNED
    // animal, white ground with hard-edged crimson over the back, and that pattern has to be
    // authored in body space so it stays put while the fish swims.
    float metal;
    float3 lp = tpFishLocal(p, f);
    float3 alb = tpKoiColour(lp, f.seed, f.tint, koi_amount, koi_sumi, metal);

    // Countershading now only MODULATES the markings instead of replacing them — a real koi is
    // still lighter underneath, but the pattern survives it.
    float up = saturate(n.y * 0.5 + 0.5);
    alb *= lerp(1.0, lerp(0.55, 1.22, 1.0 - up), saturate(fish_belly));

    float3 amb = envAt(n, 0.0) * ambient_gain;
    // Fish shadow each other, which is most of what makes a school read as a group occupying a
    // volume rather than as several unrelated fish at the same depth.
    float sh = tpFishShadow(p, gSun, selfIdx);
    float3 dir = gSunCol * sun_gain * saturate(dot(n, gSun)) * sh;

    // The caustic net plays over the fish exactly as it plays over the floor, and a fish moving
    // THROUGH that net is most of what sells it as being underwater rather than composited into
    // the shot. Sampled at the fish's own xz off the atlas floor region, which is where the
    // downward light lands.
    float3 caus = 1.0.xxx;
    if (p.y < 0.0)
    {
        float2 uv = tpAtlasUV(float3(p.x, 0.0, p.z), TP_FACE_FLOOR, gHalf);
        float3 e = _Tex3.SampleLevel(LinearSampler, uv, 0).rgb;
        caus = lerp(1.0.xxx, e, saturate(caustic_mix) * saturate(n.y));
    }

    float3 c = alb * (amb + dir * caus);

    // A wet, hard sheen — weighted by the pearlescence tpKoiColour hands back, so the white
    // ground carries the highlight and the crimson stays flatter. Glazing the whole animal
    // evenly is what makes a rendered fish look shrink-wrapped.
    float3 rv = reflect(rd, n);
    float fr = 0.04 + 0.30 * pow(saturate(1.0 + dot(n, rd)), 4.0);
    c += envAt(rv, 1.0) * fr * fish_gloss * metal;
    c += gSunCol * pow(saturate(dot(rv, gSun)), 90.0) * fish_gloss * metal * 0.5;

    return c;
}

// ---------------------------------------------------------------------------
// SUSPENDED PARTICULATE.
//
// Perfectly clear water renders as NOTHING. A tank of clean water is optically indistinguishable
// from a tank of vacuum, and the eye reads that as an empty box with a picture painted on the
// bottom — which is most of why a rendered aquarium feels like a diorama. What states "this
// volume is full of something" is the junk floating in it: the fine motes that catch the light
// in any real tank and DRIFT rather than fall.
//
// DELIBERATELY NOT A PARTICLE SYSTEM, and not a marched field either. Both would cost far more
// than this effect is worth, and the fish already showed what another large inlined field does
// to this shader's compile time. This is a smooth lattice evaluated at a few points along the
// ray that is being traced anyway: a handful of ALU per step, nothing to store, nothing to
// simulate, nothing to schedule.
//
// The nested sines are a domain warp, for the same reason the caustic detail needed one — a
// plain product of three sines is a regular grid of identical blobs, and regularity is far more
// conspicuous than noise at this density.
// ---------------------------------------------------------------------------
float3 tpMotes(float3 ro, float3 rd, float segLen, float entryDist)
{
    if (mote_gain <= 1e-4 || segLen <= 1e-4) return float3(0, 0, 0);

    int   n  = clamp((int)mote_steps, 2, 24);
    float dt = segLen / (float)n;
    float sc = 1.0 / max(mote_scale, 0.005);
    float t0 = _Time * mote_drift;

    float3 sig = (1.0 - saturate(water_tint)) * water_density;
    float3 acc = float3(0, 0, 0);

    [loop]
    for (int i = 0; i < 24; i++)
    {
        if (i >= n) break;

        float t = (float(i) + 0.5) * dt;
        float3 p = ro + rd * t;

        // Motes rise slowly and wander; they do not sit still and they do not fall.
        float3 q = p * sc + float3(sin(t0 * 0.31) * 0.4, -t0, cos(t0 * 0.27) * 0.4);

        float a = sin(q.x * 1.00 + sin(q.z * 0.71))
                * sin(q.y * 1.13 + sin(q.x * 0.63))
                * sin(q.z * 0.87 + sin(q.y * 0.79));

        float m = smoothstep(1.0 - saturate(mote_density) * 0.55, 1.0, abs(a));
        if (m <= 0.0) continue;

        // Lit by the same caustic net that lights the floor, so a mote drifting through a focus
        // beam flares and then goes out. That is the detail that makes the water read as a lit
        // VOLUME rather than as a fog card, and it costs one atlas tap that is already resident.
        float3 lit = gSunCol * sun_gain;
        if (p.y < 0.0)
        {
            float2 uv = tpAtlasUV(float3(p.x, 0.0, p.z), TP_FACE_FLOOR, gHalf);
            lit *= lerp(1.0.xxx, _Tex3.SampleLevel(LinearSampler, uv, 0).rgb, saturate(caustic_mix));
        }
        lit += envAt(float3(0, 1, 0), 0.0) * ambient_gain * 0.35;

        // Absorbed over the distance the light has already travelled to reach this mote.
        acc += m * lit * exp(-sig * (entryDist + t));
    }

    return acc * mote_gain * (dt / max(mote_scale, 0.005)) * 0.5;
}

// ---------------------------------------------------------------------------
// Water body: from a point already in the water, straight to the lining.
// ---------------------------------------------------------------------------
float3 traceWater(float3 ro, float3 rd, float entryDist, float spread)
{
    float tN, tF;
    if (!tpBox(ro, rd, float3(-gHalf.x, -gHalf.y, -gHalf.z), float3(gHalf.x, gFree, gHalf.z), tN, tF))
        return envAt(rd, 1.0);

    // The school stands between the water's entry point and the lining, so it is tested against
    // the lining distance and shades in its place when it wins. Absorption is then taken over
    // the SHORTER path — a fish two thirds of the way to the far wall must not arrive as teal as
    // the wall behind it, or it reads as painted onto the tiles.
    // The school stands between the water's entry point and the lining, so it is tested against
    // the lining distance and shades in its place when it wins.
    //
    // Both exits fall through to ONE return rather than returning early, so the mote integral is
    // inlined once instead of twice per call site. traceWater itself is already inlined twice.
    float3 outCol;
    float  segLen;

    float tf; int fi;
    if (tpFishHit(ro, rd, tF, tf, fi))
    {
        TpFish f = School[fi];
        float3 fp = ro + rd * tf;
        float3 fc = shadeFish(fp, tpFishNormal(fp, f), rd, f, fi);

        // Absorption over the SHORTER path — a fish two thirds of the way to the far wall must
        // not arrive as teal as the wall behind it, or it reads as painted onto the tiles.
        float3 sig = (1.0 - saturate(water_tint)) * water_density;
        float3 tr  = exp(-sig * max(tf, 0.0));
        outCol = fc * tr + water_tint * water_scatter * (1.0 - tr);
        segLen = tf;
        return outCol + tpMotes(ro, rd, segLen, entryDist);
    }

    float3 hit = ro + rd * tF;

    // THE TOP OF THE INTERIOR BOX IS AN OPENING, NOT A SURFACE.
    //
    // tpInteriorFace answers "which of the five lined faces is this point nearest", and it will
    // answer for a point on the open top too — with whichever WALL happens to be closest. So a
    // ray leaving through the top (looking up from inside the water, or straight up through the
    // tank from underneath) came back painted in wall tiles hanging in the air above the rim.
    // That is the back-facing tile mess visible from below. There is nothing there to shade.
    if (hit.y > gFree - 1e-3)
        return envAt(rd, 1.0) * exp(-((1.0 - saturate(water_tint)) * water_density) * max(tF, 0.0));

    int face = tpInteriorFace(hit, gHalf);
    bool sub = hit.y < 0.0;
    float3 lining = shadeLining(hit, face, rd, sub, tpFootprint(entryDist + tF, spread),
                                sub ? tpFishShadow(hit, gSun, -1) : 1.0);

    // Beer-Lambert over the path actually travelled, and a depth-proportional in-scatter. The
    // absorption is what turns the far wall teal and the near wall almost unchanged; the
    // in-scatter is what stops deep water going black instead of going blue.
    float dist = max(tF, 0.0);
    float3 sigma = (1.0 - saturate(water_tint)) * water_density;
    float3 tr = exp(-sigma * dist);
    float3 scat = water_tint * water_scatter * (1.0 - tr);

    return lining * tr + scat + tpMotes(ro, rd, dist, entryDist);
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

    // THE SHELL, AND HOW THICK IT IS.
    //
    // "Open" removes it outright rather than shading it away: with zero thickness the outer box
    // collapses onto the interior, so there is no top face outside the well and no corner post
    // left to draw, and every downstream test falls out on its own. That kills the white lip —
    // and it also kills the tank. With no shell there is no VERTICAL CORNER, so at three-quarter
    // view the two walls meet at nothing and the object stops reading as a container of water at
    // all; it reads as two flat pictures folded together. A tank needs an edge you can see.
    //
    // So the shell stays, and `lip_scale` decides how much of it there is. Thin is the point:
    // enough to catch a line of light down each corner and a hairline across the top, not enough
    // to draw a frame. The plan's own thickness is the full-scale reference.
    int   estyle = (int)edge_style;
    float shellT = (estyle == 3) ? 0.0 : gThick * max(lip_scale, 0.0);

    float3 oMin = float3(-gHalf.x - shellT, -gHalf.y - shellT, -gHalf.z - shellT);
    float3 oMax = float3( gHalf.x + shellT,  gFree,             gHalf.z + shellT);
    float3 iMin = float3(-gHalf.x, -gHalf.y, -gHalf.z);
    float3 iMax = float3( gHalf.x,  gFree + 1e-4,  gHalf.z);

    float tN, tF;
    if (!tpBox(ro, rd, oMin, oMax, tN, tF)) return envAt(rd, 0.0);

    float tEnter = max(tN, 0.0);
    float3 pe = ro + rd * tEnter;
    outDepth = tEnter;

    // --- the lip: the top face of the shell, outside the interior footprint.
    bool topFace = abs(pe.y - gFree) < 1e-3;
    bool overWell = (abs(pe.x) < gHalf.x) && (abs(pe.z) < gHalf.z);
    if (topFace && !overWell && estyle != 3)
        return shadeCoping(pe, rd, float3(0, 1, 0), estyle);

    // --- entering through a wall (or through the open top)
    float3 wallN = float3(0, 0, 0);
    float wallF = 0.0;
    if (!topFace)
    {
        wallN = -tpFaceNormal(tpInteriorFace(pe, gHalf + shellT));
        wallF = tpFresnel(dot(-rd, wallN), 1.0, glass_ior);
    }

    // ---------------------------------------------------------------------------------------
    // THE VERTICAL CORNERS.
    //
    // The lip is visible because it is a FACE — the top of the shell, an annulus with its own
    // normal and its own end-grain. The four vertical corners have no equivalent: they are just
    // the place two parallel slabs happen to meet, so the only thing standing there is a column
    // of shell one wall-thickness wide. Thin the lip down to something tasteful and that column
    // goes sub-pixel, and at three-quarter view the near corner shows NOTHING — the two walls
    // fold together at an invisible seam and the object stops reading as a tank at all.
    //
    // So the corners get their own width, independent of the lip, and their own geometry: the
    // normal is bent from the wall it was hit on toward the 45-degree diagonal, which is a
    // chamfer. A chamfer is what actually makes a glass corner legible — it faces a direction
    // neither wall does, so it catches its own vertical line of light and holds it while the
    // camera moves. Widening the wall instead would fix the corner by making the whole tank
    // clumsy, which is the trade this control exists to avoid.
    //
    // `over` is how far outside the interior footprint the entry point sits on each axis. On the
    // face actually hit that is the shell thickness; on the OTHER axis it is the signed distance
    // to the corner, negative while still out along the wall. So the smaller of the two is the
    // corner proximity, and it needs no per-face special casing.
    float  cornerT = 0.0;
    float3 cornerN = wallN;
    if (!topFace && estyle != 3)
    {
        float2 over = abs(pe.xz) - gHalf.xz;
        float  dist = max(-min(over.x, over.y), 0.0);
        cornerT = saturate(1.0 - dist / max(corner_w, 1e-4));
        cornerT *= cornerT * (3.0 - 2.0 * cornerT);          // ease, so the chamfer has no lip of its own
        float3 diag = normalize(float3(sign(pe.x) * 0.70711, 0.0, sign(pe.z) * 0.70711));
        cornerN = normalize(lerp(wallN, diag, cornerT));
    }

    // Inside the shell. Find where the interior begins.
    float iN, iF;
    float3 body;
    if (!tpBox(pe + rd * 1e-4, rd, iMin, iMax, iN, iF))
    {
        // Grazed the shell without entering the well — the vertical corner posts. Same material
        // as the lip, for the same reason: this is the OUTSIDE of the tank, and it has to agree
        // with the top edge it meets or the silhouette changes material halfway down.
        if (estyle == 3) return envAt(rd, 0.0);
        return shadeCoping(pe, rd, wallN, estyle);
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
                refl = envAt(rdir, 1.0);
            else
            {
                float3 rp = ps + rdir * rF;
                int rface = tpInteriorFace(rp, gHalf);
                refl = (rp.y > 0.0 && rp.y < gFree - 1e-3)
                     ? shadeLining(rp, rface, rdir, false, tpFootprint(tEnter + rF, 1.5), 1.0)
                     : envAt(rdir, 1.0);
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
            body = inside ? shadeLining(pl, face, rd, false, tpFootprint(tEnter + max(iN,0.0) + travel, 1.0), 1.0) : envAt(rd, 0.0);
        }
    }

    // --- back out through the glass. Two interfaces, so the wall darkens what it transmits at
    // grazing angles and adds its own reflection of the room on top.
    // The spotting rides on the wall's own Fresnel: a little extra reflectance, and a reflection
    // that goes SOFT in the spotted patches — the second half is what makes it read as texture
    // on the glass rather than as dirt drawn over it.
    float spots = tpGlassSpots(pe, wallN);
    float wf = saturate(wallF + spots * spot_gain);

    float3 c = body * (1.0 - wf * glass_reflect);
    c += envAt(reflect(rd, wallN), lerp(1.0, 0.15, spots)) * wf * glass_reflect;
    c *= exp(-glass_absorb * shellT * 2.0);

    // The chamfer, blended over the wall rather than branching around it, so the corner grades
    // into the flat glass instead of drawing a second hard edge beside itself.
    //
    // IT MUST KEEP WHAT IS BEHIND IT. shadeCoping transmits the ENVIRONMENT, which is right for
    // the lip — there is nothing behind the top of a wall but the room. Behind a corner there is
    // the tank, full of lit mosaic, so shading the corner the same way punched a dark bar
    // straight down the front of the piece: the chamfer was showing the dark backdrop through
    // solid glass that has a pool on the other side of it.
    //
    // So for glass the corner transmits `c`, the body already traced through this wall, and adds
    // only what a chamfer genuinely contributes — its own Fresnel reflection at a normal neither
    // wall has, plus a tight catchlight. That is a bright edge, not a hole. Opaque lip materials
    // keep shadeCoping, because for those the corner really is solid.
    if (cornerT > 0.001)
    {
        float3 edge;
        if (estyle == 0)
        {
            float3 rdir = reflect(rd, cornerN);
            float  cf   = tpFresnel(dot(-rd, cornerN), 1.0, glass_ior);
            edge  = c * (1.0 - cf) + envAt(rdir, 1.0) * cf;
            edge += gSunCol * pow(saturate(dot(rdir, gSun)), 300.0) * rim_gain * 1.2;
        }
        else edge = shadeCoping(pe, rd, cornerN, estyle);

        c = lerp(c, edge, cornerT);
    }

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
