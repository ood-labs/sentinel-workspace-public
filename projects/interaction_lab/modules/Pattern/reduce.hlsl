// Pattern / reduce - one thread, every cook: the viewport events edit the pattern; the transport moves
// the clock and sends every hit that falls due within the next PT_LOOKAHEAD seconds, once each, on
// EventOut "Hits" (with how long until it is due), and keeps a history of them for the tape; the
// lanes' envelopes rise when a hit actually sounds; the working state is written back.
//
//   GRID      click a cell: steps - toggle it; velocity / chance / ratchet / nudge - set from the height
//             drag along a lane: paint the edit layer      drag a lane's end bracket: its length
//             click a lane's name: select it               click M / S: mute / solo
//   RINGS     drag a ring round: turn its lane             click a dot: toggle that step
//   LANE      drag note / length / turn / hits (hits spreads that many evenly)   MUTE, SOLO
//   STEP      drag velocity / chance / nudge, click a ratchet count
//   TOOLS     click an edit layer, PLAY; drag bpm, swing
//   KEYS      Space play   0 to the top   1-5 edit layer   Tab / Up / Down lane   Left / Right step
//             Enter toggle the step   E spread the lane's hits evenly   M mute   S solo
//             Backspace clear the lane   R the default pattern (Z brings yours back)   Z undo
#define PT_STATE_RW
#include "../_shared/ui/il_core.hlsli"
#include "../_shared/ui/il_events.hlsli"
#include "../_shared/ui/il_pane.hlsli"
#include "pt.hlsli"

static uint g_lane;          // the selected lane and step
static uint g_step;

// ---------------------------------------------------------------- undo
void snapshot()
{
    [loop] for (uint i = 0u; i < PT_SAVED; i++) S[PT_UNDO0 + i] = S[i];
    S[PT_U0] = float4(1.0, 0.0, 0.0, 0.0);
}
void restoreSnapshot() { [loop] for (uint i = 0u; i < PT_SAVED; i++) S[i] = S[PT_UNDO0 + i]; }
void swapUndo()
{
    if (S[PT_U0].x < 0.5) return;
    [loop] for (uint i = 0u; i < PT_SAVED; i++)
    {
        float4 a = S[i];
        S[i] = S[PT_UNDO0 + i];
        S[PT_UNDO0 + i] = a;
    }
}

// ---------------------------------------------------------------- lane edits
void setLaneField(uint l, uint comp, float v)
{
    bool4 at = uint4(0u, 1u, 2u, 3u) == comp.xxxx;
    S[PT_LA0 + l] = at ? v.xxxx : S[PT_LA0 + l];
}
void setFlag(uint l, uint bit, bool on)
{
    uint f = (uint)S[PT_LA0 + l].w;
    setLaneField(l, 3u, (float)(on ? (f | bit) : (f & ~bit)));
}
// k of the lane's steps on, spread evenly (Euclid); every step keeps its velocity, chance, ratchet, nudge
void spread(uint l, uint k)
{
    uint n = ptLen(l);
    k = min(k, n);
    [loop] for (uint i = 0u; i < n; i++) S[ptStepSlot(l, i)] = ptWithOn(ptStep(l, i), ptEuclid(i, k, n));
    S[PT_LB0 + l] = float4((float)k, 0.0, 0.0, 0.0);
}
uint onCount(uint l)
{
    uint c = 0u;
    [loop] for (uint i = 0u; i < ptLen(l); i++) c += ptOn(ptStep(l, i)) ? 1u : 0u;
    return c;
}
// the edit layer's value painted into a step: v is the pointer's height in the row, 0..1
void paintStep(uint l, uint i, uint layer, float v, bool on)
{
    float4 st = ptStep(l, i);
    if (layer == PT_E_STEPS) st = ptWithOn(st, on);
    else if (layer == PT_E_VEL) st.y = max(v, 0.02);
    else if (layer == PT_E_CHANCE) st.z = v;
    else if (layer == PT_E_RATCHET) st = ptWithRatchet(st, 1u + min((uint)(v * 4.0), 3u));
    else st.w = round((v - 0.5) * 20.0) / 20.0;           // nudge in twentieths of a step
    S[ptStepSlot(l, i)] = st;
}

