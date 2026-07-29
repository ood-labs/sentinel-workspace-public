RWTexture2D<float4> OutputUAV : register(u0);

float laserAt(float2 uv) {
    return _Tex1.SampleLevel(LinearSampler, uv, 0).r;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID) {
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float2 texel = 1.0 / _Resolution.xy;

    float smoke = saturate(_Tex2.SampleLevel(LinearSampler, uv, 0).r);
    float smokeL = _Tex2.SampleLevel(LinearSampler, uv - float2(texel.x * 3.0, 0.0), 0).r;
    float smokeR = _Tex2.SampleLevel(LinearSampler, uv + float2(texel.x * 3.0, 0.0), 0).r;
    float smokeU = _Tex2.SampleLevel(LinearSampler, uv - float2(0.0, texel.y * 3.0), 0).r;
    float smokeD = _Tex2.SampleLevel(LinearSampler, uv + float2(0.0, texel.y * 3.0), 0).r;
    float2 smokeGradient = float2(smokeR - smokeL, smokeD - smokeU);

    float laser = smoothstep(0.05, 0.6, laserAt(uv));
    float radius = max(etch_width, 0.5);
    float2 ex = float2(texel.x * radius, 0.0);
    float2 ey = float2(0.0, texel.y * radius);
    float nearLaser = laser;
    nearLaser = max(nearLaser, laserAt(uv + ex));
    nearLaser = max(nearLaser, laserAt(uv - ex));
    nearLaser = max(nearLaser, laserAt(uv + ey));
    nearLaser = max(nearLaser, laserAt(uv - ey));
    nearLaser = max(nearLaser, laserAt(uv + ex + ey));
    nearLaser = max(nearLaser, laserAt(uv - ex + ey));
    nearLaser = max(nearLaser, laserAt(uv + ex - ey));
    nearLaser = max(nearLaser, laserAt(uv - ex - ey));
    float heatHalo = saturate(nearLaser - laser * 0.45);

    float phase = _Time * trail_motion;
    float2 wobble = float2(
        fbm2D(uv * trail_scale + float2(phase * 0.15, -phase * 0.08), 4),
        fbm2D(uv.yx * trail_scale + float2(13.1 - phase * 0.11, phase * 0.07), 4)
    ) - 0.5;

    float reactive = saturate(smoke * 0.8 + heatHalo * 0.65);
    float2 displacement = (smokeGradient * 1.7 + wobble * reactive * 0.22);
    displacement *= displacement_amount;
    float2 distortedUv = uv + displacement;

    float3 original = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float3 displaced = _Tex0.SampleLevel(LinearSampler, distortedUv, 0).rgb;
    float3 col = lerp(original, displaced, saturate(effect_mix));

    // A restrained char line, hot core, and pale smoke make the trace feel etched.
    float charMask = saturate(heatHalo * etch_char + smoke * soot_amount * 0.22);
    col *= 1.0 - charMask * 0.48;

    float3 ember = etch_color * (laser * etch_heat + heatHalo * etch_glow);
    col += ember * saturate(effect_mix);

    float smokeShape = pow(saturate(smoke), max(smoke_contrast, 0.1));
    float smokeLight = saturate(0.38 + nearLaser * 0.38 + wobble.x * 0.20);
    float smokeAlpha = smokeShape * smoke_opacity * saturate(effect_mix);
    float luminance = dot(col, float3(0.2126, 0.7152, 0.0722));
    float3 smokeBody = smoke_tint * (0.24 + luminance * 0.44) * smokeLight;
    col = lerp(col, smokeBody, smokeAlpha * 0.62);
    col += smoke_tint * smokeAlpha * 0.11;

    OutputUAV[pixel] = float4(max(col, 0.0), 1.0);
}
