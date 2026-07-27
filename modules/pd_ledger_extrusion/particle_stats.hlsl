struct ParticleRecord
{
    float3 position;
    float age;
    float3 origin;
    float life;
    float2 axis;
    float mass;
    float seed;
    uint kind;
    uint emitterId;
    uint active;
    uint serial;
};

struct SpawnState
{
    float remainder;
    uint spawnSerial;
    uint spawnBudget;
    uint initialized;
    float cameraDistance;
    float deltaTime;
    float pathPhase;
    float pad;
};

StructuredBuffer<ParticleRecord> ParticleInput : register(t0);
StructuredBuffer<SpawnState> SpawnInput : register(t1);
RWStructuredBuffer<float4> OutputStats : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    float active = 0.0;
    float ageSum = 0.0;
    float depthSum = 0.0;
    [loop]
    for (uint i = 0u; i < 192u; ++i)
    {
        ParticleRecord particle = ParticleInput[i];
        if (particle.active == 0u) continue;
        active += 1.0;
        ageSum += saturate(particle.age / max(particle.life, 1e-4));
        depthSum += particle.position.z;
    }
    SpawnState spawn = SpawnInput[0];
    OutputStats[0] = float4(
        active,
        (float)spawn.spawnSerial,
        ageSum / max(active, 1.0),
        depthSum / max(active, 1.0)
    );
}
