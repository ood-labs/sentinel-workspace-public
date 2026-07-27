#ifndef SENTINEL_SUI3_TRACE_HLSLI
#define SENTINEL_SUI3_TRACE_HLSLI

// Scrolling strip chart, v3. The CHOP-viewer behaviour: the plot advances at
// the rate of the DATA, and it rescales itself to the signal's recent dynamics.
//
// Extracted from `modules/audio_bands`, which measured all four mechanisms
// against real material. Nothing here is audio-specific; a "sample" is any
// scalar that arrives on its own clock.
//
// NO TEXT, NO THEME, NO PARAMETERS, NO `_Resolution`. Every extent is an
// argument. Two reasons. First, `audio_bands` renders through `au_hud` while the
// Interaction Lab is on sui3, and a component that reaches for either kit's
// glyphs can only ever serve one of them. Second, `au_text.hlsli:9` records what
// happens when a header drags in bindings its consumer never declared: a state
// pass that plots a value must be able to include this without declaring
// viewport events.
//
// Labels, units and readouts belong to the calling module.
//
// ---------------------------------------------------------------------------
// THE FOUR MECHANISMS
//
//   1. RING + CATCH-UP    plot every sample, not one per cook
//   2. DECAYING PEAK      full scale follows the material
//   3. MAX-REDUCE         a transient survives a column that spans many samples
//   4. SCALE THE REFERENCE a threshold line is part of the scale, not decoration
//
// Skipping any one of them produces a plot that looks right and lies.
//
// ---------------------------------------------------------------------------
// Y DIRECTION: this is a PLOT, not a pad. Value 0 sits on the rect's BOTTOM
// edge and value 1 on its top, which is the opposite of `sui3PadPoint`. That is
// not an inconsistency to be tidied up. A pad's Y is forced by the host, which
// disagrees with itself about it (see the contract in sui3_core.hlsli); a strip
// chart's value is the module's own and answers to nothing but the convention
// every measuring instrument ever built already uses. Do not "align" these.
//
// TIME DIRECTION: oldest at the rect's left edge, newest at the right, so the
// trace scrolls right to left.

// Same include spelling the rest of the kit uses: resolution is rooted at the
// consuming module's directory, not at this file's.
#include "../_shared/ui/sui3_core.hlsli"

// ---------------------------------------------------------------------------
// 1. RING ADDRESSING AND GENERATION CATCH-UP
//
// The consumer keeps a write cursor and drains from it to `_DataN_Generation`
// every cook. A module cooking at 60 Hz against a 187.5 Hz hop rate that samples
// only the newest value discards two of every three samples and aliases the
// rest, and the time axis it draws is then a fiction.

// Ring slot for absolute sample index `k`. `base` offsets a lane inside a shared
// buffer; pass 0 for a single trace.
uint sui3TraceAt(uint base, uint capacity, uint k) {
    return base + (k % max(capacity, 1u));
}

// First generation still resident in the ring.
//
// The clamp is the whole point. A fresh cursor of 0 against a generation counter
// in the millions spins the drain loop a million times on the first cook, which
// is a hang, not a slowdown.
uint sui3CatchupStart(uint cursor, uint latest, uint capacity) {
    uint cap    = max(capacity, 1u);
    uint oldest = (latest + 1u > cap) ? (latest + 1u - cap) : 0u;
    return max(cursor, oldest);
}

// Bound for the drain loop. Never exceeds the ring, so a stalled cook that wakes
// to a generation gap costs one ring's work and no more.
uint sui3CatchupEnd(uint start, uint latest, uint capacity) {
    return min(latest, start + max(capacity, 1u));
}

// Cursor to store after a drain. Always `latest + 1`: the next cook must not
// re-drain the generation it just consumed.
uint sui3CatchupNext(uint latest) { return latest + 1u; }

// ---------------------------------------------------------------------------
// 2. AUTOSCALE
//
// A fixed full scale is wrong for every input. Measured on real drums, peaks run
// past 24 dB while a quiet pad barely reaches 4: one case clips, the other is a
// flat line at the bottom of the rect.

