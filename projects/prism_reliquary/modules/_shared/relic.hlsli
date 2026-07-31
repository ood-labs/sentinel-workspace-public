// prism_reliquary / _shared/relic.hlsli
//
// THE DATA CONTRACT. One record type, one buffer, one `role` discriminator, one owner.
// PR_Plan writes it; PR_Render and PR_Post only ever read it. Nothing downstream is allowed
// to re-decide where anything sits.
//
// The reference is a hybrid: organic masses (fur torus, soap drape, spheres) next to a
// technical family (the gem lattice) next to a graphic glyph. Rather than run two contracts,
// every family is a CastRec and `role` says how to read `dims`, `p0` and `p1`.

#ifndef PR_RELIC_HLSLI
#define PR_RELIC_HLSLI

// NOTE: include paths resolve against the INCLUDING MODULE's project dir, not against this
// file's location, so this is written as every module sees it.
#include "../_shared/prmath.hlsli"

// ---------------------------------------------------------------------------
// Record — 24 floats / 96 bytes. Must match the manifest schema exactly.
// ---------------------------------------------------------------------------
struct CastRec
{
    float3 pos;     // world position
    float  radius;  // primary radius / half-extent
    float4 rot;     // orientation quaternion (world -> local via pr_qinv)
    float3 dims;    // secondary extents, role-dependent
    float  role;
    float3 tint;    // linear base colour
    float  mat;
    float  p0;      // role-dependent parameter 0
    float  p1;      // role-dependent parameter 1
    float  seed;
    float  active;
    float  flags;   // F_* bits — editor state that must persist
    float3 aux;     // aux.x = kind step; .yz role-dependent spare
};

#define CAST_COUNT 96

// Per-record editor bits.
//
// NOTE what is NOT here: selection. The selected index lives in exactly one place, the
// editor header's pos.y, so it can never be stored twice and fall out of sync. Everything
// downstream compares its own index against that one number.
#define F_EDITED  1.0    // hand-moved or hand-changed; regeneration and derivation skip it
#define F_FLOOR   2.0    // y is locked to the ground plane; re-locked after every drag

bool pr_hasFlag(CastRec r, float bit) { return (fmod(floor(r.flags / bit), 2.0) > 0.5); }
float pr_setFlag(float flags, float bit, bool on)
{
    bool had = (fmod(floor(flags / bit), 2.0) > 0.5);
    if (on == had) return flags;
    return on ? (flags + bit) : (flags - bit);
}

// ---------------------------------------------------------------------------
// Fixed slot ranges. The renderer must never scan 96 records per march step, so every
// family lives at a known index range and the marcher loops only over what it needs.
// ---------------------------------------------------------------------------
#define SLOT_STAGE    0          // global stage record; also carries the exploration axes
#define SLOT_TORUS    1
#define SLOT_GLYPH    2          // .. 11
#define GLYPH_MAX     10
#define SLOT_PLATE    12         // gem backing panel; carries the whole lattice
#define SLOT_GEM      16         // .. 55, one record per occupied cell
#define GEM_MAX       40
#define SLOT_SPHERE   56         // .. 59
#define SPHERE_MAX    4
#define SLOT_RING     60
#define SLOT_FILM     61
#define SLOT_POST     62         // .. 63
#define POST_MAX      2
// The editor header. Last slot on purpose: it sits outside every family range the renderer
// iterates, so the marcher never sees it and never has to know the editor exists.
#define SLOT_EDIT     95

// ---------------------------------------------------------------------------
// Roles
// ---------------------------------------------------------------------------
#define ROLE_NONE    0.0
#define ROLE_STAGE   1.0
#define ROLE_TORUS   2.0
#define ROLE_GLYPH   3.0
#define ROLE_PLATE   4.0
#define ROLE_GEM     5.0
#define ROLE_SPHERE  6.0
#define ROLE_RING    7.0
#define ROLE_FILM    8.0
#define ROLE_POST    9.0
#define ROLE_EDIT   10.0

// ---------------------------------------------------------------------------
// Materials. The renderer's shade pass switches on these.
// ---------------------------------------------------------------------------
#define MAT_FUR      0.0   // iridescent pelt
#define MAT_DGLASS   1.0   // smoked glass with a chromatic edge
#define MAT_CHROME   2.0   // mirror
#define MAT_GEM      3.0   // faceted chip
#define MAT_EMIT     4.0   // the light ring
#define MAT_MARBLE   5.0   // swirled stone
#define MAT_PLATE    6.0   // matte dark backing panel
#define MAT_FLOOR    7.0   // glossy stage floor
#define MAT_FILM     8.0   // soap membrane (transmissive, handled in its own pass)

