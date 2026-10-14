// shell_layout.hlsli -- the ONE transform between room space and the unfolded-room canvas, shared
// by the reducer (shell.hlsl), the drawing (plate.hlsl) and the draw list (layout.hlsl).
//
// The drawing is the room opened flat like a box: the plan in the middle, and each wall's
// interior elevation folded outward from its own plan edge. A folded wall keeps its along-wall
// coordinate (world x for S/N, world z for E/W), so a window drawn in an elevation sits exactly
// beside its cut in the plan. Rendering, picking and drag inversion all go through these
// functions; nothing in the module computes a canvas position any other way.
//
// While a drag is live the world->pixel mapping is FROZEN (scale and reference corner captured
// at the press, stored in the editor record), so dragging a wall outward does not refit the
// drawing under the pointer. It refits on release.
//
// Output pixels throughout; type, chrome and hit targets scale with the Interaction Lab kit's ui
// scale (ilCtx), the drawing with its own pixels per metre.
#ifndef SHELL_LAYOUT_HLSLI
#define SHELL_LAYOUT_HLSLI

#include "../_shared/ui/il_core.hlsli"

struct ShellLayout
{
    float s;            // pixels per metre
    float2 o;           // pixel of the reference corner (xRef, zRef)
    float xRef, zRef;   // world corner the mapping is anchored to (live x0/z1, or frozen)
    float g;            // metres between an interior face and its elevation's floor line
    float x0, x1, z0, z1, H, T;
    float ui;           // ui scale (ilCtx: 1 at 1280 x 720)
    float header;       // title strip height (px)
    float2 res;
};

ShellLayout shellLayoutFit(float2 res, BRRoom r)
{
    ShellLayout L;
    L.res = res;
    L.ui = ilCtx(res).s;
    L.header = ilSnap(36.0 * L.ui);
    L.x0 = r.x0; L.x1 = r.x1; L.z0 = r.z0; L.z1 = r.z1; L.H = r.H; L.T = r.T;
    L.g = r.T + 0.16;
    float W = r.x1 - r.x0, D = r.z1 - r.z0;
    float margin = 26.0 * L.ui;      // room for the wall names outside each elevation
    float2 avail = float2(res.x - 2.0 * margin, res.y - L.header - 2.0 * margin);
    float2 ext = float2(W + 2.0 * (L.g + L.H), D + 2.0 * (L.g + L.H));
    L.s = max(min(avail.x / ext.x, avail.y / ext.y), 1.0);
    float2 centre = float2(res.x * 0.5, L.header + margin + avail.y * 0.5);
    L.o = centre - float2(W, D) * 0.5 * L.s;
    L.xRef = r.x0; L.zRef = r.z1;
    return L;
}

// frozen = (active, s, o.x, o.y) and ref = (xRef, zRef) captured at drag start.
ShellLayout shellLayout(float2 res, BRRoom r, float4 frozen, float2 ref)
{
    ShellLayout L = shellLayoutFit(res, r);
    if (frozen.x > 0.5 && frozen.y > 0.5)
    {
        L.s = frozen.y; L.o = frozen.zw; L.xRef = ref.x; L.zRef = ref.y;
    }
    return L;
}

float shellPX(ShellLayout L, float x) { return L.o.x + (x - L.xRef) * L.s; }
float shellPY(ShellLayout L, float z) { return L.o.y + (L.zRef - z) * L.s; }

float2 shellPlanPx(ShellLayout L, float2 xz) { return float2(shellPX(L, xz.x), shellPY(L, xz.y)); }
float2 shellPlanWorld(ShellLayout L, float2 px)
{
    return float2(L.xRef + (px.x - L.o.x) / L.s, L.zRef - (px.y - L.o.y) / L.s);
}

// Elevation of wall w: along-wall coordinate a, height y -> pixel. Each elevation hangs off its
// own wall's CURRENT plan position, so it travels with that wall during a drag.
float2 shellElevPx(ShellLayout L, int w, float a, float y)
{
    float k = (L.g + y) * L.s;
    if (w == WALL_N) return float2(shellPX(L, a), shellPY(L, L.z1) - k);
    if (w == WALL_S) return float2(shellPX(L, a), shellPY(L, L.z0) + k);
    if (w == WALL_W) return float2(shellPX(L, L.x0) - k, shellPY(L, a));
    return float2(shellPX(L, L.x1) + k, shellPY(L, a));
}
// Pixel -> (a, y) in wall w's elevation frame (extends linearly outside the rect).
float2 shellElevAY(ShellLayout L, int w, float2 px)
{
    float ax = L.xRef + (px.x - L.o.x) / L.s;
    float az = L.zRef - (px.y - L.o.y) / L.s;
    if (w == WALL_N) return float2(ax, (shellPY(L, L.z1) - px.y) / L.s - L.g);
    if (w == WALL_S) return float2(ax, (px.y - shellPY(L, L.z0)) / L.s - L.g);
    if (w == WALL_W) return float2(az, (shellPX(L, L.x0) - px.x) / L.s - L.g);
    return float2(az, (px.x - shellPX(L, L.x1)) / L.s - L.g);
}
float2 shellWallSpan(ShellLayout L, int w) { return (w == WALL_N || w == WALL_S) ? float2(L.x0, L.x1) : float2(L.z0, L.z1); }

