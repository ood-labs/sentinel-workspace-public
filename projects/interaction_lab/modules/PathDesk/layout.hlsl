// Path Desk / layout - the paths list, the stage, the curvature strip and the chrome.
//
// Three steps in one group of 64 threads:
//   1. one thread per path plans its curve as line pieces (one for a straight segment, one per
//      ~5 px of control polygon for a curved one); thread 6 plans the comb (the active path's
//      samples, at most 160) and thread 7 the strip (every path's samples, thinned to ~2.5 px);
//   2. thread 0 records everything else, reserving the three batches at their places in painter's
//      order (comb under the paths, the paths under the anchors, the strip inside its well);
//   3. every thread draws pieces, hairs and strip lines.
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"
#include "path.hlsli"

StructuredBuffer<float4> P : register(t1);

#define PD_PIECES 1400u
#define PD_COMB   160u
#define PD_STRIP  640u
#define DM_ANCHOR 1u
#define DM_HANDLE 2u
#define DM_BOX    3u
#define DM_PEN    4u

#define KAPPA_LO -3.4771      // log10(1 / 3000): flatter reads as straight
#define KAPPA_HI -0.9031      // log10(1 / 8)

groupshared uint gsOff[PD_PATHS][PD_AMAX + 1u];
groupshared uint gsTot[PD_PATHS];
groupshared uint gsComb, gsCombStride, gsStripStride;
groupshared uint gsStripOff[PD_PATHS + 1u];

static PdLayout g_L;
static uint g_pk, g_active, g_flags;
static float g_s;

void plate(float4 r) { dlRect(r, IL_PANEL, 0.86, IL_RADIUS * g_s); }
float3 pathCol(uint p) { return ptSampleColour(plotInk(pdPen(p))); }
float2 scr(float2 q) { return pdScreen(g_L, q); }
float4 pathRec(uint p) { return P[PLOT_PATH0 + p]; }
float4 sampleAt(uint k) { return P[PLOT_SAMPLE0 + k]; }

// ---------------------------------------------------------------- curve pieces
bool straightSeg(float2 p0, float2 p1, float2 p2, float2 p3) { return dot(p1 - p0, p1 - p0) < 1e-6 && dot(p2 - p3, p2 - p3) < 1e-6; }

uint piecesFor(uint p, uint k)
{
    float2 p0, p1, p2, p3;
    pdSeg(g_pk, p, k, p0, p1, p2, p3);
    if (straightSeg(p0, p1, p2, p3)) return 1u;
    float len = (length(p1 - p0) + length(p2 - p1) + length(p3 - p2)) * g_L.k;
    return clamp((uint)ceil(len / (5.0 * g_s)), 2u, 48u);
}

void piece(uint p, uint k, uint i, uint m)
{
    float2 p0, p1, p2, p3;
    pdSeg(g_pk, p, k, p0, p1, p2, p3);
    dlLine(scr(pdBez(p0, p1, p2, p3, (float)i / (float)m)), scr(pdBez(p0, p1, p2, p3, (float)(i + 1u) / (float)m)), 1.5 * g_s, pathCol(p), 1.0);
}

// ---------------------------------------------------------------- the strip's axes
float stripX0() { return g_L.strip.x + 46.0 * g_s; }
float stripX1() { return g_L.strip.z - 12.0 * g_s; }
float stripGap() { return 10.0 * g_s; }

// screen px per px of path, with a fixed gap between paths
float stripScale()
{
    float4 h = P[PLOT_HEAD];
    uint drawn = 0u;
    [loop] for (uint p = 0u; p < PD_PATHS; p++) drawn += pathRec(p).y > 0.0 ? 1u : 0u;
    float room = stripX1() - stripX0() - stripGap() * max((float)drawn - 1.0, 0.0);
    return room / max(h.y, 1.0);
}

// where path p starts in the strip
float stripStart(uint p, float scale)
{
    float x = stripX0();
    [unroll] for (uint q = 0u; q < PD_PATHS; q++)
    {
        float4 r = pathRec(q);
        if (q < p && r.y > 0.0) x += r.z * scale + stripGap();
    }
    return x;
}

float stripY(float kappa)
{
    float4 st = g_L.strip;
    float y0 = st.w - 10.0 * g_s, y1 = st.y + 26.0 * g_s;
    float u = (log10(max(abs(kappa), 1.0 / 3000.0)) - KAPPA_LO) / (KAPPA_HI - KAPPA_LO);
    return lerp(y0, y1, saturate(u));
}

