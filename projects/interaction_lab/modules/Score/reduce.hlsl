// Score / reduce - one thread, every cook: the viewport events edit the show; the transport moves the
// playhead; the playhead resolves to the act showing (and the one it hands off to), a camera and a
// light, written for the program and the control outputs; the working state is written back.
//
//   ACTS      drag an act: reorder it (applied on release)   drag its right edge: its length
//             click it: select it   click / drag the ruler: scrub   drag a mark's tick: when it comes
//             double-click a rail: a mark at that moment
//   SPACE     rails: drag a mark's eye (square) or aim (ring) in the plan (x, z) or the elevation
//             (height, z); click one to select it - the playhead moves to it, so the view looks
//             through it; double-click the rail for a new mark there
//             cards: drag the word, the disc or the bar, or the corner of the selected one for size
//   VIEW      drag: turn the selected mark's aim about its eye
//   MARK      drag at, fov, eye x / y / z, aim x / y / z      ITEM  drag x, y, size; SHOWN
//   ACT       click kind, hand-off, light (rails) or the word (cards); drag length, hand-off length
//   TOOLS     PLAY; loop the show or the selected act
//   KEYS      Space play   0 to the top   Left / Right act   Up / Down mark or item   A add a mark
//             Backspace delete the mark (or, with none selected, the act)   D duplicate the act
//             K kind   H hand-off   L light (rails) or word (cards)   R the default show (Z brings
//             yours back)   Z undo (again: redo)
#define SC_STATE_RW
#include "../_shared/ui/il_core.hlsli"
#include "../_shared/ui/il_events.hlsli"
#include "../_shared/ui/il_pane.hlsli"
#include "sc.hlsli"

static uint g_act;           // the selected act
static int  g_sel;           // its selected mark (rails) or item (cards), -1 for none

// ---------------------------------------------------------------- undo
void snapshot()
{
    [loop] for (uint i = 0u; i < SC_SAVED; i++) S[SC_UNDO0 + i] = S[i];
    S[SC_U0] = float4(1.0, 0.0, 0.0, 0.0);
}
void restoreSnapshot() { [loop] for (uint i = 0u; i < SC_SAVED; i++) S[i] = S[SC_UNDO0 + i]; }
void swapUndo()
{
    if (S[SC_U0].x < 0.5) return;
    [loop] for (uint i = 0u; i < SC_SAVED; i++)
    {
        float4 a = S[i];
        S[i] = S[SC_UNDO0 + i];
        S[SC_UNDO0 + i] = a;
    }
}

// ---------------------------------------------------------------- writing acts
void setActA(uint a, uint comp, float v) { bool4 at = uint4(0u, 1u, 2u, 3u) == comp.xxxx; S[scActRec(a)] = at ? v.xxxx : S[scActRec(a)]; }
void setActB(uint a, uint comp, float v) { bool4 at = uint4(0u, 1u, 2u, 3u) == comp.xxxx; S[scActRec(a) + 1u] = at ? v.xxxx : S[scActRec(a) + 1u]; }
void writeMark(uint a, uint m, float3 eye, float at, float3 aim, float fov)
{
    S[scMarkRec(a, m)] = float4(eye, at);
    S[scMarkRec(a, m) + 1u] = float4(aim, fov);
}
void writeItem(uint a, uint k, float2 q, float size)
{
    S[scMarkRec(a, k)] = float4(q, size, 1.0);
    S[scMarkRec(a, k) + 1u] = 0.0;
}
void clearSlots(uint a, uint from)
{
    [loop] for (uint m = from; m < SC_MARKS; m++) { S[scMarkRec(a, m)] = 0.0; S[scMarkRec(a, m) + 1u] = 0.0; }
}
// a card's things: its word over a bar, a disc at the bar's end
void cardItems(uint a)
{
    writeItem(a, 0u, float2(0.0, 0.05), 0.105);
    writeItem(a, 1u, float2(0.33, -0.115), 0.028);
    writeItem(a, 2u, float2(0.0, -0.115), 0.27);
    clearSlots(a, 3u);
}
// a plain dolly down the middle of the hall
void railMarks(uint a)
{
    writeMark(a, 0u, float3(0.0, 1.7, 2.0), 0.0, float3(0.0, 1.6, 16.0), 50.0);
    writeMark(a, 1u, float3(0.0, 1.7, 9.0), 1.0, float3(0.0, 1.6, 22.0), 44.0);
    clearSlots(a, 2u);
    setActB(a, 2u, 2.0);
}

