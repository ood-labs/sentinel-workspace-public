// VT_Plan / pick.hlsli — the one hit test. plan.hlsl selects and drags with it; layout.hlsl
// hovers and inspects with it, so what the canvas lights is exactly what a click would take.
// The including pass declares `Plan` (RW in plan.hlsl, read-only in layout.hlsl) first.
#ifndef VT_PICK_HLSLI
#define VT_PICK_HLSLI

// Nearest pickable record under a stage-space point. Smallest hit wins so a dash sitting on a
// big plate stays reachable; masses and strokes win inside their core disc.
uint pickRecord(float2 p)
{
    uint best = 0u; float bestScore = 1e9;
    for (uint m = 0u; m < PLAN_MASSES; m++)
    {
        PlanRec r = Plan[PLAN_MASS_0 + m];
        if (r.active < 0.5) continue;
        float d = length(p - r.pos);
        if (d < r.size.x * 0.55 && d < bestScore) { bestScore = d; best = PLAN_MASS_0 + m + 1u; }
    }
    if (best != 0u) return best;
    for (uint st = 0u; st < PLAN_STROKES; st++)
    {
        PlanRec r = Plan[PLAN_STROKE_0 + st];
        if (r.active < 0.5) continue;
        float d = length((p - r.pos) / max(r.size, 0.01));
        if (d < 1.0 && d < bestScore) { bestScore = d; best = PLAN_STROKE_0 + st + 1u; }
    }
    if (best != 0u) return best;
    for (uint i = 0u; i < PLAN_PLATES; i++)
    {
        PlanRec r = Plan[PLAN_PLATE_0 + i];
        if (r.active < 0.5) continue;
        float2 q = abs(p - r.pos) - r.size - 0.006;
        if (max(q.x, q.y) < 0.0)
        {
            float area = r.size.x * r.size.y;
            if (area < bestScore) { bestScore = area; best = PLAN_PLATE_0 + i + 1u; }
        }
    }
    return best;
}

#endif
