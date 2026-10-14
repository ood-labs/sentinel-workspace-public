// World-space bounding box of every rig record at its home pose: the union of the type's body parts
// (from the FixtureRender port) through the record's mount transform.
// The plot draws these, so a symbol is the fixture's true footprint at any rotation. A placeholder is a
// 0.4 m cube hanging below its mount, or standing on it on the deck.
#define GDTF_RENDER _Data1
#include "../_shared/fe_tables.hlsli"
#include "../_shared/fe_rig.hlsli"

StructuredBuffer<FeInst> RigIn : register(t0);
RWStructuredBuffer<float4> Bounds : register(u0);   // [2i] = (min xyz, active), [2i+1] = (max xyz, 0)

[numthreads(64, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint i = id.x;
    if (i >= FE_N_MAX) return;
    FeInst r = RigIn[i];
    float3 lo = 1e9, hi = -1e9;
    bool active = (r.flags & FE_INST_ACTIVE) != 0u && r.type < feTypeCount();
    if (active && (r.flags & FE_INST_PLACEHOLDER) != 0u)
    {
        float3 c = r.position + float3(0.0, (r.flags & FE_INST_FLOOR) != 0u ? 0.2 : -0.2, 0.0);
        lo = c - 0.2;
        hi = c + 0.2;
    }
    else if (active)
    {
        uint4 g = FE_TYPE_GEO_AT(r.type);
        for (uint p = 0u; p < g.y; p++)
        {
            float4 a = FE_PART_G_AT((g.x + p) * 3u);
            float3 c = FE_PART_G_AT((g.x + p) * 3u + 1u).xyz;
            float4 s = FE_PART_G_AT((g.x + p) * 3u + 2u);
            float3 ext = (a.x == 2.0)
                ? (s.w == 0.0 ? float3(s.y * 0.5, s.x, s.x) : (s.w == 1.0 ? float3(s.x, s.y * 0.5, s.x) : float3(s.x, s.x, s.y * 0.5)))
                : s.xyz * 0.5;
            for (uint k = 0u; k < 8u; k++)
            {
                float3 corner = c + ext * float3((k & 1u) ? 1.0 : -1.0, (k & 2u) ? 1.0 : -1.0, (k & 4u) ? 1.0 : -1.0);
                float3 w = feWorldPoint(r, corner);
                lo = min(lo, w);
                hi = max(hi, w);
            }
        }
    }
    Bounds[i * 2u] = float4(lo, active ? 1.0 : 0.0);
    Bounds[i * 2u + 1u] = float4(hi, 0.0);
}
