StructuredBuffer<float4> PreviousPhase : register(t0);
RWStructuredBuffer<float4> OutputBuffer : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    float4 previous = PreviousPhase[0];
    float phase = previous.x;
    if (!isfinite(phase)) phase = 0.0;
    float deltaTime = 0.0;
    if (previous.w > 0.5 && isfinite(previous.z))
        deltaTime = clamp(_Time - previous.z, 0.0, 0.25);
    phase += motion_speed * deltaTime * 0.55;
    if (abs(phase) > 10000.0) phase = fmod(phase, 10000.0);
    OutputBuffer[0] = float4(phase, motion_speed, _Time, 1.0);
}
