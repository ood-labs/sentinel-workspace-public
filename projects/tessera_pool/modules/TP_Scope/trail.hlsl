// TP_Scope / trail.hlsl — record where each fish actually went.
//
// One thread per fish, writing the CURRENT position into that fish's ring slot. This is the only
// place in the node that stores anything, and it exists so the trail is recorded history rather
// than a curve fitted to a heading after the fact — a fitted curve would show where the fish
// SHOULD have been, which is precisely the claim an instrument view must not make.
//
// The head only advances when tick.hlsl says the interval elapsed; on every other cook this
// overwrites the head slot with the newer position, so the most recent segment stays live
// instead of stuttering forward one interval at a time.
#include "scope.hlsli"

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
    uint slot = i * TP_TRAIL + head;

    // w carries the cook time the sample was taken at, so the resolve can age a trail by real
    // seconds rather than by ring index — the two differ whenever the frame rate does.
    Trail[slot] = float4(f.pos, f.active > 0.5 ? st.a.y : -1.0);
}
