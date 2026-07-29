struct PanelRecord {
    float2 center; float2 size;
    float angle; float depth; float kind; float palette;
    float group_id; float order_id; float fold; float pattern;
    float skew; float phase; float weight; float active;
};
struct RouteRecord {
    float2 p0; float2 p1;
    float width; float palette; float group_id; float phase;
    float dash; float elevation; float active; float reserved;
};

StructuredBuffer<PanelRecord> Panels : register(t0);
StructuredBuffer<RouteRecord> Routes : register(t1);
RWTexture2D<float4> OutputUAV : register(u0);

float3 paletteColor(int idx) {
    if (idx == 0) return float3(0.94, 0.92, 0.85);
    if (idx == 1) return float3(0.07, 0.07, 0.09);
    if (idx == 2) return float3(0.04, 0.10, 0.24);
    if (idx == 3) return float3(0.91, 0.08, 0.055);
    if (idx == 4) return float3(0.95, 0.36, 0.06);
    if (idx == 5) return float3(0.91, 0.16, 0.48);
    if (idx == 6) return float3(0.10, 0.78, 0.28);
    return float3(0.50, 0.53, 0.56);
}

float sdBox2(float2 p, float2 b) {
    float2 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}

float sdSegment2(float2 p, float2 a, float2 b) {
    float2 pa = p - a;
    float2 ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * h);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / _Resolution.y;
    float2 p = float2((uv.x - 0.5) * aspect, uv.y - 0.5);

    float3 col = float3(0.055, 0.055, 0.065);
    float grid = min(abs(frac(uv.x * 24.0) - 0.5), abs(frac(uv.y * 14.0) - 0.5));
    col += smoothstep(0.035, 0.0, grid) * 0.025;

    [loop]
    for (uint i = 0u; i < 96u; ++i) {
        PanelRecord r = Panels[i];
        if (r.active < 0.5) continue;
        float2 c = float2((r.center.x - 0.5) * aspect, r.center.y - 0.5);
        float2 q = p - c;
        float cs = cos(r.angle), sn = sin(r.angle);
        q = float2(cs * q.x + sn * q.y, -sn * q.x + cs * q.y);
        q.x += q.y * r.skew;
        float2 halfSize = r.size * float2(aspect, 1.0) * 0.5;
        float d = sdBox2(q, halfSize);
        float edge = 1.0 / max(_Resolution.y, 1.0);
        float fill = smoothstep(edge, -edge, d);
        float border = smoothstep(edge * 2.5, 0.0, abs(d));
        float3 ink = paletteColor((int)r.palette);
        float stripe = step(0.5, frac((q.x + q.y) * _Resolution.y * 0.07));
        float patternMix = (r.pattern > 1.5 && r.pattern < 2.5) ? 0.22 * stripe : 0.0;
        ink = lerp(ink, 1.0 - ink, patternMix);
        col = lerp(col, ink * (0.78 + 0.22 * saturate(r.depth)), fill * 0.86);
        col = lerp(col, float3(0.015, 0.015, 0.02), border * 0.75);
    }

    [loop]
    for (uint j = 0u; j < 48u; ++j) {
        RouteRecord r = Routes[j];
        if (r.active < 0.5) continue;
        float2 a = float2((r.p0.x - 0.5) * aspect, r.p0.y - 0.5);
        float2 b = float2((r.p1.x - 0.5) * aspect, r.p1.y - 0.5);
        float d = sdSegment2(p, a, b);
        float mask = smoothstep(r.width + 0.0015, r.width, d);
        float3 rc = r.palette < 0.5 ? float3(0.96, 0.08, 0.05) :
                    r.palette < 1.5 ? float3(0.97, 0.42, 0.03) :
                    r.palette < 2.5 ? float3(0.08, 0.80, 0.30) :
                                      float3(0.84, 0.86, 0.88);
        col = lerp(col, rc, mask);
    }

    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}

