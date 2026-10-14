// Phage_Desk / layout - the PHAGE desk, recorded as a draw list (raster.hlsl draws it).
//
// Nothing here decides anything. A click leaves on the `panel` Event output; the Surface Script
// (scripts/show/desk_panel.luau) runs it and answers through the host, which keeps each control's
// state in _ViewportControlState and the readouts' text in _PanelLabels:
//   a look pad is ACTIVE while its look is up and LOADED otherwise (EMPTY: no answer yet),
//   TAP is LIT on the beat, PLAY is ACTIVE while the clock runs, BLACKOUT and STROBE while engaged,
//   and the Script writes the tempo, bar and beat, PLAY / PAUSE and the programmer's status line.
// Rects, banks, tiers and glyphs come from desk_layout.hlsli, which tools/phage_desk.py writes from
// the same table as the manifest and the Surface's desk_layout.luau.
//
// One colour language. Amber is only ever what is live: a lit pad, the beat, a running clock. Red is
// only BLACKOUT. The four banks carry plan_theme's identity hues (FULL LOOKS slate, STATIC sage,
// EFFECTS violet, COLOR sand), and an energy tier is a 1-4 step mark, not a colour.
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"
#include "desk_layout.hlsli"

#define DK_PAD     0u
#define DK_HEADER  2u
#define DK_TIER    4u
#define DF_POSE    1u
#define DF_ALARM   2u
#define DF_FLASH   4u
#define DI_PLAY    1u
#define DI_STOP    2u
#define DI_UP      3u
#define DI_DOWN    4u
#define DI_LEFT    5u
#define DI_RIGHT   6u
#define DI_SYNC    7u
#define DI_BEAT    8u
#define ST_EMPTY   0u
#define ST_ACTIVE  2u
#define NO_PAD     0xFFFFu
#define DESK_K     9u        // most primitives one control draws: a look pad's face, tab, number, lamp, 4 steps, name

groupshared uint gsLiveTier;   // energy tier of the effect that is up (0 none), for the tier legends
groupshared uint gsLivePose;   // 1 while a truss pose is up

float deskScale(float2 res) { return clamp(min(res.x / DESK_SIZE.x, res.y / DESK_SIZE.y), 0.4, 3.0); }

// Identity, not state: which bank a look belongs to.
float3 bankHue(uint bank) { return bank == 1u ? PT_ID_A : (bank == 2u ? PT_ID_C : (bank == 3u ? PT_ID_B : PT_ID_D)); }

bool live(uint i) { return _ViewportControlState[i].state == ST_ACTIVE || ilCtlLit(i); }

// An energy tier: four rising bars, the first `tier` filled. br is the bottom-right corner.
void stepMark(float2 br, float s, uint tier, float3 on, float3 off)
{
    float bw = 2.5 * s, gap = 1.5 * s;
    [loop] for (uint k = 0u; k < 4u; k++)
    {
        float x1 = br.x - (float)(3u - k) * (bw + gap);
        dlRect(float4(x1 - bw, br.y - (3.0 + 2.0 * k) * s, x1, br.y), k < tier ? on : off, 1.0, 0.0);
    }
}

// The readouts arrive as text ("124.0 BPM", "BAR 3 BEAT 2"): read the n-th number back out of a
// control's label so it can be set as a number. -1 while there is none ("---.- BPM").
float panelNumber(uint i, uint which)
{
    uint n = min(_ViewportControlState[i].label, 63u);
    float v = 0.0, place = 0.0, found = -1.0;
    uint group = 0u;
    bool inNum = false;
    [loop] for (uint k = 0u; k <= n; k++)
    {
        uint c = (k < n) ? ilPanelByte(i, k) : 32u;
        if (c >= 48u && c <= 57u)
        {
            float d = (float)(c - 48u);
            if (place > 0.0) { v += d * place; place *= 0.1; } else v = v * 10.0 + d;
            inNum = true;
        }
        else if (c == 46u && inNum && place == 0.0) place = 0.1;
        else if (inNum)
        {
            if (group == which) found = v;
            group++;
            inNum = false; v = 0.0; place = 0.0;
        }
    }
    return found;
}

