// FM_Scope / sctl.hlsl — the scope's clock, and the OWNER of the trail ring cursor.
//
// The cursor lives here, advanced once by one thread, rather than in the trail pass where
// sixty-four threads would each try to advance it. A producer must state what it did in the
// buffer it owns; letting each consumer re-derive the cursor from a shared clock does not work,
// because the passes observe that clock a cook apart and land on the slot about to be
// overwritten.
#include "../_shared/formic.hlsli"
#include "scope.hlsli"

RWStructuredBuffer<FmSCtl> Ctl : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    FmSCtl c = Ctl[0];

    // A persistent buffer is not guaranteed to arrive zeroed. Magnitude test, so it catches
    // infinity as well as NaN and cannot be optimised away.
    if (!(abs(c.time) < 1e12) || !(abs(c.prevTime) < 1e12)) c = (FmSCtl)0;

    float now = _Time;
    float dt = clamp(now - c.prevTime, 0.0, 0.05);
    c.prevTime = now;
    c.dt = dt;
    c.time += dt;

    if (trail_reset > 0.5) { c = (FmSCtl)0; c.prevTime = now; }

    // pad0 is the APPEND flag for this cook. The interval is a measurement interval, not a look
    // control: interval x SC_TRAIL_LEN is how far back the trail actually reaches.
    c.pad0 = 0.0;
    if (c.time - c.lastT >= max(trail_rate, 0.004))
    {
        c.lastT = c.time;
        c.writeIdx = (float)(((uint)max(c.writeIdx, 0.0) + 1u) % SC_TRAIL_LEN);
        c.written = min(c.written + 1.0, (float)SC_TRAIL_LEN);
        c.pad0 = 1.0;
    }

    Ctl[0] = c;
}
