// Mapping_Editor / layout - the editing canvas's chrome, recorded for the shared UI kit (ui.hlsl
// draws it over editor.hlsl's drawing): the title and the mapping's validity, the side panel (edit
// mode, mask tools, one row per mask - drawn in the very rects canvas.hlsl hit-tests, from
// masks.hlsli), the hover highlights and the inspector card, and the verbs for the current mode.
//
// Hover is a read of the pointer snapshot and is never stored, and it follows the reducer's own
// rules: over the panel, the target under the pointer lights; on the canvas in mapping mode, the
// handle a press would take (canvas.hlsl's radius); in masks mode, the topmost mask a press would
// take. While a handle or a mask is held, the card follows it with its live values. The Tooltips
// parameter turns the card off; the halos stay.
//
// The panel's geometry is fixed pixels (it is part of the hit test), so the whole layout is too.
#include "mapping.hlsli"                               // Points (t1), controlPoint()
StructuredBuffer<float4> Calib : register(t0);
StructuredBuffer<float4> C : register(t2);
StructuredBuffer<float4> M : register(t4);
#include "canvas_view.hlsli"
#include "masks.hlsli"
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"

static float2 g_res;

float4 kr(float4 b) { return float4(b.xy, b.xy + b.zw); }    // masks.hlsli (x, y, w, h) -> kit rect
float scanPixels() { return C[0].z * canvasScale() / (2.5 * extent_a); }
bool isCorner(int k) { return k == 0 || k == 4 || k == 20 || k == 24; }

// ---------------------------------------------------------------- the side panel
// a tool chip: the chosen tool carries the accent tick; the labels stay dim until masks are edited
void toolChip(float4 r, uint label, bool on, bool hot, bool live)
{
    float3 face = on ? IL_RAISE * 1.9 : (hot ? IL_RAISE * 1.45 : IL_RAISE);
    dlRectEdged(r, face, 1.0, IL_RADIUS, on ? IL_RULE : IL_EDGE, 1.0);
    if (on) dlRect(float4(r.x + 6.0, r.w - 3.0, r.z - 6.0, r.w - 1.0), IL_ACCENT, 1.0, 1.0);
    dlLabel(label, ilMid(r).x, ilMid(r).y, IL_T_BODY, on ? IL_INK : (live ? (hot ? IL_MID * 1.2 : IL_MID) : IL_DIM), IL_CENTER);
}

// a chip inside a mask row: lifted when engaged (no accent: that belongs to the selected mask)
void rowChip(float4 r, uint label, bool lifted, bool hot, float3 ink)
{
    float3 face = lifted ? IL_RAISE * 1.9 : (hot ? IL_RAISE * 1.45 : IL_RAISE);
    dlRectEdged(r, face, 1.0, 2.0, lifted ? IL_RULE : IL_EDGE, 1.0);
    dlLabel(label, ilMid(r).x, ilMid(r).y, IL_T_CAP, ink, IL_CENTER);
}

// one mask row: number, kind (or "drawing" while its polygon is open), Block / Only-In, On, delete
void maskRow(uint j, float2 p, bool live, int sel, int build)
{
    float4 info = maskInfo(j);
    bool on = info.z > 0.5, block = info.y < 0.5, picked = (int)j == sel, drawing = (int)j == build;
    float4 b = kr(rowBox(j));
    bool hotRow = live && inBox(p, rowBox(j));
    dlRectEdged(b, picked ? IL_RAISE * 1.4 : (hotRow ? IL_RAISE : IL_WELL), 1.0, 2.0, IL_EDGE, 1.0);
    if (picked) dlRect(float4(b.x, b.y + 3.0, b.x + 2.0, b.w - 3.0), IL_ACCENT, 1.0, 1.0);
    float y = ilMid(b).y;
    dlInt((int)j + 1, 1, b.x + 17.0, y, IL_T_CAP, on ? IL_MID : IL_DIM, IL_RIGHT);
    uint kind = info.x < 0.5 ? 0u : (info.x < 1.5 ? 1u : 2u);
    dlLabel(drawing ? LB_DRAWING : LB_KIND_0 + kind, b.x + 23.0, y, IL_T_BODY, drawing ? IL_ACCENT : (on ? IL_INK : IL_DIM), IL_LEFT);
    rowChip(kr(rowModeBox(j)), block ? LB_BLOCK : LB_ONLY_IN, false, live && inBox(p, rowModeBox(j)),
            !on ? IL_DIM : (block ? IL_ALARM : IL_INK));
    rowChip(kr(rowOnBox(j)), on ? LB_ON : LB_OFF, on, live && inBox(p, rowOnBox(j)), on ? IL_INK : IL_DIM);
    // delete: a drawn cross
    float4 d = kr(rowDeleteBox(j));
    bool hd = live && inBox(p, rowDeleteBox(j));
    dlRectEdged(d, hd ? IL_RAISE * 1.45 : IL_RAISE, 1.0, 2.0, IL_EDGE, 1.0);
    float2 c = ilMid(d);
    float3 xi = hd ? IL_INK : IL_DIM;
    dlLine(c - 3.5, c + 3.5, 1.25, xi, 1.0);
    dlLine(c + float2(-3.5, 3.5), c + float2(3.5, -3.5), 1.25, xi, 1.0);
}

