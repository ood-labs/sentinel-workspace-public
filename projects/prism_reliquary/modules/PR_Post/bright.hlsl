// PR_Post / bright.hlsl — isolate what is allowed to bloom.
//
// A soft knee rather than a hard cut: the reference's glow rolls off the speculars, and a
// hard threshold produces a visible contour where the bloom source begins.

RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float3 c  = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;

    float l = dot(c, float3(0.2126, 0.7152, 0.0722));
    float k = smoothstep(bloom_threshold, bloom_threshold + bloom_knee + 1e-4, l);

    OutputUAV[pixel] = float4(c * k, 1.0);
}
