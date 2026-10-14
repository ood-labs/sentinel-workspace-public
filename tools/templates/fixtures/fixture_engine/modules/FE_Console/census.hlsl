// What the console drives, for the control outputs: element 0 (fixtures programmed, fixtures skipped because their
// type is a placeholder, movers, strobes), element 1 (washes, bars and pixel types, 0, 0). Roles come from the
// fixture's type (fe_tables.hlsli feTypeRole, from the FixtureRender port).
#define GDTF_RENDER _Data1
#include "../_shared/fe_tables.hlsli"
#include "../_shared/fe_rig.hlsli"

RWStructuredBuffer<float4> Status : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint programmed = 0u, skipped = 0u;
    uint roles[4] = { 0u, 0u, 0u, 0u };
    uint n = min(_Data0_Count, (uint)FE_N_MAX);
    for (uint i = 0u; i < n; i++)
    {
        uint f = _Data0[i].flags;
        if ((f & FE_INST_ACTIVE) == 0u) continue;
        if ((f & FE_INST_PLACEHOLDER) != 0u || _Data0[i].type >= feTypeCount()) { skipped++; continue; }
        programmed++;
        roles[min(feTypeRole(_Data0[i].type), 3u)]++;
    }
    Status[0] = float4((float)programmed, (float)skipped, (float)roles[1], (float)roles[2]);
    Status[1] = float4((float)roles[0], (float)roles[3], 0.0, 0.0);
}
