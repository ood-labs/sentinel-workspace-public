struct KineticEvent
{
    float2 position;
    float2 velocity;
    float speed;
    float energy;
    float active;
    float id;
};

struct KineticStats
{
    float active_emitters;
    float peak_speed;
    float mean_energy;
    float reserved;
};

StructuredBuffer<KineticEvent> Events : register(t0);
RWStructuredBuffer<KineticStats> OutputBuffer : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    float activeCount = 0.0;
    float peakSpeed = 0.0;
    float energySum = 0.0;
    [unroll]
    for (uint i = 0u; i < 64u; ++i)
    {
        KineticEvent e = Events[i];
        activeCount += e.active;
        peakSpeed = max(peakSpeed, e.speed);
        energySum += e.energy;
    }

    KineticStats s;
    s.active_emitters = activeCount;
    s.peak_speed = peakSpeed;
    s.mean_energy = activeCount > 0.0 ? energySum / activeCount : 0.0;
    s.reserved = 0.0;
    OutputBuffer[0] = s;
}
