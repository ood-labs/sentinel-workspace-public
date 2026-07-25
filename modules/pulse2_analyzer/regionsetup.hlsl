// Region authoring pass — parameters in, region buffer out.
//
// 2C1 defines regions PROGRAMMATICALLY so the region path is scorable before
// any UI exists. 2C2 replaces this pass's writes with the console's own edits;
// everything downstream reads the buffer and does not care which produced it.
//
// Spans are authored in Hz because that is the meaningful unit for a user and
// for the corpus, but they are STORED as bin indices — spectrogram coordinates
// — using the producer's own reported bin width, captured by the whitening pass
// from a slot it verified. Nothing here assumes a bin width.

#include "common.hlsli"

StructuredBuffer<SP> Spec : register(t0);
RWStructuredBuffer<RG> Rgn : register(u0);

[numthreads(8, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint i = tid.x;
    if (i >= MAXREGIONS) return;

    uint capacity = max(_Data0_HopCapacity, 1u);
    uint latest = _Data0_Generation;
    float binHz = hdr_sample_rate(Spec, latest % capacity)
                / hdr_fft_size(Spec, latest % capacity);
    if (!(binHz > 0.0) || binHz > 1000.0) return;   // keep previous authoring

    float loHz, hiHz, prof, gain, lane, on;
    if (i == 0u) {
        loHz = rgn0_lo_hz; hiHz = rgn0_hi_hz; prof = rgn0_profile;
        gain = rgn0_gain;  lane = 0.0; on = 1.0;
    } else if (i == 1u) {
        loHz = rgn1_lo_hz; hiHz = rgn1_hi_hz; prof = rgn1_profile;
        gain = rgn1_gain;  lane = 1.0; on = 1.0;
    } else if (i == 2u) {
        loHz = rgn2_lo_hz; hiHz = rgn2_hi_hz; prof = rgn2_profile;
        gain = rgn2_gain;  lane = 2.0; on = 1.0;
    } else {
        loHz = 0.0; hiHz = 0.0; prof = 0.0; gain = 0.0; lane = 0.0; on = 0.0;
    }

    RG r;
    r.binLo   = max(floor(loHz / binHz), 0.0);
    r.binHi   = min(floor(hiHz / binHz), (float)(NBINS - 1u));
    // Full hop window by default: the region gates frequency, and every hop is
    // evaluated. 2C2 narrows this on the time axis interactively.
    r.hopLo   = 0.0;
    r.hopHi   = (float)(TRACE_SLOTS - 1u);
    r.profile = (prof >= 0.5) ? PROFILE_GAUSS : PROFILE_RECT;
    r.gain    = gain;
    r.enabled = (r.binHi > r.binLo) ? on : 0.0;
    r.lane    = lane;
    Rgn[i] = r;
}
