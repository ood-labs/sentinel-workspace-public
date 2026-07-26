RWStructuredBuffer<float4> OutputBuffer : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    float4 state = OutputBuffer[0];
    state.x += 1.0;
    state.y = _Time;
    OutputBuffer[0] = state;
}
