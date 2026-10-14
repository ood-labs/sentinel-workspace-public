// BR_Rug / layout.hlsl -- the rug designer's chrome, handles and type, recorded into the shared UI
// kit's draw list (ui.hlsl draws it over plate.hlsl's woven rug). Every rect comes from
// rug_layout.hlsli, the same functions rug.hlsl hit-tests with.
//
// The rug pane: a draughtsman's dimension line on two sides (the rug's size, from BR_Furnish), and
// the two handles with their guides: the medallion's tip on the long axis and the border's inner
// edge. A handle is mid grey at rest, ink under the pointer, and takes the accent while held, with
// a card of its live measure beside it. The design pane: the family, palette, size, border depth
// and medallion size; one row per dye slot showing the record's own colour (through ptInset) and
// which of its dyer's six it is, in ink once a hand has stepped it; the four chips.
#include "../_shared/br_records.hlsli"
#include "../_shared/br_furn_defs.hlsli"
#define RUG_REC(i) RugBuf[i]
StructuredBuffer<BRRec> RugBuf : register(t0);
#include "../_shared/br_rug.hlsli"
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"
#include "rug_layout.hlsli"

// A key and what it does; returns the width used.
float hintW(float s, uint key, uint does) { return ilLabelW(key, IL_T_CAP * s) + 34.0 * s + ilLabelW(does, IL_T_CAP * s); }
float hint(float x, float y, float s, uint key, uint does)
{
    float kw = ilLabelW(key, IL_T_CAP * s) + 12.0 * s, kh = 18.0 * s;
    dlKeycap(float4(x, y - 0.5 * kh, x + kw, y + 0.5 * kh), s, key);
    return kw + 6.0 * s + dlLabel(does, x + kw + 6.0 * s, y, IL_T_CAP * s, IL_DIM, IL_LEFT) + 16.0 * s;
}

// A number and its unit; returns the width. measureNU gives the width without drawing.
float measureNU(float v, int dec, uint unit, float s)
{
    return ilNumW(ilFormat(v, dec, 1, false).n, IL_T_VALUE * s) + 3.0 * s + ilLabelW(unit, IL_T_CAP * s);
}
float numUnit(float v, int dec, uint unit, float x, float y, float s, float3 ink)
{
    float w = dlNum(v, dec, x, y, IL_T_VALUE * s, ink, IL_LEFT) + 3.0 * s;
    return w + dlLabel(unit, x + w, y, IL_T_CAP * s, IL_DIM, IL_LEFT);
}

// Dimension lines: end ticks, the line broken round its length in metres.
void dimH(float y, float x0, float x1, float v, float s)
{
    float nw = measureNU(v, 2, LB_M, s), cx = 0.5 * (x0 + x1), gap = 0.5 * nw + 6.0 * s;
    dlHLine(y, x0, cx - gap, IL_RULE);
    dlHLine(y, cx + gap, x1, IL_RULE);
    dlVLine(x0, y - 5.0 * s, y + 5.0 * s, IL_RULE);
    dlVLine(x1, y - 5.0 * s, y + 5.0 * s, IL_RULE);
    numUnit(v, 2, LB_M, cx - 0.5 * nw, y, s, IL_MID);
}
void dimV(float x, float y0, float y1, float v, float s)
{
    float nw = measureNU(v, 2, LB_M, s), cy = 0.5 * (y0 + y1), gap = 10.0 * s;
    dlVLine(x, y0, cy - gap, IL_RULE);
    dlVLine(x, cy + gap, y1, IL_RULE);
    dlHLine(y0, x - 5.0 * s, x + 5.0 * s, IL_RULE);
    dlHLine(y1, x - 5.0 * s, x + 5.0 * s, IL_RULE);
    numUnit(v, 2, LB_M, x - 0.5 * nw, cy, s, IL_MID);
}

