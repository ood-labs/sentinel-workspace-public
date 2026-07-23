RWStructuredBuffer<float4> OutputBuffer : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    float4 clockState = OutputBuffer[0];
    if (clockState.w < 0.5 || isnan(clockState.x)) {
        clockState = float4(0.0, animation_speed, 0.0, 1.0);
    }
    clockState.x = frac(clockState.x + max(animation_speed, 0.0) * min(_DeltaTime, 0.05));
    clockState.y = animation_speed;
    clockState.z += min(_DeltaTime, 0.05);
    OutputBuffer[0] = clockState;
}
