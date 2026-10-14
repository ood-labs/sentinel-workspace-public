// SS_Desk / layout - the SIMPLE STAGE desk, recorded as a draw list (raster.hlsl draws it).
//
// Nothing here decides anything. A click or a fader move leaves on the `panel` Event output; the Surface Script
// (scripts/show/desk_panel.luau) runs it and answers through the host, which keeps each control's state in
// _ViewportControlState and the readouts' text in _PanelLabels:
//   a look pad is ACTIVE while its look is up and LOADED otherwise (EMPTY: no answer yet), SELECTED while STORE is
//   armed (it offers itself as the target);
//   a fixture pad is ACTIVE while the whole fixture is selected, SELECTED while some of its layers are, EMPTY when the
//   rig has no fixture there, and its colour is the colour its programmed palette slot plays;
//   a group or layer pad is ACTIVE while the selection holds all of it; a tab while it is the one in use, LIT (the
//   sequence tabs) while a sequence of its kind is up;
//   a fader's value is where the selection sits, EMPTY when the selection has nothing it can program;
//   TAP is LIT on the beat, PLAY is ACTIVE while the clock runs, BLACKOUT, STROBE and STORE while engaged,
//   and the Script writes the tempo, bar and beat, the fader names and values and the programmer's status line.
// Rects, banks, tiers, fixture types and glyphs come from desk_layout.hlsli, which tools/ss_desk.py writes from the
// same table as the manifest and the Surface's desk_layout.luau.
//
// One colour language. Amber is what is live or picked: a lit look, the selection, the beat, a running clock, an
// armed STORE. Red is only BLACKOUT. The look banks carry plan_theme's identity hues (FULL LOOKS and SEQUENCES slate,
// STATIC sage, EFFECTS violet, COLOR sand), an energy tier is a 1-4 step mark, and a fixture's swatch is its own
// colour, through ptSampleColour.
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"
#include "desk_layout.hlsli"

#define DK_PAD     0u
#define DK_HEADER  2u
#define DK_TIER    4u
#define DK_FADER   5u
#define DK_FIXTURE 6u
#define DK_GROUP   7u
#define DK_TAB     8u
#define DK_VALUE   9u
#define DF_ALARM   2u
#define DF_FLASH   4u
#define DF_ARM     8u
#define DF_TOGGLE  16u
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
#define ST_SEL     3u
#define NO_PAD     0xFFFFu

groupshared uint gsLiveTier;   // energy tier of the effect that is up (0 none), for the tier legends

float deskScale(float2 res) { return clamp(min(res.x / DESK_SIZE.x, res.y / DESK_SIZE.y), 0.4, 3.0); }

// Identity, not state: which bank a look belongs to. The sequences are whole-rig looks, like FULL LOOKS.
float3 bankHue(uint bank) { return (bank == 1u || bank == 5u) ? PT_ID_A : (bank == 2u ? PT_ID_C : (bank == 3u ? PT_ID_B : PT_ID_D)); }

bool live(uint i) { return _ViewportControlState[i].state == ST_ACTIVE || ilCtlLit(i); }

float3 feedbackColour(uint i)
{
    uint c = _ViewportControlState[i].rgba;
    return float3(c & 255u, (c >> 8) & 255u, (c >> 16) & 255u) / 255.0;
}

// Control i draws into its own run of the batch: [DESK_SPAN[i], DESK_SPAN[i] + DESK_K[i]) (il_draw dlAtSpan with a
// per-kind budget instead of one size for all).
void deskSpan(ILBatch b, uint i)
{
    uint s0 = b.first + min(DESK_SPAN[i], b.count);
    uint s1 = b.first + min(DESK_SPAN[i] + DESK_K[i], b.count);
    [loop] for (uint sl = s0; sl < s1; sl++)
    {
        DL[1u + 4u * sl] = float4(0.0, 0.0, 0.0, 0.0);
        DL[1u + 4u * sl + 3u] = float4(0.0, 0.0, 0.0, 0.0);
    }
    bool empty = s1 <= s0;
    g_dlAt = empty ? IL_DL_MAXCMD - 1u : s0;
    g_dlAtEnd = empty ? IL_DL_MAXCMD : s1;
    g_dlClip = b.clip;
}

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

