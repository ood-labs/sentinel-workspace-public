// Fixture-engine DMX codec over the type tables (fe_tables.hlsli: the FixtureRender port). Mirrors Sentinel's
// FixtureRenderCodec.cpp (engineDecode / engineEncodeValue) and scripts/fe_port.py, which the harnesses and unit tests
// compare against.
//
// The including shader defines, before including this file:
//   uint FE_READ_BYTE(uint universe, uint channel)    universe 0-based, channel 0..511
//   void FE_STATE_WRITE(uint slot, float2 fnParam)     slot within this instance's state row
//   float2 FE_STATE_READ(uint slot)                    (encode only)
// A part base is uint2(universe, address) with address 1..512; address 0 means "not patched".
// A part may run past channel 512 into the next universe (multi-universe overflow).
#ifndef FE_CODEC_HLSLI
#define FE_CODEC_HLSLI

uint feRangeLo(uint r) { return FE_RANGE_AT(r) & 255u; }
uint feRangeHi(uint r) { return (FE_RANGE_AT(r) >> 8) & 255u; }
uint feRangeFn(uint r) { return FE_RANGE_AT(r) >> 16; }

// Range index of `coarse` in channel c. Gaps are present as fn none, so every byte has a range.
uint feRangeAt(uint c, uint coarse)
{
    uint4 ci = FE_CHAN_INFO_AT(c);
    uint found = ci.x;
    for (uint i = 0; i < ci.y; i++)
    {
        uint r = ci.x + i;
        found = (coarse >= feRangeLo(r) && coarse <= feRangeHi(r)) ? r : found;
    }
    return found;
}

float feRangeParam(uint r, uint v, bool b16)
{
    float lo = (float)feRangeLo(r), hi = (float)feRangeHi(r);
    float t = b16 ? ((float)v - lo * 256.0) / ((hi - lo) * 256.0 + 255.0)
                  : (hi > lo ? ((float)v - lo) / (hi - lo) : 0.0);
    float2 p = FE_RANGE_P_AT(r);
    return p.x + (p.y - p.x) * t;
}

uint feByteAt(uint2 base, uint offset)
{
    uint ch = base.y - 1u + offset;              // 0-based channel from the part's start
    return FE_READ_BYTE(base.x + ch / 512u, ch % 512u);
}

// Decode one instance: defaults for every slot of its type, then each patched part's channels.
void feDecode(uint mode, uint2 partBase[FE_PARTS_CAP])
{
    uint4 mi = FE_MODE_INFO_AT(mode);
    uint type = mi.w;
    uint4 ti = FE_TYPE_INFO_AT(type);
    uint slot0 = FE_TYPE_SLOT0_AT(type);
    for (uint s = 0; s < ti.z; s++)
        FE_STATE_WRITE(s, FE_DEFAULT_AT(slot0 + s));
    for (uint p = 0; p < mi.y; p++)
    {
        uint2 base = partBase[p];
        uint4 pi = FE_PART_INFO_AT(mi.x + p);
        for (uint e = 0; e < pi.y; e++)
        {
            uint4 en = FE_ENTRY_AT(pi.x + e);
            uint offset = en.x & 1023u;
            bool b16 = (en.x >> 10) & 1u;
            uint coarse = base.y != 0u ? feByteAt(base, offset) : 0u;
            uint v = b16 ? coarse * 256u + (base.y != 0u ? feByteAt(base, offset + 1u) : 0u) : coarse;
            uint r = feRangeAt(en.y, coarse);
            float2 val = float2((float)feRangeFn(r), feRangeParam(r, v, b16));
            uint mask = en.w;
            for (uint c = 0; c < 32u; c++)
            {
                if (base.y != 0u && ((mask >> c) & 1u))
                    FE_STATE_WRITE(en.z + c, val);
            }
        }
    }
}

// DMX value (8- or 16-bit) for the state value `fp` on channel c; returns false if c has no range with that fn. An open
// shutter on a channel with no open range (a strobe channel whose lowest span is "off") takes the lowest value of its
// first none or closed range, the channel's not-strobing value.
bool feEncodeValue(uint c, float2 fp, bool b16, out uint v)
{
    uint4 ci = FE_CHAN_INFO_AT(c);
    uint fn = (uint)(fp.x + 0.5);
    uint best = 0xFFFFFFFFu;
    float bestErr = 3.0e38;
    for (uint i = 0; i < ci.y; i++)
    {
        uint r = ci.x + i;
        float2 p = FE_RANGE_P_AT(r);
        float a = min(p.x, p.y), b = max(p.x, p.y);
        float err = (fp.y < a) ? a - fp.y : ((fp.y > b) ? fp.y - b : 0.0);
        bool better = feRangeFn(r) == fn && err < bestErr;
        best = better ? r : best;
        bestErr = better ? err : bestErr;
    }
    v = 0u;
    if (best == 0xFFFFFFFFu && fn == FE_FN_OPEN)
    {
        for (uint j = 0; j < ci.y; j++)
        {
            uint fj = feRangeFn(ci.x + j);
            if (fj == FE_FN_NONE || fj == FE_FN_CLOSED)
            {
                v = b16 ? feRangeLo(ci.x + j) * 256u : feRangeLo(ci.x + j);
                return true;
            }
        }
    }
    if (best == 0xFFFFFFFFu)
        return false;
    float2 p = FE_RANGE_P_AT(best);
    float t = (p.y == p.x) ? 0.5 : saturate((fp.y - p.x) / (p.y - p.x));
    float lo = (float)feRangeLo(best), hi = (float)feRangeHi(best);
    v = b16 ? (uint)(lo * 256.0 + round(t * ((hi - lo) * 256.0 + 255.0)))
            : (uint)(lo + round(t * (hi - lo)));
    return true;
}

#endif
