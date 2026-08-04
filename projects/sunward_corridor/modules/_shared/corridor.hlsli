// corridor.hlsli — the sunward_corridor data contract, palette and shape vocabulary.
//
// CORRIDOR SPACE. The tunnel runs along +z. The camera sits near the origin and never
// travels: the corridor scrolls THROUGH it. World z is sampled at (z + travel), and every
// piece of geometry is periodic with SC_LOOP_Z, so travel wrapping at SC_LOOP_Z is a
// bit-exact seam. That is the whole trick behind the infinite zoom — there is no teleport
// to hide, because the frame at travel = 0 and travel = SC_LOOP_Z are the same frame.
//
// SC_Plan is the ONLY node that decides corridor shape, aperture, palette, mass placement,
// sun geometry or travel phase. SC_Corridor reads records and owns light, surface and camera.
#ifndef SC_CORRIDOR_HLSLI
#define SC_CORRIDOR_HLSLI

// ---------------------------------------------------------------------------
// Plan buffer (SC_Plan -> SC_Corridor). One buffer, `role` discriminates.
// ---------------------------------------------------------------------------
#define SC_BAY_0      0u
#define SC_BAYS      12u
#define SC_MASS_0    12u
#define SC_MASSES    10u
#define SC_SKY       22u   // sun + sea geometry
#define SC_HEADER    23u   // editor header: signature, selection, drag, travel, live counts
#define SC_RECORDS   24u

#define ROLE_BAY    0.0
#define ROLE_MASS   1.0
#define ROLE_SKY    2.0
#define ROLE_HEADER 3.0

#define F_SELECTED 1u
#define F_EDITED   2u

// One bay every SC_BAY_Z; SC_BAYS of them close the loop.
#define SC_BAY_Z    2.0
#define SC_LOOP_Z  24.0

// Neutral corridor, used by any bay switched off. Deactivating a bay straightens it back to
// this rather than deleting it, so X is a reversible "flatten this station".
//
// TALLER THAN WIDE, on purpose. The reference's opening is a portrait rectangle, and with the
// eye riding just under the ceiling that is what puts two big side walls and a broad floor in
// frame with no ceiling plane at all. A landscape section renders a ceiling you cannot get
// rid of no matter where you put the eye.
#define SC_BASE_W   0.92
#define SC_BASE_H   1.15

// mass kinds — the organic vocabulary that breaks the grid
#define MK_SWELL   0   // round bulge pushing off the wall
#define MK_WAVE    1   // long fold running with the corridor, the reference's breaking wave
#define MK_DRUM    2   // wide shallow dome
#define MK_KNUCKLE 3   // two fused lobes
// MK_LENS wears the CHECKER instead of a solid tint, and drags the checker's coordinates
// radially in a neighbourhood — so the grid bends across the swell AND across the wall around
// it. That second half is the point: the reference's grid is distorted, not merely interrupted
// by an object sitting in front of it.
#define MK_LENS    4
#define MK_KINDS   5

#define SC_PALSETS 5

struct ScRec
{
    // BAY : centre offset (x, y) of the corridor at this station, world units
    // MASS: (z along the loop, perimeter parameter t in [0,1))
    // SKY : sun centre in aperture units (-1..1)
    float2 pos;
    // BAY : aperture half-extent (w, h)
    // MASS: (radius, elongation along z)
    // SKY : (sun radius, small-sun radius) in aperture units
    float2 size;
    float  role;
    // BAY : palette set index   MASS: mass kind   SKY: stripe count
    float  kind;
    float  seed;
    // BAY : accent density of the checker   MASS: surface sheen   SKY: horizon height (-1..1)
    float  tone;
    // BAY : roll in radians   MASS: squash   SKY: small-sun offset x
    float  grp;
    // BAY : checker scale multiplier   MASS: bulge softness   SKY: small-sun offset y
    float  phase;
    float  flags;
    float  active;
};

