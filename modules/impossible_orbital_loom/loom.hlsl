RWTexture2D<float4> OutputUAV : register(u0);

float ol_hash(float2 p) {
    p = frac(p * float2(0.173, 0.287));
    p += dot(p, p.yx + 19.17);
    return frac(p.x * p.y * 31.71);
}

float ol_ring(float value, float width) {
    return smoothstep(width, 0.0, abs(frac(value) - 0.5));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float2 aspect = float2(_Resolution.x / _Resolution.y, 1.0);
    float2 center = float2(0.52, 0.50);
    float2 q = (uv - center) * aspect;
    float radius = length(q);
    float angle = atan2(q.y, q.x);
    float t = loom_phase * 6.2831853 * orbit_speed;

    float sourceRadius = saturate(radius * (1.0 + sin(angle * ring_count - t) * radial_warp));
    float sourceAngle = angle + t * 0.42 + sin(radius * 17.0 - t) * radial_warp * 0.8;
    float2 polarUv = center + float2(cos(sourceAngle), sin(sourceAngle)) * (sourceRadius / aspect);
    polarUv = saturate(polarUv);

    float3 base = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 orbital = _Tex0.SampleLevel(LinearSampler, polarUv, 0).rgb;
    float orbitalLuma = dot(orbital, float3(0.299, 0.587, 0.114));
    orbital = lerp(dark_color, orbital * (0.72 + orbitalLuma * 0.72), 0.80);

    float apertureMask = 1.0 - smoothstep(aperture, aperture + 0.035, radius);
    float innerMask = smoothstep(0.035, 0.15, radius);
    float rings = ol_ring(radius * ring_count - t * 0.32 + sin(angle * 3.0) * 0.12, 0.032);
    float spokes = ol_ring(angle / 6.2831853 * 9.0 + radius * 2.0 + t * 0.06, 0.018);
    float stitches = saturate(rings * 0.60 + spokes * 0.34) * innerMask * stitch_gain;

    float seam = smoothstep(0.012, 0.0, abs(frac(angle / 6.2831853 * 18.0 + t * 0.11) - 0.5));
    seam *= step(0.12, radius) * step(radius, aperture + 0.02);
    float grain = (ol_hash((float2)tid.xy + loom_phase * 53.0) - 0.5) * 0.018;

    float3 col = lerp(base, orbital, loom_mix * apertureMask);
    col = lerp(col, dark_color, saturate((1.0 - apertureMask) * loom_mix * 0.42));
    col += accent_color * (stitches * 0.42 + seam * 0.20);
    col += grain * loom_mix;
    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
