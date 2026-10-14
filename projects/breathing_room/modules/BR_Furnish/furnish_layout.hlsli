// furnish_layout.hlsli -- the ONE transform between room space and BR_Furnish's canvas, shared by
// the reducer (furnish.hlsl), the drawing (plate.hlsl) and the draw list (layout.hlsl).
//
//   +----------------------------------+-------------------------+
//   | title strip: arrangement, counts, alarms                   |
//   +----------------------------------+-------------------------+
//   | PLAN pane (north up)             | SECTION pane (looking   |
//   |                                  | at one wall, cut through|
//   |                                  | the room in front)      |
//   |                                  +------------+------------+
//   |                                  | INSPECTOR  | RULES      |
//   |                                  | + chips    | readouts   |
//   +----------------------------------+------------+------------+
//
// Output pixels on the Interaction Lab kit's ui scale (ilCtx). Drawing, picking and drag inversion
// all go through these functions. The plan fit depends only on the room and the panel, never on
// the furniture, so nothing refits under a drag.
#ifndef FURNISH_LAYOUT_HLSLI
#define FURNISH_LAYOUT_HLSLI

#include "../_shared/ui/il_core.hlsli"

struct FLayout
{
    float2 res;
    float ui;                              // the kit's ui scale (1 at 1280 x 720)
    float header;                          // the title strip's height
    float4 planPane, secPane;              // the two drawing panes (card + header strip)
    float4 planR, secR;                    // ... their bodies: what is drawn and picked
    float4 inspR, rulesR;                  // the inspector and rules panes (x0, y0, x1, y1)
    float s;                               // plan pixels per metre
    float2 o;                              // pixel of world corner (x0, z1)
    float x0, z1;
};

FLayout fLayout(float2 res, BRRoom r)
{
    FLayout L;
    L.res = res;
    L.ui = ilCtx(res).s;
    L.header = ilSnap(36.0 * L.ui);
    float m = ilSnap(10.0 * L.ui), ph = ilSnap(IL_HEADER * L.ui);
    float split = floor(res.x * 0.60);
    L.planPane = float4(m, L.header, split - m * 0.5, res.y - m);
    L.planR = float4(L.planPane.x, L.planPane.y + ph, L.planPane.z, L.planPane.w);
    float rx0 = split + m * 0.5, rx1 = res.x - m;
    float top = L.header, bot = res.y - m;
    float secH = floor((bot - top) * 0.47);
    L.secPane = float4(rx0, top, rx1, top + secH);
    L.secR = float4(L.secPane.x, L.secPane.y + ph, L.secPane.z, L.secPane.w);
    float midX = floor((rx0 + rx1) * 0.5);
    L.inspR = float4(rx0, top + secH + m, midX - m * 0.5, bot);
    L.rulesR = float4(midX + m * 0.5, top + secH + m, rx1, bot);
    // plan fit with a margin for dimension strings outside the walls
    float W = r.x1 - r.x0 + 2.0 * r.T, D = r.z1 - r.z0 + 2.0 * r.T;
    float pad = 34.0 * L.ui;
    float2 avail = float2(L.planR.z - L.planR.x - 2.0 * pad, L.planR.w - L.planR.y - 2.0 * pad);
    L.s = max(min(avail.x / W, avail.y / D), 1.0);
    float2 c = float2((L.planR.x + L.planR.z) * 0.5, (L.planR.y + L.planR.w) * 0.5);
    L.x0 = r.x0; L.z1 = r.z1;
    L.o = c - float2((r.x1 - r.x0) * 0.5, (r.z1 - r.z0) * 0.5) * L.s;
    return L;
}

float2 fPlanPx(FLayout L, float2 xz) { return float2(L.o.x + (xz.x - L.x0) * L.s, L.o.y + (L.z1 - xz.y) * L.s); }
float2 fPlanWorld(FLayout L, float2 px) { return float2(L.x0 + (px.x - L.o.x) / L.s, L.z1 - (px.y - L.o.y) / L.s); }
bool fInRect(float2 p, float4 r, float pad) { return p.x >= r.x - pad && p.x <= r.z + pad && p.y >= r.y - pad && p.y <= r.w + pad; }

