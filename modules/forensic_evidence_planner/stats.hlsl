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

struct EvidenceStats
{
    float activeAgents;
    float meanWeight;
    float blobAgents;
    float lineAgents;
};

StructuredBuffer<EvidenceAgent> Agents : register(t0);
RWStructuredBuffer<EvidenceStats> OutputBuffer : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    float active = 0.0;
    float weight = 0.0;
    float blobs = 0.0;
    float lines = 0.0;
    [unroll]
    for (uint i = 0u; i < 64u; ++i)
    {
        EvidenceAgent a = Agents[i];
        if (a.active == 0u) continue;
        active += 1.0;
        weight += a.weight;
        blobs += a.kind == 1u ? 1.0 : 0.0;
        lines += a.kind == 3u ? 1.0 : 0.0;
    }

    EvidenceStats s;
    s.activeAgents = active;
    s.meanWeight = active > 0.0 ? weight / active : 0.0;
    s.blobAgents = blobs;
    s.lineAgents = lines;
    OutputBuffer[0] = s;
}