// A guide over the weave: a dark halo under a fine line, so it reads on light and dark dyes alike.
void guide(float2 a, float2 b, float s, bool hot, bool held)
{
    float3 ink = held ? IL_ACCENT : IL_INK;
    dlDashed(a, b, 3.0, IL_FIELD, 0.45, 5.0 * s, 4.0 * s);
    dlDashed(a, b, 1.0, ink, (hot || held) ? 0.95 : 0.55, 5.0 * s, 4.0 * s);
}
// A handle: a field disc under a ring (rHandleR: never smaller than a comfortable target).
void handle(float2 p, float r, bool hot, bool held)
{
    float3 ink = held ? IL_ACCENT : (hot ? IL_INK : IL_MID);
    dlCircle(p, r + 2.0, IL_FIELD, 0.8);
    dlRing(p, r, (hot || held) ? 2.0 : 1.5, ink, 1.0);
    dlCircle(p, max(0.3 * r, 1.5), ink, 1.0);
}
// The measure a handle sets, on a card beside it (flipped left near the pane's edge).
void card(float2 p, float s, uint caption, float v, int dec, uint unit, float4 bounds, bool held)
{
    float h = 24.0 * s;
    float w = ilLabelW(caption, IL_T_TITLE * s) + 8.0 * s + measureNU(v, dec, unit, s) + 20.0 * s;
    float2 o = float2(p.x + 16.0 * s, p.y - 0.5 * h);
    if (o.x + w > bounds.z - 6.0 * s) o.x = p.x - 16.0 * s - w;
    float4 r = float4(o, o + float2(w, h));
    dlRectEdged(r, IL_RAISE, 0.96, IL_RADIUS * s, IL_EDGE, 1.0);
    float x = r.x + 10.0 * s, y = ilMid(r).y;
    x += dlLabel(caption, x, y, IL_T_TITLE * s, held ? IL_ACCENT : IL_INK, IL_LEFT) + 8.0 * s;
    numUnit(v, dec, unit, x, y, s, IL_INK);
}

// A table row: caption left, hairline under.
void row(float4 r, float s, uint caption)
{
    dlLabel(caption, r.x, ilMid(r).y, IL_T_BODY * s, IL_DIM, IL_LEFT);
    dlHLine(r.w - 0.5, r.x, r.z, IL_GRID);
}