void panel(float2 p, bool live, uint n, bool maskMode, uint tool, int sel, int build)
{
    float x0 = panelX0();
    dlRectEdged(float4(x0 - 8.0, -4.0, g_res.x + 4.0, panelBottom(n)), IL_PANEL, 0.94, IL_RADIUS, IL_EDGE, 1.0);
    // edit mode: the chosen tab carries the accent tick
    [unroll] for (uint i = 0u; i < 2u; i++)
        dlChip(kr(tabBox(i)), 1.0, LB_TAB_0 + i, (i == 1u) == maskMode, live && inBox(p, tabBox(i)), false);
    // what a drag on empty space draws
    [unroll] for (uint t = 0u; t < 3u; t++)
        toolChip(kr(toolBox(t)), LB_TOOL_0 + t, maskMode && tool == t, live && inBox(p, toolBox(t)), maskMode);
    if (n == 0u) dlLabel(LB_NO_MASKS, x0 + 8.0, ROW_Y0 + 11.0, IL_T_BODY, IL_DIM, IL_LEFT);
    [loop] for (uint j = 0u; j < n; j++) maskRow(j, p, live, sel, build);
}

// ---------------------------------------------------------------- hover: what a press would take
int nearestHandle(float2 p)
{
    float best = 1e9;
    int chosen = -1;
    [loop] for (int k = 0; k < 25; k++)
    {
        float d = length(canvasPixel(controlPoint(k), C[0]) - p);
        if (d < (isCorner(k) ? 16.0 : 11.0) && d < best) { best = d; chosen = k; }
    }
    return chosen;
}

int maskUnder(float2 p, uint n)
{
    float2 q = worldToScan(canvasWorld(p / g_res, C[0]));
    int found = -1;
    [loop] for (int j = (int)n - 1; j >= 0; j--)
        if (found < 0 && maskDistance((uint)j, q) * scanPixels() < 4.0) found = j;
    return found;
}

// a held or hovered handle: a ring outside its own, a value step up
void handleHalo(int k)
{
    float2 c = canvasPixel(controlPoint(k), C[0]);
    dlRing(c, (isCorner(k) ? 11.0 : 6.0) + 4.5, 1.5, IL_INK, 0.6);
}

// a hovered mask: a soft ink halo along its outline (rect corners, an ellipse in 48 chords, or the
// polygon's own points, closed once it has three)
float2 outlinePt(float4 info, float4 r, uint j, uint i, uint segs)
{
    if (info.x > 1.5) return polyPoint(j, i % max(polyCount(j), 1u));
    if (info.x < 0.5) { uint c = i % 4u; return cornerOf(info, r, c == 0u ? 0u : (c == 1u ? 1u : (c == 2u ? 3u : 2u))); }
    float t = 6.2831853 * (float)i / (float)segs;
    return r.xy + rot(r.zw * float2(cos(t), sin(t)), info.w);
}
void maskHalo(uint j)
{
    float4 info = maskInfo(j), r = maskRect(j);
    uint np = polyCount(j);
    uint segs = info.x > 1.5 ? (np >= 3u ? np : (np > 0u ? np - 1u : 0u)) : (info.x < 0.5 ? 4u : 48u);
    [loop] for (uint i = 0u; i < segs; i++)
    {
        float2 a = canvasPixel(scanToWorld(outlinePt(info, r, j, i, segs)), C[0]);
        float2 b = canvasPixel(scanToWorld(outlinePt(info, r, j, i + 1u, segs)), C[0]);
        dlLine(a, b, 6.0, IL_INK, 0.22);
    }
}

