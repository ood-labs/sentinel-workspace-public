// Ramp Desk / reduce - one thread, and the one pass that runs only when something happens
// (`time_dependent: false`): the viewport events, then each stop's shown chroma, the 256 entries
// and the revision. Its buffer IS the published Palette, so the Palette changes here and only here.
//
//   click the ramp        add a stop (in the colour already there)      click a stop: select it
//   drag a stop           move it; drag it down off the lane and let go to remove it
//   drag from the ramp    add a stop and move it
//   drag a diamond        lean the blend toward one stop                double-click it: even again
//   plane                 the selected stop's lightness and chroma (the chroma asked for; it is
//                         shown brought inside sRGB at the same lightness and hue)
//   hue strip             its hue                                       click a row: that stop
//   Backspace             remove the selected stop (two always stay)    Tab: the next stop
//   left / right          move it one entry (1/255)                     up / down: lightness 0.01
//   F                     flip the ramp                                 E: space the stops evenly
//   R                     the next built-in palette (Z brings the edit back)   Z: undo (again: redo)
#define RD_STATE_RW
#include "../_shared/ui/il_core.hlsli"
#include "../_shared/ui/il_events.hlsli"
#include "ramp.hlsli"

#define DM_NONE  0u
#define DM_PIN   1u
#define DM_MID   2u
#define DM_PLANE 3u
#define DM_HUE   4u

static uint g_n;
static uint g_sel;

uint ixA(uint i) { return PAL_STOP0 + 2u * i; }
uint ixB(uint i) { return PAL_STOP0 + 2u * i + 1u; }

void storeHead()
{
    float4 h = S[PAL_HEAD];
    h.x = (float)g_n;
    h.y = (float)PAL_ENTRIES;
    S[PAL_HEAD] = h;
}

// ---------------------------------------------------------------- undo
void snapshot()
{
    storeHead();
    [loop] for (uint i = 0u; i < PAL_SAVED; i++) S[RD_UNDO0 + i] = S[i];
    S[RD_U0] = float4(1.0, 0.0, 0.0, 0.0);
}

void readCount() { g_n = clamp((uint)S[PAL_HEAD].x, 2u, PAL_STOPS); g_sel = min(g_sel, g_n - 1u); }

void swapUndo()
{
    if (S[RD_U0].x < 0.5) return;
    storeHead();
    [loop] for (uint i = 0u; i < PAL_SAVED; i++)
    {
        float4 a = S[i];
        S[i] = S[RD_UNDO0 + i];
        S[RD_UNDO0 + i] = a;
    }
    readCount();
}

// a cancelled drag: back to where it began (the snapshot stays, so Z still has it)
void restoreSnapshot()
{
    [loop] for (uint i = 0u; i < PAL_SAVED; i++) S[i] = S[RD_UNDO0 + i];
    readCount();
}

// ---------------------------------------------------------------- the stops
void setStop(uint i, float t, float mid, float3 lch)
{
    S[ixA(i)] = float4(t, mid, 0.0, 0.0);
    S[ixB(i)] = float4(lch.x, lch.y, lch.z, lch.y);
}

void swapStops(uint i, uint j)
{
    float4 a = S[ixA(i)], b = S[ixB(i)];
    S[ixA(i)] = S[ixA(j)];
    S[ixB(i)] = S[ixB(j)];
    S[ixA(j)] = a;
    S[ixB(j)] = b;
}

// position order, carrying the selection along
void sortStops()
{
    [loop] for (uint i = 1u; i < g_n; i++)
    {
        [loop] for (uint j = i; j > 0u; j--)
        {
            if (S[ixA(j - 1u)].x <= S[ixA(j)].x) break;
            swapStops(j - 1u, j);
            if (g_sel == j) g_sel = j - 1u;
            else if (g_sel == j - 1u) g_sel = j;
        }
    }
}

void removeStop(uint i)
{
    if (g_n <= 2u || i >= g_n) return;
    [loop] for (uint k = i; k + 1u < g_n; k++)
    {
        S[ixA(k)] = S[ixA(k + 1u)];
        S[ixB(k)] = S[ixB(k + 1u)];
    }
    g_n--;
    S[ixA(g_n)] = 0.0;
    S[ixB(g_n)] = 0.0;
    g_sel = min(i, g_n - 1u);
}

