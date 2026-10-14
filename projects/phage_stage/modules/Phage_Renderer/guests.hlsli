// Guests: the rig's fixtures PHAGE's own models do not draw, as vis_gframe poses and lights them (bound at t0): per
// guest slot fe_render.hlsli's frame, 6 pose rows then 128 cells of linear radiance. Include after fe_render.hlsli.
#ifndef PHAGE_GUESTS_HLSLI
#define PHAGE_GUESTS_HLSLI

#define GUESTS 64u
StructuredBuffer<float4> GFrame : register(t0);

// Guest g's pose, false when the slot is empty or the input is missing.
bool guestPose(uint g, out FePose p)
{
    p = (FePose)0;
    uint b = g * FE_FRAME_STRIDE;
    if (g >= GUESTS || b + FE_FRAME_STRIDE > 8576u || !frTablesValid()) return false;
    p.r0 = GFrame[b]; p.r1 = GFrame[b + 1u]; p.r2 = GFrame[b + 2u];
    p.pt = GFrame[b + 3u]; p.pipeA = GFrame[b + 4u]; p.pipeB = GFrame[b + 5u];
    uint type = (uint)(p.pt.w + 0.5);
    return p.pt.z > 0.5 && type < feTypeCount();
}

// Cell c's radiance (c counts over the type's emitters, as FE_CELL_BASE does).
float3 guestCell(uint g, uint c) { return GFrame[g * FE_FRAME_STRIDE + FE_FRAME_EMIT + c].rgb; }

#endif
