// br_shade.hlsli -- materials and BRDF shared by BR_Finish (the finish board) and BR_Render.
//
// One surface model for both nodes, so a sample chip on the board IS the material the room is
// shaded with, under the same lobes. A material is a record (colour, roughness, metal, sheen,
// clearcoat, pattern scale) plus a procedural PATTERN FAMILY evaluated in the surface's own
// pattern space: wood grows rings along its object axis, linen weaves at thread pitch, marble
// veins through a warped field. Patterns take a footprint (metres per pixel) and fade every
// frequency above Nyquist instead of shimmering.
//
// Colours are authored sRGB in the manifests and converted to linear here, once.
#ifndef BR_SHADE_HLSLI
#define BR_SHADE_HLSLI

#include "../_shared/br_records.hlsli"

#define BR_PI_S 3.14159265
#define BR_INV_PI 0.31830989

// ---------------------------------------------------------------------------------------------
// NOISE (self-contained so a module needs no `noise` feature and names never collide)
float brH1(float3 p)
{
    p = frac(p * float3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yzx + 33.33);
    return frac((p.x + p.y) * p.z);
}
float3 brH3(float3 p)
{
    p = frac(p * float3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return frac((p.xxy + p.yxx) * p.zyx);
}
float brH21(float2 p)
{
    float3 p3 = frac(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.x + p3.y) * p3.z);
}
float2 brH22(float2 p)
{
    float3 p3 = frac(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.xx + p3.yz) * p3.zy);
}

// value noise, C2 fade, range ~[-1,1]
float brVN3(float3 p)
{
    float3 i = floor(p), f = frac(p);
    float3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    float a = brH1(i), b = brH1(i + float3(1, 0, 0)), c = brH1(i + float3(0, 1, 0)), d = brH1(i + float3(1, 1, 0));
    float e = brH1(i + float3(0, 0, 1)), f1 = brH1(i + float3(1, 0, 1)), g = brH1(i + float3(0, 1, 1)), h = brH1(i + float3(1, 1, 1));
    float k0 = lerp(lerp(a, b, u.x), lerp(c, d, u.x), u.y);
    float k1 = lerp(lerp(e, f1, u.x), lerp(g, h, u.x), u.y);
    return lerp(k0, k1, u.z) * 2.0 - 1.0;
}
float brVN2(float2 p)
{
    float2 i = floor(p), f = frac(p);
    float2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    float a = brH21(i), b = brH21(i + float2(1, 0)), c = brH21(i + float2(0, 1)), d = brH21(i + float2(1, 1));
    return lerp(lerp(a, b, u.x), lerp(c, d, u.x), u.y) * 2.0 - 1.0;
}

// fbm with a per-octave Nyquist fade: `fp` is the footprint in the same units as p.
float brFbm3(float3 p, int oct, float fp)
{
    float s = 0.0, a = 0.5, f = 1.0;
    [loop] for (int i = 0; i < oct; i++)
    {
        float fade = saturate(1.5 - fp * f * 2.0);
        s += a * brVN3(p * f + float3(i * 17.1, i * 3.7, i * 9.3)) * fade;
        f *= 2.03; a *= 0.5;
    }
    return s;
}
float brFbm2(float2 p, int oct, float fp)
{
    float s = 0.0, a = 0.5, f = 1.0;
    [loop] for (int i = 0; i < oct; i++)
    {
        float fade = saturate(1.5 - fp * f * 2.0);
        s += a * brVN2(p * f + float2(i * 17.1, i * 9.3)) * fade;
        f *= 2.03; a *= 0.5;
    }
    return s;
}

// cellular: F1, F2 distances
float2 brCell2(float2 p)
{
    float2 i = floor(p), f = frac(p);
    float d1 = 8.0, d2 = 8.0;
    [unroll] for (int y = -1; y <= 1; y++)
    [unroll] for (int x = -1; x <= 1; x++)
    {
        float2 g = float2(x, y);
        float2 o = brH22(i + g);
        float d = length(g + o - f);
        if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) d2 = d;
    }
    return float2(d1, d2);
}

float3 brSrgbToLinear(float3 c) { return pow(max(c, 0.0), 2.2); }
float3 brLinearToSrgb(float3 c) { return pow(max(c, 0.0), 1.0 / 2.2); }
float brLuma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

