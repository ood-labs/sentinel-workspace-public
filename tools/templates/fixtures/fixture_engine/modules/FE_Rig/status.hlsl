// The rig FE_Rig holds, for the plot's status line and the control outputs: element 0 (rig state, Fixtures records
// held, records with no rig type or engine mode, records past the engine's 1024), element 1 (records drawn as
// placeholders, 0, 0, 0).
#define GDTF_RENDER _Data1
#include "../_shared/fe_tables.hlsli"
#include "../_shared/fe_rig.hlsli"
#include "records.hlsli"

RWStructuredBuffer<float4> Status : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint4 c = feRigCensus();
    uint state = c.x == 0u ? FE_RIG_NONE : FE_RIG_HELD;
    Status[0] = float4((float)state, (float)c.x, (float)c.y, (float)c.z);
    Status[1] = float4((float)c.w, 0.0, 0.0, 0.0);
}
