// Phage_Renderer / vis_frames - where each fixture is now: its GDTF axes and origin as the show's fixture table carries it
// (Phage_Lighting's Rig Fixtures: the rig's placement, ridden on the mount or pixel-run piece it hangs from).
#define GDTF_RENDER _Data6
#include "../_shared/fe_tables.hlsli"
#include "vis_common.hlsli"

StructuredBuffer<PhRigInst> Inst : register(t0);
RWStructuredBuffer<VisFrame> Frames : register(u0);

[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint k = id.x;
    if (k >= PH_RIG_MAX) return;
    VisFrame f = (VisFrame)0;
    if (phRigActive(Inst[k]) && k < _Data1_Count)
    {
        f.x = float4(_Data1[k].x.xyz, 0.0);
        f.y = float4(_Data1[k].y.xyz, 0.0);
        f.z = float4(_Data1[k].z.xyz, 0.0);
        f.o = float4(_Data1[k].o.xyz, 1.0);
    }
    Frames[k] = f;
}