// The default show: a title card, a walk in to the sphere, a long orbit of it, a crane up the ring
// to look down the whole hall at night, and a closing card. 36 s; it loops.
void writeDefaults()
{
    [loop] for (uint i = 0u; i < SC_SAVED; i++) S[i] = 0.0;
    S[SC_P0] = float4(5.0, 0.0, 0.0, 0.0);
    S[SC_PM] = float4(SC_MAGIC, 0.0, 0.0, 0.0);
    // 0  card: THE HALL, on ink
    S[scActRec(0u)] = float4(SC_CARD, 4.0, SC_DIP, 1.0);
    S[scActRec(0u) + 1u] = float4(SC_NIGHT, 0.0, 3.0, 0.0);
    cardItems(0u);
    // 1  rail, day: walk in down the middle, drifting left to meet the sphere
    S[scActRec(1u)] = float4(SC_RAIL, 9.0, SC_GLIDE, 1.5);
    S[scActRec(1u) + 1u] = float4(SC_DAY, 0.0, 3.0, 0.0);
    writeMark(1u, 0u, float3(0.0, 1.65, -3.0), 0.0, float3(0.0, 1.55, 12.0), 48.0);
    writeMark(1u, 1u, float3(0.2, 1.70, 3.5), 0.45, float3(0.0, 1.60, 12.0), 45.0);
    writeMark(1u, 2u, float3(-1.2, 1.75, 7.6), 1.0, float3(0.0, 1.70, 12.0), 40.0);
    // 2  rail, dusk: once round the sphere, 2.6 m out, rising over its far side
    S[scActRec(2u)] = float4(SC_RAIL, 10.0, SC_CUT, 1.0);
    S[scActRec(2u) + 1u] = float4(SC_DUSK, 0.0, 5.0, 0.0);
    writeMark(2u, 0u, float3(-1.800, 3.0, 9.855), 0.0, float3(0.0, 1.65, 12.0), 46.0);
    writeMark(2u, 1u, float3(1.184, 3.4, 9.463), 0.25, float3(0.0, 1.65, 12.0), 45.0);
    writeMark(2u, 2u, float3(2.800, 3.5, 12.0), 0.5, float3(0.0, 1.65, 12.0), 44.0);
    writeMark(2u, 3u, float3(1.184, 3.1, 14.537), 0.75, float3(0.0, 1.65, 12.0), 43.0);
    writeMark(2u, 4u, float3(-1.800, 2.5, 14.145), 1.0, float3(0.0, 1.65, 12.0), 42.0);
    // 3  rail, night: low at the ring, then up past the columns to look down the hall
    S[scActRec(3u)] = float4(SC_RAIL, 9.0, SC_DIP, 1.2);
    S[scActRec(3u) + 1u] = float4(SC_NIGHT, 0.0, 3.0, 0.0);
    writeMark(3u, 0u, float3(1.4, 0.55, 18.6), 0.0, float3(0.0, 2.1, 22.0), 44.0);
    writeMark(3u, 1u, float3(0.9, 3.8, 17.0), 0.45, float3(0.0, 2.0, 23.5), 46.0);
    writeMark(3u, 2u, float3(0.0, 10.5, 9.0), 1.0, float3(0.0, 0.5, 30.0), 52.0);
    // 4  card: FINALE, on paper
    S[scActRec(4u)] = float4(SC_CARD, 4.0, SC_DIP, 1.0);
    S[scActRec(4u) + 1u] = float4(SC_DAY, 4.0, 3.0, 0.0);
    cardItems(4u);
}

// ---------------------------------------------------------------- marks
// insert a mark at `at` (0..1) on rail a, in time order; returns its index (or -1 when full)
int insertMark(uint a, float at, ScPose p)
{
    uint n = scMarkN(a);
    int r = -1;
    if (n < SC_MARKS)
    {
        at = clamp(at, 0.01, 0.99);
        uint i = n;
        [loop] for (uint m = 0u; m < SC_MARKS; m++) i = (m < n && scEyeRec(a, m).w > at && i == n) ? m : i;
        [loop] for (int j = (int)n; j > (int)i; j--)
        {
            S[scMarkRec(a, (uint)j)] = S[scMarkRec(a, (uint)j - 1u)];
            S[scMarkRec(a, (uint)j) + 1u] = S[scMarkRec(a, (uint)j - 1u) + 1u];
        }
        writeMark(a, i, p.eye, at, p.target, p.fov);
        setActB(a, 2u, (float)(n + 1u));
        r = (int)i;
    }
    return r;
}
void deleteMark(uint a, uint m)
{
    uint n = scMarkN(a);
    if (n <= 2u || m >= n) return;
    [loop] for (uint j = m; j + 1u < n; j++)
    {
        S[scMarkRec(a, j)] = S[scMarkRec(a, j + 1u)];
        S[scMarkRec(a, j) + 1u] = S[scMarkRec(a, j + 1u) + 1u];
    }
    S[scMarkRec(a, n - 1u)] = 0.0;
    S[scMarkRec(a, n - 1u) + 1u] = 0.0;
    setActB(a, 2u, (float)(n - 1u));
}
// the first and the last mark sit at the ends of the act; the rest keep their order
float2 atBounds(uint a, uint m)
{
    uint n = scMarkN(a);
    float lo = (m == 0u) ? 0.0 : scEyeRec(a, m - 1u).w + 0.01;
    float hi = (m + 1u >= n) ? 1.0 : scEyeRec(a, m + 1u).w - 0.01;
    return float2(lo, max(hi, lo));
}

