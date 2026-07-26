// Pulse2 / Console — shared layout.
//
// The console owns the DISPLAY spectrogram, which is a different object from
// the detector's analysis spectrum: log-frequency rebinned, equalised against a
// per-display-bin running peak, and gamma compressed. The detector's whitening
// is tuned for onset separation and looks flat and grey to a human; this chain
// is tuned for a human to read structure.

#include "../_shared/pulse2/regions.hlsli"

// Region buffer: 0..7 regions, 8 = drag header, 9 = firing flash,
// 10 = lane spans in Hz published to the control outputs,
// 11 = latched classifier verdict for the readout card.
static const uint P2_HDR_IDX     = 8u;
static const uint P2_FLASH_IDX   = 9u;
static const uint P2_PUB_IDX     = 10u;  // lane spans in Hz for control outputs
static const uint P2_VERDICT_IDX = 11u;  // newest classifier verdict, latched
static const uint P2_RGN_ELEMS   = 12u;  // keep in step with manifest buffers
static const uint P2_MAXFLASH    = 6u;

// The verdict record reuses RG's eight floats rather than adding a buffer,
// because it is latched by the same single-threaded events pass that already
// owns this table and a second output would need a second pass.
//
//   binLo = spectral centroid      hopHi   = classifier score
//   binHi = spectral flatness      profile = +1 accept, -1 reject, 0 none yet
//   hopLo = temporal decay ratio   gain    = seconds since the latch
//   enabled = 0 ALWAYS, so a buffer scan can never mistake this for a region.
//   lane    = which lane the verdict belongs to.

static const uint DISP_BINS = 192u;   // log-spaced rows, 25 Hz .. 20 kHz
static const uint DISP_HOPS = 768u;   // ~4.1 s of history at 187.5 hops/s
// 2 s across a ~2000 px panel is a 5 px/hop magnification: individual hits fill
// a fifth of the width and no musical structure (bar, backbeat) is visible at
// once. 4 s shows a full bar at any usual tempo.
static const uint EQ_BASE   = DISP_BINS * DISP_HOPS;   // running peaks live here
static const uint CURSOR_IDX = EQ_BASE + DISP_BINS;    // append cursor
static const uint HIST_TOTAL = CURSOR_IDX + 1u;

// [hop * DISP_BINS + bin] : v = rebinned magnitude, eq = displayed value
// [EQ_BASE + bin]         : v = per-bin running peak (persistent recursion)
// [CURSOR_IDX]            : v = newest generation appended, r0 = newest hop slot
//
// The cursor lives HERE, in this pass's own output, not in the interaction
// state. A later pass advancing it would use its own, newer _Data0_Generation
// snapshot and silently skip every hop that arrived in between.
struct DH { float v, eq, r0, r1; };

// Console interaction state, one element.
struct UI {
    float dragActive;    // 0/1
    float dragKind;      // 0 none, 1 draw new box, 2 move existing
    float dragRgn;       // region index under edit, -1 when none
    float dragStartX, dragStartY;
    float dragCurX, dragCurY;
    float lane;          // lane assigned to the next drawn region
    float command;       // 1 = clear all regions
    float binHz;         // cached producer bin width
    float snapTaken;     // 1 once this drag's undo snapshot exists
    float flash0, flash1, flash2, flash3;
    float flash4, flash5, flash6, flash7;
};   // 20 floats = 80 bytes

float ui_flash(UI s, uint i) {
    if (i == 0u) return s.flash0;
    if (i == 1u) return s.flash1;
    if (i == 2u) return s.flash2;
    if (i == 3u) return s.flash3;
    if (i == 4u) return s.flash4;
    if (i == 5u) return s.flash5;
    if (i == 6u) return s.flash6;
    return s.flash7;
}

// Palette: workspace monochrome scientific instrument, one warm accent.
// Deliberately NOT Magma/Inferno — perceptual contrast comes from the
// equalisation and gamma stages, not from hue.
static const float3 P2_INK    = float3(0.035, 0.037, 0.040);
static const float3 P2_GRID   = float3(0.16, 0.17, 0.18);
static const float3 P2_TRACE  = float3(0.92, 0.94, 0.95);
static const float3 P2_ACCENT = float3(0.98, 0.62, 0.23);

// Region borders are COOL, not the warm accent, because the intensity ramp below
// is warm through most of its upper range. An orange border on orange content
// disappears exactly where the content is loudest, which is where you most need
// to see the region edge.
static const float3 P2_EDGE = float3(0.45, 0.92, 1.0);

// Intensity ramp: near-black -> indigo -> magenta -> orange -> pale yellow.
//
// Deviation from spec, at explicit user request. Both CLAUDE.md and the phase doc
// specify the monochrome instrument look and call out NOT using a Magma/Inferno
// ramp; the user reviewed the monochrome build at the 2C2 checkpoint and asked for
// a darker base running through a colour spectrum so instruments separate. This is
// their call, so `disp_hue` blends continuously back to the authored greyscale
// rather than replacing it — set it to 0 for the spec palette.
//
// Hue does real work here that luminance cannot: a kick and a hat can sit at the
// same brightness and be told apart instantly by colour, whereas in greyscale
// everything loud converges on the same white.
float3 p2_ramp(float t, float hue) {
    t = saturate(t);

    float3 mono = lerp(P2_INK, float3(0.93, 0.95, 0.96), t);

    // Five stops, piecewise. Dark end is deliberately near-black rather than the
    // ink grey so quiet bins read as empty instead of as faint content.
    static const float3 C0 = float3(0.010, 0.012, 0.030);
    static const float3 C1 = float3(0.180, 0.090, 0.420);
    static const float3 C2 = float3(0.640, 0.130, 0.450);
    static const float3 C3 = float3(0.960, 0.420, 0.150);
    static const float3 C4 = float3(0.990, 0.930, 0.700);

    float s = t * 4.0;
    float3 col;
    if      (s < 1.0) col = lerp(C0, C1, s);
    else if (s < 2.0) col = lerp(C1, C2, s - 1.0);
    else if (s < 3.0) col = lerp(C2, C3, s - 2.0);
    else              col = lerp(C3, C4, saturate(s - 3.0));

    return lerp(mono, col, saturate(hue));
}