// The readouts arrive as text ("124.0 BPM", "BAR 3 BEAT 2"): read the n-th number back out of a control's label so it
// can be set as a number. -1 while there is none ("---.- BPM").
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

// dlPanelLabel stops at 48 glyphs; the status lines run to the host's 63 bytes.
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
    float2 tip = c + a * 4.0 * s, base = c - a * 4.0 * s;
    dlLine(base + n * 8.0 * s, tip, 2.5 * s, col, 1.0);
    dlLine(tip, base - n * 8.0 * s, 2.5 * s, col, 1.0);
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

// Look pads, transport, camera and the programmer's actions.
void pad(uint i, float4 r, float s)
{
    ViewportControlState st = _ViewportControlState[i];
    uint bank = DESK_BANK[i], flags = DESK_FLAGS[i], icon = DESK_ICON[i];
    bool hot = (st.flags & VIEWPORT_CONTROL_HOVER) != 0u;
    bool down = (st.flags & (VIEWPORT_CONTROL_HELD | VIEWPORT_CONTROL_ACTIVE)) != 0u;
    bool alarm = (flags & DF_ALARM) != 0u, flash = (flags & DF_FLASH) != 0u, arm = (flags & DF_ARM) != 0u;
    bool toggle = (flags & DF_TOGGLE) != 0u;
    bool hold = (alarm || flash) && bank == 0u;
    bool lamp = icon == DI_BEAT;                   // TAP shows the beat on its lamp, not its face
    bool on = !lamp && live(i);
    bool solid = on && (hold || arm || toggle);    // an engaged hold fills its pad: red BLACKOUT, white STROBE and HIGHLIGHT, amber STORE
    bool target = bank != 0u && st.state == ST_SEL; // STORE is armed: every look pad offers itself
    float3 hue = alarm ? IL_ALARM : ((flash || toggle) ? IL_INK : IL_ACCENT);

    float3 face = down ? IL_RAISE * 2.1 : (hot ? IL_RAISE * 1.45 : IL_RAISE);
    face = solid ? hue * 0.88 : (on ? lerp(face, alarm ? IL_ALARM : IL_ACCENT, 0.24) : face);
    float3 edge = on ? hue : (target ? IL_ACCENT * 0.8 : (alarm ? lerp(IL_EDGE, IL_ALARM, 0.5) : ((hot || down) ? IL_RULE : IL_EDGE * 1.35)));
    dlRectEdged(r, face, 1.0, IL_RADIUS * s, edge, (on || target) ? 1.5 * s : 1.0);

    float2 m = ilMid(r);
    float3 ink = solid ? IL_FIELD : (on ? IL_INK : (hot ? lerp(IL_MID, IL_INK, 0.5) : IL_MID));
    if (alarm && !on) ink = lerp(ink, IL_ALARM, 0.55);
    if (bank != 0u)
    {
        // a look: its bank's tab, slot number, energy tier and name
        if (st.state == ST_EMPTY) ink = IL_DIM;                       // the Surface has not answered yet
        float3 tab = on ? (alarm ? IL_ALARM : IL_ACCENT) : (alarm ? lerp(bankHue(bank), IL_ALARM, 0.7) : bankHue(bank));
        dlRect(float4(r.x + 5.0 * s, r.y + 3.0 * s, r.z - 5.0 * s, r.y + 5.5 * s), tab, 1.0, 1.0 * s);
        dlInt((int)DESK_SLOT[i], 1, r.x + 7.0 * s, r.y + 14.0 * s, 9.5 * s, on ? IL_INK : IL_DIM, IL_LEFT);
        if (on) dlCircle(float2(r.z - 9.0 * s, r.y + 14.0 * s), 2.75 * s, alarm ? IL_ALARM : IL_ACCENT, 1.0);
        if (DESK_SUB[i] != 0u) stepMark(float2(r.z - 7.0 * s, r.w - 6.0 * s), s, DESK_SUB[i], on ? IL_INK : IL_MID, IL_EDGE * 1.9);
        dlPanelLabel(i, m.x, m.y + 4.0 * s, 12.0 * s, IL_BOLD, ink, IL_CENTER);
    }
    else if (icon >= DI_UP && icon <= DI_RIGHT) glyph(icon, m, s, on, ink);    // the camera arrows' glyph is their label
    else if (icon != 0u)
    {
        glyph(icon, float2(m.x, m.y - 8.0 * s), s, lamp ? ilCtlLit(i) : on, ink);
        dlPanelLabel(i, m.x, m.y + 15.0 * s, 11.0 * s, IL_BOLD, ink, IL_CENTER);
    }
    else if (arm)
    {
        dlPanelLabel(i, m.x, m.y + (on ? -4.0 : 0.0) * s, 12.0 * s, IL_BOLD, ink, IL_CENTER);
        if (on) dlLabel(LB_ARMED, m.x, m.y + 8.0 * s, 8.0 * s, IL_FIELD, IL_CENTER);
    }
    else
    {
        if (hold) dlLabel(LB_HOLD, r.x + 9.0 * s, r.y + 13.0 * s, 9.0 * s, solid ? IL_FIELD : IL_DIM, IL_LEFT);
        float size = hold ? 15.0 : ((r.w - r.y) < 40.0 * s ? 11.5 : 13.0);
        dlPanelLabel(i, m.x, m.y + (hold ? 4.0 : 0.0) * s, size * s, IL_BOLD, ink, IL_CENTER);
    }
}

