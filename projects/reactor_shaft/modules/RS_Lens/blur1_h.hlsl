#include "blur_common.hlsli"
Texture2D<float4> Src : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);
[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy; uint W, H; OutputUAV.GetDimensions(W, H);
    if (px.x >= W || px.y >= H) return;
    OutputUAV[px] = float4(rs_blurDir(Src, px, uint2(W, H), float2(1, 0), bloom_radius), 1.0);
}
