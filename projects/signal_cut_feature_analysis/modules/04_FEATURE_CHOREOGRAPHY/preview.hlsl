struct GlyphRecord
{
    float2 position;
    float2 direction;
    float weight;
    float kind;
    float group_id;
    float active;
};

StructuredBuffer<GlyphRecord> Glyphs : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

float sdSegment(float2 p, float2 a, float2 b)
{
    float2 pa = p - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * h);
}

float sdDiamond(float2 p, float r)
{
    p = abs(p);
    return (p.x + p.y - r) * 0.70710678;
}

float markerCross(float2 p, float r, float width)
{
    float h = smoothstep(width, width * 0.25, abs(p.y)) * step(abs(p.x), r);
    float v = smoothstep(width, width * 0.25, abs(p.x)) * step(abs(p.y), r);
    return max(h, v);
}

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    if (id.x >= (uint)_Resolution.x || id.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)id.xy + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / _Resolution.y;
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    float px = 1.0 / _Resolution.y;

    float3 col = float3(0.0015, 0.0015, 0.0015);

    float minorX = abs(frac(uv.x * 24.0) - 0.5);
    float minorY = abs(frac(uv.y * 14.0) - 0.5);
    float majorX = abs(frac(uv.x * 6.0) - 0.5);
    float majorY = abs(frac(uv.y * 3.5) - 0.5);
    float minorGrid = 1.0 - smoothstep(0.492, 0.498, min(minorX, minorY));
    float majorGrid = 1.0 - smoothstep(0.486, 0.498, min(majorX, majorY));
    col += minorGrid * 0.018;
    col += majorGrid * 0.035;

    float border = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    col += smoothstep(px * 1.5, px * 0.25, border) * 0.22;

    [loop]
    for (uint i = 0; i < 64u; ++i)
    {
        GlyphRecord g = Glyphs[i];
        if (g.active < 0.5) continue;

        float2 gp = (g.position - 0.5) * float2(aspect, 1.0);
        float2 gd = normalize(g.direction * float2(aspect, 1.0));
        float r = (marker_size / _Resolution.y) * lerp(0.78, 2.35, g.weight);
        float groupTone = 0.52 + 0.38 * frac(g.group_id * 0.381966);

        float2 local = p - gp;
        float orbit = smoothstep(px * 1.45, px * 0.30, abs(length(local) - r));
        float core = smoothstep(px * 1.40, px * 0.25, length(local));
        float cross = markerCross(local, r * 0.62, px * 0.85);
        float2 arrowEnd = gp + gd * (0.018 + 0.044 * g.weight);
        float arrow = smoothstep(px * 1.35, px * 0.35, sdSegment(p, gp, arrowEnd));

        float3 ink = blob_ink * groupTone;
        col += ink * (max(orbit, max(core, cross * 0.42)) + arrow * direction_gain);
    }

    // Discrete 64-slot telemetry strip: one fixed cell per record, never a gradient.
    if (uv.y > 0.935 && uv.y < 0.985)
    {
        uint slot = min((uint)floor(uv.x * 64.0), 63u);
        GlyphRecord t = Glyphs[slot];
        float cellX = frac(uv.x * 64.0);
        float cellEdge = step(0.12, cellX) * step(cellX, 0.88);
        float heightGate = step(uv.y, 0.943 + 0.034 * saturate(t.weight));
        float activeBar = cellEdge * heightGate * step(0.5, t.active);
        float3 barColor = blob_ink * 0.72;
        col = max(col, barColor * activeBar);
    }

    // Registration ticks.
    float tickBand = step(uv.y, 0.018) + step(0.982, uv.y);
    float ticks = step(0.82, frac(uv.x * 32.0)) * tickBand;
    col += ticks * 0.28;

    col *= preview_exposure;
    OutputUAV[id.xy] = float4(saturate(col), 1.0);
}