// ---------------------------------------------------------------- acts
void copyAct(uint from, uint to)
{
    [loop] for (uint i = 0u; i < SC_ACTREC; i++) S[scActRec(to) + i] = S[scActRec(from) + i];
}
// the act at `from` (in the undo snapshot, taken when the drag began) moved to `to`
void moveAct(uint from, uint to)
{
    uint n = scActs();
    [loop] for (uint d = 0u; d < SC_ACTS; d++)
    {
        if (d >= n) continue;
        uint w = (d < to) ? d : d - 1u;                   // index in the list without the moved act
        uint src = (d == to) ? from : ((w < from) ? w : w + 1u);
        [loop] for (uint i = 0u; i < SC_ACTREC; i++) S[scActRec(d) + i] = S[SC_UNDO0 + scActRec(src) + i];
    }
}
void duplicateAct(uint a)
{
    uint n = scActs();
    if (n >= SC_ACTS) return;
    [loop] for (int d = (int)n; d > (int)a; d--) copyAct((uint)d - 1u, (uint)d);
    S[SC_P0] = float4((float)(n + 1u), 0.0, 0.0, 0.0);
}
void deleteAct(uint a)
{
    uint n = scActs();
    if (n <= 1u) return;
    [loop] for (uint d = a; d + 1u < n; d++) copyAct(d + 1u, d);
    [loop] for (uint i = 0u; i < SC_ACTREC; i++) S[scActRec(n - 1u) + i] = 0.0;
    S[SC_P0] = float4((float)(n - 1u), 0.0, 0.0, 0.0);
}
// a new kind gets fresh things to edit; the length, hand-off and light stay
void setKind(uint a, uint k)
{
    if (scKind(a) == k) return;
    setActA(a, 0u, (float)k);
    if (k == SC_CARD) { cardItems(a); setActB(a, 1u, (float)(a % SC_WORDS)); setActB(a, 2u, 3.0); }
    else railMarks(a);
}

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    float2 res = _Resolution.xy;
    float s = ilCtx(res).s;
    float dt = clamp(_DeltaTime, 0.0, 0.1);

    if (S[SC_PM].x != SC_MAGIC)
    {
        writeDefaults();
        S[SC_U0] = 0.0;
        S[SC_V0] = 0.0;
    }
    float4 v0 = S[SC_V0], v1 = S[SC_V1], v2 = S[SC_V2], v3 = S[SC_V3], v4 = S[SC_V4], v5 = S[SC_V5], v6 = S[SC_V6];
    if (v0.w != SC_VMAGIC)
    {
        // working state is never saved: fresh after a reopen or a preset recall
        v0 = float4(0.0, 1.0, 0.0, SC_VMAGIC);           // playing the show from the top
        v1 = 0.0;
        v2 = 0.0;
        v3 = float4(1.0, -1.0, 0.0, 0.0);                // the first rail selected
        v4 = float4(0.56, 0.60, 0.0, 0.0);
        v5 = 0.0;
        v6 = 0.0;
    }
    float time = v0.x;
    bool playing = v0.y > 0.5;
    uint loopMode = (uint)v0.z;
    uint mode = (uint)v1.z, target = (uint)v1.w;
    float2 press = v2.xy;
    g_act = min((uint)v3.x, scActs() - 1u);
    g_sel = (int)v3.y;
    bool spaceHeld = v3.z > 0.5;
    float frozen = v4.z;
    ScLayout L = scLayout(res, s, v4.xy);

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
        bool rail = scKind(g_act) == SC_RAIL;
        uint n = scActs();
        float secs = scLaneSecs(frozen);

        if (ilIsDrag(e))
        {
            if (e.phase == IL_PH_BEGIN)
            {
                mode = DM_NONE;
                frozen = scLaneSecs(0.0);
                secs = frozen;
                uint hitAct = scActAtX(L, secs, press.x);
                // the right edge of an act (6 px either side)
                uint edge = 0xFFFFu;
                float te = 0.0;
                [loop] for (uint a = 0u; a < SC_ACTS; a++)
                {
                    te += (a < n) ? scDur(a) : 0.0;
                    edge = (a < n && abs(press.x - scTX(L, secs, te)) < 6.0 * s && press.y >= L.lane.y && press.y <= L.lane.w) ? a : edge;
                }
                // a mark's tick (the selected rail's)
                int tick = -1;
                if (rail && ilIn(press, scTickBand(L, s)))
                {
                    float t0 = scStart(g_act);
                    [loop] for (uint m = 0u; m < SC_MARKS; m++)
                        tick = (m < scMarkN(g_act) && abs(press.x - scTX(L, secs, t0 + saturate(scEyeRec(g_act, m).w) * scDur(g_act))) < 6.0 * s) ? (int)m : tick;
                }
                // a mark's eye or aim in the plan or the elevation
                int markHit = -1;
                uint markMode = DM_NONE;
                if (rail)
                {
                    float best = 9.0 * s;
                    [loop] for (uint m = 0u; m < SC_MARKS; m++)
                    {
                        if (m >= scMarkN(g_act)) continue;
                        float4 er = scEyeRec(g_act, m), ar = scAimRec(g_act, m);
                        float d0 = length(press - scPlanP(L, er.x, er.z));
                        float d1 = length(press - scPlanP(L, ar.x, ar.z));
                        float d2 = length(press - scElevP(L, er.y, er.z));
                        float d3 = length(press - scElevP(L, ar.y, ar.z));
                        if (d0 < best) { best = d0; markHit = (int)m; markMode = DM_EYE_P; }
                        if (d1 < best) { best = d1; markHit = (int)m; markMode = DM_AIM_P; }
                        if (d2 < best) { best = d2; markHit = (int)m; markMode = DM_EYE_E; }
                        if (d3 < best) { best = d3; markHit = (int)m; markMode = DM_AIM_E; }
                    }
                }
                // a card item, or the selected one's size handle
                int itemHit = -1;
                bool sizeHit = false;
                if (!rail && ilIn(press, ilInset(L.stage, -8.0 * s)))
                {
                    uint word = scWord(g_act);
                    if (g_sel >= 0 && scItem(g_act, (uint)g_sel).w > 0.5 && length(press - scItemHandle(L, (uint)g_sel, scItem(g_act, (uint)g_sel), word)) < 8.0 * s)
                    {
                        itemHit = g_sel;
                        sizeHit = true;
                    }
                    else
                    {
                        [loop] for (uint k = 0u; k < SC_ITEMS; k++)
                            itemHit = (scItem(g_act, k).w > 0.5 && scItemHit(L, k, scItem(g_act, k), word, press, s)) ? (int)k : itemHit;
                    }
                }

                if (ilIn(press, L.gripX)) mode = DM_SPLITX;
                else if (ilIn(press, L.gripY)) mode = DM_SPLITY;
                else if (scInScrub(L, press, s))
                {
                    mode = DM_SCRUB;
                    playing = false;
                }
                else if (edge != 0xFFFFu)
                {
                    mode = DM_RESIZE;
                    target = edge;
                    g_act = edge;
                }
                else if (tick >= 0)
                {
                    mode = DM_TICK;
                    target = (uint)tick;
                    g_sel = tick;
                }
                else if (hitAct != 0xFFFFu && ilIn(press, L.lane))
                {
                    mode = DM_MOVEACT;
                    target = hitAct;
                    g_act = hitAct;
                    g_sel = -1;
                    v5 = float4((float)hitAct, (float)hitAct, 0.0, 0.0);
                }
                else if (markHit >= 0)
                {
                    mode = markMode;
                    target = (uint)markHit;
                    g_sel = markHit;
                    float4 er = scEyeRec(g_act, (uint)markHit), ar = scAimRec(g_act, (uint)markHit);
                    float2 pw = (mode == DM_EYE_P || mode == DM_AIM_P) ? scPlanW(L, press) : scElevW(L, press);
                    float2 mw = (mode == DM_EYE_P) ? er.xz : ((mode == DM_AIM_P) ? ar.xz : ((mode == DM_EYE_E) ? er.yz : ar.yz));
                    v5 = float4(mw - pw, 0.0, 0.0);              // the grab offset, in metres
                }
                else if (itemHit >= 0)
                {
                    mode = sizeHit ? DM_ISIZE : DM_ITEM;
                    target = (uint)itemHit;
                    g_sel = itemHit;
                    float4 it = scItem(g_act, (uint)itemHit);
                    float2 c = scStageP(L, it.xy);
                    v5 = float4(it.xy - scStageQ(L, press), length(press - c), it.z);
                }
                else if (rail && g_sel >= 0 && ilIn(press, L.view))
                {
                    mode = DM_LOOK;
                    target = (uint)g_sel;
                }
                else
                {
                    [loop] for (uint f = 0u; f < F_COUNT; f++)
                    {
                        bool markField = f <= F_TZ && rail && g_sel >= 0;
                        bool itemField = f >= F_IX && f <= F_IS && !rail && g_sel >= 0;
                        bool actField = f >= F_DUR;
                        if (!(markField || itemField || actField) || !ilIn(press, scField(L, f, s))) continue;
                        mode = DM_FIELD;
                        target = f;
                    }
                }
                // an edit keeps the state it began from: the undo, and every update's origin
                if (mode != DM_NONE && mode != DM_SCRUB && mode != DM_SPLITX && mode != DM_SPLITY) snapshot();
            }
            if (ilIsCancel(e))
            {
                if (mode != DM_NONE && mode != DM_SCRUB && mode != DM_SPLITX && mode != DM_SPLITY) restoreSnapshot();
                mode = DM_NONE;
                frozen = 0.0;
                continue;
            }
            v2.zw = px;
            float2 dpx = px - press;
            float dx = dpx.x / s;
            if (mode == DM_SPLITX) v4.x = ilSplitXValue(L.upper, px.x, SC_GAP * s);
            else if (mode == DM_SPLITY) v4.y = ilSplitYValue(float4(L.inner.x, L.tools.w + 12.0 * s, L.inner.z, L.inner.w), px.y, SC_GAP * s);
            else if (mode == DM_SCRUB) time = clamp(scXT(L, secs, px.x), 0.0, max(scTotal() - 1e-3, 0.0));
            else if (mode == DM_RESIZE)
            {
                restoreSnapshot();
                float t0 = scStart(target);
                setActA(target, 1u, clamp(round((scXT(L, secs, px.x) - t0) * 2.0) * 0.5, 1.0, 30.0));
            }
            else if (mode == DM_TICK)
            {
                restoreSnapshot();
                float2 b = atBounds(g_act, target);
                float at = clamp((scXT(L, secs, px.x) - scStart(g_act)) / scDur(g_act), b.x, b.y);
                S[scMarkRec(g_act, target)] = float4(scEyeRec(g_act, target).xyz, at);
                time = scStart(g_act) + at * scDur(g_act);
                playing = false;
            }
            else if (mode == DM_MOVEACT)
            {
                // the drop: how many of the other acts' centres lie left of the pointer
                uint drop = 0u;
                float t0 = 0.0;
                [loop] for (uint a = 0u; a < SC_ACTS; a++)
                {
                    float d = (a < n) ? scDur(a) : 0.0;
                    drop += (a < n && a != target && scTX(L, secs, t0 + 0.5 * d) < px.x) ? 1u : 0u;
                    t0 += d;
                }
                v5.y = (float)drop;
            }
            else if (mode >= DM_EYE_P && mode <= DM_AIM_E)
            {
                restoreSnapshot();
                float4 er = scEyeRec(g_act, target), ar = scAimRec(g_act, target);
                bool planView = mode == DM_EYE_P || mode == DM_AIM_P;
                float2 w = (planView ? scPlanW(L, px) : scElevW(L, px)) + v5.xy;
                if (mode == DM_EYE_P) er.xz = w;
                else if (mode == DM_AIM_P) ar.xz = w;
                else if (mode == DM_EYE_E) er.yz = w;
                else ar.yz = w;
                er.xyz = scClampEye(er.xyz);
                ar.xyz = clamp(ar.xyz, float3(-20.0, -2.0, -20.0), float3(20.0, 20.0, 60.0));
                S[scMarkRec(g_act, target)] = er;
                S[scMarkRec(g_act, target) + 1u] = ar;
            }
            else if (mode == DM_LOOK)
            {
                restoreSnapshot();
                float4 er = scEyeRec(g_act, target), ar = scAimRec(g_act, target);
                float3 d = ar.xyz - er.xyz;
                float dist = max(length(d), 0.5);
                d /= dist;
                float k = radians(clamp(ar.w, 12.0, 100.0)) / max(L.view.w - L.view.y, 1.0);
                float yaw = atan2(d.x, d.z) + dpx.x * k;
                float pitch = clamp(asin(clamp(d.y, -0.999, 0.999)) - dpx.y * k, -1.45, 1.45);
                ar.xyz = er.xyz + dist * float3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch));
                S[scMarkRec(g_act, target) + 1u] = ar;
            }
            else if (mode == DM_ITEM)
            {
                restoreSnapshot();
                float4 it = scItem(g_act, target);
                it.xy = clamp(scStageQ(L, px) + v5.xy, float2(-0.86, -0.48), float2(0.86, 0.48));
                S[scMarkRec(g_act, target)] = it;
            }
            else if (mode == DM_ISIZE)
            {
                restoreSnapshot();
                float4 it = scItem(g_act, target);
                float2 c = scStageP(L, it.xy);
                it.z = clamp(v5.w * length(px - c) / max(v5.z, 4.0 * s), 0.01, 0.45);
                S[scMarkRec(g_act, target)] = it;
            }
            else if (mode == DM_FIELD)
            {
                restoreSnapshot();
                uint m = (uint)max(g_sel, 0);
                float4 er = scEyeRec(g_act, m), ar = scAimRec(g_act, m);
                float4 it = scItem(g_act, m);
                if (target == F_AT) { float2 b = atBounds(g_act, m); er.w = clamp(er.w + dx * 0.002, b.x, b.y); }
                else if (target == F_FOV) ar.w = clamp(round((ar.w + dx * 0.1) * 10.0) / 10.0, 12.0, 100.0);
                else if (target == F_EX) er.x += dx * 0.02;
                else if (target == F_EY) er.y += dx * 0.02;
                else if (target == F_EZ) er.z += dx * 0.02;
                else if (target == F_TX) ar.x += dx * 0.02;
                else if (target == F_TY) ar.y += dx * 0.02;
                else if (target == F_TZ) ar.z += dx * 0.02;
                else if (target == F_IX) it.x = clamp(it.x + dx * 0.002, -0.86, 0.86);
                else if (target == F_IY) it.y = clamp(it.y + dx * 0.002, -0.48, 0.48);
                else if (target == F_IS) it.z = clamp(it.z + dx * 0.0005, 0.01, 0.45);
                else if (target == F_DUR) setActA(g_act, 1u, clamp(round((scDur(g_act) + dx * 0.05) * 10.0) / 10.0, 1.0, 30.0));
                else setActA(g_act, 3u, clamp(round((scActA(g_act).w + dx * 0.01) * 20.0) / 20.0, 0.25, 4.0));
                if (target <= F_TZ)
                {
                    er.xyz = scClampEye(er.xyz);
                    S[scMarkRec(g_act, m)] = er;
                    S[scMarkRec(g_act, m) + 1u] = ar;
                    if (target == F_AT) { time = scStart(g_act) + er.w * scDur(g_act); playing = false; }
                }
                else if (target <= F_IS) S[scMarkRec(g_act, m)] = it;
            }
            if (e.phase == IL_PH_END)
            {
                if (mode == DM_MOVEACT)
                {
                    uint from = (uint)v5.x, to = min((uint)v5.y, n - 1u);
                    if (to != from) moveAct(from, to);
                    g_act = to;
                }
                mode = DM_NONE;
                frozen = 0.0;
            }
        }
        else if (ilIsDouble(e) && e.type == IL_EV_GESTURE)
        {
            // a new mark where the rail passes (the plan, the elevation) or at that moment (the lane)
            if (!rail) continue;
            float t0 = scStart(g_act), d = scDur(g_act);
            float bestT = -1.0, best = 10.0 * s;
            if (ilIn(px, L.lane))
            {
                float t = scXT(L, secs, px.x) - t0;
                bestT = (t > 0.0 && t < d) ? t : -1.0;
            }
            else if (ilIn(px, L.plan) || ilIn(px, L.elev))
            {
                [loop] for (uint i = 0u; i <= 96u; i++)
                {
                    float t = d * (float)i / 96.0;
                    ScPose p = scPose(g_act, t);
                    float dd = min(length(px - scPlanP(L, p.eye.x, p.eye.z)), length(px - scElevP(L, p.eye.y, p.eye.z)));
                    if (dd < best) { best = dd; bestT = t; }
                }
            }
            if (bestT >= 0.0)
            {
                snapshot();
                int m = insertMark(g_act, bestT / d, scPose(g_act, bestT));
                if (m >= 0) { g_sel = m; time = t0 + bestT; playing = false; }
            }
        }
        else if (ilIsClick(e))
        {
            uint hitAct = scActAtX(L, secs, px.x);
            if (ilIn(px, scPlayChip(L, s))) playing = !playing;
            else if (ilIn(px, scLoopSeg(L, s)))
            {
                float4 r = scLoopSeg(L, s);
                loopMode = (px.x < 0.5 * (r.x + r.z)) ? 0u : 1u;
            }
            else if (scInScrub(L, px, s)) { time = clamp(scXT(L, secs, px.x), 0.0, max(scTotal() - 1e-3, 0.0)); playing = false; }
            else if (rail && ilIn(px, scTickBand(L, s)) && hitAct == g_act)
            {
                float t0 = scStart(g_act);
                int tick = -1;
                [loop] for (uint m = 0u; m < SC_MARKS; m++)
                    tick = (m < scMarkN(g_act) && abs(px.x - scTX(L, secs, t0 + saturate(scEyeRec(g_act, m).w) * scDur(g_act))) < 6.0 * s) ? (int)m : tick;
                if (tick >= 0) { g_sel = tick; time = t0 + saturate(scEyeRec(g_act, (uint)tick).w) * scDur(g_act); playing = false; }
            }
            else if (hitAct != 0xFFFFu && ilIn(px, L.lane))
            {
                if (hitAct != g_act) g_sel = -1;
                g_act = hitAct;
            }
            else if (rail && (ilIn(px, ilInset(L.plan, -8.0 * s)) || ilIn(px, ilInset(L.elev, -8.0 * s))))
            {
                float best = 9.0 * s;
                int hit = -1;
                [loop] for (uint m = 0u; m < SC_MARKS; m++)
                {
                    if (m >= scMarkN(g_act)) continue;
                    float4 er = scEyeRec(g_act, m), ar = scAimRec(g_act, m);
                    float dd = min(min(length(px - scPlanP(L, er.x, er.z)), length(px - scPlanP(L, ar.x, ar.z))),
                                   min(length(px - scElevP(L, er.y, er.z)), length(px - scElevP(L, ar.y, ar.z))));
                    if (dd < best) { best = dd; hit = (int)m; }
                }
                g_sel = hit;
                if (hit >= 0) { time = scStart(g_act) + saturate(scEyeRec(g_act, (uint)hit).w) * scDur(g_act); playing = false; }
            }
            else if (!rail && ilIn(px, L.stage))
            {
                int hit = -1;
                [loop] for (uint k = 0u; k < SC_ITEMS; k++)
                    hit = (scItem(g_act, k).w > 0.5 && scItemHit(L, k, scItem(g_act, k), scWord(g_act), px, s)) ? (int)k : hit;
                g_sel = hit;
            }
            else if (!rail && g_sel >= 0 && ilIn(px, scShownChip(L, s)))
            {
                snapshot();
                float4 it = scItem(g_act, (uint)g_sel);
                it.w = (it.w > 0.5) ? 0.0 : 1.0;
                S[scMarkRec(g_act, (uint)g_sel)] = it;
            }
            else
            {
                // the ACT inspector's rows (a card has its word too)
                [loop] for (uint row = 0u; row < 4u; row++)
                {
                    if (row == 3u && rail) break;
                    float4 r = scActRow(L, row, s);
                    if (!ilIn(px, r)) continue;
                    uint nSeg = (row == 0u) ? 2u : 3u;
                    uint seg = min((uint)((px.x - r.x) / max((r.z - r.x) / (float)nSeg, 1.0)), nSeg - 1u);
                    snapshot();
                    if (row == 0u) { setKind(g_act, seg); g_sel = -1; }
                    else if (row == 1u) setActA(g_act, 2u, (float)seg);
                    else if (row == 2u) setActB(g_act, 0u, (float)seg);
                    else setActB(g_act, 1u, (float)((scWord(g_act) + 1u) % SC_WORDS));
                }
            }
        }
        else if (e.type == IL_EV_KEY)
        {
            bool down = e.phase == IL_PH_PRESS && !ilRepeat(e);
            bool downOrRepeat = e.phase == IL_PH_PRESS || e.phase == IL_PH_REPEAT;
            if (ilLatch(e, IL_KEY_SPACE, spaceHeld)) playing = !playing;
            if (down && e.code == IL_KEY_0) time = (loopMode == 1u) ? scStart(g_act) : 0.0;
            if (downOrRepeat && (e.code == IL_KEY_LEFT || e.code == IL_KEY_RIGHT))
            {
                g_act = (e.code == IL_KEY_LEFT) ? (g_act + n - 1u) % n : (g_act + 1u) % n;
                g_sel = -1;
                if (!playing) time = scStart(g_act);
            }
            if (downOrRepeat && (e.code == IL_KEY_UP || e.code == IL_KEY_DOWN))
            {
                uint cnt = rail ? scMarkN(g_act) : SC_ITEMS;
                bool fwd = e.code == IL_KEY_DOWN;
                uint nxt = (g_sel < 0) ? (fwd ? 0u : cnt - 1u) : ((uint)g_sel + (fwd ? 1u : cnt - 1u)) % cnt;
                g_sel = (int)nxt;
                if (rail && !playing) time = scStart(g_act) + saturate(scEyeRec(g_act, nxt).w) * scDur(g_act);
            }
            if (down && e.code == IL_KEY_A && rail)
            {
                uint cnt = scMarkN(g_act);
                uint m = (g_sel >= 0) ? (uint)g_sel : cnt - 1u;
                uint m0 = (m + 1u < cnt) ? m : m - 1u;               // between m and the next (the last: before it)
                float at = 0.5 * (scEyeRec(g_act, m0).w + scEyeRec(g_act, m0 + 1u).w);
                snapshot();
                int nm = insertMark(g_act, at, scPose(g_act, at * scDur(g_act)));
                if (nm >= 0) { g_sel = nm; if (!playing) time = scStart(g_act) + at * scDur(g_act); }
            }
            if (down && e.code == IL_KEY_BACKSPACE)
            {
                snapshot();
                if (rail && g_sel >= 0 && scMarkN(g_act) > 2u) { deleteMark(g_act, (uint)g_sel); g_sel = min(g_sel, (int)scMarkN(g_act) - 1); }
                else if (g_sel < 0) { deleteAct(g_act); g_act = min(g_act, scActs() - 1u); }
            }
            if (down && e.code == IL_KEY_D) { snapshot(); duplicateAct(g_act); g_act = min(g_act + 1u, scActs() - 1u); g_sel = -1; }
            if (down && e.code == IL_KEY_K) { snapshot(); setKind(g_act, 1u - scKind(g_act)); g_sel = -1; }
            if (down && e.code == IL_KEY_H) { snapshot(); setActA(g_act, 2u, (float)((scHand(g_act) + 1u) % 3u)); }
            if (down && e.code == IL_KEY_L) { snapshot(); setActB(g_act, 0u, (float)((scLight(g_act) + 1u) % 3u)); }
            if (down && e.code == IL_KEY_Z) swapUndo();
            if (down && e.code == IL_KEY_R) { snapshot(); writeDefaults(); g_act = 1u; g_sel = -1; }
        }
    }
    g_act = min(g_act, scActs() - 1u);
    uint selN = (scKind(g_act) == SC_RAIL) ? scMarkN(g_act) : SC_ITEMS;
    g_sel = (g_sel >= (int)selN) ? -1 : g_sel;

    // 2. the transport: the show loops, or the selected act does
    float total = scTotal();
    if (playing && mode != DM_SCRUB) time += dt;
    float lo = (loopMode == 1u) ? scStart(g_act) : 0.0;
    float span = (loopMode == 1u) ? scDur(g_act) : total;
    if (time >= lo + span || time < lo) time = lo + (time - lo) - span * floor((time - lo) / max(span, 1e-3));

    // 3. what the playhead resolves to (sc.hlsli: the layout plots the same function over the show)
    ScShow sh = scResolve(time, loopMode == 0u);
    uint n = scActs();
    uint A = sh.A, B = sh.B, hk = sh.hk;
    float tA = sh.tA, u = sh.u;
    uint kA = scKind(A), kB = scKind(B);
    ScPose pose = sh.pose;
    float2 yp = scYawPitch(pose);

    S[SC_V0] = float4(time, playing ? 1.0 : 0.0, (float)loopMode, SC_VMAGIC);
    S[SC_V1] = float4((float)(newest & 0xFFFFu), (float)(newest >> 16), (float)mode, (float)target);
    S[SC_V2] = float4(press, v2.zw);
    S[SC_V3] = float4((float)g_act, (float)g_sel, spaceHeld ? 1.0 : 0.0, v3.w + 1.0);
    S[SC_V4] = float4(v4.xy, frozen, 0.0);
    S[SC_V5] = v5;
    S[SC_V6] = v6;
    S[SC_R0] = float4((float)A, (float)B, u, (float)hk);
    S[SC_R1] = float4(tA, 0.0, total, (float)n);
    S[SC_R2] = float4(pose.eye, pose.fov);
    S[SC_R3] = float4(pose.target, 0.0);
    S[SC_R4] = float4(yp, 0.0, 0.0);
    S[SC_R5] = float4((float)scLight(A), (float)scLight(B), (float)kA, (float)kB);
}
