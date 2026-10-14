// Path Desk / reduce - one thread: the viewport events, then the smooth anchors' handles.
//
// EDIT (the pen off)
//   click an anchor       select it (Shift: toggle)       click empty: clear the selection
//   drag an anchor        move it with every selected anchor
//   drag a handle         shape the curve (a smooth anchor becomes aligned; B breaks it)
//   drag empty            box select                      path row: select the whole path
//   double-click anchor   corner <-> smooth               double-click a curve: add an anchor
//   1 / 2, B              corner / smooth; break or re-align the handles
//   C                     close or open the active path   Backspace: delete the selected anchors
//   arrows                nudge a pixel                   K: curvature comb on / off
// PEN (P, or the switch in the header)
//   click                 a corner: the first of a new path, then the next one along it
//   drag                  a smooth anchor, its handles pulled out as you drag
//   an open path's end    carry on drawing it from that end
//   the first anchor      close the path        Enter: finish it open      Esc: stop drawing
// ALWAYS
//   a row's pen chip      the next pen          O: the plot order with the least pen-up travel
//   R                     the default plot (Z brings the edit back)
//   Z                     undo the last edit (again: redo)
#define PD_STATE_RW
#include "../_shared/ui/il_core.hlsli"
#include "../_shared/ui/il_events.hlsli"
#include "path.hlsli"

#define DM_NONE   0u
#define DM_ANCHOR 1u
#define DM_HANDLE 2u
#define DM_BOX    3u
#define DM_PEN    4u      // a new (or closing) anchor: the drag pulls its handles out

static uint g_pk;

// ---------------------------------------------------------------- undo
void storeCounts()
{
    PdRec p0 = S[PD_P0];
    p0.e = g_pk;
    S[PD_P0] = p0;
}

void snapshot()
{
    storeCounts();
    [loop] for (uint i = 0u; i < PD_SAVED; i++) S[PD_UNDO0 + i] = S[i];
    PdRec u0 = (PdRec)0;
    u0.f = 1u;
    S[PD_U0] = u0;
}

void swapUndo()
{
    if (S[PD_U0].f == 0u) return;
    storeCounts();
    [loop] for (uint i = 0u; i < PD_SAVED; i++)
    {
        PdRec a = S[i];
        S[i] = S[PD_UNDO0 + i];
        S[PD_UNDO0 + i] = a;
    }
    g_pk = S[PD_P0].e;
}

// a cancelled drag: back to where it began (the snapshot stays, so Z still has it)
void restoreSnapshot()
{
    [loop] for (uint i = 0u; i < PD_SAVED; i++) S[i] = S[PD_UNDO0 + i];
    g_pk = S[PD_P0].e;
}

// ---------------------------------------------------------------- the default plot
PdRec anchorRec(float2 pos, uint kind, float2 hin, float2 hout)
{
    PdRec r = (PdRec)0;
    r.a = pos;
    r.b = hin;
    r.c = hout.x;
    r.d = hout.y;
    r.e = kind;
    return r;
}

void pathRec(uint p, bool closed, uint pen)
{
    PdRec h = (PdRec)0;
    h.e = (closed ? 1u : 0u) | ((pen & 3u) << 1);
    S[PD_H0 + p] = h;
}