// ---------------------------------------------------------------------------
// FRAME CONTRACT
//
// The saved camera pose is part of the composition, not a preference. A long lens
// (28 degrees at 12 units) reproduces the reference's very flat perspective; a wide lens
// makes the torus splay and the glyph keystone.
//
// Because the lens is fixed and known, layout can be authored in REFERENCE IMAGE
// COORDINATES — img.x 0..1 left to right, img.y 0..1 top to bottom — and projected to
// world at a freely chosen depth. That is why the tables in plan.hlsl are readable as
// transcriptions of the reference rather than as a pile of tuned world coordinates.
// ---------------------------------------------------------------------------
#define PR_CAM_X      0.0
#define PR_CAM_Y      2.22
#define PR_CAM_Z      12.0
#define PR_CAM_FOV    28.0
#define PR_TAN_HALF   0.24932800    // tan(14 degrees)
#define PR_AR         0.8           // 4:5 portrait, width / height

// Frame height in world units at depth z.
float pr_frame_h(float z) { return (PR_CAM_Z - z) * PR_TAN_HALF * 2.0; }
// Frame width in world units at depth z.
float pr_frame_w(float z) { return pr_frame_h(z) * PR_AR; }

// Reference image coordinate -> world position at depth z.
//
// THE X NEGATION IS LOAD-BEARING. Sentinel's camera is left-handed, so a camera sitting at
// +Z and looking toward -Z puts world +X on the LEFT of frame. The layout tables are written
// in reference-image coordinates, where x runs left to right, so the projection has to flip.
// Without this the entire composition renders mirrored — and mirrored convincingly enough
// that it is easy to mistake for a layout mistake rather than a handedness one.
float3 pr_place(float2 img, float z)
{
    float hh = (PR_CAM_Z - z) * PR_TAN_HALF;
    return float3(-(img.x - 0.5) * 2.0 * hh * PR_AR,
                   PR_CAM_Y + (0.5 - img.y) * 2.0 * hh,
                   z);
}

// World position -> reference image coordinate. Exact inverse of pr_place, including the
// flip. The plan preview draws with this, so the schematic and the render agree by
// construction rather than by tuning.
float2 pr_unplace(float3 p)
{
    float hh = max(PR_CAM_Z - p.z, 1e-3) * PR_TAN_HALF;
    return float2(0.5 - p.x / (2.0 * hh * PR_AR),
                  0.5 - (p.y - PR_CAM_Y) / (2.0 * hh));
}

// A length measured as a fraction of the reference frame WIDTH -> world units at depth z.
float pr_wlen(float f, float z) { return f * pr_frame_w(z); }

// Direction -> equirectangular uv. THE single definition of the environment mapping:
// PR_Env writes with its inverse, PR_Render reads with this, so the studio the chrome
// reflects is provably the studio that was authored.
float2 pr_env_uv(float3 d)
{
    d = normalize(d);
    return float2(atan2(d.z, d.x) / PR_TAU + 0.5,
                  acos(clamp(d.y, -1.0, 1.0)) / PR_PI);
}

// ---------------------------------------------------------------------------
// Palette. Derived from the reference: an almost monochrome dark stage whose only colour
// arrives as dispersion off the speculars. Nothing here is a "neon" preset — the hues are
// spectral, produced by pr_spectral / pr_thinfilm, and the base materials are neutral.
// ---------------------------------------------------------------------------
#define PR_VOID     float3(0.0130, 0.0140, 0.0165)   // backdrop
#define PR_FLOORCOL float3(0.0180, 0.0185, 0.0205)   // stage floor
#define PR_PELT     float3(0.0420, 0.0410, 0.0450)   // fur base, nearly black
#define PR_SMOKE    float3(0.0300, 0.0320, 0.0380)   // dark glass body
#define PR_STEEL    float3(0.7400, 0.7500, 0.7800)   // chrome
#define PR_CHALK    float3(0.8600, 0.8700, 0.9000)   // emissive ring / white chips
#define PR_RUBY     float3(0.4200, 0.0500, 0.0700)   // the red chips in the lattice

// A blank record. Everything the plan does not fill stays inactive rather than undefined.
CastRec pr_blank()
{
    CastRec r;
    r.pos    = float3(0, 0, 0);
    r.radius = 0.0;
    r.rot    = float4(0, 0, 0, 1);
    r.dims   = float3(0, 0, 0);
    r.role   = ROLE_NONE;
    r.tint   = float3(0, 0, 0);
    r.mat    = MAT_PLATE;
    r.p0     = 0.0;
    r.p1     = 0.0;
    r.seed   = 0.0;
    r.active = 0.0;
    r.flags  = 0.0;
    r.aux    = float3(0, 0, 0);
    return r;
}

#endif // PR_RELIC_HLSLI
