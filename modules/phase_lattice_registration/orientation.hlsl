RWTexture2D<float4> OutputUAV : register(u0);

float orientation_luma(float3 c)
{
    return dot(c, float3(0.299, 0.587, 0.114));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint outputWidth;
    uint outputHeight;
    OutputUAV.GetDimensions(outputWidth, outputHeight);
    if (DTid.x >= outputWidth || DTid.y >= outputHeight)
        return;

    uint sourceWidth;
    uint sourceHeight;
    _Tex0.GetDimensions(sourceWidth, sourceHeight);
    float aspect = sourceWidth / max((float)sourceHeight, 1.0);
    float2 coreUV = saturate(float2(0.5, 0.5) + registration_core);
    float2 radiusUV = probe_radius * float2(1.0 / aspect, 1.0);
    float diagonal = 0.70710678118;

    float2 d0 = float2(1.0, 0.0);
    float2 d1 = float2(diagonal, diagonal);
    float2 d2 = float2(0.0, 1.0);
    float2 d3 = float2(-diagonal, diagonal);
    float2 d4 = float2(-1.0, 0.0);
    float2 d5 = float2(-diagonal, -diagonal);
    float2 d6 = float2(0.0, -1.0);
    float2 d7 = float2(diagonal, -diagonal);

    float2 moment = float2(0.0, 0.0);
    moment += d0 * orientation_luma(_Tex0.SampleLevel(LinearSampler, saturate(coreUV + d0 * radiusUV), 0).rgb);
    moment += d1 * orientation_luma(_Tex0.SampleLevel(LinearSampler, saturate(coreUV + d1 * radiusUV), 0).rgb);
    moment += d2 * orientation_luma(_Tex0.SampleLevel(LinearSampler, saturate(coreUV + d2 * radiusUV), 0).rgb);
    moment += d3 * orientation_luma(_Tex0.SampleLevel(LinearSampler, saturate(coreUV + d3 * radiusUV), 0).rgb);
    moment += d4 * orientation_luma(_Tex0.SampleLevel(LinearSampler, saturate(coreUV + d4 * radiusUV), 0).rgb);
    moment += d5 * orientation_luma(_Tex0.SampleLevel(LinearSampler, saturate(coreUV + d5 * radiusUV), 0).rgb);
    moment += d6 * orientation_luma(_Tex0.SampleLevel(LinearSampler, saturate(coreUV + d6 * radiusUV), 0).rgb);
    moment += d7 * orientation_luma(_Tex0.SampleLevel(LinearSampler, saturate(coreUV + d7 * radiusUV), 0).rgb);

    float innerScale = 0.53;
    moment += d0 * orientation_luma(_Tex0.SampleLevel(LinearSampler, saturate(coreUV + d0 * radiusUV * innerScale), 0).rgb) * 0.55;
    moment += d1 * orientation_luma(_Tex0.SampleLevel(LinearSampler, saturate(coreUV + d1 * radiusUV * innerScale), 0).rgb) * 0.55;
    moment += d2 * orientation_luma(_Tex0.SampleLevel(LinearSampler, saturate(coreUV + d2 * radiusUV * innerScale), 0).rgb) * 0.55;
    moment += d3 * orientation_luma(_Tex0.SampleLevel(LinearSampler, saturate(coreUV + d3 * radiusUV * innerScale), 0).rgb) * 0.55;
    moment += d4 * orientation_luma(_Tex0.SampleLevel(LinearSampler, saturate(coreUV + d4 * radiusUV * innerScale), 0).rgb) * 0.55;
    moment += d5 * orientation_luma(_Tex0.SampleLevel(LinearSampler, saturate(coreUV + d5 * radiusUV * innerScale), 0).rgb) * 0.55;
    moment += d6 * orientation_luma(_Tex0.SampleLevel(LinearSampler, saturate(coreUV + d6 * radiusUV * innerScale), 0).rgb) * 0.55;
    moment += d7 * orientation_luma(_Tex0.SampleLevel(LinearSampler, saturate(coreUV + d7 * radiusUV * innerScale), 0).rgb) * 0.55;

    float confidence = saturate(length(moment) * 1.8);
    float2 targetDirection = length(moment) > 1e-5 ? normalize(moment) : float2(1.0, 0.0);

    float2 feedbackUV = ((float2)DTid.xy + 0.5) / float2(outputWidth, outputHeight);
    float4 previous = _Tex1.SampleLevel(LinearSampler, feedbackUV, 0);
    float2 previousDirection = previous.a > 0.5
        ? normalize(previous.rg * 2.0 - 1.0)
        : targetDirection;

    float response = (1.0 - azimuth_smoothing) *
        smoothstep(signal_floor, min(1.0, signal_floor + 0.24), confidence);
    float2 smoothedDirection = normalize(lerp(previousDirection, targetDirection, max(response, 0.0005)));
    float smoothedConfidence = lerp(previous.b, confidence, max(response, 0.015));

    OutputUAV[DTid.xy] = float4(smoothedDirection * 0.5 + 0.5, smoothedConfidence, 1.0);
}