// A ridge with corners on its peaks, a sun, a sea of smooth swells and a gull: four ways for a pen
// to move - stopping dead, holding one speed, breathing, and turning on a point.
void writeDefaults()
{
    [loop] for (uint i = 1u; i < PD_SAVED; i++) S[i] = (PdRec)0;
    static const float2 RIDGE[8] = { float2(96, 548), float2(286, 382), float2(372, 446), float2(518, 236),
                                     float2(648, 404), float2(762, 352), float2(918, 470), float2(1184, 548) };
    static const uint RIDGE_K[8] = { PD_CORNER, PD_CORNER, PD_SMOOTH, PD_CORNER, PD_SMOOTH, PD_CORNER, PD_SMOOTH, PD_CORNER };
    pathRec(0u, false, 1u);
    [loop] for (uint r = 0u; r < 8u; r++) S[pdSlot(0u, r)] = anchorRec(RIDGE[r], RIDGE_K[r], 0.0, 0.0);

    // the sun: four aligned anchors, handles 0.5523 r - a circle to within 0.03%
    float2 c = float2(936.0, 196.0);
    float rad = 72.0, h = 0.5523 * rad;
    pathRec(1u, true, 2u);
    S[pdSlot(1u, 0u)] = anchorRec(c + float2(rad, 0.0), PD_ALIGNED, float2(0.0, -h), float2(0.0, h));
    S[pdSlot(1u, 1u)] = anchorRec(c + float2(0.0, rad), PD_ALIGNED, float2(h, 0.0), float2(-h, 0.0));
    S[pdSlot(1u, 2u)] = anchorRec(c - float2(rad, 0.0), PD_ALIGNED, float2(0.0, h), float2(0.0, -h));
    S[pdSlot(1u, 3u)] = anchorRec(c - float2(0.0, rad), PD_ALIGNED, float2(-h, 0.0), float2(h, 0.0));

    static const float SEA_Y[9] = { 622, 600, 636, 604, 642, 606, 640, 606, 626 };
    pathRec(2u, false, 0u);
    [loop] for (uint w = 0u; w < 9u; w++) S[pdSlot(2u, w)] = anchorRec(float2(100.0 + 135.0 * w, SEA_Y[w]), PD_SMOOTH, 0.0, 0.0);

    // the gull: two wings that meet in a cusp
    pathRec(3u, false, 0u);
    S[pdSlot(3u, 0u)] = anchorRec(float2(350.0, 152.0), PD_BROKEN, 0.0, float2(12.0, -12.0));
    S[pdSlot(3u, 1u)] = anchorRec(float2(384.0, 166.0), PD_BROKEN, float2(-9.0, -13.0), float2(9.0, -13.0));
    S[pdSlot(3u, 2u)] = anchorRec(float2(418.0, 152.0), PD_BROKEN, float2(-12.0, -12.0), 0.0);

    g_pk = pdWithCount(pdWithCount(pdWithCount(pdWithCount(0u, 0u, 8u), 1u, 4u), 2u, 9u), 3u, 3u);
}

// ---------------------------------------------------------------- selection
uint selectionCount()
{
    uint c = 0u;
    [loop] for (uint p = 0u; p < PD_PATHS; p++)
    {
        uint n = pdCount(g_pk, p);
        [loop] for (uint j = 0u; j < n; j++) c += pdSel(pdAnchor(p, j).e) ? 1u : 0u;
    }
    return c;
}

void setSelected(uint p, uint j, bool on)
{
    PdRec r = S[pdSlot(p, j)];
    r.e = on ? (r.e | PD_SEL) : (r.e & ~PD_SEL);
    S[pdSlot(p, j)] = r;
}

void clearSelection()
{
    [loop] for (uint p = 0u; p < PD_PATHS; p++)
    {
        uint n = pdCount(g_pk, p);
        [loop] for (uint j = 0u; j < n; j++) setSelected(p, j, false);
    }
}

void selectPath(uint p)
{
    clearSelection();
    uint n = pdCount(g_pk, p);
    [loop] for (uint j = 0u; j < n; j++) setSelected(p, j, true);
}

// ---------------------------------------------------------------- edits
// every selected anchor to its record at base + d (its handles ride along: they are relative)
void moveSelection(uint base, float2 d)
{
    [loop] for (uint p = 0u; p < PD_PATHS; p++)
    {
        uint n = pdCount(g_pk, p);
        [loop] for (uint j = 0u; j < n; j++)
        {
            PdRec r = S[base + pdSlot(p, j)];
            if (!pdSel(r.e)) continue;
            r.a += d;
            S[pdSlot(p, j)] = r;
        }
    }
}

void setKind(uint kind)
{
    [loop] for (uint p = 0u; p < PD_PATHS; p++)
    {
        uint n = pdCount(g_pk, p);
        [loop] for (uint j = 0u; j < n; j++)
        {
            PdRec r = S[pdSlot(p, j)];
            if (!pdSel(r.e)) continue;
            r.e = (r.e & ~3u) | kind;
            S[pdSlot(p, j)] = r;
        }
    }
}