// The strip is thinned to a node every few samples; a node carries the sharpest curvature in the
// stretch around it, so no peak is lost, and neighbouring lines share their node so they join.
float stripNode(uint first, uint n, uint k)
{
    uint st = gsStripStride;
    uint lo = k - min(k - first, st / 2u), hi = min(k + st / 2u, first + n - 1u);
    float kap = 0.0;
    [loop] for (uint i = lo; i <= hi; i++) kap = max(kap, abs(sampleAt(i).w));
    return kap;
}

void stripPiece(uint p, uint j, float scale)
{
    float4 r = pathRec(p);
    uint first = (uint)r.x, n = (uint)r.y, st = gsStripStride;
    uint k0 = first + j * st, k1 = min(first + (j + 1u) * st, first + n - 1u);
    float x0 = stripStart(p, scale);
    float s0 = r.z * (float)(k0 - first) / max(r.y - 1.0, 1.0), s1 = r.z * (float)(k1 - first) / max(r.y - 1.0, 1.0);
    dlLine(float2(x0 + s0 * scale, stripY(stripNode(first, n, k0))), float2(x0 + s1 * scale, stripY(stripNode(first, n, k1))),
           1.25 * g_s, pathCol(p), 1.0);
}

// comb hair c: from the curve, away from the centre of curvature, as long as the curvature is
// strong (radius 50 px reaches the cap); then the envelope back to the previous hair's tip
float2 hairTip(uint k)
{
    float4 q = sampleAt(k);
    float2 nrm = float2(-sin(q.z), cos(q.z));
    float len = min(abs(q.w) * 2400.0 * g_s, 48.0 * g_s);
    return scr(q.xy) - nrm * sign(q.w) * len;
}

void combPiece(uint c)
{
    float4 r = pathRec(g_active);
    uint first = (uint)r.x, n = (uint)r.y;
    uint k = min(first + c * gsCombStride, first + n - 1u);
    float2 base = scr(sampleAt(k).xy), tip = hairTip(k);
    dlLine(base, tip, 1.0 * g_s, IL_DIM, 1.0);
    float2 prev = (c == 0u) ? tip : hairTip(min(first + (c - 1u) * gsCombStride, first + n - 1u));
    dlLine(prev, tip, 1.0 * g_s, IL_MID, 1.0);
}

// ---------------------------------------------------------------- the header
float numW(uint cells, float size) { return ilNumW(cells, size); }

