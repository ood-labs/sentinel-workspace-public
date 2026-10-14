// Touch / observe - the DIAGNOSTICS reducer (one thread): the event log, the counters that make
// the input rules visible, and click ripples.
//
// The counters are the point of this station:
//   consumed         events applied exactly once
//   stale skipped    events the host handed back again on later cooks (rule 1 at work - without
//                    the sequence guard each of these would have been applied again)
//   watermark resets the host's sequence counter restarted below our persisted watermark (rule 2)
//   wheel notches    the running sum of ev.value - fractional on precision wheels (rule 3)
// Pointer moves are counted but not logged: they would flood the log.
#include "../_shared/ui/il_core.hlsli"
#include "../_shared/ui/il_events.hlsli"
#include "touch.hlsli"

RWStructuredBuffer<uint4> Ob : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    float2 res = _Resolution.xy;
    ILCtx cx = ilCtx(res);
    TouchLayout L = touchLayout(res, cx.s);
    float dt = clamp(_DeltaTime, 0.0, 0.1);

    uint4 sq = Ob[O_SEQ];
    uint4 cn = Ob[O_CNT];
    uint4 pub = Ob[O_PUB];
    uint lastSeq = ilEvWatermark(sq.x);
    uint consumed = sq.y, stale = sq.z, resets = sq.w + ((lastSeq != sq.x) ? 1u : 0u);
    uint moves = cn.x, logHead = cn.y, ripHead = cn.z;
    float wheelSum = asfloat(cn.w);
    if (!(abs(wheelSum) < 1e6)) wheelSum = 0.0;
    float clock = asfloat(pub.w);
    if (!(clock >= 0.0 && clock < 1e7)) clock = 0.0;
    clock += dt;
    float2 lastUv = float2(asfloat(pub.y), asfloat(pub.z));
    uint newest = lastSeq;

    // age the ripples (decay by real time, never per cook)
    [loop] for (uint r = 0u; r < T_RIPPLE_N; r++)
    {
        uint4 rp = Ob[O_RIP + r];
        float age = asfloat(rp.z);
        if (rp.w != 0u && age < 2.0) Ob[O_RIP + r] = uint4(rp.xy, asuint(age + dt), rp.w);
    }

    uint n = ilEvCount();
    [loop] for (uint i = 0u; i < n; i++)
    {
        ViewportEvent e = _ViewportEvents[i];
        if (!ilEvFresh(e.sequence, lastSeq)) { stale++; continue; }
        newest = ilEvAdvance(newest, lastSeq, e.sequence);
        consumed++;
        float2 px = ilEvPx(e, res);
        bool inside = ilIn(px, L.ink);
        float2 uv = saturate(pxToInk(L, px));
        if (inside) lastUv = uv;
        if (e.type == IL_EV_MOVE) { moves++; continue; }

        uint slot = O_LOG + 2u * (logHead % T_LOG_N);
        Ob[slot] = uint4(e.sequence, (e.type & 0xFFu) | ((e.phase & 0xFFu) << 8) | ((e.code & 0xFFFFu) << 16), e.modifiers, asuint(e.value));
        Ob[slot + 1u] = uint4(asuint(e.position.x), asuint(e.position.y), asuint(e.delta.x), asuint(e.delta.y));
        logHead++;

        if (e.type == IL_EV_WHEEL) wheelSum += ilWheel(e);
        uint kind = 0u;
        if (ilIsClick(e) && inside) kind = 1u;
        if (ilIsDouble(e) && inside) kind = 2u;
        if (kind != 0u)
        {
            Ob[O_RIP + (ripHead % T_RIPPLE_N)] = uint4(asuint(uv.x), asuint(uv.y), asuint(0.0), kind);
            ripHead++;
        }
    }

    Ob[O_SEQ] = uint4(newest, consumed, stale, resets);
    Ob[O_CNT] = uint4(moves, logHead, ripHead, asuint(wheelSum));
    Ob[O_PUB] = uint4(asuint((float)consumed), asuint(lastUv.x), asuint(lastUv.y), asuint(clock));
}
