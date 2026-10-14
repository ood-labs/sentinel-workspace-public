// Curve Desk / reduce - one thread: the viewport events, then the playhead and the auto handles.
//
//   drag a key          move it with every selected key (time snaps to frames; keys never cross)
//   drag a handle       shape the segment; an auto handle becomes aligned (equal slopes both sides)
//   drag empty graph    box select        click a key: select it (Shift: toggle), empty: clear
//   double-click curve  add a key on that curve, where you clicked
//   Backspace           remove the selected keys (a channel keeps its last one)
//   1 2 3               step / linear / bezier for the segments leaving the selected keys
//   A / B               auto handles / break them (again: re-align)
//   arrows              nudge the selection a frame / 0.01          Esc: clear the selection
//   F, wheel            frame the loop and every shown key / zoom about the pointer
//   middle drag         pan                                         Space: play / pause
//   ruler, chart        click or drag: scrub (pauses)               channel row: show / hide
//   splitter            drag: share the height between graph and chart
//   R                   back to the default ball (Z brings the edit back)
//   Z                   undo the last edit (again: redo)
#define CV_STATE_RW
#include "../_shared/ui/il_core.hlsli"
#include "../_shared/ui/il_events.hlsli"
#include "../_shared/ui/il_pane.hlsli"
#include "curve.hlsli"

#define DM_NONE   0u
#define DM_KEY    1u
#define DM_HANDLE 2u
#define DM_BOX    3u
#define DM_SCRUB  4u
#define DM_CHART  5u
#define DM_SPLIT  6u
#define DM_PAN    7u

static float2 g_tw, g_vw;
static uint g_packed;
static float g_len, g_fps;

// ---------------------------------------------------------------- undo
void snapshot()
{
    [loop] for (uint i = 0u; i < CV_CH * CV_KMAX; i++) S[CV_UNDO0 + i] = S[CV_KEY0 + i];
    CvRec u0 = S[CV_U0];
    u0.e = g_packed & 0x7FFFu;
    u0.f = 1u;
    S[CV_U0] = u0;
}

void swapUndo()
{
    CvRec u0 = S[CV_U0];
    if (u0.f == 0u) return;
    [loop] for (uint i = 0u; i < CV_CH * CV_KMAX; i++)
    {
        CvRec a = S[CV_KEY0 + i];
        S[CV_KEY0 + i] = S[CV_UNDO0 + i];
        S[CV_UNDO0 + i] = a;
    }
    uint counts = g_packed & 0x7FFFu;
    g_packed = (g_packed & ~0x7FFFu) | (u0.e & 0x7FFFu);
    u0.e = counts;
    S[CV_U0] = u0;
}

// a cancelled drag: back to where it began (the snapshot stays, so Z still has it)
void restoreSnapshot()
{
    [loop] for (uint i = 0u; i < CV_CH * CV_KMAX; i++) S[CV_KEY0 + i] = S[CV_UNDO0 + i];
}

// ---------------------------------------------------------------- the default: a bouncing ball
CvRec key24(float frame, float v, uint interp, uint handles)
{
    CvRec k = (CvRec)0;
    k.a = float2(frame / 24.0, v);
    k.e = interp | (handles << 2);
    return k;
}

// a contact: broken handles carrying the arriving and leaving slopes of two parabolas
CvRec contact(float frame, float slopeIn, float spanIn, float slopeOut, float spanOut)
{
    CvRec k = key24(frame, 0.0, CV_BEZIER, CV_BROKEN);
    k.b = float2(-spanIn / 3.0, -slopeIn * spanIn / 3.0);
    k.c = spanOut / 3.0;
    k.d = slopeOut * spanOut / 3.0;
    return k;
}

