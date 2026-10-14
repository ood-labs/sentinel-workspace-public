// Timeline - the editor's working state, its panes, and the hit tests every pass shares (the reducer
// hits exactly what the layout pass draws). The keys themselves and their evaluation are the Motion
// contract in ../_shared/timeline.hlsli.
//
// Working state, after the 167 saved records (never saved, never restored):
//   167 V0  (playhead frame, playing 0 | 1, speed index, working magic)   <- the program reads this
//   168 V1  (event watermark low 16 bits, high 16 bits, drag mode, drag target)
//   169 V2  (press x px, press y px, last drag x px, last drag y px)
//   170 V3  the shared time window (t0, t1) in frames, and the graph's value window (v0, v1)
//   171 V4  (stage | sheets split, dope | graph split, selected layer, active attribute)
//   172 V5  the drag's origin (what it was when it began; meaning per mode)
//   173 V6  (onion 0 | 1, the primary key's channel or -1, its frame, -)
//   174 V7  (cooks, Space held 0 | 1, -, -)
//   175..341 the undo snapshot of 0..166 - also every drag's origin, so a drag is "snapshot + delta"
//   342 U0  (1 when a snapshot exists)
#ifndef TL_HLSLI
#define TL_HLSLI

#ifdef TL_STATE_RW
RWStructuredBuffer<float4> S : register(u0);
#else
StructuredBuffer<float4> S : register(t0);
#endif
#define TL_BUF S
#include "../_shared/timeline.hlsli"

#define TL_V1     168u
#define TL_V2     169u
#define TL_V3     170u
#define TL_V4     171u
#define TL_V5     172u
#define TL_V6     173u
#define TL_V7     174u
#define TL_UNDO0  175u
#define TL_U0     342u
#define TL_COUNT  343u
#define TL_VMAGIC 11111.0
#define TL_ROWS   9u                 // four layers, and the selected layer's five channels under it

// drag modes (V1.z)
#define DM_NONE     0u
#define DM_MOVE     1u               // a layer on the stage: auto-keys x, y at the playhead
#define DM_SCALE    2u               // the selected layer's scale handle
#define DM_ROT      3u               // its rotation handle
#define DM_PATHKEY  4u               // a key dot on its motion path: that frame's x, y keys
#define DM_RETIME   5u               // keys in the dope sheet, along time
#define DM_BOX      6u               // a box select in the dope sheet
#define DM_SCRUB    7u               // the ruler
#define DM_LOOPIN   8u               // the loop's in marker
#define DM_LOOPOUT  9u               // its out marker
#define DM_GKEY     10u              // a key in the graph: value and time
#define DM_HANDLE   11u              // an ease influence handle in the graph
#define DM_PAN      12u              // the graph's value window
#define DM_FIELD    13u              // an inspector value field (auto-keys at the playhead)
#define DM_PARAM    14u              // an inspector parameter field (the primary key's p0 / p1)
#define DM_SPLITV   15u              // the stage | sheets splitter
#define DM_SPLITH   16u              // the dope | graph splitter

static const float TL_SPEEDS[4] = { 0.25, 0.5, 1.0, 2.0 };

float4 tlV0() { return S[TL_V0]; }
float  tlSelLayer() { return S[TL_V4].z; }

// ---------------------------------------------------------------- panes
struct TlLayout
{
    float4 head, hint, block, inner;
    float4 top, stageArea, stage, insp;
    float4 gripV; float splitVAt;
    float4 transport;
    float4 list, area, ruler, dope;
    float4 gripH; float splitHAt;
    float4 graph;
    float  rowH;
};

#define TL_GAP 14.0

