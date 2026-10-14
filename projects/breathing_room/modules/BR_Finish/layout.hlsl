// BR_Finish / layout.hlsl -- the finish schedule's chrome and type, recorded into the shared UI
// kit's draw list (ui.hlsl draws it over plate.hlsl's samples). Every rect comes from
// finish_layout.hlsli, the same grid finish.hlsl hit-tests clicks against.
//
// Each card: its code and name, the record's own colour as a small chip (through ptSampleColour),
// and the numbers that define the finish -- roughness always, then metal, coat, translucency and
// sheen wherever they are not zero. A card's edge is quiet at rest, a value step under the
// pointer, and the accent when it is the selection (which BR_Render's Scope view shows in the room).
#include "../_shared/br_shade.hlsli"
StructuredBuffer<BRRec> FinishBuf : register(t0);
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"
#include "finish_layout.hlsli"

// A key and what it does; returns the width used.
float hint(float x, float y, float s, uint key, uint does)
{
    float kw = ilLabelW(key, IL_T_CAP * s) + 12.0 * s, kh = 18.0 * s;
    dlKeycap(float4(x, y - 0.5 * kh, x + kw, y + 0.5 * kh), s, key);
    return kw + 6.0 * s + dlLabel(does, x + kw + 6.0 * s, y, IL_T_CAP * s, IL_DIM, IL_LEFT) + 16.0 * s;
}

// One defining number, "rough 0.32", if it fits before xr; returns the new pen (past xr when it
// did not fit, so every later number is dropped too rather than squeezed in out of order).
float property(uint label, float v, float x, float y, float xr, float s)
{
    float w = ilLabelW(label, IL_T_CAP * s) + 4.0 * s + ilNumW(ilFormat(v, 2, 1, false).n, IL_T_VALUE * s);
    if (x + w > xr) return xr + 1.0;
    x += dlLabel(label, x, y, IL_T_CAP * s, IL_DIM, IL_LEFT) + 4.0 * s;
    return x + dlNum(v, 2, x, y, IL_T_VALUE * s, IL_MID, IL_LEFT) + 10.0 * s;
}

void card(FinishLayout L, int i, bool sel, bool hot)
{
    float s = L.s;
    float4 cd = finishCardRect(L, i);
    BRMat m = brMatFromRec(FinishBuf[i]);
    if (sel) dlBorderRect(ilInset(cd, -1.0), IL_RADIUS * s + 1.0, IL_ACCENT, 2.0);
    else dlBorderRect(cd, IL_RADIUS * s, hot ? IL_RULE * 1.5 : IL_EDGE, 1.0);
    dlClip(ilInset(cd, 1.0));
    float pad = min(10.0 * s, L.cell * 0.08);
    float x0 = cd.x + pad, xr = cd.z - pad;
    float y2 = cd.w - pad - 5.0 * s, y1 = y2 - 15.0 * s;
    // code and name, then the record's own colour at the right
    float4 chip = float4(xr - 18.0 * s, y1 - 4.5 * s, xr, y1 + 4.5 * s);
    dlRectEdged(chip, ptSampleColour(brLinearToSrgb(m.base)), 1.0, 1.5 * s, IL_RULE, 1.0);
    float x = x0 + dlLabel(LB_C0 + (uint)i, x0, y1, IL_T_TITLE * s, sel ? IL_ACCENT : IL_INK, IL_LEFT) + 6.0 * s;
    dlLabelFit(LB_N0 + (uint)i, x, y1, IL_T_BODY * s, IL_MID, IL_LEFT, chip.x - 6.0 * s - x);
    // the defining numbers
    x = property(LB_ROUGH, m.rough, x0, y2, xr, s);
    if (m.metal > 0.005) x = property(LB_METAL, m.metal, x, y2, xr, s);
    if (m.coat > 0.005)  x = property(LB_COAT, m.coat, x, y2, xr, s);
    if (m.trans > 0.005) x = property(LB_TRANS, m.trans, x, y2, xr, s);
    if (m.sheen > 0.005) property(LB_SHEEN, m.sheen, x, y2, xr, s);
    dlClipReset();
}

void layout()
{
    float2 res = _Resolution.xy;
    FinishLayout L = finishLayout(res);
    float s = L.s;
    BRRec ed = FinishBuf[FINISH_EDITOR];
    int sel = (int)round(ed.dims.x);
    bool hasSel = sel >= 0 && sel < MAT_SLOTS;
    int hov = finishCellAt(L, _ViewportPointerPosition * res);
    dlBegin(res);

    // ---- title strip: the count and the selection
    float hy = ilMid(L.head).y;
    float x = 14.0 * s;
    x += dlLabel(LB_TITLE, x, hy, 15.0 * s, IL_INK, IL_LEFT) + 14.0 * s;
    x += dlLabel(LB_SUBTITLE, x, hy, IL_T_BODY * s, IL_DIM, IL_LEFT) + 22.0 * s;
    x += dlInt(MAT_SLOTS, 1, x, hy, IL_T_VALUE * s, IL_INK, IL_LEFT) + 5.0 * s;
    x += dlLabel(LB_COUNT, x, hy, IL_T_BODY * s, IL_DIM, IL_LEFT) + 28.0 * s;
    if (hasSel)
    {
        x += dlLabel(LB_SELECTED, x, hy, IL_T_BODY * s, IL_DIM, IL_LEFT) + 8.0 * s;
        x += dlLabel(LB_C0 + (uint)sel, x, hy, IL_T_TITLE * s, IL_ACCENT, IL_LEFT) + 6.0 * s;
        dlLabel(LB_N0 + (uint)sel, x, hy, IL_T_BODY * s, IL_INK, IL_LEFT);
    }
    else dlLabel(LB_NOSEL, x, hy, IL_T_BODY * s, IL_DIM, IL_LEFT);
    dlHLine(L.head.w - 0.5, 0.0, res.x, IL_EDGE);

    // ---- the samples' cards
    [loop] for (int i = 0; i < MAT_SLOTS; i++) card(L, i, i == sel, i == hov);

    // ---- hints, and where the selection goes
    float fy = ilMid(L.foot).y;
    float fx = 14.0 * s;
    fx += hint(fx, fy, s, LB_K_CLICK, LB_D_CLICK);
    fx += hint(fx, fy, s, LB_K_ESC, LB_D_ESC);
    float usedW = ilLabelW(LB_USED, IL_T_CAP * s);
    bool used = res.x - 14.0 * s - usedW > fx + ilLabelW(LB_D_PROPS, IL_T_CAP * s) + 24.0 * s;
    dlLabelFit(LB_D_PROPS, fx, fy, IL_T_CAP * s, IL_DIM, IL_LEFT, res.x - 14.0 * s - fx);
    if (used) dlLabel(LB_USED, res.x - 14.0 * s, fy, IL_T_CAP * s, IL_DIM, IL_RIGHT);

    dlFinish();
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    if (gi == 0u) layout();
    dlEnd(gi);
}
