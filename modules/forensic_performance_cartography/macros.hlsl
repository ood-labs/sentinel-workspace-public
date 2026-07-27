struct EvidenceAgent
{
    float2 position;
    float2 direction;
    float weight;
    float radius;
    uint kind;
    uint sourceIndex;
    uint groupId;
    uint active;
    float phase;
    float pad;
};

struct PerformanceMacros
{
    float tension;
    float memory;
    float energy;
    float topology;
    float archiveCut;
    float holdMemory;
    float activeAgents;
    float meanWeight;
};

RWStructuredBuffer<PerformanceMacros> OutputBuffer : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    float active = 0.0;
    float weight = 0.0;
    [unroll]
    for (uint i = 0u; i < 64u; ++i)
    {
        if (_Data0[i].active == 0u) continue;
        active += 1.0;
        weight += _Data0[i].weight;
    }

    PerformanceMacros m;
    m.tension = performance_pad.x;
    m.memory = performance_pad.y;
    m.energy = energy;
    m.topology = (float)topology;
    m.archiveCut = archive_cut != 0 ? 1.0 : 0.0;
    m.holdMemory = hold_memory != 0 ? 1.0 : 0.0;
    m.activeAgents = active;
    m.meanWeight = active > 0.0 ? weight / active : 0.0;
    OutputBuffer[0] = m;
}
