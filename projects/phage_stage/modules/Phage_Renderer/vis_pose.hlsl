// Phage_Renderer / vis_pose - every mover the renderer draws with PHAGE's model, in Lighting's Pose layout: one thread per mover
// slot, from the fixture of the plot's own type that plays it (the fixture table's slot: PHAGE's own, or the free slot
// an added Halo Beam took). A head of another type in a slot is drawn from its GDTF (guests.hlsl). The mount is the fixture's live frame (frames.hlsl): the GDTF axes are (side, fwd, -up) of PHAGE's
// mount frame. Pan and tilt are what its DMX says, through the GDTF: PHAGE's pan is the GDTF's negated and its tilt
// the GDTF's plus 90 (phage_fixture.hlsli). fixture_id carries the Fixture Rig record, for the optics pass.
#define GDTF_RENDER _Data6
#include "../_shared/fe_tables.hlsli"
#include "../_shared/phage_fixture.hlsli"
#include "vis_common.hlsli"
float4 phD(uint i) { return _Data7[i].value; }

StructuredBuffer<PhRigInst> Inst : register(t0);
StructuredBuffer<VisFrame> Frames : register(t1);
StructuredBuffer<float2> State : register(t2);
RWStructuredBuffer<PhMoverPose> Poses : register(u0);


[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint s = id.x;
    if (s >= PH_RIG_MOVER_SLOTS) return;
    PhMoverPose r = (PhMoverPose)0;
    if (frTablesValid())
    {
        uint own = 0xFFFFFFFFu;
        for (uint k = 0u; k < PH_RIG_MAX; k++)
        {
            PhRigInst d = Inst[k];
            own = (phRigActive(d) && d.role == ROLE_MOVER && d.index == s && own == 0xFFFFFFFFu) ? k : own;
        }
        if (own != 0xFFFFFFFFu && Frames[own].o.w > 0.5)
        {
            PhRigInst d = Inst[own];
            VisFrame f = Frames[own];
            uint2 pt = frPanTilt(d.type);
            uint stride = min(feStateStride(), FE_STATE_CAP);
            float panG = pt.x != FE_SLOT_NONE ? State[own * stride + pt.x].y : 0.0;
            float tiltG = pt.y != FE_SLOT_NONE ? State[own * stride + pt.y].y : 0.0;
            r.position = f.o.xyz;
            r.up = -f.z.xyz;
            r.fwd = f.y.xyz;
            r.pan = radians(-panG);
            r.tilt = radians(tiltG + 90.0);
            r.target_pan = r.pan;
            r.target_tilt = r.tilt;
            r.scale = _Data7_Count >= 6u ? _Data7[5].value.y : 1.0;
            r.fixture_id = (float)own;
            r.active = 1.0;
        }
    }
    Poses[s] = r;
}