// A fixture on the map: its short name, its type's mark and its programmed colour; amber when it is picked.
void fixturePad(uint i, float4 r, float s)
{
    ViewportControlState st = _ViewportControlState[i];
    bool hot = (st.flags & VIEWPORT_CONTROL_HOVER) != 0u;
    bool down = (st.flags & (VIEWPORT_CONTROL_HELD | VIEWPORT_CONTROL_ACTIVE)) != 0u;
    bool present = st.state != ST_EMPTY;
    bool all = st.state == ST_ACTIVE, some = st.state == ST_SEL;
    uint type = DESK_SUB[i];
    float3 face = all ? lerp(IL_RAISE, IL_ACCENT, 0.30) : (down ? IL_RAISE * 2.1 : (hot ? IL_RAISE * 1.5 : IL_RAISE));
    float3 edge = all ? IL_ACCENT : (some ? IL_ACCENT * 0.75 : (hot ? IL_RULE : IL_EDGE * 1.4));
    if (!present) { face = IL_PANEL; edge = IL_EDGE; }
    dlRectEdged(r, face, 1.0, IL_RADIUS * s, edge, (all || some) ? 2.0 * s : 1.0);

    // the colour it plays: a band along the bottom (a wall run's along its edge, as it runs up the wall)
    float3 col = ptSampleColour(feedbackColour(i));
    if (present && st.rgba != 0u)
    {
        if (type == 2u) dlRect(float4(r.x + 3.0 * s, r.y + 4.0 * s, r.x + 6.0 * s, r.w - 4.0 * s), col, 1.0, 1.0 * s);
        else dlRect(float4(r.x + 4.0 * s, r.w - 5.0 * s, r.z - 4.0 * s, r.w - 2.5 * s), col, 1.0, 1.0 * s);
    }
    float2 m = ilMid(r);
    float3 ink = !present ? IL_DIM * 0.7 : (all ? IL_INK : (some ? lerp(IL_MID, IL_INK, 0.6) : IL_MID));
    // a head's mark: the beam's ring
    if (type == 0u) dlRing(float2(r.x + 8.0 * s, r.y + 8.0 * s), 3.0 * s, 1.25 * s, all ? IL_INK : IL_DIM, 1.0);
    float size = type == 1u ? 10.5 : 12.0;
    dlPanelLabel(i, m.x + (type == 2u ? 2.0 * s : 0.0), m.y - (type == 1u ? 0.5 : 1.0) * s, size * s, IL_BOLD, ink, IL_CENTER);
}