// a new stop at t in the colour the ramp already has there, so adding one changes nothing until
// it is moved or recoloured; returns its index
uint addStop(float t)
{
    bool clip;
    float3 lch = palLabToLch(palLinearToLab(rdBlendAt(t, (uint)blend_space, clip)));
    uint i = g_n;
    g_n++;
    setStop(i, t, 0.5, lch);
    g_sel = i;
    sortStops();
    // the interval it split starts even on both sides
    if (g_sel > 0u)
    {
        float4 a = S[ixA(g_sel - 1u)];
        a.y = 0.5;
        S[ixA(g_sel - 1u)] = a;
    }
    return g_sel;
}

// flip the ramp end for end. Interval j of the flipped ramp is interval n - 2 - j of the old one
// walked backwards, so its lean mirrors: m' = 1 - m.
void flipStops()
{
    float mids[PAL_STOPS];
    [loop] for (uint i = 0u; i < g_n; i++)
    {
        float4 a = S[ixA(i)];
        mids[i] = a.y;
        a.x = 1.0 - a.x;
        S[ixA(i)] = a;
    }
    [loop] for (uint lo = 0u, hi = g_n - 1u; lo < hi; lo++, hi--) swapStops(lo, hi);
    [loop] for (uint j = 0u; j < g_n; j++)
    {
        float4 a = S[ixA(j)];
        a.y = (j + 1u < g_n) ? 1.0 - mids[g_n - 2u - j] : 0.5;
        S[ixA(j)] = a;
    }
    g_sel = g_n - 1u - g_sel;
}

void evenStops()
{
    [loop] for (uint i = 0u; i < g_n; i++)
    {
        float4 a = S[ixA(i)];
        a.x = (float)i / (float)(g_n - 1u);
        S[ixA(i)] = a;
    }
}

// ---------------------------------------------------------------- built-in palettes (t, L, C, h)
// 0 hypsometric: sea floor to snow, the coast a hard step at t = 0.5 (two stops 0.006 apart)
// 1 ink: paper to blue-black          2 thermal: black body, its oranges past what sRGB shows
// 3 diverging: blue, paper, red about the middle
static const float4 BUILTIN[21] = {
    float4(0.000, 0.27, 0.065, 258.0), float4(0.300, 0.45, 0.090, 245.0), float4(0.470, 0.70, 0.085, 215.0),
    float4(0.497, 0.84, 0.055, 200.0), float4(0.503, 0.66, 0.105, 138.0), float4(0.600, 0.75, 0.115, 115.0),
    float4(0.720, 0.77, 0.105,  82.0), float4(0.860, 0.59, 0.065,  52.0), float4(0.950, 0.74, 0.018,  62.0),
    float4(1.000, 0.97, 0.008, 240.0),
    float4(0.000, 0.97, 0.016,  88.0), float4(0.450, 0.66, 0.045, 245.0), float4(1.000, 0.20, 0.045, 262.0),
    float4(0.000, 0.14, 0.030, 300.0), float4(0.280, 0.40, 0.160,  28.0), float4(0.560, 0.68, 0.180,  52.0),
    float4(0.800, 0.87, 0.150,  92.0), float4(1.000, 0.98, 0.040, 105.0),
    float4(0.000, 0.42, 0.140, 258.0), float4(0.500, 0.96, 0.006,  95.0), float4(1.000, 0.48, 0.170,  28.0) };
static const uint BUILTIN_FIRST[4] = { 0u, 10u, 13u, 18u };
static const uint BUILTIN_N[4] = { 10u, 3u, 5u, 3u };

void writeBuiltin(uint b)
{
    b = b & 3u;
    [loop] for (uint i = 1u; i < PAL_SAVED; i++) S[i] = 0.0;
    g_n = BUILTIN_N[b];
    [loop] for (uint k = 0u; k < g_n; k++)
    {
        float4 v = BUILTIN[BUILTIN_FIRST[b] + k];
        setStop(k, v.x, 0.5, v.yzw);
    }
    storeHead();
    g_sel = 0u;
}

// ---------------------------------------------------------------- the published record
uint fnv(uint h, uint v) { return (h ^ v) * 16777619u; }

