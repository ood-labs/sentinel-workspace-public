RWTexture2D<float4> OutputUAV : register(u0);

float br_hash(float2 p) {
    p = frac(p * float2(0.137, 0.293));
    p += dot(p, p.yx + 17.41);
    return frac(p.x * p.y * 29.17);
}

float br_rect(float2 p, float2 halfSize) {
    float2 q = abs(p) - halfSize;
    return smoothstep(0.010, -0.010, max(q.x, q.y));
}

float br_line(float x, float width) {
    return smoothstep(width, 0.0, abs(frac(x) - 0.5));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float2 p = uv - 0.5;
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    p.x *= aspect;
    float t = rupture_phase * 6.2831853 * rupture_rate;
    float sweep = sin(t * 0.72) * 0.22 + cos(t * 0.37) * 0.11;
    float axis = p.x + rupture_diagonal * p.y - sweep;

    float curtain = smoothstep(0.50, 0.27, abs(axis));
    curtain *= saturate(blackout_amount * rupture_mix + 0.18);

    float aperture0 = br_line(axis * 2.1 + t * 0.11, aperture_width * 2.8);
    float aperture1 = br_line((axis + p.y * 0.34) * 3.7 - t * 0.08, aperture_width * 1.7);
    float aperture2 = br_line((axis - p.y * 0.18) * 6.1 + t * 0.14, aperture_width * 0.8);
    float apertures = saturate(aperture0 * 0.46 + aperture1 * 0.34 + aperture2 * 0.20);

    float3 base = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float2 warped = saturate(uv + float2(sin(t + uv.y * 8.0), cos(t * 0.8 + uv.x * 7.0)) * distortion);
    float3 displaced = _Tex0.SampleLevel(LinearSampler, warped, 0).rgb;
    float keep = saturate(apertures * (0.72 + 0.28 * sin(t + p.y * 9.0)));

    float3 col = lerp(base, blackout_color, curtain * rupture_mix);
    col = lerp(col, displaced * 0.88 + scar_color * 0.06, keep * rupture_mix);

    float shards = 0.0;
    [unroll]
    for (int i = 0; i < 7; ++i) {
        float fi = (float)i;
        float2 sp = p - float2(-0.38 + fi * 0.13 + sin(t * 0.6 + fi) * 0.025,
                               0.25 - fi * 0.09 + cos(t * 0.5 + fi * 1.4) * 0.04);
        sp.x += sp.y * (0.42 + fi * 0.025);
        float shard = br_rect(sp, float2(0.050 + fi * 0.006, 0.026 + fi * 0.004));
        shards += shard * step(fi + 0.5, 7.0);
        if (shard > 0.0) {
            float2 su = saturate(uv + float2(sin(t + fi) * distortion, cos(t * 0.9 + fi) * distortion));
            float3 ss = _Tex0.SampleLevel(LinearSampler, su, 0).rgb;
            col = lerp(col, ss * 0.7 + scar_color * 0.12, shard * shard_amount * rupture_mix);
        }
    }

    float scar = br_line(axis * 8.0 + t * 0.2, 0.014) * curtain;
    scar += br_line((p.y + axis * 0.6) * 19.0 - t * 0.07, 0.010) * curtain * 0.32;
    col = lerp(col, scar_color, saturate(scar * rupture_mix * 0.68));
    col += (br_hash((float2)tid.xy + rupture_phase * 53.0) - 0.5) * 0.010 * rupture_mix;
    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
