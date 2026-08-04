// TP_Post / blur_v.hlsl — separable gaussian, vertical.
//
// Writes a THIRD buffer rather than back into the one the bright pass filled. Writing in place
// leaves the composite reading the unblurred extraction, which looks like a geometry aliasing
// bug and is nothing of the kind.
RWTexture2D<float4> Out : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint W, H;
    Out.GetDimensions(W, H);
    if (tid.x >= W || tid.y >= H) return;
    float2 uv = ((float2)tid.xy + 0.5) / float2(W, H);
    float2 s = float2(0.0, bloom_rad / max((float)H, 1.0));
    float3 a = float3(0, 0, 0);
    static const float w[5] = { 0.2270, 0.1946, 0.1216, 0.0540, 0.0162 };
    a += _Tex0.SampleLevel(LinearSampler, uv, 0).rgb * w[0];
    [unroll]
    for (int i = 1; i < 5; i++)
    {
        a += _Tex0.SampleLevel(LinearSampler, uv + s * (float)i, 0).rgb * w[i];
        a += _Tex0.SampleLevel(LinearSampler, uv - s * (float)i, 0).rgb * w[i];
    }
    Out[tid.xy] = float4(a, 1.0);
}