// ---------------------------------------------------------------- the default pattern
// C major pentatonic, low to high; lengths 16 12 7 5 9 11 (they line up again every 55,440 steps).
void writeDefaults()
{
    static const float4 LANE[PT_LANES] = {          // (length, turn, note, hits)
        float4(16, 0, 48, 5), float4(12, 0, 55, 5), float4(7, 2, 64, 3),
        float4(5, 0, 69, 2), float4(9, 1, 74, 4), float4(11, 0, 79, 3) };
    static const float2 FEEL[PT_LANES] = {          // (velocity, chance)
        float2(0.80, 1.0), float2(0.62, 1.0), float2(0.55, 1.0),
        float2(0.50, 1.0), float2(0.46, 0.65), float2(0.42, 0.5) };
    [loop] for (uint i = 0u; i < PT_SAVED; i++) S[i] = 0.0;
    S[PT_P0] = float4(96.0, 0.56, 0.0, 0.0);
    S[PT_PM] = float4(PT_MAGIC, 0.0, 0.0, 0.0);
    [loop] for (uint l = 0u; l < PT_LANES; l++)
    {
        float4 d = LANE[l];
        S[PT_LA0 + l] = float4(d.xyz, 0.0);
        S[PT_LB0 + l] = float4(d.w, 0.0, 0.0, 0.0);
        uint n = (uint)d.x, k = (uint)d.w;
        [loop] for (uint j = 0u; j < PT_STEPS; j++)
            S[ptStepSlot(l, j)] = ptMakeStep(j < n && ptEuclid(j, k, n), 1u, FEEL[l].x * (j == 0u ? 1.15 : 1.0), FEEL[l].y, 0.0);
    }
    // a little feel: the bass leans back on its fourth hit, the top lane doubles its last and drags its middle
    S[ptStepSlot(0u, 7u)].w = 0.06;
    S[ptStepSlot(1u, 3u)].w = -0.06;
    S[ptStepSlot(5u, 8u)] = ptWithRatchet(S[ptStepSlot(5u, 8u)], 2u);
    S[ptStepSlot(5u, 4u)].w = 0.15;
}

