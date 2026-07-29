RWTexture2D<float4> OutputUAV : register(u0);

float obs_hash(float2 p) {
    p = frac(p * float2(0.1031, 0.11369));
    p += dot(p, p.yx + 19.19);
    return frac((p.x + p.y) * p.x);
}

float obs_seg(float x, float width) {
    return smoothstep(width, 0.0, abs(frac(x) - 0.5));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float aspect = _Resolution.x / max(_Resolution.y, 1.0);
    float2 p = uv - aperture_center;
    p.x *= aspect;
    float2 q = p / max(aperture_size, 0.001);
    float r = length(q);
    float chamber = smoothstep(1.04, 0.78, r);
    float rim = smoothstep(0.96, 0.91, abs(r - 0.92));

    float phase = orbit_phase * 6.2831853 * orbit_rate;
    float cs = cos(phase), sn = sin(phase);
    float2 rot = float2(q.x * cs - q.y * sn, q.x * sn + q.y * cs);

    // The full master is remapped through the chamber, with a slow depth walk;
    // this is a real representation change rather than a flat overlay.
    float depth = saturate((1.0 - r) * chamber_depth);
    float2 chamberUv = float2(0.5 + rot.x * (0.49 + depth * 0.17),
                              0.5 + rot.y * (0.49 + depth * 0.10));
    chamberUv += float2(sin(phase + rot.y * 3.0), cos(phase * 0.7 + rot.x * 2.0)) * 0.018 * chamber_depth;
    float3 source = _Tex0.SampleLevel(LinearSampler, saturate(chamberUv), 0).rgb;

    float3 base = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 col = base;
    float chamberShade = 0.72 + 0.28 * saturate(1.0 - r * 0.62);
    float3 interior = source * chamberShade;
    col = lerp(col, interior, chamber * observatory_mix);

    float angle = atan2(rot.y, rot.x) / 6.2831853 + 0.5;
    float radial = r * scan_density - orbit_phase * orbit_rate * 3.0;
    float scan = obs_seg(radial, 0.035) * (0.45 + 0.55 * chamber_depth);
    float sweep = smoothstep(0.075, 0.0, abs(frac(angle + orbit_phase * orbit_rate * 0.18) - 0.5));
    float ringA = smoothstep(0.025, 0.0, abs(frac(r * 4.0 + orbit_phase * orbit_rate * 0.45) - 0.5));
    float ringB = smoothstep(0.018, 0.0, abs(frac(r * 9.0 - orbit_phase * orbit_rate * 0.75) - 0.5));

    float2 grid = abs(frac(rot * float2(5.0, 7.0)) - 0.5);
    float gridLine = max(smoothstep(0.025, 0.0, grid.x), smoothstep(0.02, 0.0, grid.y));
    float trace = saturate(scan * 0.9 + sweep * 0.8 + ringA * 0.28 + ringB * 0.18 + gridLine * 0.13) * chamber;

    float pulse = 0.72 + 0.28 * sin(orbit_phase * 6.2831853 * 2.0 + r * 18.0);
    col = lerp(col, aperture_color, trace * signal_gain * pulse * observatory_mix);
    col += trace_color * trace * signal_gain * 0.10 * observatory_mix;

    float depthShadow = smoothstep(0.74, 1.05, r) * chamber * 0.32;
    col *= 1.0 - depthShadow;
    col = lerp(col, aperture_color, rim * 0.72 * observatory_mix);

    float2 tick = abs(p);
    float registration = smoothstep(0.009, 0.0, abs(tick.x - 0.48)) * step(abs(p.y), 0.16) +
                         smoothstep(0.009, 0.0, abs(tick.y - 0.34)) * step(abs(p.x), 0.18);
    col = lerp(col, trace_color, registration * observatory_mix * 0.85);

    float grain = obs_hash((float2)tid.xy + orbit_phase * 31.0) - 0.5;
    col += grain * 0.006 * observatory_mix;
    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
