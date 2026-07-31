// plate.hlsli — the matik_plate data contract and 2D drawing vocabulary.
//
// PLATE SPACE is the single layout transform for the whole show: [0,1] x [0,1],
// origin top-left, +y DOWN. It is identical to a square generator pass's `uv` and to
// normalized viewport pointer coordinates, so render / pick / drag all share one mapping.
// MX_Console is the ONLY node that defines placement. Every consumer reads plate space
// straight off `uv` and must not re-apply a global offset or scale.
//
// One buffer carries the whole plan. `role` discriminates:
//   role 0 = instrument cell  (pos = center, size = half-extent)
//   role 1 = organism anchor  (pos = center, size.x = reserve radius, size.y = growth scale)
//   role 2 = header record    (console bookkeeping; consumers ignore it)
#ifndef MX_PLATE_HLSLI
#define MX_PLATE_HLSLI

#define PLATE_CELLS      64u
#define PLATE_ANCHOR_0   64u
#define PLATE_ANCHORS    8u
#define PLATE_HEADER     127u
#define PLATE_RECORDS    128u

#define ROLE_CELL   0.0
#define ROLE_ANCHOR 1.0
#define ROLE_HEADER 2.0

// instrument cell kinds
#define K_GRID     0
#define K_CHECKER  1
#define K_DOTS     2
#define K_RAIL     3
#define K_DASH     4
#define K_HALFTONE 5
#define K_DIAL     6
#define K_DATA     7
#define K_CHEVRON  8
#define K_BARS     9
#define K_CONE     10
#define K_GLYPH    11
#define K_TARGET   12
#define K_WAVE     13
#define K_SPIRAL   14
#define K_KEYS     15
#define K_KINDS    16

// organism growth kinds
#define G_CHAIN    0
#define G_DENDRITE 1
#define G_BURST    2

// flag bits packed into PlateRec.flags
#define F_SELECTED 1u
#define F_PINNED   2u
#define F_EDITED   4u

struct PlateRec
{
    float2 pos;    // plate-space center
    float2 size;   // cell half-extent, or (reserve radius, growth scale) for an anchor
    float role;
    float kind;
    float seed;
    float tone;    // ink weight 0..1
    float grp;     // band id, used by the connective layer
    float phase;   // 0..1 animation phase offset
    float flags;
    float active;
};

// ---------------------------------------------------------------- hashing
float mxHash11(float p) { p = frac(p * 0.1031); p *= p + 33.33; p *= p + p; return frac(p); }
float mxHash21(float2 p)
{
    float3 p3 = frac(p.xyx * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.x + p3.y) * p3.z);
}
float2 mxHash22(float2 p)
{
    float3 p3 = frac(p.xyx * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.xx + p3.yz) * p3.zy);
}
// deterministic per-record stream: same record + same lane always gives the same value
float mxRnd(float seed, float lane) { return mxHash21(float2(seed * 37.13 + 0.5, lane * 11.7 + 1.3)); }

// ---------------------------------------------------------------- 2D signed distance
float pBox(float2 p, float2 b)
{
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}
float pSeg(float2 p, float2 a, float2 b)
{
    float2 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-9));
    return length(pa - ba * h);
}
float pCircle(float2 p, float r) { return length(p) - r; }
float2 pRot(float2 p, float a) { float s = sin(a), c = cos(a); return float2(c * p.x - s * p.y, s * p.x + c * p.y); }

// Antialiased hairline: `d` is a signed distance, `w` the half-width, `px` one pixel in the
// same units. Everything on the plate is drawn with this so line weight stays uniform.
float pStroke(float d, float w, float px) { return 1.0 - smoothstep(w - px, w + px, abs(d)); }
float pFill(float d, float px) { return 1.0 - smoothstep(-px, px, d); }

// Dashed variant: `t` is arc length along the stroke, in the same units as `d`.
float pDash(float d, float w, float px, float t, float period, float duty)
{
    float s = frac(t / max(period, 1e-5));
    float on = smoothstep(0.5, 0.5 - 0.35, abs(s - duty * 0.5) / max(duty, 1e-4));
    return pStroke(d, w, px) * saturate(on);
}

// ---------------------------------------------------------------- record helpers
bool pIsCell(PlateRec r)   { return r.role < 0.5 && r.active > 0.5; }
bool pIsAnchor(PlateRec r) { return r.role > 0.5 && r.role < 1.5 && r.active > 0.5; }
bool pFlag(PlateRec r, uint bit) { return (((uint)(r.flags + 0.5)) & bit) != 0u; }

// Map a plate-space point into a cell's local [-1,1] box coordinates.
float2 pCellLocal(PlateRec r, float2 p) { return (p - r.pos) / max(r.size, 1e-5); }

#endif // MX_PLATE_HLSLI
