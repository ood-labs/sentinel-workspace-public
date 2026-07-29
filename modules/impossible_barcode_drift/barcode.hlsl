RWTexture2D<float4> OutputUAV : register(u0);

float bd_hash(float2 p) {
    p = frac(p * float2(0.151, 0.337));
    p += dot(p, p.yx + 17.11);
    return frac(p.x * p.y * 29.43);
}

float bd_line(float x, float width) {
    return smoothstep(width, 0.0, abs(frac(x) - 0.5));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float t = barcode_phase * 6.2831853 * read_speed;
    float colId = floor(uv.x * column_count);
    float colUv = (colId + 0.5) / column_count;
    float jitter = (bd_hash(float2(colId, floor(barcode_phase * 13.0))) - 0.5) * column_jitter;
    float2 sampleUv = saturate(float2(colUv + jitter * (0.5 + 0.5 * sin(t + colId)), uv.y));
    float3 base = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 columnSample = _Tex0.SampleLevel(LinearSampler, sampleUv, 0).rgb;
    float lum = dot(columnSample, float3(0.299, 0.587, 0.114));
    float seed = bd_hash(float2(colId * 1.73 + 4.0, 9.2));
    float binary = step(seed, saturate(0.28 + lum * 1.2));
    float stripe = bd_line(uv.x * column_count * strip_stretch + seed * 0.38 + t * 0.05, 0.035 + seed * 0.028);
    float bar = saturate(binary * (0.66 + stripe * 0.34));
    float scanBand = bd_line(uv.y * 18.0 + colId * 0.07 - t * 0.12, 0.012);

    float headX = frac(barcode_phase * read_speed * 0.72 + 0.08);
    float head = smoothstep(0.032, 0.0, abs(uv.x - headX));
    float trail = smoothstep(0.16, 0.0, frac(headX - uv.x + 1.0));
    float ticks = bd_line(uv.y * 31.0 + t * 0.04, 0.012) * step(0.86, bd_hash(float2(colId, 21.0)));

    float3 ink = lerp(dark_color, line_color, bar);
    ink = lerp(ink, accent_color, head * head_gain + ticks * 0.24);
    ink += columnSample * 0.18 * (1.0 - bar);
    float3 col = lerp(base, ink, barcode_mix);
    col += accent_color * trail * head_gain * 0.10;
    col += line_color * scanBand * 0.08 * barcode_mix;
    col += (bd_hash((float2)tid.xy + barcode_phase * 43.0) - 0.5) * 0.010 * barcode_mix;
    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
