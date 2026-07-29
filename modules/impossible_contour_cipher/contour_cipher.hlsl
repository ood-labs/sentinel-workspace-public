RWTexture2D<float4> OutputUAV : register(u0);

float cc_hash(float2 p) {
    p = frac(p * float2(0.119, 0.347));
    p += dot(p, p.yx + 11.83);
    return frac(p.x * p.y * 37.11);
}

float cc_line(float x, float width) {
    return smoothstep(width, 0.0, abs(frac(x) - 0.5));
}

float cc_rect(float2 p, float2 halfSize) {
    float2 q = abs(p) - halfSize;
    return smoothstep(0.009, -0.009, max(q.x, q.y));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float t = cipher_phase * 6.2831853 * cipher_rate;
    float2 p = uv - 0.5;
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    p.x *= aspect;

    float3 base = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float luma = dot(base, float3(0.299, 0.587, 0.114));
    float2 px = float2(1.0 / _Resolution.x, 1.0 / _Resolution.y);
    float lx = dot(_Tex0.SampleLevel(LinearSampler, saturate(uv + float2(px.x, 0.0)), 0).rgb, float3(0.299,0.587,0.114));
    float ly = dot(_Tex0.SampleLevel(LinearSampler, saturate(uv + float2(0.0, px.y)), 0).rgb, float3(0.299,0.587,0.114));
    float edge = saturate(abs(luma - lx) * 4.4 + abs(luma - ly) * 4.4);

    float steps = max(3.0, floor(contour_steps + 0.5));
    float q = floor(luma * steps) / steps;
    float contour = cc_line(q * steps + t * 0.12 + luma * 0.5, 0.035);
    contour *= saturate(0.4 + edge * 1.8);

    float2 scanP = p;
    scanP.x += scanP.y * scan_angle + sin(t * 0.7) * 0.07;
    float gridX = cc_line(scanP.x * cell_scale + t * 0.08, 0.018);
    float gridY = cc_line((scanP.y - scanP.x * 0.24) * cell_scale * 0.72 - t * 0.06, 0.018);
    float grid = saturate(gridX * 0.54 + gridY * 0.42);

    float darkField = 1.0 - smoothstep(0.16, 0.42, luma);
    float mapInk = saturate((contour * contour_gain * 0.72 + grid * 0.34 + edge * 0.34) * darkField);
    float paper = saturate(mapInk * cipher_mix);

    float2 stamp = frac((uv + float2(0.03, -0.02)) * float2(5.0, 8.0) + float2(t * 0.02, -t * 0.016));
    float registration = cc_line(stamp.x, 0.012) * cc_line(stamp.y * 0.5, 0.018);
    float bars = cc_line((uv.x + uv.y * 0.21 + t * 0.015) * 31.0, 0.010) * darkField;
    paper = saturate(paper + registration * 0.26 * cipher_mix + bars * 0.18 * cipher_mix);

    float3 col = lerp(base, cipher_color, darkField * cipher_mix * 0.42);
    col = lerp(col, paper_color, paper);

    float2 marker = float2(0.12 + sin(t * 0.8) * 0.28, -0.18 + cos(t * 0.6) * 0.18);
    float2 mp = p - marker;
    float mark = cc_rect(mp, float2(0.018, 0.14)) + cc_rect(mp, float2(0.14, 0.018));
    mark *= darkField * cipher_mix;
    col = lerp(col, accent_color, saturate(mark * 0.78));
    col += (cc_hash((float2)tid.xy + cipher_phase * 61.0) - 0.5) * 0.008 * cipher_mix;
    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
