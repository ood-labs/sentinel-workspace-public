// timeline.hlsli - the Motion contract: a short title sting as four layers, five channels each,
// keyframed with an interpolation per segment; the evaluator; and the layers' shapes and inks.
//
// The Timeline (editor) writes it into its state buffer and publishes that buffer as "Motion". Its
// stage pass and the Sting (program) both evaluate it with these functions and shade it with
// tlComposite, so the editor's preview and the program draw the same picture - the program only
// adds what a preview cannot afford (motion blur from many samples across the shutter).
//
// Records (float4; integers are stored as exact float values):
//   0        P0     (loop in frame, loop out frame, frames in the timeline, frames per second)   saved
//   1        PM     (format magic, -, -, -)                                                       saved
//   2..6     counts the number of keys on each channel, four channels a record                  saved
//   7..166   keys   channel c (= layer * 5 + attribute), slot i at 7 + c * 8 + i, in frame order: saved
//                     (frame, value, mode + 8 * selected, ease params: q(p0) + 4096 * q(p1))
//                   the mode is the segment LEAVING the key, as in most motion tools
//   167      V0     (playhead frame, playing 0 | 1, speed index, working magic)   <- read by the program
//   168..    the editor's working state (see Timeline/tl.hlsli); never saved
//
// Layers, front to back: 0 Ring, 1 Sun, 2 Block, 3 Bar. Attributes: 0 x, 1 y (stage units: the
// stage is 1 tall and 16:9 wide, origin at its centre, y up), 2 scale, 3 rotation (degrees,
// clockwise), 4 opacity. A channel with no keys holds its default (0, 0, 1, 0, 1).
//
// Segment interpolation, by the key the segment leaves:
//   0 hold     the key's value until the next key
//   1 linear
//   2 ease     a timing curve with flat ends; p0 = ease-out influence (leaving), p1 = ease-in
//              influence (arriving), each 0..1: how long and flat that end's approach is (drawn in
//              the graph as a handle reaching that share of the segment)
//   3 spring   overshoots and settles by the next key; p0 = bounce
//   4 back     dips back before it leaves and overshoots before it lands; p0 = anticipation,
//              p1 = overshoot
#ifndef TIMELINE_HLSLI
#define TIMELINE_HLSLI

#ifndef TL_BUF
#error define TL_BUF (the Motion buffer: StructuredBuffer or RWStructuredBuffer of float4) before including timeline.hlsli
#endif

#define TL_LAYERS  4u
#define TL_ATTRS   5u
#define TL_CH      20u
#define TL_KMAX    8u
#define TL_P0      0u
#define TL_PM      1u
#define TL_COUNT0  2u
#define TL_KEY0    7u
#define TL_SAVED   167u
#define TL_V0      167u
#define TL_MAGIC   1111.0

#define TL_HOLD    0u
#define TL_LINEAR  1u
#define TL_EASE    2u
#define TL_SPRING  3u
#define TL_BACK    4u
#define TL_SELBIT  8u

#define TL_X 0u
#define TL_Y 1u
#define TL_SCALE 2u
#define TL_ROT 3u
#define TL_OPACITY 4u

#define TL_RING  0u
#define TL_SUN   1u
#define TL_BLOCK 2u
#define TL_BAR   3u

// ---------------------------------------------------------------- reading
float4 tlP0()                 { return TL_BUF[TL_P0]; }
uint   tlCount(uint ch)       { return min((uint)TL_BUF[TL_COUNT0 + ch / 4u][ch % 4u], TL_KMAX); }
uint   tlSlot(uint ch, uint i){ return TL_KEY0 + ch * TL_KMAX + i; }
float4 tlKey(uint ch, uint i) { return TL_BUF[tlSlot(ch, i)]; }
uint   tlMode(float4 k)       { return (uint)k.z & 7u; }
bool   tlSel(float4 k)        { return ((uint)k.z & TL_SELBIT) != 0u; }
float2 tlParams(float4 k)     { uint q = (uint)k.w; return float2((float)(q & 4095u), (float)(q >> 12)) / 4095.0; }
float  tlPackParams(float2 p) { uint2 q = (uint2)round(saturate(p) * 4095.0); return (float)(q.x + 4096u * q.y); }
float  tlPlayhead()           { return TL_BUF[TL_V0].x; }
float  tlDefault(uint attr)   { return (attr == TL_SCALE || attr == TL_OPACITY) ? 1.0 : 0.0; }

// ---------------------------------------------------------------- the segment curves
// y(u) for a segment's normalized time u in 0..1: 0 at the key it leaves, 1 at the key it reaches.
float tlEase(float2 prm, float u)
{
    // closed form, so it costs no loop wherever it inlines: y = u^a / (u^a + (1 - u)^b). The
    // exponents grow with the influences: 1 (no ease: the key is met at full speed) to 4 (a long,
    // flat approach); 0.33 gives a = b = 2, the familiar symmetric ease.
    float a = 1.0 + 3.0 * clamp(prm.x, 0.02, 1.0), b = 1.0 + 3.0 * clamp(prm.y, 0.02, 1.0);
    float pa = pow(saturate(u), a), pb = pow(saturate(1.0 - u), b);
    return pa / max(pa + pb, 1e-6);
}

