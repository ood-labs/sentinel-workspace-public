// Pattern / layout - the editor's panes: the grid (each lane's steps at its own length, in the edit
// layer's terms, with its end bracket), the rings (each lane's cycle as a ring of steps turned by its
// turn, a hand sweeping it: the hands all point up together only when every cycle starts at once),
// the lane and step inspectors, the tools, and the tape (every hit as it went out, against the steps,
// with what has been sent ahead of now).
//
// Grey carries everything; amber marks the selection (the lane, the step) and the position readouts.
// A step that sounds flashes white for its lane's envelope - a chance that says no leaves it dark,
// which is how chance is seen working.
//
// 64 threads: thread 0 records the chrome and reserves three batches - the grid's cells, the rings'
// dots, the tape's hits - which every thread then fills.
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"
#include "../_shared/ui/il_pane.hlsli"
#include "pt.hlsli"

#define CELL_SLOTS 6u                // body, value bar, three ratchet ticks, nudge marker
#define DOT_SLOTS  3u                // dot (or outline and chance arc), selection ring

static PtLayout g_L;
static float g_s;
static float2 g_res, g_ptr;
static uint g_mode, g_target, g_lane, g_step, g_layer;
static float g_nowW, g_nowF;
static bool g_playing;
static float g_env[PT_LANES];

void plate(float4 r) { dlRect(r, IL_PANEL, 0.86, IL_RADIUS * g_s); }
uint laneNow(uint l) { return ptLaneStep(l, g_nowW); }
// a lane's flash on the step sounding now: its envelope, only on that step
float flashOf(uint l, uint i) { return (g_playing && i == laneNow(l)) ? g_env[l] : 0.0; }

// a note's name and octave (C3 = 48)
float noteLabel(uint n, float x, float y, float size, float3 col, uint align)
{
    float w = ilLabelW(LB_N_0 + n % 12u, size) + ilNumW(1u, size);
    float x0 = ilAlignX(x, w, align);
    float a = dlLabel(LB_N_0 + n % 12u, x0, y, size, col, IL_LEFT);
    return a + dlInt((int)(n / 12u) - 1, 1, x0 + a, y, size, col, IL_LEFT);
}

// a drag field: caption above, value inside (the value is drawn by the caller)
float4 field(uint f, uint caption, bool live)
{
    float s = g_s;
    float4 r = ptField(g_L, f, s);
    bool hot = g_mode == DM_NONE && ilIn(g_ptr, r);
    dlLabel(caption, r.x + 2.0 * s, r.y - 9.0 * s, IL_T_CAP * s, IL_DIM, IL_LEFT);
    dlRectEdged(r, hot ? IL_RAISE : IL_WELL, 1.0, 2.0 * s, live ? IL_ACCENT : IL_EDGE, 1.0);
    return r;
}
bool liveField(uint f) { return g_mode == DM_FIELD && g_target == f; }

// ---------------------------------------------------------------- the header and the tools
void header()
{
    float s = g_s;
    float4 hd = g_L.head;
    float hy = ilMid(hd).y;
    float tw = ilLabelW(LB_TITLE, 15.0 * s), sw = ilLabelW(LB_SUBTITLE, 12.0 * s);
    float4 hp = float4(hd.x, hd.y, hd.x + tw + sw + 40.0 * s, hd.w);
    plate(hp);
    dlLabel(LB_TITLE, hp.x + 12.0 * s, hy, 15.0 * s, IL_INK, IL_LEFT);
    dlLabel(LB_SUBTITLE, hp.x + 12.0 * s + tw + 14.0 * s, hy, 12.0 * s, IL_DIM, IL_LEFT);

    float cap = IL_T_CAP * s, val = IL_T_VALUE * s;
    uint k = (uint)g_nowW;
    float ww = ilLabelW(LB_BAR, cap) + ilNumW(9u, val) + ilLabelW(LB_HPS, cap) + ilNumW(4u, val) + 70.0 * s;
    float4 cp = float4(hd.z - ww, hd.y, hd.z, hd.w);
    plate(cp);
    float x = cp.x + 12.0 * s;
    x += dlLabel(LB_BAR, x, hy, cap, IL_DIM, IL_LEFT) + 5.0 * s;
    x += dlInt((int)(k / 16u) + 1, 3, x, hy, val, IL_ACCENT, IL_LEFT);
    x += dlLabel(LB_DOT, x, hy, val, IL_DIM, IL_LEFT);
    x += dlInt((int)((k % 16u) / 4u) + 1, 1, x, hy, val, IL_ACCENT, IL_LEFT);
    x += dlLabel(LB_DOT, x, hy, val, IL_DIM, IL_LEFT);
    x += dlInt((int)(k % 4u) + 1, 1, x, hy, val, IL_ACCENT, IL_LEFT) + 16.0 * s;
    x += dlNum(S[PT_V8].z, 1, x, hy, val, IL_INK, IL_LEFT) + 4.0 * s;
    dlLabel(LB_HPS, x, hy, cap, IL_DIM, IL_LEFT);
}

