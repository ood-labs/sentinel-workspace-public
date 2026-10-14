// One thread per rig record: the Fixture Rig node's Fixtures record with its rig type, engine mode, mount pose and
// DMX breaks, read through the FixtureRender port (records.hlsli).
#define GDTF_RENDER _Data1
#include "../_shared/fe_tables.hlsli"
#include "../_shared/fe_rig.hlsli"
#include "records.hlsli"

RWStructuredBuffer<FeInst> Rig : register(u0);

[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint i = id.x;
    if (i >= FE_N_MAX) return;
    Rig[i] = feRigRecord(i);
}
