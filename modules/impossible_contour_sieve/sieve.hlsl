RWTexture2D<float4> OutputUAV : register(u0);

float cs_hash(float2 p) {
    p = frac(p * float2(0.177, 0.293));
    p += dot(p, p.yx + 14.21);
    return frac(p.x * p.y * 31.17);
}

float cs_line(float x, float width) {
    return smoothstep(width, 0.0, abs(frac(x) - 0.5));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float2 px = 1.0 / _Resolution.xy;
    float t = sieve_phase * 6.2831853 * scan_rate;
    float3 base = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 left = _Tex0.SampleLevel(LinearSampler, saturate(uv - float2(px.x, 0.0)), 0).rgb;
    float3 right = _Tex0.SampleLevel(LinearSampler, saturate(uv + float2(px.x, 0.0)), 0).rgb;
    float3 up = _Tex0.SampleLevel(LinearSampler, saturate(uv - float2(0.0, px.y)), 0).rgb;
    float3 down = _Tex0.SampleLevel(LinearSampler, saturate(uv + float2(0.0, px.y)), 0).rgb;
    float lum = dot(base, float3(0.299, 0.587, 0.114));
    float edge = length(left - right) + length(up - down);
    edge = saturate(edge * edge_gain);
    float contour = smoothstep(contour_threshold * 0.55, contour_threshold, edge);
    float bands = floor(lum * quantize_bands) / max(quantize_bands - 1.0, 1.0);

    float boundary = 0.88 - abs(uv.x - 0.5) * 1.54 + sin(t * 0.41) * 0.06;
    float triMask = 1.0 - smoothstep(boundary - 0.025, boundary + 0.025, uv.y);
    triMask = lerp(1.0, triMask, triangle_cut);
    float scan = cs_line((uv.y + uv.x * 0.13) * 19.0 + t * 0.17, 0.014);
    float datum = cs_line((uv.x - uv.y) * 13.0 - t * 0.06, 0.010);
    float sparse = saturate(contour * 1.65 + scan * 0.22 + datum * 0.18);
    sparse *= triMask;

    float3 ink = lerp(dark_color, line_color, saturate(bands * 0.92 + contour * 0.55));
    ink = lerp(ink, accent_color, saturate(contour * 0.68 + datum * 0.26));
    float3 col = lerp(base, ink * sparse, sieve_mix);
    col = lerp(col, dark_color, (1.0 - triMask) * sieve_mix * 0.92);
    col += (cs_hash((float2)tid.xy + sieve_phase * 47.0) - 0.5) * 0.012 * sieve_mix;
    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
