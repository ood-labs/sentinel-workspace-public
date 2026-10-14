// il_ui.hlsli - Interaction Lab kit, layout side: widgets recorded into the draw list.
//
// Each widget takes its rect and its VALUES and records commands; hit testing in the reducer uses
// the same rects (from the station's layout functions), so geometry has one source.
//
// States are values, not hues:
//   hot   pointer over it                 one value step up - never a hue
//   down  being pressed or dragged        the grabbed part takes the ACCENT
//   on    a chosen mode / engaged toggle  ink on a lifted face + a 2 px accent tick
// So the accent always marks the thing you are holding or the mode you chose, and nothing else.
//
// Include after _labels.generated.hlsli (widgets take label ids) and il_draw.hlsli.
#ifndef IL_UI_HLSLI
#define IL_UI_HLSLI

#include "../_shared/ui/il_draw.hlsli"


// ---------------------------------------------------------------- panes
// A pane: card, quiet edge, header strip with a title. Returns the body below the header.
float4 dlPane(float4 r, float s, uint title, bool focused)
{
    dlRectEdged(r, IL_PANEL, 1.0, IL_RADIUS * s, focused ? IL_RULE : IL_EDGE, 1.0);
    float4 body = r;
    float4 head = ilCutTop(body, ilSnap(IL_HEADER * s));
    dlHLine(head.w, head.x + 1.0, head.z - 1.0, IL_EDGE);
    dlLabel(title, head.x + 10.0 * s, ilMid(head).y, IL_T_TITLE * s, focused ? IL_INK : IL_DIM, IL_LEFT);
    return body;
}
// The header strip of a pane rect (for placing tool chips at its right end).
float4 ilPaneHead(float4 r, float s) { return float4(r.x, r.y, r.z, r.y + ilSnap(IL_HEADER * s)); }

// ---------------------------------------------------------------- chips and segments
void dlChip(float4 r, float s, uint label, bool on, bool hot, bool down)
{
    float3 face = down ? IL_WELL : (on ? IL_RAISE * 1.9 : (hot ? IL_RAISE * 1.45 : IL_RAISE));
    dlRectEdged(r, face, 1.0, IL_RADIUS * s, on ? IL_RULE : IL_EDGE, 1.0);
    if (on) dlRect(float4(r.x + 6.0 * s, r.w - 3.0 * s, r.z - 6.0 * s, r.w - 1.0 * s), IL_ACCENT, 1.0, 1.0);
    dlLabel(label, ilMid(r).x, ilMid(r).y, IL_T_BODY * s, on ? IL_INK : (hot ? IL_MID * 1.2 : IL_MID), IL_CENTER);
}

// n equal segments labelled firstLabel..firstLabel+n-1; sel chosen, hotSeg hovered (-1 none).
void dlSegmented(float4 r, float s, uint firstLabel, uint n, int sel, int hotSeg)
{
    dlRectEdged(r, IL_WELL, 1.0, IL_RADIUS * s, IL_EDGE, 1.0);
    float w = (r.z - r.x) / max((float)n, 1.0);
    [loop] for (uint i = 0u; i < n; i++)
    {
        float4 seg = float4(r.x + i * w, r.y, r.x + (i + 1u) * w, r.w);
        if ((int)i == sel)
        {
            dlRect(ilInset(seg, 2.0 * s), IL_RAISE * 2.0, 1.0, IL_RADIUS * s * 0.8);
            dlRect(float4(seg.x + 7.0 * s, seg.w - 4.0 * s, seg.z - 7.0 * s, seg.w - 2.0 * s), IL_ACCENT, 1.0, 1.0);
        }
        else if ((int)i == hotSeg) dlRect(ilInset(seg, 2.0 * s), IL_RAISE * 1.3, 1.0, IL_RADIUS * s * 0.8);
        if (i > 0u && (int)i != sel && (int)i - 1 != sel) dlVLine(seg.x, r.y + 5.0 * s, r.w - 5.0 * s, IL_EDGE);
        dlLabel(firstLabel + i, ilMid(seg).x, ilMid(seg).y, IL_T_BODY * s, ((int)i == sel) ? IL_INK : IL_DIM, IL_CENTER);
    }
}

