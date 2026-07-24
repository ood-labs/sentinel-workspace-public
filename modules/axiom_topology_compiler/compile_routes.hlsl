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

StructuredBuffer<ChoirNode> Nodes : register(t0);
RWStructuredBuffer<ChoirRoute> OutputBuffer : register(u0);

ChoirRoute emptyRoute(uint index)
{
    ChoirRoute r;
    r.a = 0.0;
    r.b = 0.0;
    r.weight = 0.0;
    r.group_id = 0.0;
    r.active = 0.0;
    r.id = (float)index;
    return r;
}

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint i = tid.x;
    if (i >= 64u) return;

    ChoirRoute route = emptyRoute(i);
    ChoirNode current = Nodes[i];
    if (current.active < 0.5 || i == 0u)
    {
        OutputBuffer[i] = route;
        return;
    }

    int bestIndex = -1;
    float bestDistance = 100.0;

    if (route_mode == 0)
    {
        for (int j = (int)i - 1; j >= 0; --j)
        {
            if (Nodes[j].active > 0.5)
            {
                bestIndex = j;
                bestDistance = length(current.position - Nodes[j].position);
                break;
            }
        }
    }
    else
    {
        [loop]
        for (uint j = 0u; j < i; ++j)
        {
            ChoirNode candidate = Nodes[j];
            if (candidate.active < 0.5) continue;
            if (route_mode == 2 && abs(candidate.group_id - current.group_id) > 0.1) continue;
            float d = length(current.position - candidate.position);
            if (d < bestDistance)
            {
                bestDistance = d;
                bestIndex = (int)j;
            }
        }

        if (bestIndex < 0 && route_mode == 2)
        {
            [loop]
            for (uint j = 0u; j < i; ++j)
            {
                ChoirNode candidate = Nodes[j];
                if (candidate.active < 0.5) continue;
                float d = length(current.position - candidate.position);
                if (d < bestDistance)
                {
                    bestDistance = d;
                    bestIndex = (int)j;
                }
            }
        }
    }

    if (bestIndex >= 0 && bestDistance <= max_connection_distance)
    {
        ChoirNode destination = Nodes[(uint)bestIndex];
        float reach = saturate(1.0 - bestDistance / max(max_connection_distance, 1e-4));
        route.a = current.position;
        route.b = destination.position;
        route.weight = saturate(sqrt(max(current.weight * destination.weight, 0.0)) * route_weight) * reach;
        route.group_id = current.group_id;
        route.active = 1.0;
    }

    OutputBuffer[i] = route;
}
