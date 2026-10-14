// Desk / layout - draws what the host controls report, over a preview of the wired Program.
//
// Nothing here decides anything. Lit, selected and fading states, pad colours, fader values and
// readout text all arrive from the Cue Brain Script through panel_feedback and panel.label; the
// host keeps them in _ViewportControlState and _PanelLabels, and this pass reads them back. The
// stack list on the right is built from the cue pads' own labels and states, so it can never
// disagree with the pads.
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"

static const float4 PREVIEW = float4(16.0, 56.0, 736.0, 461.0) / float4(1280.0, 720.0, 1280.0, 720.0);
static const float4 STACK = float4(912.0, 330.0, 1264.0, 452.0) / float4(1280.0, 720.0, 1280.0, 720.0);

void plate(float4 r, float s) { dlRect(r, IL_PANEL, 0.86, IL_RADIUS * s); }
bool fading(uint i) { return _ViewportControlState[i].state == 4u; }
bool selected(uint i) { return _ViewportControlState[i].state == 3u; }

float chip(float x, float y, float s, uint label, float3 ink, bool dot)
{
    float w = ilLabelW(label, IL_T_CAP * s) + (dot ? 30.0 : 20.0) * s;
    float4 r = float4(x - w, y, x, y + 22.0 * s);
    dlRect(r, IL_FIELD, 0.9, IL_RADIUS * s);
    if (dot) dlCircle(float2(r.x + 11.0 * s, ilMid(r).y), 3.5 * s, ink, 1.0);
    dlLabel(label, r.z - 10.0 * s, ilMid(r).y, IL_T_CAP * s, ink, IL_RIGHT);
    return w;
}

