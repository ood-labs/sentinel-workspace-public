// Path Desk - the record layout, the path maths and the geometry every pass shares (the reducer
// hit-tests exactly what the layout pass draws).
//
// Records (32 bytes, the lab's a/b/c/d/e/f shape). The first 127 - the paths - are what a save, a
// node preset and an undo payload carry (state_buffers). Everything after them is working state
// that is never restored: a recalled preset must not replay the input that followed it.
//   0       P0   e = anchor counts (5 bits per path), f = format magic
//   1..6         path p: e = closed (bit 0) | pen (bits 1-2)
//   7..126       anchors, 20 per path in drawing order: a = position (program px, y down),
//                b = in handle, (c, d) = out handle (px from the anchor),
//                e = kind (bits 0-1: corner, smooth, aligned, broken) | selected (bit 4)
//   --- not saved ---
//   127     V0   e = event watermark
//   128     V1   a = press px, b = pointer px, c = drag mode, d = drag target,
//                e = flags (bit 0 pen engaged, bit 1 comb hidden, bit 2 drawing the active path),
//                f = active path (6 = none)
//   129     V2   a = the grabbed anchor's position when the drag began, b = the box's moving
//                corner px, e = cooks, f = working-state magic
//   130..256     the undo snapshot of 0..126 (also every drag's origin)
//   257     U0   f = 1 when a snapshot exists
//
// Kinds: a CORNER has no handles, so the tangent breaks there; SMOOTH takes its handles from its
// neighbours every cook (along the line between them, a third of the way to each); ALIGNED keeps
// its two handles opposite - dragging one turns the other; BROKEN leaves them independent.
// Paths are kept compact (0 .. paths-1) and plot in that order.
#ifndef PATH_HLSLI
#define PATH_HLSLI

#include "../_shared/plot.hlsli"

#define PD_PATHS  PLOT_PATHS
#define PD_AMAX   PLOT_AMAX
#define PD_P0     0u
#define PD_H0     1u
#define PD_A0     7u
#define PD_SAVED  127u
#define PD_V0     127u
#define PD_V1     128u
#define PD_V2     129u
#define PD_UNDO0  130u
#define PD_U0     257u
#define PD_COUNT  258u
#define PD_MAGIC  0xC0DE0308u
#define PD_VMAGIC 0xC0DE1308u
#define PD_NONE   6u

#define PD_CORNER  0u
#define PD_SMOOTH  1u
#define PD_ALIGNED 2u
#define PD_BROKEN  3u
#define PD_SEL     16u

#define PD_PEN     1u
#define PD_NOCOMB  2u
#define PD_DRAWING 4u     // the pen is extending the active path

struct PdRec { float2 a; float2 b; float c; float d; uint e; uint f; };

#ifdef PD_STATE_RW
RWStructuredBuffer<PdRec> S : register(u0);
#else
StructuredBuffer<PdRec> S : register(t0);
#endif

uint  pdCount(uint pk, uint p) { return (pk >> (5u * p)) & 31u; }
uint  pdWithCount(uint pk, uint p, uint n) { return (pk & ~(31u << (5u * p))) | (min(n, 31u) << (5u * p)); }
uint  pdPaths(uint pk)
{
    uint n = 0u;
    [unroll] for (uint p = 0u; p < PD_PATHS; p++) n += (pdCount(pk, p) > 0u) ? 1u : 0u;
    return n;
}
uint  pdSlot(uint p, uint j) { return PD_A0 + p * PD_AMAX + j; }
PdRec pdAnchor(uint p, uint j) { return S[pdSlot(p, j)]; }
bool  pdClosed(uint p) { return (S[PD_H0 + p].e & 1u) != 0u; }
uint  pdPen(uint p) { return (S[PD_H0 + p].e >> 1) & 3u; }
uint  pdKind(uint e) { return e & 3u; }
bool  pdSel(uint e) { return (e & PD_SEL) != 0u; }
float2 pdOut(PdRec r) { return float2(r.c, r.d); }

// segments of path p: n - 1 open, n closed (none below two anchors)
uint pdSegs(uint pk, uint p)
{
    uint n = pdCount(pk, p);
    return n < 2u ? 0u : (pdClosed(p) ? n : n - 1u);
}

