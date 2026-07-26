struct SpawnState
{
    float remainder;
    uint spawnSerial;
    uint spawnBudget;
    uint initialized;
    float cameraDistance;
    float deltaTime;
    float pathPhase;
    float pad;
};

RWStructuredBuffer<SpawnState> OutputState : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    SpawnState state = OutputState[0];
    if (state.initialized == 0u)
    {
        state.remainder = 0.0;
        state.spawnSerial = 0u;
        state.spawnBudget = 0u;
        state.initialized = 1u;
        state.cameraDistance = 0.0;
        state.deltaTime = 1.0 / 60.0;
        state.pathPhase = phase;
        state.pad = 0.0;
    }

    float dt = clamp(max(_DeltaTime, 0.004), 0.004, 0.05);
    float desired = state.remainder + spawn_rate * dt;
    uint budget = min((uint)floor(desired), 4u);
    state.remainder = desired - (float)budget;
    state.spawnBudget = budget;
    state.spawnSerial += budget;
    state.cameraDistance = fmod(state.cameraDistance + dt * lerp(0.12, 0.82, camera_follow), 1000.0);
    state.deltaTime = dt;
    state.pathPhase = phase;
    OutputState[0] = state;
}
