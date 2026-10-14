// Score - the editor's working state, its panes, and the hit tests every pass shares (the reducer
// hits exactly what the layout pass draws). The show itself, the rail and the hall are the Score
// contract in ../_shared/score.hlsli.
//
// Working state, after the 114 saved records (never saved, never restored):
//   114 V0  (time s, playing 0 | 1, loop 0 show | 1 act, working magic)
//   115 V1  (event watermark low 16 bits, high 16 bits, drag mode, drag target)
//   116 V2  (press x px, press y px, last drag x px, last drag y px)
//   117 V3  (selected act, selected mark or item (-1: none), Space held 0 | 1, cooks)
//   118 V4  (space | right split, upper | lower split, the lane's seconds frozen for a drag, -)
//   119 V5  the drag's origin (what it was when it began; meaning per mode)
//   120 V6  more of it
//   121..126 R0..R5  what the playhead resolves to (score.hlsli)
//   127..240 the undo snapshot of 0..113 - also every drag's origin, so a drag is "snapshot + delta"
//   241 U0  (1 when a snapshot exists)
#ifndef SC_HLSLI
#define SC_HLSLI

#ifdef SC_STATE_RW
RWStructuredBuffer<float4> S : register(u0);
#else
StructuredBuffer<float4> S : register(t0);
#endif
#define SC_BUF S
#include "../_shared/score.hlsli"

#define SC_V1     115u
#define SC_V2     116u
#define SC_V3     117u
#define SC_V4     118u
#define SC_V5     119u
#define SC_V6     120u
#define SC_UNDO0  127u
#define SC_U0     241u
#define SC_COUNT  242u
#define SC_VMAGIC 31313.0

// drag modes (V1.z)
#define DM_NONE     0u
#define DM_SCRUB    1u     // the ruler
#define DM_MOVEACT  2u     // an act along the lane: reorder (applied on release)
#define DM_RESIZE   3u     // an act's right edge: its duration
#define DM_TICK     4u     // a mark's tick in the lane: when it is reached
#define DM_EYE_P    5u     // a mark's eye in the plan: x, z
#define DM_AIM_P    6u     // its target in the plan
#define DM_EYE_E    7u     // its eye in the elevation: y, z
#define DM_AIM_E    8u     // its target in the elevation
#define DM_LOOK     9u     // the view: turn the selected mark's aim about its eye
#define DM_ITEM     10u    // a card item on the stage
#define DM_ISIZE    11u    // a card item's size handle
#define DM_FIELD    12u    // an inspector field
#define DM_SPLITX   13u
#define DM_SPLITY   14u

// inspector fields
#define F_AT    0u
#define F_FOV   1u
#define F_EX    2u
#define F_EY    3u
#define F_EZ    4u
#define F_TX    5u
#define F_TY    6u
#define F_TZ    7u
#define F_IX    8u
#define F_IY    9u
#define F_IS    10u
#define F_DUR   11u
#define F_HLEN  12u
#define F_COUNT 13u

#define SC_GAP 14.0

// ---------------------------------------------------------------- what a moment of the show resolves to
// The rail whose first frame the camera holds through card a: the next rail after it (0xFFFF: none).
uint scHoldRail(uint a)
{
    uint n = scActs();
    uint r = 0xFFFFu;
    [loop] for (uint i = SC_ACTS; i > 0u; i--)
    {
        uint b = (a + i) % n;
        r = (i <= n && scKind(b) == SC_RAIL) ? b : r;
    }
    return r;
}

struct ScShow { uint A; uint B; float tA; float u; uint hk; ScPose pose; };

