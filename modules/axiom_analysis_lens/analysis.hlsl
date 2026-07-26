RWTexture2D<float4> OutputUAV : register(u0);

float luma(float3 c)
{
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    uint sourceW;
    uint sourceH;
    _Tex0.GetDimensions(sourceW, sourceH);
    float2 texel = 1.0 / max(float2((float)sourceW, (float)sourceH), float2(1.0, 1.0));

    float center = luma(_Tex0.SampleLevel(LinearSampler, uv, 0).rgb);
    float crossBlur =
        luma(_Tex0.SampleLevel(LinearSampler, uv + float2(texel.x, 0.0), 0).rgb) +
        luma(_Tex0.SampleLevel(LinearSampler, uv - float2(texel.x, 0.0), 0).rgb) +
        luma(_Tex0.SampleLevel(LinearSampler, uv + float2(0.0, texel.y), 0).rgb) +
        luma(_Tex0.SampleLevel(LinearSampler, uv - float2(0.0, texel.y), 0).rgb);
    crossBlur *= 0.25;

    float signal = lerp(center, crossBlur, preblur);
    signal = (signal - 0.5) * contrast + 0.5;
    signal += (center - crossBlur) * detail_boost;
    signal = pow(saturate(signal), max(0.1, gamma));
    float binary = smoothstep(threshold - softness, threshold + softness, signal);
    if (invert_signal != 0) binary = 1.0 - binary;

    // Two-level print signal with a tiny graphite shoulder. This exact output is
    // what Features observes; there is no decorative monitor overlay.
    float graphite = smoothstep(threshold - softness * 4.0,
                                threshold - softness * 0.5,
                                signal) * (1.0 - binary);
    float outSignal = saturate(binary + graphite * graphite_shoulder);

    // A print-separation lattice breaks overscale paper masses into bounded
    // islands. This is semantic conditioning: it preserves the plate's local
    // silhouettes while preventing either the paper or the field from becoming
    // one meaningless full-frame connected component.
    float2 cellUv = frac(uv * float2(island_columns, island_rows));
    float seamDistance = min(min(cellUv.x, 1.0 - cellUv.x),
                             min(cellUv.y, 1.0 - cellUv.y));
    float separated = smoothstep(island_seam, island_seam + 0.015, seamDistance);
    outSignal *= lerp(1.0, separated, islandize);

    OutputUAV[pixel] = float4(outSignal.xxx, 1.0);
}