// ---------------------------------------------------------------------------------------------
// MATERIAL RECORDS
//   head (role, slot, family, flags)
//   dims (base.rgb [linear], roughness)
//   look (second.rgb [linear], metallic)
//   meta (sheen, clearcoat, patternScale, transmission)
#define FAM_PAINT     0
#define FAM_WOOD      1
#define FAM_PARQUET   2
#define FAM_LINEN     3
#define FAM_LEATHER   4
#define FAM_VELVET    5
#define FAM_METAL     6
#define FAM_GLASS     7
#define FAM_GLAZE     8
#define FAM_MARBLE    9
#define FAM_WOOL      10
#define FAM_PAPER     11
#define FAM_LEAF      12
#define FAM_CLAY      13
#define FAM_SHADE     14
#define FAM_EMISSIVE  15
#define FAM_SHEER     16

struct BRMat
{
    int slot, family;
    float3 base, second;
    float rough, metal, sheen, coat, scale, trans;
};

BRMat brMatFromRec(BRRec r)
{
    BRMat m;
    m.slot = (int)round(r.head.y); m.family = (int)round(r.head.z);
    m.base = r.dims.rgb; m.rough = r.dims.w;
    m.second = r.look.rgb; m.metal = r.look.w;
    m.sheen = r.meta.x; m.coat = r.meta.y; m.scale = r.meta.z; m.trans = r.meta.w;
    return m;
}
BRRec brMatToRec(BRMat m)
{
    BRRec r;
    r.head = float4(ROLE_MAT, m.slot, m.family, 0);
    r.dims = float4(m.base, m.rough);
    r.look = float4(m.second, m.metal);
    r.meta = float4(m.sheen, m.coat, m.scale, m.trans);
    return r;
}

BRMat brMakeMat(int slot, int fam, float3 baseSrgb, float rough, float3 secondSrgb, float metal, float sheen, float coat, float scale, float trans)
{
    BRMat m;
    m.slot = slot; m.family = fam;
    m.base = brSrgbToLinear(baseSrgb); m.second = brSrgbToLinear(secondSrgb);
    m.rough = rough; m.metal = metal; m.sheen = sheen; m.coat = coat; m.scale = scale; m.trans = trans;
    return m;
}

