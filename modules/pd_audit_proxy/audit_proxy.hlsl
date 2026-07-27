RWTexture2D<float4> OutputUAV : register(u0);

float pdLuma(float3 color)
{
    return dot(color, float3(0.2126, 0.7152, 0.0722));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)tid.xy + 0.5) / _Resolution.xy;
    uint sourceWidth;
    uint sourceHeight;
    _Tex0.GetDimensions(sourceWidth, sourceHeight);
    float2 sourceTexel = 1.0 / max(float2((float)sourceWidth, (float)sourceHeight), float2(1.0, 1.0));

    float3 centerColor = _Tex0.SampleLevel(LinearSampler, uv, 0.0).rgb;
    float center = pdLuma(centerColor);
    float left = pdLuma(_Tex0.SampleLevel(LinearSampler, uv - float2(sourceTexel.x, 0.0), 0.0).rgb);
    float right = pdLuma(_Tex0.SampleLevel(LinearSampler, uv + float2(sourceTexel.x, 0.0), 0.0).rgb);
    float up = pdLuma(_Tex0.SampleLevel(LinearSampler, uv - float2(0.0, sourceTexel.y), 0.0).rgb);
    float down = pdLuma(_Tex0.SampleLevel(LinearSampler, uv + float2(0.0, sourceTexel.y), 0.0).rgb);

    float horizontal = right - left;
    float vertical = down - up;
    float gradient = sqrt(horizontal * horizontal + vertical * vertical);
    float neighborhood = (left + right + up + down) * 0.25;
    float localContrast = abs(center - neighborhood);

    float normalized = saturate((center - black_point) / max(white_point - black_point, 0.001));
    normalized = saturate(normalized * signal_gain);
    normalized = saturate(normalized + gradient * edge_gain + localContrast * detail_gain);

    float steps = max(2.0, band_count);
    float banded = floor(normalized * steps + 0.5) / steps;
    float binary = smoothstep(
        binary_threshold - binary_softness,
        binary_threshold + binary_softness,
        normalized
    );
    float disciplined = lerp(banded, binary, binary_mix);
    disciplined = invert_signal != 0 ? 1.0 - disciplined : disciplined;

    // The liability color survives only as a small diagnostic of source continuity.
    float warmEvidence = saturate(centerColor.r - max(centerColor.g, centerColor.b) * 1.35);
    float3 monochrome = disciplined.xxx;
    float3 warm = float3(1.0, 0.31, 0.025) * warmEvidence * preserve_liability;
    float analysisSafeArea =
        step(0.035, uv.x) * step(uv.x, 0.965) *
        step(0.055, uv.y) * step(uv.y, 0.945);
    float outsideValue = invert_signal != 0 ? 1.0 : 0.0;
    float3 color = lerp(outsideValue.xxx, monochrome + warm, analysisSafeArea);

    OutputUAV[tid.xy] = float4(saturate(color), 1.0);
}