// The act showing at `time`, the act it hands off to (B == A outside a hand-off), how far through the
// hand-off (u), and the one camera. When the show loops, the last act hands off to the first; when
// only an act loops, nothing hands off. Between rails a glide blends one pose into the next one's
// first mark; a dip changes pose in the dark at its middle; a card holds the next rail's first pose.
ScShow scResolve(float time, bool loopShow)
{
    ScShow r;
    uint n = scActs();
    r.A = n - 1u;
    r.tA = scDur(r.A);
    float t0 = 0.0;
    [loop] for (uint a = 0u; a < SC_ACTS; a++)
    {
        float d = (a < n) ? scDur(a) : 0.0;
        if (a < n && time >= t0 && time < t0 + d) { r.A = a; r.tA = time - t0; }
        t0 += d;
    }
    bool hasNext = loopShow && n > 1u;
    r.hk = scHand(r.A);
    float hl = scHandLen(r.A);
    r.u = (hasNext && r.hk != SC_CUT && hl > 0.0) ? saturate((r.tA - (scDur(r.A) - hl)) / hl) : 0.0;
    r.B = (r.u > 0.0) ? (r.A + 1u) % n : r.A;
    bool railA = scKind(r.A) == SC_RAIL;
    uint ra = railA ? r.A : scHoldRail(r.A);
    bool toB = r.u > 0.0 && scKind(r.B) == SC_RAIL;
    ScPose pA, pB;
    pA.eye = float3(0.0, 1.7, -3.0);                     // no rail anywhere: a plain view down the hall
    pA.target = float3(0.0, 1.6, 12.0);
    pA.fov = 50.0;
    pB = pA;
    [loop] for (uint j = 0u; j < 2u; j++)                // one scPose, compiled once: A's pose, then B's first
    {
        bool want = (j == 0u) ? ra != 0xFFFFu : toB;
        ScPose q = scPose((j == 0u) ? min(ra, SC_ACTS - 1u) : r.B, (j == 0u && railA) ? r.tA : 0.0);
        if (want && j == 0u) pA = q;
        if (want && j == 1u) pB = q;
    }
    r.pose = pA;
    if (toB)
    {
        if (r.hk == SC_GLIDE && railA) r.pose = scLerpPose(pA, pB, smoothstep(0.0, 1.0, r.u));
        else if (r.hk == SC_GLIDE || r.u >= 0.5) r.pose = pB;
    }
    return r;
}

// ---------------------------------------------------------------- panes
struct ScLayout
{
    float4 head, hint, block, inner, tools;
    float4 upper, lower, gripX, gripY;
    float  splitXAt, splitYAt;
    float4 space, plan, elev, stage;
    float  k;                                // px per metre in the plan and the elevation
    float4 viewPane, view, insp;
    float4 acts, ruler, lane, track, actInsp;   // track: the camera over the show (height, then lens)
};

