// How much of each narrow beam's light the haze between its lens and a point takes out: a cloud near a mover
// dims everything beyond it, which is half of why a beam through a hazer's puff reads uneven. One group per beam
// (the movers, then the narrow guests, as volume.hlsl stages them), 64 segments down its reach: each thread the
// haze across its own segment, then a prefix sum. BT[row * 64 + i] = Haze x the haze integrated from the lens to
// the end of segment i. Zero everywhere when no field is linked (the even haze never dimmed a beam).
#include "../_shared/ss_fixture.hlsli"
StructuredBuffer<SsOptical> Sources : register(t0);
#define HF_TEX _Tex1
#include "haze_field.hlsli"
StructuredBuffer<float4> Venue : register(t2);
RWStructuredBuffer<float> BT : register(u0);
#define VM SS_MOVERS
#define V_GUEST_SRC (2 * SS_MOVERS + 2 * SS_STROBES)
groupshared float gsT[64];

[numthreads(64, 1, 1)]
void main(uint3 gid : SV_GroupID, uint gi : SV_GroupIndex)
{
    uint row = gid.x;
    SsOptical b = Sources[row < VM ? row * 2u : V_GUEST_SRC + (row - VM)];
    uint vn, vs;
    Venue.GetDimensions(vn, vs);
    hzBegin(hzVenueDomain(vn, vn > 4u ? Venue[3] : 0, vn > 4u ? Venue[4] : 0));
    float seg = max(b.reach, 0.0) / 64.0;
    gsT[gi] = (b.active > 0.5 && gHzOn) ? haze * hzDen(b.position + b.normal * (((float)gi + 0.5) * seg)) * seg : 0.0;
    GroupMemoryBarrierWithGroupSync();
    [unroll] for (uint o = 1u; o < 64u; o <<= 1)
    {
        float v = gi >= o ? gsT[gi - o] : 0.0;
        GroupMemoryBarrierWithGroupSync();
        gsT[gi] += v;
        GroupMemoryBarrierWithGroupSync();
    }
    BT[row * 64u + gi] = gsT[gi];
}
