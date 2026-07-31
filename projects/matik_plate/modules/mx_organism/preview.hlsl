// mx_organism / preview.hlsl — front elevation of the node field this module publishes.
//
// Shows what actually matters when judging growth: where the trees are, how the bonds
// connect, how radius decays with depth, which nodes are terminal buds, how far the growth
// reveal has travelled, and how deep in Z each node sits. Same world->screen mapping as
// grow.hlsl uses in reverse, so a node here is that node.
#include "../_shared/plate.hlsli"
#include "../_shared/microfont.hlsli"

struct MolNode
{
    float3 pos; float radius; float parent; float xlink;
    float cluster; float depth; float seed; float phase; float kind; float active;
};

StructuredBuffer<MolNode> Nodes : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

#define NODE_CAP 320u

static const float3 CLUSTER_TINT[8] = {
    float3(0.95, 0.97, 1.00), float3(0.46, 0.80, 0.95), float3(0.55, 0.92, 0.80),
    float3(0.95, 0.72, 0.40), float3(0.78, 0.62, 0.95), float3(0.95, 0.55, 0.60),
    float3(0.62, 0.95, 0.55), float3(0.85, 0.85, 0.55)
};

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)px + 0.5) / _Resolution.xy;

    // inverse of plateToWorld: world [-1,1] fills the frame
    float2 w = float2(uv.x * 2.0 - 1.0, -(uv.y * 2.0 - 1.0));
    float pxw = 2.0 / _Resolution.x;

    float3 col = float3(0.028, 0.031, 0.037);
    // plate outline, so growth that escapes the plate is immediately obvious
    col += 0.10 * pStroke(pBox(w, float2(1.0, 1.0)), pxw * 0.8, pxw);

    uint live = 0u;
    float maxDepth = 0.0;

    // bonds under nodes
    for (uint i = 0u; i < NODE_CAP; i++)
    {
        MolNode n = Nodes[i];
        if (n.active < 0.5) continue;
        live++;
        maxDepth = max(maxDepth, n.depth);
        if (n.parent < 0.0) continue;
        MolNode p = Nodes[(uint)n.parent];
        if (p.active < 0.5) continue;
        float d = pSeg(w, n.pos.xy, p.pos.xy);
        float thick = max(min(n.radius, p.radius) * 0.55, pxw);
        float3 tint = CLUSTER_TINT[(uint)n.cluster & 7u];
        // z read out as brightness so the flattened depth is still visible in plan
        float zf = saturate(n.pos.z * 1.6 + 0.5);
        // opaque, not additive: dense clusters must stay countable instead of blowing to white
        col = lerp(col, tint * (0.22 + 0.30 * zf), pFill(d - thick, pxw));
    }

    for (uint j = 0u; j < NODE_CAP; j++)
    {
        MolNode n = Nodes[j];
        if (n.active < 0.5) continue;
        float d = length(w - n.pos.xy) - n.radius;
        float3 tint = CLUSTER_TINT[(uint)n.cluster & 7u];
        float zf = saturate(n.pos.z * 1.6 + 0.5);
        col = lerp(col, tint * (0.09 + 0.15 * zf), pFill(d, pxw));
        // terminal buds get a filled core; junctions stay open rings
        col = lerp(col, tint * (0.60 + 0.40 * zf), pStroke(d, pxw * 0.9, pxw));
        if (n.kind > 1.5) col = lerp(col, tint * 0.55, pFill(length(w - n.pos.xy) - n.radius * 0.34, pxw));
        if (n.depth < 0.5) col = lerp(col, float3(1.0, 1.0, 1.0), pStroke(d - n.radius * 0.35, pxw * 1.2, pxw));
    }

    // live readout: node count and reached depth
    float gh = 0.030, gw = gh * 0.72;
    float hud = 0.0;
    float2 tp = float2(uv.x, uv.y);
    hud = max(hud, mf_text((tp - float2(0.018, 0.020)) / float2(gw * 5.0, gh),
              uint2(mf_pack1(23u, 24u, 13u, 14u, 28u), 0u), 5u));                       // NODES
    hud = max(hud, mf_num((tp - float2(0.135, 0.020)) / float2(gw * 3.0, gh), live, 3u));
    hud = max(hud, mf_text((tp - float2(0.215, 0.020)) / float2(gw * 3.0, gh),
              uint2(mf_pack1(13u, 25u, 29u, 0u, 0u), 0u), 3u));                          // DPT
    hud = max(hud, mf_num((tp - float2(0.288, 0.020)) / float2(gw * 2.0, gh), (uint)maxDepth, 2u));
    col = lerp(col, float3(0.90, 0.93, 0.96), hud);

    OutputUAV[px] = float4(col, 1.0);
}