void header(uint nsel, uint selId, float2 pointer)
{
    float s = g_s;
    float4 hd = g_L.head;
    float hy = ilMid(hd).y;
    float tw = ilLabelW(LB_TITLE, 15.0 * s), sw = ilLabelW(LB_SUBTITLE, 12.0 * s);
    float4 hp = float4(hd.x, hd.y, hd.x + tw + sw + 40.0 * s, hd.w);
    plate(hp);
    dlLabel(LB_TITLE, hp.x + 12.0 * s, hy, 15.0 * s, IL_INK, IL_LEFT);
    dlLabel(LB_SUBTITLE, hp.x + 12.0 * s + tw + 14.0 * s, hy, 12.0 * s, IL_DIM, IL_LEFT);

    bool pen = (g_flags & PD_PEN) != 0u;
    int hotSeg = ilIn(pointer, g_L.mode) ? (pointer.x > ilMid(g_L.mode).x ? 1 : 0) : -1;
    dlSegmented(g_L.mode, s, LB_EDIT, 2u, pen ? 1 : 0, hotSeg);

    if (nsel == 0u) return;
    float cap = IL_T_CAP * s, val = IL_T_VALUE * s;
    float right = g_L.mode.x - 8.0 * s;
    if (nsel > 1u)
    {
        float ww = numW(3u, val) + 8.0 * s + ilLabelW(LB_SELECTED, cap) + 24.0 * s;
        float4 sp = float4(right - ww, hd.y, right, hd.w);
        plate(sp);
        float sx = sp.x + 12.0 * s;
        sx += dlInt((int)nsel, 1, sx, hy, val, IL_ACCENT, IL_LEFT) + 8.0 * s;
        dlLabel(LB_SELECTED, sx, hy, cap, IL_DIM, IL_LEFT);
        return;
    }
    uint p = selId / PD_AMAX, j = selId % PD_AMAX;
    PdRec r = pdAnchor(p, j);
    uint kind = pdKind(r.e);
    float ww = ilLabelW(LB_PATH, cap) + 5.0 * s + numW(1u, val) + 14.0 * s + ilLabelW(LB_ANCHOR, cap) + 5.0 * s + numW(2u, val) + 14.0 * s
             + ilLabelW(LB_X, cap) + 5.0 * s + numW(5u, val) + 12.0 * s + ilLabelW(LB_Y, cap) + 5.0 * s + numW(5u, val) + 14.0 * s
             + ilLabelW(LB_KIND_0 + kind, cap) + 30.0 * s;
    float4 sp = float4(right - ww, hd.y, right, hd.w);
    plate(sp);
    float sx = sp.x + 12.0 * s;
    dlRect(float4(sx, hy - 5.0 * s, sx + 3.0 * s, hy + 5.0 * s), pathCol(p), 1.0, 0.0);
    sx += 8.0 * s;
    sx += dlLabel(LB_PATH, sx, hy, cap, IL_INK, IL_LEFT) + 5.0 * s;
    sx += dlInt((int)p + 1, 1, sx, hy, val, IL_INK, IL_LEFT) + 14.0 * s;
    sx += dlLabel(LB_ANCHOR, sx, hy, cap, IL_DIM, IL_LEFT) + 5.0 * s;
    sx += dlInt((int)j + 1, 1, sx, hy, val, IL_ACCENT, IL_LEFT) + 14.0 * s;
    sx += dlLabel(LB_X, sx, hy, cap, IL_DIM, IL_LEFT) + 5.0 * s;
    sx += dlNum(r.a.x, 0, sx, hy, val, IL_INK, IL_LEFT) + 12.0 * s;
    sx += dlLabel(LB_Y, sx, hy, cap, IL_DIM, IL_LEFT) + 5.0 * s;
    sx += dlNum(r.a.y, 0, sx, hy, val, IL_INK, IL_LEFT) + 14.0 * s;
    dlLabel(LB_KIND_0 + kind, sx, hy, cap, IL_MID, IL_LEFT);
}

// ---------------------------------------------------------------- the paths list and the plot
void anchorGlyph(float2 c, uint kind, float3 col, bool filled, float r)
{
    float s = g_s;
    if (kind == PD_CORNER)
    {
        if (filled) dlRect(float4(c - r * 0.85, c + r * 0.85), col, 1.0, 0.0);
        else dlRectEdged(float4(c - r * 0.85, c + r * 0.85), IL_WELL, 1.0, 0.0, col, 1.25 * s);
    }
    else if (kind == PD_BROKEN)
    {
        dlDiamond(c, r + 1.0 * s, 0.0, filled ? col : IL_WELL, 1.0);
        if (!filled) dlDiamond(c, r + 1.0 * s, 1.25 * s, col, 1.0);
    }
    else if (kind == PD_SMOOTH || filled) dlCircle(c, r, col, 1.0);
    else
    {
        dlCircle(c, r, IL_WELL, 1.0);
        dlRing(c, r, 1.25 * s, col, 1.0);
    }
}

