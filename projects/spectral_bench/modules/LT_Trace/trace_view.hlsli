// LT_Trace / trace_view.hlsli - the scope canvas's rects and its ONE bench <-> pixel mapping.
//
// The art (scope.hlsl), the type (layout.hlsl) and the hover hit test all call tvLayout(), so the
// traced lines, the frame round them and the segment the pointer picks cannot disagree.
//
// THE ART HAS A FIXED PIXEL BUDGET. The scope is a per-pixel scan of the drawn lanes, so it costs
// its pixel count. It renders the bench at no more pixels than the node's own 768 x 432 extent
// always cost, into the top-left corner of its texture, and the layout places that image over the
// bench - 1:1 on a small canvas, upscaled on a big one. A full-screen canvas costs what the node
// preview did, never more.
#ifndef LT_TRACE_VIEW_HLSLI
#define LT_TRACE_VIEW_HLSLI

#include "../_shared/bench.hlsli"

#define TV_ART_BUDGET (768.0 * 432.0)
#define TV_MAX_DRAWN  320u          // lanes the scope draws at most (it decimates beyond that)

struct TvLayout
{
    float2 res;
    float  s;          // integer UI scale
    float4 head;       // title and readout row
    float4 plate;      // the scope plate
    float4 plot;       // the bench, fitted inside the plate, never stretched
    float4 foot;       // the verbs
    float2 org;        // canvas pixel of bench (0, 0)
    float  scale;      // canvas pixels per bench unit
    float  artScale;   // art pixels per bench unit (<= scale)
    float2 art;        // the art's extent in texture pixels, from the texture's top-left corner
};

TvLayout tvLayout(float2 res)
{
    TvLayout L;
    L.res = res;
    L.s = clamp(floor(min(res.x / 760.0, res.y / 420.0)), 1.0, 3.0);
    float s = L.s, pad = 9.0 * s;
    float headH = 25.0 * s, footH = 22.0 * s;
    L.head  = float4(pad, pad, res.x - pad, pad + headH);
    L.foot  = float4(pad, res.y - pad * 0.4 - footH, res.x - pad, res.y - pad * 0.4);
    L.plate = float4(pad, L.head.w + pad, res.x - pad, max(L.foot.y - pad * 0.4, L.head.w + pad + 1.0));

    // inside the plate: a caption row above the bench and the legend row below it
    float inset = 8.0 * s, capH = 24.0 * s, legH = 22.0 * s;
    float2 a0 = float2(L.plate.x + inset, L.plate.y + capH);
    float2 room = max(float2(L.plate.z - inset, L.plate.w - legH) - a0, 1.0);
    // Bench space is isotropic, so it is fitted, never stretched: an angle here is the same angle
    // as in the bench plan. Whole pixels, so a small canvas shows the art exactly 1:1.
    L.scale = max(floor(min(room.x, room.y / BENCH_H)), 1.0);
    float2 used = float2(L.scale, L.scale * BENCH_H);
    L.org = floor(a0 + (room - used) * 0.5);
    L.plot = float4(L.org, L.org + used);

    L.artScale = L.scale * min(1.0, sqrt(TV_ART_BUDGET / max(used.x * used.y, 1.0)));
    L.art = float2(L.artScale, L.artScale * BENCH_H);
    return L;
}

float2 tvBenchToPix(TvLayout L, float2 p) { return L.org + p * L.scale; }
float2 tvPixToBench(TvLayout L, float2 px) { return (px - L.org) / max(L.scale, 1e-4); }
bool   tvIn(float4 r, float2 p) { return p.x >= r.x && p.x <= r.z && p.y >= r.y && p.y <= r.w; }

// The lane decimation the art draws with, and the number of lanes that leaves on screen.
uint tvStep(uint nLane) { return max(1u, (nLane + TV_MAX_DRAWN - 1u) / TV_MAX_DRAWN); }
uint tvDrawn(uint nLane) { uint st = tvStep(nLane); return (nLane + st - 1u) / st; }

// A segment's colour, exactly as the art accumulates it: its wavelength at full chroma, or the
// alarm for a beam that is trapped (total internal reflection) or ran out of interactions.
float3 tvSegColour(float wl, int evtEnd)
{
    float3 c = ltWavelengthRGB(wl);
    c /= max(max(c.r, max(c.g, c.b)), 1e-3);
    if (evtEnd == EV_TIR || evtEnd == EV_EXHAUST) c = PT_ALARM * 2.0;
    return c;
}

#endif
