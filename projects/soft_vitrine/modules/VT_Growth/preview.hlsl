// VT_Growth / preview.hlsl — the expander's own diagnostic surface, the DRAWING only.
//
// This node publishes two genuinely different record families and both must be inspectable on
// one stage:
//   * masses  — front-projected world nodes as discs with their bonds, in the mass family's
//               identity hue (the plan canvas's), each group a step lighter or darker so
//               clusters stay separable; the material is a value chip at each core (legend in
//               the footer); each group's bounding sphere (the thing the ray-marcher culls
//               against) is dashed.
//   * strokes — stage-space polylines at their real published radius and per-node accent tone.
// A parameter that changes structure must visibly change this picture.
//
// The rects come from growth_view.hlsli (the canvas follows its panel). The words, the counts, the
// group tally, the hover inspector and the verbs are recorded by layout.hlsl and drawn over this
// by the shared UI kit (ui.hlsl). Pixels outside the stage skip the record loops.
//
// Every record is a small mark, but every stage pixel used to test all 768 of them, every frame
// the growth breathes. So each 8x8 group first shortlists the records whose ink can reach it
// (vgNear), in record order, and its pixels walk only that. The reach of each mark is read off the
// drawing below — vt_fill is zero from 0.75 px outside a shape — and the group test adds the
// group's half-diagonal, so nothing a pixel would draw is dropped and the picture is unchanged.
#include "../_shared/vitrine.hlsli"
#include "../_shared/ui/il_core.hlsli"
#include "growth_view.hlsli"

StructuredBuffer<LimbRec> Limbs : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

// material, as the plan canvas draws it: a value ramp (clay, chrome, frost, gloss)
float3 matTint(uint m) { return ptRamp(m == 0u ? 0.15 : (m == 1u ? 1.00 : (m == 2u ? 0.70 : 0.42))); }

groupshared uint gsRec[LIMB_RECORDS];
groupshared uint gsRun[64];

float vgDist(float2 p, float2 a, float2 b)
{
    float2 pa = p - a, ba = b - a;
    float dd = dot(ba, ba);
    return (dd > 0.0) ? length(pa - ba * saturate(dot(pa, ba) / dd)) : length(pa);
}