void pathsList(float2 pointer, float travel)
{
    float s = g_s;
    float4 l = g_L.list;
    float cap = IL_T_CAP * s, val = IL_T_VALUE * s;
    dlLabel(LB_PATHS, l.x + 2.0 * s, l.y + 10.0 * s, IL_T_TITLE * s, IL_DIM, IL_LEFT);
    uint paths = pdPaths(g_pk);
    [loop] for (uint p = 0u; p < PD_PATHS; p++)
    {
        float4 r = g_L.row[p];
        if (p >= paths)
        {
            dlBorderRect(r, IL_RADIUS * s, IL_EDGE, 1.0);
            if (p == paths) dlLabel(LB_FREE, r.x + 12.0 * s, ilMid(r).y, cap, IL_DIM, IL_LEFT);
            continue;
        }
        bool hot = ilIn(pointer, r);
        dlRect(r, hot ? IL_RAISE : IL_WELL, 1.0, IL_RADIUS * s);
        if (p == g_active) dlBorderRect(r, IL_RADIUS * s, IL_RULE, 1.0);
        float4 rec = pathRec(p);
        uint n = pdCount(g_pk, p);
        float3 col = pathCol(p);
        dlRect(float4(r.x + 10.0 * s, r.y + 9.0 * s, r.x + 13.0 * s, r.w - 9.0 * s), col, 1.0, 0.0);
        float y0 = r.y + 14.0 * s, y1 = r.y + 31.0 * s;
        float x = r.x + 22.0 * s;
        x += dlLabel(LB_PATH, x, y0, IL_T_TITLE * s, IL_INK, IL_LEFT) + 5.0 * s;
        dlInt((int)p + 1, 1, x, y0, val, IL_INK, IL_LEFT);
        float rx = r.z - 10.0 * s;
        rx -= dlLabel(LB_PX, rx, y0, cap, IL_DIM, IL_RIGHT) + 4.0 * s;
        dlNum(rec.z, 0, rx, y0, val, rec.y > 0.0 ? IL_INK : IL_DIM, IL_RIGHT);
        float dx = r.x + 22.0 * s;
        dx += dlLabel(pdClosed(p) ? LB_CLOSED : LB_OPEN, dx, y1, cap, IL_DIM, IL_LEFT) + 8.0 * s;
        dx += dlInt((int)n, 1, dx, y1, cap, IL_DIM, IL_LEFT) + 4.0 * s;
        dlLabel(LB_ANCHORS, dx, y1, cap, IL_DIM, IL_LEFT);
        // the pen chip: the ink's own colour, toned
        float4 pc = g_L.pen[p];
        bool hotPen = ilIn(pointer, pc);
        dlRectEdged(pc, hotPen ? IL_RAISE * 1.6 : IL_RAISE, 1.0, 2.5 * s, IL_EDGE, 1.0);
        dlCircle(float2(pc.x + 8.0 * s, ilMid(pc).y), 3.5 * s, col, 1.0);
        dlLabelFit(LB_INK_0 + pdPen(p), pc.x + 15.0 * s, ilMid(pc).y, cap, hotPen ? IL_INK : IL_MID, IL_LEFT, pc.z - pc.x - 18.0 * s);
    }

    // the plot's totals
    float4 pl = g_L.plot;
    float4 h = P[PLOT_HEAD];
    dlLabel(LB_PLOT, pl.x + 2.0 * s, pl.y + 8.0 * s, IL_T_TITLE * s, IL_DIM, IL_LEFT);
    float y = pl.y + 30.0 * s;
    dlLabel(LB_PEN_DOWN, pl.x + 2.0 * s, y, cap, IL_DIM, IL_LEFT);
    float vx = pl.z - 4.0 * s;
    vx -= dlLabel(LB_PX, vx, y, cap, IL_DIM, IL_RIGHT) + 4.0 * s;
    dlNum(h.y, 0, vx, y, val, IL_INK, IL_RIGHT);
    y += 20.0 * s;
    dlLabel(LB_TRAVEL, pl.x + 2.0 * s, y, cap, IL_DIM, IL_LEFT);
    vx = pl.z - 4.0 * s;
    vx -= dlLabel(LB_PX, vx, y, cap, IL_DIM, IL_RIGHT) + 4.0 * s;
    dlNum(travel, 0, vx, y, val, IL_INK, IL_RIGHT);
    y += 20.0 * s;
    dlLabel(LB_ANCHORS, pl.x + 2.0 * s, y, cap, IL_DIM, IL_LEFT);
    dlNum(h.w, 0, pl.z - 4.0 * s, y, val, IL_INK, IL_RIGHT);
    y += 20.0 * s;
    dlLabel(LB_NPATHS, pl.x + 2.0 * s, y, cap, IL_DIM, IL_LEFT);
    float px2 = pl.z - 4.0 * s;
    px2 -= dlInt((int)PD_PATHS, 1, px2, y, val, IL_DIM, IL_RIGHT);
    px2 -= dlLabel(LB_SLASH, px2, y, cap, IL_DIM, IL_RIGHT);
    dlInt((int)paths, 1, px2, y, val, IL_INK, IL_RIGHT);

    // the anchor kinds, as the stage draws them
    float ly = pl.w - 12.0 * s;
    [loop] for (uint kd = 0u; kd < 4u; kd++)
    {
        float lx = pl.x + 8.0 * s + (kd % 2u) * 92.0 * s;
        float yy = ly - (1u - kd / 2u) * 20.0 * s;
        anchorGlyph(float2(lx, yy), kd, IL_MID, false, 4.0 * s);
        dlLabel(LB_KIND_0 + kd, lx + 12.0 * s, yy, cap, IL_DIM, IL_LEFT);
    }
}

