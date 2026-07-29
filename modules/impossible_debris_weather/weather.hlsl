RWTexture2D<float4> OutputUAV : register(u0);

float dw_hash(float2 p) {
    p = frac(p * float2(0.127, 0.319));
    p += dot(p, p.yx + 15.43);
    return frac(p.x * p.y * 33.11);
}

float dw_soft(float d, float w) {
    return smoothstep(w, 0.0, abs(d));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float2 aspect = float2(_Resolution.x / _Resolution.y, 1.0);
    float t = storm_phase * 6.2831853 * fall_speed;
    float3 base = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float baseLuma = dot(base, float3(0.299, 0.587, 0.114));

    float3 shards = 0.0;
    float shardMask = 0.0;
    [unroll]
    for (int i = 0; i < 40; ++i) {
        float fi = (float)i;
        float seed = dw_hash(float2(fi + 1.0, 7.3));
        float seed2 = dw_hash(float2(fi + 31.0, 2.9));
        float seed3 = dw_hash(float2(fi + 61.0, 9.1));
        float active = step(fi, shard_density * 2.0);
        float depth = frac(seed + storm_phase * (0.22 + seed2 * 0.78) * fall_speed);
        float x = frac(seed2 + wind * depth + sin(t * (0.3 + seed3) + fi) * 0.035);
        float y = frac(1.08 - depth + sin(t * 0.4 + fi * 0.7) * 0.025);
        float2 p = (float2(x, y) - uv) * aspect;
        float size = lerp(0.0012, 0.010, depth) * (0.7 + 0.7 * seed3);
        float streak = dw_soft(p.x, size) * dw_soft(p.y + size * (0.8 + depth * 3.0), max(0.001, shard_length * depth));
        float glint = streak * (0.35 + 0.65 * baseLuma) * active;
        shards += accent_color * glint * (0.52 + depth * 1.55);
        shardMask += glint * 1.4;
    }

    float vapor = sin((uv.x + uv.y * 0.41) * 12.0 + t * 0.18) * 0.5 + 0.5;
    vapor *= sin((uv.y - uv.x * 0.22) * 31.0 - t * 0.31) * 0.5 + 0.5;
    vapor *= vapor_gain * (0.22 + 0.78 * baseLuma);
    float veil = saturate(vapor * 0.28 + shardMask * 0.11);

    float3 col = lerp(base, base * (1.0 - veil * storm_mix * 0.35) + shards, storm_mix);
    col += dark_color * veil * storm_mix * 0.12;
    col += (dw_hash((float2)tid.xy + storm_phase * 71.0) - 0.5) * 0.010 * storm_mix;
    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
