// FM_Colony / ctl.hlsl — the colony's clock and its rebuild decision.
//
// Single threaded, and it reads NOTHING that anything downstream writes. That is a scheduling
// requirement, not a style choice: passes are ordered by buffer dependency, so a clock that
// also reduced the ant buffer would depend on `ants` while `walk` depends on the clock and
// writes `ants`, which is a cycle. Measurement therefore lives in meas.hlsl, downstream.
#include "../_shared/formic.hlsli"
#include "colony.hlsli"

RWStructuredBuffer<FmCtl> Ctl : register(u0);
StructuredBuffer<FmRec> PlanB : register(t1);

// Bump when the SEEDING code changes. The signature is built from parameters and a shader edit
// changes none of them, so without a version bump the persistent buffer keeps serving a colony
// built by the old code and the edit looks like it did nothing.
#define COLONY_VERSION 1.1

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    FmCtl c = Ctl[0];

    // A persistent buffer is not guaranteed to arrive zeroed, and a non-finite clock copied
    // forward poisons every rate in the colony for the lifetime of the project. Tested by
    // magnitude rather than isnan(), so it catches infinity too and cannot be optimised away.
    if (!(abs(c.time) < 1e12) || !(abs(c.pad0) < 1e12)) c = (FmCtl)0;

    // The interval is differenced from _Time rather than read from an injected delta, so this
    // node has no dependency on the viewport-events feature it does not otherwise use. pad0
    // carries the previous _Time.
    //
    // CLAMPED, because the first cook after a compile, a hot reload or a hitch hands over a
    // very large interval, and the whole colony teleporting a second's worth of travel in one
    // frame is indistinguishable from the steering having exploded.
    float now = _Time;
    float dt = clamp(now - c.pad0, 0.0, 0.05);
    c.pad0 = now;
    c.dt = dt;
    c.time += dt;

    // Only STRUCTURAL parameters. Walking speed, gait tuning, pheromone rates and the palette
    // are all out of it, so tuning any of them never resets a colony mid-run.
    float sig = (float)ant_count * 13.7
              + colony_seed * 3.11
              + body_len * 57.3
              + PlanB[FM_NEST].pos.x * 211.3
              + PlanB[FM_NEST].pos.z * 307.1
              + COLONY_VERSION * 601.9;

    bool rebuild = (c.init < 0.5 || abs(sig - c.sig) > 1e-4 || colony_reset > 0.5);
    c.rebuild = rebuild ? 1.0 : 0.0;

    if (rebuild)
    {
        c.sig = sig;
        c.init = 1.0;
        if (colony_reset > 0.5) c.time = 0.0;
    }

    Ctl[0] = c;
}