// The house defaults: a warm, lived-in pre-war room. BR_Finish's manifest defaults match these
// and the renderer falls back to them when its Finish input is unlinked.
BRMat brDefaultMat(int slot)
{
    if (slot == MAT_FLOOR)      return brMakeMat(slot, FAM_PARQUET, float3(0.64, 0.43, 0.25), 0.32, float3(0.40, 0.24, 0.12), 0.0, 0.0, 0.85, 1.0, 0.0);
    if (slot == MAT_WALL)       return brMakeMat(slot, FAM_PAINT,   float3(0.86, 0.81, 0.72), 0.88, float3(0.80, 0.74, 0.64), 0.0, 0.0, 0.0, 1.0, 0.0);
    if (slot == MAT_CEILING)    return brMakeMat(slot, FAM_PAINT,   float3(0.90, 0.88, 0.83), 0.92, float3(0.86, 0.84, 0.78), 0.0, 0.0, 0.0, 1.0, 0.0);
    if (slot == MAT_TRIM)       return brMakeMat(slot, FAM_PAINT,   float3(0.90, 0.88, 0.82), 0.38, float3(0.86, 0.84, 0.78), 0.0, 0.0, 0.0, 0.4, 0.0);
    if (slot == MAT_WINDOW)     return brMakeMat(slot, FAM_PAINT,   float3(0.88, 0.86, 0.80), 0.40, float3(0.84, 0.82, 0.76), 0.0, 0.0, 0.0, 0.4, 0.0);
    if (slot == MAT_GLASS)      return brMakeMat(slot, FAM_GLASS,   float3(0.95, 0.97, 0.96), 0.02, float3(0.90, 0.95, 0.93), 0.0, 0.0, 0.0, 1.0, 0.94);
    if (slot == MAT_DOOR)       return brMakeMat(slot, FAM_PAINT,   float3(0.88, 0.86, 0.80), 0.40, float3(0.84, 0.82, 0.76), 0.0, 0.0, 0.0, 0.4, 0.0);
    if (slot == MAT_STONE)      return brMakeMat(slot, FAM_MARBLE,  float3(0.88, 0.87, 0.84), 0.12, float3(0.46, 0.45, 0.44), 0.0, 0.0, 0.0, 1.0, 0.0);
    if (slot == MAT_IRON)       return brMakeMat(slot, FAM_PAINT,   float3(0.82, 0.79, 0.72), 0.55, float3(0.70, 0.66, 0.58), 0.0, 0.0, 0.0, 0.6, 0.0);
    if (slot == MAT_SHEER)      return brMakeMat(slot, FAM_SHEER,   float3(0.95, 0.92, 0.86), 0.90, float3(0.90, 0.86, 0.80), 0.0, 0.35, 0.0, 1.0, 0.62);
    if (slot == MAT_LINEN)      return brMakeMat(slot, FAM_LINEN,   float3(0.74, 0.67, 0.57), 0.86, float3(0.62, 0.55, 0.45), 0.0, 0.55, 0.0, 1.0, 0.0);
    if (slot == MAT_LEATHER)    return brMakeMat(slot, FAM_LEATHER, float3(0.56, 0.29, 0.14), 0.42, float3(0.30, 0.13, 0.05), 0.0, 0.15, 0.25, 1.0, 0.0);
    if (slot == MAT_WALNUT)     return brMakeMat(slot, FAM_WOOD,    float3(0.42, 0.27, 0.17), 0.42, float3(0.20, 0.11, 0.06), 0.0, 0.0, 0.45, 1.0, 0.0);
    if (slot == MAT_BRASS)      return brMakeMat(slot, FAM_METAL,   float3(0.95, 0.78, 0.48), 0.28, float3(0.55, 0.42, 0.22), 1.0, 0.0, 0.0, 1.0, 0.0);
    if (slot == MAT_CERAMIC)    return brMakeMat(slot, FAM_GLAZE,   float3(0.46, 0.50, 0.30), 0.14, float3(0.30, 0.34, 0.18), 0.0, 0.0, 0.0, 1.0, 0.0);
    if (slot == MAT_RUG)        return brMakeMat(slot, FAM_WOOL,    float3(0.56, 0.13, 0.10), 0.95, float3(0.10, 0.13, 0.28), 0.0, 0.45, 0.0, 1.0, 0.0);
    if (slot == MAT_VELVET)     return brMakeMat(slot, FAM_VELVET,  float3(0.66, 0.30, 0.17), 0.70, float3(0.42, 0.16, 0.08), 0.0, 1.00, 0.0, 1.0, 0.0);
    if (slot == MAT_PAPER)      return brMakeMat(slot, FAM_PAPER,   float3(0.88, 0.85, 0.78), 0.80, float3(0.50, 0.30, 0.22), 0.0, 0.0, 0.0, 1.0, 0.0);
    if (slot == MAT_LEAF)       return brMakeMat(slot, FAM_LEAF,    float3(0.25, 0.40, 0.16), 0.45, float3(0.42, 0.55, 0.20), 0.0, 0.0, 0.0, 1.0, 0.35);
    if (slot == MAT_TERRACOTTA) return brMakeMat(slot, FAM_CLAY,    float3(0.74, 0.42, 0.27), 0.82, float3(0.60, 0.33, 0.21), 0.0, 0.0, 0.0, 1.0, 0.0);
    if (slot == MAT_SHADE)      return brMakeMat(slot, FAM_SHADE,   float3(0.95, 0.89, 0.78), 0.85, float3(0.90, 0.82, 0.68), 0.0, 0.3, 0.0, 1.0, 0.55);
    if (slot == MAT_BULB)       return brMakeMat(slot, FAM_EMISSIVE,float3(1.00, 0.86, 0.66), 0.20, float3(1.00, 0.80, 0.55), 0.0, 0.0, 0.0, 1.0, 0.0);
    if (slot == MAT_BLACKMETAL) return brMakeMat(slot, FAM_METAL,   float3(0.10, 0.10, 0.10), 0.42, float3(0.05, 0.05, 0.05), 0.85, 0.0, 0.0, 1.0, 0.0);
    if (slot == MAT_MARBLE)     return brMakeMat(slot, FAM_MARBLE,  float3(0.82, 0.74, 0.62), 0.20, float3(0.60, 0.50, 0.38), 0.0, 0.0, 0.0, 1.6, 0.0);
    return brMakeMat(slot, FAM_PAINT, float3(0.7, 0.7, 0.7), 0.8, float3(0.6, 0.6, 0.6), 0.0, 0.0, 0.0, 1.0, 0.0);
}