TlLayout tlLayout(float2 res, float s, float2 split)
{
    TlLayout L;
    float m = 16.0 * s;
    L.head = float4(m, 14.0 * s, res.x - m, 44.0 * s);
    L.hint = float4(m, res.y - 41.0 * s, res.x - m, res.y - 11.0 * s);
    L.block = float4(m, 54.0 * s, res.x - m, L.hint.y - 10.0 * s);
    L.inner = ilInset(L.block, 12.0 * s);
    ILSplit v = ilSplitY(L.inner, split.x, 190.0 * s, 230.0 * s, TL_GAP * s, 7.0 * s);
    L.gripV = v.grip;
    L.splitVAt = v.at;
    L.top = v.a;
    L.insp = float4(L.top.z - 292.0 * s, L.top.y, L.top.z, L.top.w);
    L.stageArea = float4(L.top.x, L.top.y + 22.0 * s, L.insp.x - TL_GAP * s, L.top.w);
    float aw = L.stageArea.z - L.stageArea.x, ah = L.stageArea.w - L.stageArea.y;
    float h = min(ah, aw * 9.0 / 16.0), w = h * 16.0 / 9.0;
    float2 c = ilMid(L.stageArea);
    L.stage = float4(c.x - 0.5 * w, c.y - 0.5 * h, c.x + 0.5 * w, c.y + 0.5 * h);
    float4 bottom = v.b;
    L.transport = float4(bottom.x, bottom.y, bottom.z, bottom.y + 30.0 * s);
    float4 below = float4(bottom.x, L.transport.w + 8.0 * s, bottom.z, bottom.w);
    L.list = float4(below.x, below.y, below.x + 196.0 * s, below.w);
    L.area = float4(L.list.z + 12.0 * s, below.y, below.z, below.w);
    L.ruler = float4(L.area.x, L.area.y, L.area.z, L.area.y + 24.0 * s);
    float4 rest = float4(L.area.x, L.ruler.w + 2.0 * s, L.area.z, L.area.w);
    ILSplit hs = ilSplitY(rest, split.y, 9.0 * 15.0 * s, 80.0 * s, 12.0 * s, 6.0 * s);
    L.gripH = hs.grip;
    L.splitHAt = hs.at;
    L.dope = hs.a;
    L.graph = hs.b;
    L.rowH = clamp((L.dope.w - L.dope.y) / (float)TL_ROWS, 15.0 * s, 26.0 * s);
    return L;
}

// ---------------------------------------------------------------- the time and value axes
float tlX(TlLayout L, float2 tw, float f) { return L.area.x + (f - tw.x) / max(tw.y - tw.x, 1e-3) * (L.area.z - L.area.x); }
float tlF(TlLayout L, float2 tw, float x) { return tw.x + (x - L.area.x) / max(L.area.z - L.area.x, 1.0) * (tw.y - tw.x); }
float tlGY(TlLayout L, float2 vw, float v) { return L.graph.w - 6.0 - (v - vw.x) / max(vw.y - vw.x, 1e-6) * (L.graph.w - L.graph.y - 12.0); }
float tlGV(TlLayout L, float2 vw, float y) { return vw.x + (L.graph.w - 6.0 - y) / max(L.graph.w - L.graph.y - 12.0, 1.0) * (vw.y - vw.x); }

// ---------------------------------------------------------------- dope sheet rows
// rows: the four layers, the selected layer's five channels right under it
uint tlLayerRow(uint layer, uint sel) { return layer + (layer > sel ? TL_ATTRS : 0u); }
uint tlAttrRow(uint attr, uint sel) { return sel + 1u + attr; }
float4 tlRow(TlLayout L, uint row) { return float4(L.list.x, L.dope.y + row * L.rowH, L.area.z, L.dope.y + (row + 1u) * L.rowH); }
// what a row holds: x = 1 for a layer row, 0 for a channel row; y = the layer; z = the attribute
uint3 tlRowWhat(uint row, uint sel)
{
    if (row <= sel) return uint3(1u, row, 0u);
    if (row <= sel + TL_ATTRS) return uint3(0u, sel, row - sel - 1u);
    return uint3(1u, row - TL_ATTRS, 0u);
}
uint tlRowAt(TlLayout L, float y)
{
    if (y < L.dope.y || y >= L.dope.y + TL_ROWS * L.rowH) return 0xFFFFu;
    return min((uint)((y - L.dope.y) / L.rowH), TL_ROWS - 1u);
}

