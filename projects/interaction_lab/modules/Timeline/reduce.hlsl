// Timeline / reduce - one thread, every cook: the transport moves the playhead, the viewport events
// edit the keys, and the working state is written back.
//
//   STAGE      click a layer: select it        drag it: move (keys x, y at the playhead)
//              drag the square handle: scale    drag the round handle: rotate (keys at the playhead)
//              drag a dot on the motion path: that frame's x, y keys
//   INSPECTOR  drag a value left / right: keys it at the playhead      click a diamond: key / unkey
//              click a mode: the selected keys' interpolation           drag a parameter: the key's ease
//   RULER      click / drag: scrub              drag a loop marker: the loop's in / out
//   DOPE       click a key: select (Shift adds)  drag keys: retime (frame-snapped, never past a
//              neighbour)    drag the empty sheet: box select    double-click a channel row: add a key
//              a layer row's diamond: every key of that layer at that frame
//   GRAPH      drag a key: value and time        drag a selected key's handle: its ease influence
//              drag the empty graph: pan          double-click: add a key on the curve
//   SPLITTERS  drag the bar between the stage and the sheets, or the sheets and the graph
//   KEYS       Space play   Left / Right a frame   Up / Down the previous / next key   Enter the loop's
//              start   1-5 hold / linear / ease / spring / back   Backspace delete   Tab next layer
//              O onion skin   F frame the graph   Z undo   R the default sting (Z brings yours back)
#define TL_STATE_RW
#include "../_shared/ui/il_core.hlsli"
#include "../_shared/ui/il_events.hlsli"
#include "../_shared/ui/il_pane.hlsli"
#include "tl.hlsli"

static uint g_sel;           // the selected layer
static uint g_attr;          // the active attribute (its channel drives the graph)
static float g_primCh;       // the primary key: its channel (or -1) and frame
static float g_primF;
static bool g_reframe;       // frame the graph on the active channel after the events
static bool g_fit;           // ... or only widen it, if an edit carried the curve out of view

// the twenty channels at the playhead, evaluated once per event at ONE call site (every inlined copy
// of tlValue costs compile time); the handlers read this table
static float g_now[TL_CH];
void evalNow(float f) { [loop] for (uint c = 0u; c < TL_CH; c++) g_now[c] = tlValue(c, f); }
float4 nowX(uint l) { uint c = l * TL_ATTRS; return float4(g_now[c], g_now[c + 1u], g_now[c + 2u], g_now[c + 3u]); }
// the frontmost layer under stage point q at the playhead, or 0xFFFF
uint pickNow(float2 q, float slack)
{
    uint hit = 0xFFFFu;
    [loop] for (uint l = TL_LAYERS; l > 0u; l--)
        if (saturate(g_now[(l - 1u) * TL_ATTRS + 4u]) >= 0.05 && tlSd(l - 1u, nowX(l - 1u), q) < slack) hit = l - 1u;
    return hit;
}

// a layer's graph channel: the attribute in focus if it moves on that layer, else its first moving one
uint pickAttr(uint layer, uint prefer)
{
    uint r = prefer;
    if (tlCount(layer * TL_ATTRS + prefer) < 2u)
        [loop] for (uint a = TL_ATTRS; a > 0u; a--) if (tlCount(layer * TL_ATTRS + a - 1u) >= 2u) r = a - 1u;
    return r;
}

void selectLayer(uint l)
{
    if (l == g_sel) return;
    g_sel = l;
    g_attr = pickAttr(l, g_attr);
    g_reframe = true;
}

// ---------------------------------------------------------------- counts and keys
void setCount(uint ch, uint n)
{
    uint r = TL_COUNT0 + ch / 4u;
    bool4 at = uint4(0u, 1u, 2u, 3u) == (ch % 4u).xxxx;
    S[r] = at ? ((float)n).xxxx : S[r];
}

void setSel(uint ch, uint i, bool on)
{
    float4 k = tlKey(ch, i);
    uint z = (uint)k.z;
    k.z = (float)(on ? (z | TL_SELBIT) : (z & ~TL_SELBIT));
    S[tlSlot(ch, i)] = k;
}

void clearSel()
{
    [loop] for (uint ch = 0u; ch < TL_CH; ch++)
    {
        uint n = tlCount(ch);
        [loop] for (uint i = 0u; i < n; i++) setSel(ch, i, false);
    }
}

uint selCount()
{
    uint c = 0u;
    [loop] for (uint ch = 0u; ch < TL_CH; ch++)
    {
        uint n = tlCount(ch);
        [loop] for (uint i = 0u; i < n; i++) c += tlSel(tlKey(ch, i)) ? 1u : 0u;
    }
    return c;
}

// the primary key after a selection change: the first selected key, preferring the graph's channel
void primFromSel(uint chA)
{
    g_primCh = -1.0;
    [loop] for (uint ch = 0u; ch < TL_CH; ch++)
    {
        uint n = tlCount(ch);
        [loop] for (uint i = 0u; i < n; i++)
        {
            float4 k = tlKey(ch, i);
            if (tlSel(k) && (g_primCh < 0.0 || (ch == chA && (uint)g_primCh != chA))) { g_primCh = (float)ch; g_primF = k.x; }
        }
    }
}

