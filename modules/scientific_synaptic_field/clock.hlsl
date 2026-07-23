RWStructuredBuffer<float4> OutputBuffer : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    float4 state = OutputBuffer[0];
    if (state.w < 0.5 || isnan(state.x)) state = float4(0.0, pulse_rate, 0.0, 1.0);
    float dt = min(_DeltaTime, 0.05);
    state.x = frac(state.x + max(pulse_rate, 0.0) * dt);
    state.y = pulse_rate;
    state.z += dt;
    state.w = 1.0;
    OutputBuffer[0] = state;
}
