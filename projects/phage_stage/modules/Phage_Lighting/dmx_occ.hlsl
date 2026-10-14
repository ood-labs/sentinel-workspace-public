// Phage_Lighting / dmx_occ - who owns each channel: one thread per channel of the 64 universes, (fixture + 1) in the low 16
// bits and the channel's offset inside that fixture's footprint in the high 16, 0 when nothing is patched there. Each
// group of 64 channels gathers the fixtures overlapping it first, as FE_Console's encoder does. The encoder and the
// map read it; a channel two fixtures claim keeps the lower record (the Fixture Rig's validate names the overlap).
#define GDTF_RENDER _Data6
#include "../_shared/fe_tables.hlsli"
#include "dmx_common.hlsli"

StructuredBuffer<DmxInst> Inst : register(t0);
RWStructuredBuffer<uint> Occ : register(u0);

groupshared uint gCand[64];
groupshared uint gN;

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID, uint3 gid : SV_GroupID, uint gi : SV_GroupIndex)
{
    uint u = gid.y, c0 = gid.x * 64u, c = c0 + gi;
    if (gi == 0u) gN = 0u;
    GroupMemoryBarrierWithGroupSync();
    for (uint k = gi; k < INST_MAX; k += 64u)
    {
        DmxInst d = Inst[k];
        uint fp = dmxActive(d) ? FE_PART_INFO_AT(FE_MODE_INFO_AT(d.mode).x).z : 0u;
        if (dmxActive(d) && d.u0 == u && d.a0 <= c0 + 64u && d.a0 + fp - 1u >= c0 + 1u)
        {
            uint j;
            InterlockedAdd(gN, 1u, j);
            if (j < 64u) gCand[j] = k;
        }
    }
    GroupMemoryBarrierWithGroupSync();
    uint owner = 0u;
    uint best = 0xFFFFFFFFu;
    uint addr = c + 1u;
    for (uint q = 0u; q < min(gN, 64u); q++)
    {
        uint k = gCand[q];
        DmxInst d = Inst[k];
        uint fp = FE_PART_INFO_AT(FE_MODE_INFO_AT(d.mode).x).z;
        if (addr >= d.a0 && addr < d.a0 + fp && k < best)
        {
            best = k;
            owner = (k + 1u) | ((addr - d.a0) << 16);
        }
    }
    Occ[u * 512u + c] = owner;
}
