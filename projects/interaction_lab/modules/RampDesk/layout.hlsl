// Ramp Desk / layout - the stops, the picker, the ramp with its lanes, and the chrome.
//
// The colour fields themselves (the ramp, the strips, the plane, the hue) come from the swatch pass
// through DL_IMAGE and are drawn exact: in a colour instrument the colours ARE the reading, so they
// skip the theme's inset toning. Everything around them stays on the grey ladder; amber marks the
// selected stop, red a stop or an entry that sRGB cannot show.
//
// 64 threads: each converts four entries to OKLab (groupshared); thread 0 records the chrome and
// reserves one batch for the three curves along the ramp; then every thread draws curve segments.
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"
#include "ramp.hlsli"

#define DM_PIN   1u
#define DM_MID   2u
#define DM_PLANE 3u
#define DM_HUE   4u
#define RD_SEGS  255u
#define C_SCALE  0.32          // the chroma lane's top

groupshared float3 gsLab[PAL_ENTRIES];
groupshared float gsMean;

static RdLayout g_L;
static float g_s;
static float2 g_res;

void plate(float4 r) { dlRect(r, IL_PANEL, 0.86, IL_RADIUS * g_s); }
void field(float4 r) { dlImage(r, r / g_res.xyxy, float3(1.0, 1.0, 1.0), 1.0); }
float3 stopColour(uint i) { return palToDisplay(palLabToLinear(palLchToLab(rdShown(i)))); }
float laneY(uint lane, float v) { float4 r = g_L.lane[lane]; return lerp(r.w - 3.0 * g_s, r.y + 3.0 * g_s, saturate(v)); }
float stepAt(uint k) { return length(gsLab[k + 1u] - gsLab[k]) * 255.0; }
// the step lane reads against the ramp's own mean step: a perfectly even ramp is a flat line at a
// quarter of the lane, a hard edge runs off the top
float stepV(uint k) { return stepAt(k) / max(4.0 * gsMean, 1e-4); }

// one segment of the three curves: 0 lightness, 1 chroma, 2 the step between neighbouring entries
void curveSeg(uint g)
{
    uint c = g / RD_SEGS, k = g % RD_SEGS;
    float s = g_s;
    float x0 = rdX(g_L, (float)k / 255.0), x1 = rdX(g_L, (float)(k + 1u) / 255.0);
    if (c == 0u)
        dlLine(float2(x0, laneY(7u, gsLab[k].x)), float2(x1, laneY(7u, gsLab[k + 1u].x)), 1.25 * s, IL_INK, 1.0);
    else if (c == 1u)
        dlLine(float2(x0, laneY(8u, length(gsLab[k].yz) / C_SCALE)), float2(x1, laneY(8u, length(gsLab[k + 1u].yz) / C_SCALE)), 1.25 * s, IL_INK, 1.0);
    else
    {
        uint k1 = min(k + 1u, RD_SEGS - 1u);
        float xa = rdX(g_L, ((float)k + 0.5) / 255.0), xb = rdX(g_L, ((float)k1 + 0.5) / 255.0);
        dlLine(float2(xa, laneY(9u, stepV(k))), float2(xb, laneY(9u, stepV(k1))), 1.25 * s, IL_INK, k1 > k ? 1.0 : 0.0);
    }
}

// ---------------------------------------------------------------- the header
void header(uint n, uint space)
{
    float s = g_s;
    float4 hd = g_L.head;
    float hy = ilMid(hd).y;
    float tw = ilLabelW(LB_TITLE, 15.0 * s), sw = ilLabelW(LB_SUBTITLE, 12.0 * s);
    float4 hp = float4(hd.x, hd.y, hd.x + tw + sw + 40.0 * s, hd.w);
    plate(hp);
    dlLabel(LB_TITLE, hp.x + 12.0 * s, hy, 15.0 * s, IL_INK, IL_LEFT);
    dlLabel(LB_SUBTITLE, hp.x + 12.0 * s + tw + 14.0 * s, hy, 12.0 * s, IL_DIM, IL_LEFT);

    float cap = IL_T_CAP * s, val = IL_T_VALUE * s;
    float ww = ilNumW(2u, val) + 6.0 * s + ilLabelW(LB_STOPS_L, cap) + 16.0 * s + ilLabelW(LB_BLEND_0 + space, cap) + 24.0 * s;
    float4 sp = float4(hd.z - ww, hd.y, hd.z, hd.w);
    plate(sp);
    float sx = sp.x + 12.0 * s;
    sx += dlInt((int)n, 1, sx, hy, val, IL_INK, IL_LEFT) + 6.0 * s;
    sx += dlLabel(LB_STOPS_L, sx, hy, cap, IL_DIM, IL_LEFT) + 16.0 * s;
    dlLabel(LB_BLEND_0 + space, sx, hy, cap, IL_MID, IL_LEFT);
}