void writeDefaults()
{
    // travel: across at a steady speed, then a short roll to rest
    S[cvSlot(0u, 0u)] = key24(0.0, 0.06, CV_LINEAR, CV_AUTO);
    CvRec roll = key24(42.0, 0.82, CV_BEZIER, CV_ALIGNED);
    float speed = (0.82 - 0.06) / (42.0 / 24.0);
    roll.b = float2(-0.25, -0.25 * speed);
    roll.c = 0.25 / 3.0;
    roll.d = speed * 0.25 / 3.0;
    S[cvSlot(0u, 1u)] = roll;
    S[cvSlot(0u, 2u)] = key24(48.0, 0.875, CV_BEZIER, CV_AUTO);
    // height: a drop and two rebounds, each apex-to-ground time and height on one parabola family
    S[cvSlot(1u, 0u)] = key24(0.0, 1.0, CV_BEZIER, CV_AUTO);
    S[cvSlot(1u, 1u)] = contact(12.0, -4.0, 0.5, 3.0, 0.375);
    S[cvSlot(1u, 2u)] = key24(21.0, 0.5625, CV_BEZIER, CV_AUTO);
    S[cvSlot(1u, 3u)] = contact(30.0, -3.0, 0.375, 2.0, 0.25);
    S[cvSlot(1u, 4u)] = key24(36.0, 0.25, CV_BEZIER, CV_AUTO);
    S[cvSlot(1u, 5u)] = contact(42.0, -2.0, 0.25, 0.0, 0.25);
    // squash: stretch falling in, squash on the contact, stretch leaving - smaller each time
    static const float SQ_F[12] = { 0.0, 10.0, 12.0, 14.0, 21.0, 28.0, 30.0, 32.0, 36.0, 40.0, 42.0, 45.0 };
    static const float SQ_V[12] = { 0.0, 0.22, -0.42, 0.16, 0.0, 0.15, -0.28, 0.10, 0.0, 0.08, -0.16, 0.0 };
    [loop] for (uint i = 0u; i < 12u; i++) S[cvSlot(2u, i)] = key24(SQ_F[i], SQ_V[i], CV_BEZIER, CV_AUTO);
    g_packed = (g_packed & ~0x7FFFu) | cvWithCount(cvWithCount(cvWithCount(0u, 0u, 3u), 1u, 6u), 2u, 12u);
}

// ---------------------------------------------------------------- edits
float frameGap() { return 1.0 / g_fps; }

// How far the selection may move in time, read from the records at base: a selected key is held
// a frame away from an unselected neighbour and inside the loop; selected neighbours move with it.
float2 allowedDt(uint base)
{
    float2 r = float2(-1e6, 1e6);
    [loop] for (uint ch = 0u; ch < CV_CH; ch++)
    {
        uint n = cvCount(g_packed, ch);
        [loop] for (uint i = 0u; i < n; i++)
        {
            CvRec k = S[base + ch * CV_KMAX + i];
            if (!cvSel(k.e)) continue;
            float lo = 0.0, hi = g_len;
            if (i > 0u)
            {
                CvRec kp = S[base + ch * CV_KMAX + i - 1u];
                if (!cvSel(kp.e)) lo = kp.a.x + frameGap();
            }
            if (i + 1u < n)
            {
                CvRec kn = S[base + ch * CV_KMAX + i + 1u];
                if (!cvSel(kn.e)) hi = kn.a.x - frameGap();
            }
            r.x = max(r.x, lo - k.a.x);
            r.y = min(r.y, hi - k.a.x);
        }
    }
    if (r.x > r.y) r = 0.0;
    return r;
}

// move every selected key to (its record at base) + d
void moveSelection(uint base, float2 d)
{
    [loop] for (uint ch = 0u; ch < CV_CH; ch++)
    {
        uint n = cvCount(g_packed, ch);
        [loop] for (uint i = 0u; i < n; i++)
        {
            CvRec k = S[base + ch * CV_KMAX + i];
            if (!cvSel(k.e)) continue;
            k.a += d;
            S[cvSlot(ch, i)] = k;
        }
    }
}

uint selectionCount()
{
    uint c = 0u;
    [loop] for (uint ch = 0u; ch < CV_CH; ch++)
    {
        uint n = cvCount(g_packed, ch);
        [loop] for (uint i = 0u; i < n; i++) c += cvSel(cvKey(ch, i).e) ? 1u : 0u;
    }
    return c;
}

