// FM_Colony / meas.hlsl — what the colony is ACTUALLY doing.
//
// Single threaded, downstream of walk and gait, so every number here describes the population
// as it is this cook rather than as it was asked to be. These eight fields are published as
// control outputs and driven onto FM_Plan's flow strip by expression, which is the only reason
// that strip is allowed to draw them in the reserved live colour.
//
// The per-lane shares are measured by asking each walking ant which route it is nearest, not by
// dividing the total by the planned recruitment. Dividing would produce a number that always
// agrees with the plan and therefore can never reveal that the colony is ignoring it — which is
// precisely the thing worth seeing.
#include "../_shared/formic.hlsli"
#include "colony.hlsli"

RWStructuredBuffer<FmMeas> Meas : register(u0);
StructuredBuffer<FmCtl> Ctl   : register(t1);
StructuredBuffer<FmAnt> Ants  : register(t2);
StructuredBuffer<FmFoot> Feet : register(t3);
StructuredBuffer<FmRec> PlanB : register(t4);

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    FmMeas m = Meas[0];
    FmCtl ctl = Ctl[0];
    FmRec arena = PlanB[FM_ARENA];

    if (!(abs(m.delivered) < 1e12) || ctl.rebuild > 0.5) m = (FmMeas)0;

    uint n = min((uint)ant_count, FM_MAX_ANTS);

    float walking = 0.0, laden = 0.0, speedSum = 0.0, slipSum = 0.0, slipN = 0.0;
    float maxSlip = 0.0, contactSum = 0.0, offTrail = 0.0;
    float lane[4] = { 0.0, 0.0, 0.0, 0.0 };

    for (uint i = 0u; i < n; i++)
    {
        FmAnt a = Ants[i];
        if (a.active < 0.5) continue;

        int task = (int)(a.task + 0.5);
        bool isWalking = (task == 0 || task == 2);

        if (a.load > 0.5) laden += 1.0;
        contactSum += a.contact;

        if (isWalking)
        {
            walking += 1.0;
            speedSum += a.speed;

            // Nearest lane, measured. Lane index is the ACTIVE-edge ordinal, matching the
            // order the flow strip stacks its lanes, so lane 2 in the readout is the third
            // lane down the strip and not the third slot in the buffer.
            uint ord = 0u, found = 0xffffffffu;
            for (uint e = 0u; e < FM_EDGES; e++)
            {
                if (PlanB[FM_EDGE_0 + e].active < 0.5) continue;
                if ((uint)(a.edge + 0.5) == e + 1u) found = ord;
                ord++;
            }
            if (found < 4u) lane[found] += 1.0;
            else if (found == 0xffffffffu) offTrail += 1.0;
        }

        // Slip is a PER-STEP measure, so only legs currently bearing weight contribute. A
        // swinging foot has no slip by definition, and averaging its zero in would halve every
        // reading and hide the fault the number exists to expose.
        for (uint lg = 0u; lg < FM_LEGS; lg++)
        {
            FmFoot f = Feet[i * FM_LEGS + lg];
            if (f.stance > 0.5)
            {
                slipSum += f.slip;
                slipN += 1.0;
                maxSlip = max(maxSlip, f.slip);
            }
        }
    }

    float inv = 1.0 / max((float)n, 1.0);
    float invW = 1.0 / max(walking, 1.0);

    m.traffic = walking;
    m.laden = laden * inv;
    m.speed = speedSum * invW;
    // Smoothed, because slip is spiky by nature — it fires on the cooks where a leg is
    // re-planted — and an unsmoothed readout flickers between zero and its peak too fast to
    // read, which makes a real fault look like noise.
    m.slip = lerp(m.slip, (slipN > 0.5) ? slipSum / slipN : 0.0, saturate(ctl.dt * 3.0));
    m.maxSlip = maxSlip;
    m.contact = contactSum * inv;
    m.offTrail = offTrail * invW;

    m.e0 = lane[0] * invW;
    m.e1 = lane[1] * invW;
    m.e2 = lane[2] * invW;
    m.e3 = lane[3] * invW;

    Meas[0] = m;
}
