// SS_Lighting / dmx_verify - the proof, every frame. Each mover's pan and tilt are decoded back out of the DMX this node
// sends, through the same GDTF tables, and turned into a beam with the GDTF's own convention (pan about the yoke's Z,
// tilt about the head's X, right-handed, home beam -Z) in the fixture's live mount frame, the GDTF axes tools/ss_mvr.py
// plots it with (side, fwd, -up) but where Kinetics has the creature now: pan and tilt are the fixture's own, so the
// beam a real head makes rides the moving truss. The worst angle between that beam and the beam PHAGE draws is the
// beam error, and only quantisation (16-bit pan and tilt, about 0.01 degrees) may separate them. With a DMX In linked to Loopback, every live channel is compared
// with what came back over the network. A moving show differs by a frame or two in flight; held still it must read 0.
//
//   Status[0]  fixtures encoded, movers, strobes, battens
//   Status[1]  live universes, channels above zero, universes received back, channels received different
//   Status[2]  worst beam error (degrees), movers checked, movers whose tilt the GDTF range clamped, loopback linked
#define GDTF_RENDER _Data5
#include "../_shared/fe_tables.hlsli"
#include "../_shared/dmx_schema_v2.hlsli"
#include "../_shared/fe_rig.hlsli"
#include "../_shared/ss_fixture.hlsli"
#include "dmx_common.hlsli"
#include "../_shared/ss_aim.hlsli"

struct DmxRecord { uint channels[512]; };
StructuredBuffer<DmxRecord> Records : register(t0);
StructuredBuffer<SsMoverPose> PoseIn : register(t4);
StructuredBuffer<SsOptical> OpticsIn : register(t5);
StructuredBuffer<SsRigFix> RigFix : register(t7);
StructuredBuffer<DmxInst> Inst : register(t1);
RWStructuredBuffer<float4> Status : register(u0);

uint FE_READ_BYTE(uint universe, uint channel)
{
    return universe < DMX_UNIVERSES ? Records[DMX_UNIVERSE_RECORD_BASE + universe].channels[channel] : 0u;
}
void FE_STATE_WRITE(uint slot, float2 v) { }
#include "../_shared/fe_codec.hlsli"

// The physical value the DMX carries for state slot `slot` of fixture d (its function's parameter).
float decodeSlot(DmxInst d, uint slot)
{
    uint4 pi = FE_PART_INFO_AT(FE_MODE_INFO_AT(d.mode).x);
    float result = 0.0;
    bool done = false;
    for (uint e = 0u; e < pi.y; e++)
    {
        uint4 en = FE_ENTRY_AT(pi.x + e);
        bool hit = !done && slot >= en.z && slot < en.z + 32u && ((en.w >> (slot - en.z)) & 1u) != 0u;
        if (hit)
        {
            uint off = en.x & 1023u;
            bool b16 = ((en.x >> 10) & 1u) != 0u;
            uint2 base = uint2(d.u0, d.a0);
            uint coarse = feByteAt(base, off);
            uint v = b16 ? coarse * 256u + feByteAt(base, off + 1u) : coarse;
            result = feRangeParam(feRangeAt(en.y, coarse), v, b16);
            done = true;
        }
    }
    return result;
}

groupshared uint gCount[16];

[numthreads(64, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    if (gi < 16u) gCount[gi] = 0u;
    GroupMemoryBarrierWithGroupSync();
    bool tables = frTablesValid();
    uint liveU = min(Records[0].channels[1], DMX_UNIVERSES);
    bool loop = _Data6_Count > DMX_UNIVERSE_RECORD_BASE && _Data6[0].channels[0] == DMX_SCHEMA_VERSION;
    for (uint k = gi; k < INST_MAX; k += 64u)
    {
        DmxInst d = Inst[k];
        if (dmxActive(d))
        {
            InterlockedAdd(gCount[0], 1u);
            InterlockedAdd(gCount[1], d.role == ROLE_MOVER ? 1u : 0u);
            InterlockedAdd(gCount[2], d.role == ROLE_STROBE ? 1u : 0u);
            InterlockedAdd(gCount[3], d.role == ROLE_BATTEN ? 1u : 0u);
        }
        bool mover = tables && dmxActive(d) && d.role == ROLE_MOVER && k < _Data4_Count
                     && d.index < SS_MOVER_SLOTS && PoseIn[d.index].active > 0.5 && d.index * SS_OPT_PER < (uint)SS_OPT_STROBE0;
        if (mover)
        {
            uint2 pt = frPanTilt(d.type);
            float p = radians(decodeSlot(d, pt.x)), t = radians(decodeSlot(d, pt.y));
            float3 g = float3(-sin(t) * sin(p), sin(t) * cos(p), -cos(t));
            float3 up = PoseIn[d.index].up, fwd = PoseIn[d.index].fwd;
            float3 beam = normalize(cross(up, fwd) * g.x + fwd * g.y - up * g.z);
            // Another type's head: its pan and tilt through its own GDTF (the fixture engine's head model).
            if (!DMX_NATIVE(d) && k < 1024u)
                beam = ssAimForward(d.type, ssAimFrame(d.type, RigFix[k].x.xyz, RigFix[k].y.xyz, RigFix[k].z.xyz),
                                    decodeSlot(d, pt.x), decodeSlot(d, pt.y));
            float3 drawn = normalize(OpticsIn[d.index * SS_OPT_PER].normal);
            float err = degrees(acos(clamp(dot(beam, drawn), -1.0, 1.0)));
            InterlockedMax(gCount[8], asuint(err));
            InterlockedAdd(gCount[9], 1u);
            float raw = degrees(PoseIn[d.index].tilt) - 90.0;
            InterlockedAdd(gCount[10], DMX_NATIVE(d) && abs(raw) > 135.01 ? 1u : 0u);
        }
    }
    for (uint i = gi; i < liveU * 512u; i += 64u)
    {
        uint u = i / 512u, c = i % 512u;
        uint sent = Records[DMX_UNIVERSE_RECORD_BASE + u].channels[c];
        InterlockedAdd(gCount[4], sent > 0u ? 1u : 0u);
        bool back = loop && DMX_UNIVERSE_RECORD_BASE + u < _Data6_Count
                    && _Data6[metadataRecord(u)].channels[metadataSlot(u) + 2u] > 0u;
        InterlockedAdd(gCount[5], back && c == 0u ? 1u : 0u);
        InterlockedAdd(gCount[6], back && _Data6[DMX_UNIVERSE_RECORD_BASE + u].channels[c] != sent ? 1u : 0u);
    }
    GroupMemoryBarrierWithGroupSync();
    if (gi == 0u)
    {
        Status[0] = float4(gCount[0], gCount[1], gCount[2], gCount[3]);
        Status[1] = float4(liveU, gCount[4], gCount[5], gCount[6]);
        Status[2] = float4(asfloat(gCount[8]), gCount[9], gCount[10], loop ? 1.0 : 0.0);
        Status[3] = float4((float)_Frame, 0.0, 0.0, 0.0);
    }
}
