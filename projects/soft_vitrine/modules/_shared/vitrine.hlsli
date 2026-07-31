// vitrine.hlsli — the soft_vitrine data contract, palette, and 2D drawing vocabulary.
//
// STAGE SPACE is the single layout transform for the whole show: [0,1] x [0,1],
// origin top-left, +y DOWN. It is identical to a square generator pass's `uv` and to
// normalized viewport pointer coordinates, so render / pick / drag all share one mapping.
// VT_Plan is the ONLY node that decides placement. Every consumer reads stage space
// straight off `uv` and must not re-apply a global offset or scale.
//
// The show leaves 2D exactly once, in VT_Growth: stage (x, y) maps to world
// (x*2-1, 1-y*2) on X/Y with +y world-up, so the ray-marched masses register 1:1 with
// the flat layers when the camera sits at the canonical pose.
#ifndef VT_VITRINE_HLSLI
#define VT_VITRINE_HLSLI

// ---------------------------------------------------------------------------
// Plan buffer (VT_Plan -> everyone). One buffer, `role` discriminates.
// ---------------------------------------------------------------------------
#define PLAN_PLATE_0    0u
#define PLAN_PLATES    24u
#define PLAN_STROKE_0  24u
#define PLAN_STROKES   16u
#define PLAN_MASS_0    40u
#define PLAN_MASSES    16u
// Global stage geometry. The horizon is a PLACEMENT decision, so the plan authority owns it:
// VT_Stage draws the wall/floor seam there and VT_Composite mirrors reflections about the same
// number. pos = (horizon, room_depth).
#define PLAN_STAGE     62u
#define PLAN_HEADER    63u
#define PLAN_RECORDS   64u

#define ROLE_PLATE   0.0
#define ROLE_STROKE  1.0
#define ROLE_MASS    2.0
#define ROLE_HEADER  3.0

// flat graphic kinds (role PLATE)
#define PK_GRIDPLATE  0
#define PK_CHECKER    1
#define PK_STARPANEL  2
#define PK_SHELF      3
#define PK_DASH       4
#define PK_BEAN       5
#define PK_KINDS      6

// stroke archetypes (role STROKE)
#define SK_SQUIGGLE   0
#define SK_BUNDLE     1
#define SK_BRANCH     2
#define SK_ARC        3
#define SK_TANGLE     4
#define SK_KINDS      5

// mass archetypes (role MASS)
#define MK_MELT       0   // drippy vertical melt
#define MK_BLOB       1   // soft looped body
#define MK_RIBBON     2   // gestural ribbon stroke
#define MK_ARMS       3   // branching figure with raised arms
#define MK_HAND       4   // thick low branching mass
#define MK_STAR       5   // small splayed star-hand
#define MK_KINDS      6

// surface materials, shared by VT_Volumes and the plate/stroke shading fakes
#define MAT_CLAY      0
#define MAT_CHROME    1
#define MAT_FROST     2
#define MAT_GLOSS     3
#define MAT_COUNT     4

// flag bits packed into PlanRec.flags
#define F_SELECTED    1u
#define F_EDITED      2u
#define F_FRONT       4u   // composite draws this plate in front of the masses

struct PlanRec
{
    float2 pos;    // stage-space center
    float2 size;   // half-extent, or (reserve radius, growth scale) for a mass/stroke
    float role;
    float kind;
    float seed;
    float tone;    // palette slot 0..1
    float grp;     // depth band: 0 far .. 1 near. drives scale, haze and reflection strength
    float phase;   // motion phase offset
    float flags;
    float active;
};