// ---------------------------------------------------------------------------------------------
// SURFACE: what a pattern produces for the BRDF.
struct BRSurf
{
    float3 albedo;
    float rough;
    float metal;
    float3 f0;
    float sheen;
    float3 sheenTint;
    float coat;
    float coatRough;
    float3 bump;        // tangent-space-free normal offset in world space (added then renormalised)
    float trans;        // diffuse transmission share (sheers, shades, leaves)
    float3 emit;
    float cavity;       // 0..1 micro-occlusion from the pattern (grooves, weave gaps)
};

BRSurf brSurfDefault(BRMat m)
{
    BRSurf s;
    s.albedo = m.base; s.rough = m.rough; s.metal = m.metal;
    s.f0 = lerp(float3(0.04, 0.04, 0.04), m.base, m.metal);
    s.sheen = m.sheen; s.sheenTint = lerp(float3(1, 1, 1), m.base / max(brLuma(m.base), 1e-3), 0.5);
    s.coat = m.coat; s.coatRough = 0.06;
    s.bump = 0; s.trans = m.trans; s.emit = 0; s.cavity = 1.0;
    return s;
}

// Context a pattern needs. `p` is the PATTERN-SPACE position (object-local for furniture, rest
// world for architecture -- the trip layer may already have flowed it). `n` is the shading
// normal in world space, `axis` a world direction the pattern runs along (grain, warp threads),
// `fp` the pixel footprint in metres, `seed` a per-part variant (book colour, slat tone).
struct BRPatternIn
{
    float3 p;
    float3 n;
    float3 axis;
    float fp;
    float seed;
    float edge;     // distance to a construction edge (parquet groove), metres; 1 if none
};

float3 brTangentFrom(float3 n, float3 axis)
{
    float3 t = axis - n * dot(axis, n);
    float l = length(t);
    if (l < 1e-3) { t = abs(n.y) < 0.9 ? cross(n, float3(0, 1, 0)) : cross(n, float3(1, 0, 0)); l = length(t); }
    return t / l;
}

// Bump from a scalar height field sampled by the caller at p, p+du, p+dv (cheap finite difference
// in pattern space). Returns a world-space normal offset.
float3 brBumpFrom(float h0, float hu, float hv, float3 t, float3 b, float eps, float amount)
{
    return -(t * (hu - h0) + b * (hv - h0)) / max(eps, 1e-6) * amount;
}

// ---- families -------------------------------------------------------------------------------

float brWoodRings(float3 q, float fp, float seed)
{
    // q: x along the grain, y/z across. A virtual log axis offset per piece makes the rings
    // read as flat-sawn cathedrals on a wide face and as straight stripes on an edge.
    float2 off = float2(0.35 + seed * 0.4, -0.6 - seed * 0.3);
    float3 w = float3(q.x * 0.6, q.y, q.z);
    float wob = brFbm3(w * float3(0.8, 3.0, 3.0) + seed * 7.0, 3, fp * 3.0) * 0.08;
    float r = length(q.yz + off + wob) * 34.0;
    float ring = frac(r);
    float early = smoothstep(0.0, 0.55, ring) * (1.0 - smoothstep(0.75, 1.0, ring));
    float fade = saturate(1.4 - fp * 34.0 * 2.0);
    return lerp(0.45, early, fade);
}

