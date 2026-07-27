// Exercises the ring, catch-up and autoscale half of the header from a pass
// that declares no viewport events, which is the point of the probe.

#include "../_shared/ui/sui3_trace.hlsli"

RWStructuredBuffer<float4> Ring : register(u0);

static const uint TP_CAP  = 512u;
static const uint TP_HEAD = 512u;   // state record lives past the ring

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    float4 st = Ring[TP_HEAD];
    uint  cursor   = (uint)max(st.x, 0.0);
    uint  writeIdx = (uint)max(st.y, 0.0);
    float peak     = st.z;

    // Stand-in for a real generation counter; the probe only has to compile and
    // stay bounded, not carry a signal.
    uint latest   = cursor + 3u;
    uint capacity = TP_CAP;

    uint start = sui3CatchupStart(cursor, latest, capacity);
    uint end   = sui3CatchupEnd(start, latest, capacity);

    [loop] for (uint g = start; g <= end; ++g) {
        float dt  = 1.0 / 187.5;
        float val = 0.5;

        peak = sui3PeakDecay(peak, val, dt, 4.0);

        Ring[sui3TraceAt(0u, capacity, writeIdx)] = float4(val, 0.0, 0.0, 0.0);
        writeIdx += 1u;
    }

    peak = sui3PeakLinear(peak, 0.0, max(_DeltaTime, 0.0), 0.55);

    Ring[TP_HEAD] = float4((float)sui3CatchupNext(latest),
                           (float)writeIdx, peak, 0.0);
}