// B: break every selected anchor's handles, or re-align them when all are broken already (the out
// handle turns to face away from the in handle, keeping its length)
void toggleBroken()
{
    bool allBroken = true;
    [loop] for (uint p = 0u; p < PD_PATHS; p++)
    {
        uint n = pdCount(g_pk, p);
        [loop] for (uint j = 0u; j < n; j++)
        {
            PdRec r = pdAnchor(p, j);
            if (pdSel(r.e) && pdKind(r.e) != PD_CORNER && pdKind(r.e) != PD_BROKEN) allBroken = false;
        }
    }
    [loop] for (uint p2 = 0u; p2 < PD_PATHS; p2++)
    {
        uint n = pdCount(g_pk, p2);
        [loop] for (uint j = 0u; j < n; j++)
        {
            PdRec r = S[pdSlot(p2, j)];
            if (!pdSel(r.e) || pdKind(r.e) == PD_CORNER) continue;
            if (allBroken)
            {
                r.e = (r.e & ~3u) | PD_ALIGNED;
                float lo = length(pdOut(r));
                if (dot(r.b, r.b) > 1e-6)
                {
                    float2 o = -normalize(r.b) * lo;
                    r.c = o.x;
                    r.d = o.y;
                }
            }
            else r.e = (r.e & ~3u) | PD_BROKEN;
            S[pdSlot(p2, j)] = r;
        }
    }
}

// Backspace: the selected anchors go; a path left empty goes too and the later ones move up; a path
// left with one anchor is opened
void deleteSelection(inout uint active)
{
    [loop] for (uint p = 0u; p < PD_PATHS; p++)
    {
        uint n = pdCount(g_pk, p);
        uint w = 0u;
        [loop] for (uint j = 0u; j < n; j++)
        {
            PdRec r = S[pdSlot(p, j)];
            if (pdSel(r.e)) continue;
            S[pdSlot(p, w)] = r;
            w++;
        }
        g_pk = pdWithCount(g_pk, p, w);
        if (w < 2u)
        {
            PdRec h = S[PD_H0 + p];
            h.e &= ~1u;
            S[PD_H0 + p] = h;
        }
    }
    uint q = 0u;
    uint newActive = PD_NONE;
    [loop] for (uint p2 = 0u; p2 < PD_PATHS; p2++)
    {
        uint n = pdCount(g_pk, p2);
        if (n == 0u) continue;
        if (q != p2)
        {
            S[PD_H0 + q] = S[PD_H0 + p2];
            [loop] for (uint j = 0u; j < n; j++) S[pdSlot(q, j)] = S[pdSlot(p2, j)];
            g_pk = pdWithCount(g_pk, q, n);
        }
        if (p2 == active) newActive = q;
        q++;
    }
    [loop] for (uint p3 = q; p3 < PD_PATHS; p3++)
    {
        g_pk = pdWithCount(g_pk, p3, 0u);
        S[PD_H0 + p3] = (PdRec)0;
    }
    active = newActive;
}

// Double-click on a curve: a new anchor that splits segment k at t (de Casteljau), so the curve
// keeps its exact shape. A smooth neighbour is frozen as aligned for the same reason.
void splitAt(uint p, uint k, float t)
{
    uint n = pdCount(g_pk, p);
    if (n >= PD_AMAX || n < 2u) return;
    float2 p0, p1, p2, p3;
    pdSeg(g_pk, p, k, p0, p1, p2, p3);
    float2 q0 = lerp(p0, p1, t), q1 = lerp(p1, p2, t), q2 = lerp(p2, p3, t);
    float2 r0 = lerp(q0, q1, t), r1 = lerp(q1, q2, t);
    float2 at = lerp(r0, r1, t);
    snapshot();
    clearSelection();
    uint kn = (k + 1u) % n;
    PdRec a = S[pdSlot(p, k)];
    if (pdKind(a.e) == PD_SMOOTH) a.e = (a.e & ~3u) | PD_ALIGNED;
    a.c = q0.x - p0.x;
    a.d = q0.y - p0.y;
    S[pdSlot(p, k)] = a;
    PdRec b = S[pdSlot(p, kn)];
    if (pdKind(b.e) == PD_SMOOTH) b.e = (b.e & ~3u) | PD_ALIGNED;
    b.b = q2 - p3;
    S[pdSlot(p, kn)] = b;
    [loop] for (uint j = n; j > k + 1u; j--) S[pdSlot(p, j)] = S[pdSlot(p, j - 1u)];
    PdRec m = anchorRec(at, PD_ALIGNED, r0 - at, r1 - at);
    m.e |= PD_SEL;
    S[pdSlot(p, k + 1u)] = m;
    g_pk = pdWithCount(g_pk, p, n + 1u);
}