// Can record `i` put any ink within `m` (uv) of `c`? Each reach is the furthest the matching
// drawing below can be non-zero; radii are floored at 0 so a degenerate record stays covered.
bool vgNear(uint i, float2 c, float px, float m)
{
    LimbRec n = Limbs[i];
    if (n.active < 0.5) return false;
    float2 a, b;
    float reach;
    if (i < LIMB_HEADERS)                                   // dashed bounds ring
    {
        bool isMass = (i < LIMB_STROKE_H_0);
        a = b = isMass ? gvWorldToUV(n.pos) : n.pos.xy;
        reach = max(isMass ? n.radius * 0.5 : n.radius, 0.0) + 1.45 * px;
    }
    else if (i < LIMB_MASS_CAP)                             // mass disc, and its bond
    {
        a = b = gvWorldToUV(n.pos);
        reach = max(n.radius * 0.5, 0.0);
        if (n.parent >= 0.0)
        {
            LimbRec pr = Limbs[(uint)n.parent];
            a = gvWorldToUV(pr.pos);
            reach = max(reach, pr.radius * 0.5 * 0.55);
        }
        reach += 0.75 * px;
    }
    else                                                    // stroke node, its bond or start ring
    {
        a = b = n.pos.xy;
        if (n.parent >= 0.0)
        {
            LimbRec pr = Limbs[(uint)n.parent];
            a = pr.pos.xy;
            reach = max(max(pr.radius, n.radius), 0.0) + 0.75 * px;
        }
        else reach = 1.9 * max(n.radius, 0.0) + 1.35 * px;
    }
    return vgDist(c, a, b) <= reach + m;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID, uint3 Gid : SV_GroupID, uint gi : SV_GroupIndex)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    // No early return: every thread has to reach the group's barriers below.
    bool inImage = DTid.x < W && DTid.y < H;
    float2 P = (float2)DTid.xy + 0.5;
    GVLayout L = gvLayout(float2(W, H));

    // The group's shortlist, in record order: 64 threads x 12 records, counted, then placed by a
    // prefix over the counts. A pixel is never more than 3.5 * sqrt(2) px from its group centre.
    {
        float sideG = gvSide(L);
        float pxG = 1.0 / sideG;
        float2 c = (float2(Gid.xy) * 8.0 + 4.0 - L.stage.xy) / sideG;
        float mG = 5.0 * pxG;
        uint j0 = gi * (LIMB_RECORDS / 64u), j1 = j0 + LIMB_RECORDS / 64u;
        uint mine = 0u;
        for (uint j = j0; j < j1; ++j) if (vgNear(j, c, pxG, mG)) mine++;
        gsRun[gi] = mine;
        GroupMemoryBarrierWithGroupSync();
        uint at = 0u;
        for (uint k = 0u; k < gi; ++k) at += gsRun[k];
        for (uint j2 = j0; j2 < j1; ++j2) if (vgNear(j2, c, pxG, mG)) { gsRec[at] = j2; at++; }
        GroupMemoryBarrierWithGroupSync();
    }
    uint kept = 0u;
    for (uint k2 = 0u; k2 < 64u; ++k2) kept += gsRun[k2];
    if (!inImage) return;

    // the stage and tally plates (layout.hlsl draws their edges, captions and the bars)
    float3 col = IL_FIELD;
    ilOver(col, IL_PANEL, ilFill(ilSdBox(P, L.stage, IL_RADIUS * L.s)));
    ilOver(col, IL_PANEL, ilFill(ilSdBox(P, L.tally, IL_RADIUS * L.s)));
    if (!ilIn(P, L.stage))
    {
        OutputUAV[DTid.xy] = float4(col, 1.0);
        return;
    }

    float side = gvSide(L);
    float2 uv = (P - L.stage.xy) / side;
    float px = 1.0 / side;

    // quarter grid, the centre lines a step stronger
    float2 q = P - L.stage.xy;
    ilOver(col, IL_GRID, max(ilGridLine(q.x, 0.25 * side, 1.0), ilGridLine(q.y, 0.25 * side, 1.0)));
    ilOver(col, IL_EDGE, max(ilGridLine(q.x - 0.5 * side, side, 1.0), ilGridLine(q.y - 0.5 * side, side, 1.0)) * 0.7);

    // The shortlist is in record order, so the three families still draw in turn: the group
    // bounds, then the mass limbs, then the stroke limbs.
    [loop]
    for (uint t = 0u; t < kept; t++)
    {
    uint ri = gsRec[t];
    // ------------------------------------------------------------------ group bounds
    // Drawn first and faintly, dashed: these are the culling spheres, not the geometry.
    if (ri < LIMB_HEADERS)
    {
        uint g = ri;
        LimbRec h = Limbs[g];
        if (h.active < 0.5) continue;
        bool isMass = (g < LIMB_STROKE_H_0);
        float2 c = isMass ? gvWorldToUV(h.pos) : h.pos.xy;
        float r = isMass ? h.radius * 0.5 : h.radius;
        float dr = abs(length(uv - c) - r) - 0.7 * px;
        float dash = step(0.45, frac(atan2(uv.y - c.y, uv.x - c.x) * 5.6));
        col = lerp(col, IL_DIM, vt_fill(dr, px) * 0.55 * dash);
    }

    // ------------------------------------------------------------------ mass limbs
    else if (ri < LIMB_MASS_CAP)
    {
        LimbRec n = Limbs[ri];
        if (n.active < 0.5) continue;

        float2 c = gvWorldToUV(n.pos);
        float r = n.radius * 0.5;                       // world radius -> uv (half-extent = 1.0)
        // the family hue, a value step per group so neighbouring clusters stay separable
        float3 tint = PT_ID_B * lerp(0.70, 1.20, frac(n.group * 0.618034));

        // bond to parent, tapered, so the topology is readable
        if (n.parent >= 0.0)
        {
            LimbRec pr = Limbs[(uint)n.parent];
            float2 pc = gvWorldToUV(pr.pos);
            float db = vt_dTaper(uv, pc, c, pr.radius * 0.5 * 0.55, r * 0.55);
            col = lerp(col, tint * 0.55, vt_fill(db, px));
        }

        float dn = length(uv - c) - r;
        col = lerp(col, tint, vt_fill(dn, px) * 0.85);
        // shallow shade so overlapping nodes stay countable
        col = lerp(col, tint * 1.4, vt_fill(dn + r * 0.55, px) * 0.5);
        col = lerp(col, matTint(((uint)n.material) & 3u), vt_fill(dn + r * 0.82, px) * 0.9);
    }

    // ------------------------------------------------------------------ stroke limbs
    else
    {
        LimbRec n = Limbs[ri];
        if (n.active < 0.5) continue;

        // the point's own accent tone: the near-black one lifted so it reads, then damped
        float3 tint = vt_accent(n.material);
        float lum = dot(tint, float3(0.299, 0.587, 0.114));
        tint = ptSampleColour(lerp(normalize(tint + 0.09) * 0.66, tint, saturate(lum * 3.2)));

        if (n.parent >= 0.0)
        {
            LimbRec pr = Limbs[(uint)n.parent];
            float db = vt_dTaper(uv, pr.pos.xy, n.pos.xy, pr.radius, n.radius);
            col = lerp(col, tint, vt_fill(db, px));
        }
        else
        {
            // run starts get a ring, so it is obvious where a polyline begins
            col = lerp(col, IL_INK,
                       vt_fill(abs(length(uv - n.pos.xy) - n.radius * 1.9) - 0.6 * px, px) * 0.7);
        }
        col = lerp(col, tint, vt_fill(length(uv - n.pos.xy) - n.radius, px) * 0.8);
    }
    }

    OutputUAV[DTid.xy] = float4(col, 1.0);
}
