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

StructuredBuffer<AgentRecord> Agents : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

float sdSegment(float2 p, float2 a, float2 b)
{
    float2 pa = p - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * h);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / _Resolution.y;
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    float px = 1.0 / _Resolution.y;

    float3 col = float3(0.003, 0.003, 0.0025);
    float grid = min(abs(frac(uv.x * 24.0) - 0.5), abs(frac(uv.y * 14.0) - 0.5));
    col += smoothstep(0.035, 0.0, grid) * 0.028;

    [loop]
    for (uint i = 0u; i < 96u; ++i)
    {
        AgentRecord a = Agents[i];
        if ((a.flags & 1u) == 0u || a.confidence < 0.02) continue;
        float2 q = (a.position - 0.5) * float2(aspect, 1.0);
        float2 local = p - q;
        float confidence = saturate(a.confidence);
        float3 ink = a.kind == 0u ? blob_ink : (a.kind == 1u ? corner_ink : line_ink);

        if (a.kind == 0u)
        {
            float radius = (7.0 + 42.0 * a.scale) * px;
            float ring = smoothstep(px * 1.45, px * 0.25, abs(length(local) - radius));
            float cross = max(
                smoothstep(px * 1.2, px * 0.2, abs(local.x)) * step(abs(local.y), radius * 0.65),
                smoothstep(px * 1.2, px * 0.2, abs(local.y)) * step(abs(local.x), radius * 0.65)
            );
            col += ink * confidence * max(ring, cross * 0.45);
        }
        else if (a.kind == 1u)
        {
            float r = (3.0 + 5.0 * a.scale) * px;
            float diamond = smoothstep(px * 1.4, px * 0.2, abs(local.x) + abs(local.y) - r);
            float tick = smoothstep(px * 1.2, px * 0.2, min(abs(local.x), abs(local.y)))
                * step(max(abs(local.x), abs(local.y)), r * 1.8);
            col += ink * confidence * max(diamond, tick * 0.55);
        }
        else
        {
            float2 p0 = (a.aux.xy - 0.5) * float2(aspect, 1.0);
            float2 p1 = (a.aux.zw - 0.5) * float2(aspect, 1.0);
            float segment = smoothstep(px * 1.6, px * 0.25, sdSegment(p, p0, p1));
            float endpoint = smoothstep(px * 2.0, px * 0.2, min(length(p - p0), length(p - p1)));
            col += ink * confidence * max(segment, endpoint);
        }

        float2 velocityEnd = q + a.velocity * float2(aspect, 1.0) * velocity_gain * 0.04;
        float motion = smoothstep(px * 1.1, px * 0.2, sdSegment(p, q, velocityEnd));
        col += velocity_ink * motion * confidence;
    }

    float border = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    col += smoothstep(px * 1.5, px * 0.25, border) * 0.24;
    OutputUAV[tid.xy] = float4(saturate(col * preview_exposure), 1.0);
}
