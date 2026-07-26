struct DebtQuantum
{
    float2 position;
    float2 axis;
    float mass;
    float radius;
    uint kind;
    uint sourceIndex;
    uint ledgerId;
    uint active;
    float phase;
    float age;
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

StructuredBuffer<SpawnState> SpawnInput : register(t0);
StructuredBuffer<DebtQuantum> DebtInput : register(t1);
RWStructuredBuffer<ParticleRecord> OutputParticles : register(u0);

uint pdHashU32(uint value)
{
    value ^= value >> 16u;
    value *= 0x7feb352du;
    value ^= value >> 15u;
    value *= 0x846ca68bu;
    value ^= value >> 16u;
    return value;
}

float2 pdPath(float normalizedAge, float2 axis, float seed)
{
    float late = smoothstep(divergence_onset, 1.0, normalizedAge);
    float2 railOffset = path_bend * normalizedAge * normalizedAge * 0.34;
    railOffset += float2(
        sin(normalizedAge * 3.14159265 + seed * 4.0),
        sin(normalizedAge * 2.31 + seed * 5.7)
    ) * path_sway * sin(normalizedAge * 3.14159265) * 0.16;
    float signedSeed = seed * 2.0 - 1.0;
    float2 split = normalize(axis + float2(1e-5, 0.0)) * signedSeed * axis_spread * divergence * late * late;
    return railOffset + split;
}

DebtQuantum pdSelectQuantum(uint serial)
{
    uint start = (serial * 17u + 11u) % 64u;
    DebtQuantum selected = DebtInput[start];
    [loop]
    for (uint step = 0u; step < 64u; ++step)
    {
        DebtQuantum candidate = DebtInput[(start + step * 13u) % 64u];
        if (candidate.active != 0u)
        {
            selected = candidate;
            break;
        }
    }
    return selected;
}

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    SpawnState spawn = SpawnInput[0];

    [loop]
    for (uint i = 0u; i < 192u; ++i)
    {
        ParticleRecord particle = OutputParticles[i];
        if (particle.active != 0u)
        {
            particle.age += spawn.deltaTime;
            if (particle.age >= particle.life)
            {
                particle.active = 0u;
            }
            else
            {
                float normalizedAge = saturate(particle.age / max(particle.life, 1e-4));
                particle.position.xy = particle.origin.xy + pdPath(normalizedAge, particle.axis, particle.seed);
                particle.position.z = normalizedAge * depth_length;
            }
        }
        OutputParticles[i] = particle;
    }

    [loop]
    for (uint spawnIndex = 0u; spawnIndex < 4u; ++spawnIndex)
    {
        if (spawnIndex >= spawn.spawnBudget) break;
        uint serial = spawn.spawnSerial - spawn.spawnBudget + spawnIndex + 1u;
        uint slot = serial % 192u;
        DebtQuantum quantum = pdSelectQuantum(serial);
        if (quantum.active == 0u) continue;

        uint seedBits = pdHashU32(serial ^ quantum.ledgerId ^ (quantum.sourceIndex * 0x9e3779b9u));
        float seed = (float)(seedBits & 0x00ffffffu) / 16777216.0;
        ParticleRecord particle;
        particle.origin = float3(quantum.position, 0.0);
        particle.position = particle.origin;
        particle.age = 0.0;
        particle.life = particle_lifetime * lerp(0.82, 1.18, seed);
        particle.axis = normalize(quantum.axis + float2(1e-5, 0.0));
        particle.mass = quantum.mass;
        particle.seed = seed;
        particle.kind = quantum.kind;
        particle.emitterId = quantum.ledgerId;
        particle.active = 1u;
        particle.serial = serial;
        OutputParticles[slot] = particle;
    }
}
