// FM_Render / ground_out.hlsl — where every pixel of the frame lands on the ground plane.
//
// This is the lane that makes the program image CLICKABLE. FM_Stage shows the finished picture
// and lets you place a station on the ants you are looking at, which needs the inverse of what
// the renderer does: not world to screen, but screen to world.
//
// Publishing it as a texture rather than solving it downstream is the whole trick, and it turns
// two hard problems into none:
//
//   - FM_Stage does not need the camera. It needs no matrix, no synchronised viewpoint, no
//     second camera-capable node, and no nine-float homography threaded through expressions.
//     It samples a texture. Fly the camera anywhere and the clicks follow it, because this pass
//     is built from the same _InvViewProjMatrix the beauty was drawn with, in the same cook.
//
//   - it also solves the OTHER direction without ever computing it. Drawing a station marker
//     normally means projecting world to screen; instead FM_Stage asks "what ground point is
//     under this pixel, and is it inside a station's reach" — which draws the reach as a true
//     perspective ellipse lying on the sweep where the ants actually feel it, rather than as a
//     flat screen-space circle pasted over a receding plane.
//
// Pixels whose ray never meets the plane — anything at or above the horizon — are marked
// invalid in blue rather than left at whatever the arithmetic produced, because a ray that is
// very nearly parallel to the plane produces an enormous finite number, and an enormous finite
// number is indistinguishable from a real coordinate to everything downstream.
#include "../_shared/formic.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);
StructuredBuffer<FmRec> PlanB : register(t0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint w, h;
    OutputUAV.GetDimensions(w, h);
    if (DTid.x >= w || DTid.y >= h) return;

    float2 uv = ((float2)DTid.xy + 0.5) / float2(w, h);
    // NDC, y up.
    float2 ndc = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);

    float4 nearW = mul(_InvViewProjMatrix, float4(ndc, 0.0, 1.0));
    float4 farW  = mul(_InvViewProjMatrix, float4(ndc, 1.0, 1.0));
    float3 p0 = nearW.xyz / max(abs(nearW.w), 1e-6);
    float3 p1 = farW.xyz  / max(abs(farW.w),  1e-6);

    float3 ro = p0;
    float3 rd = p1 - p0;

    // Intersect y = 0. The guard is on the RAY'S SLOPE, not on the resulting distance: a ray
    // 0.001 off parallel does intersect, thousands of millimetres away, and clamping that
    // afterwards would place a click at the edge of the arena instead of rejecting it.
    float denom = rd.y;
    bool valid = (abs(denom) > 1e-5);
    float t = valid ? (-ro.y / denom) : -1.0;
    valid = valid && (t > 0.0) && (t < 1.0);

    float3 hit = ro + rd * t;

    // Only inside the arena counts as placeable. Beyond it there is no substrate, no field and
    // nothing for a station to act on, and allowing a placement there would put a record the
    // plan cannot draw at a coordinate the colony cannot reach.
    FmRec arena = PlanB[FM_ARENA];
    float2 ahalf = fmArenaHalf(arena);
    bool inside = valid && abs(hit.x) <= ahalf.x && abs(hit.z) <= ahalf.y;

    // r,g  world x and z in millimetres
    // b    1 where the ray met the plane inside the arena, 0 otherwise
    OutputUAV[DTid.xy] = float4(inside ? hit.x : 0.0, inside ? hit.z : 0.0, inside ? 1.0 : 0.0, 1.0);
}
