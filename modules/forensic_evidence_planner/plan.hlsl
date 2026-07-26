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

RWStructuredBuffer<EvidenceAgent> OutputBuffer : register(u0);
StructuredBuffer<EvidenceAgent> PreviousAgents : register(t3);

float2 normalizeAnalysis(float2 pixelPosition)
{
    return pixelPosition / max(float2(analysis_width, analysis_height), float2(1.0, 1.0));
}

EvidenceAgent inactiveAgent(uint index)
{
    EvidenceAgent a;
    a.position = float2(0.5, 0.5);
    a.direction = float2(1.0, 0.0);
    a.weight = 0.0;
    a.radius = 0.0;
    a.kind = 0u;
    a.sourceIndex = index;
    a.groupId = index;
    a.active = 0u;
    a.phase = 0.0;
    a.pad = 0.0;
    return a;
}

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint index = tid.x;
    if (index >= 64u) return;

    uint blobCount = min(_Data0_Count, (uint)max_blob_agents);
    uint cornerCount = min(_Data1_Count, (uint)max_corner_agents);
    uint lineCount = min(_Data2_Count, (uint)max_line_agents);
    uint cornerStart = blobCount;
    uint lineStart = blobCount + cornerCount;

    EvidenceAgent a = inactiveAgent(index);

    if (index < blobCount)
    {
        uint i = index;
        float2 pos = normalizeAnalysis(float2(_Data0[i].centroidX, _Data0[i].centroidY));
        float areaNorm = saturate(_Data0[i].area / max(analysis_width * analysis_height, 1.0));
        a.position = pos;
        a.direction = normalize(pos - 0.5 + float2(1e-4, 0.0));
        a.weight = saturate(areaNorm * blob_weight_gain);
        a.radius = clamp(sqrt(areaNorm / 3.14159265) * blob_radius_gain, 0.025, 0.42);
        a.kind = 1u;
        a.sourceIndex = i;
        a.groupId = 1000u + i;
        a.active = 1u;
        a.phase = frac((float)i * 0.173);
    }
    else if (index < lineStart)
    {
        uint i = index - cornerStart;
        float2 pos = normalizeAnalysis(float2(_Data1[i].x, _Data1[i].y));
        float response = max(_Data1[i].response, 0.0);
        float2 dir = normalize(pos - float2(0.5, 0.5) + float2(1e-4, 0.0));
        if (_Data2_Count > 0u)
        {
            uint li = i % _Data2_Count;
            float2 p0 = normalizeAnalysis(float2(_Data2[li].x1, _Data2[li].y1));
            float2 p1 = normalizeAnalysis(float2(_Data2[li].x2, _Data2[li].y2));
            dir = normalize(p1 - p0 + float2(1e-4, 0.0));
        }
        a.position = pos;
        a.direction = dir;
        a.weight = saturate(response * corner_response_scale);
        a.radius = lerp(0.008, 0.035, a.weight);
        a.kind = 2u;
        a.sourceIndex = i;
        a.groupId = 2000u + i;
        a.active = 1u;
        a.phase = frac((float)i * 0.381966);
    }
    else if (index < lineStart + lineCount)
    {
        uint i = index - lineStart;
        float2 p0 = normalizeAnalysis(float2(_Data2[i].x1, _Data2[i].y1));
        float2 p1 = normalizeAnalysis(float2(_Data2[i].x2, _Data2[i].y2));
        float2 delta = p1 - p0;
        a.position = (p0 + p1) * 0.5;
        a.direction = normalize(delta + float2(1e-4, 0.0));
        a.weight = saturate(_Data2[i].length / max(analysis_width, 1.0) * line_weight_gain);
        a.radius = clamp(length(delta) * 0.5, 0.04, 0.45);
        a.kind = 3u;
        a.sourceIndex = i;
        a.groupId = 3000u + i;
        a.active = 1u;
        a.phase = frac((float)i * 0.618034);
    }

    EvidenceAgent prev = PreviousAgents[index];
    bool sameIdentity = prev.active != 0u && prev.kind == a.kind && prev.sourceIndex == a.sourceIndex;
    if (a.active != 0u && sameIdentity)
    {
        float follow = 1.0 - exp(-max(temporal_follow, 0.01) * _DeltaTime * 60.0);
        a.position = lerp(prev.position, a.position, follow);
        a.direction = normalize(lerp(prev.direction, a.direction, follow) + float2(1e-4, 0.0));
        a.weight = lerp(prev.weight, a.weight, follow);
        a.radius = lerp(prev.radius, a.radius, follow);
        a.phase = frac(prev.phase + _DeltaTime * phase_rate * (0.35 + a.weight));
    }

    OutputBuffer[index] = a;
}