// ---------------------------------------------------------------------------
// Hashes. Prefixed so they can never collide with the injected `noise` feature.
// ---------------------------------------------------------------------------
float sc_rnd(float s, float k)
{
    return frac(sin(s * 12.9898 + k * 78.233) * 43758.5453);
}
float2 sc_hash22(float2 p)
{
    float3 q = float3(dot(p, float2(127.1, 311.7)), dot(p, float2(269.5, 183.3)), dot(p, float2(419.2, 371.9)));
    return frac(sin(q.xy) * 43758.5453);
}

// ---------------------------------------------------------------------------
// Palette, transcribed off the reference and then extended into four alternates so a bay
// can carry a different chord without leaving the family.
// set 0 is the reference: hot magenta / white / vermilion / pale pink.
// ---------------------------------------------------------------------------
static const float3 SC_PAL[SC_PALSETS * 4] = {
    // 0 Sunset Deck — the reference
    float3(0.976, 0.086, 0.545), float3(0.957, 0.945, 0.953),
    float3(0.898, 0.243, 0.043), float3(0.949, 0.827, 0.855),
    // 1 Ember — the same room after dark
    float3(0.639, 0.055, 0.208), float3(0.965, 0.878, 0.792),
    float3(0.918, 0.376, 0.063), float3(0.400, 0.043, 0.180),
    // 2 Sherbet — lighter, more air
    float3(0.980, 0.475, 0.663), float3(0.988, 0.973, 0.937),
    float3(0.996, 0.780, 0.220), float3(0.976, 0.588, 0.404),
    // 3 Ink — hard graphic contrast
    float3(0.933, 0.055, 0.478), float3(0.086, 0.075, 0.098),
    float3(0.965, 0.957, 0.945), float3(0.878, 0.271, 0.075),
    // 4 Chalk — bleached, the grid nearly dissolving
    float3(0.925, 0.780, 0.812), float3(0.976, 0.969, 0.965),
    float3(0.851, 0.663, 0.639), float3(0.965, 0.373, 0.573)
};
float3 sc_pal(int set, int idx)
{
    int s = (int)clamp((float)set, 0.0, (float)(SC_PALSETS - 1));
    int i = (int)clamp((float)idx, 0.0, 3.0);
    return SC_PAL[s * 4 + i];
}

// sun / sky chord. Fixed: the sun is the one thing in the frame that is not negotiable.
#define SC_SUN_TOP  float3(1.000, 0.925, 0.075)
#define SC_SUN_MID  float3(0.988, 0.545, 0.055)
#define SC_SUN_LOW  float3(0.910, 0.086, 0.106)
#define SC_SKY_LOW  float3(0.996, 0.129, 0.588)
#define SC_SKY_TOP  float3(0.976, 0.318, 0.114)
#define SC_SEA_LT   float3(0.976, 0.961, 0.949)
#define SC_SEA_MD   float3(0.976, 0.451, 0.157)
#define SC_SEA_DK   float3(0.949, 0.157, 0.478)

// ---------------------------------------------------------------------------
// Shape vocabulary. Defined here with an sc_ prefix so the renderer compiles with
// `features: [camera]` alone and no injected signature can drift under us.
// ---------------------------------------------------------------------------
float sc_smin(float a, float b, float k)
{
    if (k <= 1e-5) return min(a, b);
    float h = saturate(0.5 + 0.5 * (b - a) / k);
    return lerp(b, a, h) - k * h * (1.0 - h);
}
// Iterated smooth-min inflates a phantom shell around a fused group. Clamping to
// (plain min - k) pins the fused surface back onto the real geometry.
float sc_fuse(float a, float b, float k) { return max(sc_smin(a, b, k), min(a, b) - k); }

