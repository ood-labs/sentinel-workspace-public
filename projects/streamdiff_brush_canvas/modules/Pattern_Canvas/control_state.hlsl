RWStructuredBuffer<float4> OutputBuffer : register(u0);

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

    state.x = ViewportKeyDown(26u) ? 1.0 : 0.0;
    state.z = 1.0;
    state.w = 3.0;
    OutputBuffer[0] = state;
}
