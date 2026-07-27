#ifndef SENTINEL_SUI3_CORE_HLSLI
#define SENTINEL_SUI3_CORE_HLSLI

// Instrument drawing primitives, v3.
//
// EVERY function here takes PIXEL coordinates. Nothing in this header accepts a
// normalized rect, deliberately. Phase 3A measured the seven Interaction Lab
// stations rendering at extents from 100x132 to 1920x1080 because `follow_panel`
// hands each one whatever dock it happens to occupy; normalized drawing turns
// circles into ellipses and drifts hairlines off the pixel grid at every one of
// those extents. Pixel space keeps a circle circular and a rule exactly one
// pixel regardless of the panel.
//
// COMPOSITING CONVENTION: these return coverage in 0..1 and the caller ADDS
// tinted coverage onto a near-black field:
//
//     col += theme.ink * sui3Hair(d);
//
// They never lerp toward a fill colour. Additive ink on a 0.006 field is what
// reads as drawn measurement; lerping toward a 0.05 control grey is what makes
// the v1 kit read as plastic chrome.

// Antialiased band of width w centred on signed distance d.
float sui3Aa(float d, float w) {
    return 1.0 - smoothstep(w * 0.5 - 0.5, w * 0.5 + 0.5, d);
}

// Exactly one pixel. The default weight for all instrument chrome.
float sui3Hair(float d) { return sui3Aa(d, 1.0); }

// ---------------------------------------------------------------------------
// PIXEL SNAPPING
//
// Callers pass P = tid + 0.5, so pixel CENTRES sit on half-integers. A hairline
// whose geometry lands on an integer boundary is therefore equidistant from two
// centres: both get d = 0.5, both light at 50%, and the "1px" rule renders as a
// 2px smear. Phase 3B measured exactly that -- the header rule came back as two
// adjacent rows at 0.118 each instead of one row at 0.220.
//
// Snapping the GEOMETRY to floor(v)+0.5 puts the line on a centre, so one pixel
// gets d = 0 and its neighbours get d = 1. Snap the coordinate, never the
// distance: by the time a function sees `d` the straddle has already happened.
//
// Radial primitives (ring, disc) are deliberately NOT snapped -- a circle's
// coverage is genuinely fractional and quantising its radius would flat-spot it.
float  sui3Snap(float v)      { return floor(v) + 0.5; }
float2 sui3Snap2(float2 v)    { return floor(v) + 0.5; }
float4 sui3SnapRect(float4 r) { return floor(r) + 0.5; }

// Axis-aligned hairline at coordinate `at`, snapped. The standard way to draw
// any single vertical or horizontal rule.
float sui3HairAt(float p, float at) { return sui3Hair(abs(p - sui3Snap(at))); }

float sui3RectIn(float2 P, float4 r) {
    return step(r.x, P.x) * step(P.x, r.z) * step(r.y, P.y) * step(P.y, r.w);
}

float sui3SdRect(float2 P, float4 r) {
    float2 c = (r.xy + r.zw) * 0.5;
    float2 h = max((r.zw - r.xy) * 0.5, 0.0);
    float2 q = abs(P - c) - h;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}

// 1px hairline frame. No rounded-corner variant exists on purpose: a radius
// reads as a widget, a hard corner reads as a drawn boundary.
float sui3Frame(float2 P, float4 r) {
    return sui3Hair(abs(sui3SdRect(P, sui3SnapRect(r))));
}

// Short corner brackets, the instrument's substitute for a heavy border.
// Distance-based rather than step()-based: the original tested `nearX <= 1.0`,
// which counts pixels from the rect edge and so silently doubles to 2px
// whenever that edge is not already on a pixel centre.
float sui3Brackets(float2 P, float4 r, float len) {
    float4 s = sui3SnapRect(r);
    float inRect = step(s.x - 0.5, P.x) * step(P.x, s.z + 0.5)
                 * step(s.y - 0.5, P.y) * step(P.y, s.w + 0.5);
    float edgeX  = min(abs(P.x - s.x), abs(P.x - s.z));  // to nearest vertical edge
    float edgeY  = min(abs(P.y - s.y), abs(P.y - s.w));  // to nearest horizontal edge
    float alongX = min(P.x - s.x, s.z - P.x);            // run length from a corner
    float alongY = min(P.y - s.y, s.w - P.y);
    float horiz = sui3Hair(edgeY) * step(alongX, len);
    float vert  = sui3Hair(edgeX) * step(alongY, len);
    return saturate(inRect * (horiz + vert));
}