// dlPanelLabel stops at 48 glyphs; the effects legend is 49 (the host keeps 63 bytes a control).
void panelLabelLong(uint control, float x, float y, float size, uint face, float3 col, uint align)
{
    uint n = min(_ViewportControlState[control].label, 63u);
    float reach = 0.62 * size * (float)n;
    dlTextReq(ilTextBox(x - reach, 2.0 * reach, y, size, face), float4(x, y, size, (float)control), col, DL_REQ_PANEL, n,
              (float)(face | (align << 8)));
}

void chevron(float2 c, float s, uint dir, float3 col)
{
    float2 a = dir == DI_UP ? float2(0.0, -1.0) : (dir == DI_DOWN ? float2(0.0, 1.0) : (dir == DI_LEFT ? float2(-1.0, 0.0) : float2(1.0, 0.0)));
    float2 n = float2(-a.y, a.x);
    float2 tip = c + a * 5.0 * s, base = c - a * 5.0 * s;
    dlLine(base + n * 10.0 * s, tip, 2.5 * s, col, 1.0);
    dlLine(tip, base - n * 10.0 * s, 2.5 * s, col, 1.0);
}

void glyph(uint icon, float2 c, float s, bool on, float3 ink)
{
    if (icon == DI_PLAY && on)                     // running: the pad offers PAUSE
    {
        dlRect(float4(c.x - 6.0 * s, c.y - 7.0 * s, c.x - 2.0 * s, c.y + 7.0 * s), ink, 1.0, 1.0 * s);
        dlRect(float4(c.x + 2.0 * s, c.y - 7.0 * s, c.x + 6.0 * s, c.y + 7.0 * s), ink, 1.0, 1.0 * s);
    }
    else if (icon == DI_PLAY) dlTri(float2(c.x + 7.0 * s, c.y), 7.5 * s, 13.0 * s, 3u, ink, 1.0);
    else if (icon == DI_STOP) dlRect(float4(c - 6.5 * s, c + 6.5 * s), ink, 1.0, 1.5 * s);
    else if (icon == DI_SYNC) { dlRing(c, 6.5 * s, 1.75 * s, ink, 1.0); dlCircle(c, 2.0 * s, ink, 1.0); }
    else if (icon == DI_BEAT) dlCircle(c, 6.0 * s, on ? IL_ACCENT : IL_EDGE * 1.7, 1.0);    // the beat lamp
    else chevron(c, s, icon, ink);
}