ScLayout scLayout(float2 res, float s, float2 split)
{
    ScLayout L;
    float m = 16.0 * s;
    L.head = float4(m, 14.0 * s, res.x - m, 44.0 * s);
    L.hint = float4(m, res.y - 41.0 * s, res.x - m, res.y - 11.0 * s);
    L.block = float4(m, 54.0 * s, res.x - m, L.hint.y - 10.0 * s);
    L.inner = ilInset(L.block, 12.0 * s);
    L.tools = float4(L.inner.x, L.inner.y, L.inner.z, L.inner.y + 28.0 * s);
    float4 rest = float4(L.inner.x, L.tools.w + 12.0 * s, L.inner.z, L.inner.w);
    ILSplit ys = ilSplitY(rest, split.y, 330.0 * s, 240.0 * s, SC_GAP * s, 7.0 * s);
    L.gripY = ys.grip;
    L.splitYAt = ys.at;
    L.upper = ys.a;
    L.lower = ys.b;
    ILSplit xs = ilSplitX(L.upper, split.x, 440.0 * s, 330.0 * s, SC_GAP * s, 7.0 * s);
    L.gripX = xs.grip;
    L.splitXAt = xs.at;
    L.space = xs.a;
    float4 right = xs.b;

    // SPACE: the plan over the elevation, sharing the z axis across (rails), or the stage (cards)
    float4 body = float4(L.space.x + 10.0 * s, L.space.y + 32.0 * s, L.space.z - 10.0 * s, L.space.w - 8.0 * s);
    float zx0 = body.x + 30.0 * s;
    float cap = 16.0 * s;
    L.k = max(min((body.z - zx0 - 4.0 * s) / (SC_Z1 - SC_Z0), (body.w - body.y - 2.0 * cap - 10.0 * s) / ((SC_X1 - SC_X0) + (SC_Y1 - SC_Y0))), 1.0);
    L.plan = float4(zx0, body.y + cap, zx0 + (SC_Z1 - SC_Z0) * L.k, body.y + cap + (SC_X1 - SC_X0) * L.k);
    L.elev = float4(zx0, L.plan.w + 10.0 * s + cap, zx0 + (SC_Z1 - SC_Z0) * L.k, L.plan.w + 10.0 * s + cap + (SC_Y1 - SC_Y0) * L.k);
    float bw = body.z - body.x, bh = body.w - body.y;
    float sh = min(bh, bw * 9.0 / 16.0);
    float2 bc = ilMid(body);
    L.stage = float4(bc.x - sh * 8.0 / 9.0, bc.y - 0.5 * sh, bc.x + sh * 8.0 / 9.0, bc.y + 0.5 * sh);

    // VIEW: the camera at the playhead, 16:9, its readouts under it; the MARK / ITEM inspector below
    float vw = right.z - right.x - 16.0 * s;
    float vhRoom = (right.w - right.y) - 34.0 * s - 28.0 * s - 150.0 * s - SC_GAP * s;
    float fw = max(min(vw, vhRoom * 16.0 / 9.0), 64.0 * s);
    float fh = fw * 9.0 / 16.0;
    float cx = 0.5 * (right.x + right.z);
    L.view = float4(cx - 0.5 * fw, right.y + 34.0 * s, cx + 0.5 * fw, right.y + 34.0 * s + fh);
    L.viewPane = float4(right.x, right.y, right.z, L.view.w + 28.0 * s);
    L.insp = float4(right.x, L.viewPane.w + SC_GAP * s, right.z, right.w);

    // ACTS: the ruler and the lane of acts; the ACT inspector at its right
    L.actInsp = float4(L.lower.z - 310.0 * s, L.lower.y, L.lower.z, L.lower.w);
    L.acts = float4(L.lower.x, L.lower.y, L.actInsp.x - SC_GAP * s, L.lower.w);
    L.ruler = float4(L.acts.x + 14.0 * s, L.acts.y + 34.0 * s, L.acts.z - 14.0 * s, L.acts.y + 54.0 * s);
    L.lane = float4(L.ruler.x, L.ruler.w + 6.0 * s, L.ruler.z, min(L.ruler.w + 6.0 * s + 74.0 * s, L.acts.w - 12.0 * s));
    // the camera over the show, when there is room for both of its strips
    float ty = L.lane.w + 12.0 * s;
    L.track = (L.acts.w - 12.0 * s - ty >= 64.0 * s) ? float4(L.lane.x, ty, L.lane.z, L.acts.w - 12.0 * s) : float4(L.lane.x, ty, L.lane.z, ty);
    return L;
}

// ---------------------------------------------------------------- the show's time axis (the lane)
float scLaneSecs(float frozen) { return (frozen > 0.0) ? frozen : max(scTotal(), 4.0); }
float scTX(ScLayout L, float secs, float t) { return L.lane.x + t / secs * (L.lane.z - L.lane.x); }
float scXT(ScLayout L, float secs, float x) { return (x - L.lane.x) / max(L.lane.z - L.lane.x, 1.0) * secs; }
// the act whose block holds lane x, or 0xFFFF
uint scActAtX(ScLayout L, float secs, float x)
{
    float t = scXT(L, secs, x);
    uint hit = 0xFFFFu;
    float t0 = 0.0;
    [loop] for (uint a = 0u; a < SC_ACTS; a++)
    {
        float d = (a < scActs()) ? scDur(a) : 0.0;
        hit = (a < scActs() && t >= t0 && t < t0 + d) ? a : hit;
        t0 += d;
    }
    return hit;
}
// mark ticks sit in the lane's lower band
float4 scTickBand(ScLayout L, float s) { return float4(L.lane.x, L.lane.w - 18.0 * s, L.lane.z, L.lane.w); }

