// Scope / sample - one thread: the viewport events, then one sample of the five probes.
//
// The probes are ordinary parameters. Their values come from ref() expressions on them (see the
// README), evaluated once per frame - so this records one sample per cook, stamped with this node's
// clock. Hold stops recording (the window freezes on its last moment); the ring keeps ~17 s.
//
//   drag / click   place the active cursor at that moment (Shift: the other one). A cursor rides
//                  data time, so on a rolling trace it would scroll away within the window:
//                  placing one holds the trace, as stopping a scope to measure does
//   1 / 2          make cursor A / B the active one
//   Space          hold / resume (latched); resuming lets the cursors scroll out with their data
//   Z / X, wheel   zoom the window in / out (1..16 s)
//   C              clear the cursors
#include "../_shared/ui/il_core.hlsli"
#include "../_shared/ui/il_events.hlsli"
#include "scope.hlsli"

RWStructuredBuffer<ScRec> R : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    float2 res = _Resolution.xy;
    ScLayout L = scLayout(res, ilCtx(res).s);

    ScRec h = R[SC_HEAD];
    float window = h.a.y;
    if (!(window >= SC_WIN_MIN && window <= SC_WIN_MAX)) window = 4.0;      // first cook
    uint latches = (uint)h.c;
    uint flags = (uint)h.d;
    uint written = h.f;
    float2 cur = h.b;

    // this node's clock restarts with the node: drop a ring that is now in the future
    float newestT = written > 0u ? R[SC_RING0 + (written - 1u) % SC_N].a.x : 0.0;
    if (written > 0u && _Time < newestT - 0.25)
    {
        written = 0u;
        cur = 0.0;
        flags &= ~SC_HOLD;
    }
    bool hold = (flags & SC_HOLD) != 0u;
    float now = hold ? h.a.x : _Time;

    bool spaceHeld = (latches & 1u) != 0u, zHeld = (latches & 2u) != 0u, xHeld = (latches & 4u) != 0u;
    uint lastSeq = ilEvWatermark(h.e);
    uint newest = lastSeq;
    uint n = ilEvCount();
    [loop] for (uint i = 0u; i < n; i++)
    {
        ViewportEvent e = _ViewportEvents[i];
        if (!ilEvFresh(e.sequence, lastSeq)) continue;
        newest = ilEvAdvance(newest, lastSeq, e.sequence);
        float2 px = ilEvPx(e, res);
        bool inside = ilIn(px, L.plot);
        float t = scT(L, px.x, now, window);
        bool place = inside && ((ilIsDrag(e) && e.phase == IL_PH_BEGIN) || ilIsClick(e));
        if (place && !hold) hold = true;         // now already equals this cook's _Time

        bool wantB = ((flags & SC_ACTIVE_B) != 0u) != ilShift(e);

        if (ilIsDrag(e))
        {
            if (e.phase == IL_PH_BEGIN && inside) flags = (flags & ~(SC_DRAG_A | SC_DRAG_B)) | (wantB ? SC_DRAG_B : SC_DRAG_A);
            if ((flags & SC_DRAG_A) != 0u && e.phase != IL_PH_CANCEL) cur.x = t;
            if ((flags & SC_DRAG_B) != 0u && e.phase != IL_PH_CANCEL) cur.y = t;
            if (e.phase == IL_PH_END || ilIsCancel(e)) flags &= ~(SC_DRAG_A | SC_DRAG_B);
        }
        else if (ilIsClick(e) && inside)
        {
            if (wantB) cur.y = t; else cur.x = t;
        }
        else if (e.type == IL_EV_WHEEL)
        {
            window = clamp(window * pow(2.0, -0.5 * ilWheel(e)), SC_WIN_MIN, SC_WIN_MAX);
        }
        else
        {
            if (ilLatch(e, IL_KEY_SPACE, spaceHeld))
            {
                hold = !hold;
                now = _Time;                     // hold freezes this moment; release resumes live
            }
            if (ilLatch(e, IL_KEY_Z, zHeld)) window = max(window * 0.5, SC_WIN_MIN);
            if (ilLatch(e, IL_KEY_X, xHeld)) window = min(window * 2.0, SC_WIN_MAX);
            if (ilIsKeyDown(e, IL_KEY_C)) cur = 0.0;
            if (ilIsKeyDown(e, IL_KEY_0 + 1u)) flags &= ~SC_ACTIVE_B;
            if (ilIsKeyDown(e, IL_KEY_0 + 2u)) flags |= SC_ACTIVE_B;
        }
    }

    // one sample per cook while live
    if (!hold)
    {
        now = _Time;
        ScRec r = (ScRec)0;
        r.a = float2(_Time, probe_gate);
        r.b = float2(probe_a, probe_b);
        r.c = probe_c;
        r.d = probe_d;
        R[SC_RING0 + written % SC_N] = r;
        written++;
    }
    // a cursor whose moment scrolled out of the window is gone
    if (cur.x < now - window) cur.x = 0.0;
    if (cur.y < now - window) cur.y = 0.0;

    h.a = float2(now, window);
    h.b = cur;
    h.c = (float)((spaceHeld ? 1u : 0u) | (zHeld ? 2u : 0u) | (xHeld ? 4u : 0u));
    h.d = (float)((flags & ~SC_HOLD) | (hold ? SC_HOLD : 0u));
    h.e = newest;
    h.f = written;
    R[SC_HEAD] = h;
}
