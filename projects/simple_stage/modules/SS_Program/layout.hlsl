// SS_Program / layout - the programmer sheet's type, hover crosshair and inspector, recorded for
// the shared UI kit (ui.hlsl draws them over preview.hlsl's sheet). Point at a cell and the strip
// under the sheet reads it: which fixture and layer, which attribute, and what the value MEANS for
// that layer (lane names, its own look names, palette letters, degrees),
// where it sits in its range, or that the layer never reads it. Hover comes from the pointer each
// cook; nothing stored.
#include "../_shared/ss_show.hlsli"
StructuredBuffer<SsProgram> P : register(t0);
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"
#include "sheet.hlsli"

static float gS;

// a number then its unit (SHEET_NONE for none); returns the width
float numUnit(float v, int decimals, bool sign, float x, float y, float size, uint unit)
{
    float w = dlNumEx(v, decimals, 1, sign, x, y, size, IL_INK, IL_LEFT);
    if (unit != SHEET_NONE) w += 4.0 * gS + dlLabel(unit, x + w + 4.0 * gS, y, IL_T_BODY * gS, IL_DIM, IL_LEFT);
    return w;
}
float word(uint id, float x, float y, float size) { return dlLabel(id, x, y, size, IL_INK, IL_LEFT) + 6.0 * gS; }

// A light layer's pulse FX: PULSE, repeated x1-x8 on its lane (codes 16-47), RND a random third of the fixtures;
// HOLD x1-x8 (the JMP bit, 24-27) a window instead of a pulse.
float pulseFx(uint code, float x, float y, float size)
{
    bool hold = code >= 16u && code <= 47u && ((code - 16u) & 8u) != 0u;
    float w = word(hold ? LB_FX_HOLD : LB_SLK_PULSE, x, y, size);
    if (code < 16u || code > 47u) return w;
    uint fx = code - 16u;
    w += word(LB_FX_X1 + (fx & 3u), x + w, y, size);
    if ((fx & 4u) != 0u) w += word(LB_FX_RND, x + w, y, size);
    return w;
}

// What value v of attribute a means on a row of layer group grp for fixture slot i (docs/PROGRAMMING.md), drawn at
// (x, y); returns width.
float drawMeaning(uint grp, uint i, uint a, float v, float x, float y)
{
    float size = 14.0 * gS;
    if (a == 0u || a == 1u || a == 9u || a == 10u) return numUnit(v, 1, true, x, y, size, LB_U_DEG);
    if (a == 2u || a == 3u) return numUnit(v * 100.0, 0, false, x, y, size, LB_U_PCT);
    if (a == 4u || a == 5u)
    {
        uint p = (uint)clamp(round(v), 0.0, 2.0);
        dlRect(float4(x, y - 6.0 * gS, x + 12.0 * gS, y + 6.0 * gS), ptId((int)p), 1.0, 2.0 * gS);
        return 18.0 * gS + dlLabel(LB_PAL_A + p, x + 18.0 * gS, y, size, IL_INK, IL_LEFT);
    }
    if (a >= 6u && a <= 8u) return dlLabel(LB_LANE_OFF + (uint)clamp(round(v), 0.0, 5.0), x, y, size, IL_INK, IL_LEFT);
    if (a == 11u || a == 12u) return numUnit(v, 2, false, x, y, size, SHEET_NONE);
    if (a == 13u) return numUnit(v, 2, true, x, y, size, SHEET_NONE);
    if (a == 14u) return dlLabel(v > 0.5 ? LB_REVERSE : LB_FORWARD, x, y, size, IL_INK, IL_LEFT);
    if (a == 16u) return dlLabel(LB_ORD_AROUND + (uint)clamp(round(v), 0.0, 7.0), x, y, size, IL_INK, IL_LEFT);
    // the look, in its layer's own words: TUBE and PLATES the strobe looks, PIXELS the content, CHASE its dips,
    // BEAM and HALO their pulse, MOVE the movement FX (16 + repeats + RND 4 + JMP 8 + STEP 16)
    uint code = (uint)max(round(v), 0.0);
    if (grp == 3u || grp == 4u)
        return code <= 5u ? dlLabel(LB_SLK_PULSE + code, x, y, size, IL_INK, IL_LEFT) : pulseFx(code, x, y, size);
    if (grp == 5u)
    {
        // PIXELS: the content, x2-x8 when it runs more than once per lane cycle (codes 16-63)
        float wp = word(LB_LK_SOLID + code % 16u, x, y, size);
        return code >= 16u ? wp + word(LB_FX_X1 + min(code / 16u, 3u), x + wp, y, size) : wp;
    }
    if (grp == 6u)
    {
        if (code >= 24u && code <= 27u)
        {
            // CHASE HOLD: the content shows for WIDTH of each cycle, x1-x8
            float wh = word(LB_FX_HOLD, x, y, size);
            return wh + word(LB_FX_X1 + (code - 24u), x + wh, y, size);
        }
        return (code == 1u || code == 3u) ? dlLabel(LB_SLK_PULSE + code, x, y, size, IL_INK, IL_LEFT) : pulseFx(code, x, y, size);
    }
    if (grp == 1u || grp == 2u) return pulseFx(code, x, y, size);
    if (code >= 52u && code <= 63u)
    {
        // GLIDE: eased moves between positions, x1-x8 per lane cycle; the figure, a position per head or per group
        uint g = code - 52u;
        float w = word(LB_FX_GLIDE, x, y, size);
        w += word(LB_FX_X1 + (g & 3u), x + w, y, size);
        if ((g & 8u) != 0u) w += word(LB_FX_GROUP, x + w, y, size);
        else if ((g & 4u) != 0u) w += word(LB_FX_RND, x + w, y, size);
        return w;
    }
    if (code >= 48u && code <= 51u)
    {
        float ws = word(LB_FX_SPIN, x, y, size);
        return ws + dlLabel(LB_SPIN_Q + (code - 48u), x + ws, y, size, IL_INK, IL_LEFT);
    }
    if (code < 16u || code > 47u) return dlLabel(LB_FX_NONE, x, y, size, IL_DIM, IL_LEFT);
    uint fx = code - 16u;
    float w = word(LB_FX_X1 + (fx & 3u), x, y, size);
    if ((fx & 16u) != 0u) w += word(LB_FX_STEP, x + w, y, size);
    else if ((fx & 8u) != 0u) w += word(LB_FX_JMP, x + w, y, size);
    if ((fx & 4u) != 0u) w += word(LB_FX_RND, x + w, y, size);
    return w;
}