void tools()
{
    float s = g_s;
    float cap = IL_T_CAP * s, val = IL_T_VALUE * s;
    float4 ly = ptLayers(g_L, s);
    int hs = (g_mode == DM_NONE && ilIn(g_ptr, ly)) ? (int)min((uint)((g_ptr.x - ly.x) / ((ly.z - ly.x) / 5.0)), 4u) : -1;
    dlSegmented(ly, s, LB_E_0, 5u, (int)g_layer, hs);
    float4 pc = ptPlayChip(g_L, s);
    bool hot = g_mode == DM_NONE && ilIn(g_ptr, pc);
    dlRectEdged(pc, g_playing ? IL_RAISE * 1.9 : (hot ? IL_RAISE * 1.45 : IL_RAISE), 1.0, IL_RADIUS * s, g_playing ? IL_RULE : IL_EDGE, 1.0);
    float y = ilMid(pc).y;
    float2 ic = float2(pc.x + 15.0 * s, y);
    if (g_playing) dlRect(float4(ic - 4.5 * s, ic + 4.5 * s), IL_ACCENT, 1.0, 1.0 * s);
    else dlTri(float2(ic.x + 5.0 * s, y), 5.0 * s, 8.0 * s, 3u, IL_INK, 1.0);
    dlLabel(g_playing ? LB_STOP : LB_PLAY, pc.x + 28.0 * s, y, cap, g_playing ? IL_INK : IL_MID, IL_LEFT);
    float4 fb = ptField(g_L, PT_F_BPM, s);
    dlLabelFit(LB_AHEAD_D, pc.z + 14.0 * s, y, cap, IL_DIM, IL_LEFT, fb.x - pc.z - 70.0 * s);
    // tempo and swing: drag left / right (their captions sit inside, at the left)
    bool lb = liveField(PT_F_BPM), lw = liveField(PT_F_SWING);
    float4 fw = ptField(g_L, PT_F_SWING, s);
    dlRectEdged(fb, (g_mode == DM_NONE && ilIn(g_ptr, fb)) ? IL_RAISE : IL_WELL, 1.0, 2.0 * s, lb ? IL_ACCENT : IL_EDGE, 1.0);
    dlRectEdged(fw, (g_mode == DM_NONE && ilIn(g_ptr, fw)) ? IL_RAISE : IL_WELL, 1.0, 2.0 * s, lw ? IL_ACCENT : IL_EDGE, 1.0);
    dlLabel(LB_F_7, fb.x + 8.0 * s, y, cap, IL_DIM, IL_LEFT);
    dlNum(ptBpm(), 1, fb.z - 8.0 * s, y, val, lb ? IL_ACCENT : IL_INK, IL_RIGHT);
    dlLabel(LB_F_8, fw.x + 8.0 * s, y, cap, IL_DIM, IL_LEFT);
    float x = dlLabel(LB_PCT, fw.z - 8.0 * s, y, cap, IL_DIM, IL_RIGHT);
    dlInt((int)round(ptSwing() * 100.0), 1, fw.z - 11.0 * s - x, y, val, lw ? IL_ACCENT : IL_INK, IL_RIGHT);
}

