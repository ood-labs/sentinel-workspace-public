RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    float4 previous = _Tex0.Load(int3(0, 0, 0));
    float phase = previous.a < 0.5 ? frac(master_phase) : previous.r;

    if (reset_phase != 0)
    {
        phase = frac(master_phase);
    }
    else if (play != 0)
    {
        float safeDt = clamp(_DeltaTime, 0.0, 0.1);
        phase = frac(phase + rate * safeDt);
    }

    OutputUAV[uint2(0, 0)] = float4(phase, rate, (float)play, 1.0);
}
