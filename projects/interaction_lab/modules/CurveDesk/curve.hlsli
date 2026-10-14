// Curve Desk - the record layout, the curve maths and the geometry every pass shares (the reducer
// hit-tests exactly what the layout pass draws).
//
// Records (32 bytes, the lab's a/b/c/d/e/f shape). The first 49 - the keys - are what a save, a node
// preset and an undo payload carry (state_buffers). Everything after them is working state that must
// never be restored: a recalled preset would replay the input that followed it (the event watermark)
// and yank the view. A reopened project starts its working state fresh and frames the loaded keys.
//   0      P0   e = key counts (5 bits per channel) | hidden channels (bits 15..17), f = format magic
//   1..48       keys, 16 slots per channel kept in time order:
//                 a = (t, v), b = in handle (dt <= 0, dv), (c, d) = out handle (dt >= 0, dv),
//                 e = bits 0-1 the segment leaving the key (0 step, 1 linear, 2 bezier),
//                     bits 2-3 handles (0 auto, 1 aligned, 2 broken), bit 4 selected
//   --- not saved ---
//   49     V0   a = time window (t0, t1) s, b = value window (v0, v1), c = playhead s, d = split (the
//               graph's share of the editor's height), e = event watermark, f = key latches (bit0 Space)
//   50     V1   a = press point px, b = pointer px, c = drag mode, d = drag target, e = flags (bit0
//               playing, bit1 middle button down)
//   51     V2   a = the grabbed key's position when the drag began (t, v), b = the box's moving corner
//               px, e = cooks, f = working-state magic
//   52..99      the undo snapshot of 1..48 - also every drag's origin, so a drag is "snapshot + delta"
//               and cancelling one is a restore
//   100    U0   e = the snapshot's key counts, f = 1 when a snapshot exists
//
// Handles are function-curve handles: (dt, dv) vectors from the key. Aligned means equal SLOPES on
// both sides (the curve stays smooth as a function of time), not equal screen angles.
#ifndef CURVE_HLSLI
#define CURVE_HLSLI

#define CV_CH     3u
#define CV_KMAX   16u
#define CV_P0     0u
#define CV_KEY0   1u
#define CV_SAVED  (CV_KEY0 + CV_CH * CV_KMAX)    // 49: the records a save carries
#define CV_V0     49u
#define CV_V1     50u
#define CV_V2     51u
#define CV_UNDO0  52u
#define CV_U0     (CV_UNDO0 + CV_CH * CV_KMAX)   // 100
#define CV_COUNT  101u
#define CV_MAGIC  0xC0DE0207u
#define CV_VMAGIC 0xC0DE1207u
#define CV_SAMPLES 256u

#define CV_STEP   0u
#define CV_LINEAR 1u
#define CV_BEZIER 2u
#define CV_AUTO    0u
#define CV_ALIGNED 1u
#define CV_BROKEN  2u
#define CV_SEL    16u

#define CV_PLAYING 1u
#define CV_MIDDLE  2u
#define CV_INSIDE  4u

struct CvRec { float2 a; float2 b; float c; float d; uint e; uint f; };

#ifdef CV_STATE_RW
RWStructuredBuffer<CvRec> S : register(u0);
#else
StructuredBuffer<CvRec> S : register(t0);
#endif

uint cvSlot(uint ch, uint i) { return CV_KEY0 + ch * CV_KMAX + i; }
CvRec cvKey(uint ch, uint i) { return S[cvSlot(ch, i)]; }

uint cvCount(uint packed, uint ch) { return (packed >> (5u * ch)) & 31u; }
uint cvWithCount(uint packed, uint ch, uint n) { return (packed & ~(31u << (5u * ch))) | (min(n, 31u) << (5u * ch)); }
bool cvHidden(uint packed, uint ch) { return ((packed >> (15u + ch)) & 1u) != 0u; }

uint cvInterp(uint e) { return e & 3u; }
uint cvHandles(uint e) { return (e >> 2) & 3u; }
bool cvSel(uint e) { return (e & CV_SEL) != 0u; }
uint cvWithInterp(uint e, uint m) { return (e & ~3u) | m; }
uint cvWithHandles(uint e, uint m) { return (e & ~12u) | (m << 2); }

float2 cvOut(CvRec k) { return float2(k.c, k.d); }

// ---------------------------------------------------------------- curve maths
// A bezier segment's control points. Each handle reaches at most the segment's length in time, and
// the two together at most the segment (scaled down along their own slopes), so x(s) is monotonic
// and the curve stays a function of time however the handles are dragged.
void cvSegCtl(CvRec k0, CvRec k1, out float2 p0, out float2 p1, out float2 p2, out float2 p3)
{
    float len = max(k1.a.x - k0.a.x, 1e-6);
    float2 o = cvOut(k0), i = k1.b;
    float ox = clamp(o.x, 0.0, len), ix = clamp(-i.x, 0.0, len);
    float k = (ox + ix > len) ? len / (ox + ix) : 1.0;
    float2 oo = (o.x > 1e-7) ? o * (ox * k / o.x) : float2(0.0, 0.0);
    float2 ii = (i.x < -1e-7) ? i * (ix * k / -i.x) : float2(0.0, 0.0);
    p0 = k0.a;
    p3 = k1.a;
    p1 = p0 + oo;
    p2 = p3 + ii;
}

