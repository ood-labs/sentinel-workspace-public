// TP_Plan / layout.hlsli — ONE definition of where the drawing lives on the canvas.
//
// Included by both canvas.hlsl (which draws) and plan.hlsl (which hit-tests). If these two
// derived their rectangles independently they would disagree, and a disagreement between the
// picture and the pick reads exactly like a maths bug in the record coordinates.
//
// THE PROJECTION: plan over section, sharing the x axis and sharing one scale.
//
//   plan strip     world (x, z) seen from above. z runs DOWN the page, so the viewer stands at
//                  the bottom edge — the draughtsman's convention. Owns source PLACEMENT.
//   section strip  world (x, y) cut through the tank. Owns DEPTH, the waterline, the freeboard,
//                  and the measured wave envelope. Owns the FAILURE MODE.
//
// A plan alone cannot show whether the waves clear the rim, and clearing the rim is what
// "this arrangement is broken" means for a tank of water. That is why there are two strips.
#ifndef TP_LAYOUT_HLSLI
#define TP_LAYOUT_HLSLI

#include "../_shared/tessera.hlsli"

#define TP_TITLE_B 0.072
#define TP_PLAN_T  0.088
#define TP_PLAN_B  0.612
#define TP_SEC_T   0.642
#define TP_SEC_B   0.902
#define TP_STAT_T  0.918

#define TP_DRAW_L  0.026
#define TP_DRAW_R  0.678
#define TP_COL_L   0.700
#define TP_COL_R   0.982

struct TpLayout
{
    float2 res;
    float  scale;        // pixels per world unit, SHARED by both strips
    float2 planC;        // pixel centre of the plan strip
    float2 secC;         // pixel centre of the section strip
    float3 outer;        // outer half extents: (hx+t, (depth+free+t)/2, hz+t)
    float  yMid;         // world y at the vertical centre of the section box
};

TpLayout tpLayout(float2 res, TpRec tank)
{
    TpLayout L;
    L.res = res;

    float3 h = tpTankHalf(tank);
    float  t = tpTankThick(tank);
    float  fb = tpTankFree(tank);

    float ox = h.x + t;
    float oz = h.z + t;
    float totalY = h.y + fb + t;                 // floor slab underside to glass rim
    L.outer = float3(ox, totalY * 0.5, oz);
    L.yMid = fb - totalY * 0.5;                  // world y of the section box centre

    float availW = (TP_DRAW_R - TP_DRAW_L) * res.x;
    float planH  = (TP_PLAN_B - TP_PLAN_T) * res.y;
    float secH   = (TP_SEC_B - TP_SEC_T) * res.y;

    L.scale = min(min(availW / (2.0 * ox), planH / (2.0 * oz)), secH / totalY) * 0.90;

    float cx = (TP_DRAW_L + TP_DRAW_R) * 0.5 * res.x;
    L.planC = float2(cx, (TP_PLAN_T + TP_PLAN_B) * 0.5 * res.y);
    L.secC  = float2(cx, (TP_SEC_T + TP_SEC_B) * 0.5 * res.y);
    return L;
}

// --- plan strip: world xz <-> pixels
float2 tpPlanToPx(TpLayout L, float2 wxz) { return L.planC + float2(wxz.x, wxz.y) * L.scale; }
float2 tpPxToPlan(TpLayout L, float2 px)  { return (px - L.planC) / L.scale; }

// --- section strip: world xy <-> pixels (world y is up, pixel y is down)
float2 tpSecToPx(TpLayout L, float2 wxy) { return L.secC + float2(wxy.x, -(wxy.y - L.yMid)) * L.scale; }
float2 tpPxToSec(TpLayout L, float2 px)  { return float2((px.x - L.secC.x) / L.scale, L.yMid - (px.y - L.secC.y) / L.scale); }

bool tpInPlanStrip(TpLayout L, float2 px)
{
    return px.y >= TP_PLAN_T * L.res.y && px.y <= TP_PLAN_B * L.res.y
        && px.x >= TP_DRAW_L * L.res.x && px.x <= TP_DRAW_R * L.res.x;
}

// The pick radius a source presents on the canvas, in world units. Derived from the drawn
// ring so the target is exactly what the eye sees, and floored in PIXELS so a tiny source
// stays grabbable at any canvas size.
float tpSrcPickRadius(TpLayout L, TpRec s, TpRec tank)
{
    float drawn = max(s.dims.x, 0.02) * max(tank.dims.x, 0.2);
    return max(drawn, 11.0 / L.scale);
}

#endif // TP_LAYOUT_HLSLI
