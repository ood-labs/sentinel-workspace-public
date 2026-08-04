// vitreous.hlsli — the vitreous_cross data contract, material table and shape vocabulary.
//
// STAGE SPACE is the single layout transform and the only place placement is decided.
// It is a front elevation of the sculpture: x in [-1.5, 1.5], y in [-1, 1], +y UP,
// z in [-0.6, 0.6] pointing TOWARD the viewer (out of the screen), because the canonical
// camera sits at positive z and looks back down the axis. That rectangle is
// exactly the 3:2 frame of the reference at the canonical camera pose, so a record's
// (x, y) is literally where it lands in the picture and VC_Plan's schematic can draw
// records with no projection at all.
//
// HANDEDNESS. Sentinel's camera is left-handed: a camera sitting at +Z looking toward -Z
// puts world +X on the LEFT of the screen. vc_toWorld() performs the single x flip that
// reconciles stage space with that, and it is the ONLY place the flip happens. Get this
// wrong and the entire composition renders as a convincing mirror image.
#ifndef VC_VITREOUS_HLSLI
#define VC_VITREOUS_HLSLI

// ---------------------------------------------------------------------------
// Record buffer (VC_Plan -> VC_Env, VC_Render). 64 bytes, one role discriminator.
// ---------------------------------------------------------------------------
struct VcRec
{
    float3 pos;      // stage-space centre
    float3 dims;     // SLAB/PANEL: half-extents. INCLUSION: (rx, ry, rz) ellipsoid radii.
    float  role;
    float  mat;
    float3 tint;     // glass interior tint / panel albedo
    float  seed;
    float  p0;       // SLAB: edge bevel. INCLUSION: fusion weight. PANEL: unused.
    float  p1;       // INCLUSION: surface wobble amplitude.
    float  flags;
    float  active;
};

#define VC_SLAB_0      0u
#define VC_SLABS      12u
#define VC_INC_0      12u
// 24 inclusions, not 16. The reference's organic mass resolves into roughly two dozen distinct
// lobes across five clusters; at sixteen the clusters either read as too sparse or, once fused
// hard enough to fill the volumes, lose the lobe structure entirely. This is the count the
// subject actually has.
#define VC_INCS       24u
#define VC_PANEL_0    36u
#define VC_PANELS     10u
#define VC_STAGE      46u   // global stage record: pos = (yaw, pitch, unused)
#define VC_HEADER     47u   // editor header: signature, selection, drag grab, live counts
#define VC_RECORDS    48u

#define ROLE_SLAB    0.0
#define ROLE_INC     1.0
#define ROLE_PANEL   2.0
#define ROLE_HEADER  3.0

// ---------------------------------------------------------------------------
// Materials. The first four are TRANSMISSIVE and carry an index of refraction; the
// last three are OPAQUE. VC_Render switches on this to decide whether a ray refracts
// through the interface or terminates on it.
//
// MAT_CAVITY is the whole reason the reference reads as it does: the organic masses are
// air trapped inside the glass, so a ray crossing into one goes 1.50 -> 1.00 and bends
// the OTHER way. That sign change is what produces the reference's characteristic
// swollen, lensed interiors, and no amount of surface shading imitates it.
// ---------------------------------------------------------------------------
#define MAT_CLEAR   0   // optical glass, faint cool extinction
#define MAT_AMBER   1   // burnt-orange glass, heavy Beer-Lambert extinction
#define MAT_SMOKE   2   // lightly smoked neutral glass
#define MAT_CAVITY  3   // air/low-IOR inclusion with a thin-film membrane
#define MAT_FLUID   4   // denser inclusion, water-like
#define MAT_WHITE   5   // opaque plate, near-white lambert
#define MAT_BLACK   6   // opaque plate, near-black
#define MAT_COPPER  7   // opaque plate, burnt orange
#define MAT_COUNT   8

#define VC_MAT_TRANSMISSIVE(m) ((m) <= MAT_FLUID)

// Index of refraction per material. Air (outside everything) is 1.0.
float vc_ior(int m)
{
    if (m == MAT_CLEAR)  return 1.50;
    if (m == MAT_AMBER)  return 1.52;
    if (m == MAT_SMOKE)  return 1.49;
    if (m == MAT_CAVITY) return 1.00;
    if (m == MAT_FLUID)  return 1.34;
    return 1.0;
}

// Beer-Lambert extinction coefficient per unit stage distance, per channel.
float3 vc_extinction(int m, float3 tint)
{
    if (m == MAT_CLEAR)  return float3(0.055, 0.038, 0.030) * (2.0 - tint);
    if (m == MAT_AMBER)  return float3(0.32, 1.55, 3.40) * tint.r;
    if (m == MAT_SMOKE)  return float3(0.62, 0.63, 0.66) * tint.r;
    if (m == MAT_FLUID)  return float3(0.10, 0.07, 0.05);
    return float3(0.0, 0.0, 0.0);
}