// ---------------------------------------------------------------------------
// Limb buffer (VT_Growth -> VT_Volumes, VT_Strokes). One buffer, `role` discriminates.
//
//   role 0 = GROUP HEADER. pos = bounding-sphere centre (world for masses, stage for
//            strokes), radius = bounding radius, parent = first node index,
//            group = node count, kind = archetype, material = surface, active = live.
//            Headers 0..15 are masses (plan slot 40+i), 16..31 are strokes (plan 24+i).
//            The raymarcher tests these 16 spheres before touching any node, so a pixel
//            only pays for the masses it can actually see.
//   role 1 = MASS NODE.   pos = world centre, parent = parent node index (-1 = root).
//   role 2 = STROKE NODE. pos.xy = stage space, pos.z = parallax depth, parent = previous
//            point index (-1 = start of a run).
// ---------------------------------------------------------------------------
#define LIMB_MASS_H_0   0u
#define LIMB_MASS_H     16u
#define LIMB_STROKE_H_0 16u
#define LIMB_STROKE_H   16u
#define LIMB_HEADERS    32u
#define LIMB_NODE_0     32u        // mass nodes: 32 .. 415
#define LIMB_MASS_CAP   416u
#define LIMB_STROKE_0   416u       // stroke nodes: 416 .. 767
#define LIMB_RECORDS    768u

// Fixed partition rather than one shared cursor: a heavy cast of masses must not be able to
// starve the strokes of points (or the reverse), and each renderer then scans exactly one
// contiguous range.
//
// `material` is role-discriminated:
//   mass node   -> MAT_CLAY / MAT_CHROME / MAT_FROST / MAT_GLOSS
//   stroke node -> accent tone in 0..1, indexing VT_ACCENT. Per-node so one bundle can run a
//                  full rainbow across its strands.

#define LROLE_HEADER  0.0
#define LROLE_MASS    1.0
#define LROLE_STROKE  2.0

struct LimbRec
{
    float3 pos;
    float radius;
    float parent;    // node index, or -1
    float group;     // owning group header index
    float role;
    float material;
    float tparam;    // 0..1 along the limb, drives gradients and taper
    float seed;
    float kind;
    float active;
};

// ---------------------------------------------------------------------------
// Hash / noise. vt_ prefix so nothing collides with the sd_ helpers in _shared/sdf
// or with the compiler-injected `noise` feature library.
// ---------------------------------------------------------------------------
float vt_hash11(float p) { p = frac(p * 0.1031); p *= p + 33.33; p *= p + p; return frac(p); }

float vt_hash21(float2 p)
{
    float3 p3 = frac(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.x + p3.y) * p3.z);
}

float2 vt_hash22(float2 p)
{
    float3 p3 = frac(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.xx + p3.yz) * p3.zy);
}

float3 vt_hash33(float3 p)
{
    p = frac(p * float3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return frac((p.xxy + p.yxx) * p.zyx);
}

// deterministic scalar draw from a record seed
float vt_rnd(float seed, float salt) { return vt_hash21(float2(seed * 1.7 + salt * 3.13, salt * 7.31 + 1.0)); }

float vt_vnoise2(float2 p)
{
    float2 i = floor(p), f = frac(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = vt_hash21(i), b = vt_hash21(i + float2(1, 0));
    float c = vt_hash21(i + float2(0, 1)), d = vt_hash21(i + float2(1, 1));
    return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
}

float vt_fbm2(float2 p, int oct)
{
    float s = 0.0, a = 0.5;
    for (int i = 0; i < oct; i++) { s += a * vt_vnoise2(p); p *= 2.03; a *= 0.5; }
    return s;
}

// ---------------------------------------------------------------------------
// 2D distance vocabulary (stage space). vt_ prefixed.
// ---------------------------------------------------------------------------
float2 vt_rot2(float2 v, float a) { float s = sin(a), c = cos(a); return float2(v.x * c - v.y * s, v.x * s + v.y * c); }

float vt_dCircle(float2 p, float r) { return length(p) - r; }

float vt_dBox(float2 p, float2 b) { float2 d = abs(p) - b; return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0); }

float vt_dRBox(float2 p, float2 b, float r) { return vt_dBox(p, max(b - r, 0.0)) - r; }

float vt_dSeg(float2 p, float2 a, float2 b, out float h)
{
    float2 pa = p - a, ba = b - a;
    h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-9));
    return length(pa - ba * h);
}

float vt_dCapsule(float2 p, float2 a, float2 b, float r) { float h; return vt_dSeg(p, a, b, h) - r; }

// tapered capsule: radius lerps along the segment. Used everywhere strokes need weight.
float vt_dTaper(float2 p, float2 a, float2 b, float ra, float rb)
{
    float h; float d = vt_dSeg(p, a, b, h);
    return d - lerp(ra, rb, h);
}

