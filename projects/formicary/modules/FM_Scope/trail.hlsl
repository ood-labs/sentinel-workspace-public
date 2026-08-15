// FM_Scope / trail.hlsl — record where each ant HAS BEEN.
//
// One thread per ant, appending the current position into that ant's lane when the clock pass
// says the interval has elapsed. This is recorded history, not a curve fitted to the current
// state after the fact — which matters because the whole point of drawing it beside the
// predicted path is that the two came from different places.
#include "../_shared/formic.hlsli"
#include "scope.hlsli"

RWStructuredBuffer<FmTrailPt> Trail : register(u0);
StructuredBuffer<FmSCtl> Ctl  : register(t1);
StructuredBuffer<FmAnt>  Ants : register(t2);

[numthreads(64, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID, uint3 GTid : SV_GroupThreadID)
{
    // SC_ANTS, not the population: the trail buffer has a lane per instrumented ant, and the
    // instrument deliberately covers a readable sample rather than the full colony. See scope.hlsli.
    uint ai = GTid.x;
    if (ai >= SC_ANTS) return;

    FmSCtl c = Ctl[0];
    if (c.pad0 < 0.5) return;                 // not a sampling cook

    FmAnt a = Ants[ai];
    uint slot = ai * SC_TRAIL_LEN + ((uint)max(c.writeIdx, 0.0) % SC_TRAIL_LEN);

    FmTrailPt p;
    p.pos = a.pos;
    // The timestamp IS the validity marker. A zero here means never written, and the drawing
    // pass compares two endpoints' times rather than their ring indices to find the seam.
    p.w = (a.active > 0.5) ? max(c.time, 1e-4) : 0.0;
    Trail[slot] = p;
}