// ---------------------------------------------------------------- the grid
void grid()
{
    float s = g_s;
    float cap = IL_T_CAP * s, body = IL_T_BODY * s, val = IL_T_VALUE * s;
    float4 ga = g_L.gridArea;
    float x = ga.x + 2.0 * s, ty = ga.y + 10.0 * s;
    x += dlLabel(LB_GRID, x, ty, IL_T_TITLE * s, IL_DIM, IL_LEFT) + 10.0 * s;
    dlLabelFit(LB_GRID_D, x, ty, cap, IL_DIM, IL_LEFT, ga.z - x);
    // the ruler: step numbers, beats every four
    float4 ru = g_L.ruler;
    [loop] for (uint c = 0u; c < PT_STEPS; c++)
    {
        float cx = g_L.cells.x + (c + 0.5) * g_L.colW;
        bool beat = (c % 4u) == 0u;
        dlInt((int)c + 1, 1, cx, ilMid(ru).y, cap, beat ? IL_MID : IL_DIM, IL_CENTER);
        if (beat && c > 0u) dlVLine(g_L.cells.x + c * g_L.colW, ru.w, g_L.cells.y + PT_LANES * g_L.rowH, IL_GRID);
    }
    bool anySolo = ptAnySolo();
    [loop] for (uint l = 0u; l < PT_LANES; l++)
    {
        float4 r = ptRow(g_L, l);
        float y = ilMid(r).y;
        bool sel = l == g_lane;
        bool audible = ptAudible(l, anySolo);
        float4 hc = float4(r.x, r.y + 2.0 * s, g_L.laneCol.z, r.w - 2.0 * s);
        dlRect(hc, sel ? IL_RAISE * 1.6 : IL_RAISE, 1.0, 2.0 * s);
        if (sel) dlRect(float4(hc.x, hc.y + 3.0 * s, hc.x + 2.0 * s, hc.w - 3.0 * s), IL_ACCENT, 1.0, 0.0);
        noteLabel(ptNote(l), hc.x + 12.0 * s, y, body, audible ? (sel ? IL_INK : IL_MID) : IL_DIM, IL_LEFT);
        dlInt((int)ptLen(l), 1, hc.x + 70.0 * s, y, val, IL_DIM, IL_RIGHT);
        float4 mc = ptMuteChip(g_L, l, s), sc = ptSoloChip(g_L, l, s);
        bool mh = g_mode == DM_NONE && ilIn(g_ptr, mc), sh = g_mode == DM_NONE && ilIn(g_ptr, sc);
        dlRectEdged(mc, ptMute(l) ? IL_RULE : (mh ? IL_RAISE * 2.0 : IL_WELL), 1.0, 2.0 * s, IL_EDGE, 1.0);
        dlRectEdged(sc, ptSolo(l) ? IL_INK : (sh ? IL_RAISE * 2.0 : IL_WELL), 1.0, 2.0 * s, IL_EDGE, 1.0);
        dlLabel(LB_M, ilMid(mc).x, y, cap, ptMute(l) ? IL_FIELD : IL_DIM, IL_CENTER);
        dlLabel(LB_S, ilMid(sc).x, y, cap, ptSolo(l) ? IL_FIELD : IL_DIM, IL_CENTER);
        // the end bracket: the lane loops here; drag it
        float2 b = ptBracket(g_L, l);
        bool bh = g_mode == DM_NONE && ptHitBracket(g_L, l, g_ptr, s);
        bool bl = g_mode == DM_LEN && g_target == l;
        float3 bc = bl ? IL_ACCENT : (bh ? IL_INK : IL_RULE);
        float4 c0 = ptCell(g_L, l, 0u, s);
        dlRect(float4(b.x - 1.0 * s, c0.y - 1.0 * s, b.x + 1.0 * s, c0.w + 1.0 * s), bc, 1.0, 0.0);
        dlRect(float4(b.x - 6.0 * s, c0.y - 1.0 * s, b.x, c0.y + 1.0 * s), bc, 1.0, 0.0);
        dlRect(float4(b.x - 6.0 * s, c0.w - 1.0 * s, b.x, c0.w + 1.0 * s), bc, 1.0, 0.0);
    }
}

// over the cells: the step each lane is on, and the selected step
void gridOver()
{
    float s = g_s;
    [loop] for (uint l = 0u; l < PT_LANES; l++)
    {
        if (!g_playing) continue;
        dlBorderRect(ilInset(ptCell(g_L, l, laneNow(l), s), -1.0 * s), 2.0 * s, IL_MID, 1.25 * s);
    }
    float4 c = ilInset(ptCell(g_L, g_lane, g_step, s), -2.0 * s);
    dlBorderRect(c, 2.5 * s, IL_ACCENT, 1.5 * s);
}

