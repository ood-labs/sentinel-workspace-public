RWTexture2D<float4> OutputUAV : register(u0);

float pr_hash(float2 p) {
    p = frac(p * float2(0.131, 0.271));
    p += dot(p, p.yx + 15.21);
    return frac(p.x * p.y * 25.17);
}

float pr_rect(float2 p, float2 center, float2 halfSize) {
    float2 q = abs(p - center) - halfSize;
    return smoothstep(0.012, -0.012, max(q.x, q.y));
}

float pr_edge(float x, float width) {
    return smoothstep(width, 0.0, abs(frac(x) - 0.5));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float t = prism_phase * 6.2831853 * relay_rate;
    float drift = sin(t) * 0.055;
    float tilt = prism_tilt * (uv.y - 0.5);
    float3 base = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;

    float2 c1 = float2(0.22 + drift + tilt, 0.50);
    float2 c2 = float2(0.50 - drift * 0.6 + tilt, 0.50);
    float2 c3 = float2(0.78 + drift * 0.7 + tilt, 0.50);
    float h = 0.5;
    float m1 = pr_rect(uv, c1, float2(slice_width * 0.5, h));
    float m2 = pr_rect(uv, c2, float2(slice_width * 0.5, h));
    float m3 = pr_rect(uv, c3, float2(slice_width * 0.5, h));

    float2 uv1 = saturate(uv + float2(-separation * 0.75 + sin(t + uv.y * 3.0) * 0.012, 0.0));
    float2 uv2 = saturate(uv + float2(sin(t * 0.8 + uv.y * 4.0) * 0.012, cos(t) * 0.01));
    float2 uv3 = saturate(uv + float2(separation * 0.90 + cos(t + uv.y * 2.0) * 0.014, 0.0));
    float3 s1 = _Tex0.SampleLevel(LinearSampler, uv1, 0).rgb;
    float3 s2 = _Tex0.SampleLevel(LinearSampler, uv2, 0).rgb;
    float3 s3 = _Tex0.SampleLevel(LinearSampler, uv3, 0).rgb;

    float3 col = base;
    col = lerp(col, s1 * 0.92 + prism_color * 0.035, m1 * prism_mix);
    col = lerp(col, s2 * 0.98 + prism_color * 0.025, m2 * prism_mix);
    col = lerp(col, s3 * 0.90 + prism_color * 0.045, m3 * prism_mix);

    float seam1 = smoothstep(0.012, 0.0, abs(uv.x - (c1.x + slice_width * 0.5)));
    float seam2 = smoothstep(0.012, 0.0, abs(uv.x - (c2.x + slice_width * 0.5)));
    float seam3 = smoothstep(0.012, 0.0, abs(uv.x - (c3.x + slice_width * 0.5)));
    float seams = seam1 + seam2 + seam3;
    float ticks = max(pr_edge(uv.y * 19.0 + prism_phase * relay_rate, 0.018),
                      pr_edge(uv.y * 7.0 - prism_phase * relay_rate * 0.5, 0.014));
    col = lerp(col, seam_color, saturate(seams * seam_gain * prism_mix));
    col = lerp(col, prism_color, ticks * prism_mix * 0.18);

    float corner = smoothstep(0.010, 0.0, abs(uv.x - 0.5)) * smoothstep(0.06, 0.0, abs(uv.y - 0.5));
    col = lerp(col, seam_color, corner * seam_gain * 0.30);
    col += (pr_hash((float2)tid.xy + prism_phase * 29.0) - 0.5) * 0.006 * prism_mix;
    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
