// LT_Lens / blur_h.hlsl — vertical half of the tight bloom gaussian.
// Scaled pass: the target extent comes from GetDimensions, never from _Resolution.
RWTexture2D<float4> OutputUAV : register(u0);
static const float W9[9] = { 0.0276, 0.0663, 0.1238, 0.1802, 0.2042, 0.1802, 0.1238, 0.0663, 0.0276 };

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint W, H; OutputUAV.GetDimensions(W, H);
    uint2 pix = DTid.xy;
    if (pix.x >= W || pix.y >= H) return;
    float2 res = float2(W, H);
    float2 uv = ((float2)pix + 0.5) / res;
    float st = bloom_radius / res.y;
    float3 s = 0.0.xxx;
    [unroll] for (int i = 0; i < 9; i++)
        s += _Tex0.SampleLevel(LinearSampler, uv + float2(0.0, ((float)i - 4.0) * st), 0).rgb * W9[i];
    OutputUAV[pix] = float4(s, 1.0);
}