// ---------------------------------------------------------------- the stage
void stageBack()
{
    float s = g_s;
    float4 st = g_L.stage;
    dlRect(g_L.area, IL_WELL, 1.0, 2.0 * s);
    dlRect(st, IL_PANEL, 1.0, 0.0);
    // program grid: 80 px, every fourth line a step brighter
    [loop] for (uint gx = 1u; gx < 16u; gx++)
        dlVLine(st.x + gx * 80.0 * g_L.k, st.y, st.w, (gx % 4u == 0u) ? IL_EDGE : IL_GRID);
    [loop] for (uint gy = 1u; gy < 9u; gy++)
        dlHLine(st.y + gy * 80.0 * g_L.k, st.x, st.z, (gy % 4u == 0u) ? IL_EDGE : IL_GRID);
    dlBorderRect(st, 0.0, IL_RULE, 1.0);
}

// the pen-up moves in plot order, the order numbers and each path's direction; returns the travel
float travelMoves()
{
    float s = g_s;
    float2 at = PLOT_HOME;
    float travel = 0.0;
    float2 hm = scr(PLOT_HOME);
    dlLine(hm - float2(5.0 * s, 0.0), hm + float2(5.0 * s, 0.0), 1.0 * s, IL_DIM, 1.0);
    dlLine(hm - float2(0.0, 5.0 * s), hm + float2(0.0, 5.0 * s), 1.0 * s, IL_DIM, 1.0);
    uint order = 0u;
    [loop] for (uint p = 0u; p < PD_PATHS; p++)
    {
        float4 r = pathRec(p);
        if (r.y < 2.0) continue;
        float4 a = sampleAt((uint)r.x), b = sampleAt((uint)r.x + (uint)r.y - 1u);
        travel += length(a.xy - at);
        dlDashed(scr(at), scr(a.xy), 1.0 * s, IL_DIM, 0.55, 3.0 * s, 5.0 * s);
        // the start: a chevron along the heading, and the plot order
        float2 c = scr(a.xy), t = float2(cos(a.z), sin(a.z)), n = float2(-t.y, t.x);
        float2 tip = c + t * 10.0 * s;
        dlLine(tip, tip - t * 6.0 * s + n * 4.0 * s, 1.25 * s, pathCol(p), 1.0);
        dlLine(tip, tip - t * 6.0 * s - n * 4.0 * s, 1.25 * s, pathCol(p), 1.0);
        order++;
        dlInt((int)order, 1, c.x - n.x * 12.0 * s - t.x * 6.0 * s, c.y - n.y * 12.0 * s - t.y * 6.0 * s, IL_T_CAP * s, IL_DIM, IL_CENTER);
        at = b.xy;
    }
    if (order > 0u)
    {
        travel += length(PLOT_HOME - at);
        dlDashed(scr(at), hm, 1.0 * s, IL_DIM, 0.55, 3.0 * s, 5.0 * s);
    }
    return travel;
}

