RWTexture2D<float4> OutputUAV : register(u0);

float bw_hash(float2 p) {
    p = frac(p * float2(0.127, 0.311));
    p += dot(p, p.yx + 21.71);
    return frac(p.x * p.y * 27.17);
}

float bw_line(float x, float width) {
    return smoothstep(width, 0.0, abs(frac(x) - 0.5));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = uv - well_center;
    p.x *= aspect;
    float r = length(p) / max(well_radius, 0.001);
    float well = smoothstep(1.08, 0.72, r) * smoothstep(0.64, 0.78, uv.x);
    float theta = atan2(p.y, p.x);
    float t = well_phase * 6.2831853 * pull_rate;

    float spiral = theta / 6.2831853 + 0.5 + t * 0.10 + r * 0.21;
    float radial = r - sin(theta * 5.0 + t) * 0.035;
    float2 polarUv = float2(frac(spiral + r * 0.17), saturate(0.46 + radial * 0.52));
    float3 base = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 pulled = _Tex0.SampleLevel(LinearSampler, polarUv, 0).rgb;
    float3 col = lerp(base, pulled * 0.48 + void_color * 0.28, well * well_mix);

    float rings = bw_line(r * trace_density - well_phase * pull_rate * 2.0, 0.021);
    float spokes = bw_line(theta / 6.2831853 * 17.0 + well_phase * pull_rate * 0.6 + r * 2.0, 0.017);
    float spiralLine = bw_line(spiral * 13.0 - well_phase * pull_rate, 0.018);
    float telemetry = max(rings, max(spokes * 0.72, spiralLine * 0.52));

    float trace = 0.0;
    for (int i = 0; i < 10; ++i) {
        float fi = (float)i;
        float a = frac(fi * 0.173 + well_phase * pull_rate * (0.35 + fi * 0.04));
        float rr = 0.18 + frac(fi * 0.271) * 0.78;
        float2 q = float2(cos(a * 6.2831853), sin(a * 6.2831853)) * rr;
        trace += smoothstep(0.028, 0.0, abs(length(p / max(well_radius, 0.001)) - rr)) *
                 smoothstep(0.045, 0.0, length((p / max(well_radius,0.001)) - q));
    }
    trace = saturate(trace) * well;
    col = lerp(col, tracer_color, (telemetry * 0.34 + trace * 0.92) * ring_gain * well_mix);

    float rim = smoothstep(0.036, 0.0, abs(r - 0.93)) * smoothstep(0.64, 0.78, uv.x);
    col = lerp(col, tracer_color, rim * ring_gain * 0.78);
    float seam = smoothstep(0.010, 0.0, abs(uv.x - 0.72 - sin(uv.y * 5.0 + t) * 0.018));
    col = lerp(col, void_color, seam * well_mix * 0.72);

    float grain = bw_hash((float2)tid.xy + well_phase * 37.0) - 0.5;
    col += grain * 0.006 * well;
    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