BRSurf brWood(BRMat m, BRPatternIn pin, bool parquet)
{
    BRSurf s = brSurfDefault(m);
    float3 t = brTangentFrom(pin.n, pin.axis);
    float3 b = cross(pin.n, t);
    float3 q = float3(dot(pin.p, t), dot(pin.p, b), dot(pin.p, pin.n)) / max(m.scale, 0.2);
    float seed = pin.seed;
    float rings = brWoodRings(q, pin.fp / max(m.scale, 0.2), frac(seed * 13.7));
    // pores: long thin streaks along the grain
    float poreFade = saturate(1.4 - pin.fp * 260.0);
    float pores = brVN3(q * float3(6.0, 260.0, 260.0) + seed * 31.0) * 0.5 + 0.5;
    pores = smoothstep(0.62, 0.95, pores) * poreFade;
    // figure: slow tonal drift along the piece
    float figure = brFbm3(q * float3(1.5, 9.0, 9.0) + seed * 5.0, 3, pin.fp * 9.0);
    float3 c = lerp(m.second, m.base, saturate(0.35 + rings * 0.55 + figure * 0.35));
    c *= 1.0 - pores * 0.28;
    // per-piece tone: real boards never match
    float tone = (frac(seed * 91.37) - 0.5);
    c *= 1.0 + tone * 0.22;
    c = lerp(c, c * float3(1.05, 0.98, 0.92), saturate(frac(seed * 17.3) - 0.4));
    s.albedo = c;
    s.rough = saturate(m.rough + pores * 0.12 - rings * 0.05);
    // grain bump: pores sink, latewood rises a hair
    s.bump = b * (brVN3(q * float3(6.0, 260.0, 260.0) + seed * 31.0 + float3(0, 0.01, 0)) - brVN3(q * float3(6.0, 260.0, 260.0) + seed * 31.0)) * 0.6 * poreFade;
    if (parquet)
    {
        // grooves between slats: dark, slightly rough, occluded; a micro-bevel tilts the normal
        float groove = 1.0 - smoothstep(0.0006, 0.0022 + pin.fp * 0.7, pin.edge);
        s.albedo *= 1.0 - groove * 0.65;
        s.cavity = 1.0 - groove * 0.8;
        s.rough = lerp(s.rough, 0.85, groove);
        s.coat *= 1.0 - groove;
        // gentle wear: the varnish is a little duller in a wandering path
        float wear = smoothstep(0.2, 0.8, brFbm2(pin.p.xz * 0.6, 3, pin.fp * 0.6) * 0.5 + 0.5);
        s.coatRough = lerp(0.11, 0.24, wear);
    }
    return s;
}

BRSurf brPaint(BRMat m, BRPatternIn pin)
{
    BRSurf s = brSurfDefault(m);
    // roller stipple (orange peel) and very low frequency mottling of a hand-painted wall
    float mott = brFbm3(pin.p * 0.9, 3, pin.fp * 0.9);
    s.albedo = m.base * (1.0 + mott * 0.035);
    float stipFade = saturate(1.4 - pin.fp * 180.0 / max(m.scale, 0.2));     // the stipple's real frequency
    float3 t = brTangentFrom(pin.n, float3(0, 1, 0));
    float3 b = cross(pin.n, t);
    float3 sp = pin.p * 180.0 / max(m.scale, 0.2);
    float h0 = brVN3(sp), hu = brVN3(sp + t * 0.35), hv = brVN3(sp + b * 0.35);
    s.bump = brBumpFrom(h0, hu, hv, t, b, 0.35, 0.010 * stipFade);
    s.rough = saturate(m.rough + h0 * 0.03);
    return s;
}

BRSurf brLinen(BRMat m, BRPatternIn pin)
{
    BRSurf s = brSurfDefault(m);
    float3 t = brTangentFrom(pin.n, pin.axis);
    float3 b = cross(pin.n, t);
    float2 uv = float2(dot(pin.p, t), dot(pin.p, b)) / max(m.scale, 0.2);
    float pitch = 0.0011;                                   // ~1.1 mm threads
    float fade = saturate(1.6 - pin.fp / pitch * 0.55);
    float2 g = uv / pitch;
    float wx = sin(g.x * 3.14159), wy = sin(g.y * 3.14159);
    float over = step(0.0, sin(floor(g.x) * 1.5708 + floor(g.y) * 1.5708 + 0.7));
    float weave = lerp(abs(wy), abs(wx), over);
    // slubs: thick irregular threads, the thing that makes linen read as linen
    float slub = smoothstep(0.55, 1.0, brVN2(float2(uv.x * 9.0, uv.y * 900.0)) * 0.5 + 0.5) * 0.6
               + smoothstep(0.6, 1.0, brVN2(float2(uv.x * 900.0, uv.y * 9.0)) * 0.5 + 0.5) * 0.4;
    float mott = brFbm2(uv * 7.0, 3, pin.fp * 7.0);
    float tone = 1.0 + (weave - 0.6) * 0.20 * fade - slub * 0.10 * saturate(1.4 - pin.fp * 600.0) + mott * 0.05;
    s.albedo = lerp(m.second, m.base, saturate(0.80 + (weave - 0.5) * 0.4 * fade)) * tone;
    s.cavity = 1.0 - (1.0 - weave) * 0.25 * fade;
    s.bump = (t * cos(g.x * 3.14159) * over + b * cos(g.y * 3.14159) * (1.0 - over)) * 0.12 * fade;
    return s;
}