void layout()
{
    float2 res = _Resolution.xy;
    BRRec ed = RugBuf[RUG_EDITOR];
    float2 rugHalf = (ed.dims.x > 0.05) ? ed.dims.xy : float2(1.25, 1.70);
    RLayout L = rLayout(res, rugHalf);
    float s = L.s;
    BRRugDesign R = rugFromRecs();
    BRRec hdr = RugBuf[0];
    BRRec dd = RugBuf[RUG_DELTA0 + 1];
    int pre = clamp((int)round(hdr.look.z), 0, 3);
    int held = (int)round(ed.head.y);                     // 1 medallion, 2 border, 0 none
    float2 ptr = _ViewportPointerPosition * res;
    bool down = (_ViewportButtons & 1u) != 0u;
    int hotH = (held == 0) ? rHandleAt(L, ptr, R.borderW, R.medallion, R.style) : 0;
    int hotChip = rChipAt(L, ptr);
    int hotSw = rSwatchAt(L, ptr);
    dlBegin(res);

    // ---- title strip
    float hy = ilMid(L.head).y;
    float x = 14.0 * s;
    x += dlLabel(LB_TITLE, x, hy, 15.0 * s, IL_INK, IL_LEFT) + 14.0 * s;
    dlLabel(LB_SUBTITLE, x, hy, IL_T_BODY * s, IL_DIM, IL_LEFT);
    bool linked = ed.dims.z > 0.5;
    dlLabel(linked ? LB_LINKED : LB_STANDIN, res.x - 14.0 * s, hy, IL_T_CAP * s, linked ? IL_DIM : IL_INK, IL_RIGHT);

    // ---- the rug pane: its edge and header (plate.hlsl drew the card and the rug)
    dlBorderRect(L.rugPane, IL_RADIUS * s, IL_EDGE, 1.0);
    float4 ph = ilPaneHead(L.rugPane, s);
    dlHLine(ph.w, ph.x + 1.0, ph.z - 1.0, IL_EDGE);
    float ty = ilMid(ph).y;
    float tx = ph.x + 10.0 * s + dlLabel(LB_RUG, ph.x + 10.0 * s, ty, IL_T_TITLE * s, IL_DIM, IL_LEFT) + 16.0 * s;
    float hw = hintW(s, LB_K_DRAG, LB_D_DRAG) + hintW(s, LB_K_CLICK, LB_D_CLICK);
    if (ph.z - 10.0 * s - hw > tx)
    {
        float hx = ph.z - 10.0 * s - hw;
        hx += hint(hx, ty, s, LB_K_DRAG, LB_D_DRAG);
        hint(hx, ty, s, LB_K_CLICK, LB_D_CLICK);
    }
    dlClip(L.rugR);
    float2 tl = rRugPx(L, float2(-L.h.x, L.h.y)), br = rRugPx(L, float2(L.h.x, -L.h.y));
    dimH(br.y + 0.07 * L.scale + 20.0 * s, tl.x, br.x, 2.0 * L.h.x, s);
    dimV(tl.x - 30.0 * s, tl.y, br.y, 2.0 * L.h.y, s);

    // the border's inner edge, along the whole length
    float2 be = rBorderEdge(L, R.borderW);
    guide(float2(be.x, tl.y + 3.0 * s), float2(be.x, br.y - 3.0 * s), s, hotH == 2, held == 2);
    handle(be, rHandleR(L), hotH == 2, held == 2);
    // the handles' cards, hovered or held (Tooltips); the handles themselves stay
    if (tooltips != 0 && (hotH == 2 || held == 2)) card(be, s, LB_H_BORDER, rugBorderInner(L.h.x, R.borderW), 2, LB_M, L.rugR, held == 2);
    // the medallion's tip, on the long axis (an all-over field has none)
    if (rugHasMedallion(R.style))
    {
        float2 mt = rMedallionTip(L, R.borderW, R.medallion, R.style);
        guide(rRugPx(L, float2(0.0, 0.0)), mt, s, hotH == 1, held == 1);
        handle(mt, rHandleR(L), hotH == 1, held == 1);
        if (tooltips != 0 && (hotH == 1 || held == 1)) card(mt, s, LB_H_MEDALLION, R.medallion * 100.0, 0, LB_PCT, L.rugR, held == 1);
    }
    dlClipReset();

    // ---- the design pane
    dlPane(L.sideR, s, LB_DESIGN, false);
    float4 r0 = rRowRect(L, 0);
    row(r0, s, LB_C_FAMILY);
    dlLabel(LB_F_TABRIZ + (uint)clamp(R.style, 0, 2), r0.z, ilMid(r0).y, IL_T_BODY * s, IL_INK, IL_RIGHT);
    float4 r1 = rRowRect(L, 1);
    row(r1, s, LB_C_PALETTE);
    dlLabel(LB_P_TABRIZ + (uint)pre, r1.z, ilMid(r1).y, IL_T_BODY * s, IL_INK, IL_RIGHT);
    float4 r2 = rRowRect(L, 2);
    row(r2, s, LB_C_SIZE);
    {
        float y = ilMid(r2).y, xr = r2.z;
        xr -= dlLabel(LB_M, xr, y, IL_T_CAP * s, IL_DIM, IL_RIGHT) + 3.0 * s;
        xr -= dlNum(2.0 * L.h.y, 2, xr, y, IL_T_VALUE * s, IL_INK, IL_RIGHT) + 4.0 * s;
        xr -= dlLabel(LB_X, xr, y, IL_T_CAP * s, IL_DIM, IL_RIGHT) + 4.0 * s;
        dlNum(2.0 * L.h.x, 2, xr, y, IL_T_VALUE * s, IL_INK, IL_RIGHT);
    }
    float4 r3 = rRowRect(L, 3);
    row(r3, s, LB_C_BORDER);
    {
        float y = ilMid(r3).y, xr = r3.z;
        xr -= dlLabel(LB_M, xr, y, IL_T_CAP * s, IL_DIM, IL_RIGHT) + 3.0 * s;
        dlNum(rugBorderInner(L.h.x, R.borderW), 2, xr, y, IL_T_VALUE * s, (held == 2) ? IL_ACCENT : IL_INK, IL_RIGHT);
    }
    float4 r4 = rRowRect(L, 4);
    row(r4, s, LB_C_MEDALLION);
    if (rugHasMedallion(R.style))
    {
        float y = ilMid(r4).y, xr = r4.z;
        xr -= dlLabel(LB_PCT, xr, y, IL_T_CAP * s, IL_DIM, IL_RIGHT) + 3.0 * s;
        dlNum(R.medallion * 100.0, 0, xr, y, IL_T_VALUE * s, (held == 1) ? IL_ACCENT : IL_INK, IL_RIGHT);
    }
    else dlLabel(LB_NONE, r4.z, ilMid(r4).y, IL_T_BODY * s, IL_DIM, IL_RIGHT);

    // dyes: the record's own colour, and which of its dyer's six it is
    float cy = rDyesCaptionY(L);
    dlLabel(LB_DYES, r0.x, cy, IL_T_TITLE * s, IL_DIM, IL_LEFT);
    dlLabel(LB_DYES_HINT, r0.z, cy, IL_T_CAP * s, IL_DIM, IL_RIGHT);
    float steps[RUG_SLOTS] = { dd.dims.x, dd.dims.y, dd.dims.z, dd.dims.w, dd.look.x, dd.look.y, dd.look.z, dd.look.w };
    float3 sw[RUG_SLOTS] = { R.field, R.border, R.ivory, R.gold, R.green, R.blue, R.outline, R.rose };
    [loop] for (int k = 0; k < RUG_SLOTS; k++)
    {
        float4 rr = rSwatchRect(L, k);
        bool hot = hotSw == k;
        dlRectEdged(rr, (hot && down) ? IL_WELL : (hot ? IL_RAISE * 1.45 : IL_RAISE), 1.0, IL_RADIUS * s, IL_EDGE, 1.0);
        float4 chip = float4(rr.x + 5.0 * s, rr.y + 4.0 * s, rr.x + 44.0 * s, rr.w - 4.0 * s);
        dlRectEdged(chip, ptInset(sw[k] * 2.6), 1.0, 2.0 * s, IL_EDGE, 1.0);   // a dye is a material sample
        float y = ilMid(rr).y;
        dlLabel(LB_S_FIELD + (uint)k, rr.x + 54.0 * s, y, IL_T_BODY * s, IL_INK, IL_LEFT);
        int step = (int)round(steps[k]);
        int dye = ((RUG_PRESET[pre * RUG_SLOTS + k] + step) % 6 + 6) % 6;
        bool edited = ((step % 6) + 6) % 6 != 0;
        float xr = rr.z - 10.0 * s;
        xr -= dlLabel(LB_OF6, xr, y, IL_T_CAP * s, IL_DIM, IL_RIGHT) + 4.0 * s;
        dlInt(dye + 1, 1, xr, y, IL_T_VALUE * s, edited ? IL_INK : IL_DIM, IL_RIGHT);
    }

    // chips: family, palette, re-roll, reset
    [unroll] for (int c = 0; c < RUG_CHIPS; c++)
        dlChip(rChipRect(L, c), s, LB_CH_FAMILY + (uint)c, false, hotChip == c, hotChip == c && down);

    dlFinish();
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    if (gi == 0u) layout();
    dlEnd(gi);
}
