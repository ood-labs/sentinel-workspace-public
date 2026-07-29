RWTexture2D<float4> OutputUAV : register(u0);

float do_hash(float2 p) {
    p = frac(p * float2(0.173, 0.319));
    p += dot(p, p.yx + 19.17);
    return frac(p.x * p.y * 31.71);
}

float do_disc(float2 p, float2 c, float r) {
    return 1.0 - smoothstep(r, r * 1.8, length(p - c));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float2 aspect = float2(_Resolution.x / _Resolution.y, 1.0);
    float2 p = (uv - 0.5) * aspect;
    float4 src = _Tex0.SampleLevel(LinearSampler, uv, 0);
    float3 ink = src.rgb * 0.22 + dark_color * 0.28;
    float phase = orbit_phase * 6.2831853 + _Time * orbital_speed;
    float particles = 0.0;
    float3 particleColor = 0.0;
    [unroll] for (int i = 0; i < 96; i++) {
        float fi = (float)i;
        float active = step(fi + 0.5, particle_count);
        float h0 = do_hash(float2(fi, 3.1));
        float h1 = do_hash(float2(fi, 9.7));
        float h2 = do_hash(float2(fi, 14.2));
        float shell = 0.20 + h0 * shell_radius;
        float ang = h1 * 6.2831853 + phase * (0.22 + h2 * 0.8) + sin(phase * 0.7 + fi) * 0.12;
        float depth = 0.35 + h2 * depth_spread;
        float2 c = float2(cos(ang), sin(ang)) * shell * (0.76 + depth * 0.34);
        float2 cUv = c / aspect + 0.5;
        float localLum = dot(_Tex0.SampleLevel(LinearSampler, saturate(cUv), 0).rgb, float3(0.299, 0.587, 0.114));
        float size = (0.003 + h0 * 0.012) * (1.4 - depth) * (0.55 + localLum * 1.2) * shard_gain;
        float d = do_disc(p, c, size) * active;
        particles = max(particles, d);
        float3 ccol = (h1 > 0.73) ? accent_color : shard_color;
        particleColor += ccol * d * (0.38 + localLum * 0.92);
    }
    float ring = 1.0 - smoothstep(0.008, 0.018, abs(length(p) - (0.27 + 0.04 * sin(phase))));
    ink += particleColor + shard_color * ring * 0.16;
    ink += accent_color * particles * 0.18;
    float3 outCol = lerp(src.rgb * 0.16 + dark_color * 0.25, ink, particle_mix);
    OutputUAV[tid.xy] = float4(saturate(outCol), 1.0);
}
