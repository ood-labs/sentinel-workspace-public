// Shared layout and axis mapping for audio_bands.
//
// The log-Hz mapping lives here and NOWHERE else. Three passes need it — the
// drag converts pointer x to Hz, the column reducer converts pixel x to a bin
// span, and the renderer converts a band's Hz back to pixels. If any two of
// those disagree the band you drag is not the band that gets summed, which is
// exactly the class of failure this module exists to eliminate.

#ifndef AUDIO_BANDS_HLSLI
#define AUDIO_BANDS_HLSLI

static const uint  AB_LANES        = 3u;
static const uint  AB_TRACE        = 512u;
// 0 stateA, 1 stateB, 2 stateC, 3..514 trace
static const uint  AB_LANE_STRIDE  = 515u;
static const uint  AB_BINS         = 1024u;
// Column capacity, not column count. The panel follows its dock, so the real
// width changes continuously; the reducer fills only the first _Resolution.x
// entries and the renderer indexes them 1:1 with pixels. A fixed 1280 would
// have stretched 1280 reduced columns across an arbitrary panel width.
static const uint  AB_COLS_MAX     = 2560u;
static const uint  AB_COL_HDR      = 2560u;  // cols[2560] carries axis metadata
static const uint  AB_DRAG         = 3u;     // bands[3] drag header
static const uint  AB_GRAB         = 4u;     // bands[4] grabbed band at press
static const uint  AB_CUR          = 5u;     // bands[5] current pointer

// Threshold now lives in bands[lane].w rather than in a parameter, because its
// handle has to sit inside a band that moves. Full scale of the on-band fader.
static const float AB_THRESH_MAX   = 48.0;

// Display floor. Below ~20 Hz there is nothing musical and the log axis would
// spend a third of its width on rumble.
static const float AB_HZ_MIN       = 20.0;

// Vertical split, in TOP-DOWN normalized coordinates so it can be compared
// against a raw viewport event position without flipping. Spectrum above,
// three trace strips below.
static const float AB_SPEC_BOT     = 0.58;

// Absolute signal gate, in the same units as the *_level control outputs.
//
// Measured, not guessed: the kick band sits at -41 dB on real drums and at
// -79 dB on the corpus's -44 dBFS noise floor, so -70 dB rejects the noise with
// 38 dB of headroom to spare. At -80 it did not: flux is relative to each
// band's own rolling level, so a noise floor produces the same 7 dB excursions
// a quiet drum does, and five phantom kicks per twenty seconds got through.
static const float AB_SILENCE_DB   = -70.0;

// x in 0..1 -> Hz
float abXToHz(float x, float hzMax) {
    float lo = log(AB_HZ_MIN);
    float hi = log(max(hzMax, AB_HZ_MIN * 2.0));
    return exp(lo + saturate(x) * (hi - lo));
}

// Hz -> x in 0..1
float abHzToX(float hz, float hzMax) {
    float lo = log(AB_HZ_MIN);
    float hi = log(max(hzMax, AB_HZ_MIN * 2.0));
    return saturate((log(max(hz, AB_HZ_MIN)) - lo) / (hi - lo));
}

// Band weight for a bin at `hz`. shape < 0.5 is rectangular, else gaussian
// falling to 0.5 at each declared edge.
float abWeight(float hz, float loHz, float hiHz, float shape) {
    if (shape < 0.5) return (hz >= loHz && hz <= hiHz) ? 1.0 : 0.0;
    float c     = 0.5 * (loHz + hiHz);
    float halfw = max(0.5 * (hiHz - loHz), 1e-3);
    float t     = (hz - c) / halfw;
    return exp(-0.693147 * t * t);
}

// Bin span to iterate for a band. Gaussian needs a skirt or its tails are
// truncated, which would make the shape switch change the LEVEL as well as the
// profile and force a threshold re-tune every time it is toggled.
void abBinSpan(float loHz, float hiHz, float shape, float binHz,
               out uint b0, out uint b1) {
    float pad = (shape < 0.5) ? 0.0 : 0.5 * max(hiHz - loHz, 0.0);
    float f0  = max(floor((loHz - pad) / max(binHz, 1e-6)), 0.0);
    float f1  = min(ceil ((hiHz + pad) / max(binHz, 1e-6)), (float)(AB_BINS - 1u));
    b0 = (uint)f0;
    b1 = (uint)max(f1, f0);
}

float abSafeDb(float amp) {
    return 20.0 * log10(max(amp, 1e-6));
}

// UI unit. Everything with a pixel size is a multiple of this, so the whole
// interface scales with the panel instead of shrinking into a corner of a large
// dock or overflowing a small one.
//
// Integer, and deliberately so: the glyph atlas is a 5x7 bitmap, and a
// fractional scale resamples it into mush at exactly the sizes where the Hz
// readouts most need to stay legible.
float abUI(float H) { return clamp(floor(H / 360.0), 1.0, 5.0); }

// Spectrum plot extent in PIXELS. Defined here so the renderer that draws the
// threshold handle and the event pass that grabs it derive it from one formula.
// Two copies of this drifted apart is exactly how a handle ends up not being
// where it is drawn — and with a panel that resizes continuously, a drift that
// only appears at some sizes would be far worse than one that always applies.
//
// The gap between plotBot and the spectrum's bottom edge is the Hz axis
// gutter, and it has to fit a whole line of type. The font's cell is 8x11 per
// glyph, NOT 8x7 — the 7 is the horizontal advance — so a label at scale s is
// 11*s tall. A 10-unit gutter was shorter than the 11-unit label it held and
// clipped every frequency number along its bottom.
float abPlotTop(float H) { return 13.0 * abUI(H); }
float abPlotBot(float H) { return floor(H * AB_SPEC_BOT) - 16.0 * abUI(H); }

// Threshold fader mapping, absolute rather than incremental so the handle sits
// under the pointer instead of drifting away from it during a drag.
float abYToThresh(float yPix, float H) {
    float t = abPlotTop(H), b = abPlotBot(H);
    return saturate(1.0 - (yPix - t) / max(b - t, 1.0)) * AB_THRESH_MAX;
}
float abThreshToY(float thr, float H) {
    float t = abPlotTop(H), b = abPlotBot(H);
    return t + (1.0 - saturate(thr / AB_THRESH_MAX)) * (b - t);
}

uint abStateA(uint lane) { return lane * AB_LANE_STRIDE + 0u; }
uint abStateB(uint lane) { return lane * AB_LANE_STRIDE + 1u; }
// stateC holds the INSTANTANEOUS band level, which is the value the signal gate
// actually tests. stateA's baseline is a rolling floor and sits far below it on
// percussive material, so displaying the baseline as "level" showed a lane
// reading -84 dB while it was happily firing above a -70 dB gate.
uint abStateC(uint lane) { return lane * AB_LANE_STRIDE + 2u; }
uint abTraceAt(uint lane, uint k) {
    return lane * AB_LANE_STRIDE + 3u + (k % AB_TRACE);
}

#endif