// ---------------------------------------------------------------- continuous controls
void dlSlider(float4 r, float s, float v, bool hot, bool down)
{
    float cy = ilMid(r).y;
    float th = ilSnap(4.0 * s);
    float4 track = float4(r.x, cy - th * 0.5, r.z, cy + th * 0.5);
    dlRectEdged(track, IL_WELL, 1.0, th * 0.5, IL_EDGE, 1.0);
    float x = lerp(r.x, r.z, saturate(v));
    dlRect(float4(r.x, track.y, x, track.w), (hot || down) ? IL_MID * 1.1 : IL_MID * 0.8, 1.0, th * 0.5);
    float4 thumb = float4(x - 2.5 * s, cy - 8.0 * s, x + 2.5 * s, cy + 8.0 * s);
    dlRect(ilInset(thumb, -1.5), IL_FIELD, 1.0, 3.0 * s);
    dlRect(thumb, down ? IL_ACCENT : IL_INK, 1.0, 2.0 * s);
}

void dlFader(float4 r, float s, float v, bool hot, bool down)
{
    float cx = ilMid(r).x;
    float tw = ilSnap(4.0 * s);
    float pad = 10.0 * s;
    float4 track = float4(cx - tw * 0.5, r.y + pad, cx + tw * 0.5, r.w - pad);
    dlRectEdged(track, IL_WELL, 1.0, tw * 0.5, IL_EDGE, 1.0);
    float y = lerp(track.w, track.y, saturate(v));
    dlRect(float4(track.x, y, track.z, track.w), IL_MID * 0.8, 1.0, tw * 0.5);
    [loop] for (int i = 0; i <= 10; i++)
    {
        float ty = lerp(track.w, track.y, i / 10.0);
        float len = ((i % 5) == 0) ? 7.0 * s : 4.0 * s;
        dlHLine(ty, r.x + 2.0 * s, r.x + 2.0 * s + len, IL_RULE);
    }
    float cw = min((r.z - r.x) * 0.5 - 2.0 * s, 16.0 * s);
    float4 cap = float4(cx - cw, y - 7.0 * s, cx + cw, y + 7.0 * s);
    dlRect(ilInset(cap, -1.5), IL_FIELD, 1.0, 3.5 * s);
    dlRect(cap, hot ? IL_RAISE * 2.6 : IL_RAISE * 2.2, 1.0, 2.5 * s);
    dlRect(float4(cap.x + 3.0 * s, y - 0.75, cap.z - 3.0 * s, y + 0.75), down ? IL_ACCENT : IL_INK, 1.0, 0.0);
}

void dlToggle(float4 r, float s, bool on, bool hot)
{
    float h = min(r.w - r.y, 16.0 * s);
    float w = h * 1.9;
    float2 c = ilMid(r);
    float4 pill = float4(c.x - w * 0.5, c.y - h * 0.5, c.x + w * 0.5, c.y + h * 0.5);
    dlRectEdged(pill, on ? IL_MID * 0.85 : IL_WELL, 1.0, h * 0.5, on ? IL_MID : (hot ? IL_RULE * 1.3 : IL_RULE), 1.0);
    float kx = on ? pill.z - h * 0.5 : pill.x + h * 0.5;
    dlCircle(float2(kx, c.y), h * 0.5 - 2.5 * s, on ? IL_FIELD : IL_MID, 1.0);
}