void setSelected(uint ch, uint i, bool on)
{
    CvRec k = S[cvSlot(ch, i)];
    k.e = on ? (k.e | CV_SEL) : (k.e & ~CV_SEL);
    S[cvSlot(ch, i)] = k;
}

void clearSelection()
{
    [loop] for (uint ch = 0u; ch < CV_CH; ch++)
    {
        uint n = cvCount(g_packed, ch);
        [loop] for (uint i = 0u; i < n; i++) setSelected(ch, i, false);
    }
}

// interpolation (op 0) or handle mode (op 1) for every selected key
void setMode(uint op, uint m)
{
    [loop] for (uint ch = 0u; ch < CV_CH; ch++)
    {
        uint n = cvCount(g_packed, ch);
        [loop] for (uint i = 0u; i < n; i++)
        {
            CvRec k = S[cvSlot(ch, i)];
            if (!cvSel(k.e)) continue;
            k.e = (op == 0u) ? cvWithInterp(k.e, m) : cvWithHandles(k.e, m);
            S[cvSlot(ch, i)] = k;
        }
    }
}

// B: break every selected key's handles, or re-align them when all are broken already
void toggleBroken()
{
    bool allBroken = true;
    [loop] for (uint ch = 0u; ch < CV_CH; ch++)
    {
        uint n = cvCount(g_packed, ch);
        [loop] for (uint i = 0u; i < n; i++)
        {
            CvRec k = cvKey(ch, i);
            if (cvSel(k.e) && cvHandles(k.e) != CV_BROKEN) allBroken = false;
        }
    }
    setMode(1u, allBroken ? CV_ALIGNED : CV_BROKEN);
    if (!allBroken) return;
    // re-aligned: the out handle takes the in handle's slope
    [loop] for (uint c2 = 0u; c2 < CV_CH; c2++)
    {
        uint n = cvCount(g_packed, c2);
        [loop] for (uint i = 0u; i < n; i++)
        {
            CvRec k = S[cvSlot(c2, i)];
            if (!cvSel(k.e) || k.b.x > -1e-6) continue;
            k.d = k.c * (k.b.y / k.b.x);
            S[cvSlot(c2, i)] = k;
        }
    }
}

void deleteSelection()
{
    [loop] for (uint ch = 0u; ch < CV_CH; ch++)
    {
        uint n = cvCount(g_packed, ch);
        uint w = 0u;
        [loop] for (uint i = 0u; i < n; i++)
        {
            CvRec k = S[cvSlot(ch, i)];
            if (cvSel(k.e)) continue;
            S[cvSlot(ch, w)] = k;
            w++;
        }
        if (w == 0u && n > 0u)
        {
            // every key was selected: keep the first (nothing was written over it)
            setSelected(ch, 0u, false);
            w = 1u;
        }
        g_packed = cvWithCount(g_packed, ch, w);
    }
}

// a new key on channel ch at (t, v), selected alone; it takes the interpolation of the segment it splits
void insertKey(uint ch, float t, float v)
{
    uint n = cvCount(g_packed, ch);
    if (n >= CV_KMAX) return;
    uint at = 0u;
    [loop] while (at < n && cvKey(ch, at).a.x < t) at++;
    float g = 0.5 * frameGap();
    if (at < n && abs(cvKey(ch, at).a.x - t) < g) return;
    if (at > 0u && abs(cvKey(ch, at - 1u).a.x - t) < g) return;
    snapshot();
    clearSelection();
    [loop] for (uint j = n; j > at; j--) S[cvSlot(ch, j)] = S[cvSlot(ch, j - 1u)];
    CvRec k = (CvRec)0;
    k.a = float2(t, v);
    uint interp = (at > 0u) ? cvInterp(cvKey(ch, at - 1u).e) : CV_BEZIER;
    k.e = interp | (CV_AUTO << 2) | CV_SEL;
    S[cvSlot(ch, at)] = k;
    g_packed = cvWithCount(g_packed, ch, n + 1u);
}

