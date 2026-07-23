RWTexture2D<float4> OutputUAV : register(u0);

float luminanceAt(float2 uv) {
    float3 color = _Tex0.SampleLevel(LinearSampler, saturate(uv), 0).rgb;
    return dot(color, float3(0.2126, 0.7152, 0.0722));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    uint inputWidth, inputHeight;
    _Tex0.GetDimensions(inputWidth, inputHeight);
    float2 texel = 1.0 / max(float2(inputWidth, inputHeight), float2(1.0, 1.0));

    float center = luminanceAt(uv);
    float crossAverage = 0.25 * (
        luminanceAt(uv + float2(texel.x * 2.0, 0.0))
      + luminanceAt(uv - float2(texel.x * 2.0, 0.0))
      + luminanceAt(uv + float2(0.0, texel.y * 2.0))
      + luminanceAt(uv - float2(0.0, texel.y * 2.0))
    );
    float detail = center - crossAverage;
    float analyzed = (center - 0.5) * contrast + 0.5 + exposure;
    analyzed += detail * edge_gain;
    float preserved = smoothstep(threshold_low, threshold_high, saturate(analyzed));
    float value = lerp(saturate(analyzed), preserved, binary_mix);

    // A sparse array of specimen apertures keeps spatially unrelated tissue
    // from becoming one frame-sized connected component. The content inside
    // each aperture remains entirely source-derived.
    float2 specimenCell = frac(uv * float2(12.0, 7.0)) - 0.5;
    float specimenGate = smoothstep(0.34, 0.24, length(specimenCell));
    value *= lerp(1.0, specimenGate, aperture_gate);

    float registration = smoothstep(0.018, 0.0,
        min(abs(frac(uv.x * 24.0) - 0.5), abs(frac(uv.y * 14.0) - 0.5))) * 0.05;
    value = saturate(value + registration * specimenGate);
    OutputUAV[tid.xy] = float4(value.xxx, 1.0);
}
