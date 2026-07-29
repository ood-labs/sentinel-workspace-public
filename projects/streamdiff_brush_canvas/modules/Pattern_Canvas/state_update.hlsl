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
    bool zWasHeld = ControlState[0].x > 0.5;

    // Audio drive. This pass keeps its OWN latch on the hat counter rather than
    // reading a flag control_state.hlsl set for it. A one-cook flag handed
    // between two passes of the same module has to be written by the producer
    // and read by the consumer on opposite sides of a cook boundary, and this
    // pass runs BEFORE control_state, so the handoff depends on pass ordering
    // that nothing in the manifest guarantees. Latching the counter here
    // instead needs no ordering at all: the count only ever increments, so both
    // passes independently see exactly the same edges.
    // element 1: x=latched hat count, y=window seconds left, w=initialized.
    float dtAudio = clamp(_DeltaTime, 0.0, 0.1);
    float4 audio = OutputBuffer[1];
    bool audioReady = audio.w > 0.5;
    // Stale on the first cook after a load or reload, so latch without firing
    // rather than spending the whole running total as one hit.
    float hatCount = audio_enabled != 0 ? max(audio_hat_count, 0.0) : audio.x;
    bool audioSpawn = audioReady && hatCount > audio.x + 0.5;
    // The window and the stamp are deliberately separate: a hat needs a
    // diffusion window long enough for the generator to produce a frame, but it
    // must still place exactly ONE stamp. Folding the window into zHeld would
    // spawn on every cook the window spans.
    float audioWindow = max(audio.y - dtAudio, 0.0);
    if (audioSpawn) audioWindow = max(audio_hat_hold_ms, 0.0) * 0.001;
    bool audioUnhold = audioWindow > 0.0;
    audio.x = hatCount;
    audio.y = audioWindow;
    // Running total of stamps this pass has actually placed for a hat. Against
    // the detector's own hat count it answers "is every hit landing a stamp"
    // with a number instead of an inference; the spawn records cannot, because
    // their sequence is a wall-clock cycle index that resyncs after each hit.
    if (audioSpawn) audio.z = audio.z + 1.0;
    audio.w = 1.0;
    OutputBuffer[1] = audio;

    // The window counts as "still held" for release detection, so the clock
    // resync happens when the hat's window ends rather than one cook into it.
    bool zReleased = zWasHeld && !zHeld && !audioUnhold;
    // C owns persistent auto-run at Seconds Per Stamp. Z overrides that clock
    // and requests a fresh stamp on every Pattern Canvas cook while held.
    bool effectiveRun = autoRun || zHeld || audioUnhold;
    // An audio stamp pushes state.x off the wall-clock cycle, which leaves
    // newCycle permanently true until the release below resyncs it. Without the
    // !audioUnhold guard the auto-run term would then fire a second stamp
    // inside the window and every hat would land two.
    bool shouldSpawn = zHeld || zPressed || audioSpawn ||
                       (autoRun && newCycle && !audioUnhold);

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
    // Resynchronize the ordinary clock on release so auto-run resumes cleanly
    // without an extra handoff stamp.
    else if (zReleased) {
        action = 0.0;
        state.x = cycleValue;
    }
    else if (!effectiveRun) {
        action = 0.0;
        state.x = cycleValue;
    }
    else if (shouldSpawn) {
        action = 1.0;
        state.x = (zHeld || audioSpawn)
            ? fmod(max(state.x, 0.0) + 1.0, 16777216.0)
            : cycleValue;
    }

    state.y = action;
    state.z = clearValue ? 1.0 : 0.0;
    state.w = 1.0;
    OutputBuffer[0] = state;
}
