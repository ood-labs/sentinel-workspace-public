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

RWStructuredBuffer<ChoirNode> OutputBuffer : register(u0);

static const float PI = 3.14159265359;
static const float TAU = 6.28318530718;

ChoirNode emptyNode(uint index)
{
    ChoirNode n;
    n.position = 0.0;
    n.direction = float2(1.0, 0.0);
    n.weight = 0.0;
    n.kind = 0.0;
    n.group_id = 0.0;
    n.rank = 0.0;
    n.response = 0.0;
    n.radius = 0.0;
    n.active = 0.0;
    n.id = (float)index;
    return n;
}

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint i = tid.x;
    if (i >= 64u) return;

    ChoirNode n = emptyNode(i);
    uint count = min(min(_Data0_Count, (uint)max(node_limit, 0)), 64u);
    if (i >= count)
    {
        OutputBuffer[i] = n;
        return;
    }

    float2 extent = max(float2(input_width, input_height), 1.0);
    float2 position = saturate(float2(_Data0[i].x, _Data0[i].y) / extent);
    float response = max(_Data0[i].response, 0.0);
    if (response < response_floor)
    {
        OutputBuffer[i] = n;
        return;
    }

    float2 macroCenter = 0.5;
    if (_Data1_Count > 0u)
    {
        macroCenter = saturate(float2(_Data1[0].centroidX, _Data1[0].centroidY) / extent);
    }

    float2 radial = position - macroCenter;
    float radialLength = length(radial);
    radial = radialLength > 1e-5 ? radial / radialLength : float2(1.0, 0.0);
    float2 tangent = float2(-radial.y, radial.x);
    float tangentAmount = saturate(tangent_mix * 0.5 + 0.5);
    float2 heading = normalize(lerp(radial, tangent, tangentAmount));

    uint safeGroups = (uint)clamp(group_count, 2, 8);
    float angle = atan2(radial.y, radial.x) + PI;
    float groupId = min(floor(frac(angle / TAU) * (float)safeGroups), (float)(safeGroups - 1u));
    float weight = saturate((response - response_floor) / max(response_span, 0.001));
    float rank = count > 1u ? (float)i / (float)(count - 1u) : 0.0;

    n.position = position;
    n.direction = heading;
    n.weight = weight;
    n.kind = radialLength < 0.16 ? 0.0 : (radialLength < 0.34 ? 1.0 : 2.0);
    n.group_id = groupId;
    n.rank = rank;
    n.response = response;
    n.radius = lerp(0.004, 0.018, weight);
    n.active = 1.0;
    OutputBuffer[i] = n;
}
