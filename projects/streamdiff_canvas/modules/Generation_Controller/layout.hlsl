// Generation_Controller / layout - the generation desk, recorded as a draw list for the shared UI kit
// (ui.hlsl rasterizes it; there is no art pass).
//
// It answers three questions at a glance: is StreamDiff generating right now (the status lamp),
// where in the prompt bank are we and what comes next (the bank, with an inspector on every
// prompt), and what has the controller been doing (eight seconds of windows and stamps).
//
// The seven host controls draw at their manifest rects (UI_RECT_*, the very rects the host
// hit-tests) from the host's own hover / press flags and the parameters. Everything else reads
// generation_state, which update.hlsl alone writes - [0] hold, prompt position, pulse, cycle;
// [1] interval clock, render window left, latches; [2] init, mode, run, stamp seconds;
// [3] stamp cycle, linked, continuous stamp clock, stamp pending - and the activity ring that
// history.hlsl keeps. Hover comes from the pointer here and is never stored.
//
// 64 threads: thread 0 records everything but the ring's 256 samples, which it reserves as one
// batch (two slots each: a run of open windows, a stamp tick) and every thread then fills.
#include "gc_history.hlsli"
StructuredBuffer<float4> State : register(t0);
StructuredBuffer<float4> Hist : register(t1);
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"

// The controls are fixed fractions of the panel, so the type follows them: body type is 12.5 px
// where a mode segment is ~85 px wide and a chip ~23 px tall (760 x 210), and never under 9 px.
float gcScale(float2 R) { return clamp(min(R.x / 760.0, R.y / 210.0), 0.9, 2.4); }

// Every rect below the sliders, from the live extent: the prompt readout, the bank (and its ticks),
// the activity ring (and its two lanes). Drawing, the ring batch and hover all use this.
struct GcGeom
{
    float s;
    float4 prompt, bank, act;
    float4 track;          // the bank's ticks
    float4 laneW, laneS;   // windows and stamps; the time strip runs from x to z, now at z
};

GcGeom gcGeom(float2 R)
{
    GcGeom g;
    float s = gcScale(R);
    g.s = s;
    float y0 = 0.50 * R.y, y1 = 0.965 * R.y;
    g.prompt = float4(0.02 * R.x, y0, 0.17 * R.x, y1);
    g.bank = float4(0.19 * R.x, y0, 0.64 * R.x, y1);
    g.act = float4(0.66 * R.x, y0, 0.98 * R.x, y1);
    float4 t = float4(g.bank.x + 14.0 * s, y0 + 24.0 * s, g.bank.z - 14.0 * s, y1 - 22.0 * s);
    float th = clamp(t.w - t.y, 8.0 * s, 90.0 * s);
    t.y = ilMid(t).y - 0.5 * th;
    t.w = t.y + th;
    g.track = t;
    float capW = max(ilLabelW(LB_L_WINDOWS, IL_T_CAP * s), ilLabelW(LB_L_STAMPS, IL_T_CAP * s)) + 10.0 * s;
    float4 a = float4(g.act.x + 10.0 * s + capW, y0 + 24.0 * s, g.act.z - 10.0 * s, y1 - 8.0 * s);
    float lh = clamp(0.5 * (a.w - a.y) - 3.0 * s, 6.0 * s, 40.0 * s);
    float mid = ilMid(a).y;
    g.laneW = float4(a.x, mid - 3.0 * s - lh, a.z, mid - 3.0 * s);
    g.laneS = float4(a.x, mid + 3.0 * s, a.z, mid + 3.0 * s + lh);
    return g;
}

// Sample `age` cooks back in the ring (0 = newest).
float4 ghSample(uint age, uint head) { return Hist[GH_FIRST + (head + GH_N - 1u - min(age, GH_N - 1u)) % GH_N]; }

void plate(float4 r, float s, uint caption)
{
    dlRectEdged(r, IL_PANEL, 1.0, IL_RADIUS * s, IL_EDGE, 1.0);
    dlLabel(caption, r.x + 10.0 * s, r.y + 11.0 * s, IL_T_CAP * s, IL_DIM, IL_LEFT);
}