float2 sc_rot2(float2 p, float a)
{
    float s = sin(a), c = cos(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float sc_box2(float2 p, float2 b)
{
    float2 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}
float sc_roundBox2(float2 p, float2 b, float r)
{
    return sc_box2(p, max(b - r, 0.001)) - r;
}

float sc_ellipsoid(float3 p, float3 r)
{
    float k0 = length(p / r);
    float k1 = length(p / (r * r));
    return k0 * (k0 - 1.0) / max(k1, 1e-6);
}
float sc_sphere(float3 p, float r) { return length(p) - r; }

float sc_capsule(float3 p, float3 a, float3 b, float r)
{
    float3 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / dot(ba, ba));
    return length(pa - ba * h) - r;
}

// ---------------------------------------------------------------------------
// Corridor profile. Shared verbatim by the plan canvas and the renderer so the schematic
// and the image can never disagree about where a wall is.
// ---------------------------------------------------------------------------
struct ScProfile
{
    float2 c;      // centre offset
    float2 h;      // aperture half-extent
    float  roll;
    float  chk;    // checker scale multiplier
    float  accent; // accent-cell density
    int    pal;    // palette set (discrete: nearest station, never interpolated)
};

float sc_cr(float p0, float p1, float p2, float p3, float t)
{
    float t2 = t * t, t3 = t2 * t;
    return 0.5 * ((2.0 * p1) + (-p0 + p2) * t
                + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
                + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3);
}
float2 sc_cr2(float2 p0, float2 p1, float2 p2, float2 p3, float t)
{
    return float2(sc_cr(p0.x, p1.x, p2.x, p3.x, t), sc_cr(p0.y, p1.y, p2.y, p3.y, t));
}

uint sc_wrapBay(int i)
{
    int n = (int)SC_BAYS;
    return (uint)(((i % n) + n) % n);
}

// A bay's contribution after the on/off switch: inactive stations collapse to the neutral
// straight corridor instead of vanishing, which is what makes X reversible.
void sc_bayValues(ScRec r, out float2 c, out float2 h, out float roll, out float chk, out float acc)
{
    bool on = r.active > 0.5;
    c    = on ? r.pos  : float2(0.0, 0.0);
    h    = on ? r.size : float2(SC_BASE_W, SC_BASE_H);
    roll = on ? r.grp  : 0.0;
    chk  = on ? r.phase : 1.0;
    acc  = on ? r.tone  : 0.18;
}

// Continuous bay coordinate for a world z, plus the four control indices around it.
void sc_bayFrame(float zw, out int i0, out int i1, out int i2, out int i3, out float t)
{
    float u = zw / SC_BAY_Z;
    float fi = floor(u);
    t = u - fi;
    int b = (int)fi;
    i0 = (int)sc_wrapBay(b - 1);
    i1 = (int)sc_wrapBay(b);
    i2 = (int)sc_wrapBay(b + 1);
    i3 = (int)sc_wrapBay(b + 2);
}

// Catmull-Rom through the four stations. Discrete fields (palette) take the nearest station,
// because interpolating an index produces a colour that belongs to nobody.
// `bend` and `flare` are STRUCTURAL generation parameters over in SC_Plan, already baked into
// the records — there is deliberately no live multiplier here. A global scale applied on top
// of the records would be a second authority for the same number, and the handles in the plan
// view would stop sitting on the wall they claim to control.
ScProfile sc_profileFrom(ScRec b0, ScRec b1, ScRec b2, ScRec b3, float t)
{
    float2 c0, c1, c2, c3, h0, h1, h2, h3;
    float r0, r1, r2, r3, k0, k1, k2, k3, a0, a1, a2, a3;
    sc_bayValues(b0, c0, h0, r0, k0, a0);
    sc_bayValues(b1, c1, h1, r1, k1, a1);
    sc_bayValues(b2, c2, h2, r2, k2, a2);
    sc_bayValues(b3, c3, h3, r3, k3, a3);

    ScProfile p;
    p.c    = sc_cr2(c0, c1, c2, c3, t);
    p.h    = max(sc_cr2(h0, h1, h2, h3, t), float2(0.28, 0.22));
    p.roll = sc_cr(r0, r1, r2, r3, t);
    p.chk  = max(sc_cr(k0, k1, k2, k3, t), 0.25);
    p.accent = saturate(sc_cr(a0, a1, a2, a3, t));
    p.pal  = (int)((t < 0.5) ? b1.kind : b2.kind);
    return p;
}

// Point on the aperture rectangle's boundary in direction theta. Continuous in theta and
// exactly on the rect, which is what lets a mass slide around a square tunnel smoothly.
float2 sc_perimeter(float2 h, float theta)
{
    float2 d = float2(cos(theta), sin(theta));
    float k = 1.0 / max(max(abs(d.x) / max(h.x, 1e-4), abs(d.y) / max(h.y, 1e-4)), 1e-4);
    return d * k;
}

// Shortest signed z separation on the loop. Everything in the corridor is periodic, so a
// mass near the seam has to be reachable from both sides or it pops at the wrap.
float sc_wrapDZ(float dz)
{
    return dz - SC_LOOP_Z * floor(dz / SC_LOOP_Z + 0.5);
}
float sc_wrapZ(float z)
{
    return z - SC_LOOP_Z * floor(z / SC_LOOP_Z);
}

// ---------------------------------------------------------------------------
// The sky plate. One definition, used by the renderer for the real image and by the plan
// canvas for its inset, so the schematic sun is the actual sun.
// `s` is aperture space: (0,0) is the sun record's own centre reference, +y up, roughly
// -1..1 across the visible opening.
// ---------------------------------------------------------------------------
float3 sc_skyPlate(float2 s, ScRec sky, float px)
{
    float2 sunC   = sky.pos;
    float  sunR   = max(sky.size.x, 0.02);
    float  smallR = max(sky.size.y, 0.005);
    float  horizon = sky.tone;
    float  stripes = max(sky.kind, 2.0);
    float2 smallO  = float2(sky.grp, sky.phase);

    // Sky: magenta low, scorched orange at the top. The curve is biased hard so magenta HOLDS
    // across most of the opening and the orange arrives only at the very top — a linear ramp
    // spends the whole visible range in the salmon midpoint, which is the one colour the
    // reference does not contain.
    float3 col = lerp(SC_SKY_LOW, SC_SKY_TOP, pow(saturate(s.y * 0.5 + 0.5), 4.0));

    // the disc, with its own vertical gradient. Yellow crown, orange belly, red base.
    float2 q = (s - sunC) / sunR;
    float d = length(q);
    float g = saturate(q.y * 0.5 + 0.5);
    float3 sun = (g > 0.52) ? lerp(SC_SUN_MID, SC_SUN_TOP, saturate((g - 0.52) / 0.48))
                            : lerp(SC_SUN_LOW, SC_SUN_MID, saturate(g / 0.52));
    float sunCov = 1.0 - smoothstep(1.0 - px / sunR, 1.0 + px / sunR, d);
    col = lerp(col, sun, sunCov);

    // the small pale sun sitting on the disc
    float2 q2 = (s - sunC - smallO) / smallR;
    float d2 = length(q2);
    float3 sm = lerp(float3(1.0, 0.98, 0.80), SC_SUN_TOP, saturate(q2.y * 0.5 + 0.5));
    col = lerp(col, sm, 1.0 - smoothstep(1.0 - px / smallR, 1.0 + px / smallR, d2));

    // the striped sea. It cuts the sun's base flat, which is the single detail that makes
    // the disc read as a SUN SETTING rather than as a circle pasted on a wall.
    float below = 1.0 - smoothstep(horizon - px, horizon + px, s.y);
    if (below > 0.001)
    {
        float band = (horizon - s.y) * stripes;
        float fb = frac(band);
        float row = floor(band);
        float sel = sc_rnd(row, 3.7);
        float3 a = (sel < 0.42) ? SC_SEA_LT : ((sel < 0.78) ? SC_SEA_MD : SC_SEA_DK);
        float3 b = (sel < 0.42) ? SC_SEA_MD : SC_SEA_LT;
        // bands thin out toward the horizon: a perspective cue for free
        float duty = lerp(0.34, 0.62, saturate(row / max(stripes * 0.9, 1.0)));
        float3 sea = (fb < duty) ? a : b;
        col = lerp(col, sea, below);
    }
    return col;
}

// ---------------------------------------------------------------------------
// Checker material. Two-colour parity with scattered accent cells — the reference is not a
// clean checkerboard, it is a checkerboard with vermilion tiles thrown into it.
// ---------------------------------------------------------------------------
float3 sc_checker(float2 cell, int pal, float accent, float seedK)
{
    float2 fc = floor(cell);
    float parity = fmod(abs(fc.x + fc.y), 2.0);
    float3 base = (parity < 0.5) ? sc_pal(pal, 0) : sc_pal(pal, 1);
    float h = sc_rnd(fc.x * 3.71 + fc.y * 7.13 + seedK, 11.0);
    if (h < accent * 0.55)          base = sc_pal(pal, 2);
    else if (h < accent)            base = sc_pal(pal, 3);
    return base;
}

// ---------------------------------------------------------------------------
// Editor helpers shared by plan.hlsl and canvas.hlsl so pick and draw cannot disagree.
// The plan diagram is TWO stacked orthographic strips: a plan (lateral) over an elevation
// (vertical), sharing one z axis. Everything is normalized uv, origin top-left, +y down.
// ---------------------------------------------------------------------------
#define SC_DIAG_X0   0.055
#define SC_DIAG_X1   0.760
#define SC_PLAN_CY   0.270   // centreline of the plan strip
#define SC_ELEV_CY   0.720   // centreline of the elevation strip
#define SC_STRIP_H   0.185   // half-height of a strip in uv
#define SC_WORLD_H   1.90    // world half-extent mapped onto SC_STRIP_H
#define SC_INSET_X0  0.795
#define SC_INSET_X1  0.975
#define SC_INSET_Y0  0.330
#define SC_INSET_Y1  0.670

float sc_zToX(float z)   { return SC_DIAG_X0 + (z / SC_LOOP_Z) * (SC_DIAG_X1 - SC_DIAG_X0); }
float sc_xToZ(float x)   { return (x - SC_DIAG_X0) / max(SC_DIAG_X1 - SC_DIAG_X0, 1e-4) * SC_LOOP_Z; }
// world offset -> uv y within a strip. +world up is -uv y.
float sc_wToY(float w, float cy) { return cy - (w / SC_WORLD_H) * SC_STRIP_H; }
float sc_yToW(float y, float cy) { return (cy - y) / SC_STRIP_H * SC_WORLD_H; }

// Which strip a uv point belongs to. 1 = plan, 2 = elevation, 3 = sun inset, 0 = nowhere.
int sc_stripAt(float2 uv)
{
    if (uv.x > SC_INSET_X0 - 0.02 && uv.x < SC_INSET_X1 + 0.02 &&
        uv.y > SC_INSET_Y0 - 0.02 && uv.y < SC_INSET_Y1 + 0.02) return 3;
    if (abs(uv.y - SC_PLAN_CY) < SC_STRIP_H + 0.055) return 1;
    if (abs(uv.y - SC_ELEV_CY) < SC_STRIP_H + 0.055) return 2;
    return 0;
}

// A mass's cross-section point at its own station, in world units. Both the canvas and the
// pick test route through this, so a handle is always drawn where it can be grabbed.
float2 sc_massSection(ScRec m, float2 h)
{
    return sc_perimeter(h, m.pos.y * 6.2831853);
}

#endif // SC_CORRIDOR_HLSLI