// F: the loop and every shown key and handle tip, with a margin
void frameAll()
{
    float2 tr = float2(0.0, g_len), vr = float2(0.0, 1.0);
    [loop] for (uint ch = 0u; ch < CV_CH; ch++)
    {
        if (cvHidden(g_packed, ch)) continue;
        uint n = cvCount(g_packed, ch);
        [loop] for (uint i = 0u; i < n; i++)
        {
            float2 p = cvKey(ch, i).a;
            tr = float2(min(tr.x, p.x), max(tr.y, p.x));
            vr = float2(min(vr.x, p.y), max(vr.y, p.y));
            if (cvShowsOut(ch, n, i))
            {
                float2 q = cvTipOut(ch, i);
                vr = float2(min(vr.x, q.y), max(vr.y, q.y));
            }
        }
    }
    float pt = 0.04 * (tr.y - tr.x), pv = 0.12 * (vr.y - vr.x);
    g_tw = float2(tr.x - pt, tr.y + pt);
    g_vw = float2(vr.x - pv, vr.y + pv);
}

void zoomAbout(CvLayout L, float2 p, float notches, bool values)
{
    float f = exp2(-0.35 * notches);
    float ct = cvT(L, g_tw, p.x), cv = cvV(L, g_vw, p.y);
    float2 tw = ct + (g_tw - ct) * f;
    if (tw.y - tw.x > 0.05 && tw.y - tw.x < 60.0) g_tw = tw;
    if (!values) return;
    float2 vw = cv + (g_vw - cv) * f;
    if (vw.y - vw.x > 0.02 && vw.y - vw.x < 50.0) g_vw = vw;
}

// a scrubbed moment: inside the loop, on a whole frame while snapping
float scrubTime(float t)
{
    t = clamp(t, 0.0, g_len);
    return snap ? min(round(t * g_fps) / g_fps, g_len) : t;
}

// the ghost nearest a point in the chart: its time
float ghostTimeAt(CvLayout L, float s, float2 p)
{
    uint g = cvGhosts(g_len, g_fps);
    float best = 1e9, bt = 0.0;
    [loop] for (uint k = 0u; k < g; k++)
    {
        float t = min(cvGhostT(k, g_fps), g_len);
        float2 r;
        float2 c = cvBall(L, s, cvValue(0u, cvCount(g_packed, 0u), t), cvValue(1u, cvCount(g_packed, 1u), t),
                          cvValue(2u, cvCount(g_packed, 2u), t), r);
        float d = length(c - p);
        if (d < best) { best = d; bt = t; }
    }
    return bt;
}

