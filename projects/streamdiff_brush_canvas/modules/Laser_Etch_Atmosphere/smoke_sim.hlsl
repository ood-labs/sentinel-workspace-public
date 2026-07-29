RWTexture2D<float4> OutputUAV : register(u0);

float sampleSmoke(float2 uv) {
    return _Tex0.SampleLevel(LinearSampler, uv, 0).r;
}

float sampleLaser(float2 uv, float2 texel) {
    float emitter = _Tex1.SampleLevel(LinearSampler, uv, 0).r;
    float radius = max(smoke_source_width, 0.25);
    float2 dx = float2(texel.x * radius, 0.0);
    float2 dy = float2(0.0, texel.y * radius);
    emitter = max(emitter, _Tex1.SampleLevel(LinearSampler, uv + dx, 0).r);
    emitter = max(emitter, _Tex1.SampleLevel(LinearSampler, uv - dx, 0).r);
    emitter = max(emitter, _Tex1.SampleLevel(LinearSampler, uv + dy, 0).r);
    emitter = max(emitter, _Tex1.SampleLevel(LinearSampler, uv - dy, 0).r);
    return smoothstep(0.08, 0.55, emitter);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID) {
    uint fieldWidth, fieldHeight;
    _Tex0.GetDimensions(fieldWidth, fieldHeight);
    if (DTid.x >= fieldWidth || DTid.y >= fieldHeight) return;

    uint laserWidth, laserHeight;
    _Tex1.GetDimensions(laserWidth, laserHeight);

    float2 fieldSize = float2(fieldWidth, fieldHeight);
    float2 fieldTexel = 1.0 / max(fieldSize, 1.0);
    float2 laserTexel = 1.0 / max(float2(laserWidth, laserHeight), 1.0);
    float2 uv = ((float2)DTid.xy + 0.5) / fieldSize;
    float dt = clamp(_DeltaTime, 0.0, 0.05);

    float phase = _Time * smoke_motion;
    float n0 = fbm2D(uv * smoke_scale + float2(phase * 0.17, -phase * 0.11), 4);
    float n1 = fbm2D(uv.yx * smoke_scale * 1.17 + float2(9.7 - phase * 0.13, phase * 0.09), 4);
    float2 drift = (float2(n0, n1) - 0.5) * smoke_turbulence;

    // Current pixels sample the previous field from below, producing upward motion.
    float2 backUv = uv + float2(drift.x * dt * 0.12,
                                smoke_rise * dt + drift.y * dt * 0.045);

    float spreadPx = max(smoke_spread, 0.0);
    float2 sx = float2(fieldTexel.x * spreadPx, 0.0);
    float2 sy = float2(0.0, fieldTexel.y * spreadPx);
    float advected = sampleSmoke(backUv) * 0.42;
    advected += sampleSmoke(backUv + sx) * 0.145;
    advected += sampleSmoke(backUv - sx) * 0.145;
    advected += sampleSmoke(backUv + sy) * 0.145;
    advected += sampleSmoke(backUv - sy) * 0.145;

    float retention = exp(-max(smoke_decay, 0.01) * dt);
    float emitter = sampleLaser(uv, laserTexel);
    float injected = emitter * smoke_injection * dt * 7.0;
    float smoke = saturate(advected * retention + injected);

    if (clear_smoke > 0.5) smoke = 0.0;
    OutputUAV[DTid.xy] = float4(smoke, emitter, n0, 1.0);
}
