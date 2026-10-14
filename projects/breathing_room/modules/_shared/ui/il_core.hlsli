// il_core.hlsli - Interaction Lab kit, layer 0: palette, pixel geometry, compositing.
//
// Everything in the kit works in OUTPUT PIXELS. A station derives its layout from the live
// extent (OutputUAV.GetDimensions, or _Resolution in a 1x1x1 reducer pass) and passes pixel
// coordinates down; strokes, glyphs and grab radii are pixel quantities, never fractions of
// the panel. The only normalized numbers are event positions, converted once on entry.
//
// Palette: the shared instrument ladder from plan_theme.hlsli (vendored beside this file),
// extended with two surface steps so panes can sit above the ground without hairlines on
// every edge. Hue rules are plan_theme's: amber = selection or an established live reading,
// red = broken, identity = a closed set of at most four, a record's own colour through
// ptSampleColour. Hover never takes a hue; it takes a value step.
#ifndef IL_CORE_HLSLI
#define IL_CORE_HLSLI

#include "../_shared/plan_theme.hlsli"

// ---------------------------------------------------------------- palette (display-referred)
#define IL_FIELD   PT_FIELD                        // the ground
#define IL_WELL    PT_WELL                         // inset regions: plots, pads, wells
#define IL_PANEL   float3(0.0230, 0.0240, 0.0245)  // a pane or card sitting on the ground
#define IL_RAISE   float3(0.0420, 0.0435, 0.0440)  // a control face, a hovered row
#define IL_GRID    PT_GRID                         // grids and station lines
#define IL_EDGE    float3(0.1150, 0.1180, 0.1130)  // quiet borders between surfaces
#define IL_RULE    PT_RULE                         // hairline chrome, inactive marks
#define IL_DIM     PT_DIM                          // secondary type, ticks
#define IL_MID     PT_MID                          // plotted data that is not a reading
#define IL_INK     PT_INK                          // primary type, live geometry
#define IL_ACCENT  PT_ACCENT                       // RESERVED: selection / live reading
#define IL_ALARM   PT_ALARM                        // RESERVED: broken

// ---------------------------------------------------------------- metrics
// ui px at scale 1 (multiply by ILCtx.s). Here, not in il_ui, so reducers hit-test with the same
// numbers the widgets draw with.
#define IL_RADIUS   3.0
#define IL_ROW      24.0
#define IL_HEADER   26.0
#define IL_GAP      8.0
#define IL_T_CAP    10.5     // captions
#define IL_T_BODY   12.5     // labels
#define IL_T_VALUE  12.0     // numbers
#define IL_T_TITLE  11.0     // pane titles (bold, tracked, upper case in labels.txt)

static const float IL_PI = 3.14159265359;
static const float IL_TAU = 6.28318530718;
// 10^e for digit arithmetic (e <= 9). Whole-number arithmetic stays in uint: FXC's fmod(x, y) is
// frac(x / y) * y, and x / y and log10 are a few ULP out, which by a few thousand is enough to print
// 10000 as 9999.999 (a wrong digit) or give 9999 five digits. (Not a static array: at the live /Od
// compile an indexed array becomes per-thread indexable registers.)
uint ilP10(uint e)
{
    e = min(e, 9u);                                      // from e's bits: no loop, no array
    return ((e & 1u) != 0u ? 10u : 1u) * ((e & 2u) != 0u ? 100u : 1u) * ((e & 4u) != 0u ? 10000u : 1u) * ((e & 8u) != 0u ? 100000000u : 1u);
}

// ---------------------------------------------------------------- context
// One per pixel or per reducer: the live extent and the ui scale derived from it.
struct ILCtx {
    float2 res;     // output extent in px
    float  s;       // ui scale: 1.0 at 1280x720, from the SMALLER axis ratio, clamped
    float  px;      // one device pixel in ui units (1/s); handy for hairlines
};

ILCtx ilCtx(float2 res)
{
    ILCtx c;
    c.res = max(res, float2(1.0, 1.0));
    c.s = clamp(min(c.res.x / 1280.0, c.res.y / 720.0), 0.62, 2.4);
    c.px = 1.0 / c.s;
    return c;
}

// Snap a ui length to whole device pixels (keeps hairlines crisp at fractional scales).
float ilSnap(float v) { return floor(v + 0.5); }

