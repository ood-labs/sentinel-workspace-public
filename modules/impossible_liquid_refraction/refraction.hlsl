RWTexture2D<float4> OutputUAV : register(u0);

float lr_wave(float2 p, float t, float s) {
    return sin(p.x * s + t) * 0.5 + sin(p.y * s * 1.31 - t * 0.73) * 0.35 + sin((p.x + p.y) * s * 0.61 + t * 1.4) * 0.15;
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float2 px = 1.0 / _Resolution.xy;
    float phase = refraction_phase * 6.2831853 + _Time * ripple_speed;
    float w0 = lr_wave(uv, phase, ripple_scale);
    float wx = lr_wave(uv + float2(px.x * 5.0, 0.0), phase, ripple_scale) - w0;
    float wy = lr_wave(uv + float2(0.0, px.y * 5.0), phase, ripple_scale) - w0;
    float2 offset = float2(wy, -wx) * distortion;
    float3 refracted = _Tex0.SampleLevel(LinearSampler, saturate(uv + offset), 0).rgb;
    float3 left = _Tex0.SampleLevel(LinearSampler, saturate(uv + offset - px * 3.0), 0).rgb;
    float3 right = _Tex0.SampleLevel(LinearSampler, saturate(uv + offset + px * 3.0), 0).rgb;
    float edge = length(right - left);
    float caustic = smoothstep(0.012, 0.18, edge) * caustic_gain;
    float droplet = smoothstep(0.62, 0.98, sin((uv.x * 17.0 + phase * 0.6) * (uv.y * 11.0 + 1.7)) * 0.5 + 0.5) * droplet_scale;
    float3 ink = refracted * (0.58 + 0.20 * w0) + liquid_color * caustic * 1.2;
    ink += accent_color * (caustic * 0.72 + droplet * 0.05);
    float3 outCol = lerp(refracted * 0.18 + dark_color * 0.28, ink, refraction_mix);
    OutputUAV[tid.xy] = float4(saturate(outCol), 1.0);
}