void cellItem(uint g, ILBatch b)
{
    float s = g_s;
    uint l = g / PT_STEPS, i = g % PT_STEPS;
    dlAtSpan(b, g, CELL_SLOTS);
    if (i >= ptLen(l)) return;
    float4 c = ptCell(g_L, l, i, s);
    float4 st = ptStep(l, i);
    bool on = ptOn(st);
    uint rc = ptRatchet(st);
    float fl = flashOf(l, i) * (on ? 1.0 : 0.0);
    float h = c.w - c.y;
    float3 well = IL_RAISE * ((i / 4u) % 2u == 0u ? 1.0 : 1.4);           // empty steps; beats shaded alternately
    if (g_layer == PT_E_STEPS)
    {
        float3 body = on ? lerp(IL_RULE, IL_INK, 0.35 + 0.65 * st.y) : well;
        dlRect(c, lerp(body, float3(1.0, 1.0, 1.0), fl * 0.7), 1.0, 2.0 * s);
        // chance under one: a bar along the bottom, as long as the chance
        if (on && st.z < 0.999) dlRect(float4(c.x + 2.0 * s, c.w - 4.0 * s, lerp(c.x + 2.0 * s, c.z - 2.0 * s, st.z), c.w - 2.0 * s), IL_FIELD, 1.0, 0.0);
    }
    else
    {
        dlRect(c, lerp(well, IL_RAISE * 2.2, fl), 1.0, 2.0 * s);
        float3 ink = on ? IL_INK : IL_RULE;
        if (g_layer == PT_E_VEL) dlRect(float4(c.x + 3.0 * s, c.w - h * st.y, c.z - 3.0 * s, c.w), ink, on ? 0.85 : 0.6, 1.0 * s);
        else if (g_layer == PT_E_CHANCE) dlRect(float4(c.x + 3.0 * s, c.w - h * st.z, c.z - 3.0 * s, c.w), ink, on ? 0.85 : 0.6, 1.0 * s);
        else if (g_layer == PT_E_RATCHET) dlRect(float4(c.x + 3.0 * s, c.w - h * (float)rc / 4.0, c.z - 3.0 * s, c.w), ink, on ? 0.5 : 0.35, 1.0 * s);
        else
        {
            float m = 0.5 * (c.y + c.w);
            dlRect(float4(c.x + 3.0 * s, min(m, m - h * st.w), c.z - 3.0 * s, max(m, m - h * st.w) + 1.0), ink, on ? 0.85 : 0.6, 0.0);
        }
    }
    // the ratchet's extra hits, where they fall inside the step
    if (on)
        [loop] for (uint r = 1u; r < rc; r++)
        {
            float xr = lerp(c.x, c.z, (float)r / (float)rc);
            dlRect(float4(xr - 0.75 * s, c.y + 3.0 * s, xr + 0.75 * s, c.y + 0.4 * h), g_layer == PT_E_STEPS ? IL_FIELD : IL_INK, 0.9, 0.0);
        }
    // a nudge: a notch on the top edge where the hit lands
    if (on && abs(st.w) > 0.001)
    {
        float xn = clamp(c.x + st.w * (c.z - c.x), c.x - 0.5 * g_L.colW, c.z);
        dlTri(float2(xn, c.y - 1.0 * s), 3.5 * s, 5.0 * s, 1u, IL_MID, 1.0);
    }
}

// ---------------------------------------------------------------- the rings
void rings()
{
    float s = g_s;
    float cap = IL_T_CAP * s, val = IL_T_VALUE * s;
    float4 ra = g_L.ringArea;
    float x = ra.x + 2.0 * s, ty = ra.y + 10.0 * s;
    x += dlLabel(LB_RINGS, x, ty, IL_T_TITLE * s, IL_DIM, IL_LEFT) + 10.0 * s;
    dlLabelFit(LB_RINGS_D, x, ty, cap, IL_DIM, IL_LEFT, ra.z - x);
    float2 c = g_L.ringC;
    float rw = ptRingW(g_L);
    bool anySolo = ptAnySolo();
    [loop] for (uint l = 0u; l < PT_LANES; l++)
    {
        float r = ptRingRad(g_L, l);
        bool sel = l == g_lane, held = g_mode == DM_RING && g_target == l;
        bool hot = g_mode == DM_NONE && ptRingAt(g_L, g_ptr) == l;
        dlRing(c, r, held ? 2.0 * s : 1.0 * s, held ? IL_ACCENT : (sel ? IL_RULE * 1.6 : (hot ? IL_RULE * 1.3 : IL_EDGE)), ptAudible(l, anySolo) ? 1.0 : 0.5);
    }
    // the cycle all six share: how far along, and how long until every hand points up together
    uint lcm = ptLcm();
    uint pos = ((uint)g_nowW) % lcm;
    uint left = lcm - pos;
    float r0 = g_L.ringR0;
    dlRing(c, r0 - 8.0 * s, 1.0 * s, IL_EDGE, 1.0);
    dlArc(c, r0 - 8.0 * s, 2.0 * s, 0.0, 6.2831853 * ((float)pos + g_nowF) / (float)lcm, IL_MID, 1.0);
    dlLabel(LB_REALIGN, c.x, c.y - 22.0 * s, cap, IL_DIM, IL_CENTER);
    dlInt((int)left, 1, c.x, c.y - 4.0 * s, 15.0 * s, IL_ACCENT, IL_CENTER);
    uint secs = (uint)((float)left / max(ptStepsPerSec(), 1e-3));
    uint m = secs / 60u, sec = secs % 60u;
    float tw = ilNumW(m >= 100u ? 3u : (m >= 10u ? 2u : 1u), val) + ilLabelW(LB_COLON, val) + ilNumW(2u, val);
    float tx = c.x - 0.5 * tw;
    tx += dlInt((int)m, 1, tx, c.y + 15.0 * s, val, IL_INK, IL_LEFT);
    tx += dlLabel(LB_COLON, tx, c.y + 15.0 * s, val, IL_DIM, IL_LEFT);
    dlInt((int)sec, 2, tx, c.y + 15.0 * s, val, IL_INK, IL_LEFT);
    dlLabel(LB_OF_STEPS, c.x, c.y + 32.0 * s, cap, IL_DIM, IL_CENTER);
}

