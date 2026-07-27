// Commit detector state for the next cook.
#include "common.hlsli"

StructuredBuffer<PS> Src : register(t0);
RWStructuredBuffer<PS> Dst : register(u0);

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= PSTATE_TOTAL) return;
    Dst[tid.x] = Src[tid.x];
}