// ---------------------------------------------------------------- auto handles
// Catmull-Rom slopes, flattened at a local extreme and limited so the segment cannot overshoot its
// neighbours (Fritsch-Carlson); each handle a third of its segment. End keys are flat.
void autoHandles()
{
    [loop] for (uint ch = 0u; ch < CV_CH; ch++)
    {
        uint n = cvCount(g_packed, ch);
        [loop] for (uint i = 0u; i < n; i++)
        {
            CvRec k = S[cvSlot(ch, i)];
            float spanIn = (i > 0u) ? k.a.x - cvKey(ch, i - 1u).a.x : 0.0;
            float spanOut = (i + 1u < n) ? cvKey(ch, i + 1u).a.x - k.a.x : 0.0;
            if (cvHandles(k.e) == CV_AUTO)
            {
                float slope = 0.0;
                if (i > 0u && i + 1u < n)
                {
                    float2 pp = cvKey(ch, i - 1u).a, pn = cvKey(ch, i + 1u).a;
                    float d0 = (k.a.y - pp.y) / max(spanIn, 1e-6), d1 = (pn.y - k.a.y) / max(spanOut, 1e-6);
                    if (d0 * d1 > 0.0)
                        slope = clamp((pn.y - pp.y) / max(pn.x - pp.x, 1e-6), -3.0 * min(abs(d0), abs(d1)), 3.0 * min(abs(d0), abs(d1)));
                }
                float din = max(spanIn, spanOut) / 3.0, dout = max(spanOut, spanIn) / 3.0;
                if (i > 0u) din = spanIn / 3.0;
                if (i + 1u < n) dout = spanOut / 3.0;
                k.b = float2(-din, -slope * din);
                k.c = dout;
                k.d = slope * dout;
            }
            k.b.x = min(k.b.x, 0.0);
            k.c = max(k.c, 0.0);
            S[cvSlot(ch, i)] = k;
        }
    }
}

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    float2 res = _Resolution.xy;
    float s = ilCtx(res).s;
    g_len = clamp(length_s, 0.5, 8.0);
    g_fps = clamp((float)fps, 6.0, 60.0);

    CvRec p0 = S[CV_P0], v0 = S[CV_V0], v1 = S[CV_V1], v2 = S[CV_V2];
    g_packed = p0.e;
    if (p0.f != CV_MAGIC)
    {
        // no keys yet (or an older format): the default ball
        g_packed = 0u;
        writeDefaults();
        p0 = (CvRec)0;
        p0.f = CV_MAGIC;
        S[CV_U0] = (CvRec)0;
        v2.f = 0u;
    }
    if (v2.f != CV_VMAGIC)
    {
        // working state is never saved: fresh after a reopen or a resize, framing the keys it finds
        v0 = (CvRec)0;
        v1 = (CvRec)0;
        v2 = (CvRec)0;
        v0.d = 0.66;
        v1.e = CV_PLAYING;
        v2.f = CV_VMAGIC;
        frameAll();
        v0.a = g_tw;
        v0.b = g_vw;
    }
    g_tw = v0.a;
    g_vw = v0.b;
    float split = clamp(v0.d, 0.15, 0.92);
    float play = v0.c;
    uint mode = (uint)v1.c;
    uint target = (uint)v1.d;
    uint flags = v1.e;
    float2 press = v1.a;
    bool spaceHeld = (v0.f & 1u) != 0u;

    uint lastSeq = ilEvWatermark(v0.e);
    uint newest = lastSeq;
    uint n = ilEvCount();
    [loop] for (uint ei = 0u; ei < n; ei++)
    {
        ViewportEvent e = _ViewportEvents[ei];
        if (!ilEvFresh(e.sequence, lastSeq)) continue;
        newest = ilEvAdvance(newest, lastSeq, e.sequence);
        CvLayout L = cvLayout(res, s, split);
        float2 px = ilEvPx(e, res);
        float pxT = (L.graph.z - L.graph.x) / max(g_tw.y - g_tw.x, 1e-6);
        float pxV = (L.graph.w - L.graph.y) / max(g_vw.y - g_vw.x, 1e-6);

        if (e.type == IL_EV_MOVE)
        {
            v1.b = px;
            continue;
        }
        if (ilIsPress(e, IL_BTN_LEFT)) { press = px; flags &= ~CV_MIDDLE; }
        if (ilIsPress(e, IL_BTN_MIDDLE)) { press = px; flags |= CV_MIDDLE; }
        if (ilIsRelease(e, IL_BTN_MIDDLE) && mode != DM_PAN) flags &= ~CV_MIDDLE;

        if (ilIsDrag(e))
        {
            if (e.phase == IL_PH_BEGIN)
            {
                mode = DM_NONE;
                if ((flags & CV_MIDDLE) != 0u)
                {
                    // the middle button pans, wherever it starts
                    mode = DM_PAN;
                    v2.b = press;
                }
                else if (ilIn(press, L.grip)) mode = DM_SPLIT;
                else if (ilIn(press, L.ruler)) mode = DM_SCRUB;
                else if (ilIn(press, L.chart)) mode = DM_CHART;
                else if (ilIn(press, L.graph))
                {
                    uint hh = cvHitHandle(L, g_tw, g_vw, g_packed, press, 8.0 * s);
                    uint hk = cvHitKey(L, g_tw, g_vw, g_packed, press, 8.0 * s);
                    if (hh != 0xFFFFu)
                    {
                        mode = DM_HANDLE;
                        target = hh;
                        snapshot();
                    }
                    else if (hk != 0xFFFFu)
                    {
                        mode = DM_KEY;
                        target = hk;
                        uint ch = hk / CV_KMAX, i = hk % CV_KMAX;
                        if (!cvSel(cvKey(ch, i).e))
                        {
                            clearSelection();
                            setSelected(ch, i, true);
                        }
                        v2.a = cvKey(ch, i).a;
                        snapshot();
                    }
                    else
                    {
                        mode = DM_BOX;
                        v2.b = press;
                    }
                }
            }
            if (ilIsCancel(e))
            {
                if (mode == DM_KEY || mode == DM_HANDLE) restoreSnapshot();
                mode = DM_NONE;
                continue;
            }
            if (mode == DM_KEY)
            {
                float2 d = float2((px.x - press.x) / pxT, -(px.y - press.y) / pxV);
                if (snap) d.x = round((v2.a.x + d.x) * g_fps) / g_fps - v2.a.x;
                float2 rng = allowedDt(CV_UNDO0);
                d.x = clamp(d.x, rng.x, rng.y);
                moveSelection(CV_UNDO0, d);
            }
            else if (mode == DM_HANDLE)
            {
                uint ki = target >> 1;
                uint ch = ki / CV_KMAX, i = ki % CV_KMAX;
                CvRec k = S[cvSlot(ch, i)];
                float2 v = float2(cvT(L, g_tw, px.x), cvV(L, g_vw, px.y)) - k.a;
                bool outSide = (target & 1u) != 0u;
                if (outSide)
                {
                    v.x = max(v.x, 1e-3);
                    k.c = v.x;
                    k.d = v.y;
                    if (cvHandles(k.e) != CV_BROKEN) k.b.y = min(k.b.x, -1e-3) * (v.y / v.x);
                }
                else
                {
                    v.x = min(v.x, -1e-3);
                    k.b = v;
                    if (cvHandles(k.e) != CV_BROKEN) k.d = max(k.c, 1e-3) * (v.y / v.x);
                }
                if (cvHandles(k.e) == CV_AUTO) k.e = cvWithHandles(k.e, CV_ALIGNED);
                S[cvSlot(ch, i)] = k;
            }
            else if (mode == DM_BOX)
            {
                v2.b = px;
                if (e.phase == IL_PH_END)
                {
                    float4 box = float4(min(press, px), max(press, px));
                    if (!ilShift(e)) clearSelection();
                    [loop] for (uint ch = 0u; ch < CV_CH; ch++)
                    {
                        if (cvHidden(g_packed, ch)) continue;
                        uint nk = cvCount(g_packed, ch);
                        [loop] for (uint i = 0u; i < nk; i++)
                            if (ilIn(cvP(L, g_tw, g_vw, cvKey(ch, i).a), box)) setSelected(ch, i, true);
                    }
                }
            }
            else if (mode == DM_SCRUB)
            {
                play = scrubTime(cvT(L, g_tw, px.x));
                flags &= ~CV_PLAYING;
            }
            else if (mode == DM_CHART)
            {
                play = ghostTimeAt(L, s, px);
                flags &= ~CV_PLAYING;
            }
            else if (mode == DM_SPLIT)
            {
                split = clamp(ilSplitYValue(L.inner, px.y, CV_SPLIT_GAP * s), 0.15, 0.92);
            }
            else if (mode == DM_PAN)
            {
                float2 d = px - v2.b;
                g_tw -= d.x / pxT;
                g_vw += d.y / pxV;
                v2.b = px;
            }
            if (e.phase == IL_PH_END)
            {
                if (mode == DM_PAN) flags &= ~CV_MIDDLE;
                mode = DM_NONE;
            }
        }
        else if (ilIsClick(e))
        {
            if (ilIn(px, L.graph))
            {
                uint hk = cvHitKey(L, g_tw, g_vw, g_packed, px, 8.0 * s);
                if (hk != 0xFFFFu)
                {
                    uint ch = hk / CV_KMAX, i = hk % CV_KMAX;
                    if (ilShift(e)) setSelected(ch, i, !cvSel(cvKey(ch, i).e));
                    else { clearSelection(); setSelected(ch, i, true); }
                }
                else if (cvHitHandle(L, g_tw, g_vw, g_packed, px, 8.0 * s) == 0xFFFFu) clearSelection();
            }
            else if (ilIn(px, L.ruler))
            {
                play = scrubTime(cvT(L, g_tw, px.x));
                flags &= ~CV_PLAYING;
            }
            else if (ilIn(px, L.chart))
            {
                play = ghostTimeAt(L, s, px);
                flags &= ~CV_PLAYING;
            }
            else
            {
                [loop] for (uint ch = 0u; ch < CV_CH; ch++)
                {
                    if (!ilIn(px, L.row[ch])) continue;
                    g_packed ^= 1u << (15u + ch);
                    if (cvHidden(g_packed, ch))
                    {
                        uint nk = cvCount(g_packed, ch);
                        [loop] for (uint i = 0u; i < nk; i++) setSelected(ch, i, false);
                    }
                }
            }
        }
        else if (ilIsDouble(e) && ilIn(px, L.graph))
        {
            if (cvHitKey(L, g_tw, g_vw, g_packed, px, 8.0 * s) == 0xFFFFu)
            {
                uint ch = cvHitCurve(L, g_tw, g_vw, g_packed, px, 10.0 * s);
                if (ch != 0xFFFFu)
                {
                    float t = clamp(cvT(L, g_tw, px.x), 0.0, g_len);
                    if (snap) t = round(t * g_fps) / g_fps;
                    insertKey(ch, t, cvValue(ch, cvCount(g_packed, ch), t));
                }
            }
        }
        else if (e.type == IL_EV_WHEEL)
        {
            if (ilIn(px, L.graph)) zoomAbout(L, px, ilWheel(e), true);
            else if (ilIn(px, L.ruler)) zoomAbout(L, px, ilWheel(e), false);
        }
        else if (e.type == IL_EV_KEY)
        {
            if (ilLatch(e, IL_KEY_SPACE, spaceHeld)) flags ^= CV_PLAYING;
            bool down = e.phase == IL_PH_PRESS && !ilRepeat(e);
            bool downOrRepeat = e.phase == IL_PH_PRESS || e.phase == IL_PH_REPEAT;
            bool any = selectionCount() > 0u;
            if (down && e.code == IL_KEY_BACKSPACE && any) { snapshot(); deleteSelection(); }
            if (down && e.code >= IL_KEY_0 + 1u && e.code <= IL_KEY_0 + 3u && any) { snapshot(); setMode(0u, e.code - (IL_KEY_0 + 1u)); }
            if (down && e.code == IL_KEY_A && any) { snapshot(); setMode(1u, CV_AUTO); }
            if (down && e.code == IL_KEY_B && any) { snapshot(); toggleBroken(); }
            if (down && e.code == IL_KEY_F) frameAll();
            if (down && e.code == IL_KEY_Z) swapUndo();
            if (down && e.code == IL_KEY_R) { snapshot(); writeDefaults(); }
            if (down && e.code == IL_KEY_ESC) clearSelection();
            if (downOrRepeat && any && (e.code == IL_KEY_LEFT || e.code == IL_KEY_RIGHT || e.code == IL_KEY_UP || e.code == IL_KEY_DOWN))
            {
                if (down) snapshot();
                float2 d = float2(e.code == IL_KEY_LEFT ? -frameGap() : (e.code == IL_KEY_RIGHT ? frameGap() : 0.0),
                                  e.code == IL_KEY_UP ? 0.01 : (e.code == IL_KEY_DOWN ? -0.01 : 0.0));
                float2 rng = allowedDt(CV_KEY0);
                d.x = clamp(d.x, rng.x, rng.y);
                moveSelection(CV_KEY0, d);
            }
        }
    }

    // the playhead runs on this node's clock
    if ((flags & CV_PLAYING) != 0u) play += _DeltaTime;
    play = play - g_len * floor(play / g_len);

    autoHandles();

    p0.e = g_packed;
    v0.a = g_tw;
    v0.b = g_vw;
    v0.c = play;
    v0.d = split;
    v0.e = newest;
    v0.f = spaceHeld ? 1u : 0u;
    v1.a = press;
    v1.c = (float)mode;
    v1.d = (float)target;
    v1.e = flags;
    v2.e = v2.e + 1u;
    S[CV_P0] = p0;
    S[CV_V0] = v0;
    S[CV_V1] = v1;
    S[CV_V2] = v2;
}
