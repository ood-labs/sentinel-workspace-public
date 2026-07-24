RWStructuredBuffer<float4> OutputBuffer : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    float4 state = OutputBuffer[0];
    // Z is key code 26 in the authored viewport ABI. This is a live level,
    // so the expression driving StreamDiff hold releases only while held.
    state.x = ViewportKeyDown(26u) ? 1.0 : 0.0;
    state.y = 1.0;
    OutputBuffer[0] = state;
}