// A compact inspector card by p, flipped away from the panel's edges; returns it.
float4 card(float2 p, float2 size, float2 R, float s)
{
    float x0 = p.x + 12.0 * s;
    if (x0 + size.x > R.x - 6.0 * s) x0 = p.x - 12.0 * s - size.x;
    float y0 = p.y - 10.0 * s - size.y;
    if (y0 < 6.0 * s) y0 = p.y + 16.0 * s;
    x0 = clamp(x0, 6.0 * s, max(R.x - 6.0 * s - size.x, 6.0 * s));
    y0 = clamp(y0, 6.0 * s, max(R.y - 6.0 * s - size.y, 6.0 * s));
    float4 r = float4(x0, y0, x0 + size.x, y0 + size.y);
    dlRectEdged(r, IL_RAISE, 1.0, IL_RADIUS * s, IL_EDGE, 1.0);
    return r;
}

// A position in the bank, 0..n, wrapped the way update.hlsl's wrapPrompt wraps it (exact for whole
// prompts, where frac(r / n) * n can land a hair under one and floor to the wrong tick).
float gcWrap(float r, float n) { return r - floor(r / n) * n; }

// Advances of prompt_step (Interval steps, Manual presses) until the bank position lands on tick k:
// 0 while it is there, -1 when the step never lands on it.
int advancesTo(uint k, float p, uint n, float step)
{
    [loop] for (int a = 0; a <= 64; a++)
    {
        float q = gcWrap(p + a * step, (float)n);
        if (min((uint)floor(q), n - 1u) == k) return a;
    }
    return -1;
}

