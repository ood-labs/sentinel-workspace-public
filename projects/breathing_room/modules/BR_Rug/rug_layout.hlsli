// rug_layout.hlsli -- the ONE layout of BR_Rug's canvas, shared by the reducer (rug.hlsl), the
// woven plate (plate.hlsl) and the draw list (layout.hlsl), so what you see is what you hit.
// Output pixels throughout, scaled by the Interaction Lab kit's ui scale (ilCtx). The rug is drawn
// flat, long axis vertical, in the left pane; the right pane holds the design table, one swatch
// per dye slot and the chips.
#ifndef RUG_LAYOUT_HLSLI
#define RUG_LAYOUT_HLSLI

#include "../_shared/ui/il_core.hlsli"

struct RLayout
{
    float2 res;
    float s;              // ui scale (1 at 1280 x 720)
    float4 head;          // the title strip
    float4 rugPane;       // the rug's pane (header strip + body)
    float4 rugR;          // the pane's body: the rug is fitted in it
    float4 sideR;         // the design pane
    float4 sideBody;      // ... below its header
    float scale;          // px per metre on the rug
    float2 c;             // pixel of the rug's centre
    float2 h;             // the rug's half size (x across, y along: y >= x)
};

RLayout rLayout(float2 res, float2 rugHalf)
{
    RLayout L;
    L.res = res;
    L.s = ilCtx(res).s;
    float m = ilSnap(10.0 * L.s);
    L.head = float4(0.0, 0.0, res.x, ilSnap(36.0 * L.s));
    float4 body = float4(m, L.head.w, res.x - m, res.y - m);
    L.sideR = ilCutRight(body, ilSnap(300.0 * L.s));
    body.z -= m;
    L.rugPane = body;
    L.rugR = body;
    ilCutTop(L.rugR, ilSnap(IL_HEADER * L.s));
    L.sideBody = L.sideR;
    ilCutTop(L.sideBody, ilSnap(IL_HEADER * L.s));
    L.h = float2(min(rugHalf.x, rugHalf.y), max(rugHalf.x, rugHalf.y));
    // room round the rug for the fringe and the two dimension lines (left and below)
    float2 padLo = float2(64.0, 30.0) * L.s, padHi = float2(30.0, 54.0) * L.s;
    float2 room = ilSize(L.rugR) - padLo - padHi;
    L.scale = max(min(room.x / (2.0 * L.h.x), room.y / (2.0 * (L.h.y + 0.07))), 1.0);
    L.c = (L.rugR.xy + padLo + L.rugR.zw - padHi) * 0.5;
    return L;
}

bool rInRect(float2 p, float4 r, float pad) { return p.x >= r.x - pad && p.x <= r.z + pad && p.y >= r.y - pad && p.y <= r.w + pad; }
float2 rRugPx(RLayout L, float2 q) { return L.c + float2(q.x, -q.y) * L.scale; }
float2 rRugQ(RLayout L, float2 px) { return float2((px.x - L.c.x) / L.scale, -(px.y - L.c.y) / L.scale); }

// the design's own proportions (the same arithmetic rugDesign uses)
float rugBorderInner(float shortH, float borderW) { return 0.010 + shortH * (0.045 + 2.0 * borderW); }   // b2
float rugFieldInset(float shortH, float borderW) { return rugBorderInner(shortH, borderW) + shortH * 0.032; } // b3
// the medallion's half length over its size: Tabriz's superellipse is 1.42 long, Heriz's rhombus 1.5
float rugMedTipK(int style) { return (style == 2) ? 1.5 : 1.42; }
bool rugHasMedallion(int style) { return style != 1; }       // Isfahan is an all-over field

// the two handles: the medallion's tip on the long axis, the border's inner edge on the right side
float2 rMedallionTip(RLayout L, float borderW, float medallion, int style)
{
    float b3 = rugFieldInset(L.h.x, borderW);
    float ms = min(L.h.x - b3, L.h.y - b3) * medallion;
    return rRugPx(L, float2(0.0, ms * rugMedTipK(style)));
}
float2 rBorderEdge(RLayout L, float borderW) { return rRugPx(L, float2(L.h.x - rugBorderInner(L.h.x, borderW), 0.0)); }

// A handle's drawn ring and its grab radius, in px: they scale with the ui but never shrink below
// a comfortable target (a docked panel runs at a ui scale near 0.6).
float rHandleR(RLayout L) { return max(7.0 * L.s, 6.0); }
float rGrabR(RLayout L) { return max(14.0 * L.s, 12.0); }

// The handle a press at px grabs: 1 the medallion tip, 2 the border edge, 0 none. The layout's
// hover ring asks the same question.
int rHandleAt(RLayout L, float2 px, float borderW, float medallion, int style)
{
    float dm = rugHasMedallion(style) ? length(px - rMedallionTip(L, borderW, medallion, style)) : 1e9;
    float db = length(px - rBorderEdge(L, borderW));
    if (dm < rGrabR(L) && dm <= db) return 1;
    if (db < rGrabR(L)) return 2;
    return 0;
}

// ---- the design pane: the table, one swatch row per dye slot, then the chips (2 x 2)
#define RUG_TABLE_ROWS 5
float4 rRowRect(RLayout L, int k)
{
    float pad = 12.0 * L.s, rh = ilSnap(IL_ROW * L.s);
    float y0 = L.sideBody.y + 6.0 * L.s + (float)k * rh;
    return float4(L.sideBody.x + pad, y0, L.sideBody.z - pad, y0 + rh);
}
float rDyesCaptionY(RLayout L) { return rRowRect(L, RUG_TABLE_ROWS).y + 14.0 * L.s; }
float4 rSwatchRect(RLayout L, int k)
{
    float pad = 12.0 * L.s, pitch = ilSnap(32.0 * L.s);
    float y0 = rDyesCaptionY(L) + 14.0 * L.s + (float)k * pitch;
    return float4(L.sideBody.x + pad, y0, L.sideBody.z - pad, y0 + pitch - ilSnap(4.0 * L.s));
}
int rSwatchAt(RLayout L, float2 px)
{
    int hit = -1;
    [unroll] for (int k = 0; k < RUG_SLOTS; k++) if (hit < 0 && rInRect(px, rSwatchRect(L, k), 0.0)) hit = k;
    return hit;
}
#define RUG_CHIPS 4
float4 rChipRect(RLayout L, int k)
{
    float gap = 6.0 * L.s, hh = ilSnap(32.0 * L.s), pad = 12.0 * L.s;
    float w = (L.sideBody.z - L.sideBody.x - 2.0 * pad - gap) * 0.5;
    int col = k % 2, row = k / 2;
    float x0 = L.sideBody.x + pad + (float)col * (w + gap);
    float y0 = L.sideBody.w - pad - 2.0 * hh - gap + (float)row * (hh + gap);
    return float4(x0, y0, x0 + w, y0 + hh);
}
int rChipAt(RLayout L, float2 px)
{
    int hit = -1;
    [unroll] for (int k = 0; k < RUG_CHIPS; k++) if (hit < 0 && rInRect(px, rChipRect(L, k), 0.0)) hit = k;
    return hit;
}

#endif
