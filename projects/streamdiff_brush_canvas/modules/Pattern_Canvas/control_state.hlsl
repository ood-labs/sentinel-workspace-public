RWStructuredBuffer<float4> OutputBuffer : register(u0);
// canvas_state, written earlier this cook by state_update.hlsl. Element 1 is
// the audio drive latch; .y is the seconds left in the current hi-hat window.
StructuredBuffer<float4> CanvasState : register(t1);

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    float4 state = OutputBuffer[0];
    // State layout: x=Z held, y=auto-run toggle, z=initialized, w=version.
    // Version the state so this hot reload initializes from the visible Run
    // parameter instead of inheriting the old scratch value in y.
    if (state.w < 3.0)
    {
        state.y = run != 0 ? 1.0 : 0.0;
    }

    uint eventCount = min(_ViewportEventCount, 64u);
    for (uint eventIndex = 0u; eventIndex < eventCount; ++eventIndex)
    {
        ViewportEvent eventItem = _ViewportEvents[eventIndex];
        bool cPressed = eventItem.type == 4u &&
                        eventItem.phase == 1u &&
                        eventItem.code == 3u;
        if (cPressed) state.y = state.y > 0.5 ? 0.0 : 1.0;
    }

    // Z and a hi-hat are the same signal downstream: both hold this flag high,
    // and streamdiff_unhold reads it to release Collage Diffusion. The window
    // is owned by state_update rather than re-derived here, so the cook that
    // places a hat's stamp is exactly the cook that unholds the generator.
    bool audioUnhold = CanvasState[1].y > 0.0;
    state.x = (ViewportKeyDown(26u) || audioUnhold) ? 1.0 : 0.0;
    state.z = 1.0;
    state.w = 3.0;
    OutputBuffer[0] = state;
}