void stageFront(PdRec v1, PdRec v2, float2 pointer)
{
    float s = g_s;
    float4 st = g_L.stage;
    uint mode = (uint)v1.c, target = (uint)v1.d;
    bool pen = (g_flags & PD_PEN) != 0u;
    bool inStage = ilIn(pointer, st) && mode == 0u;
    uint hotAnchor = inStage ? pdHitAnchor(g_L, g_pk, pointer, 8.0 * s) : 0xFFFFu;
    uint hotHandle = (inStage && !pen) ? pdHitHandle(g_L, g_pk, pointer, 8.0 * s) : 0xFFFFu;

    // handles of the selected anchors, under the anchors
    [loop] for (uint p = 0u; p < PD_PATHS; p++)
    {
        uint n = pdCount(g_pk, p);
        [loop] for (uint j = 0u; j < n; j++)
        {
            PdRec r = pdAnchor(p, j);
            if (!pdSel(r.e) || pdKind(r.e) == PD_CORNER) continue;
            float2 c = scr(r.a);
            [loop] for (uint side = 0u; side < 2u; side++)
            {
                bool shown = side == 0u ? pdShowsIn(g_pk, p, j) : pdShowsOut(g_pk, p, j);
                if (!shown) continue;
                float2 q = scr(r.a + (side == 0u ? r.b : pdOut(r)));
                uint id = (p * PD_AMAX + j) * 2u + side;
                bool dragged = (mode == DM_HANDLE && target == id);
                dlLine(c, q, 1.0 * s, IL_MID, 1.0);
                dlCircle(q, 3.5 * s, dragged ? IL_ACCENT : IL_INK, 1.0);
                if (hotHandle == id) dlRing(q, 7.0 * s, 1.0 * s, IL_INK, 1.0);
            }
        }
    }
    // anchors: square corner, disc smooth, ring aligned, diamond broken; selected in amber
    [loop] for (uint p2 = 0u; p2 < PD_PATHS; p2++)
    {
        uint n = pdCount(g_pk, p2);
        float3 col = pathCol(p2);
        [loop] for (uint j = 0u; j < n; j++)
        {
            PdRec r = pdAnchor(p2, j);
            bool sel = pdSel(r.e);
            float2 c = scr(r.a);
            anchorGlyph(c, pdKind(r.e), sel ? IL_ACCENT : col, sel, 4.0 * s);
            if (hotAnchor == p2 * PD_AMAX + j && hotHandle == 0xFFFFu) dlRing(c, 8.5 * s, 1.0 * s, IL_INK, 1.0);
        }
    }

    // the pen: the next segment as it would be, and the close target
    if (pen && ilIn(pointer, st) && mode == 0u)
    {
        uint paths = pdPaths(g_pk);
        float2 q = pdProg(g_L, pointer);
        bool open = (g_flags & PD_DRAWING) != 0u && g_active < paths && !pdClosed(g_active) && pdCount(g_pk, g_active) >= 1u;
        if (open)
        {
            uint n = pdCount(g_pk, g_active);
            PdRec last = pdAnchor(g_active, n - 1u);
            bool closing = n >= 2u && length(scr(pdAnchor(g_active, 0u).a) - pointer) < 8.0 * s;
            float2 end = closing ? pdAnchor(g_active, 0u).a : q;
            float2 c1 = last.a + pdOut(last), c2 = closing ? end + pdAnchor(g_active, 0u).b : end;
            float2 prev = scr(last.a);
            [loop] for (uint i = 1u; i <= 16u; i++)
            {
                float2 cur = scr(pdBez(last.a, c1, c2, end, i / 16.0));
                dlLine(prev, cur, 1.0 * s, IL_MID, 0.85);
                prev = cur;
            }
            if (closing) dlRing(scr(end), 9.0 * s, 1.25 * s, IL_INK, 1.0);
        }
        dlLine(pointer - float2(7.0 * s, 0.0), pointer + float2(7.0 * s, 0.0), 1.0 * s, IL_INK, 1.0);
        dlLine(pointer - float2(0.0, 7.0 * s), pointer + float2(0.0, 7.0 * s), 1.0 * s, IL_INK, 1.0);
    }

    // the plotter's pen, when a ref() expression feeds it in: a live reading
    if (pen_d >= 0.0)
    {
        float2 c = scr(float2(pen_x, pen_y));
        if (pen_down > 0.5)
        {
            dlRing(c, 7.0 * s, 1.5 * s, IL_ACCENT, 1.0);
            dlCircle(c, 2.0 * s, IL_ACCENT, 1.0);
        }
        else dlEllipse(c, float2(7.0, 7.0) * s, 1.25 * s, IL_ACCENT, 1.0, 3.0 * s, 3.0 * s);
    }

    if (mode == DM_BOX)
    {
        float4 box = float4(min(v1.a, v2.b), max(v1.a, v2.b));
        dlRectEdged(box, IL_INK, 0.06, 0.0, IL_INK, 1.0 * s);
    }
}

// ---------------------------------------------------------------- the strip
void stripBack()
{
    float s = g_s;
    float4 st = g_L.strip;
    dlRect(st, IL_WELL, 1.0, IL_RADIUS * s);
    dlLabel(LB_CURVATURE, st.x + 10.0 * s, st.y + 12.0 * s, IL_T_TITLE * s, IL_INK, IL_LEFT);
    dlLabel(LB_ALONG, st.x + 12.0 * s + ilLabelW(LB_CURVATURE, IL_T_TITLE * s) + 10.0 * s, st.y + 12.0 * s, IL_T_CAP * s, IL_DIM, IL_LEFT);
    static const float RADII[5] = { 10.0, 30.0, 100.0, 300.0, 1000.0 };
    [loop] for (uint i = 0u; i < 5u; i++)
    {
        float y = stripY(1.0 / RADII[i]);
        dlHLine(y, stripX0() - 4.0 * s, stripX1(), (i % 2u == 0u) ? IL_EDGE : IL_GRID);
        float x = st.x + 8.0 * s;
        x += dlLabel(LB_R, x, y, IL_T_CAP * s, IL_DIM, IL_LEFT) + 3.0 * s;
        dlInt((int)RADII[i], 1, x, y, IL_T_CAP * s, IL_DIM, IL_LEFT);
    }
    dlHLine(stripY(0.0), stripX0() - 4.0 * s, stripX1(), IL_RULE);
}

