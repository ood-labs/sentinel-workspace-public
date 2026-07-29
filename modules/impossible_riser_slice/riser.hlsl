RWTexture2D<float4> OutputUAV : register(u0);

float rs_hash(float2 p) {
    p = frac(p * float2(0.117, 0.327));
    p += dot(p, p.yx + 14.77);
    return frac(p.x * p.y * 29.11);
}

float rs_line(float x, float width) {
    return smoothstep(width, 0.0, abs(frac(x) - 0.5));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = uv - riser_center;
    p.x *= aspect;
    float2 local = float2(p.x / max(riser_width, 0.001), p.y / max(riser_height, 0.001));
    float shape = smoothstep(1.10, 0.84, max(abs(local.x), abs(local.y)));
    float trapezoid = smoothstep(1.0, 0.70, abs(local.x + local.y * 0.18));
    float mask = shape * trapezoid;

    float2 sourceUv = float2(0.5 + local.x * 0.48, 0.5 + local.y * 0.48);
    float3 base = _Tex0.SampleLevel(LinearSampler, saturate(uv), 0).rgb;
    float3 src = _Tex0.SampleLevel(LinearSampler, saturate(sourceUv), 0).rgb;
    float height = dot(src, float3(0.299, 0.587, 0.114));
    float phase = riser_phase * 6.2831853 * drift_rate;
    float2 drift = float2(cos(phase) * 0.026, sin(phase * 0.71) * 0.018);

    float3 relief = plate_color * 0.35;
    float layerCount = max(layer_count, 3.0);
    for (int i = 0; i < 18; ++i) {
        float fi = (float)i;
        if (fi >= layerCount) break;
        float z = fi / max(layerCount - 1.0, 1.0);
        float layerH = height * (0.36 + z * 0.64);
        float2 sampleUv = sourceUv + drift * z + float2(layerH * relief_depth * 0.11, -layerH * relief_depth * 0.055);
        float3 layer = _Tex0.SampleLevel(LinearSampler, saturate(sampleUv), 0).rgb;
        float shadow = 0.36 + 0.64 * z;
        relief = lerp(relief, layer * shadow + plate_color * 0.14, 0.22 + z * 0.035);
    }

    float contour = rs_line(height * 10.0 - riser_phase * drift_rate * 2.0, 0.018);
    float cross = max(rs_line(local.x * 8.0 + phase, 0.022), rs_line(local.y * 6.0 - phase * 0.7, 0.018));
    float bevel = smoothstep(0.10, 0.0, abs(max(abs(local.x), abs(local.y)) - 0.86));
    relief = lerp(relief, bevel_color, (contour * 0.62 + bevel * 0.58) * relief_gain);
    relief = lerp(relief, plate_color, cross * relief_gain * 0.30);

    float scan = rs_line(local.y * 13.0 - riser_phase * drift_rate * 1.7, 0.018) * shape;
    relief = lerp(relief, bevel_color, scan * relief_gain * 0.24);

    float3 col = lerp(base, relief, mask * riser_mix);
    float shadow = smoothstep(1.15, 0.62, max(abs(local.x + 0.035), abs(local.y + 0.045))) * mask;
    col *= 1.0 - shadow * 0.18 * riser_mix;
    col += (rs_hash((float2)tid.xy + riser_phase * 23.0) - 0.5) * 0.007 * mask;
    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