// A group or a layer filter: amber while the selection holds all of it.
void groupPad(uint i, float4 r, float s)
{
    ViewportControlState st = _ViewportControlState[i];
    bool hot = (st.flags & VIEWPORT_CONTROL_HOVER) != 0u;
    bool down = (st.flags & (VIEWPORT_CONTROL_HELD | VIEWPORT_CONTROL_ACTIVE)) != 0u;
    bool on = st.state == ST_ACTIVE;
    bool layer = DESK_SUB[i] != 0u;
    float3 face = down ? IL_RAISE * 2.1 : (hot ? IL_RAISE * 1.5 : (layer ? IL_WELL * 1.6 : IL_RAISE));
    if (on) face = lerp(face, IL_ACCENT, 0.18);
    dlRectEdged(r, face, 1.0, IL_RADIUS * s, on ? IL_ACCENT : (hot ? IL_RULE : IL_EDGE * 1.35), on ? 1.5 * s : 1.0);
    float3 ink = st.state == ST_EMPTY ? IL_DIM * 0.8 : (on ? IL_INK : (hot ? lerp(IL_MID, IL_INK, 0.5) : IL_MID));
    float2 m = ilMid(r);
    dlPanelLabel(i, m.x, m.y, (layer ? 10.5 : 11.5) * s, IL_BOLD, ink, IL_CENTER);
}

// A tab: the attribute bank the faders program, or which fixture types the SEQUENCES pads play. The one in use reads
// as a raised face with an underline; a sequence tab with a look of its kind up carries the live dot.
void tab(uint i, float4 r, float s)
{
    ViewportControlState st = _ViewportControlState[i];
    bool hot = (st.flags & VIEWPORT_CONTROL_HOVER) != 0u;
    bool on = st.state == ST_ACTIVE;
    bool dead = st.state == ST_EMPTY;
    uint bank = DESK_BANK[i];
    float3 face = on ? IL_RAISE * 2.2 : (hot ? IL_RAISE * 1.5 : IL_WELL);
    dlRectEdged(r, face, 1.0, IL_RADIUS * s, on ? IL_RULE : IL_EDGE, 1.0);
    if (on) dlRect(float4(r.x + 4.0 * s, r.w - 3.0 * s, r.z - 4.0 * s, r.w - 1.0 * s), bank != 0u ? bankHue(bank) : IL_INK, 1.0, 0.0);
    if (ilCtlLit(i)) dlCircle(float2(r.z - 7.0 * s, r.y + 7.0 * s), 2.5 * s, IL_ACCENT, 1.0);
    float2 m = ilMid(r);
    dlPanelLabel(i, m.x, m.y - 0.5 * s, 10.5 * s, IL_BOLD, on ? IL_INK : (dead ? IL_DIM * 0.7 : IL_MID), IL_CENTER);
}

// A fader: the host maps its whole rect, bottom 0 to top 1; the cap sits where the selection is.
void fader(uint i, float4 r, float s)
{
    ViewportControlState st = _ViewportControlState[i];
    bool hot = (st.flags & VIEWPORT_CONTROL_HOVER) != 0u;
    bool down = (st.flags & (VIEWPORT_CONTROL_HELD | VIEWPORT_CONTROL_ACTIVE)) != 0u;
    bool dead = st.state == ST_EMPTY;
    float v = saturate(st.value);
    float cx = ilMid(r).x, tw = ilSnap(5.0 * s), ch = 7.0 * s;
    dlRect(r, IL_WELL, 1.0, IL_RADIUS * s);
    float4 track = float4(cx - tw * 0.5, r.y + ch, cx + tw * 0.5, r.w - ch);
    dlRect(track, IL_FIELD, 1.0, tw * 0.5);
    float y = lerp(track.w, track.y, v);
    if (!dead)
    {
        dlRect(float4(track.x, y, track.z, track.w), (hot || down) ? IL_MID : IL_MID * 0.75, 1.0, tw * 0.5);
        dlHLine(lerp(track.w, track.y, 0.5), r.x + 4.0 * s, r.x + 10.0 * s, IL_RULE);
        float cw = min((r.z - r.x) * 0.5 - 6.0 * s, 20.0 * s);
        float4 cap = float4(cx - cw, y - ch, cx + cw, y + ch);
        dlRectEdged(cap, hot ? IL_RAISE * 3.0 : IL_RAISE * 2.4, 1.0, 2.5 * s, down ? IL_ACCENT : IL_RULE, 1.0);
        dlRect(float4(cap.x + 4.0 * s, y - 0.75, cap.z - 4.0 * s, y + 0.75), down ? IL_ACCENT : IL_INK, 1.0, 0.0);
    }
}