// 270 degree knob. v in 0..1.
void dlKnob(float2 c, float rad, float s, float v, bool down)
{
    float sweep = 0.75 * IL_PI;
    dlArc(c, rad, 3.0 * s, -sweep, sweep, IL_EDGE * 1.3, 1.0);
    float a1 = lerp(-sweep, sweep, saturate(v));
    if (v > 0.002) dlArc(c, rad, 3.0 * s, -sweep, a1, down ? IL_ACCENT : IL_MID, 1.0);
    dlCircle(c, rad - 6.0 * s, IL_RAISE * 1.6, 1.0);
    float2 dir = float2(sin(a1), -cos(a1));
    dlLine(c + dir * (rad * 0.18), c + dir * (rad - 8.0 * s), 2.0 * s, IL_INK, 1.0);
}

// Segmented vertical meter. v, peak in 0..1. Segments above 0.92 are the alarm zone.
void dlMeter(float4 r, float s, float v, float peak)
{
    dlRect(r, IL_WELL, 1.0, 2.0 * s);
    float4 in4 = ilInset(r, 2.0 * s);
    float segH = 3.0 * s, gap = 2.0 * s;
    float h = in4.w - in4.y;
    uint n = (uint)max(floor((h + gap) / (segH + gap)), 1.0);
    // lit run and unlit run as two rects each split by the gaps: draw lit segments individually
    [loop] for (uint k = 0u; k < n && k < 64u; k++)
    {
        float lvl = (k + 0.5) / n;
        float y1 = in4.w - k * (segH + gap);
        float4 seg = float4(in4.x, y1 - segH, in4.z, y1);
        bool lit = lvl <= saturate(v);
        bool pk = abs(lvl - saturate(peak)) < 0.5 / n;
        float3 c = pk ? IL_INK : (lit ? ((lvl > 0.92) ? IL_ALARM : IL_MID) : IL_EDGE * 0.8);
        dlRect(seg, c, 1.0, 0.0);
    }
}

// ---------------------------------------------------------------- the XY pad authority
// The host parameter is the single source of truth: Y-UP, unmodified in state, data and control
// outputs. The canvas is Y-DOWN. Exactly one conversion exists, here, in both directions. Never
// write `1.0 - value.y` anywhere else, and never publish a flipped copy.
float2 ilPadPoint(float4 r, float2 value) { return float2(lerp(r.x, r.z, value.x), lerp(r.w, r.y, value.y)); }
float2 ilPadValue(float4 r, float2 px)    { return saturate(float2((px.x - r.x) / (r.z - r.x), (r.w - px.y) / (r.w - r.y))); }

void dlPadXY(float4 r, float s, float2 value, bool down)
{
    dlRectEdged(r, IL_WELL, 1.0, IL_RADIUS * s, IL_EDGE, 1.0);
    float4 clip = dlGetClip();
    dlClip(ilInset(r, 1.0));
    [loop] for (int i = 1; i < 8; i++)
    {
        float t = i / 8.0;
        float3 g = (i == 4) ? IL_EDGE * 1.4 : IL_GRID;
        dlVLine(lerp(r.x, r.z, t), r.y, r.w, g);
        dlHLine(lerp(r.y, r.w, t), r.x, r.z, g);
    }
    float2 pt = ilPadPoint(r, value);
    dlVLine(pt.x, r.y, r.w, IL_RULE);
    dlHLine(pt.y, r.x, r.z, IL_RULE);
    g_dlClip = clip;
    dlCircle(pt, 8.0 * s, IL_FIELD, 1.0);
    dlRing(pt, 7.0 * s, 2.0 * s, down ? IL_ACCENT : IL_INK, 1.0);
    dlCircle(pt, 2.0 * s, down ? IL_ACCENT : IL_INK, 1.0);
}

// ---------------------------------------------------------------- furniture
void dlKeycap(float4 r, float s, uint label)
{
    dlRectEdged(r, IL_RAISE, 1.0, 2.5 * s, IL_RULE, 1.0);
    dlLabel(label, ilMid(r).x, ilMid(r).y, IL_T_CAP * s, IL_MID, IL_CENTER);
}