// The pen's next anchor at q (program px): on the end of the path it is drawing, or the first of a
// new path. Returns its slot (p * 20 + j), or 0xFFFF when there is no room for another path.
uint penAppend(inout uint active, inout uint flags, float2 q)
{
    uint paths = pdPaths(g_pk);
    uint p = active;
    bool fresh = (flags & PD_DRAWING) == 0u || p >= paths || pdClosed(p) || pdCount(g_pk, p) >= PD_AMAX;
    if (fresh && paths >= PD_PATHS) return 0xFFFFu;
    if (fresh)
    {
        uint pen = (active < paths) ? pdPen(active) : 0u;
        p = paths;
        pathRec(p, false, pen);
        active = p;
    }
    uint n = pdCount(g_pk, p);
    clearSelection();
    PdRec r = anchorRec(q, PD_CORNER, 0.0, 0.0);
    r.e |= PD_SEL;
    S[pdSlot(p, n)] = r;
    g_pk = pdWithCount(g_pk, p, n + 1u);
    flags |= PD_DRAWING;
    return p * PD_AMAX + n;
}

// the pen is over the first anchor of the open path it is drawing: a click there closes it
bool closesActive(PdLayout L, uint active, uint flags, float2 at, float reach)
{
    if ((flags & PD_DRAWING) == 0u || active >= pdPaths(g_pk) || pdClosed(active) || pdCount(g_pk, active) < 2u) return false;
    return length(pdScreen(L, pdAnchor(active, 0u).a) - at) < reach;
}

// drawn the other way round: anchors reversed, in and out handles swapped (the same curve)
void reversePath(uint p)
{
    uint n = pdCount(g_pk, p);
    [loop] for (uint i = 0u; i < n / 2u; i++)
    {
        PdRec a = S[pdSlot(p, i)];
        S[pdSlot(p, i)] = S[pdSlot(p, n - 1u - i)];
        S[pdSlot(p, n - 1u - i)] = a;
    }
    [loop] for (uint j = 0u; j < n; j++)
    {
        PdRec r = S[pdSlot(p, j)];
        float2 hin = r.b;
        r.b = pdOut(r);
        r.c = hin.x;
        r.d = hin.y;
        S[pdSlot(p, j)] = r;
    }
}

void setClosed(uint p, bool on)
{
    PdRec h = S[PD_H0 + p];
    h.e = on ? (h.e | 1u) : (h.e & ~1u);
    S[PD_H0 + p] = h;
}

// O: a plot order with little pen-up travel. Greedy - after each path, the nearest free path end;
// a path whose far end is the nearer one is drawn backwards (anchors reversed, in and out handles
// swapped) - tried from every first path in both directions, with the trip home counted, keeping
// the shortest. A closed path starts and ends on its first anchor. The snapshot holds the order
// before, so the paths are rebuilt from it.
bool snapClosed(uint q) { return (S[PD_UNDO0 + PD_H0 + q].e & 1u) != 0u; }
float2 snapEnd(uint opk, uint q, bool far) { return S[PD_UNDO0 + pdSlot(q, far ? pdCount(opk, q) - 1u : 0u)].a; }

