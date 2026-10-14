// BR_Render / sky.hlsl -- the frame's sky table: 64 x 32 lat-long texels of single-scattered sky
// radiance (absolute: sun intensity and the sky gain are baked in). Everything else looks it up.
#include "render_common.hlsli"

RWStructuredBuffer<float4> SkyLut : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    if (tid.x >= SKY_W || tid.y >= SKY_H) return;
    float2 uv = (float2(tid.xy) + 0.5) / float2(SKY_W, SKY_H);
    float3 d = brSkyDir(uv);
    BRRec s = SceneBuf[SC_SUN];
    float3 sunDir = normalize(s.dims.xyz);
    float sunI = s.dims.w;
    float skyI = s.meta.x;
    float3 L = brSkyIntegrate(d, sunDir) * sunI * skyI;
    SkyLut[tid.y * SKY_W + tid.x] = float4(L, 1.0);
}
