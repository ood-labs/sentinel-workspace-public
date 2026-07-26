// Publish the accepted-onset ring and the PLL's beat ring as one typed 2A1
// `Hits` contract, so the scoring harness stays detector-agnostic.
//
// Slots 0..511 are the picker's onsets (lanes 0..2), 512..1023 the beat clock's
// beats (lane 3). Merging here rather than letting the PLL append into the
// picker's ring is deliberate: two passes writing one buffer are ping-ponged
// onto separate physical sides, and the beats were silently discarded every
// cook. Each ring keeps its own serial sequence, so consumers must key records
// by (lane_id, onset_serial) rather than by serial alone.
#include "common.hlsli"

struct Hit { uint lane_id, onset_serial, hop_index, sample_position; };

StructuredBuffer<PS> Src : register(t0);   // pstate: header + onset hits ring
StructuredBuffer<PS> Bts : register(t1);   // beats: beat ring + state header
RWStructuredBuffer<Hit> Dst : register(u0);

static const uint BRING = 512u;

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint i = tid.x;
    if (i >= HITCAP + BRING) return;

    // Branch rather than a ternary: HLSL will not fold a conditional between
    // reads of two different StructuredBuffers into one value (X3020).
    PS r;
    if (i < HITCAP) r = Src[HITS_BASE + i];
    else            r = Bts[i - HITCAP];

    Hit h;
    h.lane_id         = (uint)max(r.a, 0.0);
    h.onset_serial    = (uint)max(r.b, 0.0);
    h.hop_index       = (uint)max(r.c, 0.0);
    h.sample_position = (uint)max(r.d, 0.0);
    Dst[i] = h;
}
