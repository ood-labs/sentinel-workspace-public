RWTexture2D<float4> OutputUAV : register(u0);

float ex_hash(float2 p) {
    p = frac(p * float2(0.173, 0.319));
    p += dot(p, p.yx + 19.17);
    return frac(p.x * p.y * 27.31);
}

float ex_band(float x, float center, float width) {
    return smoothstep(width, width * 0.25, abs(x - center));
}

float ex_line(float x, float width) {
    return smoothstep(width, 0.0, abs(frac(x) - 0.5));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float t = excavation_phase * 6.2831853 * excavation_rate;
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = uv - 0.5;
    p.x *= aspect;

    float sweep = sin(t) * 0.20 + cos(t * 0.53) * 0.09;
    float axis = p.x + excavation_tilt * p.y - sweep;
    float voidMask = ex_band(axis, 0.0, void_width * aspect);
    float rim = smoothstep(void_width * aspect * 0.92, void_width * aspect * 0.48, abs(axis));

    float3 base = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 excavated = lerp(base, void_color, voidMask * excavation_mix);

    float count = max(1.0, floor(slab_count + 0.5));
    float3 slabs = 0.0;
    float slabAlpha = 0.0;
    [unroll]
    for (int i = 0; i < 7; ++i) {
        float fi = (float)i;
        float active = step(fi + 0.5, count);
        float yCenter = 0.16 + fi * 0.12 + sin(t * (0.7 + fi * 0.09) + fi * 1.7) * 0.035;
        float local = ex_band(p.y, yCenter - 0.30, 0.055 + fi * 0.006);
        float xOffset = (fi - 3.0) * slab_depth * 0.24 + sin(t + fi * 0.8) * slab_depth * 0.14;
        float2 suv = saturate(uv + float2(xOffset + slab_depth * 0.18, fi * 0.003));
        float3 sample = _Tex0.SampleLevel(LinearSampler, suv, 0).rgb;
        float gate = local * voidMask * active * excavation_mix;
        slabs += sample * gate;
        slabAlpha += gate;
    }
    excavated = lerp(excavated, slabs / max(slabAlpha, 0.001), saturate(slabAlpha));

    float ticks = ex_line((axis + excavation_phase * 0.32) * 8.0, 0.020);
    float hatch = ex_line((p.y + t * 0.018) * 21.0 + axis * 4.0, 0.014);
    float ink = saturate((rim * 0.62 + ticks * 0.28 + hatch * 0.12) * edge_gain * excavation_mix);
    excavated = lerp(excavated, edge_color, ink);
    excavated += (ex_hash((float2)tid.xy + excavation_phase * 41.0) - 0.5) * 0.008 * excavation_mix;
    OutputUAV[tid.xy] = float4(saturate(excavated), 1.0);
}
