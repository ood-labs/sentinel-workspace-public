// VT_Plates / front.hlsl — plates that sit IN FRONT of the sculpted masses: the glass shelf,
// the checkerboard strip, the bean pebbles and the confetti dashes.
#include "plates_body.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float3 col; float cov;
    drawPlates(uv, 1.0 / _Resolution.y, true, col, cov);
    OutputUAV[pixel] = float4(col, cov);
}
