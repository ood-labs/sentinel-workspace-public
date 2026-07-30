#ifndef SENTINEL_PICK3D_HLSLI
#define SENTINEL_PICK3D_HLSLI

// Pointer picking against 3D points, for authored Module viewports.
//
// The ray is built from the SAME injected camera matrices the renderer draws
// with, so what the user clicks is what they see. Nothing here reads an injected
// global directly - pass them in - so the header works in any pass and does not
// require the camera feature to be present under a fixed name.
//
// ---------------------------------------------------------------------------
// Event handling rules that belong with this (all verified the hard way)
// ---------------------------------------------------------------------------
// * Acquire a handle on a RAW BUTTON edge (type 2, code 0 for left), never on the
//   drag GESTURE (type 5, code 3). The gesture carries no button identity, so an
//   RMB camera-fly drag is indistinguishable from a left drag and will grab.
//
// * Latch the handle on acquire and hold it until release. Re-picking every cook
//   drops it during fast pointer motion and on any cook carrying no events. A
//   tool that should sweep (a blade) is the deliberate exception.
//
// * While a handle is held, recompute the target from the CURRENT pointer every
//   cook, not only on cooks that carry events - modules cook far faster than
//   events arrive, and event-only updates make a drag stutter.
//
// * Do not read the wheel unmodified: the host camera consumes it for dolly and
//   fly speed, so an unmodified wheel does two jobs at once. Require a modifier,
//   and offer a key as a guaranteed alternative.
//
// * Reduce events ONCE per cook in a dispatch:[1,1,1] pass and publish derived
//   state; keep heavy passes free of event logic.
// ---------------------------------------------------------------------------

// Builds a world-space ray through a normalised pointer position. Pointer
// coordinates are in the same space as a full-resolution pass's uv, so the centre
// of the preview is (0.5, 0.5); the y flip below is the DirectX NDC convention.
void vp_ray_from_pointer(float2 pointerPos, float4x4 invViewProj,
                         float3 cameraPos, out float3 ro, out float3 rd)
{
    float2 ndc = float2(pointerPos.x * 2.0 - 1.0, 1.0 - pointerPos.y * 2.0);

    float4 nearW = mul(invViewProj, float4(ndc, 0.0, 1.0));
    float4 farW  = mul(invViewProj, float4(ndc, 1.0, 1.0));
    nearW /= nearW.w;
    farW  /= farW.w;

    ro = cameraPos;
    rd = normalize(farW.xyz - nearW.xyz);
}

// Sort key for a nearest-point-under-the-cursor reduction.
//
// Candidates inside the pick cylinder sort by distance ALONG the ray, so the
// near face wins rather than whichever point happens to sit closest to the ray
// axis. Everything else sorts far away by perpendicular distance, which keeps a
// sensible fallback when nothing is under the cursor at all. Test the winning key
// against VP_PICK_MISS to tell a real hit from that fallback.
#define VP_PICK_MISS 1e9

float vp_pick_key(float3 p, float3 ro, float3 rd, float pickRadius, out float along)
{
    float3 op = p - ro;
    along = dot(op, rd);
    float perp = length(op - rd * along);
    return (along > 0.0 && perp < pickRadius) ? along : (VP_PICK_MISS + perp);
}

// Point on the ray at a locked depth: the standard "drag in a plane facing the
// camera at the depth the handle was acquired" behaviour.
float3 vp_ray_at(float3 ro, float3 rd, float depth)
{
    return ro + rd * depth;
}

#endif // SENTINEL_PICK3D_HLSLI
