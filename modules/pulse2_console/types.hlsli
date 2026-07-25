// Pulse2 / Console — shared layout.
//
// The console owns the DISPLAY spectrogram, which is a different object from
// the detector's analysis spectrum: log-frequency rebinned, equalised against a
// per-display-bin running peak, and gamma compressed. The detector's whitening
// is tuned for onset separation and looks flat and grey to a human; this chain
// is tuned for a human to read structure.

#include "../_shared/pulse2/regions.hlsli"

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
