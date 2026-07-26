StructuredBuffer<float4> PhaseIn : register(t0);
RWStructuredBuffer<float4> PhaseOut : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    float4 s = PhaseIn[0];
    s.x = frac(s.x + max(0.0, animation_speed) * max(0.0, _DeltaTime));
    s.y = _DeltaTime;
    s.z = _Time;
    s.w = 1.0;
    PhaseOut[0] = s;
}