// Exponentially-decaying rolling peak. Instant attack, half-life release.
//
// `dt` is the SAMPLE's own delta, not the frame's, when driven from a drain loop
// — that is what makes the decay a human sees identical at 20 Hz and 60 Hz cook
// rates. `audio_bands` measured a 4 s half-life as the point where the scale
// follows a change of material without twitching on individual hits.
float sui3PeakDecay(float peak, float value, float dt, float halfLifeSec) {
    float tau = max(halfLifeSec, 1e-3) / 0.693147;
    return max(peak * exp(-max(dt, 0.0) / tau), value);
}

// Linear-slope peak hold, for a per-column meter where a constant fall rate
// reads better than an exponential tail. Units are value-per-second.
float sui3PeakLinear(float peak, float value, float dt, float ratePerSec) {
    return max(value, peak - max(dt, 0.0) * max(ratePerSec, 0.0));
}

// Full scale for a strip.
//
// `refLevel` is MECHANISM 4: any reference line drawn on the strip must
// participate in its own scale. Leave it out and a threshold set above the
// recent peak pins itself to the top edge, where it stops reading as a threshold
// and becomes the rect border — losing exactly the thing the strip exists to
// show, which is how far under the line the peaks are falling. Pass 0 when the
// strip carries no reference.
//
// `minFs` is not optional in practice. Without a floor a silent input
// autoscales its own noise to full height and looks like it is working.
// `headroom` of ~1.15 keeps the tallest peak off the top edge.
//
// FEED THIS THE WINDOW MAX, NOT ONLY THE DECAYED PEAK. The decay is anchored at
// "now" while the plot shows history, so whenever the half-life is short
// relative to the span, a loud passage still fully on screen has already
// decayed the peak below its own samples and the plot clips itself.
//
// Measured in Data Scope, same material and same settings both times, span 5 s
// against a 0.25 s half-life. Plotted column height as a fraction of the strip:
//
//   decayed peak only:            peak 1.000  p95 1.000  median 1.000/0.875/0.876
//   max(windowMax, decayedPeak):  peak 0.875  p95 0.855  median 0.614/0.473/0.492
//
// 0.875 is 1/1.15, exactly the headroom, so the tallest sample lands just under
// the top edge and nothing clips. The severity scales with span/half-life: at
// the 3 s and 4 s defaults the same break measured only 0.896, which looks
// almost right and is the reason this needs a written number rather than a
// glance.
//
// The fix is a floor, not a replacement. Scan the displayed samples for their
// maximum and pass `max(windowMax, decayedPeak)`: the window term guarantees
// nothing on screen can clip, and the decayed term keeps the scale from
// snapping the instant a peak scrolls off the left edge.
float sui3FullScale(float peak, float refLevel, float minFs, float headroom) {
    return max(max(peak, refLevel), max(minFs, 1e-6)) * max(headroom, 1.0);
}

// ---------------------------------------------------------------------------
// 3. COLUMN SPAN (MAX-REDUCE)
//
// At long spans one pixel column covers many samples. Reduce with MAX, never
// with a mean: averaging hides precisely the transient the plot exists to show.
//
// This returns the span rather than the value because HLSL cannot take a
// resource as a function argument, and a macro that reaches for a buffer by
// name is how a "shared" header stops being shareable. The caller runs a
// four-line loop over [i0, i1] and takes its own max.

// How many samples to show, from a span in seconds and the sample interval.
// Clamped to the ring: asking for more history than the ring holds would replay
// stale slots as if they were recent.
float sui3TraceSamples(float spanSeconds, float sampleDt, uint capacity) {
    if (sampleDt <= 0.0) return 0.0;
    return clamp(spanSeconds / sampleDt, 8.0, (float)max(capacity, 16u) - 2.0);
}

// Absolute sample indices covered by the pixel column at `px`, for a plot
// spanning x0..x1 with `writeIdx` as the next write position.
//
// Indices are ABSOLUTE and may be negative before the ring has filled; the
// caller skips those. Convert with `sui3TraceAt`.
//
// The step cap is a real bound, not defensive garnish: at a long span on a
// narrow panel one column can cover hundreds of samples, and an uncapped loop
// per pixel is a frame-rate cliff. Eight samples is enough that a single-sample
// transient survives at every span the ring can hold.
void sui3TraceSpan(float px, float x0, float x1, float nShow, float writeIdx,
                   out int i0, out int i1) {
    float w  = max(x1 - x0, 1.0);
    float u0 = (px - x0) / w;
    float u1 = (px + 1.0 - x0) / w;
    int kA = (int)floor(u0 * nShow);
    int kB = min((int)floor(u1 * nShow), kA + 8);
    float origin = writeIdx - nShow;
    i0 = (int)origin + kA;
    i1 = (int)origin + max(kB, kA);
}

