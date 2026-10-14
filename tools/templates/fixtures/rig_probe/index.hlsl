// Universe lookup from the DMX port's metadata: Table[port address] = record index + 1, 0 when no live record
// carries that address (the fixture engine's FE_Decode index pass, for the schema v2 port).
#include "dmx_schema_v2.hlsli"

RWStructuredBuffer<uint> Table : register(u0);

groupshared uint gAddr[DMX_MAX_UNIVERSES];

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID, uint gi : SV_GroupIndex)
{
    uint cap = _Data2_Count > DMX_UNIVERSE_RECORD_BASE ? min(_Data2_Count - DMX_UNIVERSE_RECORD_BASE, DMX_MAX_UNIVERSES) : 0u;
    for (uint j = gi; j < DMX_MAX_UNIVERSES; j += 64u)
    {
        uint a = 0xFFFFFFFFu;
        if (j < cap)
        {
            uint mr = metadataRecord(j), ms = metadataSlot(j);
            a = _Data2[mr].channels[ms + 2u] > 0u ? _Data2[mr].channels[ms] : 0xFFFFFFFFu;
        }
        gAddr[j] = a;
    }
    GroupMemoryBarrierWithGroupSync();
    uint addr = tid.x;
    if (addr >= DMX_MAX_UNIVERSES) return;
    uint found = 0u;
    for (uint k = 0u; k < cap; k++)
        found = (found == 0u && gAddr[k] == addr) ? k + 1u : found;
    Table[addr] = found;
}
