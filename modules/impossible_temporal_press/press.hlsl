RWTexture2D<float4> OutputUAV : register(u0);

float hash_press(float p) {
    p = frac(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return frac(p);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint2 pixel = tid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float2 texel = 1.0 / _Resolution.xy;

    float quantizedPhase = floor(press_phase * step_count) / max(step_count, 1.0);
    float scan = frac(quantizedPhase + uv.y * scan_slope);
    float cutBand = smoothstep(cut_width, 0.0, abs(scan - scan_position));
    float rowHash = hash_press(floor(uv.y * 96.0) + floor(quantizedPhase * 97.0));
    float signedRow = rowHash * 2.0 - 1.0;

    float2 cutOffset = float2(signedRow, -signedRow * 0.27) *
                       texel * cut_strength * cutBand * strike;
    float2 plateOffset = float2(channel_split, -channel_split * 0.36) *
                         texel * (0.35 + strike * 1.8);

    float4 srcCenter = _Tex0.SampleLevel(PointSampler, saturate(uv + cutOffset), 0);
    float redPlate = _Tex0.SampleLevel(PointSampler, saturate(uv + plateOffset + cutOffset), 0).r;
    float bluePlate = _Tex0.SampleLevel(PointSampler, saturate(uv - plateOffset + cutOffset), 0).b;
    float3 separated = float3(redPlate, srcCenter.g, bluePlate);

    float2 memoryOffset = float2(
        sin(quantizedPhase * 6.2831853),
        cos(quantizedPhase * 6.2831853 * 0.73)
    ) * texel * memory_drift;
    float3 previous = _Tex1.SampleLevel(LinearSampler, saturate(uv + memoryOffset), 0).rgb;

    float dtMemory = pow(saturate(memory_decay), _DeltaTime * 60.0);
    float localMemory = dtMemory * (1.0 - cutBand * strike * memory_cutout);
    float3 mixed = lerp(separated, previous, saturate(localMemory));

    float edgeInk = abs(srcCenter.r - _Tex0.SampleLevel(PointSampler, saturate(uv + float2(texel.x,0)), 0).r) +
                    abs(srcCenter.g - _Tex0.SampleLevel(PointSampler, saturate(uv + float2(0,texel.y)), 0).g);
    mixed -= edgeInk * ink_crush * strike;

    float plateFlash = cutBand * strike * flash_gain;
    mixed = lerp(mixed, float3(0.95, 0.08, 0.035), plateFlash * step(0.55, rowHash));
    OutputUAV[pixel] = float4(mixed, 1.0);
}

