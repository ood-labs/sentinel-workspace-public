// Paint_Canvas / layout - the editor's type and chrome, recorded for the shared UI kit and drawn by
// ui.hlsl over view.hlsl's canvas: the toolbar (title, brush and zoom readouts, CLEAR), the
// canvas frame, and the keycap footer.
//
// Fixed pixels at s = 1: the 32 px toolbar and the CLEAR rect are the hit-test contract in
// events.hlsl, so the geometry comes from paint_view.hlsli (the same formulas) and the type is
// sized for that toolbar. Hover is read from the pointer here and never stored.
#include "paint_view.hlsli"
StructuredBuffer<float4> PaintState : register(t0);
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"

#define HINTS 7u

float hintW(uint i) { return ilLabelW(LB_K_CLICK + i, IL_T_CAP) + 12.0 + 6.0 + ilLabelW(LB_D_CLICK + i, IL_T_CAP); }

// A key and what it does; returns the width used, with the gap to the next one.
float hint(float x, float y, uint i)
{
    float kw = ilLabelW(LB_K_CLICK + i, IL_T_CAP) + 12.0, kh = 18.0;
    dlKeycap(float4(x, y - 0.5 * kh, x + kw, y + 0.5 * kh), 1.0, LB_K_CLICK + i);
    return kw + 6.0 + dlLabel(LB_D_CLICK + i, x + kw + 6.0, y, IL_T_CAP, IL_DIM, IL_LEFT) + 16.0;
}

// Caption, whole number, unit - the width it takes, and drawing it from x.
float readoutW(uint cap, float v, uint unit)
{
    return ilLabelW(cap, IL_T_CAP) + 6.0 + ilNumW(ilFormat(v, 0, 1, false).n, IL_T_VALUE) + 3.0 + ilLabelW(unit, IL_T_CAP);
}
void readout(float x, float y, uint cap, float v, uint unit)
{
    x += dlLabel(cap, x, y, IL_T_CAP, IL_DIM, IL_LEFT) + 6.0;
    x += dlNum(v, 0, x, y, IL_T_VALUE, IL_INK, IL_LEFT) + 3.0;
    dlLabel(unit, x, y, IL_T_CAP, IL_DIM, IL_LEFT);
}

void layout()
{
    float2 R = _Resolution.xy;
    dlBegin(R);
    float4 view = PaintState[19];
    float2 ptr = _ViewportPointerPosition * R;
    bool inView = all(ptr >= 0.0) && all(ptr <= R);

    // ---- the canvas frame: where the painted image ends (view.hlsl draws the image)
    float4 cr = pcCanvasRectPx(R, view.xy, view.z);
    dlClip(float4(0.0, PC_TOOLBAR_PX, R));
    dlBorderRect(ilInset(cr, -1.0), 0.0, IL_EDGE, 1.0);
    dlClipReset();

    // ---- the toolbar
    float ty = 0.5 * PC_TOOLBAR_PX;
    dlRect(float4(0.0, 0.0, R.x, PC_TOOLBAR_PX), IL_PANEL, 1.0, 0.0);
    dlHLine(PC_TOOLBAR_PX - 0.5, 0.0, R.x, IL_EDGE);
    float4 cl = pcClearRectPx(R);
    bool hot = inView && ilIn(ptr, cl);
    dlChip(cl, 1.0, LB_CLEAR, false, hot, hot && (_ViewportButtons & 1u) != 0u);

    // title, then the readouts right-aligned before CLEAR: the subtitle gives way first, then zoom
    float x0 = 12.0;
    float tw = dlLabel(LB_TITLE, x0, ty, 14.0, IL_INK, IL_LEFT);
    float brush = PaintState[0].y * PC_CANVAS_PIXELS.y;            // stamp height in canvas px
    float zoom = 100.0 * pcDisplayScale(R, view.z);                // screen px per canvas px
    float wB = readoutW(LB_BRUSH, brush, LB_PX), wZ = readoutW(LB_ZOOM, zoom, LB_PCT);
    float wSub = ilLabelW(LB_SUBTITLE, 12.0) + 10.0;
    float right = cl.x - 16.0, left = x0 + tw + 18.0;
    bool showZ = right - left >= wB + 18.0 + wZ;
    bool showB = right - left >= wB;
    bool showSub = right - left >= wSub + (showZ ? wB + 18.0 + wZ : (showB ? wB : 0.0)) + 18.0;
    if (showSub) dlLabel(LB_SUBTITLE, x0 + tw + 10.0, ty, 12.0, IL_DIM, IL_LEFT);
    float rx = right;
    if (showZ) { rx -= wZ; readout(rx, ty, LB_ZOOM, zoom, LB_PCT); rx -= 18.0; }
    if (showB) { rx -= wB; readout(rx, ty, LB_BRUSH, brush, LB_PX); }

    // ---- the Depth and Mask outputs beside the canvas when it leaves room (view.hlsl draws them):
    // what the Depth Paint controls are doing, which the painting itself never shows
    float4 depthR, maskR;
    if (pcThumbs(R, view.xy, view.z, depthR, maskR))
    {
        dlBorderRect(ilInset(depthR, -1.0), 0.0, IL_EDGE, 1.0);
        dlBorderRect(ilInset(maskR, -1.0), 0.0, IL_EDGE, 1.0);
        dlLabel(LB_DEPTH, depthR.x, depthR.y - 12.0, IL_T_CAP, IL_DIM, IL_LEFT);
        dlLabel(LB_B_OVER + (uint)clamp(depth_blend_mode, 0, 2), depthR.z, depthR.y - 12.0, IL_T_CAP, IL_MID, IL_RIGHT);
        dlLabel(LB_MASK, maskR.x, maskR.y - 12.0, IL_T_CAP, IL_DIM, IL_LEFT);
    }

    // ---- the gestures (the manifest's bindings) as keycaps: a row under the canvas when it leaves
    // a margin there, a column in the left margin when that is wide enough, else a row on a plate
    // over the canvas's bottom edge that steps aside while the pointer is over it
    float widest = 0.0;
    [loop] for (uint j = 0u; j < HINTS; j++) widest = max(widest, hintW(j));
    float below = R.y - min(cr.w, R.y);
    bool column = below < 30.0 && cr.x >= widest + 24.0 && R.y - PC_TOOLBAR_PX >= HINTS * 26.0 + 16.0;
    if (column)
    {
        float cy = R.y - 18.0 - (HINTS - 1u) * 26.0;
        [loop] for (uint c = 0u; c < HINTS; c++) { hint(12.0, cy, c); cy += 26.0; }
        dlFinish();
        return;
    }
    float room = R.x - 36.0;
    uint shown = 0u;
    float fw = 0.0;
    [loop] for (uint i = 0u; i < HINTS; i++)
    {
        float w = hintW(i);
        if (fw + w > room) break;
        fw += w + 16.0;
        shown++;
    }
    fw = max(fw - 16.0, 0.0) + 20.0;
    bool overlay = below < 30.0;
    float fy = overlay ? R.y - 22.0 : min(cr.w, R.y) + 0.5 * below;
    float4 bar = float4(8.0, fy - 14.0, 8.0 + fw, fy + 14.0);
    bool away = overlay && inView && ilIn(ptr, ilInset(bar, -24.0));
    if (shown > 0u && !away)
    {
        if (overlay) dlRect(bar, IL_PANEL, 0.86, IL_RADIUS);
        float hx = bar.x + 10.0;
        [loop] for (uint k = 0u; k < shown; k++) hx += hint(hx, fy, k);
    }
    dlFinish();
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    if (gi == 0u) layout();
    dlEnd(gi);
}