float sui3SegDist(float2 P, float2 a, float2 b) {
    float2 ab = b - a;
    float h = saturate(dot(P - a, ab) / max(dot(ab, ab), 1e-7));
    return length(P - (a + ab * h));
}

float sui3Line(float2 P, float2 a, float2 b, float w) {
    return sui3Aa(sui3SegDist(P, a, b), w);
}

float sui3Ring(float2 P, float2 c, float radius, float w) {
    return sui3Aa(abs(length(P - c) - radius), w);
}

float sui3Disc(float2 P, float2 c, float radius) {
    return sui3Aa(length(P - c) - radius, 1.0);
}

// Measurement graticule inside a rect: `cells` divisions on each axis.
// Resolves the NEAREST gridline coordinate and snaps it, rather than taking a
// frac() distance -- a frac distance is measured from an unsnapped origin, so
// every one of the resulting lines straddles.
float sui3Graticule(float2 P, float4 r, float2 cells) {
    float2 size = max(r.zw - r.xy, float2(1.0, 1.0));
    float2 sp   = size / max(cells, float2(1.0, 1.0));
    float2 at   = sui3Snap2(r.xy + round((P - r.xy) / sp) * sp);
    float2 d    = abs(P - at);
    return sui3RectIn(P, r) * sui3Hair(min(d.x, d.y));
}

// Tick rail along the top edge (axis 0) or the left edge (axis 1).
float sui3Ticks(float2 P, float4 r, float count, float lengthPx, int axis) {
    float2 size = max(r.zw - r.xy, float2(1.0, 1.0));
    float c = max(count, 1.0);
    if (axis == 0) {
        float sp = size.x / c;
        float at = sui3Snap(r.x + round((P.x - r.x) / sp) * sp);
        return sui3RectIn(P, r) * sui3Hair(abs(P.x - at)) * step(P.y, r.y + lengthPx);
    }
    float sp = size.y / c;
    float at = sui3Snap(r.y + round((P.y - r.y) / sp) * sp);
    return sui3RectIn(P, r) * sui3Hair(abs(P.y - at)) * step(P.x, r.x + lengthPx);
}

// Gapped crosshair. The gap is what makes it read as a measurement reticle
// rather than a cursor: the centre stays visible under the crossing.
float sui3Reticle(float2 P, float2 atRaw, float gap, float arm) {
    float2 at = sui3Snap2(atRaw);
    float2 d = P - at;
    float hx = sui3Hair(abs(d.y)) * step(gap, abs(d.x)) * step(abs(d.x), arm);
    float hy = sui3Hair(abs(d.x)) * step(gap, abs(d.y)) * step(abs(d.y), arm);
    return saturate(hx + hy);
}

// Corner crop marks on the full output, in the print-registration sense.
float sui3Registration(float2 P, float2 R, float len) {
    float2 e = min(P, R - P);
    return saturate(step(e.x, len) * step(e.y, 1.0) + step(e.y, len) * step(e.x, 1.0));
}

// Projects a value onto the top and left rails of a rect: the "where does this
// sit on each axis" readout that a bare marker cannot give.
// BOTH SIDES of each rail must be bounded. The first version clipped only the
// far edge (`step(P.y, r.y + railPx)`), which is true for every pixel ABOVE the
// rect as well -- so each readout painted a full-width and full-height line
// across the entire output. It was invisible on a rect near the top-left corner
// and obvious the moment one was placed mid-canvas.
float sui3EdgeReadout(float2 P, float4 r, float2 at, float railPx) {
    float x = sui3HairAt(P.x, at.x)
            * step(r.x, P.x) * step(P.x, r.z)
            * step(r.y, P.y) * step(P.y, r.y + railPx);
    float y = sui3HairAt(P.y, at.y)
            * step(r.y, P.y) * step(P.y, r.w)
            * step(r.x, P.x) * step(P.x, r.x + railPx);
    return saturate(x + y);
}

