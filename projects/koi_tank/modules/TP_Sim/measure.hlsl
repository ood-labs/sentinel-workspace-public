// TP_Sim / measure.hlsl — reduce the finished surface to numbers that can actually see a fault.
//
// WHY THERE ARE MOTION METRICS AND NOT JUST HEIGHT METRICS.
//
// Peak and RMS of HEIGHT cannot detect the failure that matters here. A standing wave — the
// surface flipping up and down in place, never travelling, never dying — has a peak and an RMS
// that are CONSTANT. So does water at rest, at a different value. Watching those two numbers
// hold steady and concluding "stable" is not a weak measurement, it is a measurement of the
// wrong quantity: it is blind to oscillation by construction, and it reported "settled" on a
// tank that was visibly thrashing.
//
// The quantity that separates them is MOTION. Instantaneous velocity alone is not enough either,
// because every point of a standing wave passes through v = 0 twice a cycle and a single frame
// would sample some of them at exactly the wrong moment. So this reduces the motion ENVELOPE,
//
//     env = sqrt( v^2 + (h / tau)^2 )
//
// which is the smooth amplitude of the local oscillation rather than its instantaneous value.
// It is ZERO for still water, and large and steady for a standing wave. That is the number.
#include "sim.hlsli"

RWStructuredBuffer<float4> Metrics : register(u0);

groupshared float gPeak[256];
groupshared float gSum[256];
groupshared float gMPeak[256];
groupshared float gMSum[256];

[numthreads(256, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID, uint gi : SV_GroupIndex)
{
    uint gw, gh;
    _Tex0.GetDimensions(gw, gh);
    uint total = gw * gh;

    float invTau = 1.0 / max(motion_tau, 0.005);

    float pk = 0.0, sm = 0.0, mpk = 0.0, msm = 0.0;
    for (uint i = gi; i < total; i += 256u)
    {
        float2 s = _Tex0.Load(int3(int(i % gw), int(i / gw), 0)).xy;
        pk = max(pk, abs(s.x));
        sm += s.x * s.x;

        float env = sqrt(s.y * s.y + (s.x * invTau) * (s.x * invTau));
        mpk = max(mpk, env);
        msm += env * env;
    }
    gPeak[gi] = pk;  gSum[gi] = sm;
    gMPeak[gi] = mpk; gMSum[gi] = msm;
    GroupMemoryBarrierWithGroupSync();

    for (uint s2 = 128u; s2 > 0u; s2 >>= 1)
    {
        if (gi < s2)
        {
            gPeak[gi]  = max(gPeak[gi],  gPeak[gi + s2]);
            gSum[gi]  += gSum[gi + s2];
            gMPeak[gi] = max(gMPeak[gi], gMPeak[gi + s2]);
            gMSum[gi] += gMSum[gi + s2];
        }
        GroupMemoryBarrierWithGroupSync();
    }

    if (gi == 0u)
    {
        // All four in element 0. A control output bound to element 1 read back as exactly
        // zero while element 0 of the same buffer read correctly, so nothing here relies on
        // indexing past the first element.
        float n = max((float)total, 1.0);
        Metrics[0] = float4(gPeak[0], sqrt(gSum[0] / n), gMPeak[0], sqrt(gMSum[0] / n));
        Metrics[1] = float4(n, 0.0, 0.0, 0.0);
    }
}
