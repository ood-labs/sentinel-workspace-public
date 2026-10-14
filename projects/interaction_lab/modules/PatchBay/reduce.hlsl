// Patch Bay / reduce - one thread, every cook: the sources advance (each phase integrated from its
// rate, so turning a rate never makes a source jump), the viewport events edit the patch, the
// outputs are summed from the cables, and the history rings take a sample every 1/50 s.
//
//   drag a source jack to an output jack   patch a cable (starting from an output jack works too)
//   drag a plug out of an output jack      take the newest cable there to another output;
//                                          let go anywhere else and it is unplugged
//   click a cable                          select it            drag its knob up / down: depth
//   matrix cell: click                     patch it (a patched cell: select; again: unplug)
//   matrix cell: drag up / down            depth (patching the cell if it was empty)
//   drag along an output's meter           its base             up / down: the selected depth
//   Backspace                              unplug the selected   Tab: the next cable
//   M                                      mute every cable (each output rests on its base)
//   R                                      the default patch (Z brings the edit back)    Z: undo
#define PB_STATE_RW
#include "../_shared/ui/il_core.hlsli"
#include "../_shared/ui/il_events.hlsli"
#include "bay.hlsli"

static uint g_n;
static int g_sel;
static float g_muted;

void storeHead() { S[PB_HEAD] = float4((float)g_n, PB_MAGIC, g_muted, 0.0); }

// ---------------------------------------------------------------- undo
void snapshot()
{
    storeHead();
    [loop] for (uint i = 0u; i < PB_SAVED; i++) S[PB_UNDO0 + i] = S[i];
    S[PB_U0] = float4(1.0, 0.0, 0.0, 0.0);
}

void readHead()
{
    g_n = min((uint)S[PB_HEAD].x, PB_CABLES);
    g_muted = S[PB_HEAD].z;
    if (g_sel >= (int)g_n) g_sel = -1;
}

void swapUndo()
{
    if (S[PB_U0].x < 0.5) return;
    storeHead();
    [loop] for (uint i = 0u; i < PB_SAVED; i++)
    {
        float4 a = S[i];
        S[i] = S[PB_UNDO0 + i];
        S[PB_UNDO0 + i] = a;
    }
    readHead();
}

void restoreSnapshot()
{
    [loop] for (uint i = 0u; i < PB_SAVED; i++) S[i] = S[PB_UNDO0 + i];
    readHead();
}

// ---------------------------------------------------------------- the patch
uint findCable(uint src, uint dst)
{
    [loop] for (uint k = 0u; k < g_n; k++)
    {
        float4 c = S[PB_CABLE0 + k];
        if ((uint)c.x == src && (uint)c.y == dst) return k;
    }
    return 0xFFFFu;
}

// a cable from src to dst (the one already there if the pair is patched); 0xFFFF when full
uint addCable(uint src, uint dst, float depth)
{
    uint k = findCable(src, dst);
    if (k != 0xFFFFu) return k;
    if (g_n >= PB_CABLES) return 0xFFFFu;
    S[PB_CABLE0 + g_n] = float4((float)src, (float)dst, depth, 0.0);
    g_n++;
    return g_n - 1u;
}

void removeCable(uint k)
{
    if (k >= g_n) return;
    [loop] for (uint j = k; j + 1u < g_n; j++) S[PB_CABLE0 + j] = S[PB_CABLE0 + j + 1u];
    g_n--;
    S[PB_CABLE0 + g_n] = 0.0;
    if (g_sel == (int)k) g_sel = -1;
    else if (g_sel > (int)k) g_sel--;
}