// The mode switch. Mode is a host slider on an int, and the host rounds a slider to the nearest
// value: a press a quarter of the way in already picks INTERVAL. So the three cells are its capture
// zones - a quarter, a half, a quarter - rather than equal thirds, and the hovered cell (hot, from the
// same rounding) is the one a click would pick. The kit's equal segments would put a quarter of
// MANUAL and of CONTINUOUS under the wrong value. The labels shrink together if an end cell is short.
void modeCells(float4 r, float s, int sel, int hot)
{
    dlRectEdged(r, IL_WELL, 1.0, IL_RADIUS * s, IL_EDGE, 1.0);
    float w = r.z - r.x;
    float size = IL_T_BODY * s;
    float room = 0.25 * w - 8.0 * s;
    float need = max(ilLabelW(LB_M_MANUAL, size), ilLabelW(LB_M_CONTINUOUS, size));
    if (need > room) size *= max(room, 1.0) / need;
    [loop] for (uint i = 0u; i < 3u; i++)
    {
        float4 seg = float4(r.x + w * max(0.5 * (float)i - 0.25, 0.0), r.y, r.x + w * min(0.5 * (float)i + 0.25, 1.0), r.w);
        if ((int)i == sel)
        {
            dlRect(ilInset(seg, 2.0 * s), IL_RAISE * 2.0, 1.0, IL_RADIUS * s * 0.8);
            dlRect(float4(seg.x + 7.0 * s, seg.w - 4.0 * s, seg.z - 7.0 * s, seg.w - 2.0 * s), IL_ACCENT, 1.0, 1.0);
        }
        else if ((int)i == hot) dlRect(ilInset(seg, 2.0 * s), IL_RAISE * 1.3, 1.0, IL_RADIUS * s * 0.8);
        if (i > 0u && (int)i != sel && (int)i - 1 != sel) dlVLine(seg.x, r.y + 5.0 * s, r.w - 5.0 * s, IL_EDGE);
        dlLabel(LB_M_MANUAL + i, ilMid(seg).x, ilMid(seg).y, size, ((int)i == sel) ? IL_INK : IL_DIM, IL_CENTER);
    }
}

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
    GcGeom g = gcGeom(R);
    float s = g.s;
    dlBegin(R);
    float4 out0 = State[0];
    bool held = out0.x > 0.5;
    bool running = transport_run != 0;
    int m = (int)clamp(round((float)mode), 0.0, 2.0);
    float2 ptr = _ViewportPointerPosition * R;
    bool inView = all(ptr >= 0.0) && all(ptr <= R);

    // ---- the top row: mode (the cell a click would pick lifts), then RUN / LINKED / GENERATE / NEXT PROMPT
    float4 rMode = ilCtlRect(UI_RECT_MODE, R);
    int hotSeg = (inView && ilCtlHot(UI_MODE)) ? (int)clamp(round(2.0 * (ptr.x - rMode.x) / max(rMode.z - rMode.x, 1.0)), 0.0, 2.0) : -1;
    modeCells(rMode, s, m, hotSeg);
    uint ids[4] = { UI_TRANSPORT, UI_LINKED, UI_GENERATE, UI_NEXT };
    float4 rects[4] = { UI_RECT_TRANSPORT, UI_RECT_LINKED, UI_RECT_GENERATE, UI_RECT_NEXT };
    // RUN and LINKED are modes (the accent tick while on). GENERATE and NEXT PROMPT are triggers:
    // every flip of their latch opens one render window, so the latch itself never reads as "on".
    uint on = (running ? 1u : 0u) | (link_stamps != 0 ? 2u : 0u);
    [loop] for (uint i = 0u; i < 4u; i++)
        dlChip(ilCtlRect(rects[i], R), s, LB_C_RUN + i, ((on >> i) & 1u) != 0u, ilCtlHot(ids[i]), ilCtlDown(ids[i]));
    float xR = ilCtlRect(UI_RECT_NEXT, R).z;

    // ---- the title row: identity, the gestures, and the hold StreamDiff is getting right now
    float4 rRate = ilCtlRect(UI_RECT_PROMPT_RATE, R);
    float4 rStamp = ilCtlRect(UI_RECT_STAMP_SPEED, R);
    float ty = 0.5 * (rMode.w + rRate.y);
    float tw = dlLabel(LB_TITLE, rMode.x, ty, 14.0 * s, IL_INK, IL_LEFT);
    tw += 10.0 * s + dlLabel(LB_SUBTITLE, rMode.x + tw + 10.0 * s, ty, 12.0 * s, IL_DIM, IL_LEFT);
    float sw = dlLabel(held ? LB_HELD : LB_GENERATING, xR, ty, IL_T_TITLE * s, held ? IL_DIM : IL_INK, IL_RIGHT);
    float lampX = xR - sw - 10.0 * s;
    dlCircle(float2(lampX, ty), 3.5 * s, held ? IL_RULE : IL_ACCENT, 1.0);
    float hw = hintW(LB_K_CLICK, LB_D_CLICK, s) + 16.0 * s + hintW(LB_K_DRAG, LB_D_DRAG, s);
    float hx = lampX - 28.0 * s - hw;
    if (hx >= rMode.x + tw + 28.0 * s)
    {
        hx += hint(hx, ty, s, LB_K_CLICK, LB_D_CLICK);
        hint(hx, ty, s, LB_K_DRAG, LB_D_DRAG);
    }

    // ---- the two sliders, each captioned underneath with its value and what it does in this mode
    [loop] for (uint k = 0u; k < 2u; k++)
    {
        bool rate = k == 0u;
        float4 r = rate ? rRate : rStamp;
        uint ctl = rate ? UI_PROMPT_RATE : UI_STAMP_SPEED;
        float v = rate ? prompt_rate : stamp_rate;
        float lo = rate ? 0.05 : 0.5, hi = rate ? 8.0 : 20.0;
        dlSlider(r, s, saturate((v - lo) / (hi - lo)), ilCtlHot(ctl), ilCtlDown(ctl));
        float y = r.w + 8.0 * s;
        float x = r.x;
        x += dlLabel(rate ? LB_PROMPT_RATE : LB_STAMP_SPEED, x, y, IL_T_CAP * s, IL_DIM, IL_LEFT) + 8.0 * s;
        x += dlNum(v, 2, x, y, IL_T_VALUE * s, IL_INK, IL_LEFT) + 2.0 * s;
        dlLabel(LB_PER_S, x, y, IL_T_CAP * s, IL_DIM, IL_LEFT);
        // Interval steps every 1 / rate s and Continuous travels rate prompts a second; stamps come
        // every 1 / speed s unless they are linked to the windows (Manual and Interval)
        uint note = rate ? (m == 0 ? LB_N_MANUAL : (m == 2 ? LB_N_TRAVEL : LB_EVERY))
                         : ((link_stamps != 0 && m < 2) ? LB_N_LINKED : LB_EVERY);
        float xn = r.z;
        if (note == LB_EVERY)
        {
            xn -= dlLabel(LB_U_S, xn, y, IL_T_CAP * s, IL_DIM, IL_RIGHT) + 3.0 * s;
            xn -= dlNum(1.0 / max(v, lo), 2, xn, y, IL_T_VALUE * s, IL_MID, IL_RIGHT) + 4.0 * s;
        }
        dlLabel(note, xn, y, IL_T_CAP * s, IL_DIM, IL_RIGHT);
    }

    // ---- the prompt StreamDiff is on, and how many windows have opened
    float y0 = g.prompt.y, y1 = g.prompt.w;
    plate(g.prompt, s, LB_PROMPT);
    float hero = min(44.0 * s, 0.40 * (y1 - y0));
    dlInt((int)floor(out0.y), 2, g.prompt.x + 10.0 * s, lerp(y0, y1, 0.48), hero, IL_INK, IL_LEFT);
    float cy = y1 - 11.0 * s;
    float cx = g.prompt.x + 10.0 * s;
    cx += dlLabel(LB_CYCLE, cx, cy, IL_T_CAP * s, IL_DIM, IL_LEFT) + 8.0 * s;
    cx += dlInt((int)floor(out0.w), 4, cx, cy, IL_T_VALUE * s, IL_INK, IL_LEFT) + 3.0 * s;
    dlLabelFit(LB_WINDOWS_U, cx, cy, IL_T_CAP * s, IL_DIM, IL_LEFT, g.prompt.z - 8.0 * s - cx);

    // ---- the bank: a tick per prompt, the current one tall, the playhead on the live position
    plate(g.bank, s, LB_BANK);
    uint n = (uint)clamp(prompt_count, 1, 64);
    float p = gcWrap(out0.y - prompt_start, (float)n);                  // 0..n into the bank
    uint cur = min((uint)floor(p), n - 1u);
    float first = floor(prompt_start);
    float4 tr = g.track;
    float th = tr.w - tr.y, my = ilMid(tr).y;
    [loop] for (uint t = 0u; t < n; t++)
    {
        float x = floor(lerp(tr.x, tr.z, (t + 0.5) / n)) + 0.5;
        float h = (t == cur ? 0.80 : 0.32) * th;
        dlVLine(x, my - 0.5 * h, my + 0.5 * h, t == cur ? IL_INK : IL_DIM);
    }
    dlInt((int)first, 1, lerp(tr.x, tr.z, 0.5 / n), y1 - 11.0 * s, IL_T_CAP * s, IL_DIM, IL_CENTER);
    dlInt((int)(first + n - 1u), 1, lerp(tr.x, tr.z, (n - 0.5) / n), y1 - 11.0 * s, IL_T_CAP * s, IL_DIM, IL_CENTER);
    // on a tick at a whole prompt, between two while Continuous travels
    float px = lerp(tr.x, tr.z, frac((p + 0.5) / n));
    dlLine(float2(px, tr.y - 3.0 * s), float2(px, tr.w + 3.0 * s), 2.0, IL_ACCENT, 1.0);
    dlTri(float2(px, tr.y - 2.0 * s), 4.0 * s, 6.0 * s, 0u, IL_ACCENT, 1.0);

    // ---- the activity ring: windows open and stamps fired over the last 8 s, now at the right
    plate(g.act, s, LB_ACTIVITY);
    dlLabel(LB_LAST_8, g.act.z - 10.0 * s, g.act.y + 11.0 * s, IL_T_CAP * s, IL_DIM, IL_RIGHT);
    dlLabel(LB_L_WINDOWS, g.act.x + 10.0 * s, ilMid(g.laneW).y, IL_T_CAP * s, IL_DIM, IL_LEFT);
    dlLabel(LB_L_STAMPS, g.act.x + 10.0 * s, ilMid(g.laneS).y, IL_T_CAP * s, IL_DIM, IL_LEFT);
    dlRect(g.laneW, IL_WELL, 1.0, 2.0 * s);
    dlRect(g.laneS, IL_WELL, 1.0, 2.0 * s);
    [loop] for (uint sec = 1u; sec < 8u; sec++)
    {
        float gx = floor(lerp(g.laneW.z, g.laneW.x, sec / GH_SPAN)) + 0.5;
        dlVLine(gx, g.laneW.y, g.laneW.w, IL_GRID);
        dlVLine(gx, g.laneS.y, g.laneS.w, IL_GRID);
    }
    dlBatch(GH_N * 2u, 0u);                      // the samples, filled by every thread (main)

    // ---- inspectors, on top of everything
    uint head = (uint)Hist[0].x % GH_N;
    float4 hitBank = float4(tr.x, g.bank.y + 20.0 * s, tr.z, g.bank.w - 4.0 * s);
    float4 hitAct = float4(g.laneW.x, g.laneW.y - 3.0 * s, g.laneW.z, g.laneS.w + 3.0 * s);
    float vs = IL_T_VALUE * s, cs = IL_T_CAP * s;
    if (inView && ilIn(ptr, hitBank))
    {
        uint hk = min((uint)floor((ptr.x - tr.x) / max(tr.z - tr.x, 1.0) * n), n - 1u);
        float hx2 = floor(lerp(tr.x, tr.z, (hk + 0.5) / n)) + 0.5;
        if (hk != cur) dlVLine(hx2, tr.y, tr.w, IL_INK);
        if (tooltips != 0)                       // Tooltips: the card beside the pointer
        {
            // what it takes to get there: Manual presses, Interval steps (and when), Continuous travel
            bool live = hk == cur;
            int adv = 0;
            float eta = -1.0;
            if (m == 2)
            {
                adv = (int)((hk + n - cur) % n);
                if (running && !live) eta = gcWrap((float)hk - p, (float)n) / max(prompt_rate, 1e-3);
            }
            else
            {
                adv = advancesTo(hk, p, n, max(prompt_step, 0.01));
                float iv = 1.0 / max(prompt_rate, 0.05);
                if (m == 1 && running && adv > 0) eta = max(iv - State[1].x, 0.0) + (adv - 1) * iv;
            }
            uint unit = (m == 0) ? (adv == 1 ? LB_I_PRESS : LB_I_PRESSES)
                      : ((m == 1) ? (adv == 1 ? LB_I_STEP : LB_I_STEPS) : (adv == 1 ? LB_I_AHEAD : LB_I_AHEADS));
            uint words = live ? LB_I_NOW : (adv < 0 ? LB_I_SKIP : unit);
            bool showAdv = !live && adv >= 0;
            float w2 = (showAdv ? ilNumW(ilFormat((float)adv, 0, 1, false).n, vs) + 4.0 * s : 0.0) + ilLabelW(words, cs)
                     + (eta >= 0.0 ? 8.0 * s + ilLabelW(LB_I_IN, cs) + 4.0 * s + ilNumW(ilFormat(eta, 1, 1, false).n, vs) + 3.0 * s + ilLabelW(LB_U_S, cs) : 0.0);
            float w1 = ilLabelW(LB_PROMPT, cs) + 8.0 * s + ilNumW(3u, vs * 1.15);
            float4 c = card(float2(hx2, tr.y), float2(max(w1, w2) + 20.0 * s, 46.0 * s), R, s);
            float r1 = c.y + 14.0 * s, r2 = c.y + 32.0 * s;
            float x = c.x + 10.0 * s;
            x += dlLabel(LB_PROMPT, x, r1, cs, IL_DIM, IL_LEFT) + 8.0 * s;
            dlInt((int)(first + hk), 2, x, r1, vs * 1.15, IL_INK, IL_LEFT);
            x = c.x + 10.0 * s;
            if (showAdv) x += dlInt(adv, 1, x, r2, vs, IL_INK, IL_LEFT) + 4.0 * s;
            x += dlLabel(words, x, r2, cs, live ? IL_INK : IL_DIM, IL_LEFT);
            if (eta >= 0.0)
            {
                x += 8.0 * s;
                x += dlLabel(LB_I_IN, x, r2, cs, IL_DIM, IL_LEFT) + 4.0 * s;
                x += dlNum(eta, 1, x, r2, vs, IL_INK, IL_LEFT) + 3.0 * s;
                dlLabel(LB_U_S, x, r2, cs, IL_DIM, IL_LEFT);
            }
        }
    }
    else if (inView && ilIn(ptr, hitAct))
    {
        float wS = (g.laneW.z - g.laneW.x) / (float)GH_N;
        uint age = min((uint)floor((g.laneW.z - ptr.x) / max(wS, 1e-3)), GH_N - 1u);
        float4 smp = ghSample(age, head);
        dlVLine(floor(ptr.x) + 0.5, g.laneW.y - 2.0 * s, g.laneS.w + 2.0 * s, IL_INK);
        if (tooltips != 0)                       // Tooltips: the card beside the pointer
        {
            bool open = smp.x > 0.5, stamp = smp.y > 0.5;
            float ago = (age + 0.5) * GH_DT;
            float w1 = ilNumW(ilFormat(ago, 2, 1, false).n, vs) + 3.0 * s + ilLabelW(LB_I_AGO, cs);
            float w2 = ilLabelW(open ? LB_I_OPEN : LB_I_SHUT, cs) + (stamp ? 6.0 * s + ilLabelW(LB_I_STAMP, cs) : 0.0);
            float4 c = card(float2(ptr.x, g.laneW.y), float2(max(w1, w2) + 20.0 * s, 46.0 * s), R, s);
            float x = c.x + 10.0 * s;
            x += dlNum(ago, 2, x, c.y + 14.0 * s, vs, IL_INK, IL_LEFT) + 3.0 * s;
            dlLabel(LB_I_AGO, x, c.y + 14.0 * s, cs, IL_DIM, IL_LEFT);
            x = c.x + 10.0 * s;
            x += dlLabel(open ? LB_I_OPEN : LB_I_SHUT, x, c.y + 32.0 * s, cs, open ? IL_INK : IL_DIM, IL_LEFT);
            if (stamp) dlLabel(LB_I_STAMP, x + 6.0 * s, c.y + 32.0 * s, cs, IL_INK, IL_LEFT);
        }
    }

    dlFinish();
}