float greedyOrder(uint opk, uint paths, uint first, bool firstRev, bool write, inout uint active)
{
    uint used = 0u, pk = 0u, newActive = PD_NONE;
    float2 at = PLOT_HOME;
    float travel = 0.0;
    [loop] for (uint slot = 0u; slot < paths; slot++)
    {
        uint best = first;
        bool rev = firstRev;
        float bd = length(snapEnd(opk, first, firstRev) - at);
        if (slot > 0u)
        {
            bd = 1e9;
            [loop] for (uint q = 0u; q < paths; q++)
            {
                if ((used >> q) & 1u) continue;
                float d0 = length(snapEnd(opk, q, false) - at);
                float d1 = snapClosed(q) ? 1e9 : length(snapEnd(opk, q, true) - at);
                if (d0 < bd) { bd = d0; best = q; rev = false; }
                if (d1 < bd) { bd = d1; best = q; rev = true; }
            }
        }
        travel += bd;
        used |= 1u << best;
        bool closed = snapClosed(best);
        at = closed ? snapEnd(opk, best, false) : snapEnd(opk, best, !rev);
        if (!write) continue;
        if (best == active) newActive = slot;
        uint n = pdCount(opk, best);
        S[PD_H0 + slot] = S[PD_UNDO0 + PD_H0 + best];
        [loop] for (uint j = 0u; j < n; j++)
        {
            PdRec r = S[PD_UNDO0 + pdSlot(best, rev ? n - 1u - j : j)];
            if (rev)
            {
                float2 hin = r.b;
                r.b = pdOut(r);
                r.c = hin.x;
                r.d = hin.y;
            }
            S[pdSlot(slot, j)] = r;
        }
        pk = pdWithCount(pk, slot, n);
    }
    travel += length(PLOT_HOME - at);
    if (write)
    {
        g_pk = pk;
        active = newActive;
    }
    return travel;
}

void optimiseOrder(inout uint active)
{
    snapshot();
    uint opk = S[PD_UNDO0 + PD_P0].e;
    uint paths = pdPaths(opk);
    float bestT = 1e9;
    uint bestFirst = 0u;
    bool bestRev = false;
    uint dummy = active;
    [loop] for (uint f = 0u; f < paths; f++)
    {
        [loop] for (uint r = 0u; r < 2u; r++)
        {
            if (r == 1u && snapClosed(f)) continue;
            float t = greedyOrder(opk, paths, f, r == 1u, false, dummy);
            if (t < bestT) { bestT = t; bestFirst = f; bestRev = r == 1u; }
        }
    }
    greedyOrder(opk, paths, bestFirst, bestRev, true, active);
}