void stripFront(float scale)
{
    float s = g_s;
    float4 st = g_L.strip;
    float base = stripY(0.0);
    [loop] for (uint p = 0u; p < PD_PATHS; p++)
    {
        float4 r = pathRec(p);
        if (r.y < 2.0) continue;
        float x0 = stripStart(p, scale);
        dlInt((int)p + 1, 1, x0 + 2.0 * s, st.y + 30.0 * s, IL_T_CAP * s, IL_DIM, IL_LEFT);
        uint n = pdCount(g_pk, p);
        [loop] for (uint j = 0u; j < n; j++)
        {
            float4 a = P[PLOT_ANCHOR0 + p * PD_AMAX + j];
            PdRec rec = pdAnchor(p, j);
            bool corner = abs(a.y) > 0.02;
            float x = x0 + a.x * scale;
            float hgt = corner ? 9.0 * s : 4.0 * s;
            dlRect(float4(x - 0.75 * s, base + 2.0 * s, x + 0.75 * s, base + 2.0 * s + hgt), pdSel(rec.e) ? IL_ACCENT : (corner ? IL_MID : IL_DIM), 1.0, 0.0);
        }
    }
    // the plotter's pen along the plot
    if (pen_d >= 0.0)
    {
        float d = pen_d, x = stripX0();
        [loop] for (uint q = 0u; q < PD_PATHS; q++)
        {
            float4 r = pathRec(q);
            if (r.y < 2.0) continue;
            if (d <= r.z) { x += d * scale; break; }
            d -= r.z;
            x += r.z * scale + stripGap();
        }
        x = min(x, stripX1());
        dlLine(float2(x, st.y + 22.0 * s), float2(x, st.w - 4.0 * s), 1.25 * s, IL_ACCENT, 0.9);
    }
}

// ---------------------------------------------------------------- hint bar: the verbs that apply now
void hints(uint set)
{
    float s = g_s;
    uint k0 = set == 2u ? LB_K_C0 : (set == 1u ? LB_K_B0 : LB_K_A0);
    uint d0 = set == 2u ? LB_D_C0 : (set == 1u ? LB_D_B0 : LB_D_A0);
    uint pairs = set == 0u ? 7u : 6u;
    float kh = 18.0 * s;
    float bx = g_L.hint.x, by = ilMid(g_L.hint).y;
    float total = 0.0;
    [loop] for (uint a = 0u; a < pairs; a++)
        total += ilLabelW(k0 + a, IL_T_CAP * s) + 12.0 * s + 6.0 * s + ilLabelW(d0 + a, IL_T_CAP * s) + 16.0 * s;
    plate(float4(bx, by - 15.0 * s, bx + total + 8.0 * s, by + 15.0 * s));
    bx += 10.0 * s;
    [loop] for (uint b = 0u; b < pairs; b++)
    {
        float kw = ilLabelW(k0 + b, IL_T_CAP * s) + 12.0 * s;
        float dw = ilLabelW(d0 + b, IL_T_CAP * s);
        dlKeycap(float4(bx, by - kh * 0.5, bx + kw, by + kh * 0.5), s, k0 + b);
        dlLabel(d0 + b, bx + kw + 6.0 * s, by, IL_T_CAP * s, IL_DIM, IL_LEFT);
        bx += kw + 6.0 * s + dw + 16.0 * s;
    }
}

