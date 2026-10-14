// Variant_Switcher_UI / layout - the switcher's type and chrome, recorded for the shared UI kit and
// drawn by ui.hlsl over render.hlsl's stage: the title and the live reading (which input is up and
// when the next automatic switch comes), the four host controls at their manifest rects (the rects
// the host hit-tests) from the host's own hover / press flags, the cycle progress, the stage frame
// that flashes on an automatic switch, and the keycap footer.
#include "switcher_view.hlsli"

struct SwitcherState
{
    float selected;
    float elapsed;
    float auto_latch;
    float one_latch;
    float two_latch;
    float three_latch;
    float cycle_pulse;
    float reserved;
};

StructuredBuffer<SwitcherState> Switcher : register(t1);
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"

// A key and what it does; returns the width used, with the gap to the next one.
float hintW(uint key, uint does, float s) { return ilLabelW(key, IL_T_CAP * s) + 18.0 * s + ilLabelW(does, IL_T_CAP * s); }
float hint(float x, float y, float s, uint key, uint does)
{
    float kw = ilLabelW(key, IL_T_CAP * s) + 12.0 * s, kh = 18.0 * s;
    dlKeycap(float4(x, y - 0.5 * kh, x + kw, y + 0.5 * kh), s, key);
    return kw + 6.0 * s + dlLabel(does, x + kw + 6.0 * s, y, IL_T_CAP * s, IL_DIM, IL_LEFT) + 16.0 * s;
}

void layout()
{
    float2 R = _Resolution.xy;
    float s = swScale(R);
    dlBegin(R);
    SwitcherState st = Switcher[0];
    int sel = clamp((int)round(st.selected), 0, 2);
    bool autoOn = auto_mode != 0;
    float period = max(cycle_seconds, 0.25);              // the interval state.hlsl cycles on
    float4 rAuto = ilCtlRect(UI_RECT_AUTO_MODE, R);
    float4 rLast = ilCtlRect(UI_RECT_SELECT_3, R);

    // ---- the header: the title, then the live reading under it
    float x0 = 0.02 * R.x;
    float y1 = 0.045 * R.y, y2 = 0.095 * R.y;
    float tw = dlLabel(LB_TITLE, x0, y1, 14.0 * s, IL_INK, IL_LEFT);
    dlLabelFit(LB_SUBTITLE, x0 + tw + 10.0 * s, y1, 12.0 * s, IL_DIM, IL_LEFT, rAuto.x - 16.0 * s - (x0 + tw + 10.0 * s));
    float x = x0, limit = rAuto.x - 16.0 * s;
    x += dlLabel(LB_LIVE, x, y2, IL_T_CAP * s, IL_DIM, IL_LEFT) + 12.0 * s;
    x += dlLabel(LB_INPUT, x, y2, IL_T_CAP * s, IL_DIM, IL_LEFT) + 4.0 * s;
    x += dlInt(sel + 1, 1, x, y2, 15.0 * s, IL_INK, IL_LEFT) + 14.0 * s;          // the input that is up
    float wNext = ilLabelW(LB_NEXT_IN, IL_T_CAP * s) + ilLabelW(LB_OF, IL_T_CAP * s) + ilLabelW(LB_U_S, IL_T_CAP * s)
                + 2.0 * ilNumW(4u, IL_T_VALUE * s) + 14.0 * s;
    if (autoOn && x + wNext <= limit)
    {
        x += dlLabel(LB_NEXT_IN, x, y2, IL_T_CAP * s, IL_DIM, IL_LEFT) + 4.0 * s;
        x += dlNum(max(period - st.elapsed, 0.0), 1, x, y2, IL_T_VALUE * s, IL_INK, IL_LEFT) + 4.0 * s;
        x += dlLabel(LB_OF, x, y2, IL_T_CAP * s, IL_DIM, IL_LEFT) + 4.0 * s;
        x += dlNum(period, 1, x, y2, IL_T_VALUE * s, IL_MID, IL_LEFT) + 2.0 * s;
        dlLabel(LB_U_S, x, y2, IL_T_CAP * s, IL_DIM, IL_LEFT);
    }
    else if (!autoOn) dlLabelFit(LB_DIRECT, x, y2, IL_T_CAP * s, IL_DIM, IL_LEFT, limit - x);

    // ---- AUTO and the three inputs: the accent tick marks AUTO while it runs and the input that is up
    uint ids[4] = { UI_AUTO_MODE, UI_SELECT_1, UI_SELECT_2, UI_SELECT_3 };
    float4 rects[4] = { UI_RECT_AUTO_MODE, UI_RECT_SELECT_1, UI_RECT_SELECT_2, UI_RECT_SELECT_3 };
    uint on = (autoOn ? 1u : 0u) | (2u << (uint)sel);
    [loop] for (uint i = 0u; i < 4u; i++)
        dlChip(ilCtlRect(rects[i], R), s, LB_C_AUTO + i, ((on >> i) & 1u) != 0u, ilCtlHot(ids[i]), ilCtlDown(ids[i]));

    // the time to the next automatic switch: a live reading, so it takes the accent
    if (autoOn)
    {
        float4 track = float4(rAuto.x, 0.114 * R.y, rLast.z, max(0.119 * R.y, 0.114 * R.y + 2.0));
        dlRect(track, IL_WELL, 1.0, 1.0);
        dlRect(float4(track.xy, lerp(track.x, track.z, saturate(st.elapsed / period)), track.w), IL_ACCENT, 1.0, 1.0);
    }

    // ---- the stage frame, which flashes when AUTO switches
    uint iw = 1u, ih = 1u;
    _Tex0.GetDimensions(iw, ih);
    float4 stage = swStage(R, float2(iw, ih));
    dlBorderRect(ilInset(stage, -1.0), 0.0, IL_EDGE, 1.0);
    float pulse = saturate(st.cycle_pulse);
    if (pulse > 0.01)
    {
        float w = 1.0 + 2.0 * pulse;
        dlBorderRect(ilInset(stage, -w), 0.0, lerp(IL_EDGE, IL_ACCENT, pulse), w);
    }

    // ---- what the clicks do
    float fy = R.y - 0.5 * swFooterH(R);
    float hx = x0, right = 0.98 * R.x;
    if (hx + hintW(LB_K_CLICK, LB_D_AUTO, s) <= right) hx += hint(hx, fy, s, LB_K_CLICK, LB_D_AUTO);
    if (hx + hintW(LB_K_CLICK, LB_D_PICK, s) <= right) hint(hx, fy, s, LB_K_CLICK, LB_D_PICK);

    dlFinish();
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    if (gi == 0u) layout();
    dlEnd(gi);
}