BRSurf brLeather(BRMat m, BRPatternIn pin)
{
    BRSurf s = brSurfDefault(m);
    float3 t = brTangentFrom(pin.n, pin.axis);
    float3 b = cross(pin.n, t);
    float2 uv = float2(dot(pin.p, t), dot(pin.p, b)) / max(m.scale, 0.2);
    float fade = saturate(1.6 - pin.fp * 380.0);
    float2 c = brCell2(uv * 380.0);
    float crease = 1.0 - smoothstep(0.0, 0.18, c.y - c.x);
    float wrinkle = brFbm2(uv * float2(14.0, 30.0), 4, pin.fp * 30.0);
    float patina = smoothstep(-0.2, 0.6, brFbm2(uv * 3.0 + 4.0, 3, pin.fp * 3.0));
    s.albedo = lerp(m.base, m.second, saturate(crease * 0.45 * fade + (1.0 - patina) * 0.35));
    s.albedo *= 1.0 + wrinkle * 0.08;
    s.rough = saturate(m.rough + crease * 0.20 * fade - patina * 0.12);
    s.cavity = 1.0 - crease * 0.3 * fade;
    float2 cu = brCell2(uv * 380.0 + float2(0.02, 0));
    float2 cv = brCell2(uv * 380.0 + float2(0, 0.02));
    float h0 = c.y - c.x, hu = cu.y - cu.x, hv = cv.y - cv.x;
    s.bump = brBumpFrom(h0, hu, hv, t, b, 0.02, 0.012 * fade) + (t * wrinkle) * 0.05;
    return s;
}

BRSurf brVelvet(BRMat m, BRPatternIn pin)
{
    BRSurf s = brSurfDefault(m);
    // crushed nap: patches where the pile lies a different way read lighter/darker
    float nap = brFbm3(pin.p * 9.0 / max(m.scale, 0.2), 4, pin.fp * 9.0);
    s.albedo = lerp(m.second, m.base, saturate(0.65 + nap * 0.5));
    s.sheen = m.sheen * (0.75 + nap * 0.5);
    s.sheenTint = normalize(m.base + 0.05) * 1.6;
    return s;
}

BRSurf brMetal(BRMat m, BRPatternIn pin)
{
    BRSurf s = brSurfDefault(m);
    float tarnish = smoothstep(0.1, 0.8, brFbm3(pin.p * 4.0, 4, pin.fp * 4.0) * 0.5 + 0.5);
    float3 t = brTangentFrom(pin.n, pin.axis);
    float brush = brVN3(float3(dot(pin.p, t) * 30.0, dot(pin.p, cross(pin.n, t)) * 900.0, 0.0)) * saturate(1.4 - pin.fp * 900.0);
    s.albedo = lerp(m.base, m.second, tarnish * 0.45);
    s.f0 = lerp(float3(0.04, 0.04, 0.04), s.albedo, m.metal);
    s.rough = saturate(m.rough + tarnish * 0.18 + brush * 0.04);
    return s;
}

BRSurf brGlaze(BRMat m, BRPatternIn pin)
{
    BRSurf s = brSurfDefault(m);
    // glaze pools darker in low spots and breaks lighter on edges: drive with slow noise
    float pool = brFbm3(pin.p * 14.0, 4, pin.fp * 14.0);
    s.albedo = lerp(m.second, m.base, saturate(0.6 + pool * 0.6));
    s.rough = saturate(m.rough + max(pool, 0.0) * 0.05);
    float crazing = 1.0 - smoothstep(0.0, 0.03, brCell2(pin.p.xy * 60.0 + pin.p.z * 30.0).y - brCell2(pin.p.xy * 60.0 + pin.p.z * 30.0).x);
    s.albedo *= 1.0 - crazing * 0.08 * saturate(1.4 - pin.fp * 120.0);
    return s;
}