// Caption left (dim), number right (ink, or accent when it is the live reading). Drops the
// caption when it cannot fit beside the number.
void dlValueRow(float4 r, float s, uint caption, float v, int decimals, bool live)
{
    float y = ilMid(r).y;
    float numW = dlNum(v, decimals, r.z, y, IL_T_VALUE * s, live ? IL_ACCENT : IL_INK, IL_RIGHT);
    dlLabelFit(caption, r.x, y, IL_T_BODY * s, IL_DIM, IL_LEFT, (r.z - r.x) - numW - 6.0 * s);
}

// ---------------------------------------------------------------- host viewport.controls
#ifdef SENTINEL_PANEL_TEXT
float4 ilCtlRect(float4 norm, float2 res) { return float4(norm.xy * res, norm.zw * res); }
bool ilCtlHot(uint i)  { return (_ViewportControlState[i].flags & VIEWPORT_CONTROL_HOVER) != 0u; }
bool ilCtlDown(uint i) { return (_ViewportControlState[i].flags & (VIEWPORT_CONTROL_ACTIVE | VIEWPORT_CONTROL_HELD)) != 0u; }
bool ilCtlLit(uint i)  { return (_ViewportControlState[i].flags & VIEWPORT_CONTROL_LIT) != 0u; }
float ilCtlValue(uint i)  { return _ViewportControlState[i].value; }
float ilCtlValue2(uint i) { return _ViewportControlState[i].value2; }

// Whether a pad reads as engaged. A RADIO pad's `value` is the shared parameter normalized, which
// cannot say whether THIS pad is the chosen one - compare the parameter with the pad's manifest
// value in the caller instead.
bool ilPadEngaged(uint i)
{
    ViewportControlState st = _ViewportControlState[i];
    return (st.flags & VIEWPORT_CONTROL_LIT) != 0u || st.state == 2u || (st.mode != 2u && st.value > 0.5);
}

// A show pad in the host's states (empty / loaded / active / selected / fading / held). A Script's
// feedback colour is the pad's own information, shown through ptSampleColour.
void dlShowPad(float4 r, float s, uint i, bool lit)
{
    ViewportControlState st = _ViewportControlState[i];
    bool hot = (st.flags & VIEWPORT_CONTROL_HOVER) != 0u;
    bool held = (st.flags & VIEWPORT_CONTROL_HELD) != 0u;
    float3 role = (st.rgba != 0u) ? ptSampleColour(float3(st.rgba & 255u, (st.rgba >> 8) & 255u, (st.rgba >> 16) & 255u) / 255.0) : IL_ACCENT;
    float3 face = held ? role * 0.85 : (lit ? lerp(IL_RAISE, role, 0.30) : (hot ? IL_RAISE * 1.5 : IL_RAISE));
    float3 edge = (lit || held) ? role : (hot ? IL_RULE * 1.2 : IL_EDGE * 1.4);
    dlRectEdged(r, face, 1.0, IL_RADIUS * s, edge, lit ? 1.5 * s : 1.0);
    if (st.state == 4u) dlRect(float4(r.x, r.w - 3.0 * s, lerp(r.x, r.z, saturate(st.fade)), r.w), role, 1.0, 1.0);
    if (st.state == 3u) dlBorderRect(ilInset(r, -2.0), IL_RADIUS * s + 2.0, IL_ACCENT, 2.0);
    if (lit && !held) dlCircle(float2(r.z - 7.0 * s, r.y + 7.0 * s), 2.5 * s, role, 1.0);
    float2 m = ilMid(r);
    // a pad given a colour keeps showing it while unlit: an underline swatch beneath its label
    if (st.rgba != 0u && !held) dlRect(float4(m.x - 12.0 * s, m.y + 11.0 * s, m.x + 12.0 * s, m.y + 13.0 * s), role, 1.0, 1.0 * s);
    dlPanelLabel(i, m.x, m.y, IL_T_BODY * s, IL_BOLD, held ? IL_FIELD : (lit ? IL_INK : IL_MID), IL_CENTER);
}
#endif

#endif
