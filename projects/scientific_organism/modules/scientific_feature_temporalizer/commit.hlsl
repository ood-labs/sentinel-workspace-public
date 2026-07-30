struct AgentRecord
{
    float2 position;
    float2 velocity;
    float scale;
    float confidence;
    float angle;
    float age;
    uint stable_id;
    uint kind;
    uint source_index;
    uint flags;
    float4 aux;
};

StructuredBuffer<AgentRecord> Current : register(t0);
RWStructuredBuffer<AgentRecord> PreviousOut : register(u0);

[numthreads(96, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x < 96u) PreviousOut[tid.x] = Current[tid.x];
}