// The selection's handles in the plan: the turn knob stands this far beyond the piece's front
// edge, and each handle grabs within these radii (pixels; the layout draws them the same size).
float fKnobPx(FLayout L) { return 34.0 * L.ui; }
float fKnobGrab(FLayout L) { return 9.0 * L.ui; }
float fGripGrab(FLayout L) { return 8.0 * L.ui; }

// ---------------------------------------------------------------------------------------------
// SECTION: looking at wall w from inside the room. Horizontal = the wall's viewer's-right tangent,
// vertical = height. Only things between the cut plane (cutD metres in front of the wall) and the
// wall are drawn; the cut line is marked in the plan.
struct FSection
{
    int wall;
    float2 t;           // viewer's right along the wall (world xz)
    float2 n;           // inward normal
    float plane;        // u of the wall's left end (in t units)
    float u0, u1;       // extent along t
    float cutD;         // depth of the cut plane from the wall face
    float ss;           // px per metre
    float2 o;           // pixel of (u0, y = 0)
    float H;
};

FSection fSection(FLayout L, BRRoom r, int w, float cutD)
{
    FSection S;
    S.wall = w;
    S.t = brWallTangent(w);
    S.n = brWallNormal(w);
    float2 e = brWallExtent(r, w);
    float2 p0 = brWallPoint(r, w, e.x, 0.0), p1 = brWallPoint(r, w, e.y, 0.0);
    float a = dot(p0, S.t), b = dot(p1, S.t);
    S.u0 = min(a, b); S.u1 = max(a, b);
    S.plane = 0;
    S.cutD = cutD;
    S.H = r.H;
    float hint = 16.0 * L.ui;               // the drag hint's row along the top of the body
    float pad = 14.0 * L.ui;
    float2 avail = float2(L.secR.z - L.secR.x - 2.0 * pad, L.secR.w - L.secR.y - hint - 2.0 * pad);
    S.ss = max(min(avail.x / (S.u1 - S.u0 + 0.2), avail.y / (r.H + 0.15)), 1.0);
    float cx = (L.secR.x + L.secR.z) * 0.5;
    S.o = float2(cx - (S.u1 - S.u0) * 0.5 * S.ss, L.secR.w - pad - 0.05 * S.ss);
    return S;
}
float2 fSecPx(FSection S, float u, float y) { return float2(S.o.x + (u - S.u0) * S.ss, S.o.y - y * S.ss); }
float2 fSecUY(FSection S, float2 px) { return float2(S.u0 + (px.x - S.o.x) / S.ss, (S.o.y - px.y) / S.ss); }
float fSecU(FSection S, float2 xz) { return dot(xz, S.t); }
float fSecDepth(FSection S, BRRoom r, float2 xz)
{
    float2 p0 = brWallPoint(r, S.wall, brWallExtent(r, S.wall).x, 0.0);
    return dot(xz - p0, S.n);
}

// ---------------------------------------------------------------------------------------------
// INSPECTOR chips: a 2x2 grid at the bottom of the inspector pane. Computed HERE so the drawing
// and the hit test cannot disagree.
float4 fChipRect(FLayout L, int k)
{
    float gap = 6.0 * L.ui, h = ilSnap(28.0 * L.ui), pad = 10.0 * L.ui;
    float w = (L.inspR.z - L.inspR.x - 2.0 * pad - gap) * 0.5;
    int col = k % 2, row = k / 2;
    float y0 = L.inspR.w - pad - (2.0 - (float)row) * h - (1.0 - (float)row) * gap;
    float x0 = L.inspR.x + pad + (float)col * (w + gap);
    return float4(x0, y0, x0 + w, y0 + h);
}
int fChipAt(FLayout L, float2 px)
{
    [unroll] for (int k = 0; k < 4; k++) if (fInRect(px, fChipRect(L, k), 0.0)) return k;
    return -1;
}

#endif
