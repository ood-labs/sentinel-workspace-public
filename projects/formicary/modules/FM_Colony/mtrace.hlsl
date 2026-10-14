// FM_Colony / mtrace.hlsl — a short history of what the colony is doing, for the canvas.
//
// The readout column traces two measurements over the last four seconds, because both are
// values that MOVE and whose movement is the point: mean body speed is what the kick drives, so
// its trace shows the colony surging on the beat (or not), and mean foot slip is the gait's
// correctness reading, so its trace shows when a fault started rather than only that one exists.
//
// One sample every FC_TRACE_DT seconds of WALL CLOCK into a FC_TRACE_N ring. Time is accumulated
// from _DeltaTime, so the trace spans the same four seconds at 20 cooks a second or 2000; after a
// stall the backlog is dropped rather than replayed as a burst of identical samples. Single
// threaded and downstream of meas by buffer dependency. It reads its own ring through the UAV, the
// way ctl reads its clock: binding it as an input too would null the SRV.
#include "../_shared/formic.hlsli"
#include "../_shared/ui/il_core.hlsli"
#include "colony.hlsli"
#include "colony_view.hlsli"

RWStructuredBuffer<float4> Trace : register(u0);
StructuredBuffer<FmMeas> Meas : register(t1);

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    float4 h = Trace[0];                       // (cursor, samples written, time owed, magic)
    if (h.w != FC_TRACE_MAGIC || !(abs(h.z) < 1e6) || !(h.x >= 0.0) || !(h.y >= 0.0))
        h = float4(0.0, 0.0, 0.0, FC_TRACE_MAGIC);

    h.z += clamp(_DeltaTime, 0.0, 1.0);
    FmMeas m = Meas[0];
    float4 smp = float4(m.speed, m.slip, m.traffic, m.laden);

    [loop] for (uint k = 0u; k < 4u && h.z >= FC_TRACE_DT; k++)
    {
        h.z -= FC_TRACE_DT;
        uint c = (uint)h.x % FC_TRACE_N;
        Trace[1u + c] = smp;
        h.x = (float)((c + 1u) % FC_TRACE_N);
        h.y = min(h.y + 1.0, (float)FC_TRACE_N);
    }
    h.z = min(h.z, FC_TRACE_DT);               // never owe more than one sample
    Trace[0] = h;
}