// over the dots: the hands
void ringsOver()
{
    float s = g_s;
    float2 c = g_L.ringC;
    float rw = ptRingW(g_L);
    [loop] for (uint l = 0u; l < PT_LANES; l++)
    {
        float r = ptRingRad(g_L, l);
        float a = 6.2831853 * ptLanePos(l, g_nowW, g_nowF) / (float)ptLen(l);
        bool sel = l == g_lane;
        dlLine(ptRingPoint(g_L, r - 0.42 * rw, a), ptRingPoint(g_L, r + 0.42 * rw, a), (sel ? 2.0 : 1.5) * s, sel ? IL_ACCENT : IL_INK, sel ? 1.0 : 0.75);
    }
}

void dotItem(uint g, ILBatch b)
{
    float s = g_s;
    uint l = g / PT_STEPS, i = g % PT_STEPS;
    dlAtSpan(b, g, DOT_SLOTS);
    if (i >= ptLen(l)) return;
    float4 st = ptStep(l, i);
    bool on = ptOn(st);
    float rw = ptRingW(g_L), r = ptRingRad(g_L, l);
    float2 p = ptRingPoint(g_L, r, ptStepAngle(l, i));
    float fl = flashOf(l, i) * (on ? 1.0 : 0.0);
    bool sel = l == g_lane && i == g_step;
    if (!on)
    {
        dlCircle(p, max(1.5 * s, 0.09 * rw), sel ? IL_ACCENT : IL_RULE, 1.0);
        return;
    }
    float dr = lerp(0.16, 0.36, st.y) * rw;
    float3 col = lerp(lerp(IL_MID, IL_INK, st.y), float3(1.0, 1.0, 1.0), fl);
    if (st.z < 0.999)
    {
        // a chance under one: an outline, filled round as far as the chance
        dlRing(p, dr, 1.25 * s, col, 1.0);
        dlArc(p, 0.5 * dr, dr, 0.0, 6.2831853 * st.z, col, 1.0);
    }
    else dlCircle(p, dr, col, 1.0);
    if (sel) dlRing(p, dr + 3.0 * s, 1.5 * s, IL_ACCENT, 1.0);
}

