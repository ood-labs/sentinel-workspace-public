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

StructuredBuffer<EvidenceAgent> Agents : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float pressure = 0.0;
    float directionX = 0.5;
    float directionY = 0.5;

    [loop]
    for (uint i = 0u; i < 64u; ++i)
    {
        EvidenceAgent a = Agents[i];
        if (a.active == 0u) continue;
        float2 d = uv - a.position;
        float r = max(a.radius, 0.012);
        float influence = exp(-dot(d, d) / max(r * r, 1e-5)) * a.weight;
        pressure += influence * (a.kind == 1u ? 1.0 : 0.15);
        directionX += a.direction.x * influence * 0.1;
        directionY += a.direction.y * influence * 0.1;
    }

    OutputUAV[tid.xy] = float4(saturate(pressure), saturate(directionX), saturate(directionY), 1.0);
}