// ---------------------------------------------------------------- the stops
void stopsList(float2 pointer, uint n, uint sel)
{
    float s = g_s;
    float cap = IL_T_CAP * s, val = IL_T_VALUE * s;
    dlLabel(LB_STOPS, g_L.left.x + 2.0 * s, g_L.left.y + 10.0 * s, IL_T_TITLE * s, IL_DIM, IL_LEFT);
    [loop] for (uint i = 0u; i < PAL_STOPS; i++)
    {
        float4 r = rdRow(g_L, i);
        float y = ilMid(r).y;
        if (i >= n)
        {
            dlBorderRect(r, IL_RADIUS * s, IL_EDGE, 1.0);
            if (i == n) dlLabel(LB_FREE, r.x + 12.0 * s, y, cap, IL_DIM, IL_LEFT);
            continue;
        }
        bool hot = ilIn(pointer, r);
        dlRect(r, hot ? IL_RAISE : IL_WELL, 1.0, IL_RADIUS * s);
        if (i == sel)
        {
            dlBorderRect(r, IL_RADIUS * s, IL_RULE, 1.0);
            dlRect(float4(r.x, r.y + 4.0 * s, r.x + 2.0 * s, r.w - 4.0 * s), IL_ACCENT, 1.0, 0.0);
        }
        dlRectEdged(float4(r.x + 10.0 * s, y - 6.0 * s, r.x + 22.0 * s, y + 6.0 * s), stopColour(i), 1.0, 2.0 * s, IL_EDGE, 1.0);
        float3 a = rdAsked(i), sh = rdShown(i);
        float x = r.x + 30.0 * s;
        dlInt((int)i + 1, 2, x, y, val, i == sel ? IL_ACCENT : IL_DIM, IL_LEFT);
        x += ilNumW(2u, val) + 10.0 * s;
        x += dlLabel(LB_T_, x, y, cap, IL_DIM, IL_LEFT) + 4.0 * s;
        dlNum(rdT(i), 2, x, y, val, IL_INK, IL_LEFT);
        x += ilNumW(4u, val) + 10.0 * s;
        x += dlLabel(LB_L_, x, y, cap, IL_DIM, IL_LEFT) + 4.0 * s;
        dlNum(a.x, 2, x, y, val, IL_INK, IL_LEFT);
        x += ilNumW(4u, val) + 8.0 * s;
        x += dlLabel(LB_C_, x, y, cap, IL_DIM, IL_LEFT) + 4.0 * s;
        dlNum(sh.y, 3, x, y, val, rdClipped(i) ? IL_ALARM : IL_INK, IL_LEFT);
        x += ilNumW(5u, val) + 8.0 * s;
        x += dlLabel(LB_H_, x, y, cap, IL_DIM, IL_LEFT) + 4.0 * s;
        dlNum(a.z, 0, x, y, val, IL_INK, IL_LEFT);
    }
}

