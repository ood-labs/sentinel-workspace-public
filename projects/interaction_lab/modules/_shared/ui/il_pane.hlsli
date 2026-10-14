// il_pane.hlsli - Interaction Lab kit: panes, splitters and per-pane views.
//
// A multi-view editor is ONE canvas cut into panes by a pure layout function of
// (extent, persisted splitter values). The reducer pass and every draw pass call the same
// function, so the thing you see and the thing you hit can never disagree - and because the
// rects are recomputed from the live extent, hit targets keep their pixel size in any dock
// (host `viewport.controls` rects are fixed fractions; that is why complex editors hit-test in
// the shader instead).
//
// Splitters: a split stores ONE number, the fraction of the parent given to the first child.
// Minimum pane sizes are pixels, enforced at layout time, so a narrow dock squeezes the flexible
// pane rather than collapsing a toolbar.
//
// Views: each pane that pans or zooms keeps an ILView (origin + scale per axis) in the state
// buffer. world -> screen is  s = pane.xy + org + w * scale.  Zoom about the cursor keeps the
// world point under the cursor fixed; that one rule is what makes zoom feel right.
#ifndef IL_PANE_HLSLI
#define IL_PANE_HLSLI

#include "../_shared/ui/il_core.hlsli"

struct ILSplit {
    float4 a;       // first child (left / top)
    float4 b;       // second child (right / bottom)
    float4 grip;    // the hit band for dragging this split (wider than the drawn hairline)
    float  at;      // the divider coordinate in px
};

// Vertical divider (children side by side). t = fraction of r's width given to `a`.
ILSplit ilSplitX(float4 r, float t, float minA, float minB, float gap, float grip)
{
    ILSplit s;
    float w = max(r.z - r.x - gap, 1.0);
    float x = r.x + clamp(t * w, min(minA, w * 0.5), max(w - minB, w * 0.5));
    s.at = x + gap * 0.5;
    s.a = float4(r.x, r.y, x, r.w);
    s.b = float4(x + gap, r.y, r.z, r.w);
    s.grip = float4(s.at - grip, r.y, s.at + grip, r.w);
    return s;
}

// Horizontal divider (children stacked). t = fraction of r's height given to `a`.
ILSplit ilSplitY(float4 r, float t, float minA, float minB, float gap, float grip)
{
    ILSplit s;
    float h = max(r.w - r.y - gap, 1.0);
    float y = r.y + clamp(t * h, min(minA, h * 0.5), max(h - minB, h * 0.5));
    s.at = y + gap * 0.5;
    s.a = float4(r.x, r.y, r.z, y);
    s.b = float4(r.x, y + gap, r.z, r.w);
    s.grip = float4(r.x, s.at - grip, r.z, s.at + grip);
    return s;
}

// Inverse: the split fraction that puts the divider under pointer coordinate v.
float ilSplitXValue(float4 r, float x, float gap) { return saturate((x - gap * 0.5 - r.x) / max(r.z - r.x - gap, 1.0)); }
float ilSplitYValue(float4 r, float y, float gap) { return saturate((y - gap * 0.5 - r.y) / max(r.w - r.y - gap, 1.0)); }

// ---------------------------------------------------------------- views
struct ILView { float2 org; float2 scale; };

ILView ilView(float2 org, float2 scale) { ILView v; v.org = org; v.scale = scale; return v; }
float2 ilW2S(ILView v, float4 pane, float2 w) { return pane.xy + v.org + w * v.scale; }
float2 ilS2W(ILView v, float4 pane, float2 s) { return (s - pane.xy - v.org) / v.scale; }

// Multiply scale by `factor` per axis while keeping the world point under screen point sp fixed.
ILView ilZoomAbout(ILView v, float4 pane, float2 sp, float2 factor, float2 minScale, float2 maxScale)
{
    float2 w = ilS2W(v, pane, sp);
    float2 ns = clamp(v.scale * factor, minScale, maxScale);
    ILView o;
    o.scale = ns;
    o.org = sp - pane.xy - w * ns;
    return o;
}

// Frame a world box [wlo, whi] inside the pane with a pixel margin (F = frame all).
ILView ilFrame(float4 pane, float2 wlo, float2 whi, float margin, bool sameScale)
{
    float2 sz = max(ilSize(pane) - 2.0 * margin, float2(8.0, 8.0));
    float2 ext = max(whi - wlo, float2(1e-4, 1e-4));
    float2 sc = sz / ext;
    if (sameScale) sc = min(sc.x, sc.y).xx;
    ILView v;
    v.scale = sc;
    v.org = (ilSize(pane) - ext * sc) * 0.5 - wlo * sc;
    return v;
}

// A "nice" step for grid lines / ruler ticks: the 1-2-5 sequence step whose screen spacing is
// at least minPx at `scale` px per unit.
float ilNiceStep(float scale, float minPx)
{
    float raw = minPx / max(abs(scale), 1e-6);
    float p10 = pow(10.0, floor(log10(raw)));
    float m = raw / p10;
    float k = (m <= 1.0) ? 1.0 : ((m <= 2.0) ? 2.0 : ((m <= 5.0) ? 5.0 : 10.0));
    return k * p10;
}

#endif
