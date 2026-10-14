// One thread per fixture: its patched parts' DMX through the type tables into its canonical state row
// (fe_codec.hlsli feDecode, the GPU twin of Sentinel's engineDecode and of scripts/fe_port.py). The tables are the
// Fixture Rig node's FixtureRender port, and the row stride is the port's (feStateStride). Slots past the type's
// own, inactive records and placeholders get zeros, so nothing from an earlier layout or rig stays in the buffer.
#define GDTF_RENDER _Data2
#include "../_shared/fe_tables.hlsli"
#include "../_shared/fe_rig.hlsli"
#include "../_shared/dmx_schema_v2.hlsli"

RWStructuredBuffer<float2> State : register(u0);
StructuredBuffer<uint> Table : register(t2);

static uint gInst;
static uint gStride;

uint FE_READ_BYTE(uint universe, uint channel)
{
    uint r = universe < DMX_MAX_UNIVERSES ? Table[universe] : 0u;
    return r > 0u ? (_Data1[DMX_UNIVERSE_RECORD_BASE + r - 1u].channels[channel] & 255u) : 0u;
}
void FE_STATE_WRITE(uint slot, float2 v) { State[gInst * gStride + slot] = v; }
float2 FE_STATE_READ(uint slot) { return State[gInst * gStride + slot]; }

#include "../_shared/fe_codec.hlsli"

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint i = tid.x;
    if (i >= FE_N_MAX) return;
    gInst = i;
    gStride = min(feStateStride(), FE_STATE_CAP);
    bool active = i < _Data0_Count && (_Data0[i].flags & FE_INST_ACTIVE) != 0u
               && (_Data0[i].flags & FE_INST_PLACEHOLDER) == 0u && _Data0[i].type < feTypeCount();
    uint used = 0u;
    if (active)
    {
        uint2 bases[FE_PARTS_CAP];
        bases[0] = uint2(_Data0[i].u0, _Data0[i].a0);
        bases[1] = uint2(_Data0[i].u1, _Data0[i].a1);
        bases[2] = uint2(_Data0[i].u2, _Data0[i].a2);
        bases[3] = uint2(_Data0[i].u3, _Data0[i].a3);
        uint mode = _Data0[i].mode;
        feDecode(mode, bases);
        used = min(FE_TYPE_INFO_AT(FE_MODE_INFO_AT(mode).w).z, gStride);
    }
    for (uint s = used; s < gStride; s++)
        State[i * gStride + s] = float2(0.0, 0.0);
}