// ---------------------------------------------------------------- the picker
void picker(uint sel, uint mode)
{
    float s = g_s;
    float cap = IL_T_CAP * s, val = IL_T_VALUE * s;
    float4 pk = g_L.pick;
    float ty = pk.y + 12.0 * s;
    float x = pk.x + 2.0 * s;
    x += dlLabel(LB_COLOUR, x, ty, IL_T_TITLE * s, IL_DIM, IL_LEFT) + 10.0 * s;
    x += dlLabel(LB_STOP, x, ty, IL_T_TITLE * s, IL_INK, IL_LEFT) + 5.0 * s;
    x += dlInt((int)sel + 1, 1, x, ty, val, IL_ACCENT, IL_LEFT) + 10.0 * s;
    dlLabelFit(LB_PLANE_D, pk.z - 2.0 * s, ty, cap, IL_DIM, IL_RIGHT, pk.z - x - 4.0 * s);

    // the plane, a grid every quarter of lightness and every 0.1 of chroma
    float4 pl = g_L.plane;
    field(pl);
    [loop] for (uint gl = 1u; gl < 4u; gl++)
    {
        float y = lerp(pl.w, pl.y, gl * 0.25);
        dlRect(float4(pl.x, y - 0.5, pl.z, y + 0.5), IL_FIELD, 0.28, 0.0);
    }
    [loop] for (uint gc = 1u; gc < 4u; gc++)
    {
        float xx = lerp(pl.x, pl.z, gc * 0.1 / RD_PLANE_CMAX);
        dlRect(float4(xx - 0.5, pl.y, xx + 0.5, pl.w), IL_FIELD, 0.28, 0.0);
    }
    dlBorderRect(pl, 0.0, IL_RULE, 1.0);

    // the stop where it shows; where it asked to be when sRGB cannot show that
    float3 a = rdAsked(sel), sh = rdShown(sel);
    float2 ps = rdPlanePx(g_L, sh.x, sh.y);
    if (rdClipped(sel))
    {
        float2 pa = rdPlanePx(g_L, a.x, a.y);
        dlDashed(ps, pa, 1.0 * s, IL_INK, 0.8, 3.0 * s, 3.0 * s);
        dlEllipse(pa, float2(6.0, 6.0) * s, 1.25 * s, IL_ALARM, 1.0, 3.0 * s, 2.5 * s);
    }
    dlRing(ps, 7.0 * s, 3.5 * s, IL_FIELD, 0.85);
    dlRing(ps, 7.0 * s, 1.5 * s, mode == DM_PLANE ? IL_ACCENT : IL_INK, 1.0);

    // the hue strip and the stop's hue
    float4 hu = g_L.hue;
    field(hu);
    dlBorderRect(hu, 0.0, IL_RULE, 1.0);
    float hx = lerp(hu.x, hu.z, a.z / 360.0);
    dlRect(float4(hx - 2.25 * s, hu.y - 3.0 * s, hx + 2.25 * s, hu.w + 3.0 * s), IL_FIELD, 0.85, 1.0 * s);
    dlRect(float4(hx - 0.75 * s, hu.y - 3.0 * s, hx + 0.75 * s, hu.w + 3.0 * s), mode == DM_HUE ? IL_ACCENT : IL_INK, 1.0, 0.0);

    // the numbers
    float4 ro = g_L.readout;
    float y1 = ro.y + 10.0 * s, y2 = ro.y + 28.0 * s;
    float xx = ro.x + 2.0 * s;
    xx += dlLabel(LB_T_, xx, y1, cap, IL_DIM, IL_LEFT) + 4.0 * s;
    xx += dlNum(rdT(sel), 3, xx, y1, val, IL_INK, IL_LEFT) + 12.0 * s;
    xx += dlLabel(LB_L_, xx, y1, cap, IL_DIM, IL_LEFT) + 4.0 * s;
    xx += dlNum(a.x, 3, xx, y1, val, IL_INK, IL_LEFT) + 12.0 * s;
    xx += dlLabel(LB_C_, xx, y1, cap, IL_DIM, IL_LEFT) + 4.0 * s;
    xx += dlNum(sh.y, 3, xx, y1, val, IL_INK, IL_LEFT) + 12.0 * s;
    xx += dlLabel(LB_H_, xx, y1, cap, IL_DIM, IL_LEFT) + 4.0 * s;
    dlNum(a.z, 1, xx, y1, val, IL_INK, IL_LEFT);
    if (rdClipped(sel))
    {
        float x2 = ro.x + 2.0 * s;
        dlCircle(float2(x2 + 3.0 * s, y2), 3.0 * s, IL_ALARM, 1.0);
        x2 += 10.0 * s;
        x2 += dlLabel(LB_ASKED, x2, y2, cap, IL_DIM, IL_LEFT) + 4.0 * s;
        x2 += dlLabel(LB_C_, x2, y2, cap, IL_DIM, IL_LEFT) + 4.0 * s;
        x2 += dlNum(a.y, 3, x2, y2, val, IL_ALARM, IL_LEFT) + 10.0 * s;
        dlLabelFit(LB_CLIPPED, x2, y2, cap, IL_DIM, IL_LEFT, ro.z - x2);
    }
    else dlLabel(LB_INSIDE, ro.x + 2.0 * s, y2, cap, IL_DIM, IL_LEFT);
}