// ---------------------------------------------------------------- smooth handles
// Along the line through the two neighbours, a third of the way to each; an open end aims at its
// one neighbour. Corners have none.
void smoothHandles()
{
    [loop] for (uint p = 0u; p < PD_PATHS; p++)
    {
        uint n = pdCount(g_pk, p);
        bool closed = pdClosed(p);
        [loop] for (uint j = 0u; j < n; j++)
        {
            PdRec r = S[pdSlot(p, j)];
            uint kind = pdKind(r.e);
            if (kind == PD_CORNER)
            {
                r.b = 0.0;
                r.c = 0.0;
                r.d = 0.0;
            }
            else if (kind == PD_SMOOTH)
            {
                bool hasPrev = n >= 2u && (j > 0u || closed);
                bool hasNext = n >= 2u && (j + 1u < n || closed);
                float2 prev = hasPrev ? pdAnchor(p, (j + n - 1u) % n).a : r.a;
                float2 next = hasNext ? pdAnchor(p, (j + 1u) % n).a : r.a;
                float2 dir = next - prev;
                dir = dot(dir, dir) > 1e-6 ? normalize(dir) : float2(1.0, 0.0);
                float2 hin = hasPrev ? -dir * length(r.a - prev) / 3.0 : float2(0.0, 0.0);
                float2 hout = hasNext ? dir * length(next - r.a) / 3.0 : float2(0.0, 0.0);
                r.b = hin;
                r.c = hout.x;
                r.d = hout.y;
            }
            S[pdSlot(p, j)] = r;
        }
    }
}

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    float2 res = _Resolution.xy;
    float s = ilCtx(res).s;
    PdLayout L = pdLayout(res, s);

    PdRec p0 = S[PD_P0], v0 = S[PD_V0], v1 = S[PD_V1], v2 = S[PD_V2];
    g_pk = p0.e;
    if (p0.f != PD_MAGIC)
    {
        // no paths yet (or an older format): the default plot
        writeDefaults();
        p0 = (PdRec)0;
        p0.f = PD_MAGIC;
        S[PD_P0] = p0;
        S[PD_U0] = (PdRec)0;
        v2.f = 0u;
    }
    if (v2.f != PD_VMAGIC)
    {
        // working state is never saved: fresh after a reopen, the comb on the sea
        v0 = (PdRec)0;
        v1 = (PdRec)0;
        v2 = (PdRec)0;
        v1.f = min(2u, max(pdPaths(g_pk), 1u) - 1u);
        v2.f = PD_VMAGIC;
    }
    uint mode = (uint)v1.c;
    uint target = (uint)v1.d;
    uint flags = v1.e;
    uint active = v1.f;
    float2 press = v1.a;

    uint lastSeq = ilEvWatermark(v0.e);
    uint newest = lastSeq;
    uint ne = ilEvCount();
    [loop] for (uint ei = 0u; ei < ne; ei++)
    {
        ViewportEvent e = _ViewportEvents[ei];
        if (!ilEvFresh(e.sequence, lastSeq)) continue;
        newest = ilEvAdvance(newest, lastSeq, e.sequence);
        float2 px = ilEvPx(e, res);
        bool pen = (flags & PD_PEN) != 0u;
        float reach = 8.0 * s;

        if (e.type == IL_EV_MOVE)
        {
            v1.b = px;
            continue;
        }
        if (ilIsPress(e, IL_BTN_LEFT)) press = px;

        if (ilIsDrag(e))
        {
            if (e.phase == IL_PH_BEGIN)
            {
                mode = DM_NONE;
                if (ilIn(press, L.stage))
                {
                    uint ha = pdHitAnchor(L, g_pk, press, reach);
                    uint hh = pen ? 0xFFFFu : pdHitHandle(L, g_pk, press, reach);
                    if (pen && closesActive(L, active, flags, press, reach))
                    {
                        // closing with a drag shapes the first anchor as it closes
                        snapshot();
                        setClosed(active, true);
                        flags &= ~PD_DRAWING;
                        clearSelection();
                        setSelected(active, 0u, true);
                        mode = DM_PEN;
                        target = active * PD_AMAX;
                    }
                    else if (hh != 0xFFFFu)
                    {
                        mode = DM_HANDLE;
                        target = hh;
                        snapshot();
                    }
                    else if (ha != 0xFFFFu)
                    {
                        mode = DM_ANCHOR;
                        target = ha;
                        uint p = ha / PD_AMAX, j = ha % PD_AMAX;
                        if (!pdSel(pdAnchor(p, j).e))
                        {
                            clearSelection();
                            setSelected(p, j, true);
                        }
                        active = p;
                        v2.a = pdAnchor(p, j).a;
                        snapshot();
                    }
                    else if (pen)
                    {
                        snapshot();
                        uint slot = penAppend(active, flags, pdProg(L, press));
                        if (slot != 0xFFFFu)
                        {
                            mode = DM_PEN;
                            target = slot;
                        }
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
                if (mode == DM_ANCHOR || mode == DM_HANDLE || mode == DM_PEN) restoreSnapshot();
                mode = DM_NONE;
                continue;
            }
            if (mode == DM_ANCHOR)
            {
                moveSelection(PD_UNDO0, pdProg(L, px) - pdProg(L, press));
            }
            else if (mode == DM_HANDLE)
            {
                uint slot = target >> 1;
                uint p = slot / PD_AMAX, j = slot % PD_AMAX;
                PdRec r = S[pdSlot(p, j)];
                float2 v = pdProg(L, px) - r.a;
                if (pdKind(r.e) == PD_SMOOTH) r.e = (r.e & ~3u) | PD_ALIGNED;
                bool aligned = pdKind(r.e) == PD_ALIGNED && dot(v, v) > 1e-4;
                if ((target & 1u) != 0u)
                {
                    if (aligned) r.b = -normalize(v) * length(r.b);
                    r.c = v.x;
                    r.d = v.y;
                }
                else
                {
                    if (aligned)
                    {
                        float2 o = -normalize(v) * length(pdOut(r));
                        r.c = o.x;
                        r.d = o.y;
                    }
                    r.b = v;
                }
                S[pdSlot(p, j)] = r;
            }
            else if (mode == DM_PEN)
            {
                // the handles come out symmetric; a drag that barely moved leaves a corner
                uint p = target / PD_AMAX, j = target % PD_AMAX;
                PdRec r = S[pdSlot(p, j)];
                float2 v = pdProg(L, px) - r.a;
                if (length(v) < 3.0)
                {
                    if (j != 0u || !pdClosed(p)) r.e = (r.e & ~3u) | PD_CORNER;
                }
                else
                {
                    r.e = (r.e & ~3u) | PD_ALIGNED;
                    r.b = -v;
                    r.c = v.x;
                    r.d = v.y;
                }
                S[pdSlot(p, j)] = r;
            }
            else if (mode == DM_BOX)
            {
                v2.b = px;
                if (e.phase == IL_PH_END)
                {
                    float4 box = float4(min(press, px), max(press, px));
                    if (!ilShift(e)) clearSelection();
                    [loop] for (uint p = 0u; p < PD_PATHS; p++)
                    {
                        uint n = pdCount(g_pk, p);
                        [loop] for (uint j = 0u; j < n; j++)
                        {
                            if (!ilIn(pdScreen(L, pdAnchor(p, j).a), box)) continue;
                            setSelected(p, j, true);
                            active = p;
                        }
                    }
                }
            }
            if (e.phase == IL_PH_END) mode = DM_NONE;
        }
        else if (ilIsClick(e))
        {
            if (ilIn(px, L.mode))
            {
                bool wantPen = px.x > ilMid(L.mode).x;
                flags = (wantPen ? (flags | PD_PEN) : (flags & ~PD_PEN)) & ~PD_DRAWING;
            }
            else if (ilIn(px, L.stage))
            {
                uint ha = pdHitAnchor(L, g_pk, px, reach);
                if (pen)
                {
                    if (closesActive(L, active, flags, px, reach))
                    {
                        snapshot();
                        setClosed(active, true);
                        flags &= ~PD_DRAWING;
                    }
                    else if (ha == 0xFFFFu)
                    {
                        snapshot();
                        penAppend(active, flags, pdProg(L, px));
                    }
                    else
                    {
                        // an open path's end: carry on drawing from it
                        uint p = ha / PD_AMAX, j = ha % PD_AMAX;
                        uint n = pdCount(g_pk, p);
                        if (!pdClosed(p) && (j == 0u || j + 1u == n))
                        {
                            snapshot();
                            if (j == 0u && n > 1u) reversePath(p);
                            clearSelection();
                            setSelected(p, n - 1u, true);
                            active = p;
                            flags |= PD_DRAWING;
                        }
                    }
                }
                else if (ha != 0xFFFFu)
                {
                    uint p = ha / PD_AMAX, j = ha % PD_AMAX;
                    if (ilShift(e)) setSelected(p, j, !pdSel(pdAnchor(p, j).e));
                    else
                    {
                        clearSelection();
                        setSelected(p, j, true);
                    }
                    active = p;
                }
                else if (pdHitHandle(L, g_pk, px, reach) == 0xFFFFu) clearSelection();
            }
            else
            {
                uint paths = pdPaths(g_pk);
                [loop] for (uint p = 0u; p < paths; p++)
                {
                    if (ilIn(px, L.pen[p]))
                    {
                        snapshot();
                        PdRec h = S[PD_H0 + p];
                        h.e = (h.e & 1u) | ((((h.e >> 1) + 1u) & 3u) << 1);
                        S[PD_H0 + p] = h;
                    }
                    else if (ilIn(px, L.row[p]))
                    {
                        selectPath(p);
                        active = p;
                    }
                }
            }
        }
        else if (ilIsDouble(e) && !pen && ilIn(px, L.stage))
        {
            uint ha = pdHitAnchor(L, g_pk, px, reach);
            if (ha != 0xFFFFu)
            {
                uint p = ha / PD_AMAX, j = ha % PD_AMAX;
                snapshot();
                PdRec r = S[pdSlot(p, j)];
                r.e = (r.e & ~3u) | (pdKind(r.e) == PD_CORNER ? PD_SMOOTH : PD_CORNER);
                S[pdSlot(p, j)] = r;
                active = p;
            }
            else
            {
                float3 hc = pdHitCurve(L, g_pk, px, reach);
                if (hc.x >= 0.0)
                {
                    uint id = (uint)hc.x;
                    splitAt(id / PD_AMAX, id % PD_AMAX, hc.y);
                    active = id / PD_AMAX;
                }
            }
        }
        else if (e.type == IL_EV_KEY)
        {
            bool down = e.phase == IL_PH_PRESS && !ilRepeat(e);
            bool downOrRepeat = e.phase == IL_PH_PRESS || e.phase == IL_PH_REPEAT;
            bool any = selectionCount() > 0u;
            if (down && e.code == IL_KEY_P) flags = (flags ^ PD_PEN) & ~PD_DRAWING;
            if (down && e.code == IL_KEY_ENTER && pen) flags &= ~PD_DRAWING;
            if (down && e.code == IL_KEY_ESC)
            {
                if (pen) flags &= ~(PD_PEN | PD_DRAWING);
                else clearSelection();
            }
            if (down && e.code == IL_KEY_K) flags ^= PD_NOCOMB;
            if (down && e.code == IL_KEY_BACKSPACE && any) { snapshot(); deleteSelection(active); }
            if (down && e.code == IL_KEY_0 + 1u && any) { snapshot(); setKind(PD_CORNER); }
            if (down && e.code == IL_KEY_0 + 2u && any) { snapshot(); setKind(PD_SMOOTH); }
            if (down && e.code == IL_KEY_B && any) { snapshot(); toggleBroken(); }
            if (down && e.code == IL_KEY_C && active < pdPaths(g_pk) && pdCount(g_pk, active) >= 2u)
            {
                snapshot();
                setClosed(active, !pdClosed(active));
            }
            if (down && e.code == IL_KEY_O && !pen && pdPaths(g_pk) > 0u) optimiseOrder(active);
            if (down && e.code == IL_KEY_Z) swapUndo();
            if (down && e.code == IL_KEY_R)
            {
                snapshot();
                writeDefaults();
                active = 2u;
            }
            if (downOrRepeat && any && (e.code == IL_KEY_LEFT || e.code == IL_KEY_RIGHT || e.code == IL_KEY_UP || e.code == IL_KEY_DOWN))
            {
                if (down) snapshot();
                float2 d = float2(e.code == IL_KEY_LEFT ? -1.0 : (e.code == IL_KEY_RIGHT ? 1.0 : 0.0),
                                  e.code == IL_KEY_UP ? -1.0 : (e.code == IL_KEY_DOWN ? 1.0 : 0.0));
                [loop] for (uint p = 0u; p < PD_PATHS; p++)
                {
                    uint n = pdCount(g_pk, p);
                    [loop] for (uint j = 0u; j < n; j++)
                    {
                        PdRec r = S[pdSlot(p, j)];
                        if (!pdSel(r.e)) continue;
                        r.a += d;
                        S[pdSlot(p, j)] = r;
                    }
                }
            }
        }
    }

    smoothHandles();

    if (active >= pdPaths(g_pk)) active = PD_NONE;
    p0 = S[PD_P0];
    p0.e = g_pk;
    p0.f = PD_MAGIC;
    v0.e = newest;
    v1.a = press;
    v1.c = (float)mode;
    v1.d = (float)target;
    v1.e = flags;
    v1.f = active;
    v2.e = v2.e + 1u;
    S[PD_P0] = p0;
    S[PD_V0] = v0;
    S[PD_V1] = v1;
    S[PD_V2] = v2;
}