// ---------------------------------------------------------------- rects (float4 = x0,y0,x1,y1)
float4 ilRect(float2 lo, float2 hi) { return float4(lo, hi); }
float2 ilSize(float4 r) { return r.zw - r.xy; }
float2 ilMid(float4 r) { return (r.xy + r.zw) * 0.5; }
bool   ilIn(float2 p, float4 r) { return all(p >= r.xy) && all(p <= r.zw); }
float4 ilInset(float4 r, float d) { return float4(r.xy + d, r.zw - d); }
float4 ilInset2(float4 r, float2 d) { return float4(r.xy + d, r.zw - d); }
// Normalized sub-rect of r (t = x0,y0,x1,y1 in 0..1 of r).
float4 ilSub(float4 r, float4 t) { float2 sz = ilSize(r); return float4(r.xy + t.xy * sz, r.xy + t.zw * sz); }
// Cut a strip off one side: returns the strip; r keeps the remainder.
float4 ilCutTop(inout float4 r, float h)    { float4 s = float4(r.x, r.y, r.z, min(r.y + h, r.w)); r.y = s.w; return s; }
float4 ilCutBottom(inout float4 r, float h) { float4 s = float4(r.x, max(r.w - h, r.y), r.z, r.w); r.w = s.y; return s; }
float4 ilCutLeft(inout float4 r, float w)   { float4 s = float4(r.x, r.y, min(r.x + w, r.z), r.w); r.x = s.z; return s; }
float4 ilCutRight(inout float4 r, float w)  { float4 s = float4(max(r.z - w, r.x), r.y, r.z, r.w); r.z = s.x; return s; }

// ---------------------------------------------------------------- signed distances (px, - inside)
float ilSdBox(float2 p, float4 r, float rad)
{
    float2 c = ilMid(r);
    float2 q = abs(p - c) - (ilSize(r) * 0.5 - rad);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rad;
}
float ilSdCircle(float2 p, float2 c, float rad) { return length(p - c) - rad; }
float ilSdSeg(float2 p, float2 a, float2 b)
{
    float2 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * h);
}
// Diamond (keyframe) of half-diagonal r.
float ilSdDiamond(float2 p, float2 c, float rad) { float2 q = abs(p - c); return (q.x + q.y - rad) * 0.70710678; }
// Isosceles triangle with its apex at c pointing DOWN the screen (a playhead cap), base h px
// above the apex, half-width w. Exact distance (after Inigo Quilez).
float ilSdTriDown(float2 p, float2 c, float w, float h)
{
    float2 q = float2(w, h);
    float2 a2 = float2(abs(p.x - c.x), c.y - p.y);
    float2 a = a2 - q * saturate(dot(a2, q) / dot(q, q));
    float2 b = a2 - q * float2(saturate(a2.x / q.x), 1.0);
    float2 d = min(float2(dot(a, a), -(a2.x * q.y - a2.y * q.x)), float2(dot(b, b), -(a2.y - q.y)));
    return -sqrt(d.x) * sign(d.y);
}

// ---------------------------------------------------------------- coverage
float ilFill(float d) { return saturate(0.5 - d); }
// Stroke centred on the contour, width w px.
float ilStroke(float d, float w) { return saturate(0.5 * w + 0.5 - abs(d)); }
// Stroke lying just inside the edge (borders that must not grow a rect).
float ilBorder(float d, float w) { return ilFill(d) * (1.0 - ilFill(d + w)); }

void ilOver(inout float3 dst, float3 src, float a) { dst = lerp(dst, src, saturate(a)); }

float ilLum(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

// Dashed coverage along a parameter t (px), dash and gap in px.
float ilDash(float t, float dash, float gap) { return step(frac(t / (dash + gap)), dash / (dash + gap)); }

// ---------------------------------------------------------------- small maths
float ilHash11(float x) { x = frac(x * 0.1031); x *= x + 33.33; x *= x + x; return frac(x); }
float ilHash21(float2 p) { float3 q = frac(float3(p.xyx) * 0.1031); q += dot(q, q.yzx + 33.33); return frac((q.x + q.y) * q.z); }
uint  ilHashU(uint x) { x ^= x >> 16; x *= 0x7feb352dU; x ^= x >> 15; x *= 0x846ca68bU; x ^= x >> 16; return x; }

// Exponential approach that is correct at any cook rate: k = response per second.
float  ilApproach(float cur, float target, float k, float dt)  { return lerp(target, cur, exp(-k * max(dt, 0.0))); }
float2 ilApproach2(float2 cur, float2 target, float k, float dt) { return lerp(target, cur, exp(-k * max(dt, 0.0))); }

// Pixel grid line coverage for a 1D coordinate x (px) with spacing sp (px), line width w.
float ilGridLine(float x, float sp, float w)
{
    float d = abs(x - sp * floor(x / sp + 0.5));
    return saturate(0.5 * w + 0.5 - d);
}

#endif