// ---------------------------------------------------------------- the ramp and its lanes
void ramp(float2 pointer, uint n, uint sel, uint mode, uint target, uint flags, uint space)
{
    float s = g_s;
    float cap = IL_T_CAP * s, val = IL_T_VALUE * s;
    float4 rt = g_L.right;
    float ty = rt.y + 12.0 * s;
    float x = rt.x + 2.0 * s;
    x += dlLabel(LB_RAMP, x, ty, IL_T_TITLE * s, IL_DIM, IL_LEFT) + 10.0 * s;
    x += dlLabel(LB_BLEND_0 + space, x, ty, cap, IL_MID, IL_LEFT) + 10.0 * s;
    dlLabel(LB_ENTRIES, x, ty, cap, IL_DIM, IL_LEFT);

    float4 bar = g_L.bar;
    field(bar);
    dlBorderRect(bar, 0.0, IL_RULE, 1.0);

    // the stops' lane: the intervals, their midpoint diamonds, the pins
    uint hotPin = (mode == 0u) ? rdHitPin(g_L, pointer, s) : 0xFFFFu;
    uint hotMid = (mode == 0u && hotPin == 0xFFFFu) ? rdHitMid(g_L, pointer, s) : 0xFFFFu;
    float my = rdMidY(g_L, s);
    [loop] for (uint i = 0u; i + 1u < n; i++)
    {
        float xa = rdX(g_L, rdT(i)) + 8.0 * s, xb = rdX(g_L, rdT(i + 1u)) - 8.0 * s;
        if (xb > xa) dlRect(float4(xa, my - 0.5, xb, my + 0.5), IL_EDGE, 1.0, 0.0);
        if (!rdMidShown(g_L, i, s)) continue;
        float2 c = float2(rdMidX(g_L, i), my);
        bool act = mode == DM_MID && target == i;
        dlDiamond(c, 4.5 * s, 0.0, IL_PANEL, 1.0);
        dlDiamond(c, 4.5 * s, 1.25 * s, act ? IL_ACCENT : (hotMid == i ? IL_INK : IL_DIM), 1.0);
    }
    bool removing = mode == DM_PIN && (flags & RD_REMOVE) != 0u;
    [loop] for (uint j = 0u; j < n; j++)
    {
        float px = rdX(g_L, rdT(j));
        bool isSel = j == sel;
        bool gone = isSel && removing;
        float3 edge = isSel ? IL_ACCENT : (hotPin == j ? IL_INK : IL_RULE);
        dlRect(float4(px - 0.75 * s, bar.w - 7.0 * s, px + 0.75 * s, g_L.pins.y + 7.0 * s), gone ? IL_DIM : edge, 1.0, 0.0);
        float4 sw = rdPinSwatch(g_L, px, s);
        if (gone) dlRectEdged(sw, IL_WELL, 1.0, 2.0 * s, IL_DIM, 1.0 * s);
        else dlRectEdged(sw, stopColour(j), 1.0, 2.0 * s, edge, isSel ? 2.0 * s : 1.0 * s);
    }
    if (removing)
    {
        float px = clamp(rdX(g_L, rdT(sel)), bar.x + 60.0 * s, bar.z - 60.0 * s);
        dlLabel(LB_REMOVE, px, g_L.pins.w + 4.0 * s, cap, IL_INK, IL_CENTER);
    }

    // the three groups of lanes
    [loop] for (uint gidx = 0u; gidx < 3u; gidx++)
    {
        float4 gt = g_L.groupT[gidx];
        float gy = ilMid(gt).y;
        float gx = gt.x + 2.0 * s;
        gx += dlLabel(LB_G_0 + gidx, gx, gy, IL_T_TITLE * s, IL_DIM, IL_LEFT) + 10.0 * s;
        dlLabel(LB_G_0_D + gidx, gx, gy, cap, IL_DIM, IL_LEFT);
    }
    [loop] for (uint a = 0u; a < 7u; a++)
    {
        float4 ln = g_L.lane[a];
        float ly = ilMid(ln).y;
        bool active = a == space;
        float lw = dlLabel(LB_LN_0 + a, ln.x - 8.0 * s, ly, cap, active ? IL_INK : IL_DIM, IL_RIGHT);
        if (active) dlCircle(float2(ln.x - 15.0 * s - lw, ly), 2.5 * s, IL_ACCENT, 1.0);
        field(ln);
        dlBorderRect(ln, 0.0, IL_EDGE, 1.0);
    }
    [loop] for (uint b = 7u; b < 10u; b++)
    {
        float4 ln = g_L.lane[b];
        dlRect(ln, IL_WELL, 1.0, 2.0 * s);
        dlLabel(LB_LN_0 + b, ln.x - 8.0 * s, ln.y + 9.0 * s, cap, IL_DIM, IL_RIGHT);
    }
    // grids and scales
    [loop] for (uint q = 1u; q < 4u; q++)
    {
        float yl = laneY(7u, q * 0.25);
        dlRect(float4(g_L.lane[7].x, yl - 0.5, g_L.lane[7].z, yl + 0.5), (q == 2u) ? IL_EDGE : IL_GRID, 1.0, 0.0);
        float yc = laneY(8u, q * 0.1 / C_SCALE);
        dlRect(float4(g_L.lane[8].x, yc - 0.5, g_L.lane[8].z, yc + 0.5), (q == 2u) ? IL_EDGE : IL_GRID, 1.0, 0.0);
    }
    dlNum(0.5, 1, g_L.lane[7].x - 8.0 * s, laneY(7u, 0.5), cap, IL_DIM, IL_RIGHT);
    dlNum(0.2, 1, g_L.lane[8].x - 8.0 * s, laneY(8u, 0.2 / C_SCALE), cap, IL_DIM, IL_RIGHT);
    float ym = laneY(9u, 0.25);
    dlDashed(float2(g_L.lane[9].x, ym), float2(g_L.lane[9].z, ym), 1.0 * s, IL_MID, 1.0, 4.0 * s, 4.0 * s);
    // the mean, in the gutter beside its line
    float mx = g_L.lane[9].x - 8.0 * s;
    dlNum(gsMean, 2, mx, ym, cap, IL_MID, IL_RIGHT);
    dlLabel(LB_MEAN, mx, ym - 13.0 * s, cap, IL_DIM, IL_RIGHT);

    // the stops through the reading lanes, under the curves
    [loop] for (uint k = 0u; k < n; k++)
    {
        float px = rdX(g_L, rdT(k));
        dlRect(float4(px - 0.5, g_L.lane[7].y, px + 0.5, g_L.lane[9].w), k == sel ? IL_ACCENT : IL_EDGE, k == sel ? 0.6 : 1.0, 0.0);
    }
}