// ---------------------------------------------------------------- the inspector card
// beside the pointer, flipped away from the edges, the panel and the footer
float2 cardAt(float2 at, float w, float h, uint n)
{
    float x0 = at.x + 18.0, y0 = at.y + 18.0;
    float right = (y0 < panelBottom(n) + 8.0) ? panelX0() - 16.0 : g_res.x - 8.0;
    if (x0 + w > right) x0 = at.x - 18.0 - w;
    if (y0 + h > g_res.y - 40.0) y0 = at.y - 18.0 - h;
    return max(float2(x0, y0), float2(8.0, 44.0));
}

// one row: caption left, value(s) right with the unit after (two values joined by `sep`)
void cardRow(float cx, float vx, float y, uint capL, uint nums, float v0, float v1, int dec, uint sep, uint unit, uint word, float3 wordInk)
{
    dlLabel(capL, cx, y, IL_T_CAP, IL_DIM, IL_LEFT);
    if (nums == 0u)
    {
        dlLabel(word, vx, y, IL_T_BODY, wordInk, IL_RIGHT);
        return;
    }
    float xr = vx - dlLabel(unit, vx, y, IL_T_CAP, IL_DIM, IL_RIGHT) - 4.0;
    xr -= dlNum(nums == 2u ? v1 : v0, dec, xr, y, IL_T_VALUE, IL_INK, IL_RIGHT);
    if (nums == 2u)
    {
        xr -= 4.0;
        xr -= dlLabel(sep, xr, y, IL_T_CAP, IL_DIM, IL_RIGHT) + 4.0;
        dlNum(v0, dec, xr, y, IL_T_VALUE, IL_INK, IL_RIGHT);
    }
}

// A handle: where it puts that lattice point in the laser's field (+y up), and how far it bends
// the lattice off the pure perspective of the corners (the Calibration's own residual).
void handleCard(int k, float2 at, uint n, bool sel)
{
    bool corner = isCorner(k);
    bool edge = !corner && (k % 5 == 0 || k % 5 == 4 || k / 5 == 0 || k / 5 == 4);
    float2 q = worldToScan(controlPoint(k));
    float bend = length(Calib[4 + k].xy) * 2.0 * extent_a;
    float w = 232.0, h = 36.0 + 18.0 * 3.0;
    float2 o = cardAt(at, w, h, n);
    dlRectEdged(float4(o, o + float2(w, h)), IL_RAISE, 1.0, IL_RADIUS, IL_EDGE, 1.0);
    float ty = o.y + 15.0, tx = o.x + 10.0;
    float3 tc = sel ? IL_ACCENT : IL_INK;
    tx += dlLabel(LB_I_HANDLE, tx, ty, IL_T_TITLE, tc, IL_LEFT) + 5.0;
    tx += dlInt(k + 1, 1, tx, ty, IL_T_VALUE, tc, IL_LEFT) + 9.0;
    dlLabel(corner ? LB_H_CORNER : (edge ? LB_H_EDGE : LB_H_INNER), tx, ty, IL_T_BODY, IL_MID, IL_LEFT);
    dlHLine(o.y + 29.0, o.x + 1.0, o.x + w - 1.0, IL_EDGE);
    float cx = o.x + 10.0, vx = o.x + w - 10.0, y = o.y + 44.0;
    cardRow(cx, vx, y, LB_I_AT, 2u, q.x, -q.y, 3, LB_U_COMMA, LB_U_FIELD, 0u, IL_INK);
    cardRow(cx, vx, y + 18.0, LB_I_BEND, 1u, corner ? 0.0 : bend, 0.0, 4, LB_U_COMMA, LB_U_FIELD, 0u, IL_INK);
    dlLabelFit(corner ? LB_H_NOTE_C : LB_H_NOTE_B, cx, y + 36.0, IL_T_CAP, IL_DIM, IL_LEFT, w - 20.0);
}