float wrapPi(float a) { return a - 6.2831853 * floor((a + 3.1415927) / 6.2831853); }
// a whole number (above -4096 n) brought into 0..n-1, in integers (t / n is not exact on the GPU)
float wrapN(float t, float n) { uint ni = max((uint)n, 1u); return (float)((uint)(t + (float)(ni * 4096u)) % ni); }

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    float2 res = _Resolution.xy;
    float s = ilCtx(res).s;
    float dt = clamp(_DeltaTime, 0.0, 0.1);

    if (S[PT_PM].x != PT_MAGIC)
    {
        // nothing saved yet (or another format): the default pattern
        writeDefaults();
        S[PT_U0] = 0.0;
        S[PT_V0] = 0.0;
    }
    float4 v0 = S[PT_V0], v1 = S[PT_V1], v2 = S[PT_V2], v3 = S[PT_V3], v4 = S[PT_V4], v5 = S[PT_V5], v6 = S[PT_V6], v7 = S[PT_V7], v8 = S[PT_V8];
    if (v0.w != PT_VMAGIC)
    {
        // working state is never saved: fresh after a reopen or a preset recall
        v0 = float4(1.0, 0.0, 0.0, PT_VMAGIC);          // playing from the top
        v1 = 0.0;
        v2 = 0.0;
        v3 = 0.0;
        v4 = 0.0;
        v5 = 0.0;
        v6 = float4(0.62, 0.70, 0.0, 0.0);
        v7 = 0.0;
        v8 = 0.0;
        [loop] for (uint h = 0u; h < PT_HISTN; h++) S[PT_HIST0 + h] = float4(0.0, 0.0, -1.0, 0.0);
    }
    bool playing = v0.x > 0.5;
    float nowW = v0.y, nowF = v0.z;
    g_lane = min((uint)v3.x, PT_LANES - 1u);
    g_step = (uint)v3.y;
    uint layer = min((uint)v3.z, 4u);
    float paintV = v3.w;
    uint mode = (uint)v1.z, target = (uint)v1.w;
    float2 press = v2.xy;
    bool spaceHeld = v6.z > 0.5;
    bool restart = false;                                // the clock jumped: send from now
    bool rewound = false;                                // back to the top: the history no longer applies
    PtLayout L = ptLayout(res, s, v6.xy);

    // 1. the events
    uint lastSeq = ilEvWatermark((uint)v1.x | ((uint)v1.y << 16));
    uint newest = lastSeq;
    uint ne = ilEvCount();
    [loop] for (uint ei = 0u; ei < ne; ei++)
    {
        ViewportEvent e = _ViewportEvents[ei];
        if (!ilEvFresh(e.sequence, lastSeq)) continue;
        newest = ilEvAdvance(newest, lastSeq, e.sequence);
        float2 px = ilEvPx(e, res);
        if (e.type == IL_EV_MOVE) continue;
        if (ilIsPress(e, IL_BTN_LEFT)) press = px;

        if (ilIsDrag(e))
        {
            if (e.phase == IL_PH_BEGIN)
            {
                mode = DM_NONE;
                uint2 cell = ptCellAt(L, press);
                uint ring = ptRingAt(L, press);
                uint bracket = 0xFFFFu;
                [loop] for (uint bl = 0u; bl < PT_LANES; bl++) if (ptHitBracket(L, bl, press, s)) bracket = bl;
                if (ilIn(press, L.gripX)) mode = DM_SPLITX;
                else if (ilIn(press, L.gripY)) mode = DM_SPLITY;
                else if (bracket != 0xFFFFu)
                {
                    snapshot();
                    mode = DM_LEN;
                    target = bracket;
                    g_lane = bracket;
                }
                else if (cell.x != 0xFFFFu && cell.y < ptLen(cell.x))
                {
                    snapshot();
                    mode = DM_PAINT;
                    target = cell.x;
                    g_lane = cell.x;
                    g_step = cell.y;
                    float v = ptRowValue(L, cell.x, press.y, s);
                    bool on = !ptOn(ptStep(cell.x, cell.y));
                    paintV = (layer == PT_E_STEPS) ? (on ? 1.0 : 0.0) : v;
                    paintStep(cell.x, cell.y, layer, v, on);
                    v5 = float4((float)cell.y, 0.0, 0.0, 0.0);
                }
                else if (ring != 0xFFFFu)
                {
                    snapshot();
                    mode = DM_RING;
                    target = ring;
                    g_lane = ring;
                    float a = ptAngleAt(L, press);
                    v5 = float4((float)ptTurn(ring), a, 0.0, 0.0);      // turn at the press, last angle, turned so far
                }
                else
                {
                    [loop] for (uint f = 0u; f <= PT_F_SWING; f++)
                    {
                        if (!ilIn(press, ptField(L, f, s))) continue;
                        snapshot();
                        mode = DM_FIELD;
                        target = f;
                        float fv = 0.0;
                        if (f == PT_F_NOTE) fv = (float)ptNote(g_lane);
                        else if (f == PT_F_LEN) fv = (float)ptLen(g_lane);
                        else if (f == PT_F_TURN) fv = (float)ptTurn(g_lane);
                        else if (f == PT_F_HITS) fv = (float)ptHits(g_lane);
                        else if (f == PT_F_VEL) fv = ptStep(g_lane, g_step).y;
                        else if (f == PT_F_CHANCE) fv = ptStep(g_lane, g_step).z;
                        else if (f == PT_F_NUDGE) fv = ptStep(g_lane, g_step).w;
                        else if (f == PT_F_BPM) fv = ptBpm();
                        else fv = ptSwing();
                        v5 = float4(fv, 0.0, 0.0, 0.0);
                    }
                }
            }
            if (ilIsCancel(e))
            {
                if (mode == DM_PAINT || mode == DM_LEN || mode == DM_RING || mode == DM_FIELD) restoreSnapshot();
                mode = DM_NONE;
                continue;
            }
            v2.zw = px;
            float dx = (px.x - press.x) / s;
            if (mode == DM_SPLITX) v6.x = ilSplitXValue(L.upper, px.x, PT_GAP * s);
            else if (mode == DM_SPLITY)
            {
                float4 rest = float4(L.inner.x, L.tools.w + 12.0 * s, L.inner.z, L.inner.w);
                v6.y = ilSplitYValue(rest, px.y, PT_GAP * s);
            }
            else if (mode == DM_LEN) setLaneField(target, 0u, (float)clamp((int)round((px.x - L.cells.x) / L.colW), 1, (int)PT_STEPS));
            else if (mode == DM_PAINT)
            {
                // every step between the last painted one and the pointer's, so a fast drag skips none
                uint n = ptLen(target);
                int c = clamp((int)floor((px.x - L.cells.x) / L.colW), 0, (int)n - 1);
                int last = (int)v5.x;
                float v = ptRowValue(L, target, px.y, s);
                int dir = (c >= last) ? 1 : -1;
                [loop] for (uint t = 0u; t <= (uint)abs(c - last); t++)
                    paintStep(target, (uint)(last + dir * (int)t), layer, (layer == PT_E_STEPS) ? 0.0 : v, paintV > 0.5);
                v5.x = (float)c;
                g_step = (uint)c;
            }
            else if (mode == DM_RING)
            {
                restoreSnapshot();
                float a = ptAngleAt(L, px);
                v5.z += wrapPi(a - v5.y);                // accumulated, so it can go round more than once
                v5.y = a;
                float n = (float)ptLen(target);
                setLaneField(target, 1u, wrapN(v5.x + round(v5.z / 6.2831853 * n), n));
            }
            else if (mode == DM_FIELD)
            {
                restoreSnapshot();
                float4 st = ptStep(g_lane, g_step);
                if (target == PT_F_NOTE) setLaneField(g_lane, 2u, clamp(round(v5.x + dx / 8.0), 0.0, 127.0));
                else if (target == PT_F_LEN) setLaneField(g_lane, 0u, clamp(round(v5.x + dx / 14.0), 1.0, (float)PT_STEPS));
                else if (target == PT_F_TURN)
                {
                    setLaneField(g_lane, 1u, wrapN(round(v5.x + dx / 14.0), (float)ptLen(g_lane)));
                }
                else if (target == PT_F_HITS) spread(g_lane, (uint)clamp(round(v5.x + dx / 14.0), 0.0, (float)ptLen(g_lane)));
                else if (target == PT_F_VEL) { st.y = saturate(v5.x + dx * 0.004); S[ptStepSlot(g_lane, g_step)] = st; }
                else if (target == PT_F_CHANCE) { st.z = saturate(v5.x + dx * 0.004); S[ptStepSlot(g_lane, g_step)] = st; }
                else if (target == PT_F_NUDGE) { st.w = clamp(round((v5.x + dx * 0.002) * 100.0) / 100.0, -0.5, 0.5); S[ptStepSlot(g_lane, g_step)] = st; }
                else if (target == PT_F_BPM) S[PT_P0] = float4(clamp(round((v5.x + dx * 0.25) * 2.0) / 2.0, 30.0, 300.0), S[PT_P0].yzw);
                else S[PT_P0] = float4(S[PT_P0].x, clamp(round((v5.x + dx * 0.001) * 100.0) / 100.0, 0.5, 0.75), S[PT_P0].zw);
            }
            if (e.phase == IL_PH_END) mode = DM_NONE;
        }
        else if (ilIsClick(e))
        {
            uint2 cell = ptCellAt(L, px);
            uint ring = ptRingAt(L, px);
            if (ilIn(px, ptLayers(L, s)))
            {
                float4 r = ptLayers(L, s);
                layer = min((uint)((px.x - r.x) / ((r.z - r.x) / 5.0)), 4u);
            }
            else if (ilIn(px, ptPlayChip(L, s))) { playing = !playing; restart = true; }
            else if (cell.x != 0xFFFFu)
            {
                g_lane = cell.x;
                if (cell.y < ptLen(cell.x))
                {
                    g_step = cell.y;
                    snapshot();
                    paintStep(cell.x, cell.y, layer, ptRowValue(L, cell.x, px.y, s), !ptOn(ptStep(cell.x, cell.y)));
                }
            }
            else if (px.x < L.cells.x && px.y >= L.cells.y && px.y < L.cells.y + PT_LANES * L.rowH)
            {
                uint l = min((uint)((px.y - L.cells.y) / L.rowH), PT_LANES - 1u);
                g_lane = l;
                if (ilIn(px, ptMuteChip(L, l, s))) { snapshot(); setFlag(l, 1u, !ptMute(l)); }
                else if (ilIn(px, ptSoloChip(L, l, s))) { snapshot(); setFlag(l, 2u, !ptSolo(l)); }
            }
            else if (ring != 0xFFFFu)
            {
                uint i = ptRingStepAt(L, ring, px, 0.5 * ptRingW(L) + 2.0 * s);
                g_lane = ring;
                if (i != 0xFFFFu)
                {
                    g_step = i;
                    snapshot();
                    S[ptStepSlot(ring, i)] = ptWithOn(ptStep(ring, i), !ptOn(ptStep(ring, i)));
                }
            }
            else if (ilIn(px, ptLaneChip(L, 0u, s))) { snapshot(); setFlag(g_lane, 1u, !ptMute(g_lane)); }
            else if (ilIn(px, ptLaneChip(L, 1u, s))) { snapshot(); setFlag(g_lane, 2u, !ptSolo(g_lane)); }
            else if (ilIn(px, ptRatchets(L, s)))
            {
                float4 r = ptRatchets(L, s);
                snapshot();
                S[ptStepSlot(g_lane, g_step)] = ptWithRatchet(ptStep(g_lane, g_step), 1u + min((uint)((px.x - r.x) / ((r.z - r.x) / 4.0)), 3u));
            }
        }
        else if (e.type == IL_EV_KEY)
        {
            bool down = e.phase == IL_PH_PRESS && !ilRepeat(e);
            bool downOrRepeat = e.phase == IL_PH_PRESS || e.phase == IL_PH_REPEAT;
            if (ilLatch(e, IL_KEY_SPACE, spaceHeld)) { playing = !playing; restart = true; }
            if (down && e.code == IL_KEY_0) { nowW = 0.0; nowF = 0.0; restart = true; rewound = true; }
            if (down && e.code >= IL_KEY_0 + 1u && e.code <= IL_KEY_0 + 5u) layer = e.code - IL_KEY_0 - 1u;
            if (down && e.code == IL_KEY_TAB) g_lane = (g_lane + 1u) % PT_LANES;
            if (downOrRepeat && e.code == IL_KEY_UP) g_lane = (g_lane + PT_LANES - 1u) % PT_LANES;
            if (downOrRepeat && e.code == IL_KEY_DOWN) g_lane = (g_lane + 1u) % PT_LANES;
            if (downOrRepeat && e.code == IL_KEY_LEFT) g_step = (min(g_step, ptLen(g_lane) - 1u) + ptLen(g_lane) - 1u) % ptLen(g_lane);
            if (downOrRepeat && e.code == IL_KEY_RIGHT) g_step = (min(g_step, ptLen(g_lane) - 1u) + 1u) % ptLen(g_lane);
            if (down && e.code == IL_KEY_ENTER)
            {
                uint i = min(g_step, ptLen(g_lane) - 1u);
                snapshot();
                S[ptStepSlot(g_lane, i)] = ptWithOn(ptStep(g_lane, i), !ptOn(ptStep(g_lane, i)));
            }
            if (down && e.code == IL_KEY_E) { snapshot(); spread(g_lane, onCount(g_lane)); }
            if (down && e.code == IL_KEY_M) { snapshot(); setFlag(g_lane, 1u, !ptMute(g_lane)); }
            if (down && e.code == IL_KEY_S) { snapshot(); setFlag(g_lane, 2u, !ptSolo(g_lane)); }
            if (down && e.code == IL_KEY_BACKSPACE)
            {
                snapshot();
                [loop] for (uint i = 0u; i < PT_STEPS; i++) S[ptStepSlot(g_lane, i)] = ptWithOn(ptStep(g_lane, i), false);
                S[PT_LB0 + g_lane] = 0.0;
            }
            if (down && e.code == IL_KEY_Z) swapUndo();
            if (down && e.code == IL_KEY_R) { snapshot(); writeDefaults(); }
        }
    }
    g_step = min(g_step, ptLen(g_lane) - 1u);

    // 2. the clock, and every hit due in [sent, now + lookahead) out on EventOut "Hits"
    float sps = ptStepsPerSec();
    float adv = playing ? dt * sps : 0.0;
    if (playing)
    {
        nowF += adv;
        float w = floor(nowF);
        nowW += w;
        nowF -= w;
    }
    float sentW = v4.x, sentF = v4.y;
    uint head = (uint)v4.z % PT_HISTN;
    if (nowW > 8000000.0)
    {
        // far along: step back a whole number of double cycles (every lane's phase and the swing kept)
        uint lcm2 = 2u * ptLcm();
        float back = (float)(((uint)nowW / lcm2) * lcm2);
        nowW -= back;
        sentW -= back;
        [loop] for (uint h = 0u; h < PT_HISTN; h++) S[PT_HIST0 + h].x -= back;
    }
    float look = PT_LOOKAHEAD * sps;
    float endF = nowF + look, endW = nowW + floor(endF);
    endF -= floor(endF);
    if (!playing || restart) { sentW = nowW; sentF = nowF; }
    if (rewound) { [loop] for (uint h = 0u; h < PT_HISTN; h++) S[PT_HIST0 + h] = float4(0.0, 0.0, -1.0, 0.0); }
    if (playing)
    {
        float r0 = max((sentW - nowW) + (sentF - nowF), -2.0);   // never reach back more than 2 steps
        float r1 = (endW - nowW) + (endF - nowF);
        bool anySolo = ptAnySolo();
        float swing = (ptSwing() - 0.5) * 2.0;
        int j0 = (int)floor(r0) - 2, j1 = (int)ceil(r1) + 1;
        [loop] for (int j = j0; j <= j1; j++)
        {
            float k = nowW + (float)j;
            if (k < 0.0) continue;
            bool odd = (((uint)k) & 1u) != 0u;
            [loop] for (uint l = 0u; l < PT_LANES; l++)
            {
                if (!ptAudible(l, anySolo)) continue;
                float4 st = ptStep(l, ptLaneStep(l, k));
                if (!ptOn(st)) continue;
                uint rc = ptRatchet(st);
                [loop] for (uint r = 0u; r < rc; r++)
                {
                    float off = (odd ? swing : 0.0) + st.w + (float)r / (float)rc;
                    float rel = (float)j + off - nowF;           // steps from now
                    if (rel < r0 || rel >= r1) continue;
                    bool play = ptRoll(l, k, r) < st.z;
                    float vel = saturate(st.y * (1.0 - 0.18 * (float)r));
                    if (play)
                    {
                        GPUEventRecord ev;
                        ev.event_type = PT_EV_HIT;
                        ev.payload = float4((float)(l * 128u + ptNote(l)), clamp(round(vel * 127.0), 1.0, 127.0), max(rel, 0.0) / sps, (float)r);
                        ev.sub_step = 0u;
                        ev.sub_step_fraction = 0.0;
                        ev.sub_step_count = 1u;
                        EventOut0.Append(ev);
                    }
                    uint flags = (play ? PT_H_PLAYED : PT_H_DROPPED) | (r > 0u ? PT_H_RATCHET : 0u);
                    S[PT_HIST0 + head] = float4(k, off, (float)(l + 8u * flags), vel);
                    head = (head + 1u) % PT_HISTN;
                }
            }
        }
        sentW = endW;
        sentF = endF;
    }

    // 3. the envelopes: a lane's rises to a hit's velocity as the hit sounds (when now crosses it).
    // The rate: the hits that sounded in the last bar (16 steps; less if the history is full), per
    // second - counted, not smoothed, so it reads steady and true.
    float4 envA = v7 * exp(-dt / 0.22);
    float2 envB = v8.xy * exp(-dt / 0.22);
    uint inBar = 0u;
    float oldest = 0.0;
    [loop] for (uint h = 0u; h < PT_HISTN; h++)
    {
        float4 hr = S[PT_HIST0 + h];
        if (hr.z < 0.0) continue;
        uint flags = (uint)hr.z / 8u, l = (uint)hr.z % 8u;
        float rel = (hr.x - nowW) + (hr.y - nowF);
        oldest = min(oldest, rel);
        if ((flags & PT_H_PLAYED) == 0u || rel > 0.0) continue;
        if (rel > -16.0) inBar++;
        if (rel <= -adv || adv <= 0.0) continue;
        bool4 at = uint4(0u, 1u, 2u, 3u) == l.xxxx;
        envA = at ? max(envA, hr.w) : envA;
        bool2 bt = uint2(4u, 5u) == l.xx;
        envB = bt ? max(envB, hr.w) : envB;
    }
    bool full = S[PT_HIST0 + head].z >= 0.0;            // the oldest entry is about to be overwritten
    float span = full ? clamp(-oldest, 1.0, 16.0) : 16.0;
    float rate = playing ? (float)inBar / (span / sps) : 0.0;

    S[PT_V0] = float4(playing ? 1.0 : 0.0, nowW, nowF, PT_VMAGIC);
    S[PT_V1] = float4((float)(newest & 0xFFFFu), (float)(newest >> 16), (float)mode, (float)target);
    S[PT_V2] = float4(press, v2.zw);
    S[PT_V3] = float4((float)g_lane, (float)g_step, (float)layer, paintV);
    S[PT_V4] = float4(sentW, sentF, (float)head, v4.w + 1.0);
    S[PT_V5] = v5;
    S[PT_V6] = float4(v6.xy, spaceHeld ? 1.0 : 0.0, 0.0);
    S[PT_V7] = envA;
    S[PT_V8] = float4(envB, rate, 0.0);
}
