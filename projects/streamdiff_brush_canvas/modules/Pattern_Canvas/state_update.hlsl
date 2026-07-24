RWStructuredBuffer<float4> OutputBuffer : register(u0);
StructuredBuffer<float4> ControlState : register(t1);

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    float4 state = OutputBuffer[0];
    bool wasInitialized = state.w > 0.5;
    bool clearValue = clear_toggle != 0;
    bool previousClearValue = state.z > 0.5;
    // Clear on either toggle transition. Unlike a one-frame button pulse, the
    // new value persists until this pass observes it, so no click can be lost.
    bool clearEdge = wasInitialized && clearValue != previousClearValue;

    float seconds = max(spawn_seconds, 0.05);
    uint cycle = (uint)max(floor(_Time / seconds + seed * 0.31), 0.0);
    float cycleValue = (float)(cycle & 0x00ffffffu);
    bool newCycle = !wasInitialized || abs(state.x - cycleValue) > 0.25;
    bool zHeld = ViewportKeyDown(26u);
    bool zPressed = false;
    uint eventCount = min(_ViewportEventCount, 64u);
    for (uint eventIndex = 0u; eventIndex < eventCount; ++eventIndex)
    {
        ViewportEvent eventItem = _ViewportEvents[eventIndex];
        bool keyPress = eventItem.type == 4u && eventItem.phase == 1u;
        if (keyPress && eventItem.code == 26u) zPressed = true;
    }
    bool autoRun = ControlState[0].y > 0.5;
    // C owns persistent auto-run. Z is immediate on press and repeats at
    // Seconds Per Stamp for the full duration of the hold.
    bool effectiveRun = autoRun || zHeld;
    bool shouldSpawn = zPressed || (effectiveRun && newCycle);

    int previousStage = (int)round(clamp(state.y, 0.0, 3.0));
    bool revealEnabled = reveal_sequence != 0;
    float action = 0.0;
    if (!wasInitialized || clearEdge) {
        action = -1.0;
        state.x = cycleValue;
    }
    // Once a reveal begins, always finish it even if the run key is released.
    else if (revealEnabled && previousStage >= 1 && previousStage < 3) {
        action = (float)(previousStage + 1);
    }
    else if (!effectiveRun) {
        action = 0.0;
        state.x = cycleValue;
    }
    else if (shouldSpawn) {
        action = 1.0;
        state.x = cycleValue;
    }

    state.y = action;
    state.z = clearValue ? 1.0 : 0.0;
    state.w = 1.0;
    OutputBuffer[0] = state;
}