void layout()
{
    float2 R = _Resolution.xy;
    Sheet g = sheetOf(R);
    float s = g.s;
    gS = s;
    dlBegin(R);
    uint rows, stride;
    P.GetDimensions(rows, stride);
    bool ok = rows >= SHEET_COLS && P[0].meta.w == 260933;
    float hy = 19.0 * s;
    float tw = dlLabel(LB_TITLE, 14.0 * s, hy, 14.0 * s, IL_INK, IL_LEFT);
    dlLabel(LB_SUBTITLE, 14.0 * s + tw + 10.0 * s, hy, 12.0 * s, IL_DIM, IL_LEFT);

    // the committed revision and the two globals it carries (meta = commit, master, pitch, magic)
    float x = R.x - 14.0 * s;
    if (ok)
    {
        float4 m = P[0].meta;
        x -= dlNumSigned(m.z, 1, x, hy, IL_T_VALUE * s, IL_INK, IL_RIGHT) + 6.0 * s;
        x -= dlLabel(LB_PITCH, x, hy, IL_T_TITLE * s, IL_DIM, IL_RIGHT) + 22.0 * s;
        x -= dlNum(m.y, 2, x, hy, IL_T_VALUE * s, IL_INK, IL_RIGHT) + 6.0 * s;
        x -= dlLabel(LB_MASTER, x, hy, IL_T_TITLE * s, IL_DIM, IL_RIGHT) + 22.0 * s;
        x -= dlInt((int)fmod(m.x, 10000000.0), 1, x, hy, IL_T_VALUE * s, IL_INK, IL_RIGHT) + 6.0 * s;
        x -= dlLabel(LB_COMMIT, x, hy, IL_T_TITLE * s, IL_DIM, IL_RIGHT) + 30.0 * s;
    }
    // which identity hue is which palette, for the two colour rows
    [unroll] for (int p = 2; p >= 0; p--)
    {
        x -= dlLabel(LB_PAL_A + (uint)p, x, hy, IL_T_TITLE * s, IL_DIM, IL_RIGHT) + 5.0 * s;
        dlRect(float4(x - 9.0 * s, hy - 4.5 * s, x, hy + 4.5 * s), ptId(p), 1.0, 1.5 * s);
        x -= 21.0 * s;
    }
    dlLabel(LB_PALETTE, x + 3.0 * s, hy, IL_T_TITLE * s, IL_DIM, IL_RIGHT);

    // hover: the cell under the pointer (never stored)
    float2 uv = _ViewportPointerPosition, ptr = uv * R;
    bool inside = all(uv >= 0.0) && all(uv <= 1.0) && ptr.x > g.pane.x && ptr.x < g.pane.z;
    int row = (inside && ptr.y >= g.grid.y && ptr.y < g.grid.w) ? (int)floor((ptr.y - g.grid.y) / g.rowH) : -1;
    uint col = (ok && row >= 0) ? colAt(g, ptr.x) : SHEET_NONE;
    int hovGrp = col != SHEET_NONE ? (int)sheetGroup(col) : -1;

    // the sheet: each fixture type over its layers, each layer over its columns, attributes down the side
    dlBorderRect(g.pane, IL_RADIUS * s, IL_EDGE, 1.0);
    dlHLine(g.grid.y - 4.0 * s, g.pane.x + 1.0, g.pane.z - 1.0, IL_EDGE);
    float ty = g.pane.y + 11.0 * s, fy = g.grid.y - 13.0 * s;
    [unroll] for (uint t = 0u; t < 3u; t++)
    {
        // the fixture types over their layers
        uint f0 = t == 0u ? 0u : (t == 1u ? 3u : 5u), f1 = t == 0u ? 2u : (t == 1u ? 4u : 6u);
        float x0 = colX(g, SHEET_FIRST[f0]), x1 = colX(g, SHEET_END[f1] - 1u) + g.cell;
        bool hot = hovGrp >= (int)f0 && hovGrp <= (int)f1;
        dlLabel(LB_T_HALO_BEAM + t, x0, ty, IL_T_BODY * s, hot ? IL_INK : IL_DIM, IL_LEFT);
        dlHLine(ty + 8.0 * s, x0, x1, IL_EDGE);
    }
    [unroll] for (uint f = 0u; f < (uint)SHEET_GROUPS; f++)
    {
        float3 ink = (int)f == hovGrp ? IL_INK : IL_DIM;
        float fx = colX(g, SHEET_FIRST[f]);
        float w = dlLabel(LB_G_MOVE + f, fx, fy, IL_T_TITLE * s, ink, IL_LEFT);
        dlInt((int)(SHEET_END[f] - SHEET_FIRST[f]), 1, fx + w + 5.0 * s, fy, IL_T_CAP * s, IL_MID, IL_LEFT);
    }
    [loop] for (uint a = 0u; a < SHEET_ROWS; a++)
        dlLabel(LB_A_PAN + a, g.pane.x + 10.0 * s, g.grid.y + (a + 0.5) * g.rowH, IL_T_CAP * s, (int)a == row ? IL_INK : IL_DIM, IL_LEFT);
    if (row >= 0)
    {
        float ry = g.grid.y + row * g.rowH;
        dlRect(float4(g.pane.x + 1.0, ry, g.pane.z - 1.0, ry + g.rowH), IL_INK, 0.045, 0.0);
        if (col != SHEET_NONE)
        {
            float cx = colX(g, col);
            dlRect(float4(cx - 1.0, g.grid.y, cx + g.cell + 1.0, g.grid.w), IL_INK, 0.07, 0.0);
            dlBorderRect(float4(cx - 2.0, ry + 0.5, cx + g.cell + 2.0, ry + g.rowH - 0.5), 1.0, IL_INK, 1.0);
        }
    }

    // the inspector strip
    dlBorderRect(g.strip, IL_RADIUS * s, IL_EDGE, 1.0);
    float sy = ilMid(g.strip).y;
    x = g.strip.x + 12.0 * s;
    if (col != SHEET_NONE)
    {
        uint grp = (uint)hovGrp, a = (uint)row, fam = SHEET_TYPE[grp];
        uint prow = sheetRow(col), slot = rowSlot(prow);
        x += dlLabel(LB_N_MOVER + fam, x, sy, IL_T_TITLE * s, IL_INK, IL_LEFT) + 5.0 * s;
        x += dlInt((int)(col - SHEET_FIRST[grp]) + 1, 2, x, sy, IL_T_VALUE * s, IL_INK, IL_LEFT) + 8.0 * s;
        x += dlLabel(LB_G_MOVE + grp, x, sy, IL_T_TITLE * s, IL_INK, IL_LEFT) + 5.0 * s;
        x += 6.0 * s;
        x += dlLabel(LB_SLOT, x, sy, IL_T_BODY * s, IL_DIM, IL_LEFT) + 4.0 * s;
        x += dlInt((int)slot, 1, x, sy, IL_T_CAP * s, IL_DIM, IL_LEFT) + 8.0 * s;
        x += dlLabel(LB_ROW, x, sy, IL_T_BODY * s, IL_DIM, IL_LEFT) + 4.0 * s;
        x += dlInt((int)prow, 1, x, sy, IL_T_CAP * s, IL_DIM, IL_LEFT) + 24.0 * s;
        x += dlLabel(LB_A_PAN + a, x, sy, IL_T_TITLE * s, IL_DIM, IL_LEFT) + 12.0 * s;
        if (((SHEET_READS[grp] >> a) & 1u) != 0u)
        {
            float v = sheetAttr(P[prow], a);
            x += drawMeaning(grp, slot, a, v, x, sy) + 26.0 * s;
            // continuous attributes: where the value sits in its range, on the sheet's own ramp
            bool cont = a <= 3u || (a >= 9u && a <= 13u);
            if (cont)
            {
                float2 rg = SHEET_RANGE[a];
                float k = (a == 2u || a == 3u) ? 100.0 : 1.0;
                int dec = (rg.y - rg.x) <= 2.0 && k == 1.0 ? 2 : 0;
                x += dlNumEx(rg.x * k, dec, 1, false, x, sy, IL_T_CAP * s, IL_DIM, IL_LEFT) + 6.0 * s;
                float4 bar = float4(x, sy - 3.0 * s, x + 140.0 * s, sy + 3.0 * s);
                dlHGrad(bar, ptRamp(0.0), ptRamp(1.0), 1.5 * s);
                float t = saturate((v - rg.x) / (rg.y - rg.x));
                float tx = lerp(bar.x, bar.z, t);
                dlRect(float4(tx - 1.0 * s, bar.y - 4.0 * s, tx + 1.0 * s, bar.w + 4.0 * s), IL_INK, 1.0, 0.5 * s);
                dlNumEx(rg.y * k, dec, 1, false, bar.z + 6.0 * s, sy, IL_T_CAP * s, IL_DIM, IL_LEFT);
            }
        }
        else
        {
            x += dlLabel(LB_NOT_READ, x, sy, IL_T_BODY * s, IL_DIM, IL_LEFT) + 5.0 * s;
            dlLabel(LB_G_MOVE + grp, x, sy, IL_T_TITLE * s, IL_DIM, IL_LEFT);
        }
    }
    else
    {
        // the key to reading the sheet
        x += dlLabel(LB_KEY_VALUE, x, sy, IL_T_TITLE * s, IL_DIM, IL_LEFT) + 8.0 * s;
        x += dlLabel(LB_KEY_MIN, x, sy, IL_T_BODY * s, IL_DIM, IL_LEFT) + 6.0 * s;
        float4 bar = float4(x, sy - 3.0 * s, x + 90.0 * s, sy + 3.0 * s);
        dlHGrad(bar, ptRamp(0.0), ptRamp(1.0), 1.5 * s);
        x = bar.z + 6.0 * s;
        x += dlLabel(LB_KEY_MAX, x, sy, IL_T_BODY * s, IL_DIM, IL_LEFT) + 24.0 * s;
        dlRect(float4(x, sy - 6.0 * s, x + 12.0 * s, sy + 6.0 * s), IL_WELL, 1.0, 1.5 * s);
        dlBorderRect(float4(x, sy - 6.0 * s, x + 12.0 * s, sy + 6.0 * s), 1.5 * s, IL_EDGE, 1.0);
        x += 18.0 * s;
        dlLabel(LB_KEY_EMPTY, x, sy, IL_T_BODY * s, IL_DIM, IL_LEFT);
        dlLabel(LB_KEY_HINT, g.strip.z - 12.0 * s, sy, IL_T_BODY * s, IL_DIM, IL_RIGHT);
    }
    if (!ok)
        dlLabel(LB_WAITING, 0.5 * (g.grid.x + g.grid.z), 0.5 * (g.grid.y + g.grid.w), IL_T_BODY * s, IL_DIM, IL_CENTER);
    dlFinish();
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    if (gi == 0u) layout();
    dlEnd(gi);
}