// entries sRGB could not show, as red runs along the foot of the chroma lane, and their count
void outside()
{
    float s = g_s;
    float4 ln = g_L.lane[8];
    uint count = 0u;
    int runStart = -1;
    [loop] for (uint k = 0u; k <= PAL_ENTRIES; k++)
    {
        bool isOut = k < PAL_ENTRIES && palEntry(k).w > 0.5;
        count += isOut ? 1u : 0u;
        if (isOut && runStart < 0) runStart = (int)k;
        if (!isOut && runStart >= 0)
        {
            float x0 = rdX(g_L, ((float)runStart - 0.5) / 255.0), x1 = rdX(g_L, ((float)k - 0.5) / 255.0);
            dlRect(float4(max(x0, ln.x), ln.w - 4.0 * s, min(x1, ln.z), ln.w - 1.0 * s), IL_ALARM, 1.0, 0.0);
            runStart = -1;
        }
    }
    if (count == 0u) return;
    float cap = IL_T_CAP * s;
    float x = ln.z - 6.0 * s;
    x -= dlLabel(LB_OUTSIDE, x, ln.y + 9.0 * s, cap, IL_DIM, IL_RIGHT) + 4.0 * s;
    dlInt((int)count, 1, x, ln.y + 9.0 * s, cap, IL_ALARM, IL_RIGHT);
}

