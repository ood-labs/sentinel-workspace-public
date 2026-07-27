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
StructuredBuffer<EvidenceStats> Stats : register(t1);
RWTexture2D<float4> OutputUAV : register(u0);

float sdSegment(float2 p, float2 a, float2 b)
{
    float2 pa = p - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * h);
}

float stroke(float d, float width)
{
    float px = 1.5 / max(_Resolution.y, 1.0);
    return 1.0 - smoothstep(width, width + px, d);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / _Resolution.y;
    float2 p = uv * float2(aspect, 1.0);

    float3 ink = float3(0.005, 0.006, 0.006);
    float3 paper = float3(0.78, 0.81, 0.79);
    float3 graphite = float3(0.20, 0.22, 0.21);
    float3 current = current_color;
    float3 col = ink;

    float2 g = abs(frac(uv * float2(24.0, 14.0) + 0.5) - 0.5);
    float grid = 1.0 - smoothstep(0.018, 0.035, min(g.x, g.y));
    col += graphite * grid * 0.16;

    float agentInk = 0.0;
    float warmInk = 0.0;
    [loop]
    for (uint i = 0u; i < 64u; ++i)
    {
        EvidenceAgent a = Agents[i];
        if (a.active == 0u) continue;
        float2 q = a.position * float2(aspect, 1.0);
        float2 dir = normalize(a.direction * float2(aspect, 1.0) + float2(1e-4, 0.0));
        float d = length(p - q);

        if (a.kind == 1u)
        {
            float ring = stroke(abs(d - a.radius), 0.0022);
            float axis = max(
                stroke(sdSegment(p, q - float2(a.radius, 0.0), q + float2(a.radius, 0.0)), 0.0012),
                stroke(sdSegment(p, q - float2(0.0, a.radius), q + float2(0.0, a.radius)), 0.0012));
            warmInk = max(warmInk, (ring + axis * 0.45) * (0.35 + a.weight));
        }
        else if (a.kind == 2u)
        {
            float r = 0.012 + a.radius * 0.35;
            float cross = max(
                stroke(sdSegment(p, q - float2(r, 0.0), q + float2(r, 0.0)), 0.0013),
                stroke(sdSegment(p, q - float2(0.0, r), q + float2(0.0, r)), 0.0013));
            float tangent = stroke(sdSegment(p, q - dir * r * 2.2, q + dir * r * 2.2), 0.0008);
            agentInk = max(agentInk, cross * (0.4 + a.weight) + tangent * 0.35);
        }
        else if (a.kind == 3u)
        {
            float len = max(a.radius, 0.04);
            float segment = stroke(sdSegment(p, q - dir * len, q + dir * len), 0.0018);
            float normalTick = stroke(sdSegment(p, q - float2(-dir.y, dir.x) * 0.015, q + float2(-dir.y, dir.x) * 0.015), 0.0012);
            agentInk = max(agentInk, segment * (0.45 + a.weight) + normalTick);
        }
    }

    col += paper * saturate(agentInk);
    col += current * saturate(warmInk);

    EvidenceStats s = Stats[0];
    float telemetryX = uv.x;
    float bandY = 0.94;
    float band = 1.0 - smoothstep(0.0, 0.006, abs(uv.y - bandY));
    float activeFill = step(telemetryX, saturate(s.activeAgents / 48.0));
    float weightFill = step(telemetryX, saturate(s.meanWeight));
    col += paper * band * activeFill * 0.45;
    col += current * (1.0 - smoothstep(0.0, 0.004, abs(uv.y - (bandY + 0.018)))) * weightFill * 0.8;

    float frame = stroke(abs(max(abs((uv.x - 0.5) * aspect) - aspect * 0.47, abs(uv.y - 0.5) - 0.43)), 0.0015);
    col += paper * frame * 0.55;

    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