// Fractional sample position of a pixel column.
//
// MAX-REDUCE IS ONLY RIGHT WHEN DOWNSAMPLING. It exists to stop a transient
// being lost between two pixels when a column covers many samples. When the
// plot is UPSAMPLING -- more pixel columns than samples, which is the normal
// case for a cook-rate signal on a wide panel -- several adjacent columns land
// on the same sample, the reduced value is piecewise constant, and a smooth
// curve is drawn as a visible staircase. Measured on a 60 Hz LFO at an 8 s span
// across 1600 px: 481 samples, so roughly three columns per sample and a
// three-pixel tread on every step.
//
// Use `sui3TraceUpsampling` to pick, then interpolate between floor(pos) and
// floor(pos)+1 by frac(pos) instead of reducing.
float sui3TraceFrac(float px, float x0, float x1, float nShow, float writeIdx) {
    float w = max(x1 - x0, 1.0);
    float u = (px - x0) / w;
    return writeIdx - nShow + u * nShow;
}

// True when the plot has more columns than samples to fill them.
bool sui3TraceUpsampling(float x0, float x1, float nShow) {
    return nShow < max(x1 - x0, 1.0);
}

// ---------------------------------------------------------------------------
// 4. DRAWING
//
// Geometry only, in the sui3 additive-coverage convention: these return 0..1 and
// the caller adds tinted coverage onto a near-black field.

// Pixel row for a normalized 0..1 value inside the strip rect. Value 0 -> bottom.
float sui3StripY(float4 r, float norm) {
    return lerp(r.w, r.y, saturate(norm));
}

// Normalized value for a pixel row. Exact inverse of sui3StripY.
float sui3StripValue(float4 r, float py) {
    return saturate((r.w - py) / max(r.w - r.y, 1e-5));
}

// Filled column from the baseline up to `norm`. The strip's primary mark.
//
// Filled rather than a traced outline on purpose: an outline of a signal that
// max-reduces across a column is a scatter of disconnected dots, because
// adjacent columns take their maxima from different samples. A fill reads as one
// continuous envelope at every span.
float sui3StripFill(float2 P, float4 r, float norm) {
    float top = sui3StripY(r, norm);
    return sui3RectIn(P, r) * step(top, P.y);
}

// Connected trail between this column's value and the next one's.
//
// The fill above is right for a signal made of events, where each column is an
// independent excursion from a baseline. It is wrong for a smooth continuous
// signal: a solid slab under an LFO hides the shape that is the whole content.
// Drawing unconnected per-column marks instead gives a dotted scatter, because
// adjacent columns take their maxima from different samples.
//
// A segment spanning both columns' values reads as one continuous curve at any
// span. `w` is the stroke width in pixels; 1.0 is the instrument hairline.
float sui3StripTrail(float2 P, float4 r, float normHere, float normNext, float w) {
    float y0 = sui3StripY(r, normHere);
    float y1 = sui3StripY(r, normNext);
    float d  = max(max(min(y0, y1) - P.y, P.y - max(y0, y1)), 0.0);
    return sui3RectIn(P, r) * sui3Aa(d, w);
}

// Horizontal reference line across the strip at a normalized level. Dashed, so
// it can never be mistaken for signal. The dash period is in pixels and should
// scale with the panel's UI unit, or it closes into a solid line on a large dock.
float sui3StripRef(float2 P, float4 r, float norm, float dashPx) {
    float y = sui3StripY(r, norm);
    float on = step(frac(P.x / max(dashPx, 1.0)), 0.55);
    return sui3RectIn(P, r) * sui3HairAt(P.y, y) * on;
}

// Full-height event tick at the current column. For marking a sample that was
// accepted, triggered, or otherwise decided about, on the sample it happened.
float sui3StripTick(float2 P, float4 r, float fired) {
    return sui3RectIn(P, r) * step(0.5, fired);
}

// Baseline rule along the bottom edge.
float sui3StripBase(float2 P, float4 r) {
    return step(r.x, P.x) * step(P.x, r.z) * sui3HairAt(P.y, r.w);
}

#endif
