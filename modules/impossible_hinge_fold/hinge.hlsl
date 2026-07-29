RWTexture2D<float4> OutputUAV : register(u0);

float hf_line(float x, float width) {
    return smoothstep(width, 0.0, abs(x));
}

float hf_hash(float2 p) {
    p = frac(p * float2(0.193, 0.271));
    p += dot(p, p.yx + 12.17);
    return frac(p.x * p.y * 31.71);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float2 p = uv - 0.5;
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    p.x *= aspect;
    float t = hinge_phase * 6.2831853 * hinge_rate;
    float sweep = sin(t * 0.72) * 0.16 + hinge_offset;
    float axis = p.x + fold_angle * p.y - sweep;
    float left = smoothstep(0.012, -0.012, axis);
    float hinge = hf_line(axis, crease_width);

    float3 base = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float2 folded = uv;
    float2 pivot = float2(0.5 + sweep / max(aspect, 0.001), 0.5);
    folded.x = pivot.x - (uv.x - pivot.x) * (1.0 - fold_amount);
    folded.y = saturate(uv.y + sin(t + uv.x * 4.0) * fold_amount * 0.06);
    folded = saturate(folded + float2(cos(t * 0.8) * fold_amount * 0.025, 0.0));
    float3 reflected = _Tex0.SampleLevel(LinearSampler, folded, 0).rgb;

    float2 secondary = saturate(float2(1.0 - folded.x, folded.y + sin(t * 0.6) * 0.018));
    float3 echo = _Tex0.SampleLevel(LinearSampler, secondary, 0).rgb;
    float3 foldedCol = lerp(reflected, echo, 0.24 + 0.20 * sin(t * 0.9));

    float3 col = lerp(base, foldedCol, left * hinge_mix);
    float shadow = saturate((1.0 - left) * fold_amount * 0.18);
    col = lerp(col, shadow_color, shadow * hinge_mix);

    float seam = hinge * seam_gain * hinge_mix;
    float ticks = hf_line(frac((p.y + t * 0.03) * 17.0) - 0.5, 0.012) * hinge;
    col = lerp(col, seam_color, saturate(seam * 0.92 + ticks * 0.20));
    col += (hf_hash((float2)tid.xy + hinge_phase * 73.0) - 0.5) * 0.007 * hinge_mix;
    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
