RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y)
        return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;

    // Enlarge and move the complete live specimen as one indivisible object.
    // The resulting edge tension makes the wide black field intentional while
    // keeping every rhythm, rupture, umbra, and geodesic spatially unified.
    float2 mainUv =
        (uv - main_center) / max(main_scale, 0.001) +
        float2(0.5, 0.5);
    float mainInside =
        step(0.0, mainUv.x) *
        step(mainUv.x, 1.0) *
        step(0.0, mainUv.y) *
        step(mainUv.y, 1.0);
    float3 mainColor =
        _Tex0.SampleLevel(LinearSampler, saturate(mainUv), 0).rgb *
        mainInside;

    OutputUAV[pixel] = float4(saturate(mainColor), 1.0);
}
