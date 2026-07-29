struct RibbonRecord {
    float2 p0;
    float2 p1;
    float width;
    float feather;
    float material;
    float layer;
    float phase;
    float speed;
    float warp;
    float opacity;
    float2 uv_offset;
    float active;
    float reserved;
};

StructuredBuffer<RibbonRecord> Ribbons : register(t1);
RWTexture2D<float4> OutputUAV : register(u0);

float rp_segment(float2 p, float2 a, float2 b, out float t) {
    float2 pa = p - a;
    float2 ba = b - a;
    t = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * t);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / _Resolution.y;
    float2 p = float2(uv.x * aspect, uv.y);
    float3 base = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 col = base * 0.08 + float3(0.006, 0.006, 0.009);

    [loop]
    for (uint i = 0u; i < 24u; ++i) {
        RibbonRecord r = Ribbons[i];
        if (r.active < 0.5) continue;
        float2 a = float2(r.p0.x * aspect, r.p0.y);
        float2 b = float2(r.p1.x * aspect, r.p1.y);
        float along;
        float d = rp_segment(p, a, b, along);
        float wave = sin(along * 18.0 + r.phase * 6.2831853) * r.warp * 0.012;
        float mask = 1.0 - smoothstep(r.width * 0.5 + r.feather, r.width * 0.5 + r.feather * 2.0, abs(d + wave));
        float edge = 1.0 - smoothstep(r.feather, r.feather * 3.0, abs(abs(d + wave) - r.width * 0.5));
        float2 sampleUv = frac(float2(along, uv.y) + r.uv_offset);
        float3 material = _Tex0.SampleLevel(LinearSampler, sampleUv, 0).rgb;
        float3 layerTint = lerp(float3(0.94, 0.88, 0.76), float3(1.0, 0.09, 0.015), frac(r.material * 0.37));
        col = lerp(col, material * 0.72 + layerTint * 0.28, mask * r.opacity * 0.88);
        col += layerTint * edge * 0.30;
    }

    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
