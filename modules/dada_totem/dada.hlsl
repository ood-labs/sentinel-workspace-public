// dada_totem — a surrealist Dada assemblage totem raymarched as ONE SDF scene in a
// barren desert. Everything (sculpture + ground + sky) shares one depth domain so a
// fly camera can roam it with real occlusion, sun shadows and AO.
//
// STAGE 1: the environment + camera + lighting shell. Ground plane, gradient sky with
// a hazy distant ridge, soft studio sun, and two test primitives to prove the mood.
// Later stages hang the black spine, the part-list of solids, and the hero pieces off
// this shell.

#include "../_shared/sdf/sdf_ops.hlsli"
#include "../_shared/sdf/sdf_shading.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

// active ray origin, set in main() — correct in both fly and orbit modes.
static float3 g_camPos = float3(0, 0, 0);

// ---- value noise / fbm (for sand grain + horizon ridge) ----------------------
float vnoise2(float2 p)
{
    float2 i = floor(p); float2 f = frac(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = sd_hash21(i);
    float b = sd_hash21(i + float2(1, 0));
    float c = sd_hash21(i + float2(0, 1));
    float d = sd_hash21(i + float2(1, 1));
    return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
}
float fbm2(float2 p)
{
    float s = 0.0, a = 0.5;
    for (int i = 0; i < 5; i++) { s += a * vnoise2(p); p *= 2.02; a *= 0.5; }
    return s;
}

// ---- spline / turned-geometry helpers (harvest candidates) -------------------
// quadratic-bezier tube: A->B->C swept capsule, approximated by 8 segments. The
// "spline" transport for wires, rigging and bent arcs.
float sd_bezierTube(float3 p, float3 a, float3 b, float3 c, float r)
{
    float d = 1e9;
    float3 prev = a;
    [unroll] for (int i = 1; i <= 8; i++)
    {
        float t = (float)i / 8.0;
        float3 pt = lerp(lerp(a, b, t), lerp(b, c, t), t);
        d = min(d, sd_capsule(p, prev, pt, r));
        prev = pt;
    }
    return d;
}

// a turned white baluster / chess-pawn finial: stacked lathe-like primitives.
float obj_baluster(float3 p, float3 base)
{
    float3 q = p - base;
    float d = sd_cyl(q - float3(0, 0.04, 0), 0.04, 0.14);           // foot disc
    d = min(d, sd_sphere(q - float3(0, 0.26, 0), 0.155));           // lower bulb
    d = min(d, sd_cone(q - float3(0, 0.52, 0), 0.20, 0.12, 0.05));  // neck
    d = min(d, sd_torus(q - float3(0, 0.74, 0), 0.085, 0.028));     // collar
    d = min(d, sd_sphere(q - float3(0, 0.94, 0), 0.11));            // upper bulb
    d = min(d, sd_sphere(q - float3(0, 1.12, 0), 0.055));           // finial tip
    return d;
}

// ---- material ids (extends the _shared MAT_* set) ----------------------------
#define M_GROUND 0.0
#define M_WOOD   1.0
#define M_BLACK  2.0   // matte black (spine/panels)
#define M_WHITE  3.0   // white plaster (shelves)
// painted / assemblage palette
#define M_RED    10.0
#define M_YELLOW 11.0
#define M_ORANGE 12.0
#define M_OLIVE  13.0
#define M_GRAY   14.0
#define M_BLACKG 15.0  // glossy black balls / discs
#define M_WHITEG 16.0  // glossy white spheres
#define M_GOLD   17.0
// hero pieces with procedural multi-colour materials (need their centre to shade)
#define M_BEACH  20.0  // rainbow-gore beach ball
#define M_RAINBOW 21.0 // diagonal rainbow-stripe lens
#define M_HARLEQ 22.0  // harlequin-checker cone

#define PI 3.14159265

static const float3 BALL_C = float3(-2.25, 4.85, 0.35);  // beach ball centre
static const float3 LENS_C = float3(0.05, 6.45, 0.20);   // rainbow lens centre
static const float3 HARL_C = float3(0.10, 4.30, 0.95);   // harlequin cone base

// procedural wood grain for the base plank and shelves
float3 woodAlbedo(float3 p)
{
    float g   = fbm2(float2(p.x * 1.1 + p.z * 0.2, p.z * 0.5 + p.y * 0.3));
    float ring = frac(g * 3.0 + p.x * 0.55 + p.z * 0.15);
    float streak = smoothstep(0.15, 0.85, ring * 0.55 + g * 0.45);
    float3 dark  = float3(0.30, 0.19, 0.10);
    float3 light = float3(0.56, 0.41, 0.24);
    return lerp(dark, light, streak);
}

// ---- assemblage sub-maps -----------------------------------------------------

// the wooden plank the whole totem stands on, resting on the desert
float2 mapBase(float3 p)
{
    float3 q = p - float3(0.0, 0.15, 0.35);
    q.xz = sd_rot2(q.xz, 0.14);                       // slight yaw, like a dropped board
    float plank = sd_box(q, float3(3.1, 0.14, 1.75));
    return float2(plank, M_WOOD);
}

// the bold black armature — vertical spine slab + upper panel + a mid crossbar,
// giving the reference's black "cross/F" that everything hangs off.
float2 mapSpine(float3 p)
{
    float spine = sd_box(p - float3(0.0, 4.60, -0.15), float3(0.80, 3.55, 0.28));
    float panel = sd_box(p - float3(0.0, 6.60, -0.20), float3(1.34, 1.42, 0.24));
    float cross = sd_box(p - float3(0.0, 3.55, -0.12), float3(1.95, 0.30, 0.32));
    float d = min(spine, min(panel, cross));
    return float2(d, M_BLACK);
}

// white shelves / plinths the mid-tier objects sit on
float2 mapPlatforms(float3 p)
{
    float shelf = sd_rbox(p - float3(0.15, 3.60, 0.60), float3(2.15, 0.055, 0.95), 0.015);
    float2 res = float2(shelf, M_WHITE);
    float plinth = sd_rbox(p - float3(-1.70, 2.25, 0.30), float3(0.52, 1.15, 0.55), 0.03);
    res = op_matmin(res, float2(plinth, M_WHITE));
    return res;
}

// the bulk of the assemblage: hand-placed generic solids (spheres, cones, cylinders,
// boxes). Each op_matmin adds one part with its material. Hero pieces (crescent moon,
// beach ball, rainbow lens, harlequin cone) and the splines come in later stages.
float2 mapParts(float3 p)
{
    float2 r = float2(1e9, M_WHITE);

    // ---- crown: black sphere on a black cone-stand, red spheres ----
    r = op_matmin(r, float2(sd_sphere(p - float3(0.0, 8.55, 0.05), 0.46), M_BLACKG));
    r = op_matmin(r, float2(sd_cone(p - float3(0.0, 8.02, 0.05), 0.36, 0.05, 0.28), M_BLACK));
    r = op_matmin(r, float2(sd_sphere(p - float3(0.90, 8.35, 0.15), 0.40), M_RED));
    r = op_matmin(r, float2(sd_sphere(p - float3(-0.42, 9.05, 0.0), 0.28), M_RED));

    // ---- upper: red balloon on the right ----
    r = op_matmin(r, float2(sd_sphere(p - float3(1.75, 7.05, 0.30), 0.52), M_RED));

    // ---- mid shelf props (shelf top ~ y 3.69) ----
    // red cube on the white plinth
    r = op_matmin(r, float2(sd_rbox(sd_rotY(p - float3(-1.70, 3.78, 0.35), 0.55),
                                    float3(0.42, 0.42, 0.42), 0.03), M_RED));
    // yellow drawer box
    r = op_matmin(r, float2(sd_rbox(p - float3(0.62, 4.05, 0.55),
                                    float3(0.55, 0.32, 0.42), 0.02), M_YELLOW));
    // black glossy ball resting on the shelf
    r = op_matmin(r, float2(sd_sphere(p - float3(-0.95, 4.12, 0.55), 0.36), M_BLACKG));
    // three floating spheres in a row (white, grey, olive), gently bobbing
    float bob0 = 0.06 * sway * sin(_Time * anim_speed * 0.9 + 0.0);
    float bob1 = 0.06 * sway * sin(_Time * anim_speed * 0.9 + 2.1);
    float bob2 = 0.06 * sway * sin(_Time * anim_speed * 0.9 + 4.2);
    r = op_matmin(r, float2(sd_sphere(p - float3(-0.30, 3.05 + bob0, 1.00), 0.34), M_WHITEG));
    r = op_matmin(r, float2(sd_sphere(p - float3(0.38, 3.00 + bob1, 1.00), 0.32), M_GRAY));
    r = op_matmin(r, float2(sd_sphere(p - float3(1.02, 2.95 + bob2, 1.00), 0.30), M_OLIVE));

    // ---- lower: tall red cone pointing down (wide top, narrow base) ----
    r = op_matmin(r, float2(sd_cone(p - float3(-1.15, 1.70, 0.15), 1.15, 0.06, 0.50), M_RED));
    // black vinyl disc (thin cylinder laid to face forward)
    {
        float3 q = sd_rotX(p - float3(1.70, 1.65, 0.30), 1.5708);
        r = op_matmin(r, float2(sd_cyl(q, 0.05, 0.70), M_BLACKG));
    }
    // hanging pendulum spheres (wires added in Stage 5)
    r = op_matmin(r, float2(sd_sphere(p - float3(-2.35, 2.70, 0.05), 0.26), M_YELLOW));
    r = op_matmin(r, float2(sd_sphere(p - float3(-2.35, 1.92, 0.05), 0.24), M_BLACKG));
    r = op_matmin(r, float2(sd_sphere(p - float3(-2.35, 1.20, 0.05), 0.24), M_ORANGE));
    // low centre black ball
    r = op_matmin(r, float2(sd_sphere(p - float3(0.15, 1.30, 0.40), 0.30), M_BLACKG));

    return r;
}

// the identity-defining hero pieces, each a bespoke SDF with a procedural material:
// the crescent moon, the rainbow beach ball, the porthole rainbow lens, and the
// harlequin cone. Flat cutout pieces are real thin discs facing +Z (on-aesthetic).
float2 mapHeroes(float3 p)
{
    float2 r = float2(1e9, M_WHITE);

    // ---- crescent moon: big white disc + offset black disc proud in front ----
    {
        float3 c = float3(2.05, 7.40, -0.05);
        float3 q  = sd_rotX(p - c, PI * 0.5);                    // face +Z
        float white = sd_cyl(q, 0.11, 1.32);
        float3 qb = sd_rotX(p - (c + float3(-0.52, 0.50, 0.13)), PI * 0.5);
        float black = sd_cyl(qb, 0.18, 1.06);                    // big offset disc → white reads as crescent
        r = op_matmin(r, float2(white, M_WHITE));
        r = op_matmin(r, float2(black, M_BLACKG));
    }

    // ---- beach ball: rainbow gores (coloured in matAlbedo from BALL_C) ----
    r = op_matmin(r, float2(sd_sphere(p - BALL_C, 0.72), M_BEACH));

    // ---- rainbow lens in a porthole ring (torus rim + striped disc) ----
    {
        float3 q = sd_rotX(p - LENS_C, PI * 0.5);
        float rim  = sd_torus(q, 1.00, 0.12);                    // white ring
        float disc = sd_cyl(q, 0.06, 0.92);                      // rainbow inside
        r = op_matmin(r, float2(rim, M_WHITE));
        r = op_matmin(r, float2(disc, M_RAINBOW));
    }

    // ---- harlequin wedge/sail: a cone flattened in Z into a stylised triangle ----
    {
        float3 hq = p - (HARL_C + float3(0, 0.55, 0));
        hq.z *= 2.4;                                            // squash to a wedge
        r = op_matmin(r, float2(sd_cone(hq, 0.55, 0.36, 0.02) / 2.4, M_HARLEQ));
    }

    return r;
}

// the airy thin elements: gold hoops, mast + rigging wires, pendulum strings, a
// beaded spindle, a bent wire arc, a turned baluster and a black bowl. These give
// the reference its spindly negative-space quality.
float2 mapSplines(float3 p)
{
    float2 r = float2(1e9, M_GRAY);

    // ---- gold hoops floating upper-left (thin tilted tori, gently tumbling) ----
    {
        float tilt = 1.15 + 0.22 * sway * sin(_Time * anim_speed * 0.5);
        float3 q = sd_rotY(sd_rotX(p - float3(-2.20, 6.55, 0.10), tilt), 0.45);
        r = op_matmin(r, float2(sd_torus(q, 0.98, 0.045), M_GOLD));
        float tilt2 = 1.40 + 0.18 * sway * sin(_Time * anim_speed * 0.6 + 1.7);
        float3 q2 = sd_rotX(p - float3(-1.55, 3.10, 0.55), tilt2);
        r = op_matmin(r, float2(sd_torus(q2, 0.55, 0.035), M_GOLD));
    }

    // ---- mast + rigging wires (thin diagonal pole with strung bezier cables) ----
    float3 mastTop = float3(-2.55, 7.75, -0.05);
    r = op_matmin(r, float2(sd_capsule(p, float3(-1.55, 3.75, 0.20), mastTop, 0.03), M_BLACK));
    r = op_matmin(r, float2(sd_bezierTube(p, mastTop, float3(-1.1, 6.0, 0.3), float3(-0.1, 4.0, 0.6), 0.012), M_GOLD));
    r = op_matmin(r, float2(sd_bezierTube(p, mastTop, float3(-3.0, 5.8, 0.2), float3(-2.3, 3.9, 0.4), 0.012), M_GOLD));

    // ---- pendulum strings down to the hanging balls (placed in mapParts) ----
    r = op_matmin(r, float2(sd_capsule(p, float3(-2.05, 3.30, 0.05), float3(-2.35, 2.70, 0.05), 0.012), M_BLACK));
    r = op_matmin(r, float2(sd_capsule(p, float3(-2.35, 2.70, 0.05), float3(-2.35, 1.92, 0.05), 0.012), M_BLACK));
    r = op_matmin(r, float2(sd_capsule(p, float3(-2.35, 1.92, 0.05), float3(-2.35, 1.20, 0.05), 0.012), M_BLACK));

    // ---- beaded spindle under the red balloon (rod + spaced beads) ----
    {
        r = op_matmin(r, float2(sd_capsule(p, float3(1.75, 5.55, 0.30), float3(1.75, 6.90, 0.30), 0.022), M_GRAY));
        [unroll] for (int i = 0; i < 4; i++)
        {
            float y = 5.78 + 0.33 * i;
            float mat = (i & 1) ? M_GOLD : M_BLACKG;
            r = op_matmin(r, float2(sd_sphere(p - float3(1.75, y, 0.30), 0.093), mat));
        }
    }

    // ---- bent wire arc lower-right ----
    r = op_matmin(r, float2(sd_bezierTube(p, float3(1.15, 0.55, 0.45), float3(2.75, 1.35, 0.15), float3(2.05, 0.15, 0.55), 0.03), M_GRAY));

    // ---- turned white baluster finial on the right of the shelf ----
    r = op_matmin(r, float2(obj_baluster(p, float3(1.45, 3.655, 0.70)), M_WHITE));

    // ---- black bowl (open hemisphere shell) on a small stem ----
    {
        float3 q = p - float3(0.05, 4.05, 0.78);
        float outer = sd_sphere(q, 0.36);
        float inner = sd_sphere(q, 0.29);
        float bowl = max(max(outer, -inner), q.y);          // keep the lower shell
        float stem = sd_cone(p - float3(0.05, 3.80, 0.78), 0.16, 0.05, 0.12);
        r = op_matmin(r, float2(min(bowl, stem), M_BLACKG));
    }

    return r;
}

// ---- the scene (contract for sdf_shading.hlsli) ------------------------------
float2 sceneMap(float3 p)
{
    // desert ground plane at y = 0 (gentle undulation so it isn't glassy flat)
    float ground = p.y + 0.04 * fbm2(p.xz * 0.15) - 0.02;
    float2 res = float2(ground, M_GROUND);

    res = op_matmin(res, mapBase(p));
    res = op_matmin(res, mapSpine(p));
    res = op_matmin(res, mapPlatforms(p));
    res = op_matmin(res, mapParts(p));
    res = op_matmin(res, mapHeroes(p));
    res = op_matmin(res, mapSplines(p));
    return res;
}

// ---- sky + distant mountains for a ray that misses all geometry ---------------
float3 skyColor(float3 rd)
{
    float3 zenith  = sky_zenith.rgb;
    float3 horizon = sky_horizon.rgb;
    float h = saturate(rd.y);
    float3 sky = lerp(horizon, zenith, pow(h, 0.55));

    // a low hazy ridge sitting just above the horizon line (right-heavy like the ref,
    // but present all round so it reads from any fly angle). azimuth-driven silhouette.
    float az = atan2(rd.z, rd.x);
    float ridge = (fbm2(float2(az * 2.4, 0.0) * 3.0 + 11.0) - 0.5) * 0.05
                + (fbm2(float2(az * 6.1, 5.0) * 3.0) - 0.5) * 0.018;
    float base = 0.006;
    float m = smoothstep(base + ridge + 0.006, base + ridge - 0.006, rd.y);   // 1 below ridge
    m *= smoothstep(-0.08, 0.02, rd.y);                                        // fade under horizon
    float3 mtn = lerp(float3(0.58, 0.62, 0.68), horizon, 0.55);               // hazy blue-grey
    sky = lerp(sky, mtn, m * 0.9);
    return sky;
}

// desert surface albedo with faint drift of tone
float3 groundAlbedo(float3 p)
{
    float g = fbm2(p.xz * 0.6);
    float3 sand = lerp(float3(0.78, 0.71, 0.57), float3(0.85, 0.79, 0.66), g);
    return sand;
}

// six-colour beach-ball gore palette
float3 goreColor(int i)
{
    i = ((i % 6) + 6) % 6;
    if (i == 0) return float3(0.82, 0.16, 0.13);   // red
    if (i == 1) return float3(0.90, 0.45, 0.10);   // orange
    if (i == 2) return float3(0.93, 0.78, 0.14);   // yellow
    if (i == 3) return float3(0.22, 0.55, 0.32);   // green
    if (i == 4) return float3(0.16, 0.40, 0.64);   // blue
    return float3(0.93, 0.92, 0.88);               // white
}

float3 heroAlbedo(float mat, float3 p)
{
    if (mat < 20.5)   // beach ball: longitudinal rainbow gores + white poles
    {
        float3 lp = normalize(p - BALL_C);
        float a = atan2(lp.z, lp.x);
        int seg = (int)floor((a / (2.0 * PI) + 0.5) * 6.0);
        float3 c = goreColor(seg);
        return lerp(c, float3(0.93, 0.92, 0.88), smoothstep(0.72, 0.92, abs(lp.y)));
    }
    if (mat < 21.5)   // rainbow lens: 45-degree bands red/blue/green/yellow
    {
        float3 lp = p - LENS_C;
        float s = (lp.x + lp.y) * 0.70;
        int b = ((int)floor(s * 1.7 + 16.0)) % 4;
        if (b == 0) return float3(0.88, 0.11, 0.09);   // deep primary red
        if (b == 1) return float3(0.14, 0.38, 0.66);   // blue
        if (b == 2) return float3(0.20, 0.55, 0.30);   // green
        return float3(0.95, 0.77, 0.10);               // yellow
    }
    // harlequin cone: two-tone diagonal checker
    float3 lp = p - HARL_C;
    float a = atan2(lp.z, lp.x);
    int chk = ((int)floor(a * 3.0 / PI) + (int)floor(lp.y * 7.0)) & 1;
    return chk ? float3(0.93, 0.78, 0.14) : float3(0.10, 0.10, 0.12);
}

float3 matAlbedo(float mat, float3 p)
{
    if (mat > 19.5) return heroAlbedo(mat, p);
    // structural
    if (mat < 0.5) return groundAlbedo(p);
    if (mat < 1.5) return woodAlbedo(p);
    if (mat < 2.5) return float3(0.018, 0.018, 0.022);  // black matte (deep)
    if (mat < 3.5) return float3(0.945, 0.935, 0.905);  // white plaster (clean)
    // painted palette (deeper, more graphic)
    if (mat < 10.5) return float3(0.86, 0.13, 0.09);    // red
    if (mat < 11.5) return float3(0.95, 0.75, 0.10);    // yellow
    if (mat < 12.5) return float3(0.90, 0.40, 0.08);    // orange
    if (mat < 13.5) return float3(0.48, 0.52, 0.24);    // olive
    if (mat < 14.5) return float3(0.52, 0.53, 0.55);    // grey
    if (mat < 15.5) return float3(0.020, 0.020, 0.024); // glossy black (deep)
    if (mat < 16.5) return float3(0.955, 0.945, 0.915); // glossy white
    return float3(0.85, 0.66, 0.24);                    // gold
}

// specular (amount, power) per material — matte plaster vs glossy balls vs metal
float2 matSpec(float mat)
{
    if (mat > 19.5) return float2(0.08, 26.0);  // hero pieces (painted matte)
    if (mat < 0.5) return float2(0.02, 16.0);   // ground
    if (mat < 1.5) return float2(0.04, 18.0);   // wood
    if (mat < 2.5) return float2(0.03, 24.0);   // black matte
    if (mat < 3.5) return float2(0.07, 26.0);   // white plaster
    if (mat < 13.5) return float2(0.09, 26.0);  // painted matte (red/yellow/orange/olive)
    if (mat < 14.5) return float2(0.20, 40.0);  // grey (semi-gloss)
    if (mat < 15.5) return float2(0.22, 44.0);  // black (semi-gloss)
    if (mat < 16.5) return float2(0.20, 40.0);  // white (semi-gloss)
    return float2(0.72, 42.0);                  // gold (metal)
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float2 ndc = (uv * 2.0 - 1.0) * float2(_Resolution.x / _Resolution.y, -1.0);

    float3 ro, rd;
    if (cam_mode == 0)   // Fly — unproject NDC through the live inverse view-projection
    {
        float2 ndcv = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
        float4 nearW = mul(_InvViewProjMatrix, float4(ndcv, 0.0, 1.0));
        float4 farW  = mul(_InvViewProjMatrix, float4(ndcv, 1.0, 1.0));
        nearW /= nearW.w; farW /= farW.w;
        ro = _CameraPos;
        rd = normalize(farW.xyz - nearW.xyz);
    }
    else                 // Orbit — deterministic rig for captures / A-B
    {
        float az = cam_orbit + rotate_speed * _Time * 30.0;
        sdf_orbitRay(az, cam_elevation, cam_distance,
                     float3(0.0, cam_target_y, 0.0), ndc, cam_focal, ro, rd);
    }
    g_camPos = ro;

    float3 sun = sdf_sunDir(sun_azimuth, sun_elevation);
    float3 haze = lerp(sky_horizon.rgb, float3(0.86, 0.83, 0.76), 0.5);

    float mat;
    float t = sdf_march(ro, rd, march_dist, 200, mat);

    float3 col;
    if (t < 0.0)
    {
        col = skyColor(rd);
    }
    else
    {
        float3 pos = ro + rd * t;
        float3 n = sdf_calcNormal(pos);
        float ao = sdf_calcAO(pos, n);
        float sha = 1.0;
        if (shadows != 0) sha = sdf_softShadow(pos + n * 0.02, sun, 16.0, 24.0);

        float3 albedo = matAlbedo(mat, pos);
        float2 sp = matSpec(mat);
        col = sdf_shade(albedo, n, rd, sun, sha, ao, sp.x, sp.y);

        // cool sky ambient fill from above (museum softness)
        float sky_up = saturate(0.5 + 0.5 * n.y);
        col += albedo * sky_zenith.rgb * sky_up * 0.10;

        // warm bounce off the sunlit sand below — softens the white shelf/pawn AO
        col += albedo * float3(0.95, 0.80, 0.55) * 0.07 * saturate(0.35 - n.y) * ao;

        // atmospheric haze — starts PAST the subject so the sculpture keeps its deep
        // blacks and saturated colour; only the far desert/ground recedes into haze.
        float fog = 1.0 - exp(-fog_density * 0.020 * max(t - 16.0, 0.0));
        col = lerp(col, haze, fog);
    }

    col = pow(saturate(col * exposure), 1.0 / 2.2);
    OutputUAV[pixel] = float4(col, 1.0);
}