// A fader's caption above it (sub 1) or the selection's value below it.
void faderText(uint i, float4 r, float s)
{
    bool dead = _ViewportControlState[UI_FADER_1 + DESK_SLOT[i] - 1u].state == ST_EMPTY;
    float2 m = ilMid(r);
    if (DESK_SUB[i] != 0u) dlPanelLabel(i, m.x, m.y, 10.0 * s, IL_BOLD, dead ? IL_DIM * 0.8 : IL_MID, IL_CENTER);
    else
    {
        dlRect(r, IL_WELL, 1.0, IL_RADIUS * s);
        dlPanelLabel(i, m.x, m.y, 10.5 * s, IL_MONO, dead ? IL_DIM * 0.8 : IL_INK, IL_CENTER);
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

// A tier legend reads as live (ink) while an effect of its tier is up.
void tierChip(uint i, float4 r, float s, uint liveTier)
{
    uint t = DESK_SUB[i];
    bool lit = t == liveTier;
    dlRect(r, IL_WELL, 1.0, IL_RADIUS * s);
    float y = ilMid(r).y, x = r.x + 9.0 * s;
    stepMark(float2(x + 14.5 * s, y + 4.5 * s), s, t, lit ? IL_INK : IL_MID, IL_EDGE * 1.9);
    dlPanelLabel(i, x + 22.0 * s, y, 10.5 * s, IL_BOLD, lit ? IL_INK : IL_DIM, IL_LEFT);
}

void tempoReadout(float4 r, float s)
{
    dlRect(r, IL_WELL, 1.0, IL_RADIUS * s);
    dlLabel(LB_TEMPO, r.x + 10.0 * s, r.y + 13.0 * s, 9.0 * s, IL_DIM, IL_LEFT);
    float bpm = panelNumber(UI_BPM, 0u), vy = lerp(r.y, r.w, 0.62);
    if (bpm >= 0.0)
    {
        float w = dlNum(bpm, 1, r.x + 10.0 * s, vy, 28.0 * s, IL_INK, IL_LEFT);
        dlLabel(LB_BPM, r.x + 18.0 * s + w, vy + 7.0 * s, 9.0 * s, IL_DIM, IL_LEFT);
    }
    else dlPanelLabel(UI_BPM, r.x + 10.0 * s, vy, 20.0 * s, IL_MONO, IL_DIM, IL_LEFT);
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
    if (bar >= 0.0) dlInt((int)bar, 1, r.x + 10.0 * s, vy, 28.0 * s, IL_INK, IL_LEFT);
    else dlLabel(LB_DASH, r.x + 10.0 * s, vy, 28.0 * s, IL_DIM, IL_LEFT);
    if (beat >= 0.0) dlInt((int)beat, 1, half + 10.0 * s, vy, 28.0 * s, ilCtlLit(UI_TAP) ? IL_ACCENT : IL_INK, IL_LEFT);
    else dlLabel(LB_DASH, half + 10.0 * s, vy, 28.0 * s, IL_DIM, IL_LEFT);
}

// One cell of the live line: its bank's mark, caption, and the look that is up (a pad's name) or "none".
void liveCell(float4 c, float s, uint bank, uint caption, uint idx, bool any)
{
    dlRect(c, IL_WELL, 1.0, IL_RADIUS * s);
    float cy = c.y + 12.0 * s, ny = lerp(c.y, c.w, 0.68);
    dlRect(float4(c.x + 10.0 * s, cy - 3.5 * s, c.x + 17.0 * s, cy + 3.5 * s), bankHue(bank), 1.0, 1.0 * s);
    dlLabel(caption, c.x + 23.0 * s, cy, 9.0 * s, IL_DIM, IL_LEFT);
    if (any)
    {
        dlCircle(float2(c.x + 13.5 * s, ny), 2.75 * s, IL_ACCENT, 1.0);
        dlPanelLabel(idx, c.x + 23.0 * s, ny, 14.0 * s, IL_BOLD, IL_INK, IL_LEFT);
    }
    else dlLabel(LB_NONE, c.x + 23.0 * s, ny, 12.0 * s, IL_DIM, IL_LEFT);
}

// FULL LOOK = STATIC + EFFECTS + COLOR, filled in with what is up in each bank.
void equation(float4 r, float s, uint lvFull, uint lvStatic, uint lvFx, uint lvColor)
{
    float op = 20.0 * s;
    float cw = (r.z - r.x - 3.0 * op) / 4.0;
    [loop] for (uint t = 0u; t < 4u; t++)
    {
        uint idx = t == 0u ? lvFull : (t == 1u ? lvStatic : (t == 2u ? lvFx : lvColor));
        float x0 = r.x + (float)t * (cw + op);
        float4 c = float4(x0, r.y, x0 + cw, r.w);
        liveCell(c, s, t + 1u, LB_C_FULL + t, idx, idx != NO_PAD);
        if (t < 3u) dlLabel(t == 0u ? LB_EQ : LB_PLUS, c.z + 0.5 * op, ilMid(c).y, 16.0 * s, IL_DIM, IL_CENTER);
    }
}

// The fixture map's ground: the deck, the booth and the three truss lines the rows hang from, the audience below.
void fixtureMap(float2 res, float s)
{
    float4 m = ilCtlRect(DESK_MAP, res), d = ilCtlRect(DESK_DECK, res), b = ilCtlRect(DESK_BOOTH, res);
    dlRect(m, IL_WELL, 1.0, IL_RADIUS * s);
    dlRectEdged(d, IL_PANEL * 1.25, 1.0, 1.0 * s, IL_EDGE, 1.0);
    dlRectEdged(b, IL_RAISE, 1.0, 1.0 * s, IL_EDGE * 1.4, 1.0);
    dlLabel(LB_DECK, ilMid(b).x, ilMid(b).y, 8.0 * s, IL_DIM, IL_CENTER);
    float w = 1.5 * s, x0 = DESK_TRUSS_X.x * res.x, x1 = DESK_TRUSS_X.y * res.x;
    [unroll] for (uint k = 0u; k < 3u; k++)
    {
        float y = DESK_TRUSS_Y[k] * res.y;
        dlRect(float4(x0, y - w, x1, y + w), IL_RULE * 0.7, 1.0, 0.0);
    }
    float4 a = ilCtlRect(DESK_AUDIENCE, res);
    dlLabel(LB_AUDIENCE, ilMid(a).x, ilMid(a).y, 8.5 * s, IL_DIM, IL_CENTER);
}

// Thread 0 records the plates and everything that is not a control, reserves one run of slots for the controls, and
// publishes what they need to know; every thread then draws the controls (main).
void layout()
{
    float2 res = _Resolution.xy;
    float s = deskScale(res);
    dlBegin(res);

    // what is up in each bank, and whether the Surface is answering at all
    uint lvFull = NO_PAD, lvStatic = NO_PAD, lvFx = NO_PAD, lvColor = NO_PAD;
    bool heard = false;
    [loop] for (uint k = 0u; k < DESK_COUNT; k++)
    {
        uint b = DESK_BANK[k];
        if (DESK_KIND[k] != DK_PAD || b == 0u) continue;
        heard = heard || _ViewportControlState[k].state != ST_EMPTY;
        if (!live(k)) continue;
        if (b == 1u && lvFull == NO_PAD) lvFull = k;
        if (b == 2u && lvStatic == NO_PAD) lvStatic = k;
        if (b == 3u && lvFx == NO_PAD) lvFx = k;
        if (b == 4u && lvColor == NO_PAD) lvColor = k;
    }

    [loop] for (uint p = 0u; p < DESK_PANES; p++)
        dlRect(ilCtlRect(DESK_PANE[p], res), IL_PANEL, 1.0, 1.5 * IL_RADIUS * s);

    float4 tr = ilCtlRect(DESK_TITLE, res);
    dlLabel(LB_TITLE, tr.x + 2.0 * s, lerp(tr.y, tr.w, 0.38), 20.0 * s, IL_INK, IL_LEFT);
    dlLabel(LB_SUBTITLE, tr.x + 2.0 * s, lerp(tr.y, tr.w, 0.74), 12.0 * s, IL_DIM, IL_LEFT);
    fixtureMap(res, s);

    // the controls themselves draw in parallel, into these slots (main)
    gsLiveTier = (lvFx != NO_PAD) ? DESK_SUB[lvFx] : 0u;
    dlBatch(DESK_SLOTS, 0u);

    tempoReadout(ilCtlRect(UI_RECT_BPM, res), s);
    beatReadout(ilCtlRect(UI_RECT_BEAT, res), s);

    float4 lh = ilCtlRect(DESK_LIVE_HEAD, res);
    dlLabel(LB_LIVE, lh.x, ilMid(lh).y, 12.0 * s, IL_MID, IL_LEFT);
    dlHLine(lh.w, lh.x, lh.z, IL_EDGE);
    equation(ilCtlRect(UI_RECT_LEGEND_FULL, res), s, lvFull, lvStatic, lvFx, lvColor);
    // the sequence that is up: the Surface names it (which types, which sequence) in seq_live
    float4 sq = ilCtlRect(UI_RECT_SEQ_LIVE, res);
    bool anySeq = false;
    [loop] for (uint q = 0u; q < 4u; q++) anySeq = anySeq || ilCtlLit(UI_SEQK_RIG + q);
    liveCell(sq, s, 5u, LB_C_SEQ, UI_SEQ_LIVE, anySeq);
    float4 cam = ilCtlRect(DESK_CAMERA, res);
    dlLabel(LB_CAMERA, cam.x + 2.0 * s, ilMid(cam).y, 11.0 * s, IL_MID, IL_LEFT);

    float4 sr = ilCtlRect(UI_RECT_STATUS, res);
    dlRect(sr, IL_WELL, 1.0, IL_RADIUS * s);
    panelLabelLong(UI_STATUS, sr.x + 10.0 * s, ilMid(sr).y, 14.0 * s, IL_SANS, IL_INK, IL_LEFT);
    if (!heard) dlLabel(LB_QUIET, sr.z - 8.0 * s, ilMid(sr).y, IL_T_CAP * s, IL_MID, IL_RIGHT);
    float4 si = ilCtlRect(UI_RECT_SEL_INFO, res);
    dlRect(si, IL_WELL, 1.0, IL_RADIUS * s);
    dlCircle(float2(si.x + 12.0 * s, ilMid(si).y), 3.0 * s, IL_ACCENT, 1.0);
    panelLabelLong(UI_SEL_INFO, si.x + 22.0 * s, ilMid(si).y, 12.0 * s, IL_BOLD, IL_MID, IL_LEFT);

    dlFinish();
}

// One control, on any layout thread, into its own run of slots.
void control(uint i, float s)
{
    float4 r = ilCtlRect(DESK_RECT[i], _Resolution.xy);
    uint kind = DESK_KIND[i];
    if (kind == DK_PAD) pad(i, r, s);
    else if (kind == DK_FIXTURE) fixturePad(i, r, s);
    else if (kind == DK_GROUP) groupPad(i, r, s);
    else if (kind == DK_TAB) tab(i, r, s);
    else if (kind == DK_FADER) fader(i, r, s);
    else if (kind == DK_VALUE) faderText(i, r, s);
    else if (kind == DK_HEADER) header(i, r, s);
    else if (kind == DK_TIER) tierChip(i, r, s, gsLiveTier);
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
        deskSpan(b, i);
        control(i, s);
    }
    dlEnd(gi);
}