// ---------------------------------------------------------------------------
// Y-DIRECTION CONTRACT: ZERO FLIPS
//
// A pad has four surfaces that describe the same control -- the Properties row,
// the reticle drawn on the canvas, the number printed beside that reticle, and
// the published control output. THEY MUST ALL CARRY THE SAME NUMBER. The pad's
// value is the host parameter, unmodified, everywhere.
//
// This replaces a "flip exactly once, at publish" rule that was wrong in
// practice. Under it the reticle was drawn at `raw` while the readout beside it
// printed `1 - raw`: a pad sitting 68% down the well captioned 0.32. Two
// visible numbers for one control, disagreeing, which is precisely what
// CLAUDE.md's "every number stays attached to what it describes" forbids. The
// rule also could not survive contact with a second pad, because "once" is not
// checkable -- nothing stops a renderer from flipping again, and
// `au_deck/state.hlsl:52` is AUTOPSIA hitting exactly that.
//
// The VALUE is never flipped. The DIRECTION is a separate question, and the
// answer is uncomfortable: THE HOST DISAGREES WITH ITSELF.
//
// Two host surfaces write and display the same `point2D` parameter, and they use
// opposite Y conventions. Measured, both times by the operator at the mouse:
//
//   * The host's PROPERTIES row is Y-UP. Value 1 renders at the top of the
//     widget. Drag the canvas dot to the top of its well and the Properties row
//     shows the dot at the bottom.
//   * The host's CANVAS xypad gesture (`viewport.controls`, `kind: xypad`) is
//     Y-DOWN. A pointer at the top of the declared rect writes value 0.
//
// The module does not own either mapping. It cannot draw one reticle that agrees
// with both, and there is no third option: the parameter is a single number.
//
// SO THE CANVAS GESTURE WINS, and this is a deliberate choice rather than a
// coin toss. The reticle is the thing under the operator's cursor during a drag;
// a control that does not track the pointer is broken in the hand, while a
// Properties row that plots the same number at the opposite end is merely
// inconsistent to look at. Direct manipulation beats a secondary readout. The
// first attempt at this matched the Properties row instead and made the pad
// undraggable in exactly that way.
//
// Consequence, stated plainly so nobody "fixes" it again: a value of 0 draws at
// the TOP of the well on the canvas and displays at the BOTTOM of the Properties
// widget. That residual mismatch is the host's, it is not reachable from module
// code, and closing it needs a host change to make the two surfaces agree.
//
// The rule, whole: the stored value is the host parameter unmodified on every
// surface, and every value-to-pixel conversion is `sui3PadPoint`. A bare
// `lerp` on a pad is a bug on sight, and so is any `1.0 -` outside this file.
//
// This lives in core, not in sui3_events.hlsli, deliberately: it is a pure
// function and a state pass must be able to call it without declaring viewport
// events. `au_text.hlsli:9` records the v1 kit failing to compile for exactly
// that reason -- an umbrella header dragging in interaction bindings the
// consuming module never declared.
float2 sui3PublishPad(float2 raw) {
    return saturate(raw);
}

// Value -> canvas pixel, for a pad occupying rect `r` = (x0, y0, x1, y1) with y
// increasing downward. This matches the HOST CANVAS GESTURE, which is Y-down:
// value 0 lands on r.y (the TOP edge), so the reticle sits under the pointer
// that produced it. See the contract above for why this and not the Properties
// row. Do not "correct" the Y term here without re-reading it.
float2 sui3PadPoint(float4 r, float2 val) {
    val = saturate(val);
    return float2(lerp(r.x, r.z, val.x), lerp(r.y, r.w, val.y));
}

// Canvas pixel -> value. The exact inverse of sui3PadPoint, and therefore also
// Y-down. A pad that hit-tests with its own arithmetic drifts from the drawing
// the moment one of the two is edited.
float2 sui3PadValue(float4 r, float2 px) {
    float x = (px.x - r.x) / max(r.z - r.x, 1e-5);
    float y = (px.y - r.y) / max(r.w - r.y, 1e-5);
    return saturate(float2(x, y));
}

#endif
