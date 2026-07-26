struct ChoirNode
{
    float2 position;
    float2 direction;
    float weight;
    float kind;
    float group_id;
    float rank;
    float response;
    float radius;
    float active;
    float id;
};

struct ChoirRoute
{
    float2 a;
    float2 b;
    float weight;
    float group_id;
    float active;
    float id;
};

struct CompilerStats
{
    float active_nodes;
    float active_routes;
    float mean_weight;
    float group_coverage;
};

StructuredBuffer<ChoirNode> Nodes : register(t0);
StructuredBuffer<ChoirRoute> Routes : register(t1);
RWStructuredBuffer<CompilerStats> OutputBuffer : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    float nodeCount = 0.0;
    float routeCount = 0.0;
    float weightSum = 0.0;
    uint occupiedMask = 0u;

    [unroll]
    for (uint i = 0u; i < 64u; ++i)
    {
        ChoirNode n = Nodes[i];
        if (n.active > 0.5)
        {
            nodeCount += 1.0;
            weightSum += n.weight;
            uint groupIndex = (uint)clamp(n.group_id, 0.0, 7.0);
            occupiedMask |= 1u << groupIndex;
        }
        routeCount += Routes[i].active > 0.5 ? 1.0 : 0.0;
    }

    float occupied = 0.0;
    [unroll]
    for (uint g = 0u; g < 8u; ++g)
    {
        occupied += (occupiedMask & (1u << g)) != 0u ? 1.0 : 0.0;
    }

    CompilerStats s;
    s.active_nodes = nodeCount;
    s.active_routes = routeCount;
    s.mean_weight = nodeCount > 0.0 ? weightSum / nodeCount : 0.0;
    s.group_coverage = occupied / (float)clamp(group_count, 2, 8);
    OutputBuffer[0] = s;
}
