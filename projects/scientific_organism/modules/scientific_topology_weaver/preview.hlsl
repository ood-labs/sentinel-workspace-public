struct EdgeRecord
{
    float2 a;
    float2 b;
    float weight;
    float phase;
    float distance;
    float tension;
    uint source_a;
    uint source_b;
    uint kind;
    uint flags;
};

StructuredBuffer<EdgeRecord> Edges : register(t0);
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
    float3 col = float3(0.0025, 0.0025, 0.002);

    float grid = min(abs(frac(uv.x * 24.0) - 0.5), abs(frac(uv.y * 14.0) - 0.5));
    col += smoothstep(0.03, 0.0, grid) * 0.022;

    [loop]
    for (uint i = 0u; i < 96u; ++i)
    {
        EdgeRecord e = Edges[i];
        if ((e.flags & 1u) == 0u) continue;
        float2 a = (e.a - 0.5) * float2(aspect, 1.0);
        float2 b = (e.b - 0.5) * float2(aspect, 1.0);
        float d = sdSegment(p, a, b);
        float width = px * lerp(0.7, 2.5, saturate(e.weight));
        float wire = smoothstep(width * 1.8, width * 0.25, d);
        float dash = step(0.36, frac((length(p - a) / max(length(b - a), 1e-4)) * dash_count + e.phase));
        float kindDash = e.kind == 0u ? 1.0 : lerp(1.0, dash, dash_mix);
        float3 ink = e.kind == 1u ? mass_ink : (e.kind == 2u ? line_ink : edge_ink);
        col += ink * wire * e.weight * kindDash;

        float endpoint = smoothstep(px * 2.0, px * 0.25, min(length(p - a), length(p - b)));
        col += endpoint * ink * e.weight * 0.7;
    }

    [loop]
    for (uint i = 0u; i < 96u; ++i)
    {
        if ((_Data0[i].flags & 1u) == 0u || _Data0[i].confidence < 0.03) continue;
        float2 q = (_Data0[i].position - 0.5) * float2(aspect, 1.0);
        float node = smoothstep(px * 2.0, px * 0.2, abs(length(p - q) - px * (2.0 + _Data0[i].scale * 8.0)));
        float3 ink = _Data0[i].kind == 0u ? mass_ink : node_ink;
        col += ink * node * _Data0[i].confidence;
    }

    float border = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    col += smoothstep(px * 1.4, px * 0.2, border) * 0.25;
    OutputUAV[tid.xy] = float4(saturate(col * preview_exposure), 1.0);
}
