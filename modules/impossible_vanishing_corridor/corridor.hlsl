RWTexture2D<float4> OutputUAV : register(u0);

float vc_hash(float2 p) {
    p = frac(p * float2(0.137, 0.291));
    p += dot(p, p.yx + 18.73);
    return frac(p.x * p.y * 27.19);
}

float vc_line(float x, float width) {
    return smoothstep(width, 0.0, abs(frac(x) - 0.5));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float2 aspect = float2(_Resolution.x / _Resolution.y, 1.0);
    float t = corridor_phase * 6.2831853 * travel_speed;
    float2 vanish = float2(0.50 + sin(t * 0.37) * vanishing_pull, 0.50 + cos(t * 0.29) * vanishing_pull * 0.55);
    float2 q = (uv - vanish) * aspect;
    float radius = max(length(q), 0.0001);

    float3 base = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 layered = 0.0;
    float layerWeight = 0.0;
    [unroll]
    for (int i = 0; i < 8; ++i) {
        float fi = (float)i;
        float z = frac(fi / slice_count + corridor_phase * travel_speed * 0.33);
        float scale = lerp(0.10, 1.0, z * z);
        float2 layerUv = saturate(vanish + (uv - vanish) * scale + float2(sin(t + fi * 1.7), cos(t * 0.7 - fi * 1.1)) * 0.008 * corridor_depth);
        float3 sample = _Tex0.SampleLevel(LinearSampler, layerUv, 0).rgb;
        float w = (1.0 - z) * (0.34 + 0.66 * corridor_depth);
        layered += sample * w;
        layerWeight += w;
    }
    layered /= max(layerWeight, 0.001);
    float lum = dot(layered, float3(0.299, 0.587, 0.114));
    layered *= 0.68 + lum * 0.72;

    float squareRadius = max(abs(q.x), abs(q.y));
    float frames = vc_line(squareRadius * slice_count - t * 0.22, 0.026);
    float frames2 = vc_line(squareRadius * slice_count * 0.47 + t * 0.14, 0.018);
    float rayAngle = atan2(q.y, q.x) / 6.2831853;
    float rays = vc_line(rayAngle * 14.0 + t * 0.025, 0.022);
    float crossRay = vc_line((rayAngle + 0.125) * 7.0 - t * 0.018, 0.016);
    float edge = saturate(frames * 0.72 + frames2 * 0.36 + rays * 0.42 + crossRay * 0.26) * frame_gain;
    float throat = 1.0 - smoothstep(0.04, 0.18, radius);

    float3 col = lerp(base, layered, corridor_mix);
    col = lerp(col, dark_color, throat * corridor_mix * 0.58);
    col += accent_color * edge * (0.32 + 0.34 * lum);
    col += (vc_hash((float2)tid.xy + corridor_phase * 43.0) - 0.5) * 0.012 * corridor_mix;
    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