// A mask: kind, mode and state; where it sits (field units, +y up), its size and turn, or its
// points; and the margin Adaptive Mapping cuts it with.
void maskCard(uint j, float2 at, uint n, bool sel)
{
    float4 info = maskInfo(j), r = maskRect(j);
    bool poly = info.x > 1.5, on = info.z > 0.5, block = info.y < 0.5;
    uint np = polyCount(j);
    uint rows = poly ? 3u : 4u;
    float w = 248.0, h = 36.0 + 18.0 * (float)rows;
    float2 o = cardAt(at, w, h, n);
    dlRectEdged(float4(o, o + float2(w, h)), IL_RAISE, 1.0, IL_RADIUS, IL_EDGE, 1.0);
    float ty = o.y + 15.0, tx = o.x + 10.0;
    float3 tc = sel ? IL_ACCENT : IL_INK;
    tx += dlLabel(LB_I_MASK, tx, ty, IL_T_TITLE, tc, IL_LEFT) + 5.0;
    tx += dlInt((int)j + 1, 1, tx, ty, IL_T_VALUE, tc, IL_LEFT) + 9.0;
    uint kind = info.x < 0.5 ? 0u : (info.x < 1.5 ? 1u : 2u);
    tx += dlLabel(LB_KIND_0 + kind, tx, ty, IL_T_BODY, IL_MID, IL_LEFT) + 10.0;
    float rx = o.x + w - 10.0;
    if (!on) rx -= dlLabel(LB_OFF, rx, ty, IL_T_CAP, IL_DIM, IL_RIGHT) + 8.0;
    dlLabel(block ? LB_BLOCK : LB_ONLY_IN, rx, ty, IL_T_CAP, !on ? IL_DIM : (block ? IL_ALARM : IL_INK), IL_RIGHT);
    dlHLine(o.y + 29.0, o.x + 1.0, o.x + w - 1.0, IL_EDGE);
    float2 ctr = r.xy;
    if (poly)
    {
        float2 acc = 0.0;
        [loop] for (uint i = 0u; i < np; i++) acc += polyPoint(j, i);
        ctr = acc / max((float)np, 1.0);
    }
    float cx = o.x + 10.0, vx = o.x + w - 10.0, y = o.y + 44.0;
    [loop] for (uint k = 0u; k < rows; k++)
    {
        uint capL = LB_I_CENTRE, nums = 2u, unit = LB_U_FIELD, sep = LB_U_COMMA, word = LB_GROWS;
        float v0 = ctr.x, v1 = -ctr.y;
        int dec = 3;
        float3 wi = IL_INK;
        bool marginRow = k == rows - 1u;
        if (poly && k == 0u) { capL = LB_I_POINTS; nums = 1u; v0 = (float)np; dec = 0; unit = LB_U_COMMA; }
        else if (!poly && k == 1u) { capL = LB_I_SIZE; v0 = 2.0 * r.z; v1 = 2.0 * r.w; sep = LB_U_TIMES; }
        else if (!poly && k == 2u) { capL = LB_I_ANGLE; nums = 1u; v0 = degrees(info.w); dec = 1; unit = LB_U_DEG; }
        else if (marginRow) { capL = LB_I_MARGIN; nums = 1u; v0 = mask_margin; unit = block ? LB_GROWS : LB_SHRINKS; }
        if (poly && k == 0u)
        {
            // a bare count: no unit
            dlLabel(capL, cx, y, IL_T_CAP, IL_DIM, IL_LEFT);
            dlInt((int)np, 1, vx, y, IL_T_VALUE, IL_INK, IL_RIGHT);
        }
        else cardRow(cx, vx, y, capL, nums, v0, v1, dec, sep, unit, word, wi);
        y += 18.0;
    }
}

// ---------------------------------------------------------------- the footer: readouts and verbs
float verbW(uint key, uint does) { return ilLabelW(key, IL_T_CAP) + 34.0 + ilLabelW(does, IL_T_CAP); }
float verb(float x, float y, uint key, uint does)
{
    float kw = ilLabelW(key, IL_T_CAP) + 12.0, kh = 18.0;
    dlKeycap(float4(x, y - 0.5 * kh, x + kw, y + 0.5 * kh), 1.0, key);
    return kw + 6.0 + dlLabel(does, x + kw + 6.0, y, IL_T_CAP, IL_DIM, IL_LEFT) + 16.0;
}

