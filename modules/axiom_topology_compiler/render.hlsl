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
StructuredBuffer<CompilerStats> Stats : register(t2);
RWTexture2D<float4> OutputUAV : register(u0);

float sdSegment(float2 p, float2 a, float2 b)
{
    float2 pa = p - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * h);
}

float crossMark(float2 p, float radius, float width)
{
    float horizontal = smoothstep(width, width * 0.15, abs(p.y)) * step(abs(p.x), radius);
    float vertical = smoothstep(width, width * 0.15, abs(p.x)) * step(abs(p.y), radius);
    return max(horizontal, vertical);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    float px = 1.0 / _Resolution.y;
    float3 col = float3(0.0018, 0.0018, 0.0016);

    float minorX = abs(frac(uv.x * 24.0) - 0.5);
    float minorY = abs(frac(uv.y * 14.0) - 0.5);
    float majorX = abs(frac(uv.x * 6.0) - 0.5);
    float majorY = abs(frac(uv.y * 3.5) - 0.5);
    float minorGrid = 1.0 - smoothstep(0.491, 0.499, min(minorX, minorY));
    float majorGrid = 1.0 - smoothstep(0.482, 0.499, min(majorX, majorY));
    col += minorGrid * 0.013 + majorGrid * 0.032;

    [loop]
    for (uint i = 0u; i < 64u; ++i)
    {
        ChoirRoute route = Routes[i];
        if (route.active < 0.5) continue;
        float2 a = (route.a - 0.5) * float2(aspect, 1.0);
        float2 b = (route.b - 0.5) * float2(aspect, 1.0);
        float distanceToRoute = sdSegment(p, a, b);
        float ink = smoothstep(px * (2.2 + route.weight * 1.7), px * 0.35, distanceToRoute);
        float groupPulse = frac(route.group_id * 0.381966);
        float3 routeColor = lerp(paper_color * 0.42, accent_color * 0.82, step(0.72, groupPulse));
        col = max(col, routeColor * ink * lerp(0.28, 0.88, route.weight));
    }

    [loop]
    for (uint i = 0u; i < 64u; ++i)
    {
        ChoirNode node = Nodes[i];
        if (node.active < 0.5) continue;

        float2 center = (node.position - 0.5) * float2(aspect, 1.0);
        float2 local = p - center;
        float radius = (node_size / _Resolution.y) * lerp(0.75, 2.1, node.weight);
        float ring = smoothstep(px * 1.35, px * 0.22, abs(length(local) - radius));
        float cross = crossMark(local, radius * 0.72, px * 0.82);
        float core = smoothstep(px * 1.35, px * 0.18, length(local));

        float2 direction = normalize(node.direction * float2(aspect, 1.0));
        float2 arrowEnd = center + direction * (0.018 + 0.052 * node.weight);
        float arrow = smoothstep(px * 1.30, px * 0.25, sdSegment(p, center, arrowEnd));

        float groupPhase = frac(node.group_id * 0.381966);
        float accentGate = step(0.73, groupPhase) * step(1.0, node.kind);
        float3 nodeColor = lerp(paper_color * lerp(0.58, 1.0, node.weight), accent_color, accentGate);
        float nodeInk = max(ring, max(cross * 0.55, core));
        col = max(col, nodeColor * max(nodeInk, arrow * direction_gain * 0.72));
    }

    // The lower 64 cells directly visualize the published node buffer.
    if (uv.y > 0.936 && uv.y < 0.985)
    {
        uint slot = min((uint)floor(uv.x * 64.0), 63u);
        ChoirNode record = Nodes[slot];
        float cellX = frac(uv.x * 64.0);
        float cell = step(0.13, cellX) * step(cellX, 0.87);
        float heightGate = step(uv.y, 0.943 + 0.034 * saturate(record.weight));
        float activeBar = cell * heightGate * step(0.5, record.active);
        float groupAccent = step(0.73, frac(record.group_id * 0.381966));
        float3 barColor = lerp(paper_color * 0.60, accent_color, groupAccent);
        col = max(col, barColor * activeBar);
    }

    // Four compact bars are bound to the actual compiler_stats record.
    CompilerStats s = Stats[0];
    if (uv.x > 0.018 && uv.x < 0.158 && uv.y > 0.020 && uv.y < 0.076)
    {
        float localX = saturate((uv.x - 0.018) / 0.14);
        float localY = saturate((uv.y - 0.020) / 0.056);
        uint row = min((uint)floor(localY * 4.0), 3u);
        float rowY = frac(localY * 4.0);
        float value = row == 0u ? s.active_nodes / 64.0 :
                      row == 1u ? s.active_routes / 64.0 :
                      row == 2u ? s.mean_weight :
                                  s.group_coverage;
        float bar = step(0.16, rowY) * step(rowY, 0.78) * step(localX, saturate(value));
        col = max(col, lerp(paper_color * 0.48, accent_color, row == 3u ? 0.65 : 0.0) * bar);
    }

    float border = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    col += smoothstep(px * 1.6, px * 0.2, border) * 0.22;
    float tickBand = step(uv.y, 0.017) + step(0.983, uv.y);
    col += step(0.82, frac(uv.x * 32.0)) * tickBand * 0.24;

    col *= preview_exposure;
    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
