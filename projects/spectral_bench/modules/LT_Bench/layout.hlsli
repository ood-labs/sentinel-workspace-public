// LT_Bench / layout.hlsli — the canvas's two strips, and the ONE mapping between bench space and
// pixels.
//
// Pick and draw both go through ltPixToBench / ltBenchToPix. If the diagram and the hit test
// derived their coordinates independently they would disagree, and it would look like a maths
// bug rather than a layout bug.
#ifndef LT_LAYOUT_HLSLI
#define LT_LAYOUT_HLSLI

#include "../_shared/bench.hlsli"

struct LtLayout
{
    float2 res;
    float  s;          // integer UI scale
    float4 head;       // title / readout row
    float4 planBox;    // outer frame of the bench plan
    float4 plan;       // the bench rectangle itself, aspect-fitted inside planBox
    float4 railBox;    // outer frame of the spectral rail
    float4 ladder;     // event ladder matrix (wavelength x interaction)
    float4 devplot;    // deviation profile (degrees x wavelength)
    float4 foot;       // legend / hint row
    float2 org;        // pixel of bench (0,0)
    float  scale;      // pixels per bench unit
};

LtLayout ltLayout(float2 res)
{
    LtLayout L;
    L.res = res;
    L.s = clamp(floor(min(res.x / 470.0, res.y / 540.0)), 1.0, 3.0);

    float s = L.s;
    float pad = 9.0 * s;
    float headH = 25.0 * s;
    float footH = 27.0 * s;   // two rows: the verbs are the point of this node

    float availY = res.y - headH - footH - pad * 4.0;
    float railH = clamp(availY * 0.40, 80.0 * s, availY - 60.0 * s);

    L.head    = float4(pad, pad, res.x - pad, pad + headH);
    L.planBox = float4(pad, L.head.w + pad, res.x - pad, res.y - pad - footH - pad - railH);
    L.railBox = float4(pad, L.planBox.w + pad, res.x - pad, res.y - pad - footH);
    L.foot    = float4(pad, L.railBox.w + pad * 0.4, res.x - pad, res.y - pad * 0.4);

    // Bench space is isotropic, so it is fitted, never stretched. A stretched plan makes a
    // rotation look like a shear and every angle readout becomes a lie.
    float inset = 7.0 * s;
    float bw = max(L.planBox.z - L.planBox.x - inset * 2.0, 1.0);
    float bh = max(L.planBox.w - L.planBox.y - inset * 2.0, 1.0);
    L.scale = min(bw / 1.0, bh / BENCH_H);
    float2 used = float2(L.scale, L.scale * BENCH_H);
    L.org = float2(L.planBox.x + inset + (bw - used.x) * 0.5,
                   L.planBox.y + inset + (bh - used.y) * 0.5);
    L.plan = float4(L.org, L.org + used);

    // The rail splits into the ladder (what happened, per wavelength per interaction) and the
    // deviation profile (how far each wavelength ended up bent). The profile is the reading the
    // whole instrument exists to produce, so it gets a third of the width and its own frame.
    float rin = 6.0 * s;
    float rx0 = L.railBox.x + rin, rx1 = L.railBox.z - rin;
    float ry0 = L.railBox.y + rin + 11.0 * s;      // room for the column captions
    float ry1 = L.railBox.w - rin - 9.0 * s;       // room for the axis labels
    float split = rx0 + (rx1 - rx0) * 0.615;
    L.ladder  = float4(rx0 + 26.0 * s, ry0, split - 8.0 * s, ry1);
    L.devplot = float4(split + 26.0 * s, ry0, rx1, ry1);

    return L;
}

float2 ltBenchToPix(LtLayout L, float2 p) { return L.org + p * L.scale; }
float2 ltPixToBench(LtLayout L, float2 px) { return (px - L.org) / max(L.scale, 1e-4); }
float  ltBenchToPixR(LtLayout L, float r)  { return r * L.scale; }

bool ltInBox(float4 r, float2 p) { return p.x >= r.x && p.x <= r.z && p.y >= r.y && p.y <= r.w; }

// Rail axes. Red at the TOP, matching both a spectrograph plate and the reference photograph.
float ltWlToY(float4 r, float wl)
{
    float t = saturate((wl - WL_MIN) / (WL_MAX - WL_MIN));
    return lerp(r.w, r.y, t);
}
float ltDepthToX(float4 r, float d, float n)
{
    return lerp(r.x, r.z, saturate((d + 0.5) / max(n, 1.0)));
}

#endif