uint revision(uint space)
{
    uint h = fnv(fnv(2166136261u, g_n), space);
    [loop] for (uint i = 0u; i < g_n; i++)
    {
        float4 a = S[ixA(i)], b = S[ixB(i)];
        uint4 q = (uint4)round(saturate(float4(a.x, a.y, b.x, b.y * 2.5)) * 4095.0);
        h = fnv(fnv(fnv(fnv(fnv(h, q.x), q.y), q.z), q.w), (uint)round(b.z * 8.0));
    }
    return h & 0xFFFFFFu;
}

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    float2 res = _Resolution.xy;
    float s = ilCtx(res).s;
    RdLayout L = rdLayout(res, s);

    float4 head = S[PAL_HEAD];
    if (head.x < 2.0 || head.x > (float)PAL_STOPS || head.y != (float)PAL_ENTRIES)
    {
        // nothing saved yet (or another format): the hypsometric built-in
        writeBuiltin(0u);
        S[RD_U0] = 0.0;
        S[RD_V2] = 0.0;
    }
    g_sel = 0u;
    readCount();
    float4 v0 = S[RD_V0], v1 = S[RD_V1], v2 = S[RD_V2];
    if (v2.w != RD_VMAGIC)
    {
        // working state is never saved: fresh after a reopen
        v0 = 0.0;
        v1 = 0.0;
        v2 = float4(0.0, 0.0, 0.0, RD_VMAGIC);
    }
    uint mode = (uint)v1.x, target = (uint)v1.y, flags = (uint)v1.w;
    g_sel = min((uint)v1.z, g_n - 1u);
    float2 press = v2.xy;
    float grab = v2.z;
    uint builtin = (uint)v0.z;

    uint lastSeq = ilEvWatermark((uint)v0.x | ((uint)v0.y << 16));
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
                flags &= ~RD_REMOVE;
                uint hp = rdHitPin(L, press, s);
                uint hm = rdHitMid(L, press, s);
                if (ilIn(press, L.plane)) { snapshot(); mode = DM_PLANE; }
                else if (ilIn(press, L.hue)) { snapshot(); mode = DM_HUE; }
                else if (hp != 0xFFFFu)
                {
                    snapshot();
                    mode = DM_PIN;
                    g_sel = hp;
                    grab = rdX(L, rdT(hp)) - press.x;
                }
                else if (hm != 0xFFFFu) { snapshot(); mode = DM_MID; target = hm; }
                else if (rdOnRamp(L, press) && g_n < PAL_STOPS)
                {
                    snapshot();
                    addStop(rdTOf(L, press.x));
                    mode = DM_PIN;
                    grab = 0.0;
                }
            }
            if (ilIsCancel(e))
            {
                if (mode != DM_NONE) restoreSnapshot();
                mode = DM_NONE;
                flags &= ~RD_REMOVE;
                continue;
            }
            if (mode == DM_PLANE)
            {
                float2 lc = rdPlaneLC(L, px);
                float4 b = S[ixB(g_sel)];
                S[ixB(g_sel)] = float4(lc.x, lc.y, b.z, lc.y);
            }
            else if (mode == DM_HUE)
            {
                float4 b = S[ixB(g_sel)];
                b.z = 360.0 * saturate((px.x - L.hue.x) / max(L.hue.z - L.hue.x, 1.0));
                S[ixB(g_sel)] = b;
            }
            else if (mode == DM_PIN)
            {
                float4 a = S[ixA(g_sel)];
                a.x = rdTOf(L, px.x + grab);
                S[ixA(g_sel)] = a;
                sortStops();
                bool removing = g_n > 2u && px.y > L.pins.w + 26.0 * s;
                flags = removing ? (flags | RD_REMOVE) : (flags & ~RD_REMOVE);
                if (e.phase == IL_PH_END && removing) removeStop(g_sel);
            }
            else if (mode == DM_MID && target + 1u < g_n)
            {
                float a = rdT(target), b = rdT(target + 1u);
                float4 r = S[ixA(target)];
                r.y = b > a + 1e-6 ? clamp((rdTOf(L, px.x) - a) / (b - a), 0.05, 0.95) : 0.5;
                S[ixA(target)] = r;
            }
            if (e.phase == IL_PH_END)
            {
                mode = DM_NONE;
                flags &= ~RD_REMOVE;
            }
        }
        else if (ilIsClick(e))
        {
            uint hp = rdHitPin(L, px, s);
            if (ilIn(px, L.plane))
            {
                snapshot();
                float2 lc = rdPlaneLC(L, px);
                float4 b = S[ixB(g_sel)];
                S[ixB(g_sel)] = float4(lc.x, lc.y, b.z, lc.y);
            }
            else if (ilIn(px, L.hue))
            {
                snapshot();
                float4 b = S[ixB(g_sel)];
                b.z = 360.0 * saturate((px.x - L.hue.x) / max(L.hue.z - L.hue.x, 1.0));
                S[ixB(g_sel)] = b;
            }
            else if (hp != 0xFFFFu) g_sel = hp;
            else if (rdHitMid(L, px, s) != 0xFFFFu) { }        // a diamond: double-click evens it
            else if (rdOnRamp(L, px) && g_n < PAL_STOPS)
            {
                snapshot();
                addStop(rdTOf(L, px.x));
            }
            else
            {
                [loop] for (uint i = 0u; i < g_n; i++) if (ilIn(px, rdRow(L, i))) g_sel = i;
            }
        }
        else if (ilIsDouble(e))
        {
            uint hm = rdHitMid(L, px, s);
            if (hm != 0xFFFFu)
            {
                snapshot();
                float4 r = S[ixA(hm)];
                r.y = 0.5;
                S[ixA(hm)] = r;
            }
        }
        else if (e.type == IL_EV_KEY)
        {
            bool down = e.phase == IL_PH_PRESS && !ilRepeat(e);
            bool downOrRepeat = e.phase == IL_PH_PRESS || e.phase == IL_PH_REPEAT;
            if (down && e.code == IL_KEY_BACKSPACE && g_n > 2u) { snapshot(); removeStop(g_sel); }
            if (down && e.code == IL_KEY_TAB) g_sel = (g_sel + 1u) % g_n;
            if (down && e.code == IL_KEY_F) { snapshot(); flipStops(); }
            if (down && e.code == IL_KEY_E) { snapshot(); evenStops(); }
            if (down && e.code == IL_KEY_Z) swapUndo();
            if (down && e.code == IL_KEY_R)
            {
                snapshot();
                builtin = (builtin + 1u) & 3u;
                writeBuiltin(builtin);
            }
            if (downOrRepeat && (e.code == IL_KEY_LEFT || e.code == IL_KEY_RIGHT))
            {
                if (down) snapshot();
                float4 a = S[ixA(g_sel)];
                a.x = saturate(a.x + (e.code == IL_KEY_RIGHT ? 1.0 : -1.0) / 255.0);
                S[ixA(g_sel)] = a;
                sortStops();
            }
            if (downOrRepeat && (e.code == IL_KEY_UP || e.code == IL_KEY_DOWN))
            {
                if (down) snapshot();
                float4 b = S[ixB(g_sel)];
                b.x = saturate(b.x + (e.code == IL_KEY_UP ? 0.01 : -0.01));
                S[ixB(g_sel)] = b;
            }
        }
    }

    // the chroma each stop can show: what it asked for, brought inside sRGB at its lightness and hue
    [loop] for (uint i = 0u; i < PAL_STOPS; i++)
    {
        if (i >= g_n)
        {
            S[ixA(i)] = 0.0;
            S[ixB(i)] = 0.0;
            continue;
        }
        float4 b = S[ixB(i)];
        b.x = saturate(b.x);
        b.y = clamp(b.y, 0.0, 0.4);
        b.z = b.z - 360.0 * floor(b.z / 360.0);
        b.w = min(b.y, palMaxChroma(b.x, b.z));
        S[ixB(i)] = b;
    }

    // the 256 entries: what any consumer reads
    uint space = min((uint)blend_space, 2u);
    [loop] for (uint k = 0u; k < PAL_ENTRIES; k++)
    {
        bool clip;
        float3 lin = rdBlendAt((float)k / 255.0, space, clip);
        S[PAL_ENTRY0 + k] = float4(palToDisplay(lin), clip ? 1.0 : 0.0);
    }

    S[PAL_HEAD] = float4((float)g_n, (float)PAL_ENTRIES, (float)space, (float)revision(space));
    S[RD_V0] = float4((float)(newest & 0xFFFFu), (float)(newest >> 16), (float)builtin, 0.0);
    S[RD_V1] = float4((float)mode, (float)target, (float)g_sel, (float)flags);
    S[RD_V2] = float4(press, grab, RD_VMAGIC);
}
