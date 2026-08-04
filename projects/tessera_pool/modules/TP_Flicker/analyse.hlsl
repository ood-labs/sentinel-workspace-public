// TP_Flicker / analyse.hlsl — an INDEPENDENT flashing detector.
//
// This module trusts nothing upstream. It takes whatever texture it is pointed at, remembers the
// previous frame, and measures the TEMPORAL SECOND DIFFERENCE: how much this frame's change
// differs from the preceding frame's change. A first difference is only a motion detector and
// lights up a perfectly smooth traveling ripple. The second difference stays small for smooth
// motion but becomes large for alternating brightness, discontinuities, and actual flicker.
//
//   - height peak / RMS are CONSTANT for a standing wave and for still water alike;
//   - a motion metric computed inside the sim only sees the sim's own buffer, not the preview
//     the eye is actually judging — and a preview can add flashing of its own, which is exactly
//     what an auto-ranging display does when the signal it is scaling to decays toward zero.
//
// Measuring the delivered PIXELS closes both holes at once.
//
// WHY A STRUCTURED BUFFER AND ONE PASS. The history has to be read and written in the same pass.
// Splitting it into a "store previous frame" pass creates a dependency that the scheduler
// resolves by running the store FIRST, so `prev` already equals the current frame and every
// difference is exactly zero — a detector that always reports success. A structured buffer can
// be read and written through the same UAV, so the history stays in one pass and one writer.
#include "../_shared/plan_theme.hlsli"

RWStructuredBuffer<float4> Hist : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint W, H;
    _Tex0.GetDimensions(W, H);
    if (tid.x >= W || tid.y >= H) return;

    uint idx = tid.y * W + tid.x;
    float4 h = Hist[idx];

    // A persistent buffer is not guaranteed to arrive sane.
    bool ok = (abs(h.x) < 1e5) && (abs(h.y) < 1e5) && (abs(h.z) < 1e5);
    float prev = ok ? h.x : 0.0;
    float hold = ok ? h.y : 0.0;
    float prevStep = ok ? h.w : 0.0;

    float3 c = _Tex0.Load(int3(int2(tid.xy), 0)).rgb;
    float cur = dot(c, float3(0.2126, 0.7152, 0.0722));

    float curStep = cur - prev;
    float d = abs(curStep - prevStep);
    float dt = clamp(_DeltaTime, 1e-5, 0.1);

    // PEAK HOLD with an exponential release, so a flash that happened a moment ago is still on
    // screen when you look. An instantaneous difference map is nearly useless to a human: the
    // frame you happen to capture may be one where the flicker was mid-cycle and near zero.
    hold = max(hold * exp(-max(hold_release, 0.0) * dt), d);

    // Layout: current luminance, held second difference, instantaneous second difference,
    // signed first difference for the next frame. AREA and MEAN read the instantaneous lane;
    // only the visible locator and PEAK remain held.
    Hist[idx] = float4(cur, hold, d, curStep);
}