float2 cvBez(float2 p0, float2 p1, float2 p2, float2 p3, float s)
{
    float u = 1.0 - s;
    return u * u * u * p0 + 3.0 * u * u * s * p1 + 3.0 * u * s * s * p2 + s * s * s * p3;
}

// the segment from k0 to k1 at time t (k0.t <= t <= k1.t)
float cvSegValue(CvRec k0, CvRec k1, float t)
{
    uint m = cvInterp(k0.e);
    if (m == CV_STEP) return k0.a.y;
    float u = saturate((t - k0.a.x) / max(k1.a.x - k0.a.x, 1e-6));
    if (m == CV_LINEAR) return lerp(k0.a.y, k1.a.y, u);
    float2 p0 = 0.0, p1 = 0.0, p2 = 0.0, p3 = 0.0;
    cvSegCtl(k0, k1, p0, p1, p2, p3);
    // x(s) is monotonic: bisect for the s whose x is t
    float lo = 0.0, hi = 1.0;
    [loop] for (int it = 0; it < 16; it++)
    {
        float s = 0.5 * (lo + hi);
        if (cvBez(p0, p1, p2, p3, s).x < t) lo = s; else hi = s;
    }
    return cvBez(p0, p1, p2, p3, 0.5 * (lo + hi)).y;
}

// a channel's value at time t: the first key's value before it, the last key's after it
float cvValue(uint ch, uint n, float t)
{
    if (n == 0u) return 0.0;
    CvRec k0 = cvKey(ch, 0u);
    if (n == 1u || t <= k0.a.x) return k0.a.y;
    CvRec kl = cvKey(ch, n - 1u);
    if (t >= kl.a.x) return kl.a.y;
    uint lo = 0u, hi = n - 1u;
    [loop] while (hi - lo > 1u)
    {
        uint mid = (lo + hi) >> 1;
        if (cvKey(ch, mid).a.x <= t) lo = mid; else hi = mid;
    }
    return cvSegValue(cvKey(ch, lo), cvKey(ch, hi), t);
}

// ---------------------------------------------------------------- geometry
struct CvLayout
{
    float4 head;
    float4 block;        // the plate behind everything below the header
    float4 inner;        // block minus its padding: split between graph and chart
    float4 list;         // channel list, left of the graph
    float4 row[CV_CH];   // one channel each
    float4 ruler;        // time ruler above the graph (click / drag: scrub)
    float4 graph;        // the curve plot
    float4 grip;         // the splitter's hit band
    float  splitAt;      // the splitter's y
    float4 chart;        // the spacing chart
    float4 stage;        // where the ball moves inside the chart
    float4 hint;         // the hint bar's row
};

#define CV_SPLIT_GAP 14.0

CvLayout cvLayout(float2 res, float s, float split)
{
    CvLayout L;
    float m = 16.0 * s;
    L.head = float4(m, 14.0 * s, res.x - m, 44.0 * s);
    L.hint = float4(m, res.y - 41.0 * s, res.x - m, res.y - 11.0 * s);
    L.block = float4(m, 54.0 * s, res.x - m, L.hint.y - 10.0 * s);
    L.inner = ilInset(L.block, 12.0 * s);
    ILSplit sp = ilSplitY(L.inner, split, 190.0 * s, 120.0 * s, CV_SPLIT_GAP * s, 7.0 * s);
    L.grip = sp.grip;
    L.splitAt = sp.at;
    L.chart = sp.b;
    float4 top = sp.a;
    L.list = float4(top.x, top.y, top.x + 172.0 * s, top.w);
    float rowH = 52.0 * s;
    [unroll] for (uint c = 0u; c < CV_CH; c++)
    {
        float y0 = L.list.y + 30.0 * s + c * (rowH + 6.0 * s);
        L.row[c] = float4(L.list.x, y0, L.list.z, y0 + rowH);
    }
    float gx = L.list.z + 14.0 * s;
    L.ruler = float4(gx, top.y, top.z, top.y + 22.0 * s);
    L.graph = float4(gx, L.ruler.w + 2.0 * s, top.z, top.w);
    L.stage = float4(L.chart.x + 172.0 * s + 14.0 * s, L.chart.y + 6.0 * s, L.chart.z - 8.0 * s, L.chart.w - 6.0 * s);
    return L;
}

// time / value <-> screen inside the graph
float cvX(CvLayout L, float2 tw, float t) { return L.graph.x + (t - tw.x) / max(tw.y - tw.x, 1e-6) * (L.graph.z - L.graph.x); }
float cvY(CvLayout L, float2 vw, float v) { return L.graph.w - (v - vw.x) / max(vw.y - vw.x, 1e-6) * (L.graph.w - L.graph.y); }
float cvT(CvLayout L, float2 tw, float x) { return tw.x + (x - L.graph.x) / max(L.graph.z - L.graph.x, 1.0) * (tw.y - tw.x); }
float cvV(CvLayout L, float2 vw, float y) { return vw.x + (L.graph.w - y) / max(L.graph.w - L.graph.y, 1.0) * (vw.y - vw.x); }
float2 cvP(CvLayout L, float2 tw, float2 vw, float2 w) { return float2(cvX(L, tw, w.x), cvY(L, vw, w.y)); }

