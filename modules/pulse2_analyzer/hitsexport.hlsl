// Publish the accepted-onset ring as the typed 2A1 `Hits` contract, so the
// scoring harness is detector-agnostic.
#include "common.hlsli"

struct Hit { uint lane_id, onset_serial, hop_index, sample_position; };

StructuredBuffer<PS> Src : register(t0);
RWStructuredBuffer<Hit> Dst : register(u0);

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint i = tid.x;
    if (i >= HITCAP) return;

    PS r = Src[HITS_BASE + i];
    Hit h;
    h.lane_id         = (uint)max(r.a, 0.0);
    h.onset_serial    = (uint)max(r.b, 0.0);
    h.hop_index       = (uint)max(r.c, 0.0);
    h.sample_position = (uint)max(r.d, 0.0);
    Dst[i] = h;
}
