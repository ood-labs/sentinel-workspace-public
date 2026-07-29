RWTexture2D<float4> OutputUAV : register(u0);

float qc_hash(float2 p) {
    p = frac(p * float2(0.193, 0.271));
    p += dot(p, p.yx + 17.31);
    return frac(p.x * p.y * 29.17);
}

float qc_line(float x, float width) {
    return smoothstep(width, 0.0, abs(frac(x) - 0.5));
}

float2 qc_rot(float2 p, float a) {
    float s = sin(a), c = cos(a);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float t = cathedral_phase * 6.2831853 * chamber_speed;
    float2 cell = floor(uv * 2.0);
    float2 local = frac(uv * 2.0) - 0.5;
    float chamberId = cell.x + cell.y * 2.0;

    float angle = (chamberId - 1.5) * 0.31 + t * (0.35 + 0.12 * chamberId);
    local = qc_rot(local, angle);
    float2 drift = float2(sin(t * 0.7 + chamberId * 1.9), cos(t * 0.53 - chamberId * 1.3))
                 * chamber_drift * (0.45 + 0.55 * sin(t + chamberId));
    float2 sampleUv = saturate(local * cell_zoom + 0.5 + drift);
    if (chamberId > 1.5) sampleUv = sampleUv.yx;
    if (chamberId > 2.5) sampleUv.x = 1.0 - sampleUv.x;

    float3 base = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 chamber = _Tex0.SampleLevel(LinearSampler, sampleUv, 0).rgb;
    float lum = dot(chamber, float3(0.299, 0.587, 0.114));
    chamber *= 0.68 + lum * 0.74;

    float verticalCross = 1.0 - smoothstep(cross_width, cross_width + 0.012, abs(uv.x - 0.5));
    float horizontalCross = 1.0 - smoothstep(cross_width, cross_width + 0.012, abs(uv.y - 0.5));
    float cross = saturate(verticalCross + horizontalCross);
    float border = qc_line(local.x * 2.0 + 0.5, 0.018) + qc_line(local.y * 2.0 + 0.5, 0.018);
    border *= 0.55;

    float hatch = qc_line((local.x + local.y * 0.77) * 17.0 + t * 0.13 + chamberId * 0.8, 0.014);
    float datum = qc_line((local.x - local.y) * 5.0 - t * 0.08 + chamberId, 0.010);
    float marks = saturate(hatch * 0.55 + datum * 0.32 + border) * glyph_gain;
    float3 col = lerp(base, chamber, cathedral_mix);
    col = lerp(col, dark_color, cross * cathedral_mix * 0.88);
    col += accent_color * marks * (0.34 + 0.30 * lum);
    col += (qc_hash((float2)tid.xy + cathedral_phase * 61.0) - 0.5) * 0.014 * cathedral_mix;
    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