// Opaque plate albedo.
float3 vc_plateAlbedo(int m, float3 tint)
{
    if (m == MAT_WHITE)  return float3(0.94, 0.94, 0.945) * tint;
    if (m == MAT_BLACK)  return float3(0.022, 0.022, 0.024);
    if (m == MAT_COPPER) return float3(0.78, 0.33, 0.13) * tint;
    return tint;
}

// flag bits
#define F_SELECTED 1u
#define F_EDITED   2u
#define F_HIDDEN   4u

// ---------------------------------------------------------------------------
// Stage <-> world. One transform, applied once, in both directions.
// ---------------------------------------------------------------------------
float3 vc_toWorld(float3 stage)
{
    // The x flip reconciles stage space (read off the reference, +x right) with
    // Sentinel's left-handed camera at +Z. See the handedness note at the top.
    return float3(-stage.x, stage.y, stage.z);
}

float3 vc_toStage(float3 world)
{
    return float3(-world.x, world.y, world.z);
}

// The editor's viewing rectangle, deliberately WIDER than the 3:2 program frame so an element
// dragged just outside the picture is still visible and still reachable. Draw and hit test
// both go through vc_uvToStage(), which is the only reason they cannot drift apart.
#define VC_VIEW_W 3.40
#define VC_VIEW_H 2.2666667

float2 vc_uvToStage(float2 uv)
{
    return float2((uv.x - 0.5) * VC_VIEW_W, (0.5 - uv.y) * VC_VIEW_H);
}

// ---------------------------------------------------------------------------
// Environment mapping. THE single definition: VC_Env writes with vc_envDir() and VC_Render
// reads with vc_envUV(), which are exact inverses, so the studio the glass refracts is
// provably the studio that was authored.
// ---------------------------------------------------------------------------
float3 vc_envDir(float2 uv)
{
    float phi = (uv.x - 0.5) * 6.2831853;
    float theta = uv.y * 3.14159265;
    float st = sin(theta);
    return float3(st * sin(phi), cos(theta), st * cos(phi));
}

float2 vc_envUV(float3 d)
{
    d = normalize(d);
    return float2(atan2(d.x, d.z) / 6.2831853 + 0.5,
                  acos(clamp(d.y, -1.0, 1.0)) / 3.14159265);
}

// ---------------------------------------------------------------------------
// Hashes and noise
// ---------------------------------------------------------------------------
float vc_rnd(float s, float k)
{
    return frac(sin(s * 12.9898 + k * 78.233) * 43758.5453);
}

float2 vc_hash22(float2 p)
{
    float3 p3 = frac(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.xx + p3.yz) * p3.zy);
}

float3 vc_hash33(float3 p)
{
    p = frac(p * float3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return frac((p.xxy + p.yxx) * p.zyx);
}

float vc_vnoise(float3 p)
{
    float3 i = floor(p);
    float3 f = frac(p);
    f = f * f * (3.0 - 2.0 * f);
    float n = 0.0;
    [unroll]
    for (int k = 0; k < 8; k++)
    {
        float3 o = float3((k & 1), ((k >> 1) & 1), ((k >> 2) & 1));
        float w = lerp(1.0 - f.x, f.x, o.x) * lerp(1.0 - f.y, f.y, o.y) * lerp(1.0 - f.z, f.z, o.z);
        n += w * vc_hash33(i + o).x;
    }
    return n * 2.0 - 1.0;
}

// ---------------------------------------------------------------------------
// Distance primitives
// ---------------------------------------------------------------------------
float vc_box(float3 p, float3 b)
{
    float3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

float vc_roundBox(float3 p, float3 b, float r)
{
    return vc_box(p, max(b - r, 0.0)) - r;
}

float vc_ellipsoid(float3 p, float3 r)
{
    float k0 = length(p / r);
    float k1 = length(p / (r * r));
    return k0 * (k0 - 1.0) / max(k1, 1e-5);
}

// Smooth union. The clamp is not cosmetic: iterating polynomial smin over many
// primitives compounds, and the accumulated understatement inflates a phantom shell
// well outside every contributing surface — spheres that are not there. Clamping the
// result to plainMin - k bounds the total inflation at one blend radius, forever.
float vc_fuse(float a, float b, float k)
{
    float h = saturate(0.5 + 0.5 * (b - a) / max(k, 1e-5));
    float m = lerp(b, a, h) - k * h * (1.0 - h);
    return max(m, min(a, b) - k);
}

#endif
