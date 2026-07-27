RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    float4 state = _Tex0.Load(int3(0, 0, 0));
    if (state.a < 0.5) state = float4(0.0, 0.0, 0.0, 1.0);

    float dt = clamp(_DeltaTime, 0.0, 0.1);
    state.r = fmod(state.r + dt * flow_rate, 4096.0);
    state.g = 0.5 + 0.5 * sin(state.r * 6.28318530718);
    state.b = 0.5 + 0.5 * sin(state.r * 3.88322207745 + 0.73);
    state.a = 1.0;
    OutputUAV[uint2(0, 0)] = state;
}