// the pointer over the ramp: a hairline through every lane and the entry under it
void probe(float2 pointer, uint mode)
{
    float4 bar = g_L.bar;
    if (mode != 0u || pointer.x < bar.x || pointer.x > bar.z || pointer.y < bar.y || pointer.y > g_L.lane[9].w) return;
    float s = g_s;
    float cap = IL_T_CAP * s, val = IL_T_VALUE * s;
    float t = rdTOf(g_L, pointer.x);
    uint k = min((uint)round(t * 255.0), PAL_ENTRIES - 1u);
    float3 lch = palLabToLch(gsLab[k]);
    dlRect(float4(pointer.x - 0.5, bar.y, pointer.x + 0.5, g_L.lane[9].w), IL_INK, 0.5, 0.0);
    dlCircle(float2(pointer.x, laneY(7u, lch.x)), 2.5 * s, IL_INK, 1.0);
    dlCircle(float2(pointer.x, laneY(8u, lch.y / C_SCALE)), 2.5 * s, IL_INK, 1.0);
    float4 rt = g_L.right;
    float ty = rt.y + 12.0 * s;
    float x = rt.z - 2.0 * s;
    x -= dlNum(lch.z, 0, x, ty, val, IL_INK, IL_RIGHT) + 4.0 * s;
    x -= dlLabel(LB_H_, x, ty, cap, IL_DIM, IL_RIGHT) + 12.0 * s;
    x -= dlNum(lch.y, 3, x, ty, val, IL_INK, IL_RIGHT) + 4.0 * s;
    x -= dlLabel(LB_C_, x, ty, cap, IL_DIM, IL_RIGHT) + 12.0 * s;
    x -= dlNum(lch.x, 3, x, ty, val, IL_INK, IL_RIGHT) + 4.0 * s;
    x -= dlLabel(LB_L_, x, ty, cap, IL_DIM, IL_RIGHT) + 12.0 * s;
    x -= dlNum(t, 3, x, ty, val, IL_INK, IL_RIGHT) + 4.0 * s;
    dlLabel(LB_T_, x, ty, cap, IL_DIM, IL_RIGHT);
}

// ---------------------------------------------------------------- hint bar
void hints()
{
    float s = g_s;
    float kh = 18.0 * s;
    float bx = g_L.hint.x, by = ilMid(g_L.hint).y;
    float total = 0.0;
    [loop] for (uint a = 0u; a < 7u; a++)
        total += ilLabelW(LB_K_A0 + a, IL_T_CAP * s) + 12.0 * s + 6.0 * s + ilLabelW(LB_D_A0 + a, IL_T_CAP * s) + 16.0 * s;
    plate(float4(bx, by - 15.0 * s, bx + total + 8.0 * s, by + 15.0 * s));
    bx += 10.0 * s;
    [loop] for (uint b = 0u; b < 7u; b++)
    {
        float kw = ilLabelW(LB_K_A0 + b, IL_T_CAP * s) + 12.0 * s;
        float dw = ilLabelW(LB_D_A0 + b, IL_T_CAP * s);
        dlKeycap(float4(bx, by - kh * 0.5, bx + kw, by + kh * 0.5), s, LB_K_A0 + b);
        dlLabel(LB_D_A0 + b, bx + kw + 6.0 * s, by, IL_T_CAP * s, IL_DIM, IL_LEFT);
        bx += kw + 6.0 * s + dw + 16.0 * s;
    }
}

// ---------------------------------------------------------------- thread 0
void layout()
{
    dlBegin(g_res);
    float2 pointer = _ViewportPointerPosition * g_res;
    float4 v1 = S[RD_V1];
    uint mode = (uint)v1.x, target = (uint)v1.y, flags = (uint)v1.w;
    uint n = rdN(), sel = rdSel();
    uint space = min((uint)S[PAL_HEAD].z, 2u);

    header(n, space);
    plate(g_L.block);
    stopsList(pointer, n, sel);
    picker(sel, mode);
    ramp(pointer, n, sel, mode, target, flags, space);
    dlBatch(3u * RD_SEGS, 0u);        // batch 0: the curves
    outside();
    probe(pointer, mode);
    hints();
    dlFinish();
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    g_res = _Resolution.xy;
    g_s = ilCtx(g_res).s;
    g_L = rdLayout(g_res, g_s);

    // 1. the entries in OKLab, and the mean step between neighbours
    [loop] for (uint k = gi; k < PAL_ENTRIES; k += IL_LAYOUT_THREADS) gsLab[k] = palLinearToLab(palToLinear(palEntry(k).rgb));
    GroupMemoryBarrierWithGroupSync();
    if (gi == 0u)
    {
        float acc = 0.0;
        [loop] for (uint j = 0u; j < RD_SEGS; j++) acc += stepAt(j);
        gsMean = acc / (float)RD_SEGS;
    }
    GroupMemoryBarrierWithGroupSync();

    // 2. everything else
    if (gi == 0u) layout();
    dlSync();

    // 3. the curves
    ILBatch b = dlGetBatch(0u);
    [loop] for (uint g = gi; g < 3u * RD_SEGS; g += IL_LAYOUT_THREADS)
    {
        dlAt(b, g);
        curveSeg(g);
    }
    dlEnd(gi);
}