void pad(uint i, float4 r, float s)
{
    ViewportControlState st = _ViewportControlState[i];
    uint bank = DESK_BANK[i], flags = DESK_FLAGS[i], icon = DESK_ICON[i];
    bool hot = (st.flags & VIEWPORT_CONTROL_HOVER) != 0u;
    bool down = (st.flags & (VIEWPORT_CONTROL_HELD | VIEWPORT_CONTROL_ACTIVE)) != 0u;
    bool alarm = (flags & DF_ALARM) != 0u, flash = (flags & DF_FLASH) != 0u, hold = alarm || flash;
    bool lamp = icon == DI_BEAT;                   // TAP shows the beat on its lamp, not its face
    bool on = !lamp && live(i);
    bool solid = on && hold;                       // an engaged hold fills its pad: red BLACKOUT, white STROBE
    float3 hue = alarm ? IL_ALARM : (flash ? IL_INK : IL_ACCENT);

    float3 face = down ? IL_RAISE * 2.1 : (hot ? IL_RAISE * 1.45 : IL_RAISE);
    face = solid ? hue * 0.88 : (on ? lerp(face, IL_ACCENT, 0.24) : face);
    float3 edge = on ? hue : (alarm ? lerp(IL_EDGE, IL_ALARM, 0.5) : ((hot || down) ? IL_RULE : IL_EDGE * 1.35));
    dlRectEdged(r, face, 1.0, IL_RADIUS * s, edge, on ? 1.5 * s : 1.0);

    float2 m = ilMid(r);
    float3 ink = solid ? IL_FIELD : (on ? IL_INK : (hot ? lerp(IL_MID, IL_INK, 0.5) : IL_MID));
    if (alarm && !on) ink = lerp(ink, IL_ALARM, 0.55);
    if (bank != 0u)
    {
        // a look: its bank's tab, slot number, energy tier or POSE, and name
        if (st.state == ST_EMPTY) ink = IL_DIM;                       // the Surface has not answered yet
        dlRect(float4(r.x + 5.0 * s, r.y + 3.0 * s, r.z - 5.0 * s, r.y + 5.5 * s), on ? IL_ACCENT : bankHue(bank), 1.0, 1.0 * s);
        dlInt((int)DESK_SLOT[i], 1, r.x + 8.0 * s, r.y + 16.0 * s, 10.0 * s, on ? IL_INK : IL_DIM, IL_LEFT);
        if (on) dlCircle(float2(r.z - 10.0 * s, r.y + 16.0 * s), 2.75 * s, IL_ACCENT, 1.0);
        if (DESK_TIER[i] != 0u) stepMark(float2(r.z - 8.0 * s, r.w - 8.0 * s), s, DESK_TIER[i], on ? IL_INK : IL_MID, IL_EDGE * 1.9);
        if ((flags & DF_POSE) != 0u) dlLabel(LB_POSE, r.z - 8.0 * s, r.w - 11.0 * s, 8.5 * s, on ? IL_INK : IL_DIM, IL_RIGHT);
        dlPanelLabel(i, m.x, m.y + 3.0 * s, 13.0 * s, IL_BOLD, ink, IL_CENTER);
    }
    else if (icon >= DI_UP && icon <= DI_RIGHT) glyph(icon, m, s, on, ink);    // the camera arrows' glyph is their label
    else if (icon != 0u)
    {
        glyph(icon, float2(m.x, m.y - 9.0 * s), s, lamp ? ilCtlLit(i) : on, ink);
        dlPanelLabel(i, m.x, m.y + 17.0 * s, 11.5 * s, IL_BOLD, ink, IL_CENTER);
    }
    else
    {
        if (hold) dlLabel(LB_HOLD, r.x + 9.0 * s, r.y + 13.0 * s, 9.0 * s, solid ? IL_FIELD : IL_DIM, IL_LEFT);
        dlPanelLabel(i, m.x, m.y + (hold ? 4.0 : 0.0) * s, (hold ? 15.0 : 13.0) * s, IL_BOLD, ink, IL_CENTER);
    }
}

void header(uint i, float4 r, float s)
{
    float y = ilMid(r).y, x = r.x;
    if (DESK_BANK[i] != 0u)
    {
        dlRect(float4(x, y - 4.0 * s, x + 8.0 * s, y + 4.0 * s), bankHue(DESK_BANK[i]), 1.0, 1.5 * s);
        x += 15.0 * s;
    }
    dlPanelLabel(i, x, y, 12.0 * s, IL_BOLD, IL_MID, IL_LEFT);
    dlHLine(r.w, r.x, r.z, IL_EDGE);
}

// A tier legend reads as live (ink) while an effect of its tier is up; the pose legend while a pose is.
void tierChip(uint i, float4 r, float s, uint liveTier, bool livePose)
{
    uint t = DESK_TIER[i];
    bool lit = (t != 0u) ? (t == liveTier) : livePose;
    dlRect(r, IL_WELL, 1.0, IL_RADIUS * s);
    float y = ilMid(r).y, x = r.x + 9.0 * s;
    if (t != 0u)
    {
        stepMark(float2(x + 14.5 * s, y + 4.5 * s), s, t, lit ? IL_INK : IL_MID, IL_EDGE * 1.9);
        x += 22.0 * s;
    }
    dlPanelLabel(i, x, y, 10.5 * s, IL_BOLD, lit ? IL_INK : IL_DIM, IL_LEFT);
}

void tempoReadout(float4 r, float s)
{
    dlRect(r, IL_WELL, 1.0, IL_RADIUS * s);
    dlLabel(LB_TEMPO, r.x + 10.0 * s, r.y + 13.0 * s, 9.0 * s, IL_DIM, IL_LEFT);
    float bpm = panelNumber(UI_BPM, 0u), vy = lerp(r.y, r.w, 0.62);
    if (bpm >= 0.0)
    {
        float w = dlNum(bpm, 1, r.x + 10.0 * s, vy, 30.0 * s, IL_INK, IL_LEFT);
        dlLabel(LB_BPM, r.x + 18.0 * s + w, vy + 7.0 * s, 9.0 * s, IL_DIM, IL_LEFT);
    }
    else dlPanelLabel(UI_BPM, r.x + 10.0 * s, vy, 22.0 * s, IL_MONO, IL_DIM, IL_LEFT);
}