float vt_smin(float a, float b, float k)
{
    float h = saturate(0.5 + 0.5 * (b - a) / max(k, 1e-6));
    return lerp(b, a, h) - k * h * (1.0 - h);
}

// pixel-width antialiased fill from a signed distance. `px` is one pixel in stage units.
float vt_fill(float d, float px) { return saturate(0.5 - d / max(px * 1.5, 1e-7)); }

// ---------------------------------------------------------------------------
// Palette. Derived from the reference: an electric-blue studio cyclorama with
// saturated toy-plastic and matte-clay objects, plus a hard black/white chrome and
// a full-spectrum accent set for the thin strokes.
// ---------------------------------------------------------------------------
#define C_WALL_TOP   float3(0.016, 0.035, 0.180)
#define C_WALL_MID   float3(0.055, 0.180, 0.760)
#define C_WALL_LOW   float3(0.180, 0.640, 0.960)
#define C_HORIZON    float3(0.560, 0.900, 1.000)
#define C_FLOOR      float3(0.028, 0.052, 0.200)
#define C_FLOOR_FAR  float3(0.090, 0.240, 0.640)

#define C_MAGENTA    float3(0.900, 0.130, 0.780)
#define C_PINK       float3(0.880, 0.115, 0.360)
#define C_NEON       float3(0.690, 0.940, 0.130)
#define C_CORAL      float3(0.870, 0.195, 0.290)
#define C_TERRA      float3(0.830, 0.250, 0.150)
#define C_FROSTC     float3(0.840, 0.850, 0.960)
#define C_PAPER      float3(0.960, 0.960, 0.955)

// 8 accent hues for the thin strokes and confetti, in reference order.
static const float3 VT_ACCENT[8] = {
    float3(0.145, 0.780, 0.330),   // grass green
    float3(0.075, 0.760, 0.760),   // cyan
    float3(0.945, 0.520, 0.090),   // orange
    float3(0.880, 0.180, 0.120),   // red
    float3(0.960, 0.845, 0.090),   // yellow
    float3(0.130, 0.290, 0.870),   // blue
    float3(0.055, 0.055, 0.060),   // near black
    float3(0.620, 0.930, 0.150)    // neon green
};

float3 vt_accent(float t) { return VT_ACCENT[((uint)(saturate(t) * 7.999)) & 7u]; }

// 6 body colours for the sculpted masses.
static const float3 VT_BODY[6] = {
    float3(0.900, 0.130, 0.780),   // magenta melt
    float3(0.840, 0.850, 0.960),   // frost
    float3(0.780, 0.790, 0.810),   // chrome base
    float3(0.870, 0.195, 0.290),   // coral
    float3(0.830, 0.250, 0.150),   // terracotta
    float3(0.880, 0.115, 0.360)    // hot pink
};

float3 vt_body(float t) { return VT_BODY[((uint)(saturate(t) * 5.999)) % 6u]; }

// ---------------------------------------------------------------------------
// The one place the show leaves 2D.
//
// The canonical camera sits at (0, 0, -1.732) looking down +z with a 60 degree vertical FOV,
// so the plane z = 0 has a half-height of exactly 1.0 and world XY in [-1,1] fills the square
// frame. `toWorld` pre-divides by the depth so a record PROJECTS to its planned stage position
// at any z — depth changes apparent size, shading and overlap, never planned placement.
// ---------------------------------------------------------------------------
#define VT_CAM_DIST 1.7320508

float vt_depthW(float grp) { return (lerp(0.32, -0.30, saturate(grp)) + VT_CAM_DIST) / VT_CAM_DIST; }

float3 vt_toWorld(float2 stage, float grp)
{
    float z = lerp(0.32, -0.30, saturate(grp));
    float w = (z + VT_CAM_DIST) / VT_CAM_DIST;
    return float3((stage.x * 2.0 - 1.0) * w, (1.0 - stage.y * 2.0) * w, z);
}

// sRGB-ish encode for the final 8-bit publish
float3 vt_tosrgb(float3 c) { return pow(max(c, 0.0), 1.0 / 2.2); }
float3 vt_tolin(float3 c) { return pow(max(c, 0.0), 2.2); }

#endif // VT_VITRINE_HLSLI
