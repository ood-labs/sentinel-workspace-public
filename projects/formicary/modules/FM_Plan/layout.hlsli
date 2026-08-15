// FM_Plan / layout.hlsli — ONE definition of where the drawing lives on the canvas.
//
// Included by canvas.hlsl (which draws) and plan.hlsl (which hit-tests). If the two derived
// their rectangles independently they would disagree, and a disagreement between the picture
// and the pick reads exactly like a maths bug in the record coordinates rather than what it is.
//
// ---------------------------------------------------------------------------
// THE PROJECTION: plan over route diagram.
//
//   plan strip   the arena footprint from above. World x across, world z DOWN the page, so the
//                viewer stands at the bottom edge — the draughtsman's convention, and the same
//                way round as the camera looks at it. Owns PLACEMENT.
//
//   flow strip   one horizontal lane per trail edge, laid out by ROUTE DISTANCE FROM THE NEST.
//                Owns COST. This is the strip that earns its place.
//
// Why a second strip at all. The program image is itself a top-down view, so a plan strip on
// its own would be a small grey copy of the render — the exact failure the scaffold rule warns
// about. What a plan genuinely cannot show is that two caches which look equidistant are not:
// a route bent around a twig is longer to walk than the straight line it replaced, and how much
// longer is the single number that decides where a colony sends its foragers. The flow strip
// draws each route at its true walked length against the same millimetre ruler, so a detour is
// visible as horizontal extent rather than inferred.
//
// It also carries the two live readings and the failure mode:
//   - measured traffic, fed back from FM_Colony, drawn as a fill inside the planned lane;
//   - a lane drawn in ALARM RED when its route passes through an obstacle or leaves the arena,
//     with a tick at the offending distance, so "this arrangement is broken" is a thing you see
//     in the diagram instead of discovering later as ants walking through a stone.
// ---------------------------------------------------------------------------
#ifndef FM_LAYOUT_HLSLI
#define FM_LAYOUT_HLSLI

#include "../_shared/formic.hlsli"

#define FM_TITLE_B 0.056
#define FM_PLAN_T  0.074
#define FM_PLAN_B  0.700
#define FM_FLOW_T  0.726
#define FM_FLOW_B  0.900
#define FM_STAT_T  0.916

#define FM_DRAW_L  0.022
#define FM_DRAW_R  0.752
#define FM_COL_L   0.770
#define FM_COL_R   0.984

struct FmLayout
{
    float2 res;
    float  scale;      // PIXELS PER MILLIMETRE in the plan strip
    float2 planC;      // pixel centre of the plan strip
    float2 planAxis;   // page direction of world +x and +z. See fmPlanAxis below.
    float  flowScale;  // pixels per millimetre along the flow strip's distance axis
    float2 flowO;      // pixel origin of the flow strip: x at route distance 0, y at lane 0 top
    float  laneH;      // pixel height of one lane
    float2 half;       // arena half extents, mm
};

// ---------------------------------------------------------------------------
// WHICH WAY ROUND THE PAGE GOES. This was wrong, and wrong in the one way that is hard to
// see: the plan was a MIRROR of the arena rather than a rotation of it.
//
// Measured, not reasoned. With the colony frozen and the camera put straight overhead, the
// twenty-four ant records read back from the data port land on the captured frame at
//
//     screen right = world +x        screen up = world +z
//
// to within a pixel on every one of them. So a true overhead view of this arena has +z going
// UP the page. The plan drew +z DOWN the page with +x still to the right, which is not any
// view of the arena from anywhere: it is the overhead view reflected. Every route curve,
// every obstacle yaw and every chevron therefore had the wrong handedness, on top of the
// left-right swap that is the part you actually notice.
//
// A plan may be rotated freely and must never be reflected. Both options below are rigid
// half-turns of the measured overhead view, so the drawing is a real plan either way:
//
//   Camera Side  page right = -x, page down = +z. The half-turn that puts the viewer at the
//                BOTTOM edge for a camera standing on the +z side of the arena, which is
//                where the shipped camera stands (pos z = +100, looking back toward -z).
//                Sentinel's camera basis is left-handed: right = (cos yaw, 0, -sin yaw), so a
//                camera at +z looking -z genuinely does put world +x on the LEFT of frame.
//
//   Far Side     page right = +x, page down = -z. The measured overhead view unrotated, which
//                is the one that matches a camera flown around to the -z side.
//
// Fly the camera across the arena and switch this; leave it alone and the default is right.
float2 fmPlanAxis()
{
    return (((int)plan_facing) == 0) ? float2(-1.0, 1.0) : float2(1.0, -1.0);
}