// the key on channel ch at frame f, or 0xFFFF
uint keyAt(uint ch, float f)
{
    uint n = tlCount(ch), r = 0xFFFFu;
    [loop] for (uint i = 0u; i < n; i++) if (abs(tlKey(ch, i).x - f) < 0.5) r = i;
    return r;
}

// a key on channel ch at frame f with value v: the key already there takes the value; a new one
// takes the interpolation of the segment it splits (ease at either end). Returns its index or 0xFFFF.
uint setKeyAt(uint ch, float f, float v)
{
    f = round(f);
    uint idx = keyAt(ch, f);
    uint n = tlCount(ch);
    if (idx != 0xFFFFu)
    {
        float4 k = tlKey(ch, idx);
        k.y = v;
        S[tlSlot(ch, idx)] = k;
    }
    else if (n < TL_KMAX)
    {
        uint at = n;
        [loop] for (uint j = n; j > 0u; j--) if (tlKey(ch, j - 1u).x > f) at = j - 1u;
        float4 like = (at > 0u) ? tlKey(ch, at - 1u) : float4(0.0, 0.0, (float)TL_EASE, tlPackParams(float2(0.33, 0.33)));
        [loop] for (uint m = n; m > at; m--) S[tlSlot(ch, m)] = S[tlSlot(ch, m - 1u)];
        S[tlSlot(ch, at)] = float4(f, v, (float)tlMode(like), like.w);
        setCount(ch, n + 1u);
        idx = at;
    }
    return idx;
}

void deleteKey(uint ch, uint i)
{
    uint n = tlCount(ch);
    if (i >= n) return;
    [loop] for (uint j = i; j + 1u < n; j++) S[tlSlot(ch, j)] = S[tlSlot(ch, j + 1u)];
    S[tlSlot(ch, n - 1u)] = 0.0;
    setCount(ch, n - 1u);
}

void deleteSelected()
{
    [loop] for (uint ch = 0u; ch < TL_CH; ch++)
    {
        [loop] for (uint i = tlCount(ch); i > 0u; i--) if (tlSel(tlKey(ch, i - 1u))) deleteKey(ch, i - 1u);
    }
}

void setModeSelected(uint mode)
{
    [loop] for (uint ch = 0u; ch < TL_CH; ch++)
    {
        uint n = tlCount(ch);
        [loop] for (uint i = 0u; i < n; i++)
        {
            float4 k = tlKey(ch, i);
            if (!tlSel(k)) continue;
            k.z = (float)(mode | ((uint)k.z & TL_SELBIT));
            // each mode starts from parameters that show it plainly
            if (mode == TL_EASE) k.w = tlPackParams(float2(0.33, 0.33));
            else if (mode == TL_SPRING) k.w = tlPackParams(float2(0.5, 0.0));
            else if (mode == TL_BACK) k.w = tlPackParams(float2(0.6, 0.6));
            S[tlSlot(ch, i)] = k;
        }
    }
}

// how far (whole frames) the selected keys may move together: never onto or past a key that stays
float2 retimeRange()
{
    float lo = -1e6, hi = 1e6, frames = tlP0().z;
    [loop] for (uint ch = 0u; ch < TL_CH; ch++)
    {
        uint n = tlCount(ch);
        float left = 0.0;                    // just past the last key that stays, so far
        [loop] for (uint i = 0u; i < n; i++)
        {
            float4 k = tlKey(ch, i);
            if (tlSel(k)) lo = max(lo, left - k.x); else left = k.x + 1.0;
        }
        float right = frames;
        [loop] for (uint j = n; j > 0u; j--)
        {
            float4 k = tlKey(ch, j - 1u);
            if (tlSel(k)) hi = min(hi, right - k.x); else right = k.x - 1.0;
        }
    }
    return float2(lo, hi);
}

void retimeSelected(float d)
{
    [loop] for (uint ch = 0u; ch < TL_CH; ch++)
    {
        uint n = tlCount(ch);
        [loop] for (uint i = 0u; i < n; i++)
        {
            float4 k = tlKey(ch, i);
            if (tlSel(k)) { k.x += d; S[tlSlot(ch, i)] = k; }
        }
    }
}

// ---------------------------------------------------------------- undo
void snapshot()
{
    [loop] for (uint i = 0u; i < TL_SAVED; i++) S[TL_UNDO0 + i] = S[i];
    S[TL_U0] = float4(1.0, 0.0, 0.0, 0.0);
}
void restoreSnapshot() { [loop] for (uint i = 0u; i < TL_SAVED; i++) S[i] = S[TL_UNDO0 + i]; }
void swapUndo()
{
    if (S[TL_U0].x < 0.5) return;
    [loop] for (uint i = 0u; i < TL_SAVED; i++)
    {
        float4 a = S[i];
        S[i] = S[TL_UNDO0 + i];
        S[TL_UNDO0 + i] = a;
    }
}