float tlShape01(uint mode, float2 prm, float u)
{
    if (mode == TL_HOLD) return 0.0;
    if (mode == TL_LINEAR) return u;
    if (mode == TL_EASE) return tlEase(prm, u);
    if (mode == TL_SPRING)
    {
        // a damped cosine that reaches its target exactly at the next key
        float b = saturate(prm.x);
        float w = 6.2831853 * (0.75 + 2.0 * b), d = 5.0 - 2.5 * b;
        return 1.0 - exp(-d * u) * cos(w * u) * (1.0 - u);
    }
    // back: a cubic with x(s) = s, y controls (0, -a, 1 + b, 1)
    float a = 0.6 * saturate(prm.x), b = 0.6 * saturate(prm.y), r = 1.0 - u;
    return -3.0 * r * r * u * a + 3.0 * r * u * u * (1.0 + b) + u * u * u;
}

// a channel's value at frame f: the first key's value before it, the last key's after it
float tlValue(uint ch, float f)
{
    uint n = tlCount(ch);
    if (n == 0u) return tlDefault(ch % TL_ATTRS);
    float4 k0 = tlKey(ch, 0u);
    if (n == 1u || f <= k0.x) return k0.y;
    float4 kl = tlKey(ch, n - 1u);
    if (f >= kl.x) return kl.y;
    uint i = 0u;
    [loop] for (uint j = 1u; j + 1u < n; j++) if (tlKey(ch, j).x <= f) i = j;
    float4 a = tlKey(ch, i), b = tlKey(ch, i + 1u);
    float u = saturate((f - a.x) / max(b.x - a.x, 1e-4));
    return a.y + (b.y - a.y) * tlShape01(tlMode(a), tlParams(a), u);
}

// ---------------------------------------------------------------- the layers
// A layer's pose: (x, y, scale, rotation degrees) and opacity.
struct TlPose { float4 xfrm; float opacity; };

TlPose tlPose(uint layer, float f)
{
    TlPose p;
    uint c = layer * TL_ATTRS;
    p.xfrm = float4(tlValue(c, f), tlValue(c + 1u, f), tlValue(c + 2u, f), tlValue(c + 3u, f));
    p.opacity = saturate(tlValue(c + 4u, f));
    return p;
}

// stage units; sizes at scale 1
#define TL_SUN_R     0.150
#define TL_RING_R    0.215
#define TL_RING_W    0.0075
#define TL_BLOCK_H   0.080
#define TL_BAR_HALF  float2(0.46, 0.024)

// the layer's signed distance (stage units) at stage point q
float tlSd(uint layer, float4 x, float2 q)
{
    float sc = max(abs(x.z), 1e-3);
    float a = radians(x.w);
    float2 d = q - x.xy;
    float2 r = float2(d.x * cos(a) - d.y * sin(a), d.x * sin(a) + d.y * cos(a));   // into the layer's frame
    if (layer == TL_RING) return abs(length(d) - TL_RING_R * sc) - TL_RING_W * sc;
    if (layer == TL_SUN) return length(d) - TL_SUN_R * sc;
    float2 h = (layer == TL_BLOCK) ? float2(TL_BLOCK_H, TL_BLOCK_H) * sc : TL_BAR_HALF * sc;
    float2 e = abs(r) - h;
    return length(max(e, 0.0)) + min(max(e.x, e.y), 0.0);
}

// the sting's inks: paper, a near-black for the geometry, vermilion for the sun
#define TL_PAPER  float3(0.930, 0.922, 0.902)
#define TL_INK    float3(0.075, 0.075, 0.080)
#define TL_RED    float3(0.880, 0.250, 0.110)
float3 tlInk(uint layer) { return layer == TL_SUN ? TL_RED : TL_INK; }

// the picture at one instant: paper, then the layers back to front. pxPerUnit sets the edge's
// anti-aliasing (one pixel), poses are indexed by layer.
float3 tlComposite(float2 q, float pxPerUnit, float4 xf[TL_LAYERS], float op[TL_LAYERS])
{
    float3 col = TL_PAPER;
    [unroll] for (int l = (int)TL_LAYERS - 1; l >= 0; l--)
    {
        float cov = saturate(0.5 - tlSd((uint)l, xf[l], q) * pxPerUnit) * op[l];
        col = lerp(col, tlInk((uint)l), cov);
    }
    return col;
}

// stage <-> pixels inside a fitted 16:9 stage rect (y up in stage units)
float2 tlStageToPx(float4 st, float2 q) { float h = st.w - st.y; return float2(0.5 * (st.x + st.z) + q.x * h, 0.5 * (st.y + st.w) - q.y * h); }
float2 tlPxToStage(float4 st, float2 p) { float h = max(st.w - st.y, 1.0); return float2((p.x - 0.5 * (st.x + st.z)) / h, (0.5 * (st.y + st.w) - p.y) / h); }

#endif