FmLayout fmLayout(float2 res, FmRec arena, float maxRoute, uint laneCount)
{
    FmLayout L;
    L.res = res;
    L.half = fmArenaHalf(arena);

    float availW = (FM_DRAW_R - FM_DRAW_L) * res.x;
    float planH  = (FM_PLAN_B - FM_PLAN_T) * res.y;
    float flowH  = (FM_FLOW_B - FM_FLOW_T) * res.y;

    L.scale = min(availW / (2.0 * L.half.x), planH / (2.0 * L.half.y)) * 0.92;

    float cx = (FM_DRAW_L + FM_DRAW_R) * 0.5 * res.x;
    L.planC = float2(cx, (FM_PLAN_T + FM_PLAN_B) * 0.5 * res.y);
    L.planAxis = fmPlanAxis();

    // The flow strip SHARES the plan's millimetre ruler wherever it fits, so a route lane can
    // be compared to the arena above it by eye. It only shrinks when a bent route runs longer
    // than the arena is wide, and the readout column says so when it does.
    float flowW = availW * 0.86;
    L.flowScale = min(L.scale, flowW / max(maxRoute, 1.0));

    // The lane block is CENTRED in the flow band rather than stacked from the top. With one
    // route — which is the reference, and the most common case — a top-stacked block leaves
    // three quarters of the strip as dead canvas, and dead canvas in an instrument reads as a
    // panel that failed to draw rather than as a diagram with one lane in it.
    uint lanes = max(laneCount, 1u);
    L.laneH = min(flowH / (float)lanes, 26.0);
    float blockH = L.laneH * (float)lanes;
    L.flowO = float2(FM_DRAW_L * res.x + 46.0,
                     FM_FLOW_T * res.y + (flowH - blockH) * 0.5);
    return L;
}

// The vertical extent the lane block actually occupies. The ruler, the frame and the caption
// all derive from this so none of them draws across empty band.
float2 fmFlowBlockY(FmLayout L, uint lanes) { return float2(L.flowO.y, L.flowO.y + L.laneH * (float)max(lanes, 1u)); }

// --- plan strip: world (x, z) millimetres <-> pixels, through the page axes above. Both
// directions go through planAxis, whose components are exactly +/-1, so the round trip is
// exact and the pick can never disagree with the picture.
float2 fmPlanToPx(FmLayout L, float2 wxz) { return L.planC + wxz * L.planAxis * L.scale; }
float2 fmPxToPlan(FmLayout L, float2 px)  { return (px - L.planC) / L.scale * L.planAxis; }

// A world-space axis-aligned box maps to a pixel box whose corners SWAP when the page axis is
// negative. Anything that draws a frame or tests a rectangle wants it sorted.
void fmPlanBoxPx(FmLayout L, float2 wLo, float2 wHi, out float2 pLo, out float2 pHi)
{
    float2 a = fmPlanToPx(L, wLo), b = fmPlanToPx(L, wHi);
    pLo = min(a, b); pHi = max(a, b);
}

// --- flow strip: (route distance mm, lane index) -> pixels
float2 fmFlowToPx(FmLayout L, float dist, uint lane)
{
    return float2(L.flowO.x + dist * L.flowScale, L.flowO.y + ((float)lane + 0.5) * L.laneH);
}

bool fmInPlanStrip(FmLayout L, float2 px)
{
    return px.y >= FM_PLAN_T * L.res.y && px.y <= FM_PLAN_B * L.res.y
        && px.x >= FM_DRAW_L * L.res.x && px.x <= FM_DRAW_R * L.res.x;
}

// The pick radius a record presents on the canvas, in WORLD millimetres. Derived from the ring
// the canvas actually draws, so the target is exactly what the eye sees, and floored in PIXELS
// so a 1 mm cache stays grabbable however the canvas is scaled.
float fmPickRadius(FmLayout L, float drawnMm)
{
    return max(drawnMm, 12.0 / max(L.scale, 1e-4));
}

// Where an edge's mid handle sits, in world mm. Dragging this is how a route is bent by hand,
// so the canvas and the hit test must agree on it exactly — hence one definition here rather
// than a constant repeated in two files.
float2 fmEdgeHandle(float2 a, float2 b, float2 ctrl) { return fmRoutePoint(a, b, ctrl, 0.5); }

#endif // FM_LAYOUT_HLSLI