// ---------------------------------------------------------------- the stage
// the layer's reach from its centre (stage units), for its frame and handles
float tlReach(uint layer, float sc)
{
    sc = max(abs(sc), 1e-3);
    if (layer == TL_RING) return (TL_RING_R + TL_RING_W) * sc;
    if (layer == TL_SUN) return TL_SUN_R * sc;
    if (layer == TL_BLOCK) return TL_BLOCK_H * 1.41421 * sc;
    return TL_BAR_HALF.x * sc;
}
// the scale handle: up and right of the layer; the rotation handle: above it, turning with it
float2 tlScaleHandle(float4 x, uint layer) { return x.xy + tlReach(layer, x.z) * float2(0.7071, 0.7071) + float2(0.02, 0.02); }
float2 tlRotHandle(float4 x, uint layer) { float a = radians(x.w); return x.xy + float2(sin(a), cos(a)) * (tlReach(layer, x.z) + 0.075); }

// the frontmost layer whose shape (or its thin ring's band) is under stage point q, or 0xFFFF
uint tlPickLayer(float2 q, float f, float slack)
{
    [loop] for (uint l = 0u; l < TL_LAYERS; l++)
    {
        TlPose p = tlPose(l, f);
        if (p.opacity < 0.05) continue;
        if (tlSd(l, p.xfrm, q) < slack) return l;
    }
    return 0xFFFFu;
}

// ---------------------------------------------------------------- the inspector
float4 tlField(TlLayout L, uint attr, float s)   // a value field, one per attribute
{
    float y = L.insp.y + 52.0 * s + attr * 26.0 * s;
    return float4(L.insp.z - 116.0 * s, y, L.insp.z - 34.0 * s, y + 20.0 * s);
}
float2 tlKeyToggle(TlLayout L, uint attr, float s) { float4 f = tlField(L, attr, s); return float2(L.insp.z - 16.0 * s, ilMid(f).y); }
float4 tlModes(TlLayout L, float s) { float y = L.insp.y + 52.0 * s + 5.0 * 26.0 * s + 62.0 * s; return float4(L.insp.x + 8.0 * s, y, L.insp.z - 8.0 * s, y + 24.0 * s); }
float4 tlParamField(TlLayout L, uint i, float s) { float4 m = tlModes(L, s); float y = m.w + 10.0 * s + i * 26.0 * s; return float4(L.insp.z - 116.0 * s, y, L.insp.z - 34.0 * s, y + 20.0 * s); }

// ---------------------------------------------------------------- the transport
float4 tlPlayChip(TlLayout L, float s) { return float4(L.transport.x, L.transport.y + 2.0 * s, L.transport.x + 64.0 * s, L.transport.w - 2.0 * s); }
float4 tlSpeeds(TlLayout L, float s) { float x = L.transport.x + 264.0 * s; return float4(x, L.transport.y + 3.0 * s, x + 168.0 * s, L.transport.w - 3.0 * s); }
float4 tlOnionChip(TlLayout L, float s) { float x = L.transport.x + 448.0 * s; return float4(x, L.transport.y + 2.0 * s, x + 86.0 * s, L.transport.w - 2.0 * s); }

// ---------------------------------------------------------------- ruler markers
float2 tlLoopIn(TlLayout L, float2 tw)  { return float2(tlX(L, tw, tlP0().x), L.ruler.w - 6.0); }
float2 tlLoopOut(TlLayout L, float2 tw) { return float2(tlX(L, tw, tlP0().y), L.ruler.w - 6.0); }

// ---------------------------------------------------------------- dope / graph keys
// the key of a shown channel row nearest p within reach px: ch * 8 + i, or 0xFFFF
uint tlHitDopeKey(TlLayout L, float2 tw, uint sel, float2 p, float reach)
{
    uint row = tlRowAt(L, p.y);
    if (row == 0xFFFFu || p.x < L.area.x) return 0xFFFFu;
    uint3 w = tlRowWhat(row, sel);
    if (w.x == 1u) return 0xFFFFu;
    uint ch = w.y * TL_ATTRS + w.z, n = tlCount(ch), best = 0xFFFFu;
    float bd = reach;
    [loop] for (uint i = 0u; i < n; i++)
    {
        float d = abs(tlX(L, tw, tlKey(ch, i).x) - p.x);
        if (d < bd) { bd = d; best = ch * TL_KMAX + i; }
    }
    return best;
}