// ---------------------------------------------------------------- the inspectors
void inspectors()
{
    float s = g_s;
    float cap = IL_T_CAP * s, val = IL_T_VALUE * s, body = IL_T_BODY * s;
    // the lane
    float4 li = g_L.laneI;
    plate(li);
    float x = li.x + 10.0 * s, ty = li.y + 14.0 * s;
    x += dlLabel(LB_LANE, x, ty, IL_T_TITLE * s, IL_DIM, IL_LEFT) + 10.0 * s;
    x += dlInt((int)g_lane + 1, 1, x, ty, body, IL_INK, IL_LEFT) + 8.0 * s;
    noteLabel(ptNote(g_lane), x, ty, body, IL_ACCENT, IL_LEFT);
    float4 f0 = field(PT_F_NOTE, LB_F_0, liveField(PT_F_NOTE));
    noteLabel(ptNote(g_lane), f0.z - 8.0 * s, ilMid(f0).y, val, liveField(PT_F_NOTE) ? IL_ACCENT : IL_INK, IL_RIGHT);
    float4 f1 = field(PT_F_LEN, LB_F_1, liveField(PT_F_LEN));
    dlInt((int)ptLen(g_lane), 1, f1.z - 8.0 * s, ilMid(f1).y, val, liveField(PT_F_LEN) ? IL_ACCENT : IL_INK, IL_RIGHT);
    float4 f2 = field(PT_F_TURN, LB_F_2, liveField(PT_F_TURN));
    dlInt((int)ptTurn(g_lane), 1, f2.z - 8.0 * s, ilMid(f2).y, val, liveField(PT_F_TURN) ? IL_ACCENT : IL_INK, IL_RIGHT);
    float4 f3 = field(PT_F_HITS, LB_F_3, liveField(PT_F_HITS));
    dlInt((int)ptHits(g_lane), 1, f3.z - 8.0 * s, ilMid(f3).y, val, liveField(PT_F_HITS) ? IL_ACCENT : IL_INK, IL_RIGHT);
    float4 mc = ptLaneChip(g_L, 0u, s), sc = ptLaneChip(g_L, 1u, s);
    dlChip(mc, s, LB_MUTE, ptMute(g_lane), g_mode == DM_NONE && ilIn(g_ptr, mc), false);
    dlChip(sc, s, LB_SOLO, ptSolo(g_lane), g_mode == DM_NONE && ilIn(g_ptr, sc), false);
    dlLabelFit(LB_EUCLID_D, sc.z + 14.0 * s, ilMid(sc).y, cap, IL_DIM, IL_LEFT, li.z - sc.z - 24.0 * s);

    // the step
    float4 si = g_L.stepI;
    plate(si);
    float4 st = ptStep(g_lane, g_step);
    x = si.x + 10.0 * s;
    x += dlLabel(LB_STEP, x, ty, IL_T_TITLE * s, IL_DIM, IL_LEFT) + 10.0 * s;
    x += dlInt((int)g_step + 1, 1, x, ty, body, IL_ACCENT, IL_LEFT) + 5.0 * s;
    x += dlLabel(LB_OF, x, ty, cap, IL_DIM, IL_LEFT) + 5.0 * s;
    x += dlInt((int)ptLen(g_lane), 1, x, ty, body, IL_INK, IL_LEFT) + 10.0 * s;
    dlLabel(ptOn(st) ? LB_ON : LB_OFF, x, ty, cap, ptOn(st) ? IL_INK : IL_DIM, IL_LEFT);
    float4 f4 = field(PT_F_VEL, LB_F_4, liveField(PT_F_VEL));
    float px = dlLabel(LB_PCT, f4.z - 8.0 * s, ilMid(f4).y, cap, IL_DIM, IL_RIGHT);
    dlInt((int)round(st.y * 100.0), 1, f4.z - 11.0 * s - px, ilMid(f4).y, val, liveField(PT_F_VEL) ? IL_ACCENT : IL_INK, IL_RIGHT);
    float4 f5 = field(PT_F_CHANCE, LB_F_5, liveField(PT_F_CHANCE));
    dlLabel(LB_PCT, f5.z - 8.0 * s, ilMid(f5).y, cap, IL_DIM, IL_RIGHT);
    dlInt((int)round(st.z * 100.0), 1, f5.z - 11.0 * s - px, ilMid(f5).y, val, liveField(PT_F_CHANCE) ? IL_ACCENT : IL_INK, IL_RIGHT);
    float4 f6 = field(PT_F_NUDGE, LB_F_6, liveField(PT_F_NUDGE));
    dlLabel(LB_PCT, f6.z - 8.0 * s, ilMid(f6).y, cap, IL_DIM, IL_RIGHT);
    dlNumEx(round(st.w * 100.0), 0, 1, true, f6.z - 11.0 * s - px, ilMid(f6).y, val, liveField(PT_F_NUDGE) ? IL_ACCENT : IL_INK, IL_RIGHT);
    float4 rr = ptRatchets(g_L, s);
    int hr = (g_mode == DM_NONE && ilIn(g_ptr, rr)) ? (int)min((uint)((g_ptr.x - rr.x) / ((rr.z - rr.x) / 4.0)), 3u) : -1;
    dlLabel(LB_F_9, rr.x + 2.0 * s, rr.y - 9.0 * s, cap, IL_DIM, IL_LEFT);
    dlSegmented(rr, s, LB_R_0, 4u, (int)ptRatchet(st) - 1, hr);
}

