// face_cutout anchor_history — stores each tracked anchor's current feature UV into the anchor ring
// head each frame, so delayed clones can crop the OLD face at the feature's OLD location (position
// delayed in tandem with the image). _Data0 = Face_Stitch anchors.
#include "cutout_common.hlsli"

RWStructuredBuffer<float2> AnchorRingOut : register(u0);   // output: buffer:anchor_ring

[numthreads(16, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint a = DTid.x;
    if (a >= MAX_NODES) return;

    uint slot = ((uint)floor(_Time * capture_rate)) % HF;
    float2 uv = float2(0.5, 0.5);
    if (a < (uint)_Data0_Count)
    {
        PNode n = _Data0[a];
        uv = float2(n.pos.x * 0.5 + 0.5, 0.5 - n.pos.y * 0.5);
    }
    AnchorRingOut[slot * MAX_NODES + a] = uv;
}
