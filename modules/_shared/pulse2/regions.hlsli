#ifndef SENTINEL_PULSE2_REGIONS_HLSLI
#define SENTINEL_PULSE2_REGIONS_HLSLI

// Shared detection-region contract for the Pulse2 analyzer and console.
//
// ONE definition of the region record, the profile weighting, and the
// spectrogram <-> panel transform, included by both modules. The console draws,
// hit-tests and drags regions through the same functions the analyzer reduces
// them with, so a box the user sees can never mean something else to the
// detector.
//
// Regions are stored in SPECTROGRAM COORDINATES: linear FFT bin index and hops
// back from the newest hop. Never panel UV — panel extent changes with the dock
// and the analysis must not. The log frequency axis lives inside the transform,
// not in the stored data.

struct RG { float binLo, binHi, hopLo, hopHi, profile, gain, enabled, lane; };

static const uint  P2_MAXREGIONS = 8u;
static const float P2_PROFILE_RECT  = 0.0;
static const float P2_PROFILE_GAUSS = 1.0;

// Display frequency axis. The console's vertical axis is logarithmic because a
// linear bin axis spends three quarters of its height on 5-20 kHz, where almost
// nothing distinguishing happens, and crushes the kick band into a few pixels.
static const float P2_AXIS_LO_HZ = 25.0;
static const float P2_AXIS_HI_HZ = 20000.0;

// --- profile weighting -----------------------------------------------------

// The authored span is treated as +/-2 sigma, so a Gaussian has fallen to ~0.14
// at the region edge rather than being cut off.
float p2_region_sigma(RG r) { return max((r.binHi - r.binLo) * 0.25, 0.5); }

float p2_region_bin_pad(RG r) {
    return (r.profile == P2_PROFILE_GAUSS) ? (2.0 * p2_region_sigma(r)) : 0.0;
}

// Weight of linear bin `bin` at `hopsBack` hops behind the newest hop.
//
// The profile shapes the BIN axis only; the hop axis is always a rectangular
// gate. A Gaussian across time would weight a hop by how old it is, which is a
// property of the display rather than of the audio, and would make one onset
// score differently depending on when it was looked at.
float p2_region_weight(RG r, float hopsBack, float bin) {
    if (r.enabled < 0.5) return 0.0;
    if (hopsBack < r.hopLo || hopsBack > r.hopHi) return 0.0;

    if (r.profile == P2_PROFILE_GAUSS) {
        float c = 0.5 * (r.binLo + r.binHi);
        float s = p2_region_sigma(r);
        if (bin < r.binLo - 2.0 * s || bin > r.binHi + 2.0 * s) return 0.0;
        float t = (bin - c) / s;
        return r.gain * exp(-0.5 * t * t);
    }
    if (bin < r.binLo || bin > r.binHi) return 0.0;
    return r.gain;
}

// --- the one spectrogram <-> panel transform -------------------------------
//
// x: hops back grows to the LEFT, so the newest hop sits at the right edge.
// y: 0 at the bottom (P2_AXIS_LO_HZ) rising to 1 (P2_AXIS_HI_HZ), logarithmic.
//
// `binHz` is the producer's own reported bin width. Nothing here assumes one.

float p2_bin_to_axis(float bin, float binHz) {
    float f = max(bin * binHz, 1e-6);
    float t = log(f / P2_AXIS_LO_HZ) / log(P2_AXIS_HI_HZ / P2_AXIS_LO_HZ);
    return saturate(t);
}

float p2_axis_to_bin(float t, float binHz) {
    float f = P2_AXIS_LO_HZ * pow(P2_AXIS_HI_HZ / P2_AXIS_LO_HZ, saturate(t));
    return f / max(binHz, 1e-6);
}

float2 p2_spec_to_panel(float hopsBack, float bin, float nHops, float binHz) {
    return float2(1.0 - hopsBack / max(nHops - 1.0, 1.0),
                  p2_bin_to_axis(bin, binHz));
}

// uv -> (hopsBack, linear bin). Inverse of p2_spec_to_panel.
float2 p2_panel_to_spec(float2 uv, float nHops, float binHz) {
    return float2((1.0 - uv.x) * max(nHops - 1.0, 1.0),
                  p2_axis_to_bin(uv.y, binHz));
}

#endif