// The spacing chart: travel across, height up, squash as an area-keeping squash and stretch.
// Returns the ball's centre; r = its radii.
float2 cvBall(CvLayout L, float s, float travel, float height, float squash, out float2 r)
{
    float4 st = L.stage;
    float rad = clamp((st.w - st.y) * 0.075, 5.0 * s, 16.0 * s);
    float sy = 1.0 + clamp(squash, -0.6, 0.6);
    r = float2(rad / sy, rad * sy);
    float ground = st.w - 4.0 * s;
    float apex = st.y + 2.0 * rad + 4.0 * s;
    float x = lerp(st.x + 2.0 * rad, st.z - 2.0 * rad, saturate(travel));
    return float2(x, ground - height * (ground - apex) - r.y);
}

// ghosts on twos: one every second frame of the loop (at most 49)
uint cvGhosts(float len, float fps) { return min((uint)floor(len * fps / 2.0 + 1e-3) + 1u, 49u); }
float cvGhostT(uint k, float fps) { return (float)k * 2.0 / fps; }

// ---------------------------------------------------------------- hit tests (reducer + hover)
// Whether key i's in / out handle is shown and draggable: only on a selected key, and only where
// the segment on that side is a bezier.
bool cvShowsIn(uint ch, uint n, uint i)  { return i > 0u && cvInterp(cvKey(ch, i - 1u).e) == CV_BEZIER; }
bool cvShowsOut(uint ch, uint n, uint i) { return i + 1u < n && cvInterp(cvKey(ch, i).e) == CV_BEZIER; }

// The handle tip as drawn: the stored vector, clamped the way the curve uses it.
float2 cvTipIn(uint ch, uint i)
{
    CvRec k = cvKey(ch, i), kp = cvKey(ch, i - 1u);
    float2 p0 = 0.0, p1 = 0.0, p2 = 0.0, p3 = 0.0;
    cvSegCtl(kp, k, p0, p1, p2, p3);
    return p2;
}
float2 cvTipOut(uint ch, uint i)
{
    CvRec k = cvKey(ch, i), kn = cvKey(ch, i + 1u);
    float2 p0 = 0.0, p1 = 0.0, p2 = 0.0, p3 = 0.0;
    cvSegCtl(k, kn, p0, p1, p2, p3);
    return p1;
}

// nearest key of a shown channel within reach px: returns ch * 16 + i, or 0xFFFF
uint cvHitKey(CvLayout L, float2 tw, float2 vw, uint packed, float2 p, float reach)
{
    uint best = 0xFFFFu;
    float bd = reach;
    [loop] for (uint ch = 0u; ch < CV_CH; ch++)
    {
        if (cvHidden(packed, ch)) continue;
        uint n = cvCount(packed, ch);
        [loop] for (uint i = 0u; i < n; i++)
        {
            float d = length(cvP(L, tw, vw, cvKey(ch, i).a) - p);
            if (d < bd) { bd = d; best = ch * CV_KMAX + i; }
        }
    }
    return best;
}

// nearest shown handle tip of a selected key: returns (ch * 16 + i) * 2 + (1 = out), or 0xFFFF
uint cvHitHandle(CvLayout L, float2 tw, float2 vw, uint packed, float2 p, float reach)
{
    uint best = 0xFFFFu;
    float bd = reach;
    [loop] for (uint ch = 0u; ch < CV_CH; ch++)
    {
        if (cvHidden(packed, ch)) continue;
        uint n = cvCount(packed, ch);
        [loop] for (uint i = 0u; i < n; i++)
        {
            if (!cvSel(cvKey(ch, i).e)) continue;
            if (cvShowsIn(ch, n, i))
            {
                float d = length(cvP(L, tw, vw, cvTipIn(ch, i)) - p);
                if (d < bd) { bd = d; best = (ch * CV_KMAX + i) * 2u; }
            }
            if (cvShowsOut(ch, n, i))
            {
                float d = length(cvP(L, tw, vw, cvTipOut(ch, i)) - p);
                if (d < bd) { bd = d; best = (ch * CV_KMAX + i) * 2u + 1u; }
            }
        }
    }
    return best;
}

// the shown channel whose curve passes nearest p (vertically) within reach px, or 0xFFFF
uint cvHitCurve(CvLayout L, float2 tw, float2 vw, uint packed, float2 p, float reach)
{
    uint best = 0xFFFFu;
    float bd = reach;
    float t = cvT(L, tw, p.x);
    [loop] for (uint ch = 0u; ch < CV_CH; ch++)
    {
        if (cvHidden(packed, ch)) continue;
        float d = abs(cvY(L, vw, cvValue(ch, cvCount(packed, ch), t)) - p.y);
        if (d < bd) { bd = d; best = ch; }
    }
    return best;
}

#endif
