// Persistent phase accumulator for the line displacement ripple. Keeping the
// accumulated phase in GPU state means changing speed does not jump the wave.
RWStructuredBuffer<float4> OutputBuffer : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    float4 state = OutputBuffer[0];
    if (state.w < 0.5 || !isfinite(state.x))
        state = float4(0.0, 0.0, 0.0, 1.0);

    float dt = min(max(_DeltaTime, 0.0), 0.1);
    state.x = frac(state.x + displace_speed * dt);
    state.w = 1.0;
    OutputBuffer[0] = state;
}