// ---------------------------------------------------------------- the default sting
// Front to back: Ring, Sun, Block, Bar. The bar slides in, the sun drops onto it and the ring pulses
// out from the landing, the block pops (spring) and turns onto its corner (back); then they leave.
#define TL_NDEF 30u
void writeDefaults()
{
    // (channel, frame, value, mode) and (p0, p1)
    static const float4 A[TL_NDEF] = {
        float4(0, 0, 0.18, 0), float4(1, 0, 0.074, 0),
        float4(2, 0, 0.6, 0), float4(2, 22, 0.6, 2), float4(2, 52, 1.75, 0),
        float4(4, 0, 0.0, 0), float4(4, 22, 1.0, 2), float4(4, 52, 0.0, 0),
        float4(5, 0, 0.18, 0),
        float4(6, 0, 0.80, 2), float4(6, 22, 0.074, 0), float4(6, 90, 0.074, 4), float4(6, 112, -0.85, 0),
        float4(10, 0, -0.30, 0), float4(11, 0, 0.037, 0),
        float4(12, 0, 0.0, 0), float4(12, 28, 0.0, 3), float4(12, 52, 1.0, 0), float4(12, 96, 1.0, 2), float4(12, 110, 0.0, 0),
        float4(13, 0, 0.0, 0), float4(13, 34, 0.0, 4), float4(13, 58, 45.0, 0), float4(13, 96, 45.0, 2), float4(13, 114, 225.0, 0),
        float4(15, 0, -1.55, 2), float4(15, 26, 0.0, 0), float4(15, 94, 0.0, 2), float4(15, 118, 1.55, 0),
        float4(16, 0, -0.10, 0) };
    static const float2 B[TL_NDEF] = {
        float2(0, 0), float2(0, 0),
        float2(0, 0), float2(0.05, 0.65), float2(0, 0),
        float2(0, 0), float2(0.10, 0.60), float2(0, 0),
        float2(0, 0),
        float2(0.75, 0.04), float2(0, 0), float2(0.70, 0.0), float2(0, 0),
        float2(0, 0), float2(0, 0),
        float2(0, 0), float2(0.55, 0), float2(0, 0), float2(0.60, 0.10), float2(0, 0),
        float2(0, 0), float2(0.60, 0.50), float2(0, 0), float2(0.30, 0.30), float2(0, 0),
        float2(0.04, 0.80), float2(0, 0), float2(0.80, 0.04), float2(0, 0),
        float2(0, 0) };
    [loop] for (uint i = 0u; i < TL_SAVED; i++) S[i] = 0.0;
    S[TL_P0] = float4(0.0, 120.0, 120.0, 30.0);
    S[TL_PM] = float4(TL_MAGIC, 0.0, 0.0, 0.0);
    [loop] for (uint k = 0u; k < TL_NDEF; k++)
    {
        uint ch = (uint)A[k].x, n = tlCount(ch);
        S[tlSlot(ch, n)] = float4(A[k].y, A[k].z, A[k].w, tlPackParams(B[k]));
        setCount(ch, n + 1u);
    }
    // a channel's last key has no segment yet; it eases, so a key added after it moves rather than
    // jumps (a new key at the end takes its mode)
    [loop] for (uint c = 0u; c < TL_CH; c++)
    {
        uint n = tlCount(c);
        if (n > 0u && tlMode(tlKey(c, n - 1u)) == TL_HOLD) S[tlSlot(c, n - 1u)] = float4(tlKey(c, n - 1u).xy, (float)TL_EASE, tlPackParams(float2(0.33, 0.33)));
    }
}

// ---------------------------------------------------------------- views
// the graph's value window around the active channel's curve (or its default), with a margin; .zw
// the curve's own extent
float4 frameValues(uint ch)
{
    uint n = tlCount(ch);
    float lo = 1e9, hi = -1e9;
    float frames = tlP0().z;
    // the curve itself (spring and back overshoot their keys)
    [loop] for (uint j = 0u; j <= 64u; j++)
    {
        float v = tlValue(ch, frames * j / 64.0);
        lo = min(lo, v);
        hi = max(hi, v);
    }
    float2 raw = float2(lo, hi);
    if (n == 0u) { lo = tlDefault(ch % TL_ATTRS) - 0.5; hi = lo + 1.0; }
    float span = max(hi - lo, (ch % TL_ATTRS == TL_ROT) ? 10.0 : 0.1);
    float c = 0.5 * (lo + hi);
    return float4(c - 0.62 * span, c + 0.62 * span, raw);
}

float stepOf(uint attr)
{
    if (attr == TL_ROT) return 0.5;
    if (attr == TL_SCALE) return 0.005;
    if (attr == TL_OPACITY) return 0.004;
    return 0.002;
}