// ---------------------------------------------------------------- thread 0
void layout(uint pieces, uint comb, uint strip, float scale)
{
    float2 res = _Resolution.xy;
    dlBegin(res);
    PdRec v1 = S[PD_V1], v2 = S[PD_V2];
    float2 pointer = v1.b;

    uint nsel = 0u, selId = 0u;
    [loop] for (uint p = 0u; p < PD_PATHS; p++)
    {
        uint n = pdCount(g_pk, p);
        [loop] for (uint j = 0u; j < n; j++)
            if (pdSel(pdAnchor(p, j).e)) { nsel++; selId = p * PD_AMAX + j; }
    }

    header(nsel, selId, pointer);
    plate(g_L.block);
    stageBack();
    dlClip(g_L.stage);
    float travel = travelMoves();
    dlBatch(comb * 2u, 0u);       // batch 0: the comb, two slots a hair
    dlBatch(pieces, 0u);          // batch 1: the paths
    dlClip(float4(0.0, 0.0, res));
    dlClip(g_L.area);
    stageFront(v1, v2, pointer);
    dlClip(float4(0.0, 0.0, res));
    pathsList(pointer, travel);
    stripBack();
    dlBatch(strip, 0u);           // batch 2: the strip
    stripFront(scale);
    hints((g_flags & PD_PEN) != 0u ? 2u : (nsel > 0u ? 1u : 0u));
    dlFinish();
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    float2 res = _Resolution.xy;
    g_s = ilCtx(res).s;
    PdRec v1 = S[PD_V1];
    g_pk = S[PD_P0].e;
    g_flags = v1.e;
    g_active = v1.f;
    g_L = pdLayout(res, g_s);

    // 1. plans
    if (gi < PD_PATHS)
    {
        uint segs = pdSegs(g_pk, gi);
        uint acc = 0u;
        gsOff[gi][0] = 0u;
        [loop] for (uint k = 0u; k < segs; k++)
        {
            acc += piecesFor(gi, k);
            gsOff[gi][k + 1u] = acc;
        }
        gsTot[gi] = acc;
    }
    else if (gi == PD_PATHS)
    {
        uint n = (g_active < PD_PATHS && (g_flags & PD_NOCOMB) == 0u) ? (uint)pathRec(g_active).y : 0u;
        uint stride = max(1u, (n + PD_COMB - 1u) / PD_COMB);
        gsCombStride = stride;
        gsComb = n >= 2u ? (n - 1u) / stride + 1u : 0u;
    }
    else if (gi == PD_PATHS + 1u)
    {
        float width = max(g_L.strip.z - g_L.strip.x - 58.0 * g_s, 1.0);
        uint used = (uint)P[PLOT_HEAD].z;
        uint stride = max(1u, (uint)ceil((float)used / (width / (2.5 * g_s))));
        gsStripStride = stride;
        uint acc = 0u;
        [loop] for (uint p = 0u; p < PD_PATHS; p++)
        {
            gsStripOff[p] = acc;
            uint n = (uint)pathRec(p).y;
            if (n >= 2u) acc += (n - 2u) / stride + 1u;
        }
        gsStripOff[PD_PATHS] = acc;
    }
    GroupMemoryBarrierWithGroupSync();
    uint base[PD_PATHS + 1u];
    base[0] = 0u;
    [unroll] for (uint q = 0u; q < PD_PATHS; q++) base[q + 1u] = base[q] + gsTot[q];
    uint pieces = min(base[PD_PATHS], PD_PIECES);
    uint comb = min(gsComb, PD_COMB);
    uint strip = min(gsStripOff[PD_PATHS], PD_STRIP);
    float scale = stripScale();

    // 2. everything else
    if (gi == 0u) layout(pieces, comb, strip, scale);
    dlSync();

    // 3. pieces, hairs, strip lines
    ILBatch b0 = dlGetBatch(1u);
    [loop] for (uint g = gi; g < pieces; g += IL_LAYOUT_THREADS)
    {
        uint p = 0u;
        [loop] while (p + 1u < PD_PATHS && base[p + 1u] <= g) p++;
        uint local = g - base[p];
        uint k = 0u;
        [loop] while (gsOff[p][k + 1u] <= local) k++;
        dlAt(b0, g);
        piece(p, k, local - gsOff[p][k], gsOff[p][k + 1u] - gsOff[p][k]);
    }
    ILBatch b1 = dlGetBatch(0u);
    [loop] for (uint c = gi; c < comb; c += IL_LAYOUT_THREADS)
    {
        dlAtSpan(b1, c, 2u);
        combPiece(c);
    }
    ILBatch b2 = dlGetBatch(2u);
    [loop] for (uint t = gi; t < strip; t += IL_LAYOUT_THREADS)
    {
        uint p = 0u;
        [loop] while (p + 1u < PD_PATHS && gsStripOff[p + 1u] <= t) p++;
        dlAt(b2, t);
        stripPiece(p, t - gsStripOff[p], scale);
    }
    dlEnd(gi);
}
