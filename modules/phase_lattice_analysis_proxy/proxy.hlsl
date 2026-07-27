RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y)
        return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float3 source = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float luma = dot(source, float3(0.299, 0.587, 0.114));
    float analysisLuma =
        pow(saturate(luma * analysis_gain), analysis_gamma);

    // A neutral, faithful analysis preview: the real mounted specimen is
    // downsampled for bounded Features work without introducing diagnostic
    // imagery or changing its spatial coordinate contract.
    float3 neutral = analysisLuma * float3(0.96, 0.98, 0.94);
    OutputUAV[pixel] = float4(saturate(neutral), 1.0);
}
