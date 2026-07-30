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

StructuredBuffer<AgentRecord> Previous : register(t3);
RWStructuredBuffer<AgentRecord> AgentsOut : register(u0);

static const float2 ANALYSIS_SIZE = float2(480.0, 270.0);
static const float PI = 3.14159265359;

AgentRecord emptyAgent(uint slot)
{
    AgentRecord a;
    a.position = 0.0;
    a.velocity = 0.0;
    a.scale = 0.0;
    a.confidence = 0.0;
    a.angle = 0.0;
    a.age = 0.0;
    a.stable_id = slot;
    a.kind = 0u;
    a.source_index = slot;
    a.flags = 0u;
    a.aux = 0.0;
    return a;
}

AgentRecord blobAgent(uint sourceIndex, uint slot)
{
    AgentRecord a = emptyAgent(slot);
    float2 lo = float2(_Data0[sourceIndex].x1, _Data0[sourceIndex].y1);
    float2 hi = float2(_Data0[sourceIndex].x2, _Data0[sourceIndex].y2);
    float2 extent = max((hi - lo) / ANALYSIS_SIZE, 1e-4);
    a.position = float2(_Data0[sourceIndex].centroidX, _Data0[sourceIndex].centroidY) / ANALYSIS_SIZE;
    a.scale = saturate(sqrt(max(_Data0[sourceIndex].area, 0.0) / 129600.0) * blob_scale_gain);
    a.confidence = saturate(_Data0[sourceIndex].area / max(blob_confidence_area, 1.0));
    a.angle = atan2(extent.y, extent.x);
    a.stable_id = 1000u + sourceIndex;
    a.kind = 0u;
    a.source_index = sourceIndex;
    a.flags = 1u;
    a.aux = float4(lo / ANALYSIS_SIZE, hi / ANALYSIS_SIZE);
    return a;
}

AgentRecord cornerAgent(uint sourceIndex, uint slot)
{
    AgentRecord a = emptyAgent(slot);
    a.position = float2(_Data1[sourceIndex].x, _Data1[sourceIndex].y) / ANALYSIS_SIZE;
    a.scale = corner_scale;
    a.confidence = saturate(log2(1.0 + max(_Data1[sourceIndex].response, 0.0)) * corner_response_gain);
    a.angle = frac((float)sourceIndex * 0.61803398875) * PI * 2.0;
    a.stable_id = 2000u + sourceIndex;
    a.kind = 1u;
    a.source_index = sourceIndex;
    a.flags = 1u;
    a.aux = float4(_Data1[sourceIndex].response, 0.0, 0.0, 0.0);
    return a;
}

AgentRecord lineAgent(uint sourceIndex, uint slot)
{
    AgentRecord a = emptyAgent(slot);
    float2 p0 = float2(_Data2[sourceIndex].x1, _Data2[sourceIndex].y1) / ANALYSIS_SIZE;
    float2 p1 = float2(_Data2[sourceIndex].x2, _Data2[sourceIndex].y2) / ANALYSIS_SIZE;
    a.position = (p0 + p1) * 0.5;
    a.scale = saturate(_Data2[sourceIndex].length / max(line_reference_length, 1.0));
    a.confidence = saturate(a.scale * line_confidence_gain);
    a.angle = radians(_Data2[sourceIndex].angle);
    a.stable_id = 3000u + sourceIndex;
    a.kind = 2u;
    a.source_index = sourceIndex;
    a.flags = 1u;
    a.aux = float4(p0, p1);
    return a;
}

[numthreads(96, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint slot = tid.x;
    if (slot >= 96u) return;

    AgentRecord target = emptyAgent(slot);
    if (slot < 16u)
    {
        if (slot < min(_Data0_Count, 16u)) target = blobAgent(slot, slot);
    }
    else if (slot < 80u)
    {
        uint sourceIndex = slot - 16u;
        if (sourceIndex < min(_Data1_Count, 64u)) target = cornerAgent(sourceIndex, slot);
    }
    else
    {
        uint sourceIndex = slot - 80u;
        if (sourceIndex < min(_Data2_Count, 16u)) target = lineAgent(sourceIndex, slot);
    }

    AgentRecord old = Previous[slot];
    float dt = clamp(_DeltaTime, 0.0, 0.1);
    float response = 1.0 - exp(-dt * tracking_response);
    float release = exp(-dt * release_rate);

    if ((target.flags & 1u) != 0u)
    {
        bool compatible = (old.flags & 1u) != 0u && old.kind == target.kind;
        float2 prior = compatible ? old.position : target.position;
        target.position = lerp(prior, target.position, response);
        target.velocity = (target.position - prior) / max(dt, 1e-3);
        target.scale = compatible ? lerp(old.scale, target.scale, response) : target.scale;
        target.confidence = compatible ? lerp(old.confidence, target.confidence, response) : target.confidence;
        target.angle = compatible ? lerp(old.angle, target.angle, response) : target.angle;
        target.age = compatible ? old.age + dt : 0.0;
    }
    else if ((old.flags & 1u) != 0u && old.confidence > 0.01)
    {
        target = old;
        target.velocity *= release;
        target.confidence *= release;
        target.scale *= release;
        target.age += dt;
        if (target.confidence < 0.025) target.flags = 0u;
    }

    AgentsOut[slot] = target;
}