float wrap180(float a) { return a - 360.0 * floor((a + 180.0) / 360.0); }

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    float2 res = _Resolution.xy;
    float s = ilCtx(res).s;
    float dt = clamp(_DeltaTime, 0.0, 0.1);

    bool fresh = false;
    if (S[TL_PM].x != TL_MAGIC)
    {
        // nothing saved yet (or another format): the default sting
        writeDefaults();
        S[TL_U0] = 0.0;
        S[TL_V0] = 0.0;
    }
    float4 v0 = S[TL_V0], v1 = S[TL_V1], v2 = S[TL_V2], v3 = S[TL_V3], v4 = S[TL_V4], v5 = S[TL_V5], v6 = S[TL_V6], v7 = S[TL_V7];
    if (v0.w != TL_VMAGIC)
    {
        // working state is never saved: fresh after a reopen or a preset recall
        v0 = float4(0.0, 1.0, 2.0, TL_VMAGIC);          // playing, at 1x
        v1 = 0.0;
        v2 = 0.0;
        v4 = float4(0.56, 0.34, 1.0, 1.0);
        v5 = 0.0;
        v6 = float4(0.0, -1.0, -1.0, 0.0);
        v7 = 0.0;
        fresh = true;
    }
    float4 P0 = tlP0();
    float frames = max(P0.z, 1.0), fps = max(P0.w, 1.0);
    g_sel = min((uint)v4.z, TL_LAYERS - 1u);
    g_attr = min((uint)v4.w, TL_ATTRS - 1u);
    g_primCh = v6.y;
    g_primF = v6.z;
    g_reframe = false;
    g_fit = false;
    uint mode = (uint)v1.z, target = (uint)v1.w;
    float2 press = v2.xy;
    TlLayout L = tlLayout(res, s, v4.xy);
    if (fresh) { v3 = float4(-4.0, frames + 4.0, 0.0, 1.0); g_reframe = true; }
    float2 tw = v3.xy, vw = v3.zw;
    float playhead = v0.x;
    bool playing = v0.y > 0.5;
    uint speedIx = (uint)clamp(v0.z, 0.0, 3.0);
    bool spaceHeld = v7.y > 0.5;

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
        bool shift = (e.modifiers & VIEWPORT_MODIFIER_SHIFT) != 0u;
        float frameNow = clamp(round(playhead), 0.0, frames);
        uint chA = g_sel * TL_ATTRS + g_attr;
        evalNow(frameNow);

        if (e.type == IL_EV_WHEEL)
        {
            float notches = ilWheel(e);
            if (ilIn(px, L.graph))
            {
                float k = pow(1.15, -notches), pv = tlGV(L, vw, px.y);
                vw = pv + (vw - pv) * k;
            }
            else if (ilIn(px, L.dope) || ilIn(px, L.ruler))
            {
                float k = pow(1.15, -notches), pf = tlF(L, tw, px.x);
                tw = pf + (tw - pf) * k;
                if (tw.y - tw.x < 12.0) tw = pf + (tw - pf) * (12.0 / (tw.y - tw.x));
            }
            continue;
        }

        if (ilIsDrag(e))
        {
            if (e.phase == IL_PH_BEGIN)
            {
                mode = DM_NONE;
                float2 q = tlPxToStage(L.stage, press);
                float4 xs = nowX(g_sel);
                float rh = 9.0 * s / max(L.stage.w - L.stage.y, 1.0);   // handle reach, stage units
                if (ilIn(press, L.gripV)) mode = DM_SPLITV;
                else if (ilIn(press, L.gripH)) mode = DM_SPLITH;
                else if (ilIn(press, L.stage))
                {
                    float pf[16];
                    uint np = tlPathKeys(g_sel, pf), hitPath = 0xFFFFu;
                    [loop] for (uint z = 0u; z < np; z++)
                    {
                        float2 pq = float2(tlValue(g_sel * TL_ATTRS, pf[z]), tlValue(g_sel * TL_ATTRS + 1u, pf[z]));
                        if (length(pq - q) < rh) hitPath = z;
                    }
                    playing = false;
                    if (length(tlRotHandle(xs, g_sel) - q) < rh * 1.2) { snapshot(); mode = DM_ROT; target = g_sel; v5 = float4(xs.w, degrees(atan2(q.x - xs.x, q.y - xs.y)), 0.0, 0.0); }
                    else if (length(tlScaleHandle(xs, g_sel) - q) < rh * 1.2) { snapshot(); mode = DM_SCALE; target = g_sel; v5 = float4(xs.z, max(length(q - xs.xy), 1e-3), 0.0, 0.0); }
                    else if (hitPath != 0xFFFFu)
                    {
                        snapshot();
                        mode = DM_PATHKEY;
                        target = (uint)round(pf[hitPath]);
                        v5 = float4(tlValue(g_sel * TL_ATTRS, pf[hitPath]), tlValue(g_sel * TL_ATTRS + 1u, pf[hitPath]), 0.0, 0.0);
                    }
                    else
                    {
                        uint l = pickNow(q, 4.0 * s / max(L.stage.w - L.stage.y, 1.0));
                        if (l != 0xFFFFu)
                        {
                            selectLayer(l);
                            snapshot();
                            mode = DM_MOVE;
                            target = l;
                            v5 = float4(nowX(l).xy, 0.0, 0.0);
                        }
                    }
                }
                else if (ilIn(press, L.insp))
                {
                    [loop] for (uint a = 0u; a < TL_ATTRS; a++)
                        if (ilIn(press, tlField(L, a, s))) { snapshot(); mode = DM_FIELD; target = a; v5 = float4(g_now[g_sel * TL_ATTRS + a], 0.0, 0.0, 0.0); playing = false; }
                    if (g_primCh >= 0.0)
                    {
                        uint pc = (uint)g_primCh, pi = keyAt(pc, g_primF);
                        if (pi != 0xFFFFu)
                            [loop] for (uint b = 0u; b < 2u; b++)
                                if (ilIn(press, tlParamField(L, b, s))) { snapshot(); mode = DM_PARAM; target = b; v5 = float4(tlParams(tlKey(pc, pi)), 0.0, 0.0); }
                    }
                }
                else if (ilIn(press, L.ruler))
                {
                    if (length(press - tlLoopIn(L, tw)) < 8.0 * s) mode = DM_LOOPIN;
                    else if (length(press - tlLoopOut(L, tw)) < 8.0 * s) mode = DM_LOOPOUT;
                    else mode = DM_SCRUB;
                    if (mode != DM_SCRUB) snapshot();
                    playing = false;
                }
                else if (ilIn(press, L.dope))
                {
                    uint hk = tlHitDopeKey(L, tw, g_sel, press, 7.0 * s);
                    uint hs = (hk == 0xFFFFu) ? tlHitSummary(L, tw, g_sel, press, 7.0 * s) : 0xFFFFu;
                    if (hk != 0xFFFFu)
                    {
                        uint ch = hk / TL_KMAX, i = hk % TL_KMAX;
                        if (!tlSel(tlKey(ch, i))) { if (!shift) clearSel(); setSel(ch, i, true); }
                        g_primCh = (float)ch; g_primF = tlKey(ch, i).x;
                    }
                    else if (hs != 0xFFFFu)
                    {
                        if (!shift) clearSel();
                        uint layer = hs / 4096u;
                        float f = (float)(hs % 4096u);
                        [loop] for (uint a = 0u; a < TL_ATTRS; a++) { uint ch = layer * TL_ATTRS + a, i = keyAt(ch, f); if (i != 0xFFFFu) setSel(ch, i, true); }
                        primFromSel(chA);
                    }
                    if (hk != 0xFFFFu || hs != 0xFFFFu)
                    {
                        snapshot();
                        mode = DM_RETIME;
                        v5 = float4(retimeRange(), 0.0, 0.0);
                    }
                    else mode = DM_BOX;
                }
                else if (ilIn(press, L.graph))
                {
                    uint hh = tlHitHandle(L, tw, vw, chA, press, 8.0 * s);
                    uint hk = (hh == 0xFFFFu) ? tlHitGraphKey(L, tw, vw, chA, press, 8.0 * s) : 0xFFFFu;
                    if (hh != 0xFFFFu) { snapshot(); mode = DM_HANDLE; target = hh; }
                    else if (hk != 0xFFFFu)
                    {
                        if (!tlSel(tlKey(chA, hk))) { if (!shift) clearSel(); setSel(chA, hk, true); }
                        g_primCh = (float)chA; g_primF = tlKey(chA, hk).x;
                        snapshot();
                        mode = DM_GKEY;
                        target = hk;
                        v5 = tlKey(chA, hk);
                    }
                    else { mode = DM_PAN; v5 = float4(vw, 0.0, 0.0); }
                }
            }
            if (ilIsCancel(e))
            {
                if (mode != DM_NONE && mode != DM_SCRUB && mode != DM_BOX && mode != DM_PAN && mode != DM_SPLITV && mode != DM_SPLITH) restoreSnapshot();
                mode = DM_NONE;
                continue;
            }
            v2.zw = px;
            float2 q = tlPxToStage(L.stage, px), q0 = tlPxToStage(L.stage, press);
            float frameNow2 = clamp(round(playhead), 0.0, frames);
            if (mode == DM_SPLITV) v4.x = ilSplitYValue(L.inner, px.y, TL_GAP * s);
            else if (mode == DM_SPLITH)
            {
                float4 rest = float4(L.area.x, L.ruler.w + 2.0 * s, L.area.z, L.area.w);
                v4.y = ilSplitYValue(rest, px.y, 12.0 * s);
            }
            else if (mode == DM_MOVE)
            {
                restoreSnapshot();
                float2 np = v5.xy + (q - q0);
                setKeyAt(target * TL_ATTRS + TL_X, frameNow2, np.x);
                setKeyAt(target * TL_ATTRS + TL_Y, frameNow2, np.y);
            }
            else if (mode == DM_SCALE)
            {
                restoreSnapshot();
                float2 c = nowX(target).xy;
                setKeyAt(target * TL_ATTRS + TL_SCALE, frameNow2, max(v5.x * length(q - c) / v5.y, 0.0));
            }
            else if (mode == DM_ROT)
            {
                restoreSnapshot();
                float2 c = nowX(target).xy;
                float ang = degrees(atan2(q.x - c.x, q.y - c.y));
                v5.z += wrap180(ang - v5.y);       // accumulated, so it can turn past a half turn
                v5.y = ang;
                setKeyAt(target * TL_ATTRS + TL_ROT, frameNow2, v5.x + v5.z);
            }
            else if (mode == DM_PATHKEY)
            {
                restoreSnapshot();
                float2 np = v5.xy + (q - q0);
                setKeyAt(g_sel * TL_ATTRS + TL_X, (float)target, np.x);
                setKeyAt(g_sel * TL_ATTRS + TL_Y, (float)target, np.y);
            }
            else if (mode == DM_FIELD)
            {
                restoreSnapshot();
                float v = v5.x + (px.x - press.x) / s * stepOf(target);
                if (target == TL_OPACITY) v = saturate(v);
                if (target == TL_SCALE) v = max(v, 0.0);
                setKeyAt(g_sel * TL_ATTRS + target, frameNow2, v);
            }
            else if (mode == DM_PARAM && g_primCh >= 0.0)
            {
                restoreSnapshot();
                uint pc = (uint)g_primCh, pi = keyAt(pc, g_primF);
                if (pi != 0xFFFFu)
                {
                    float4 k = tlKey(pc, pi);
                    float2 prm = v5.xy;
                    float dp = (px.x - press.x) / s * 0.004;
                    if (target == 0u) prm.x = saturate(v5.x + dp); else prm.y = saturate(v5.y + dp);
                    k.w = tlPackParams(prm);
                    S[tlSlot(pc, pi)] = k;
                }
            }
            else if (mode == DM_SCRUB) playhead = clamp(round(tlF(L, tw, px.x)), 0.0, frames);
            else if (mode == DM_LOOPIN) { float4 p = tlP0(); p.x = clamp(round(tlF(L, tw, px.x)), 0.0, p.y - 1.0); S[TL_P0] = p; }
            else if (mode == DM_LOOPOUT) { float4 p = tlP0(); p.y = clamp(round(tlF(L, tw, px.x)), p.x + 1.0, frames); S[TL_P0] = p; }
            else if (mode == DM_RETIME)
            {
                restoreSnapshot();
                float d = clamp(round(tlF(L, tw, px.x) - tlF(L, tw, press.x)), v5.x, v5.y);
                retimeSelected(d);
            }
            else if (mode == DM_GKEY)
            {
                restoreSnapshot();
                uint n = tlCount(chA);
                float lo = (target > 0u) ? tlKey(chA, target - 1u).x + 1.0 : 0.0;
                float hi = (target + 1u < n) ? tlKey(chA, target + 1u).x - 1.0 : frames;
                float4 k = v5;
                k.x = clamp(round(v5.x + tlF(L, tw, px.x) - tlF(L, tw, press.x)), lo, hi);
                k.y = v5.y + tlGV(L, vw, px.y) - tlGV(L, vw, press.y);
                S[tlSlot(chA, target)] = k;
                g_primF = k.x;
            }
            else if (mode == DM_HANDLE)
            {
                restoreSnapshot();
                uint i = target / 2u;
                float f = tlF(L, tw, px.x);
                if ((target & 1u) != 0u)
                {
                    float4 k = tlKey(chA, i), kn = tlKey(chA, i + 1u);
                    float2 prm = tlParams(k);
                    prm.x = clamp((f - k.x) / max(kn.x - k.x, 1.0), 0.02, 1.0);
                    k.w = tlPackParams(prm);
                    S[tlSlot(chA, i)] = k;
                }
                else
                {
                    float4 k = tlKey(chA, i), kp = tlKey(chA, i - 1u);
                    float2 prm = tlParams(kp);
                    prm.y = clamp((k.x - f) / max(k.x - kp.x, 1.0), 0.02, 1.0);
                    kp.w = tlPackParams(prm);
                    S[tlSlot(chA, i - 1u)] = kp;
                }
            }
            else if (mode == DM_PAN)
            {
                float dv = (px.y - press.y) / max(L.graph.w - L.graph.y - 12.0, 1.0) * (v5.y - v5.x);
                vw = v5.xy + dv;
            }
            if (e.phase == IL_PH_END)
            {
                if (mode == DM_RETIME && g_primCh >= 0.0)
                {
                    // the primary key moved with the selection
                    float d = clamp(round(tlF(L, tw, px.x) - tlF(L, tw, press.x)), v5.x, v5.y);
                    g_primF += d;
                }
                if (mode == DM_BOX)
                {
                    if (!shift) clearSel();
                    float4 bx = float4(min(press, px), max(press, px));
                    [loop] for (uint row = 0u; row < TL_ROWS; row++)
                    {
                        float4 r = tlRow(L, row);
                        if (r.w < bx.y || r.y > bx.w) continue;
                        uint3 w = tlRowWhat(row, g_sel);
                        [loop] for (uint a = 0u; a < TL_ATTRS; a++)
                        {
                            if (w.x == 0u && a != w.z) continue;          // a channel row: that channel
                            uint ch = w.y * TL_ATTRS + a, n = tlCount(ch);
                            [loop] for (uint i = 0u; i < n; i++)
                            {
                                float x = tlX(L, tw, tlKey(ch, i).x);
                                if (x >= bx.x && x <= bx.z) setSel(ch, i, true);
                            }
                        }
                    }
                    primFromSel(chA);
                }
                if (mode == DM_MOVE || mode == DM_SCALE || mode == DM_ROT || mode == DM_PATHKEY || mode == DM_FIELD) g_fit = true;
                mode = DM_NONE;
            }
        }
        else if (ilIsClick(e))
        {
            if (ilIn(px, L.stage))
            {
                float2 q = tlPxToStage(L.stage, px);
                uint l = pickNow(q, 4.0 * s / max(L.stage.w - L.stage.y, 1.0));
                if (l != 0xFFFFu) selectLayer(l);
            }
            else if (ilIn(px, L.ruler)) { playhead = clamp(round(tlF(L, tw, px.x)), 0.0, frames); playing = false; }
            else if (ilIn(px, L.transport))
            {
                if (ilIn(px, tlPlayChip(L, s))) playing = !playing;
                float4 sp = tlSpeeds(L, s);
                if (ilIn(px, sp)) speedIx = min((uint)((px.x - sp.x) / ((sp.z - sp.x) / 4.0)), 3u);
                if (ilIn(px, tlOnionChip(L, s))) v6.x = v6.x > 0.5 ? 0.0 : 1.0;
            }
            else if (ilIn(px, L.insp))
            {
                [loop] for (uint a = 0u; a < TL_ATTRS; a++)
                {
                    if (length(px - tlKeyToggle(L, a, s)) < 9.0 * s)
                    {
                        snapshot();
                        uint ch = g_sel * TL_ATTRS + a, have = keyAt(ch, frameNow);
                        if (have != 0xFFFFu) deleteKey(ch, have);
                        else { setKeyAt(ch, frameNow, g_now[ch]); g_primCh = (float)ch; g_primF = frameNow; }
                    }
                }
                float4 md = tlModes(L, s);
                if (ilIn(px, md))
                {
                    uint m = min((uint)((px.x - md.x) / ((md.z - md.x) / 5.0)), 4u);
                    snapshot();
                    if (selCount() == 0u && g_primCh >= 0.0)
                    {
                        uint pi = keyAt((uint)g_primCh, g_primF);
                        if (pi != 0xFFFFu) setSel((uint)g_primCh, pi, true);
                    }
                    setModeSelected(m);
                }
            }
            else if (ilIn(px, L.list) && tlRowAt(L, px.y) != 0xFFFFu)
            {
                uint3 w = tlRowWhat(tlRowAt(L, px.y), g_sel);
                if (w.x == 1u) selectLayer(w.y);
                else { g_attr = w.z; g_reframe = true; }
            }
            else if (ilIn(px, L.dope))
            {
                uint hk = tlHitDopeKey(L, tw, g_sel, px, 7.0 * s);
                uint hs = (hk == 0xFFFFu) ? tlHitSummary(L, tw, g_sel, px, 7.0 * s) : 0xFFFFu;
                if (hk != 0xFFFFu)
                {
                    uint ch = hk / TL_KMAX, i = hk % TL_KMAX;
                    bool was = tlSel(tlKey(ch, i));
                    if (!shift) clearSel();
                    setSel(ch, i, shift ? !was : true);
                    if (shift && was) primFromSel(chA);
                    else
                    {
                        g_primCh = (float)ch; g_primF = tlKey(ch, i).x;
                        if (ch / TL_ATTRS == g_sel && ch % TL_ATTRS != g_attr) { g_attr = ch % TL_ATTRS; g_reframe = true; }
                    }
                }
                else if (hs != 0xFFFFu)
                {
                    if (!shift) clearSel();
                    uint layer = hs / 4096u;
                    float f = (float)(hs % 4096u);
                    [loop] for (uint a = 0u; a < TL_ATTRS; a++) { uint ch = layer * TL_ATTRS + a, i = keyAt(ch, f); if (i != 0xFFFFu) setSel(ch, i, true); }
                    primFromSel(chA);
                }
                else if (!shift) { clearSel(); g_primCh = -1.0; }
            }
            else if (ilIn(px, L.graph))
            {
                uint hk = tlHitGraphKey(L, tw, vw, chA, px, 8.0 * s);
                if (hk != 0xFFFFu)
                {
                    bool was = tlSel(tlKey(chA, hk));
                    if (!shift) clearSel();
                    setSel(chA, hk, shift ? !was : true);
                    if (shift && was) primFromSel(chA); else { g_primCh = (float)chA; g_primF = tlKey(chA, hk).x; }
                }
                else if (!shift) { clearSel(); g_primCh = -1.0; }
            }
        }
        else if (ilIsDouble(e))
        {
            if (ilIn(px, L.dope))
            {
                uint row = tlRowAt(L, px.y);
                uint3 w = (row != 0xFFFFu) ? tlRowWhat(row, g_sel) : uint3(1u, 0u, 0u);
                if (w.x == 0u)
                {
                    uint ch = w.y * TL_ATTRS + w.z;
                    float f = clamp(round(tlF(L, tw, px.x)), 0.0, frames);
                    snapshot();
                    if (setKeyAt(ch, f, tlValue(ch, f)) != 0xFFFFu) { clearSel(); setSel(ch, keyAt(ch, f), true); g_primCh = (float)ch; g_primF = f; }
                    if (w.z != g_attr) { g_attr = w.z; g_reframe = true; }
                }
            }
            else if (ilIn(px, L.graph))
            {
                float f = clamp(round(tlF(L, tw, px.x)), 0.0, frames);
                snapshot();
                if (setKeyAt(chA, f, tlValue(chA, f)) != 0xFFFFu) { clearSel(); setSel(chA, keyAt(chA, f), true); g_primCh = (float)chA; g_primF = f; }
            }
        }
        else if (e.type == IL_EV_KEY)
        {
            bool down = e.phase == IL_PH_PRESS && !ilRepeat(e);
            bool downOrRepeat = e.phase == IL_PH_PRESS || e.phase == IL_PH_REPEAT;
            if (ilLatch(e, IL_KEY_SPACE, spaceHeld)) playing = !playing;
            if (downOrRepeat && (e.code == IL_KEY_LEFT || e.code == IL_KEY_RIGHT))
            {
                playing = false;
                playhead = clamp(round(playhead) + (e.code == IL_KEY_RIGHT ? 1.0 : -1.0), 0.0, frames);
            }
            if (downOrRepeat && (e.code == IL_KEY_UP || e.code == IL_KEY_DOWN))
            {
                // the previous / next key on any of the selected layer's channels
                playing = false;
                float best = (e.code == IL_KEY_DOWN) ? 1e9 : -1e9;
                [loop] for (uint a = 0u; a < TL_ATTRS; a++)
                {
                    uint ch = g_sel * TL_ATTRS + a, n = tlCount(ch);
                    [loop] for (uint i = 0u; i < n; i++)
                    {
                        float f = tlKey(ch, i).x;
                        if (e.code == IL_KEY_DOWN && f > playhead + 0.5) best = min(best, f);
                        if (e.code == IL_KEY_UP && f < playhead - 0.5) best = max(best, f);
                    }
                }
                if (abs(best) < 1e8) playhead = best;
            }
            if (down && e.code == IL_KEY_ENTER) { playhead = tlP0().x; }
            if (down && e.code >= IL_KEY_0 + 1u && e.code <= IL_KEY_0 + 5u)
            {
                snapshot();
                if (selCount() == 0u && g_primCh >= 0.0)
                {
                    uint pi = keyAt((uint)g_primCh, g_primF);
                    if (pi != 0xFFFFu) setSel((uint)g_primCh, pi, true);
                }
                setModeSelected(e.code - IL_KEY_0 - 1u);
            }
            if (down && e.code == IL_KEY_BACKSPACE && selCount() > 0u) { snapshot(); deleteSelected(); g_primCh = -1.0; }
            if (down && e.code == IL_KEY_TAB) selectLayer((g_sel + 1u) % TL_LAYERS);
            if (down && e.code == IL_KEY_O) v6.x = v6.x > 0.5 ? 0.0 : 1.0;
            if (down && e.code == IL_KEY_F) { g_reframe = true; tw = float2(tlP0().x - 4.0, tlP0().y + 4.0); }
            if (down && e.code == IL_KEY_Z) swapUndo();
            if (down && e.code == IL_KEY_R) { snapshot(); writeDefaults(); g_primCh = -1.0; }
        }
    }

    // the graph's value window follows the active channel: framed when the channel changes (or on F),
    // widened when an edit carried the curve out of view. One call site: frameValues is a 65-sample loop.
    if (g_reframe || g_fit)
    {
        float4 fv = frameValues(g_sel * TL_ATTRS + g_attr);
        if (g_reframe || fv.z < vw.x || fv.w > vw.y) vw = fv.xy;
    }

    // 2. the transport: the playhead runs the loop at the timeline's rate times the speed
    float4 lp = tlP0();
    if (playing && mode != DM_SCRUB)
    {
        playhead += dt * fps * TL_SPEEDS[speedIx];
        if (playhead >= lp.y) playhead = lp.x + fmod(playhead - lp.y, max(lp.y - lp.x, 1.0));
        if (playhead < lp.x) playhead = lp.x;
    }
    playhead = clamp(playhead, 0.0, frames);

    S[TL_V0] = float4(playhead, playing ? 1.0 : 0.0, (float)speedIx, TL_VMAGIC);
    S[TL_V1] = float4((float)(newest & 0xFFFFu), (float)(newest >> 16), (float)mode, (float)target);
    S[TL_V2] = float4(press, v2.zw);
    S[TL_V3] = float4(tw, vw);
    S[TL_V4] = float4(v4.xy, (float)g_sel, (float)g_attr);
    S[TL_V5] = v5;
    S[TL_V6] = float4(v6.x, g_primCh, g_primF, 0.0);
    S[TL_V7] = float4(v7.x + 1.0, spaceHeld ? 1.0 : 0.0, 0.0, 0.0);
}
