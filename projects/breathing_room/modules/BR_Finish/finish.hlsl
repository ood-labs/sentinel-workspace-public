// BR_Finish / finish.hlsl -- the material authority. One thread per cook.
//
// Publishes the 24 material slots every geometry record names by id (br_records.hlsli), built
// from the Properties finish schedule over the house defaults in br_shade.hlsli. Colours are
// authored sRGB and stored linear. Record 31 is the board's editor header: the selected slot,
// which the renderer's Scope view uses to show where a finish is used in the room.
#include "../_shared/br_shade.hlsli"
#include "finish_layout.hlsli"

RWStructuredBuffer<BRRec> Finish : register(u0);

#define FINISH_ED FINISH_EDITOR

float3 lin(float3 srgb) { return brSrgbToLinear(srgb); }

BRMat slotMat(int i)
{
    BRMat m = brDefaultMat(i);
    float ts = texture_scale;
    m.scale *= ts;
    if (i == MAT_FLOOR)      { m.base = lin(floor_tone); m.second = lin(floor_grain); m.rough = floor_rough; m.coat = floor_varnish; }
    else if (i == MAT_WALL)  { m.base = lin(wall_paint); m.second = lin(wall_paint * 0.93); m.rough = wall_rough; }
    else if (i == MAT_CEILING) { m.base = lin(ceiling_paint); m.second = lin(ceiling_paint * 0.95); }
    else if (i == MAT_TRIM || i == MAT_DOOR) { m.base = lin(trim_paint); m.second = lin(trim_paint * 0.95); m.rough = trim_rough; }
    else if (i == MAT_WINDOW) { m.base = lin(window_paint); m.second = lin(window_paint * 0.95); m.rough = trim_rough; }
    else if (i == MAT_STONE) { m.base = lin(stone_base); m.second = lin(stone_vein); }
    else if (i == MAT_IRON)  { m.base = lin(radiator_paint); m.second = lin(radiator_paint * 0.82); }
    else if (i == MAT_SHEER) { m.base = lin(sheer_colour); m.second = lin(sheer_colour * 0.94); m.trans = sheer_trans; }
    else if (i == MAT_LINEN) { m.base = lin(linen_colour); m.second = lin(linen_colour * 0.84); }
    else if (i == MAT_LEATHER) { m.base = lin(leather_colour); m.second = lin(leather_colour * 0.55); }
    else if (i == MAT_WALNUT) { m.base = lin(walnut_colour); m.second = lin(walnut_colour * 0.48); }
    else if (i == MAT_BRASS) { m.base = lin(brass_colour); m.second = lin(brass_colour * float3(0.55, 0.52, 0.42)); m.rough = brass_rough; }
    else if (i == MAT_CERAMIC) { m.base = lin(glaze_colour); m.second = lin(glaze_colour * 0.66); }
    else if (i == MAT_VELVET) { m.base = lin(velvet_colour); m.second = lin(velvet_colour * 0.62); }
    else if (i == MAT_LEAF) { m.base = lin(leaf_colour); m.second = lin(leaf_colour * float3(1.4, 1.25, 1.0)); }
    else if (i == MAT_TERRACOTTA) { m.base = lin(terracotta_colour); m.second = lin(terracotta_colour * 0.82); }
    else if (i == MAT_SHADE) { m.base = lin(shade_colour); m.second = lin(shade_colour * 0.92); }
    else if (i == MAT_MARBLE) { m.base = lin(travertine_colour); m.second = lin(travertine_colour * float3(0.74, 0.68, 0.60)); }
    return m;
}

float sane(float v) { return (abs(v) < 1e5) ? v : 0.0; }

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    float2 res = (_Resolution.x >= 64.0) ? _Resolution.xy : float2(1280.0, 860.0);
    BRRec ed = Finish[FINISH_ED];
    bool fresh = !(abs(ed.head.x - ROLE_FINISH_ED) < 0.5);
    int sel = fresh ? -1 : (int)round(sane(ed.dims.x));
    uint lastSeq = fresh ? 0u : asuint(ed.meta.x);

    FinishLayout L = finishLayout(res);
    uint n = _ViewportEventCount;
    uint ringMax = 0u;
    [loop] for (uint ri = 0u; ri < n; ri++) ringMax = max(ringMax, _ViewportEvents[ri].sequence);
    if (n > 0u && ringMax < lastSeq) lastSeq = 0u;
    uint newLast = lastSeq;
    [loop] for (uint ei = 0u; ei < n; ei++)
    {
        ViewportEvent ev = _ViewportEvents[ei];
        bool isFresh = ev.sequence > lastSeq || (lastSeq - ev.sequence) > (1u << 20);
        if (isFresh)                                // one exit per event (no mid-body `continue`)
        {
            newLast = (ev.sequence > lastSeq) ? max(newLast, ev.sequence) : ev.sequence;
            if (ev.type == 2u && ev.code == 0u && ev.phase == 1u)
            {
                int c = finishCellAt(L, ev.position * res);
                sel = (c == sel) ? sel : c;
            }
            else if (ev.type == 4u && ev.phase == 1u && ev.code == 48u) sel = -1;    // Escape
        }
    }

    [loop] for (int i = 0; i < FINISH_RECORDS; i++)
    {
        if (i == FINISH_ED) {}
        else if (i < MAT_SLOTS) Finish[i] = brMatToRec(slotMat(i));
        else { BRRec z; z.head = 0; z.dims = 0; z.look = 0; z.meta = 0; Finish[i] = z; }
    }
    ed.head = float4(ROLE_FINISH_ED, MAT_SLOTS, 0, 0);
    ed.dims = float4(sel, 0, 0, 0);
    ed.look = 0;
    ed.meta = float4(asfloat(newLast), res, 0);
    Finish[FINISH_ED] = ed;
}
