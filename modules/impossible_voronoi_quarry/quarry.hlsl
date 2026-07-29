RWTexture2D<float4> OutputUAV : register(u0);

float vq_hash(float2 p) {
    p = frac(p * float2(0.163, 0.307));
    p += dot(p, p.yx + 16.73);
    return frac(p.x * p.y * 28.17);
}

float vq_line(float x, float width) {
    return smoothstep(width, 0.0, abs(frac(x) - 0.5));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float2 aspect = float2(_Resolution.x / _Resolution.y, 1.0);
    float t = quarry_phase * 6.2831853 * plate_speed;
    float nearest = 99.0;
    float second = 99.0;
    float2 nearestSite = 0.0;
    float siteId = 0.0;

    [unroll]
    for (int i = 0; i < 18; ++i) {
        float fi = (float)i;
        float active = step(fi, plate_count);
        float2 seed = float2(vq_hash(float2(fi + 1.0, 3.1)), vq_hash(float2(fi + 21.0, 8.7)));
        float2 drift = float2(sin(t * (0.22 + vq_hash(seed + 4.0)) + fi), cos(t * (0.17 + vq_hash(seed + 8.0)) - fi * 0.7)) * 0.14;
        float2 site = frac(seed + drift + quarry_phase * float2(0.09 + fi * 0.003, -0.06 + fi * 0.002));
        float2 delta = (uv - site) * aspect;
        float d = dot(delta, delta) + (1.0 - active) * 100.0;
        if (d < nearest) { second = nearest; nearest = d; nearestSite = site; siteId = fi; }
        else if (d < second) second = d;
    }

    float edge = saturate((sqrt(second) - sqrt(nearest)) * 8.0);
    float2 local = (uv - nearestSite) * aspect;
    float2 warp = local * (0.35 + 0.62 * plate_scale) + nearestSite;
    warp += float2(sin(t * 0.6 + siteId), cos(t * 0.47 - siteId)) * 0.025;
    float3 base = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 stone = _Tex0.SampleLevel(LinearSampler, saturate(warp), 0).rgb;
    float lum = dot(stone, float3(0.299, 0.587, 0.114));
    stone = lerp(dark_color, stone * (0.62 + lum * 0.82), 0.86);
    float mineralTone = 0.24 + 0.76 * frac(siteId * 0.173 + quarry_phase * 0.11);
    float3 mineral = dark_color + float3(0.16, 0.14, 0.12) * mineralTone;
    mineral += accent_color * (0.045 + 0.075 * lum);
    stone = lerp(mineral, stone, 0.28);

    float facet = vq_line((local.x + local.y * 0.63) * 5.0 + siteId * 0.37 + t * 0.05, 0.018);
    float seam = saturate(1.0 - edge) * seam_gain;
    float marks = facet * facet_gain * (0.3 + 0.7 * lum);
    float3 col = lerp(base, stone, quarry_mix);
    col = lerp(col, dark_color, seam * quarry_mix * 0.64);
    col += accent_color * marks * 0.42;
    col += accent_color * (1.0 - edge) * 0.12 * quarry_mix;
    col += (vq_hash((float2)tid.xy + quarry_phase * 59.0) - 0.5) * 0.012 * quarry_mix;
    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