float4 shellRectOf(float2 a, float2 b) { return float4(min(a, b), max(a, b)); }

// Pixel rect of wall w's elevation (floor line to ceiling line, wall end to wall end).
float4 shellElevRect(ShellLayout L, int w)
{
    float2 span = shellWallSpan(L, w);
    return shellRectOf(shellElevPx(L, w, span.x, 0.0), shellElevPx(L, w, span.y, L.H));
}
// Pixel rect of an opening's elevation footprint.
float4 shellOpenElevRect(ShellLayout L, int w, float a, float width, float sill, float height)
{
    return shellRectOf(shellElevPx(L, w, a - width * 0.5, sill), shellElevPx(L, w, a + width * 0.5, sill + height));
}
// Pixel rect of the plan footprint between inward offsets d0 and d1 from wall w's interior face.
float4 shellPlanBand(ShellLayout L, BRRoom r, int w, float a0, float a1, float d0, float d1)
{
    return shellRectOf(shellPlanPx(L, brWallPoint(r, w, a0, d0)), shellPlanPx(L, brWallPoint(r, w, a1, d1)));
}

bool shellInRect(float2 p, float4 r, float pad)
{
    return p.x >= r.x - pad && p.x <= r.z + pad && p.y >= r.y - pad && p.y <= r.w + pad;
}

// ---- the four free squares of the cross carry the instrument's cards
// TL the inspector (its action chips are the mouse path to every key verb, K/X/C/R/A/0, so each
// one can also be exercised by injected pointer input), TR the room's measures and alarms, BL the
// scale and north, BR the key map. The inspector and its chips are computed HERE so the drawing
// and the hit test cannot disagree.
#define SHELL_PAD      10.0     // ui px: card inset from the corner and the canvas edge
#define SHELL_CARD_W   212.0    // ui px: a card never narrower than this (it grows into the margin)
#define SHELL_ROW_H    16.0     // ui px: one inspector / measures row
#define SHELL_CHIP_H   24.0     // ui px: an inspector chip
#define SHELL_INSP_ROWS 7.0     // title, wall, four measures, curtains

float shellCornerW(ShellLayout L) { return (L.g + L.H) * L.s; }

// The inspector card: right edge on the TL corner's inner edge, growing left into the margin when
// the corner is narrower than a card; fixed height, so its chips never move with the selection.
float4 shellInspectorRect(ShellLayout L)
{
    float pad = SHELL_PAD * L.ui;
    float xr = shellPX(L, L.x0) - pad;
    float xl = max(min(xr - shellCornerW(L) + 2.0 * pad, xr - SHELL_CARD_W * L.ui), pad);
    float h = (16.0 + SHELL_INSP_ROWS * SHELL_ROW_H + 8.0 + 2.0 * SHELL_CHIP_H + 6.0) * L.ui;
    float y0 = L.header + pad;
    return float4(xl, y0, max(xr, xl + 80.0 * L.ui), y0 + h);
}
// Row k of the inspector's text (k = 0 title ... 6 curtains).
float4 shellInspectorRow(ShellLayout L, int k)
{
    float4 c = shellInspectorRect(L);
    float pad = 10.0 * L.ui, rh = SHELL_ROW_H * L.ui;
    float y0 = c.y + 8.0 * L.ui + (float)k * rh;
    return float4(c.x + pad, y0, c.z - pad, y0 + rh);
}
float4 shellChipRect(ShellLayout L, int k)
{
    float4 c = shellInspectorRect(L);
    float pad = 10.0 * L.ui, gap = 6.0 * L.ui, h = ilSnap(SHELL_CHIP_H * L.ui);
    float cw = (c.z - c.x - 2.0 * pad - gap) * 0.5;
    int col = k % 2, row = k / 2;
    float x0 = c.x + pad + (float)col * (cw + gap);
    float y0 = c.w - 8.0 * L.ui - 2.0 * h - gap + (float)row * (h + gap);
    return float4(x0, y0, x0 + cw, y0 + h);
}
int shellChipAt(ShellLayout L, float2 px)
{
    int hit = -1;
    [unroll] for (int k = 0; k < 4; k++) if (hit < 0 && shellInRect(px, shellChipRect(L, k), 0.0)) hit = k;
    return hit;
}

// The measures card's left edge and width (TR corner, growing right into the margin).
float2 shellMeasuresX(ShellLayout L)
{
    float pad = SHELL_PAD * L.ui;
    float xl = shellPX(L, L.x1) + pad;
    float xr = min(max(xl + shellCornerW(L) - 2.0 * pad, xl + SHELL_CARD_W * L.ui), L.res.x - pad);
    return float2(xl, xr);
}

#endif
