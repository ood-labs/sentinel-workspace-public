// Phage_Renderer / vis_decode - every rig fixture's DMX read back through its own GDTF: one thread per Fixture Rig record
// decodes its break into its canonical state (the fixture engine's codec, as FE_Decode does), defaults first, then each
// patched channel's function and value. The DMX is whatever is linked to the DMX input: Phage_Lighting's, or a DMX In
// receiving a console on the network, which then plays PHAGE the same way.
#define GDTF_RENDER _Data6
#include "../_shared/fe_tables.hlsli"
#include "../_shared/dmx_schema_v2.hlsli"
#include "../_shared/phage_rig.hlsli"

StructuredBuffer<PhRigInst> Inst : register(t0);
RWStructuredBuffer<float2> State : register(u0);

static uint gBase;

uint FE_READ_BYTE(uint universe, uint channel)
{
    uint r = DMX_UNIVERSE_RECORD_BASE + universe;
    return r < _Data0_Count ? _Data0[r].channels[channel] : 0u;
}
void FE_STATE_WRITE(uint slot, float2 v) { State[gBase + slot] = v; }
#include "../_shared/fe_codec.hlsli"

[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint k = id.x;
    if (k >= PH_RIG_MAX || !frTablesValid()) return;
    PhRigInst d = Inst[k];
    if (!phRigActive(d)) return;
    gBase = k * min(feStateStride(), FE_STATE_CAP);
    uint2 parts[FE_PARTS_CAP] = { uint2(d.u0, d.a0), uint2(0u, 0u), uint2(0u, 0u), uint2(0u, 0u) };
    feDecode(d.mode, parts);
}