// ---------------------------------------------------------------- the tape
void tape()
{
    float s = g_s;
    float cap = IL_T_CAP * s;
    float4 tp = g_L.tape;
    float x = tp.x + 2.0 * s, ty = tp.y + 10.0 * s;
    x += dlLabel(LB_TAPE, x, ty, IL_T_TITLE * s, IL_DIM, IL_LEFT) + 10.0 * s;
    dlLabelFit(LB_TAPE_D, x, ty, cap, IL_DIM, IL_LEFT, tp.z - x - 10.0 * s);
    float4 tb = float4(tp.x + 40.0 * s, tp.y + 24.0 * s, tp.z, tp.w);
    dlRect(tb, IL_FIELD, 1.0, 2.0 * s);
    dlBorderRect(tb, 2.0 * s, IL_EDGE, 1.0);
    float rh = (tb.w - tb.y) / (float)PT_LANES;
    [loop] for (uint l = 0u; l < PT_LANES; l++)
    {
        float y = tb.y + (l + 0.5) * rh;
        noteLabel(ptNote(l), tp.x + 34.0 * s, y, cap, l == g_lane ? IL_INK : IL_DIM, IL_RIGHT);
        if (l > 0u) dlHLine(tb.y + l * rh, tb.x, tb.z, IL_GRID);
    }
    // the steps: a line each, beats and bars stronger, moving with the clock
    float x0 = tb.x, x1 = tb.z;
    float xNow = ptTapeX(g_L, 0.0, x0, x1);
    dlClip(tb);
    float swing = (ptSwing() - 0.5) * 2.0;
    [loop] for (int j = -(int)PT_TAPE_BEHIND - 1; j <= (int)PT_TAPE_AHEAD + 1; j++)
    {
        float k = g_nowW + (float)j;
        if (k < 0.0) continue;
        float xs = ptTapeX(g_L, (float)j - g_nowF, x0, x1);
        uint ki = (uint)k;
        float3 c = (ki % 16u == 0u) ? IL_RULE : ((ki % 4u == 0u) ? IL_EDGE * 1.4 : IL_GRID);
        dlVLine(xs, tb.y, tb.w, c);
    }
    // what has been sent: right of now, up to now + the lookahead
    float xAhead = ptTapeX(g_L, PT_LOOKAHEAD * ptStepsPerSec(), x0, x1);
    dlRect(float4(xNow, tb.y, xAhead, tb.w), IL_RAISE, 0.9, 0.0);
    dlClipReset();
    dlRect(float4(xNow - 0.75 * s, tb.y - 4.0 * s, xNow + 0.75 * s, tb.w), IL_ACCENT, 1.0, 0.0);
    dlLabel(LB_NOW, xNow - 4.0 * s, tb.y - 9.0 * s, cap, IL_ACCENT, IL_RIGHT);
    dlLabel(LB_AHEAD, xAhead + 4.0 * s, tb.y - 9.0 * s, cap, IL_DIM, IL_LEFT);
}

void hitItem(uint g)
{
    float s = g_s;
    float4 hr = S[PT_HIST0 + g];
    if (hr.z < 0.0) return;
    uint flags = (uint)hr.z / 8u, l = (uint)hr.z % 8u;
    float rel = (hr.x - g_nowW) + (hr.y - g_nowF);
    if (rel < -PT_TAPE_BEHIND || rel > PT_TAPE_AHEAD) return;
    float4 tp = g_L.tape;
    float4 tb = float4(tp.x + 40.0 * s, tp.y + 24.0 * s, tp.z, tp.w);
    float rh = (tb.w - tb.y) / (float)PT_LANES;
    float x = ptTapeX(g_L, rel, tb.x, tb.z);
    float yb = tb.y + (l + 1u) * rh - 3.0 * s;
    float h = (rh - 6.0 * s) * lerp(0.25, 1.0, hr.w);
    float w = ((flags & PT_H_RATCHET) != 0u ? 1.0 : 1.75) * s;
    float4 r = float4(x - w, yb - h, x + w, yb);
    if ((flags & PT_H_DROPPED) != 0u) dlRectEdged(float4(x - 2.0 * s, yb - h, x + 2.0 * s, yb), IL_FIELD, 1.0, 0.0, IL_RULE, 1.0);
    else dlRect(r, rel > 0.0 ? IL_MID : (l == g_lane ? IL_INK : IL_INK * 0.85), 1.0, 0.0);
}