BRSurf brMarble(BRMat m, BRPatternIn pin)
{
    BRSurf s = brSurfDefault(m);
    // veins every ~25-35 cm on a mantel; finer fractures at a third of that
    float3 q = pin.p * 6.5 / max(m.scale, 0.2);
    float warp = brFbm3(q * 1.3, 5, pin.fp * 1.3 * 1.4);
    float vein = abs(sin((q.x + q.y * 0.6 + warp * 2.6) * 3.1));
    float veinFine = abs(sin((q.y - q.z * 0.8 + warp * 4.5) * 9.0));
    float v = 1.0 - smoothstep(0.0, 0.10, vein);
    float vf = (1.0 - smoothstep(0.0, 0.05, veinFine)) * saturate(1.3 - pin.fp * 40.0);
    float cloud = brFbm3(q * 3.0, 4, pin.fp * 4.2);
    s.albedo = lerp(m.base * (1.0 + cloud * 0.06), m.second, saturate(v * 0.85 + vf * 0.35));
    s.rough = saturate(m.rough + v * 0.04);
    return s;
}

BRSurf brWool(BRMat m, BRPatternIn pin, float3 rugColour, bool haveRug)
{
    BRSurf s = brSurfDefault(m);
    float fade = saturate(1.6 - pin.fp * 500.0);
    float fiber = brVN3(pin.p * 500.0) * 0.5 + 0.5;
    float tuft = brVN3(pin.p * 140.0) * 0.5 + 0.5;
    float3 c = haveRug ? rugColour : m.base;
    s.albedo = c * (0.88 + (fiber * 0.12 + tuft * 0.10) * fade);
    s.cavity = 0.82 + tuft * 0.18 * fade;
    s.sheen = m.sheen;
    s.sheenTint = lerp(float3(1, 1, 1), c / max(brLuma(c), 1e-3), 0.6);
    return s;
}

BRSurf brPaper(BRMat m, BRPatternIn pin)
{
    BRSurf s = brSurfDefault(m);
    // seed-driven colour for book spines: a library of muted bindings
    float h = frac(pin.seed * 7.31);
    float3 bind[6] = { float3(0.36, 0.10, 0.08), float3(0.12, 0.18, 0.30), float3(0.20, 0.27, 0.16),
                       float3(0.70, 0.62, 0.48), float3(0.42, 0.30, 0.18), float3(0.10, 0.10, 0.11) };
    int bi = (int)floor(h * 6.0);
    float3 spine = brSrgbToLinear(bind[clamp(bi, 0, 5)] * (0.85 + frac(pin.seed * 3.1) * 0.3));
    s.albedo = (pin.seed > 0.0) ? spine : m.base;
    s.albedo *= 1.0 + brFbm3(pin.p * 40.0, 3, pin.fp * 40.0) * 0.05;
    return s;
}

BRSurf brLeaf(BRMat m, BRPatternIn pin)
{
    BRSurf s = brSurfDefault(m);
    float vein = brVN3(pin.p * 60.0) * 0.5 + 0.5;
    float shade = frac(pin.seed * 5.3);
    s.albedo = lerp(m.base, m.second, saturate(shade * 0.6 + vein * 0.2));
    return s;
}

BRSurf brClay(BRMat m, BRPatternIn pin)
{
    BRSurf s = brSurfDefault(m);
    float mott = brFbm3(pin.p * 18.0, 4, pin.fp * 18.0);
    float grit = brVN3(pin.p * 600.0) * saturate(1.4 - pin.fp * 600.0);
    s.albedo = lerp(m.second, m.base, saturate(0.65 + mott * 0.6)) * (1.0 + grit * 0.06);
    return s;
}

// Rug texture lookup is the renderer's business; it passes the sampled colour in.
BRSurf brEvalSurface(BRMat m, BRPatternIn pin, float3 rugColour, bool haveRug)
{
    int f = m.family;
    if (f == FAM_WOOD)    return brWood(m, pin, false);
    if (f == FAM_PARQUET) return brWood(m, pin, true);
    if (f == FAM_LINEN)   return brLinen(m, pin);
    if (f == FAM_LEATHER) return brLeather(m, pin);
    if (f == FAM_VELVET)  return brVelvet(m, pin);
    if (f == FAM_METAL)   return brMetal(m, pin);
    if (f == FAM_GLAZE)   return brGlaze(m, pin);
    if (f == FAM_MARBLE)  return brMarble(m, pin);
    if (f == FAM_WOOL)    return brWool(m, pin, rugColour, haveRug);
    if (f == FAM_PAPER)   return brPaper(m, pin);
    if (f == FAM_LEAF)    return brLeaf(m, pin);
    if (f == FAM_CLAY)    return brClay(m, pin);
    if (f == FAM_SHEER || f == FAM_LINEN) return brLinen(m, pin);
    BRSurf s = brSurfDefault(m);
    if (f == FAM_EMISSIVE) s.emit = m.base * 6.0;
    if (f == FAM_PAINT) return brPaint(m, pin);
    return s;
}

