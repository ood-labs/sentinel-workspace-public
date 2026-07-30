RWStructuredBuffer<float4> OutputBuffer : register(u0);

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
    bool externalMode = sync_generation != 0;
    float activeCycle = externalMode
        ? floor(max(external_cycle, 0.0))
        : cycleValue;
    bool newCycle = !wasInitialized || abs(state.x - activeCycle) > 0.25;
    bool autoRun = run != 0;
    bool shouldSpawn = autoRun && newCycle;

    int previousStage = (int)round(clamp(state.y, 0.0, 3.0));
    bool revealEnabled = reveal_sequence != 0;
    float action = 0.0;
    if (!wasInitialized || clearEdge) {
        action = -1.0;
        state.x = activeCycle;
    }
    // Once a reveal begins, always finish it even if the run key is released.
    else if (revealEnabled && previousStage >= 1 && previousStage < 3) {
        action = (float)(previousStage + 1);
    }
    else if (!autoRun) {
        action = 0.0;
        state.x = activeCycle;
    }
    else if (shouldSpawn) {
        action = 1.0;
        state.x = activeCycle;
    }

    state.y = action;
    state.z = clearValue ? 1.0 : 0.0;
    state.w = 1.0;
    OutputBuffer[0] = state;
}
