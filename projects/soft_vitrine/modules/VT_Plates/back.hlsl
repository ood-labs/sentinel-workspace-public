// VT_Plates / back.hlsl — plates that hang BEHIND the sculpted masses: the pink grid slab and
// the starfield portal panel. rgb = colour, a = coverage; the split lanes are published by the
// small passes downstream.
#include "plates_body.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float3 col; float cov;
    drawPlates(uv, 1.0 / _Resolution.y, false, col, cov);
    OutputUAV[pixel] = float4(col, cov);
}