// ---------------------------------------------------------------------------------------------
// BRDF -- GGX specular (height-correlated Smith), Burley diffuse, Charlie sheen, clearcoat.
float3 brFresnel(float3 f0, float c) { float k = pow(1.0 - saturate(c), 5.0); return f0 + (1.0 - f0) * k; }
float brDGGX(float NoH, float a) { float a2 = a * a; float d = NoH * NoH * (a2 - 1.0) + 1.0; return a2 / (BR_PI_S * d * d + 1e-7); }
float brVSmith(float NoV, float NoL, float a)
{
    float a2 = a * a;
    float gv = NoL * sqrt(NoV * NoV * (1.0 - a2) + a2);
    float gl = NoV * sqrt(NoL * NoL * (1.0 - a2) + a2);
    return 0.5 / max(gv + gl, 1e-6);
}
float brDCharlie(float NoH, float r)
{
    float inv = 1.0 / max(r, 0.07);
    float s2 = 1.0 - NoH * NoH;
    return (2.0 + inv) * pow(max(s2, 0.0), inv * 0.5) / (2.0 * BR_PI_S);
}
float brVNeubelt(float NoV, float NoL) { return saturate(1.0 / (4.0 * (NoL + NoV - NoL * NoV) + 1e-4)); }

// Direct light response (radiance multiplier: multiply by light radiance / irradiance).
// Returns diffuse and specular separately so the caller can apply AO/translucency differently.
void brDirect(BRSurf s, float3 n, float3 v, float3 l, out float3 diff, out float3 spec)
{
    float3 h = normalize(v + l);
    float NoL = saturate(dot(n, l)), NoV = max(dot(n, v), 1e-4), NoH = saturate(dot(n, h)), VoH = saturate(dot(v, h));
    float a = max(s.rough * s.rough, 0.002);
    float3 F = brFresnel(s.f0, VoH);
    float3 specL = brDGGX(NoH, a) * brVSmith(NoV, NoL, a) * F;
    // Burley diffuse
    float fd90 = 0.5 + 2.0 * VoH * VoH * s.rough;
    float fl = 1.0 + (fd90 - 1.0) * pow(1.0 - NoL, 5.0);
    float fv = 1.0 + (fd90 - 1.0) * pow(1.0 - NoV, 5.0);
    float3 kd = (1.0 - F) * (1.0 - s.metal);
    float3 diffL = s.albedo * kd * BR_INV_PI * fl * fv;
    // sheen (fabric)
    float3 sheenL = s.sheen * s.sheenTint * brDCharlie(NoH, max(s.rough, 0.3)) * brVNeubelt(NoV, NoL) * 0.6;
    // clearcoat (varnish)
    float ca = max(s.coatRough * s.coatRough, 0.002);
    float Fc = 0.04 + 0.96 * pow(1.0 - VoH, 5.0);
    float coatL = s.coat * brDGGX(NoH, ca) * brVSmith(NoV, NoL, ca) * Fc;
    float base = 1.0 - s.coat * Fc;
    diff = diffL * base * NoL;
    spec = (specL * base + sheenL + coatL) * NoL;
}

// Wrap-lit diffuse transmission for thin translucent surfaces lit from behind.
float3 brTransmit(BRSurf s, float3 n, float3 l)
{
    float back = saturate(dot(-n, l) * 0.8 + 0.2);
    return s.albedo * s.trans * back * BR_INV_PI;
}

// Split-sum style environment specular weight (Karis' analytic fit).
float3 brEnvBRDF(float3 f0, float rough, float NoV)
{
    float4 c0 = float4(-1, -0.0275, -0.572, 0.022);
    float4 c1 = float4(1, 0.0425, 1.04, -0.04);
    float4 r = rough * c0 + c1;
    float a004 = min(r.x * r.x, exp2(-9.28 * NoV)) * r.x + r.y;
    float2 ab = float2(-1.04, 1.04) * a004 + r.zw;
    return f0 * ab.x + ab.y;
}

#endif
