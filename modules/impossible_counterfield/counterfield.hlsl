RWTexture2D<float4> OutputUAV : register(u0);

float cf_hash(float2 p) {
    p = frac(p * float2(0.1237, 0.3171));
    p += dot(p, p.yx + 11.73);
    return frac(p.x * p.y * 31.17);
}

float cf_line(float x, float width) {
    return smoothstep(width, 0.0, abs(frac(x) - 0.5));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float2 srcUv = uv;
    float t = counter_phase * 6.2831853 * gate_rate;
    srcUv += float2(sin(uv.y * 8.0 + t) * 0.015, cos(uv.x * 5.0 - t) * 0.012);
    float3 base = _Tex0.SampleLevel(LinearSampler, saturate(srcUv), 0).rgb;

    float edge = field_x + sin(uv.y * 6.0 + t * 0.6) * 0.021 + field_shear * (uv.y - 0.5) * 0.22;
    float left = smoothstep(edge - 0.012, edge + 0.012, uv.x);
    float right = smoothstep(edge + field_width - 0.012, edge + field_width + 0.012, uv.x);
    float field = saturate(left * (1.0 - right)) * counter_mix;

    float luma = dot(base, float3(0.299, 0.587, 0.114));
    float q = floor(saturate(luma) * quant_steps) / max(quant_steps - 1.0, 1.0);
    float2 fp = float2((uv.x - edge) / max(field_width, 0.001), uv.y);
    float hatch = cf_line(fp.x * 13.0 + fp.y * 3.0 - counter_phase * gate_rate * 2.0, 0.035);
    float cross = max(cf_line(fp.x * 8.0 + counter_phase * gate_rate, 0.018),
                      cf_line(fp.y * 15.0 - counter_phase * gate_rate * 0.8, 0.018));
    float gate = smoothstep(0.040, 0.0, abs(frac(fp.x + counter_phase * gate_rate) - 0.5));
    float registration = smoothstep(0.008, 0.0, abs(frac(fp.y * 5.0) - 0.5)) * smoothstep(0.0, 0.1, fp.x) * smoothstep(1.0, 0.84, fp.x);

    float3 binaryInk = lerp(counter_color, bone_color, q);
    binaryInk = lerp(binaryInk, bone_color, hatch * 0.18 + registration * 0.7);
    binaryInk = lerp(binaryInk, counter_color, cross * 0.27);
    binaryInk += bone_color * gate * 0.22;

    float3 col = lerp(base, binaryInk, field);
    float boundary = smoothstep(0.018, 0.0, abs(uv.x - edge)) + smoothstep(0.018, 0.0, abs(uv.x - edge - field_width));
    col = lerp(col, bone_color, saturate(boundary) * counter_mix * 0.72);
    float scan = cf_line(uv.y * 31.0 - counter_phase * gate_rate * 2.3, 0.014) * field;
    col = lerp(col, bone_color, scan * ink_gain * 0.36);

    float noise = cf_hash((float2)tid.xy + counter_phase * 19.0) - 0.5;
    col += noise * 0.008 * field;
    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