// ---------------------------------------------------------------- plan and elevation (metres <-> px)
// The plan looks down with the hall running left to right: z across, +x DOWN the screen (a camera
// facing +z has +x on its right). The elevation looks from -x: z across, y up.
float2 scPlanP(ScLayout L, float x, float z) { return float2(L.plan.x + (z - SC_Z0) * L.k, L.plan.y + (x - SC_X0) * L.k); }
float2 scElevP(ScLayout L, float y, float z) { return float2(L.elev.x + (z - SC_Z0) * L.k, L.elev.w - (y - SC_Y0) * L.k); }
float2 scPlanW(ScLayout L, float2 p) { return float2(SC_X0 + (p.y - L.plan.y) / L.k, SC_Z0 + (p.x - L.plan.x) / L.k); }   // (x, z)
float2 scElevW(ScLayout L, float2 p) { return float2(SC_Y0 + (L.elev.w - p.y) / L.k, SC_Z0 + (p.x - L.elev.x) / L.k); }   // (y, z)

// ---------------------------------------------------------------- the card stage (stage units <-> px)
float  scStageH(ScLayout L) { return L.stage.w - L.stage.y; }
float2 scStageP(ScLayout L, float2 q) { float2 c = ilMid(L.stage); return float2(c.x + q.x * scStageH(L), c.y - q.y * scStageH(L)); }
float2 scStageQ(ScLayout L, float2 p) { float2 c = ilMid(L.stage); return float2((p.x - c.x) / scStageH(L), (c.y - p.y) / scStageH(L)); }

// ---------------------------------------------------------------- the view (a pose -> the 16:9 frame)
struct ScCam { float3 eye, f, r, u; float th; float aspect; };
ScCam scCam(ScPose p, float aspect)
{
    ScCam c;
    c.eye = p.eye;
    float3 d = p.target - p.eye;
    c.f = (dot(d, d) > 1e-8) ? normalize(d) : float3(0.0, 0.0, 1.0);
    float3 r = cross(float3(0.0, 1.0, 0.0), c.f);
    c.r = (dot(r, r) > 1e-8) ? normalize(r) : float3(1.0, 0.0, 0.0);
    c.u = cross(c.f, c.r);
    c.th = tan(radians(p.fov) * 0.5);
    c.aspect = aspect;
    return c;
}
float3 scToCam(ScCam c, float3 p) { float3 d = p - c.eye; return float3(dot(d, c.r), dot(d, c.u), dot(d, c.f)); }
float2 scCamPx(ScLayout L, ScCam c, float3 q)
{
    float2 n = float2(q.x / (q.z * c.th * c.aspect), q.y / (q.z * c.th));
    return float2(lerp(L.view.x, L.view.z, 0.5 + 0.5 * n.x), lerp(L.view.w, L.view.y, 0.5 + 0.5 * n.y));
}

