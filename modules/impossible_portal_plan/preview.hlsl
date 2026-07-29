struct PortalRecord {
    float2 center;
    float radius;
    float thickness;
    float rotation;
    float sector_count;
    float depth;
    float material;
    float phase;
    float speed;
    float2 eccentricity;
    float opacity;
    float scale;
    float active;
    float reserved;
};

StructuredBuffer<PortalRecord> Portals : register(t1);
RWTexture2D<float4> OutputUAV : register(u0);

float2 pp_rotate(float2 p, float a) {
    float s = sin(a);
    float c = cos(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / _Resolution.y;
    float3 col = float3(0.004, 0.004, 0.007);

    [loop]
    for (uint i = 0u; i < 16u; ++i) {
        PortalRecord r = Portals[i];
        if (r.active < 0.5) continue;
        float2 q = (uv - r.center) * float2(aspect, 1.0);
        q = pp_rotate(q, -r.rotation);
        q /= max(r.eccentricity, float2(0.2, 0.2));
        float d = length(q);
        float disk = 1.0 - smoothstep(r.radius, r.radius + 0.008, d);
        float ring = 1.0 - smoothstep(r.thickness, r.thickness * 2.6, abs(d - r.radius));
        float angle = atan2(q.y, q.x);
        float sector = step(0.44, frac(angle / 6.2831853 * max(3.0, r.sector_count) + r.phase));
        float2 sampleUv = pp_rotate(q / max(r.radius * 2.0, 0.02), r.phase * 0.4) + 0.5;
        float3 material = _Tex0.SampleLevel(LinearSampler, saturate(sampleUv), 0).rgb;
        float3 tint = r.material < 0.5 ? float3(0.95, 0.12, 0.025) :
                      r.material < 1.5 ? float3(0.78, 0.69, 0.55) :
                                         float3(0.92, 0.90, 0.84);
        float depthFade = saturate(0.58 + r.depth * 0.24);
        col = lerp(col, material * depthFade + tint * 0.12, disk * r.opacity * 0.84);
        col += tint * ring * (0.42 + sector * 0.42);
    }

    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
