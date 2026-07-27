RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    float4 previous = _Tex0.Load(int3(0, 0, 0));
    float phase = previous.w > 0.5 ? previous.x : 0.0;
    float resetState = reset > 0 ? 1.0 : 0.0;
    bool resetEdge = previous.w > 0.5 && abs(resetState - previous.z) > 0.5;

    if (resetEdge)
    {
        phase = 0.0;
    }
    else if (scrub_mode > 0)
    {
        phase = frac(scrub_phase);
    }
    else if (play > 0)
    {
        phase = frac(phase + max(rate, 0.0) * min(_DeltaTime, 0.1));
    }

    OutputUAV[uint2(0, 0)] = float4(phase, previous.x, resetState, 1.0);
}