// a layer row's summary key under p: the frame (0..4095) + 4096 * layer, or 0xFFFF
uint tlHitSummary(TlLayout L, float2 tw, uint sel, float2 p, float reach)
{
    uint row = tlRowAt(L, p.y);
    if (row == 0xFFFFu || p.x < L.area.x) return 0xFFFFu;
    uint3 w = tlRowWhat(row, sel);
    if (w.x != 1u) return 0xFFFFu;
    float bd = reach, bf = -1.0;
    [loop] for (uint a = 0u; a < TL_ATTRS; a++)
    {
        uint ch = w.y * TL_ATTRS + a, n = tlCount(ch);
        [loop] for (uint i = 0u; i < n; i++)
        {
            float f = tlKey(ch, i).x, d = abs(tlX(L, tw, f) - p.x);
            if (d < bd) { bd = d; bf = f; }
        }
    }
    return bf < 0.0 ? 0xFFFFu : (uint)round(bf) + 4096u * w.y;
}

// the active channel's key nearest p in the graph, or 0xFFFF
uint tlHitGraphKey(TlLayout L, float2 tw, float2 vw, uint ch, float2 p, float reach)
{
    uint n = tlCount(ch), best = 0xFFFFu;
    float bd = reach;
    [loop] for (uint i = 0u; i < n; i++)
    {
        float4 k = tlKey(ch, i);
        float d = length(float2(tlX(L, tw, k.x), tlGY(L, vw, k.y)) - p);
        if (d < bd) { bd = d; best = i; }
    }
    return best;
}

// an ease handle's tip (graph px): out = the influence leaving key i, in = arriving at key i
bool tlHasOut(uint ch, uint i) { return i + 1u < tlCount(ch) && tlMode(tlKey(ch, i)) == TL_EASE; }
bool tlHasIn(uint ch, uint i)  { return i > 0u && tlMode(tlKey(ch, i - 1u)) == TL_EASE; }
float2 tlOutTip(TlLayout L, float2 tw, float2 vw, uint ch, uint i)
{
    float4 k = tlKey(ch, i), kn = tlKey(ch, i + 1u);
    return float2(tlX(L, tw, k.x + tlParams(k).x * (kn.x - k.x)), tlGY(L, vw, k.y));
}
float2 tlInTip(TlLayout L, float2 tw, float2 vw, uint ch, uint i)
{
    float4 k = tlKey(ch, i), kp = tlKey(ch, i - 1u);
    return float2(tlX(L, tw, k.x - tlParams(kp).y * (k.x - kp.x)), tlGY(L, vw, k.y));
}
// a selected key's handle nearest p: i * 2 + (1 = out), or 0xFFFF
uint tlHitHandle(TlLayout L, float2 tw, float2 vw, uint ch, float2 p, float reach)
{
    uint n = tlCount(ch), best = 0xFFFFu;
    float bd = reach;
    [loop] for (uint i = 0u; i < n; i++)
    {
        if (!tlSel(tlKey(ch, i))) continue;
        if (tlHasOut(ch, i)) { float d = length(tlOutTip(L, tw, vw, ch, i) - p); if (d < bd) { bd = d; best = i * 2u + 1u; } }
        if (tlHasIn(ch, i))  { float d = length(tlInTip(L, tw, vw, ch, i) - p);  if (d < bd) { bd = d; best = i * 2u; } }
    }
    return best;
}

// the frames where the selected layer's x or y has a key: its motion path's key dots
// (returns the count; frames written to f[] in order, at most 16)
uint tlPathKeys(uint layer, out float f[16])
{
    uint n = 0u;
    [unroll] for (uint z = 0u; z < 16u; z++) f[z] = 0.0;
    uint cx = layer * TL_ATTRS, cy = cx + 1u;
    uint nx = tlCount(cx), ny = tlCount(cy), ix = 0u, iy = 0u;
    [loop] for (uint it = 0u; it < 16u && (ix < nx || iy < ny); it++)
    {
        float fx = ix < nx ? tlKey(cx, ix).x : 1e9, fy = iy < ny ? tlKey(cy, iy).x : 1e9;
        float fm = min(fx, fy);
        f[n] = fm;
        n++;
        if (abs(fx - fm) < 0.5) ix++;
        if (abs(fy - fm) < 0.5) iy++;
    }
    return n;
}

#endif
