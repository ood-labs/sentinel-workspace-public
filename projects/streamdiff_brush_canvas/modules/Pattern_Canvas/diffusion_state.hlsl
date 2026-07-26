RWStructuredBuffer<float4> OutputBuffer : register(u0);
StructuredBuffer<float4> ControlState : register(t1);

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    float4 state = OutputBuffer[0];
    float interval = max(spawn_seconds * max((float)diffusion_every, 1.0), 0.05);
    uint cycle = (uint)max(floor(_Time / interval + seed * 0.31), 0.0);
    bool initialized = state.z > 0.5;
    bool newCycle = !initialized || abs(state.x - (float)cycle) > 0.25;
    state.x = (float)cycle;
    // Automatic StreamDiff cadence follows the same C-toggled auto-run state.
    bool automaticCadence = diffusion_sync != 0 && ControlState[0].y > 0.5;
    state.y = (automaticCadence && newCycle) ? 1.0 : 0.0;
    state.z = 1.0;
    state.w = 1.0;
    OutputBuffer[0] = state;
}
