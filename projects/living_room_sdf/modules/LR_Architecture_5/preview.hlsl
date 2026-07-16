struct PNode {
    float3 position;
    float scale;
    float kind_id;
    float seed;
    float yaw;
    float height;
    float width;
    float depth;
    float2 dir;
};

StructuredBuffer<PNode> PreviewNodes : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

float2 rotate2(float2 p, float a) {
    float s = sin(a), c = cos(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float box2(float2 p, float2 b) {
    float2 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}

float segment2(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 0.00001));
    return length(pa - ba * h);
}

float3 kindColor(float k) {
    if (k < 0.5) return float3(0.18, 0.28, 0.34);   // floor
    if (k < 3.5) return float3(0.44, 0.72, 0.88);   // shell
    if (k < 4.5) return float3(0.30, 0.82, 1.00);   // window
    if (k < 5.5) return float3(0.95, 0.55, 0.20);   // door
    if (k < 14.0) return float3(0.90, 0.28, 0.18);  // rug
    if (k < 18.0) return float3(0.95, 0.38, 0.58);  // art
    return float3(1.00, 0.80, 0.24);                // pendants
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID) {
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)px + 0.5) / _Resolution.xy;
    float2 world = float2((uv.x - 0.5) * 12.0, (0.5 - uv.y) * 8.0);
    float3 col = lerp(float3(0.018, 0.024, 0.030), float3(0.030, 0.042, 0.052), uv.y);

    float2 gridUv = abs(frac(world) - 0.5);
    float gridLine = 1.0 - smoothstep(0.475, 0.495, min(gridUv.x, gridUv.y));
    col += gridLine * float3(0.040, 0.065, 0.080);
    col += (1.0 - smoothstep(0.015, 0.025, abs(world.x))) * float3(0.06, 0.16, 0.20);
    col += (1.0 - smoothstep(0.015, 0.025, abs(world.y))) * float3(0.06, 0.16, 0.20);

    [loop] for (uint i = 0; i < 12; ++i) {
        PNode n = PreviewNodes[i];
        float2 center = n.position.xz;
        float2 local = rotate2(world - center, -n.yaw);
        float2 footprint = max(float2(n.width, n.depth) * 0.5, 0.035);
        float d = box2(local, footprint);
        float edge = 1.0 - smoothstep(0.025, 0.055, abs(d));
        float fill = smoothstep(0.08, -0.02, d);
        float3 tint = kindColor(n.kind_id);
        float shellOnly = n.kind_id < 3.5 ? 1.0 : 0.0;
        col = lerp(col, tint * 0.34, fill * (shellOnly * 0.10 + (1.0 - shellOnly) * 0.36));
        col += edge * tint * 0.82;

        float centerDot = 1.0 - smoothstep(0.055, 0.085, length(world - center));
        float2 arrowEnd = center + normalize(n.dir + float2(0.0001, 0.0001)) * 0.36;
        float arrow = 1.0 - smoothstep(0.025, 0.055, segment2(world, center, arrowEnd));
        col += centerDot * float3(1.0, 1.0, 1.0) + arrow * tint;
    }

    float border = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    col += (1.0 - smoothstep(0.004, 0.012, border)) * float3(0.20, 0.72, 0.92);
    OutputUAV[px] = float4(saturate(col), 1.0);
}