// ---------------------------------------------------------------- hint bar
void hints()
{
    float s = g_s;
    float kh = 18.0 * s;
    float bx = g_L.hint.x, by = ilMid(g_L.hint).y;
    float total = 0.0;
    [loop] for (uint a = 0u; a < 7u; a++)
        total += ilLabelW(LB_H_K0 + a, IL_T_CAP * s) + 12.0 * s + 6.0 * s + ilLabelW(LB_H_D0 + a, IL_T_CAP * s) + 16.0 * s;
    plate(float4(bx, by - 15.0 * s, bx + total + 8.0 * s, by + 15.0 * s));
    bx += 10.0 * s;
    [loop] for (uint b = 0u; b < 7u; b++)
    {
        float kw = ilLabelW(LB_H_K0 + b, IL_T_CAP * s) + 12.0 * s;
        float dw = ilLabelW(LB_H_D0 + b, IL_T_CAP * s);
        dlKeycap(float4(bx, by - kh * 0.5, bx + kw, by + kh * 0.5), s, LB_H_K0 + b);
        dlLabel(LB_H_D0 + b, bx + kw + 6.0 * s, by, IL_T_CAP * s, IL_DIM, IL_LEFT);
        bx += kw + 6.0 * s + dw + 16.0 * s;
    }
}

// ---------------------------------------------------------------- thread 0
void layout()
{
    dlBegin(g_res);
    header();
    plate(g_L.block);
    tools();
    grid();
    dlBatch(PT_LANES * PT_STEPS * CELL_SLOTS, 0u);       // batch 0: the cells
    gridOver();
    rings();
    dlBatch(PT_LANES * PT_STEPS * DOT_SLOTS, 0u);        // batch 1: the dots
    ringsOver();
    inspectors();
    tape();
    dlClip(float4(g_L.tape.x + 40.0 * g_s, g_L.tape.y + 24.0 * g_s, g_L.tape.z, g_L.tape.w));
    dlBatch(PT_HISTN, 0u);                               // batch 2: the tape's hits
    dlClipReset();
    // the splitters' grips, lit while hovered or held
    bool hx = g_mode == DM_SPLITX || (g_mode == DM_NONE && ilIn(g_ptr, g_L.gripX));
    bool hy = g_mode == DM_SPLITY || (g_mode == DM_NONE && ilIn(g_ptr, g_L.gripY));
    float2 mx = float2(g_L.splitXAt, ilMid(g_L.upper).y), my = float2(ilMid(g_L.inner).x, g_L.splitYAt);
    dlRect(float4(mx.x - 1.5 * g_s, mx.y - 18.0 * g_s, mx.x + 1.5 * g_s, mx.y + 18.0 * g_s), hx ? (g_mode == DM_SPLITX ? IL_ACCENT : IL_INK) : IL_RULE, 1.0, 1.5 * g_s);
    dlRect(float4(my.x - 18.0 * g_s, my.y - 1.5 * g_s, my.x + 18.0 * g_s, my.y + 1.5 * g_s), hy ? (g_mode == DM_SPLITY ? IL_ACCENT : IL_INK) : IL_RULE, 1.0, 1.5 * g_s);
    hints();
    dlFinish();
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    g_res = _Resolution.xy;
    g_s = ilCtx(g_res).s;
    float4 v0 = S[PT_V0], v1 = S[PT_V1], v3 = S[PT_V3], v6 = S[PT_V6], v7 = S[PT_V7], v8 = S[PT_V8];
    g_L = ptLayout(g_res, g_s, v6.xy);
    g_mode = (uint)v1.z;
    g_target = (uint)v1.w;
    g_lane = min((uint)v3.x, PT_LANES - 1u);
    g_step = min((uint)v3.y, ptLen(g_lane) - 1u);
    g_layer = min((uint)v3.z, 4u);
    g_playing = v0.x > 0.5;
    g_nowW = v0.y;
    g_nowF = v0.z;
    g_env[0] = v7.x; g_env[1] = v7.y; g_env[2] = v7.z; g_env[3] = v7.w; g_env[4] = v8.x; g_env[5] = v8.y;
    g_ptr = (g_mode != DM_NONE) ? S[PT_V2].zw : _ViewportPointerPosition * g_res;

    if (gi == 0u) layout();
    dlSync();

    ILBatch bc = dlGetBatch(0u);
    [loop] for (uint a = gi; a < PT_LANES * PT_STEPS; a += IL_LAYOUT_THREADS) cellItem(a, bc);
    ILBatch bd = dlGetBatch(1u);
    [loop] for (uint d = gi; d < PT_LANES * PT_STEPS; d += IL_LAYOUT_THREADS) dotItem(d, bd);
    ILBatch bh = dlGetBatch(2u);
    [loop] for (uint h = gi; h < bh.count; h += IL_LAYOUT_THREADS) { dlAt(bh, h); hitItem(h); }
    dlEnd(gi);
}
