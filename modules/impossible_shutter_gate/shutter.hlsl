RWTexture2D<float4> OutputUAV : register(u0);

float sg_hash(float2 p) {
    p = frac(p * float2(0.137, 0.287));
    p += dot(p, p.yx + 13.17);
    return frac(p.x * p.y * 23.11);
}

float sg_line(float x, float width) {
    return smoothstep(width, 0.0, abs(frac(x) - 0.5));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float2 p = uv - 0.5;
    float t = gate_phase * 6.2831853 * gate_rate;
    float2 axis = normalize(float2(1.0, gate_angle * 1.8));
    float2 normal = float2(-axis.y, axis.x);
    float along = dot(p, axis) + gate_offset + sin(t * 0.7) * 0.07;
    float across = dot(p, normal);
    float moving = sin(t + along * 7.0) * 0.035;

    float bladeA = smoothstep(gate_width + 0.012, gate_width - 0.012, abs(across - moving));
    float bladeB = smoothstep(gate_width + 0.012, gate_width - 0.012, abs(across + moving + 0.19));
    float gate = saturate(bladeA + bladeB) * gate_mix;
    float slitA = smoothstep(0.018, 0.0, abs(across - moving));
    float slitB = smoothstep(0.018, 0.0, abs(across + moving + 0.19));
    float slit = saturate(slitA + slitB);

    float2 sheared = uv + normal * (slat_depth * 0.10) + axis * (sin(t + across * 4.0) * 0.018);
    float3 base = _Tex0.SampleLevel(LinearSampler, saturate(uv), 0).rgb;
    float3 shifted = _Tex0.SampleLevel(LinearSampler, saturate(sheared), 0).rgb;
    float3 slat = shifted * (0.58 + 0.22 * cos(t + along * 8.0));
    float3 col = lerp(base, slat, gate);
    col = lerp(col, slit_color, slit * gate_mix * 0.58);

    float seam = max(sg_line(along * 13.0 + gate_phase * gate_rate, 0.021),
                     sg_line(along * 5.0 - gate_phase * gate_rate * 0.6, 0.014));
    seam *= saturate(gate + slit * 0.4);
    col = lerp(col, seam_color, seam * seam_gain);

    float ticks = sg_line(along * 28.0 - gate_phase * gate_rate * 1.8, 0.012) *
                  smoothstep(0.86, 0.15, abs(across));
    col = lerp(col, seam_color, ticks * gate_mix * 0.32);

    float edge = smoothstep(0.014, 0.0, abs(abs(across) - 0.47));
    col = lerp(col, slit_color, edge * gate_mix * 0.35);
    col += (sg_hash((float2)tid.xy + gate_phase * 17.0) - 0.5) * 0.006 * gate_mix;
    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
