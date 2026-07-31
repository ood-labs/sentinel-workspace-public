// PR_Post / blur_h.hlsl — separable gaussian, horizontal half.

RWTexture2D<float4> OutputUAV : register(u0);

static const float W[7] = { 0.1964, 0.1747, 0.1210, 0.0656, 0.0278, 0.0092, 0.0024 };

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float  px = bloom_radius / _Resolution.x;

    float3 s = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb * W[0];
    [unroll] for (int i = 1; i < 7; i++)
    {
        float o = (float)i * px;
        s += _Tex0.SampleLevel(LinearSampler, uv + float2(o, 0.0), 0).rgb * W[i];
        s += _Tex0.SampleLevel(LinearSampler, uv - float2(o, 0.0), 0).rgb * W[i];
    }
    OutputUAV[pixel] = float4(s, 1.0);
}