void layout()
{
    float2 res = _Resolution.xy;
    float s = ilCtx(res).s;
    dlBegin(res);

    // header
    float4 hr = float4(16.0 * s, 14.0 * s, 0.0, 44.0 * s);
    float tw = ilLabelW(LB_TITLE, 15.0 * s), sw = ilLabelW(LB_SUBTITLE, 12.0 * s);
    hr.z = hr.x + tw + sw + 40.0 * s;
    plate(hr, s);
    float hy = ilMid(hr).y;
    dlLabel(LB_TITLE, hr.x + 12.0 * s, hy, 15.0 * s, IL_INK, IL_LEFT);
    dlLabel(LB_SUBTITLE, hr.x + 12.0 * s + tw + 14.0 * s, hy, 12.0 * s, IL_DIM, IL_LEFT);

    // the Program it is wired to, with what is happening to it
    float4 pr = ilCtlRect(PREVIEW, res);
    dlRectEdged(ilInset(pr, -1.0), IL_FIELD, 1.0, IL_RADIUS * s, IL_EDGE, 1.0);
    dlImage(pr, float4(0.0, 0.0, 1.0, 1.0), float3(1.0, 1.0, 1.0), 1.0);
    float4 cp = float4(pr.x + 8.0 * s, pr.y + 8.0 * s, pr.x + 8.0 * s + ilLabelW(LB_PROGRAM, IL_T_CAP * s) + 20.0 * s, pr.y + 30.0 * s);
    dlRect(cp, IL_FIELD, 0.9, IL_RADIUS * s);
    dlLabel(LB_PROGRAM, cp.x + 10.0 * s, ilMid(cp).y, IL_T_CAP * s, IL_MID, IL_LEFT);
    float cx = pr.z - 8.0 * s;
    bool bo = ilCtlLit(UI_BLACKOUT);
    if (bo) cx -= chip(cx, pr.y + 8.0 * s, s, LB_BLACKOUT, IL_ALARM, true) + 6.0 * s;
    if (fading(UI_GO)) chip(cx, pr.y + 8.0 * s, s, LB_FADING, IL_ACCENT, true);

    // readouts: what is live, what is next, and how far the fade has run
    float4 rn = ilCtlRect(UI_RECT_R_NOW, res);
    float4 rx = ilCtlRect(UI_RECT_R_NEXT, res);
    dlPanelLabel(UI_R_NOW, rn.x + 2.0 * s, ilMid(rn).y, 24.0 * s, IL_BOLD, IL_INK, IL_LEFT);
    dlPanelLabel(UI_R_NEXT, rx.x + 2.0 * s, ilMid(rx).y, 14.0 * s, IL_SANS, IL_MID, IL_LEFT);
    float py = rx.w + 9.0 * s;
    dlRect(float4(rx.x, py - 1.0 * s, rx.z, py + 1.0 * s), IL_GRID, 1.0, 1.0 * s);
    if (fading(UI_GO))
        dlRect(float4(rx.x, py - 2.0 * s, lerp(rx.x, rx.z, saturate(_ViewportControlState[UI_GO].fade)), py + 2.0 * s), IL_ACCENT, 1.0, 2.0 * s);

    // every pad through one call site
    uint ids[11] = { UI_GO, UI_BACK, UI_BLACKOUT, UI_CUE1, UI_CUE2, UI_CUE3, UI_CUE4, UI_CUE5, UI_CUE6, UI_CUE7, UI_CUE8 };
    float4 rects[11] = { UI_RECT_GO, UI_RECT_BACK, UI_RECT_BLACKOUT, UI_RECT_CUE1, UI_RECT_CUE2, UI_RECT_CUE3, UI_RECT_CUE4,
                         UI_RECT_CUE5, UI_RECT_CUE6, UI_RECT_CUE7, UI_RECT_CUE8 };
    bool heard = false; // a pad colour only ever arrives as feedback
    [loop] for (uint i = 0u; i < 11u; i++)
    {
        float4 r = ilCtlRect(rects[i], res);
        bool lit = ilCtlLit(ids[i]);
        heard = heard || (i >= 3u && _ViewportControlState[ids[i]].rgba != 0u);
        dlShowPad(r, s, ids[i], lit);
        if (i >= 3u) dlInt((int)(i - 2u), 1, r.x + 9.0 * s, r.y + 11.0 * s, IL_T_CAP * s, lit ? IL_INK : IL_DIM, IL_LEFT);
    }

    // faders: fade time (0..10 s) and master
    uint fid[2] = { UI_FADE, UI_MASTER };
    float4 frc[2] = { UI_RECT_FADE, UI_RECT_MASTER };
    uint fcap[2] = { LB_C_FADE, LB_C_MASTER };
    [loop] for (uint k = 0u; k < 2u; k++)
    {
        float4 r = ilCtlRect(frc[k], res);
        float v = ilCtlValue(fid[k]);
        dlLabel(fcap[k], ilMid(r).x, r.y - 11.0 * s, IL_T_CAP * s, IL_DIM, IL_CENTER);
        dlFader(r, s, v, ilCtlHot(fid[k]), ilCtlDown(fid[k]));
        float vy = r.w + 13.0 * s;
        float uw = ilLabelW(k == 0u ? LB_UNIT_S : LB_PCT, IL_T_CAP * s);
        float nw = dlNum(k == 0u ? v * 10.0 : v * 100.0, k == 0u ? 1 : 0, ilMid(r).x + 0.5 * uw, vy, IL_T_VALUE * s, IL_INK, IL_CENTER);
        dlLabel(k == 0u ? LB_UNIT_S : LB_PCT, ilMid(r).x + 0.5 * uw + 0.5 * nw + 2.0 * s, vy, IL_T_CAP * s, IL_DIM, IL_LEFT);
    }

    // the stack: the cue pads' own labels and states as a list
    float4 st = ilCtlRect(STACK, res);
    dlLabel(LB_STACK, st.x, st.y, IL_T_TITLE * s, IL_INK, IL_LEFT);
    float rowH = (st.w - st.y - 16.0 * s) / 8.0;
    [loop] for (uint c = 0u; c < 8u; c++)
    {
        uint id = UI_CUE1 + c;
        float y = st.y + 16.0 * s + (c + 0.5) * rowH;
        bool live = ilCtlLit(id), nxt = selected(id) || fading(id);
        float3 ink = live ? IL_ACCENT : (nxt ? IL_INK : IL_DIM);
        if (nxt) dlTri(float2(st.x + 4.0 * s, y), 3.5 * s, 6.0 * s, 3u, IL_INK, 1.0);
        dlInt((int)c + 1, 1, st.x + 14.0 * s, y, IL_T_CAP * s, ink, IL_LEFT);
        dlPanelLabel(id, st.x + 30.0 * s, y, IL_T_CAP * s, IL_SANS, ink, IL_LEFT);
        float bx0 = st.x + 112.0 * s; // a column just past the longest name
        if (fading(id))
            dlRect(float4(bx0, y - 1.5 * s, lerp(bx0, bx0 + 72.0 * s, saturate(_ViewportControlState[id].fade)), y + 1.5 * s), IL_ACCENT, 1.0, 1.0);
    }
    if (!heard)
        dlLabel(LB_QUIET, ilMid(pr).x, pr.w + 8.0 * s, IL_T_CAP * s, IL_MID, IL_CENTER);

    // hint bar
    float kh = 18.0 * s;
    float bx = 16.0 * s, by = res.y - 26.0 * s;
    float total = 0.0;
    [loop] for (uint k1 = 0u; k1 < 5u; k1++)
        total += ilLabelW(LB_K_CUE + k1, IL_T_CAP * s) + 12.0 * s + 6.0 * s + ilLabelW(LB_D_CUE + k1, IL_T_CAP * s) + 16.0 * s;
    plate(float4(bx, by - 15.0 * s, bx + total + 8.0 * s, by + 15.0 * s), s);
    bx += 10.0 * s;
    [loop] for (uint k2 = 0u; k2 < 5u; k2++)
    {
        float kw = ilLabelW(LB_K_CUE + k2, IL_T_CAP * s) + 12.0 * s;
        float dw = ilLabelW(LB_D_CUE + k2, IL_T_CAP * s);
        dlKeycap(float4(bx, by - kh * 0.5, bx + kw, by + kh * 0.5), s, LB_K_CUE + k2);
        dlLabel(LB_D_CUE + k2, bx + kw + 6.0 * s, by, IL_T_CAP * s, IL_DIM, IL_LEFT);
        bx += kw + 6.0 * s + dw + 16.0 * s;
    }
    dlFinish();
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    if (gi == 0u) layout();
    dlEnd(gi);
}
