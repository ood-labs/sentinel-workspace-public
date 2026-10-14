// The encoder: one thread per channel of every DMX record. The header and metadata describe the live
// universes (record 9 + u carries port address u). A universe channel finds the fixture part patched over it
// and encodes that part's channel from the programmer's state through the profile's ranges, exactly as
// Sentinel's engineEncodeValue does on the CPU. The tables are the Fixture Rig node's FixtureRender port; parts run to
// four breaks and placeholders send nothing.
// Gathering per channel needs no clear pass and has no write races.
#define GDTF_RENDER _Data1
#include "../_shared/fe_tables.hlsli"
#include "../_shared/fe_rig.hlsli"
#include "../_shared/dmx_schema_v2.hlsli"

struct DmxRecord { uint channels[512]; };
RWStructuredBuffer<DmxRecord> Records : register(u0);
StructuredBuffer<float2> StateIn : register(t1);

uint FE_READ_BYTE(uint universe, uint channel) { return 0u; }   // decode is not used here
void FE_STATE_WRITE(uint slot, float2 v) { }
#include "../_shared/fe_codec.hlsli"

// Part p's (universe, address) of Rig record k.
uint2 partBase(uint k, uint p)
{
    return p == 0u ? uint2(_Data0[k].u0, _Data0[k].a0) : (p == 1u ? uint2(_Data0[k].u1, _Data0[k].a1)
         : (p == 2u ? uint2(_Data0[k].u2, _Data0[k].a2) : uint2(_Data0[k].u3, _Data0[k].a3)));
}

groupshared uint gParts[64];
groupshared uint gN;
groupshared uint gMaxU;

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID, uint3 gid : SV_GroupID, uint gi : SV_GroupIndex)
{
    uint record = gid.y;
    uint c = tid.x;                       // 0..511
    uint c0 = gid.x * 64u;
    if (gi == 0u) { gN = 0u; gMaxU = 0u; }
    GroupMemoryBarrierWithGroupSync();
    uint stride = min(feStateStride(), FE_STATE_CAP);
    bool isUniverse = record >= DMX_UNIVERSE_RECORD_BASE;
    uint u = isUniverse ? record - DMX_UNIVERSE_RECORD_BASE : 0u;
    for (uint k = gi; k < FE_N_MAX; k += 64u)
    {
        if (k < _Data0_Count && (_Data0[k].flags & FE_INST_ACTIVE) != 0u && (_Data0[k].flags & FE_INST_PLACEHOLDER) == 0u
            && _Data0[k].type < feTypeCount())
        {
            uint4 mi = FE_MODE_INFO_AT(_Data0[k].mode);
            for (uint p = 0u; p < min(mi.y, FE_PARTS_CAP); p++)
            {
                uint2 b = partBase(k, p);
                if (b.y > 0u)
                {
                    uint fp = FE_PART_INFO_AT(mi.x + p).z;
                    InterlockedMax(gMaxU, b.x + 1u);
                    if (isUniverse && b.x == u && b.y <= c0 + 64u && b.y + fp - 1u >= c0 + 1u)
                    {
                        uint j;
                        InterlockedAdd(gN, 1u, j);
                        if (j < 64u) gParts[j] = k | (p << 16);
                    }
                }
            }
        }
    }
    GroupMemoryBarrierWithGroupSync();
    if (record >= DMX_MAX_RECORDS || c >= 512u) return;
    uint liveU = min(gMaxU, DMX_MAX_UNIVERSES);
    uint value = 0u;
    if (record == 0u)
    {
        value = c == 0u ? DMX_SCHEMA_VERSION : (c == 1u ? liveU : (c == 2u ? (uint)_Frame :
                (c == 8u ? DMX_METADATA_RECORDS : (c == 9u ? DMX_UNIVERSE_RECORD_BASE : 0u))));
    }
    else if (!isUniverse)
    {
        uint mu = (record - 1u) * 128u + c / 4u, field = c % 4u;
        value = field == 0u ? mu : (field == 2u ? (mu < liveU ? 512u : 0u) : 0u);
    }
    else if (u < liveU)
    {
        uint addr = c + 1u;
        uint n = min(gN, 64u);
        for (uint q = 0u; q < n; q++)
        {
            uint k = gParts[q] & 0xFFFFu, p = gParts[q] >> 16;
            uint4 mi = FE_MODE_INFO_AT(_Data0[k].mode);
            uint4 pi = FE_PART_INFO_AT(mi.x + p);
            uint a = partBase(k, p).y;
            if (addr >= a && addr < a + pi.z)
            {
                uint o = addr - a;
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
                        // A port channel that drives several cells (one RGB for a whole panel) sends the brightest
                        // of them, so a pattern lights the fixture while any of its cells is lit.
                        uint pick = firstbitlow(en.w);
                        if (countbits(en.w) > 1u)
                        {
                            float best = -1e30;
                            for (uint mm = en.w; mm != 0u; mm &= mm - 1u)
                            {
                                uint bit = firstbitlow(mm);
                                float2 sc = StateIn[k * stride + en.z + bit];
                                if (sc.x >= -0.5 && sc.y > best) { best = sc.y; pick = bit; }
                            }
                        }
                        // An attribute the programmer left untouched (fn -1) sends the channel's default.
                        float2 st = StateIn[k * stride + en.z + pick];
                        uint enc;
                        if (st.x >= -0.5 && feEncodeValue(en.y, st, b16, enc))
                            v = enc;
                    }
                    value = b16 ? (fine ? (v & 255u) : (v >> 8) & 255u) : (v & 255u);
                }
            }
        }
    }
    Records[record].channels[c] = value;
}