// Bar and beat, read back from the Script's "BAR n BEAT m"; the beat takes the accent on the beat.
void beatReadout(float4 r, float s)
{
    dlRect(r, IL_WELL, 1.0, IL_RADIUS * s);
    float half = lerp(r.x, r.z, 0.5), vy = lerp(r.y, r.w, 0.62);
    float bar = panelNumber(UI_BEAT, 0u), beat = panelNumber(UI_BEAT, 1u);
    dlVLine(half, r.y + 10.0 * s, r.w - 10.0 * s, IL_EDGE);
    dlLabel(LB_BAR, r.x + 10.0 * s, r.y + 13.0 * s, 9.0 * s, IL_DIM, IL_LEFT);
    dlLabel(LB_BEAT, half + 10.0 * s, r.y + 13.0 * s, 9.0 * s, IL_DIM, IL_LEFT);
    if (bar >= 0.0) dlInt((int)bar, 1, r.x + 10.0 * s, vy, 30.0 * s, IL_INK, IL_LEFT);
    else dlLabel(LB_DASH, r.x + 10.0 * s, vy, 30.0 * s, IL_DIM, IL_LEFT);
    if (beat >= 0.0) dlInt((int)beat, 1, half + 10.0 * s, vy, 30.0 * s, ilCtlLit(UI_TAP) ? IL_ACCENT : IL_INK, IL_LEFT);
    else dlLabel(LB_DASH, half + 10.0 * s, vy, 30.0 * s, IL_DIM, IL_LEFT);
}

// FULL LOOK = STATIC + TRUSS POSE + EFFECTS + COLOR, filled in with what is up in each bank.
void equation(float4 r, float s, uint lvFull, uint lvStatic, uint lvPose, uint lvFx, uint lvColor)
{
    float op = 24.0 * s;
    float cw = (r.z - r.x - 4.0 * op) / 5.0;
    [loop] for (uint t = 0u; t < 5u; t++)
    {
        uint idx = t == 0u ? lvFull : (t == 1u ? lvStatic : (t == 2u ? lvPose : (t == 3u ? lvFx : lvColor)));
        uint bank = t == 0u ? 1u : (t <= 2u ? 2u : t);
        float x0 = r.x + (float)t * (cw + op);
        float4 c = float4(x0, r.y, x0 + cw, r.w);
        dlRect(c, IL_WELL, 1.0, IL_RADIUS * s);
        float cy = c.y + 13.0 * s, ny = lerp(c.y, c.w, 0.66);
        dlRect(float4(c.x + 10.0 * s, cy - 3.5 * s, c.x + 17.0 * s, cy + 3.5 * s), bankHue(bank), 1.0, 1.0 * s);
        dlLabel(LB_C_FULL + t, c.x + 23.0 * s, cy, 9.0 * s, IL_DIM, IL_LEFT);
        if (idx != NO_PAD)
        {
            dlCircle(float2(c.x + 13.5 * s, ny), 2.75 * s, IL_ACCENT, 1.0);
            dlPanelLabel(idx, c.x + 23.0 * s, ny, 16.0 * s, IL_BOLD, IL_INK, IL_LEFT);
        }
        else dlLabel(LB_NONE, c.x + 23.0 * s, ny, 13.0 * s, IL_DIM, IL_LEFT);
        if (t < 4u) dlLabel(t == 0u ? LB_EQ : LB_PLUS, c.z + 0.5 * op, ilMid(c).y, 18.0 * s, IL_DIM, IL_CENTER);
    }
}

