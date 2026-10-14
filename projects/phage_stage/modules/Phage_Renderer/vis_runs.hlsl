// Phage_Renderer / vis_runs - which battens sit on each pixel run: entry run * 32 + j is (rig record + 1) of the j-th batten the
// fixture table puts on that run (its own, by the plot, or one the rig added near it), 0 past the last. led.hlsl finds
// the batten under each texel by where each starts along the run.
#include "../_shared/phage_rig.hlsli"

StructuredBuffer<PhRigInst> Inst : register(t0);
RWStructuredBuffer<uint> Runs : register(u0);

#define VIS_RUNS 64u
#define VIS_UNITS 32u

[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint e = id.x;
    if (e >= VIS_RUNS * VIS_UNITS) return;
    uint b = e / VIS_UNITS, j = e % VIS_UNITS;
    uint n = 0u, found = 0u;
    for (uint k = 0u; k < PH_RIG_MAX; k++)
    {
        PhRigInst d = Inst[k];
        bool on = phRigActive(d) && d.role == ROLE_BATTEN && d.index == b;
        found = (on && n == j && found == 0u) ? k + 1u : found;
        n += on ? 1u : 0u;
    }
    Runs[e] = found;
}
