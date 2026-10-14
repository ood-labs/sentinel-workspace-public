// SS_Lighting / dmx_encode - the DMX port: one thread per channel of every record. The header and metadata describe the
// live universes (record 9 + u carries port address u, MVR universe u + 1); a universe channel finds its owner in the
// occupancy map and encodes that fixture's state through its GDTF ranges with the fixture engine's codec, exactly as
// FE_Console's encoder does (fe_codec.hlsli mirrors Sentinel's own engineEncodeValue). Unowned channels send 0.
#define GDTF_RENDER _Data5
#include "../_shared/fe_tables.hlsli"
#include "../_shared/dmx_schema_v2.hlsli"
#include "dmx_common.hlsli"

struct DmxRecord { uint channels[512]; };
StructuredBuffer<DmxInst> Inst : register(t0);
StructuredBuffer<float2> StateIn : register(t1);
StructuredBuffer<uint> Occ : register(t2);
RWStructuredBuffer<DmxRecord> Records : register(u0);

uint FE_READ_BYTE(uint universe, uint channel) { return 0u; }   // decode is not used here
void FE_STATE_WRITE(uint slot, float2 v) { }
#include "../_shared/fe_codec.hlsli"

groupshared uint gMaxU;

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID, uint3 gid : SV_GroupID, uint gi : SV_GroupIndex)
{
    uint record = gid.y, c = tid.x;
    if (gi == 0u) gMaxU = 0u;
    GroupMemoryBarrierWithGroupSync();
    for (uint k = gi; k < INST_MAX; k += 64u)
    {
        DmxInst d = Inst[k];
        if (dmxActive(d)) InterlockedMax(gMaxU, d.u0 + 1u);
    }
    GroupMemoryBarrierWithGroupSync();
    if (record >= DMX_RECORDS || c >= 512u) return;
    uint liveU = min(gMaxU, DMX_UNIVERSES);
    uint value = 0u;
    if (record == 0u)
    {
        value = c == 0u ? DMX_SCHEMA_VERSION : (c == 1u ? liveU : (c == 2u ? (uint)_Frame :
                (c == 8u ? DMX_METADATA_RECORDS : (c == 9u ? DMX_UNIVERSE_RECORD_BASE : 0u))));
    }
    else if (record < DMX_UNIVERSE_RECORD_BASE)
    {
        uint mu = (record - 1u) * 128u + c / 4u, field = c % 4u;
        value = field == 0u ? mu : (field == 2u ? (mu < liveU ? 512u : 0u) : 0u);
    }
    else
    {
        uint u = record - DMX_UNIVERSE_RECORD_BASE;
        uint own = u < liveU ? Occ[u * 512u + c] : 0u;
        if (own != 0u && frTablesValid())
        {
            uint k = (own & 0xFFFFu) - 1u, o = own >> 16;
            DmxInst d = Inst[k];
            uint stride = min(feStateStride(), FE_STATE_CAP);
            uint4 pi = FE_PART_INFO_AT(FE_MODE_INFO_AT(d.mode).x);
            uint found = 0xFFFFFFFFu;
            bool fine = false;
            for (uint e = 0u; e < pi.y; e++)
            {
                uint4 en = FE_ENTRY_AT(pi.x + e);
                uint off = en.x & 1023u;
                bool b16 = ((en.x >> 10) & 1u) != 0u;
                bool hit = found == 0xFFFFFFFFu && (off == o || (b16 && off + 1u == o));
                fine = hit ? (b16 && off + 1u == o) : fine;
                found = hit ? pi.x + e : found;
            }
            if (found != 0xFFFFFFFFu)
            {
                uint4 en = FE_ENTRY_AT(found);
                bool b16 = ((en.x >> 10) & 1u) != 0u;
                uint v = FE_CHAN_DEF_AT(en.y);
                if (en.w != 0u)
                {
                    // A channel shared by several cells (one RGB for the whole halo) sends the brightest of them.
                    uint pick = firstbitlow(en.w);
                    if (countbits(en.w) > 1u)
                    {
                        float best = -1e30;
                        for (uint mm = en.w; mm != 0u; mm &= mm - 1u)
                        {
                            uint bit = firstbitlow(mm);
                            float2 sc = StateIn[k * stride + en.z + bit];
                            bool better = sc.x >= -0.5 && sc.y > best;
                            best = better ? sc.y : best;
                            pick = better ? bit : pick;
                        }
                    }
                    float2 st = StateIn[k * stride + en.z + pick];
                    uint enc;
                    if (st.x >= -0.5 && feEncodeValue(en.y, st, b16, enc))
                        v = enc;
                }
                value = b16 ? (fine ? (v & 255u) : (v >> 8) & 255u) : (v & 255u);
            }
        }
    }
    Records[record].channels[c] = value;
}