// ---------------------------------------------------------------- path maths
void pdSeg(uint pk, uint p, uint k, out float2 p0, out float2 p1, out float2 p2, out float2 p3)
{
    uint n = max(pdCount(pk, p), 1u);
    PdRec a = pdAnchor(p, k), b = pdAnchor(p, (k + 1u) % n);
    p0 = a.a;
    p1 = a.a + pdOut(a);
    p2 = b.a + b.b;
    p3 = b.a;
}

float2 pdBez(float2 p0, float2 p1, float2 p2, float2 p3, float t)
{
    float u = 1.0 - t;
    return u * u * u * p0 + 3.0 * u * u * t * p1 + 3.0 * u * t * t * p2 + t * t * t * p3;
}
float2 pdBezD(float2 p0, float2 p1, float2 p2, float2 p3, float t)
{
    float u = 1.0 - t;
    return 3.0 * (u * u * (p1 - p0) + 2.0 * u * t * (p2 - p1) + t * t * (p3 - p2));
}
float2 pdBezDD(float2 p0, float2 p1, float2 p2, float2 p3, float t)
{
    return 6.0 * ((1.0 - t) * (p2 - 2.0 * p1 + p0) + t * (p3 - 2.0 * p2 + p1));
}

// The direction of travel at t. A zero handle at an end gives a zero derivative there: the curve
// then leaves along the next control point that differs.
float2 pdTangent(float2 p0, float2 p1, float2 p2, float2 p3, float t)
{
    float2 d = pdBezD(p0, p1, p2, p3, t);
    if (dot(d, d) > 1e-6) return d;
    float2 alt = (t < 0.5) ? (p2 - p0) : (p3 - p1);
    if (dot(alt, alt) > 1e-6) return alt;
    return p3 - p0;
}

// signed curvature (1/px, + clockwise on screen), held to a 2 px radius: a zero handle makes the
// curvature at that end unbounded, and a number nobody can draw helps nobody
float pdCurvature(float2 p0, float2 p1, float2 p2, float2 p3, float t)
{
    float2 d = pdBezD(p0, p1, p2, p3, t), dd = pdBezDD(p0, p1, p2, p3, t);
    float l = length(d);
    if (l < 1e-3) return 0.0;
    return clamp((d.x * dd.y - d.y * dd.x) / (l * l * l), -0.5, 0.5);
}

// ---------------------------------------------------------------- geometry
struct PdLayout
{
    float4 head;
    float4 mode;               // EDIT | PEN in the header (click: switch)
    float4 hint;
    float4 block;
    float4 list;               // the paths, left
    float4 row[PD_PATHS];      // click: select the path
    float4 pen[PD_PATHS];      // each row's pen chip (click: the next pen)
    float4 plot;               // the plot's totals under the rows
    float4 area;               // the stage's region
    float4 stage;              // the 1280 x 720 program frame, fitted
    float  k;                  // screen px per program px
    float4 strip;              // curvature along the plot
};

PdLayout pdLayout(float2 res, float s)
{
    PdLayout L;
    float m = 16.0 * s;
    L.head = float4(m, 14.0 * s, res.x - m, 44.0 * s);
    L.mode = float4(L.head.z - 132.0 * s, L.head.y, L.head.z, L.head.w);
    L.hint = float4(m, res.y - 41.0 * s, res.x - m, res.y - 11.0 * s);
    L.block = float4(m, 54.0 * s, res.x - m, L.hint.y - 10.0 * s);
    float4 inner = ilInset(L.block, 12.0 * s);
    L.list = float4(inner.x, inner.y, inner.x + 222.0 * s, inner.w);
    float rowH = 44.0 * s;
    [unroll] for (uint p = 0u; p < PD_PATHS; p++)
    {
        float y0 = L.list.y + 30.0 * s + p * (rowH + 5.0 * s);
        L.row[p] = float4(L.list.x, y0, L.list.z, y0 + rowH);
        L.pen[p] = float4(L.row[p].z - 88.0 * s, y0 + 23.0 * s, L.row[p].z - 6.0 * s, y0 + 39.0 * s);
    }
    L.plot = float4(L.list.x, L.row[PD_PATHS - 1u].w + 16.0 * s, L.list.z, L.list.w);
    float rx = L.list.z + 14.0 * s;
    float stripH = clamp((inner.w - inner.y) * 0.22, 92.0 * s, 160.0 * s);
    L.strip = float4(rx, inner.w - stripH, inner.z, inner.w);
    L.area = float4(rx, inner.y, inner.z, L.strip.y - 10.0 * s);
    float aw = L.area.z - L.area.x, ah = L.area.w - L.area.y;
    L.k = max(min(aw / PLOT_W, ah / PLOT_H), 1e-3);
    float2 sz = float2(PLOT_W, PLOT_H) * L.k;
    float2 o = float2(L.area.x + 0.5 * (aw - sz.x), L.area.y + 0.5 * (ah - sz.y));
    L.stage = float4(o, o + sz);
    return L;
}

