// TP_School / trail.hlsl — record where each fish actually went, for this node's own preview.
//
// TP_Scope keeps a ring of its own for the overlay it draws. This is a SECOND, private one, and
// the duplication is deliberate rather than an oversight: sharing would mean publishing not just
// the samples but the ring HEAD, because a ring is meaningless without knowing where its newest
// sample sits — and the two nodes cook independently, so a shared head is a cross-node ordering
// problem for sixteen kilobytes of saving. Each node recording what it itself draws has no
// ordering to get wrong.
#include "school.hlsli"

RWStructuredBuffer<float4> Trail : register(u0);
StructuredBuffer<TpSCtl>   Ctl   : register(t1);
StructuredBuffer<TpFish>   Fish  : register(t2);

[numthreads(16, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID, uint3 gtid : SV_GroupThreadID)
{
    uint i = gtid.x;
    if (i >= TP_FISH_MAX) return;

    TpFish f = Fish[i];
    TpSCtl st = Ctl[0];

    uint head = (uint)max(st.b.x, 0.0) % TP_TRAIL;

    // The head only advances when ctl says the interval elapsed; on every other cook this
    // overwrites the head slot with the newer position, so the leading segment stays live
    // instead of stepping forward one interval at a time.
    Trail[i * TP_TRAIL + head] = float4(f.pos, f.active > 0.5 ? st.a.y : -1.0);
}
