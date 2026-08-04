// TP_Post / bright.hlsl — isolate what is genuinely brighter than the scene.
//
// The threshold matters more here than in most shows: the studio backdrop occupies most of the
// frame at around 0.6, and a threshold under that blooms the BACKGROUND, which reads as fog
// rather than as glare. What should bloom is the glass rim and the sun glints on the ripples,
// and those are several times brighter than anything else.
RWTexture2D<float4> Out : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint W, H;
    Out.GetDimensions(W, H);
    if (tid.x >= W || tid.y >= H) return;

    float2 uv = ((float2)tid.xy + 0.5) / float2(W, H);
    float3 c = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;
    float l = max(max(c.r, c.g), c.b);
    float k = max(l - bloom_thr, 0.0) / max(l, 1e-4);
    Out[tid.xy] = float4(c * k, 1.0);
}