// ---------------------------------------------------------------- inspector fields
// MARK (rails) / ITEM (cards) under the view, two columns; ACT at the lane's right
float4 scField(ScLayout L, uint f, float s)
{
    float4 r = float4(0.0, 0.0, 0.0, 0.0);
    float4 b = float4(L.insp.x + 12.0 * s, L.insp.y + 34.0 * s, L.insp.z - 12.0 * s, L.insp.w);
    float cw = 0.5 * (b.z - b.x - 12.0 * s);
    float rh = 28.0 * s;
    if (f <= F_TZ)
    {
        uint col = (f == F_AT || f == F_EX || f == F_EY || f == F_EZ) ? 0u : 1u;
        uint row = (f == F_AT || f == F_FOV) ? 0u : ((f == F_EX || f == F_TX) ? 1u : ((f == F_EY || f == F_TY) ? 2u : 3u));
        float x0 = b.x + col * (cw + 12.0 * s);
        r = float4(x0, b.y + row * rh + 4.0 * s, x0 + cw, b.y + row * rh + 28.0 * s);
    }
    else if (f <= F_IS)
    {
        uint i = f - F_IX;
        float x0 = b.x + (i % 2u) * (cw + 12.0 * s);
        float y0 = b.y + (i / 2u) * rh + 4.0 * s;
        r = float4(x0, y0, x0 + cw, y0 + 24.0 * s);
    }
    else
    {
        float4 a = float4(L.actInsp.x + 12.0 * s, L.actInsp.y + 34.0 * s, L.actInsp.z - 12.0 * s, L.actInsp.w);
        float hw = 0.5 * (a.z - a.x - 10.0 * s);
        float x0 = a.x + (f - F_DUR) * (hw + 10.0 * s);
        r = float4(x0, a.y + 50.0 * s, x0 + hw, a.y + 74.0 * s);
    }
    return r;
}
// the ACT inspector's rows: 0 kind (left) and 2 light (right) side by side, then the two lengths
// (scField), then 1 the hand-off across, then - a card - 3 its word across
float4 scActRow(ScLayout L, uint row, float s)
{
    float4 a = float4(L.actInsp.x + 12.0 * s, L.actInsp.y + 34.0 * s, L.actInsp.z - 12.0 * s, L.actInsp.w);
    float hw = 0.5 * (a.z - a.x - 10.0 * s);
    float4 r = float4(a.x, a.y + 98.0 * s, a.z, a.y + 122.0 * s);
    if (row == 0u) r = float4(a.x, a.y + 14.0 * s, a.x + hw, a.y + 38.0 * s);
    else if (row == 2u) r = float4(a.z - hw, a.y + 14.0 * s, a.z, a.y + 38.0 * s);
    else if (row == 3u) r = float4(a.x, a.y + 132.0 * s, a.z, a.y + 156.0 * s);
    return r;
}
// the ruler and the camera track both scrub
bool scInScrub(ScLayout L, float2 p, float s)
{
    return ilIn(p, float4(L.ruler.x, L.ruler.y - 4.0 * s, L.ruler.z, L.ruler.w)) || (L.track.w > L.track.y && ilIn(p, L.track));
}
// the item inspector's SHOWN chip
float4 scShownChip(ScLayout L, float s)
{
    float4 f = scField(L, F_IS, s);
    return float4(f.z + 12.0 * s, f.y, L.insp.z - 12.0 * s, f.w);
}
// the tools row: PLAY chip, LOOP segmented
float4 scPlayChip(ScLayout L, float s) { return float4(L.tools.x, L.tools.y, L.tools.x + 88.0 * s, L.tools.w); }
float4 scLoopSeg(ScLayout L, float s)  { return float4(L.tools.x + 100.0 * s, L.tools.y, L.tools.x + 256.0 * s, L.tools.w); }

// ---------------------------------------------------------------- card items: where they sit and grab
// A word's width per unit of its cap height (W_0..W_5 in labels.txt, from the label tables: em /
// cap = 48 / 33.5 times the run's width per em). The words never change; regenerate these if they do.
float scWordW(uint w)
{
    float perEm = (w == 0u) ? 4.836 : ((w == 1u) ? 5.357 : ((w == 2u) ? 5.065 : ((w == 3u) ? 4.553 : ((w == 4u) ? 3.677 : 2.753))));
    return SC_EM_PER_CAP * perEm;
}
// the text size (em, px) that gives a cap height of cap px
float scCapToEm(float cap) { return cap * SC_EM_PER_CAP; }
// (half width, half height) px of item k: the word's box, the disc's radius, the bar
float2 scItemHalf(ScLayout L, uint k, float4 it, uint word)
{
    float h = scStageH(L);
    return (k == 0u) ? float2(0.5 * scWordW(word) * it.z * h, 0.5 * it.z * h) : ((k == 1u) ? it.zz * h : float2(it.z * h, SC_BAR_HT * h));
}
// the corner handle that sizes it
float2 scItemHandle(ScLayout L, uint k, float4 it, uint word)
{
    float2 c = scStageP(L, it.xy);
    float2 hx = scItemHalf(L, k, it, word);
    return (k == 1u) ? c + float2(0.7071, -0.7071) * hx.x : c + float2(hx.x, -hx.y);
}
bool scItemHit(ScLayout L, uint k, float4 it, uint word, float2 p, float s)
{
    float2 c = scStageP(L, it.xy);
    float2 hx = scItemHalf(L, k, it, word);
    bool box = all(abs(p - c) <= hx + 6.0 * s);
    return (k == 1u) ? length(p - c) <= hx.x + 6.0 * s : box;
}

#endif
