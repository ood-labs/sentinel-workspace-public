struct KineticEvent
{
    float2 position;
    float2 velocity;
    float speed;
    float energy;
    float active;
    float id;
};

RWStructuredBuffer<KineticEvent> OutputBuffer : register(u0);

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint i = tid.x;
    KineticEvent e;
    e.position = 0.0;
    e.velocity = 0.0;
    e.speed = 0.0;
    e.energy = 0.0;
    e.active = 0.0;
    e.id = (float)i;

    if (i < _Data0_Count && _Data0[i].active > 0.5)
    {
        float4 state = _Tex1.Load(int3(i, 0, 0));
        float speed = length(state.zw);
        float energy = smoothstep(speed_threshold,
                                  speed_threshold + speed_softness,
                                  speed);
        e.position = state.xy;
        e.velocity = state.zw;
        e.speed = speed;
        e.energy = energy;
        e.active = step(0.001, energy);
    }
    OutputBuffer[i] = e;
}
