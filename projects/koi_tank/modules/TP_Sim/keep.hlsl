// TP_Sim / keep.hlsl — legacy, intentionally unused.
//
// A pass cannot bind one texture as both SRV and UAV, so there is no in-place ping-pong to be
// had. The canonical pipeline now runs every substep directly through `state`; retaining this
// file documents the abandoned copy-back design but no manifest pass references it.
#include "sim.hlsli"

RWTexture2D<float4> StateOut : register(u0);

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint gw, gh;
    _Tex0.GetDimensions(gw, gh);
    if (tid.x >= gw || tid.y >= gh) return;
    StateOut[int2(tid.xy)] = _Tex0.Load(int3(int2(tid.xy), 0));
}