// Ring sample `age` (0 = newest), on any layout thread: a run of open windows is drawn once, from its
// newest sample, as one rect; a sample that fired stamps draws a tick.
void drawSample(uint age, GcGeom g, uint head)
{
    float w = (g.laneW.z - g.laneW.x) / (float)GH_N;
    float4 smp = ghSample(age, head);
    if (smp.x > 0.5 && (age == 0u || ghSample(age - 1u, head).x <= 0.5))
    {
        uint e = age;
        [loop] while (e + 1u < GH_N && ghSample(e + 1u, head).x > 0.5) e++;
        float xl = floor(g.laneW.z - (e + 1u) * w), xr = floor(g.laneW.z - age * w);
        dlRect(float4(xl, g.laneW.y, max(xr, xl + 1.0), g.laneW.w), IL_MID, 1.0, 0.0);
    }
    if (smp.y > 0.5)
    {
        float xc = floor(g.laneS.z - (age + 0.5) * w) + 0.5;
        dlRect(float4(xc - 0.5, g.laneS.y, xc + 0.5, g.laneS.w), IL_INK, 1.0, 0.0);
    }
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    if (gi == 0u) layout();
    dlSync();
    ILBatch b = dlGetBatch(0u);
    GcGeom g = gcGeom(_Resolution.xy);
    uint head = (uint)Hist[0].x % GH_N;
    [loop] for (uint i = gi; i < GH_N; i += IL_LAYOUT_THREADS)
    {
        dlAtSpan(b, i, 2u);
        drawSample(i, g, head);
    }
    dlEnd(gi);
}
