// Kit / state - publishes the host controls' values exactly as the host holds them.
//
// The xypad value is copied UNMODIFIED (host Y-up). Nothing here flips, rescales or smooths a
// published value: the published numbers, the Properties values and the drawn reticle must agree,
// and the render pass prints all three side by side so any drift is visible.
//
// The button is counted from the host's held flag (a rising edge), not from the `button`
// parameter global - that global is a one-way latch, and counting edges is what makes the count
// undoable state rather than a pulse that can be missed between cooks.
#include "_labels.generated.hlsli"

RWStructuredBuffer<float4> KitState : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    float4 e1 = KitState[1];
    float4 e2 = KitState[2];

    bool fireDown = (_ViewportControlState[UI_FIRE].flags & (VIEWPORT_CONTROL_HELD | VIEWPORT_CONTROL_ACTIVE)) != 0u;
    bool wasDown = e2.y > 0.5;
    float fires = e1.x + ((fireDown && !wasDown) ? 1.0 : 0.0);
    // the level's peak hold, for the meter specimen: up with the fader at once, back 0.4 a second
    float peak = max(k_level, e2.z - 0.4 * _DeltaTime);

    KitState[0] = float4(k_point.x, k_point.y, k_amount, k_level);
    KitState[1] = float4(fires, (float)k_mode, (float)k_hold, (float)k_latch);
    KitState[2] = float4((float)k_enabled, fireDown ? 1.0 : 0.0, peak, 0.0);
    KitState[3] = float4(_ViewportControlState[UI_POINT].value, _ViewportControlState[UI_POINT].value2, 0.0, 0.0);
}
