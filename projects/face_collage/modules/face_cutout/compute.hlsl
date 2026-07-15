// face_cutout compute — writes one Clone record per (anchor, copy) into the Clones buffer. For
// history copies (>=1) it overrides the sample UV with the anchor's DELAYED tracking position
// (from the anchor ring), so the crop matches where the feature was in the older frame the draw
// samples. _Data0 = Face_Stitch anchors; AnchorRing = per-frame anchor UVs.
#include "cutout_common.hlsli"

RWStructuredBuffer<Clone> ClonesOut : register(u0);   // output: buffer:clones
StructuredBuffer<float2>  AnchorRing : register(t1);  // t0 = _Data0 (anchors)

float2 delayedAnchorUV(uint anchorIdx, float htf)
{
    float s0 = floor(htf);
    float fr = htf - s0;
    uint sA = ((uint)max(s0, 0.0)) % HF;
    uint sB = ((uint)max(s0, 0.0) + 1u) % HF;
    return lerp(AnchorRing[sA * MAX_NODES + anchorIdx], AnchorRing[sB * MAX_NODES + anchorIdx], fr);
}

[numthreads(64, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint inst = DTid.x;
    if (inst >= MAX_NODES * MAX_COPIES) return;
    uint anchorIdx = inst % MAX_NODES;
    uint copyIdx = inst / MAX_NODES;

    PNode n = _Data0[min(anchorIdx, (uint)max(1, (int)_Data0_Count) - 1u)];
    bool live = (anchorIdx < (uint)_Data0_Count) && (n.active > 0.5) && (copyIdx < (uint)copies);
    Clone c = makeClone(n, copyIdx, live);

    if (live && history_on != 0 && copyIdx >= 1u)
        c.uv = delayedAnchorUV(anchorIdx, ringTimeFor(copyIdx));   // crop the OLD feature location

    ClonesOut[inst] = c;
}