// Thread 0 records the plates and everything that is not a control, reserves one run of slots per
// control, and publishes what the controls need to know; every thread then draws the controls (main).
void layout()
{
    float2 res = _Resolution.xy;
    float s = deskScale(res);
    dlBegin(res);

    // what is up in each bank, and whether the Surface is answering at all
    uint lvFull = NO_PAD, lvStatic = NO_PAD, lvPose = NO_PAD, lvFx = NO_PAD, lvColor = NO_PAD;
    bool heard = false;
    [loop] for (uint k = 0u; k < DESK_COUNT; k++)
    {
        uint b = DESK_BANK[k];
        if (DESK_KIND[k] != DK_PAD || b == 0u) continue;
        heard = heard || _ViewportControlState[k].state != ST_EMPTY;
        if (!live(k)) continue;
        bool pose = (DESK_FLAGS[k] & DF_POSE) != 0u;
        if (b == 1u && lvFull == NO_PAD) lvFull = k;
        if (b == 2u && !pose && lvStatic == NO_PAD) lvStatic = k;
        if (b == 2u && pose && lvPose == NO_PAD) lvPose = k;
        if (b == 3u && lvFx == NO_PAD) lvFx = k;
        if (b == 4u && lvColor == NO_PAD) lvColor = k;
    }
    uint liveTier = (lvFx != NO_PAD) ? DESK_TIER[lvFx] : 0u;

    [loop] for (uint p = 0u; p < DESK_PANES; p++)
        dlRect(ilCtlRect(DESK_PANE[p], res), IL_PANEL, 1.0, 1.5 * IL_RADIUS * s);

    float4 tr = ilCtlRect(DESK_TITLE, res);
    dlLabel(LB_TITLE, tr.x + 2.0 * s, lerp(tr.y, tr.w, 0.38), 22.0 * s, IL_INK, IL_LEFT);
    dlLabel(LB_SUBTITLE, tr.x + 2.0 * s, lerp(tr.y, tr.w, 0.74), 12.0 * s, IL_DIM, IL_LEFT);

    // the controls themselves draw in parallel, into these slots (main)
    gsLiveTier = liveTier;
    gsLivePose = (lvPose != NO_PAD) ? 1u : 0u;
    dlBatch(DESK_COUNT * DESK_K, 0u);

    tempoReadout(ilCtlRect(UI_RECT_BPM, res), s);
    beatReadout(ilCtlRect(UI_RECT_BEAT, res), s);

    float4 orb = ilCtlRect(DESK_ORBIT, res), zm = ilCtlRect(DESK_ZOOM, res);
    dlLabel(LB_ORBIT, ilMid(orb).x, ilMid(orb).y, 9.0 * s, IL_DIM, IL_CENTER);
    dlLabel(LB_ZOOM, ilMid(zm).x, ilMid(zm).y, 9.0 * s, IL_DIM, IL_CENTER);

    float4 lh = ilCtlRect(DESK_LIVE_HEAD, res);
    dlLabel(LB_LIVE, lh.x, ilMid(lh).y, 12.0 * s, IL_MID, IL_LEFT);
    dlHLine(lh.w, lh.x, lh.z, IL_EDGE);
    equation(ilCtlRect(UI_RECT_LEGEND_FULL, res), s, lvFull, lvStatic, lvPose, lvFx, lvColor);
    float4 fx = ilCtlRect(UI_RECT_LEGEND_FX, res);
    panelLabelLong(UI_LEGEND_FX, fx.x + 2.0 * s, ilMid(fx).y, 10.5 * s, IL_SANS, IL_DIM, IL_LEFT);

    float4 sr = ilCtlRect(UI_RECT_STATUS, res);
    dlPanelLabel(UI_STATUS, sr.x + 2.0 * s, ilMid(sr).y, 17.0 * s, IL_SANS, IL_INK, IL_LEFT);
    if (!heard) dlLabel(LB_QUIET, sr.z - 2.0 * s, ilMid(sr).y, IL_T_CAP * s, IL_MID, IL_RIGHT);

    dlFinish();
}

// One control, on any layout thread: it owns DESK_K slots of the batch, in manifest order.
void control(uint i, float s)
{
    float4 r = ilCtlRect(DESK_RECT[i], _Resolution.xy);
    uint kind = DESK_KIND[i];
    if (kind == DK_PAD) pad(i, r, s);
    else if (kind == DK_HEADER) header(i, r, s);
    else if (kind == DK_TIER) tierChip(i, r, s, gsLiveTier, gsLivePose != 0u);
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    if (gi == 0u) layout();
    dlSync();
    ILBatch b = dlGetBatch(0u);
    float s = deskScale(_Resolution.xy);
    [loop] for (uint i = gi; i < DESK_COUNT; i += IL_LAYOUT_THREADS)
    {
        dlAtSpan(b, i, DESK_K);
        control(i, s);
    }
    dlEnd(gi);
}