float2 pdScreen(PdLayout L, float2 q) { return L.stage.xy + q * L.k; }
float2 pdProg(PdLayout L, float2 p) { return (p - L.stage.xy) / L.k; }

// ---------------------------------------------------------------- hit tests (reducer + hover)
// Handles show on a selected anchor that is not a corner, on the sides that have a segment.
bool pdShowsIn(uint pk, uint p, uint j)  { return pdCount(pk, p) >= 2u && (j > 0u || pdClosed(p)); }
bool pdShowsOut(uint pk, uint p, uint j) { return pdCount(pk, p) >= 2u && (j + 1u < pdCount(pk, p) || pdClosed(p)); }

// nearest anchor within reach px: p * 20 + j, or 0xFFFF
uint pdHitAnchor(PdLayout L, uint pk, float2 at, float reach)
{
    uint best = 0xFFFFu;
    float bd = reach;
    [loop] for (uint p = 0u; p < PD_PATHS; p++)
    {
        uint n = pdCount(pk, p);
        [loop] for (uint j = 0u; j < n; j++)
        {
            float d = length(pdScreen(L, pdAnchor(p, j).a) - at);
            if (d < bd) { bd = d; best = p * PD_AMAX + j; }
        }
    }
    return best;
}

// nearest shown handle tip of a selected anchor: (p * 20 + j) * 2 + (1 = out), or 0xFFFF
uint pdHitHandle(PdLayout L, uint pk, float2 at, float reach)
{
    uint best = 0xFFFFu;
    float bd = reach;
    [loop] for (uint p = 0u; p < PD_PATHS; p++)
    {
        uint n = pdCount(pk, p);
        [loop] for (uint j = 0u; j < n; j++)
        {
            PdRec r = pdAnchor(p, j);
            if (!pdSel(r.e) || pdKind(r.e) == PD_CORNER) continue;
            if (pdShowsIn(pk, p, j))
            {
                float d = length(pdScreen(L, r.a + r.b) - at);
                if (d < bd) { bd = d; best = (p * PD_AMAX + j) * 2u; }
            }
            if (pdShowsOut(pk, p, j))
            {
                float d = length(pdScreen(L, r.a + pdOut(r)) - at);
                if (d < bd) { bd = d; best = (p * PD_AMAX + j) * 2u + 1u; }
            }
        }
    }
    return best;
}

// The nearest point on any segment within reach px: (p * 20 + segment, t, distance px), or x = -1.
// Each segment is walked as 32 chords, then t is refined on the nearest chord.
float3 pdHitCurve(PdLayout L, uint pk, float2 at, float reach)
{
    float3 best = float3(-1.0, 0.0, reach);
    [loop] for (uint p = 0u; p < PD_PATHS; p++)
    {
        uint segs = pdSegs(pk, p);
        [loop] for (uint k = 0u; k < segs; k++)
        {
            float2 p0, p1, p2, p3;
            pdSeg(pk, p, k, p0, p1, p2, p3);
            float2 prev = pdScreen(L, p0);
            [loop] for (uint i = 1u; i <= 32u; i++)
            {
                float2 cur = pdScreen(L, pdBez(p0, p1, p2, p3, i / 32.0));
                float2 ab = cur - prev;
                float h = saturate(dot(at - prev, ab) / max(dot(ab, ab), 1e-6));
                float d = length(at - prev - ab * h);
                if (d < best.z) best = float3((float)(p * PD_AMAX + k), (i - 1.0 + h) / 32.0, d);
                prev = cur;
            }
        }
    }
    return best;
}

#endif
