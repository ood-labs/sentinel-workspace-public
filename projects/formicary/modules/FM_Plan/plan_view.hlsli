// FM_Plan / plan_view.hlsli — the canvas's plates and chrome bands, and the hover pick.
//
// The plan strip and the flow strip are NOT defined here: they stay layout.hlsli's, because
// plan.hlsl hit-tests the plan strip through exactly those fractions. This file names the
// rectangles the drawing (canvas.hlsl) and the type (layout.hlsl) share around them - every one a
// fraction of the live extent, so the canvas follows its panel - and carries the hover pick.
//
// Include after layout.hlsli, il_core.hlsli and the `Plan` buffer declaration.
#ifndef FM_PLAN_VIEW_HLSLI
#define FM_PLAN_VIEW_HLSLI

// The kit's UI scale (1.0 at 1280 x 720), floored so a caption never renders under 9 px.
float fmS(float2 R) { return max(ilCtx(R).s, 0.86); }

float4 fmPlanRect(float2 R) { return float4(FM_DRAW_L * R.x, FM_PLAN_T * R.y, FM_DRAW_R * R.x, FM_PLAN_B * R.y); }
float4 fmFlowRect(float2 R) { return float4(FM_DRAW_L * R.x, FM_FLOW_T * R.y, FM_DRAW_R * R.x, FM_FLOW_B * R.y); }
float4 fmColRect(float2 R)  { return float4(FM_COL_L * R.x, FM_PLAN_T * R.y, FM_COL_R * R.x, FM_FLOW_B * R.y); }
float4 fmHeadRect(float2 R) { return float4(FM_DRAW_L * R.x, 0.0, FM_COL_R * R.x, FM_PLAN_T * R.y); }
float4 fmFootRect(float2 R) { return float4(FM_DRAW_L * R.x, FM_FLOW_B * R.y, FM_COL_R * R.x, R.y); }

// The pointer in canvas pixels, or (-1, -1) when it is outside the canvas (hover is never stored).
float2 fmPointer(float2 R)
{
    float2 n = _ViewportPointerPosition;
    return (all(n >= 0.0) && all(n <= 1.0)) ? n * R : float2(-1.0, -1.0);
}

// What a click at world point w would select: plan.hlsl's pickRecord(), rule for rule - the same
// order, the same radii from layout.hlsli, smallest hit wins - so hover lights exactly the record a
// click there would select. plan.hlsl is the interaction pass and keeps its own copy (it must not
// change); if its rules ever change, change these with them. Returns slot + 1, 0 for nothing.
uint fmHoverPick(float2 w, FmLayout L, FmRec arena)
{
    uint best = 0u;
    float bestR = 1e9;
    {
        FmRec r = Plan[FM_NEST];
        float rad = fmPickRadius(L, max(r.dims.x, 1.0));
        if (r.active > 0.5 && length(w - fmRecWorld(r, arena)) < rad * 1.4 && rad < bestR) { bestR = rad; best = FM_NEST + 1u; }
    }
    for (uint c = 0u; c < FM_CACHES; c++)
    {
        FmRec r = Plan[FM_CACHE_0 + c];
        if (r.active < 0.5) continue;
        float rad = fmPickRadius(L, max(r.dims.x, 0.6));
        if (length(w - fmRecWorld(r, arena)) < rad * 1.5 && rad < bestR) { bestR = rad; best = FM_CACHE_0 + c + 1u; }
    }
    for (uint o = 0u; o < FM_OBSTS; o++)
    {
        FmRec r = Plan[FM_OBST_0 + o];
        if (r.active < 0.5) continue;
        float d = fmObstDist(w, r, arena);
        float rad = max(r.dims.z, 1.0);
        if (d < 12.0 / max(L.scale, 1e-4) && rad < bestR) { bestR = rad; best = FM_OBST_0 + o + 1u; }
    }
    for (uint s = 0u; s < FM_STAS; s++)
    {
        FmRec r = Plan[FM_STA_0 + s];
        if (r.active < 0.5) continue;
        float rad = fmPickRadius(L, 2.2);
        if (length(w - fmRecWorld(r, arena)) < rad && rad < bestR) { bestR = rad; best = FM_STA_0 + s + 1u; }
    }
    for (uint e = 0u; e < FM_EDGES; e++)
    {
        FmRec r = Plan[FM_EDGE_0 + e];
        if (r.active < 0.5) continue;
        float2 a = fmRecWorld(Plan[(uint)r.p0], arena);
        float2 b = fmRecWorld(Plan[(uint)r.p1], arena);
        float2 h = fmEdgeHandle(a, b, float2(r.dims.x, r.dims.z));
        float rad = 11.0 / max(L.scale, 1e-4);
        if (length(w - h) < rad && rad < bestR) { bestR = rad; best = FM_EDGE_0 + e + 1u; }
    }
    return best;
}

// The flow strip's lane under a pixel: the active-edge ordinal the strip stacks its lanes in, and
// the edge slot it belongs to (FM_EDGES for none). The flow strip is a readout - plan.hlsl never
// tests it - so pointing at a lane inspects its route without selecting anything.
uint fmFlowLaneAt(FmLayout L, float2 px, uint lanes, out uint slot)
{
    slot = FM_EDGES;
    float4 fr = float4(FM_DRAW_L * L.res.x, FM_FLOW_T * L.res.y, FM_DRAW_R * L.res.x, FM_FLOW_B * L.res.y);
    if (!ilIn(px, fr)) return 0xFFFFu;
    float k = floor((px.y - L.flowO.y) / max(L.laneH, 1.0));
    if (k < 0.0 || k >= (float)lanes) return 0xFFFFu;
    uint want = (uint)k, ord = 0u;
    for (uint e = 0u; e < FM_EDGES; e++)
    {
        if (Plan[FM_EDGE_0 + e].active < 0.5) continue;
        if (ord == want) { slot = e; return want; }
        ord++;
    }
    return 0xFFFFu;
}

#endif