// Six sources, one cable each into an output of the Bloom that follows the bay: the sample and
// hold steps the petal count, the second LFO breathes the petal depth, the ramp winds the twist,
// the first LFO rocks the spin, the external input (the Curve Desk's ball) pumps the size and the
// drift walks the hue.
void writeDefaults()
{
    static const float BASES[PB_OUT] = { 0.40, 0.50, 0.50, 0.50, 0.55, 0.55 };
    static const float3 CABLES[6] = { float3(3, 0, 0.40), float3(1, 1, 0.35), float3(2, 2, -0.50),
                                      float3(0, 3, 0.50), float3(5, 4, 0.30), float3(4, 5, 0.60) };
    [loop] for (uint i = 1u; i < PB_SAVED; i++) S[i] = 0.0;
    [loop] for (uint d = 0u; d < PB_OUT; d++) S[PB_BASE0 + d] = float4(BASES[d], 0.0, 0.0, 0.0);
    [loop] for (uint k = 0u; k < 6u; k++) S[PB_CABLE0 + k] = float4(CABLES[k], 0.0);
    g_n = 6u;
    g_muted = 0.0;
    storeHead();
}

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    float2 res = _Resolution.xy;
    float s = ilCtx(res).s;
    PbLayout L = pbLayout(res, s);
    float dt = clamp(_DeltaTime, 0.0, 0.1);

    g_sel = -1;
    if (S[PB_HEAD].y != PB_MAGIC)
    {
        // nothing saved yet (or another format): the default patch
        writeDefaults();
        S[PB_U0] = 0.0;
        S[PB_V0] = 0.0;
    }
    readHead();
    float4 v0 = S[PB_V0], v1 = S[PB_V1], v2 = S[PB_V2];
    float4 ph = S[PB_PH], ph2 = S[PB_PH2];
    if (v0.w != PB_VMAGIC)
    {
        // working state is never saved: fresh after a reopen
        v0 = float4(0.0, 0.0, 0.0, PB_VMAGIC);
        v1 = float4(0.0, 0.0, -1.0, 0.0);
        v2 = 0.0;
        ph = 0.0;
        ph2 = 0.0;
        [loop] for (uint h = 0u; h < 7u * PB_HIST_RECS; h++) S[PB_HIST0 + h] = 0.5;
    }
    uint mode = (uint)v1.x, target = (uint)v1.y;
    g_sel = (int)v1.z;
    if (g_sel >= (int)g_n) g_sel = -1;
    float origin = v1.w;
    float2 press = v2.xy;

    // 1. the sources: phases advance by their rates (wrapped far out, so S&H keeps its sequence)
    float4 rates = float4(rate_1, rate_2, rate_3, rate_4);
    ph += rates * dt;
    ph = ph - 4096.0 * floor(ph / 4096.0);
    ph2.x += rate_5 * dt;
    ph2.x -= 4096.0 * floor(ph2.x / 4096.0);
    float4 srcA = float4(pbWave(0u, ph.x), pbWave(1u, ph.y), pbWave(2u, ph.z), pbWave(3u, ph.w));
    float ext = saturate(input);
    S[PB_PH] = ph;
    S[PB_SRCV] = srcA;
    S[PB_SRCV2] = float4(pbWave(4u, ph2.x), ext, 0.0, 0.0);

    // 2. the events
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
                uint hs = pbHitSrcJack(L, press, s), hd = pbHitDstJack(L, press, s);
                uint hc = pbHitCell(L, press), hm = pbHitMeter(L, press, s);
                if (hs != 0xFFFFu) { mode = DM_FROM_SRC; target = hs; }
                else if (hd != 0xFFFFu)
                {
                    uint k = pbCableAtDst(hd);
                    if (k != 0xFFFFu) { snapshot(); mode = DM_REPLUG; target = k; g_sel = (int)k; }
                    else { mode = DM_FROM_DST; target = hd; }
                }
                else if (g_sel >= 0 && (length(press - pbCableMid(L, (uint)g_sel, s)) < 11.0 * s || length(press - pbKnob(L, s)) < PB_KNOB_R * s))
                {
                    snapshot();
                    mode = DM_DEPTH;
                    origin = pbDepth((uint)g_sel);
                }
                else if (hc != 0xFFFFu)
                {
                    snapshot();
                    uint k = addCable(hc / PB_OUT, hc % PB_OUT, 0.0);
                    if (k != 0xFFFFu)
                    {
                        mode = DM_CELL;
                        g_sel = (int)k;
                        origin = pbDepth(k);
                    }
                }
                else if (hm != 0xFFFFu) { snapshot(); mode = DM_BASE; target = hm; }
            }
            if (ilIsCancel(e))
            {
                if (mode == DM_REPLUG || mode == DM_DEPTH || mode == DM_CELL || mode == DM_BASE) restoreSnapshot();
                mode = DM_NONE;
                continue;
            }
            v2.zw = px;
            if ((mode == DM_DEPTH || mode == DM_CELL) && g_sel >= 0)
            {
                float4 c = S[PB_CABLE0 + (uint)g_sel];
                c.z = clamp(origin + (press.y - px.y) / (90.0 * s), -1.0, 1.0);
                if (abs(c.z) < 0.02) c.z = 0.0;
                S[PB_CABLE0 + (uint)g_sel] = c;
            }
            else if (mode == DM_BASE)
            {
                float4 m = pbMeter(L, target, s);
                S[PB_BASE0 + target] = float4(saturate((px.x - m.x) / (m.z - m.x)), 0.0, 0.0, 0.0);
            }
            if (e.phase == IL_PH_END)
            {
                if (mode == DM_FROM_SRC)
                {
                    uint hd = pbHitDstJack(L, px, s);
                    if (hd != 0xFFFFu)
                    {
                        if (findCable(target, hd) == 0xFFFFu) snapshot();
                        uint k = addCable(target, hd, 0.5);
                        if (k != 0xFFFFu) g_sel = (int)k;
                    }
                }
                else if (mode == DM_FROM_DST)
                {
                    uint hs = pbHitSrcJack(L, px, s);
                    if (hs != 0xFFFFu)
                    {
                        if (findCable(hs, target) == 0xFFFFu) snapshot();
                        uint k = addCable(hs, target, 0.5);
                        if (k != 0xFFFFu) g_sel = (int)k;
                    }
                }
                else if (mode == DM_REPLUG && target < g_n)
                {
                    uint hd = pbHitDstJack(L, px, s);
                    float4 c = S[PB_CABLE0 + target];
                    if (hd == 0xFFFFu) removeCable(target);              // let go in the air: unplugged
                    else if (hd != (uint)c.y)
                    {
                        uint other = findCable((uint)c.x, hd);
                        if (other != 0xFFFFu)
                        {
                            removeCable(target);                          // that pair is patched already
                            g_sel = (int)(other > target ? other - 1u : other);
                        }
                        else
                        {
                            c.y = (float)hd;
                            S[PB_CABLE0 + target] = c;
                        }
                    }
                }
                mode = DM_NONE;
            }
        }
        else if (ilIsClick(e))
        {
            uint hc = pbHitCell(L, px);
            if (hc != 0xFFFFu)
            {
                uint k = findCable(hc / PB_OUT, hc % PB_OUT);
                if (k == 0xFFFFu)
                {
                    snapshot();
                    k = addCable(hc / PB_OUT, hc % PB_OUT, 0.5);
                    if (k != 0xFFFFu) g_sel = (int)k;
                }
                else if (g_sel == (int)k) { snapshot(); removeCable(k); }
                else g_sel = (int)k;
            }
            else if (pbHitSrcJack(L, px, s) == 0xFFFFu && pbHitDstJack(L, px, s) == 0xFFFFu && pbHitMeter(L, px, s) == 0xFFFFu)
            {
                uint k = pbHitCable(L, px, s);
                g_sel = (k != 0xFFFFu) ? (int)k : -1;
            }
        }
        else if (e.type == IL_EV_KEY)
        {
            bool down = e.phase == IL_PH_PRESS && !ilRepeat(e);
            bool downOrRepeat = e.phase == IL_PH_PRESS || e.phase == IL_PH_REPEAT;
            if (down && e.code == IL_KEY_BACKSPACE && g_sel >= 0) { snapshot(); removeCable((uint)g_sel); }
            if (down && e.code == IL_KEY_TAB && g_n > 0u) g_sel = (int)((uint)(g_sel + 1) % g_n);
            if (down && e.code == IL_KEY_M) g_muted = g_muted > 0.5 ? 0.0 : 1.0;
            if (down && e.code == IL_KEY_R) { snapshot(); writeDefaults(); g_sel = -1; }
            if (down && e.code == IL_KEY_Z) swapUndo();
            if (downOrRepeat && g_sel >= 0 && (e.code == IL_KEY_UP || e.code == IL_KEY_DOWN))
            {
                if (down) snapshot();
                float4 c = S[PB_CABLE0 + (uint)g_sel];
                c.z = clamp(c.z + (e.code == IL_KEY_UP ? 0.05 : -0.05), -1.0, 1.0);
                S[PB_CABLE0 + (uint)g_sel] = c;
            }
        }
    }
    storeHead();

    // 3. the outputs
    float outs[PB_OUT];
    [unroll] for (uint d = 0u; d < PB_OUT; d++)
    {
        float reach;
        float base = pbBase(d);
        outs[d] = g_muted > 0.5 ? base : pbModulate(d, base, reach);
    }
    S[PB_OUTV] = float4(outs[0], outs[1], outs[2], outs[3]);
    S[PB_OUTV2] = float4(outs[4], outs[5], 0.0, 0.0);

    // 4. the history rings, one sample every 1/50 s whatever the cook rate
    uint head = (uint)v0.z % PB_HIST_N;
    float clock = ph2.y + dt;
    [loop] for (uint step = 0u; step < 8u && clock >= PB_HIST_DT; step++)
    {
        clock -= PB_HIST_DT;
        bool4 at = uint4(0u, 1u, 2u, 3u) == (head % 4u).xxxx;
        uint r = PB_HIST0 + head / 4u;
        S[r] = at ? ext.xxxx : S[r];
        [unroll] for (uint lane = 1u; lane < 7u; lane++)
        {
            uint rl = r + lane * PB_HIST_RECS;
            S[rl] = at ? outs[lane - 1u].xxxx : S[rl];
        }
        head = (head + 1u) % PB_HIST_N;
    }
    ph2.y = min(clock, PB_HIST_DT);
    S[PB_PH2] = ph2;

    S[PB_V0] = float4((float)(newest & 0xFFFFu), (float)(newest >> 16), (float)head, PB_VMAGIC);
    S[PB_V1] = float4((float)mode, (float)target, (float)g_sel, origin);
    S[PB_V2] = float4(press, v2.zw);
}
