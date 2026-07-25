// Copy this cook's region table into the durable state buffer.
//
// Split from the events pass because `regions_prev` is the persistent,
// save/preset/undo-backed buffer: the events pass reads it as an SRV and cannot
// also write it as a UAV in the same dispatch.

#include "types.hlsli"

StructuredBuffer<RG>   Cur  : register(t0);
RWStructuredBuffer<RG> Prev : register(u0);

[numthreads(16, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint i = tid.x;
    if (i > P2_PUB_IDX) return;
    Prev[i] = Cur[i];
}