void footer(bool maskMode, int build, uint n)
{
    float2 R = g_res;
    float fy = R.y - 16.0;
    dlRect(float4(0.0, R.y - 32.0, R.x, R.y), IL_FIELD, 0.82, 0.0);
    dlHLine(R.y - 32.0, 0.0, R.x, IL_EDGE);
    bool drawing = maskMode && build >= 0 && build < (int)n;
    // right: the view's zoom, then what this mode counts against its limit
    float rx = R.x - 14.0;
    rx -= dlNum(C[0].z, 2, rx, fy, IL_T_VALUE, IL_INK, IL_RIGHT) + 6.0;
    rx -= dlLabel(LB_ZOOM, rx, fy, IL_T_TITLE, IL_DIM, IL_RIGHT) + 22.0;
    uint have = drawing ? polyCount((uint)build) : (maskMode ? n : (uint)clamp(C[4].x, 0.0, 25.0));
    uint limit = drawing ? (uint)POLY_MAX : (maskMode ? (uint)MASK_MAX : 25u);
    rx -= dlInt((int)limit, 1, rx, fy, IL_T_VALUE, IL_MID, IL_RIGHT) + 5.0;
    rx -= dlLabel(LB_OF, rx, fy, IL_T_CAP, IL_DIM, IL_RIGHT) + 5.0;
    rx -= dlInt((int)have, 1, rx, fy, IL_T_VALUE, IL_INK, IL_RIGHT) + 6.0;
    rx -= dlLabel(drawing ? LB_N_POINTS : (maskMode ? LB_N_MASKS : LB_SELECTED), rx, fy, IL_T_TITLE, IL_DIM, IL_RIGHT) + 24.0;
    // left: the verbs of this mode, as many as fit
    uint k0 = drawing ? LB_PK_0 : (maskMode ? LB_SK_0 : LB_MK_0);
    uint d0 = drawing ? LB_PD_0 : (maskMode ? LB_SD_0 : LB_MD_0);
    uint cnt = drawing ? 5u : (maskMode ? 7u : 9u);
    float x = 14.0;
    [loop] for (uint i = 0u; i < cnt; i++)
    {
        if (x + verbW(k0 + i, d0 + i) > rx) break;
        x += verb(x, fy, k0 + i, d0 + i);
    }
}

// ---------------------------------------------------------------- the title band
void title(bool valid)
{
    float right = panelX0() - 8.0;
    dlRect(float4(0.0, 0.0, right, 38.0), IL_FIELD, 0.82, 0.0);
    float hy = 21.0;
    float x = 14.0;
    x += dlLabel(LB_TITLE, x, hy, 14.0, IL_INK, IL_LEFT) + 10.0;
    x += dlLabel(LB_SUBTITLE, x, hy, 12.0, IL_DIM, IL_LEFT) + 22.0;
    if (valid) return;
    x += dlLabel(LB_INVALID, x, hy, IL_T_TITLE, IL_ALARM, IL_LEFT) + 10.0;
    dlLabelFit(LB_INVALID_D, x, hy, IL_T_CAP, IL_DIM, IL_LEFT, right - x - 12.0);
}

// ---------------------------------------------------------------- thread 0
void layout()
{
    float2 R = g_res;
    dlBegin(R);
    uint n = maskCount();
    bool maskMode = C[34].x > 0.5;
    uint tool = (uint)clamp(C[34].y, 0.0, 2.0);
    int sel = (int)C[34].z - 1, build = (int)C[34].w - 1;
    uint gesture = (uint)C[2].x;
    bool valid = Calib[0].x > 0.5;

    // the pointer, ignored off the canvas and while the reducer holds a gesture
    float2 pn = _ViewportPointerPosition;
    float2 p = pn * R;
    bool inside = all(pn >= 0.0) && all(pn <= 1.0);
    uint row = 0u;
    uint hit = inside ? panelHit(p, n, row) : 0u;
    bool live = inside && gesture == 0u;

    // what is inspected: what is held, else what a press here would take
    int hHandle = -1, hMask = -1;
    if (gesture == 1u) hHandle = (int)clamp(C[2].z, 0.0, 24.0);
    else if (gesture >= 4u && gesture <= 8u) hMask = (int)C[37].w;
    else if (live && hit >= 30u && hit <= 33u) hMask = (int)row;
    else if (live && hit == 0u) { if (maskMode) hMask = maskUnder(p, n); else hHandle = nearestHandle(p); }
    if (hMask >= (int)n) hMask = -1;

    if (hHandle >= 0) handleHalo(hHandle);
    if (hMask >= 0) maskHalo((uint)hMask);
    title(valid);
    panel(p, live, n, maskMode, tool, sel, build);
    footer(maskMode, build, n);
    // the card beside the pointer (Tooltips): off, the halos above still say what a press would take
    if (tooltips != 0)
    {
        if (hHandle >= 0) handleCard(hHandle, p, n, C[8 + hHandle].x > 0.5);
        else if (hMask >= 0) maskCard((uint)hMask, p, n, hMask == sel);
    }
    // the mapping's validity, along the top edge (red: Adaptive Mapping will not use it)
    dlRect(float4(0.0, 0.0, R.x, 3.0), valid ? IL_RULE : IL_ALARM, 1.0, 0.0);
    dlFinish();
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    g_res = _Resolution.xy;
    if (gi == 0u) layout();
    dlEnd(gi);
}
