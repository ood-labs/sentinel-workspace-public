// Pulse2 / Analyzer — shared layout and helpers.
//
// pstate element layout (8 floats, 32 bytes):
//   [0]  H: cursor, hopCount, latestSeen, hopsPerSec, sampleRate, hopSize, spare, signalPresent
//   [1]  C: kickCount, snareCount, hatCount, onsetCount, hitSerial, spare, spare, spare
//   [2]  E: kickEnv, snareEnv, hatEnv, spare, lastHop0, lastHop1, lastHop2, spare
//   [3]  T: bpm, beatPhase, tempoConf, beatPulse, spare, spare, spare, spare   (2E1)
//   [4..15]  reserved
//   [16 .. 527]    hits ring: lane, serial, hop, samplePos, strength, 0, 0, 0
//   [528 .. 1551]  trace ring [slot*16 + lane]: flux, thr, hit, samplePos
//
// pstate is PERSISTENT, so pass C writes only what changed instead of copying
// the whole buffer on a single thread each cook. commit mirrors it into
// pstate_prev so passes A/B/C read a stable snapshot.

// A detection region, stored in SPECTROGRAM COORDINATES (hop index, bin index)
// and never in panel UV. Panel space is a rendering concern that changes with
// dock size; the analysis must not. `spec_to_panel` below is the single
// conversion, shared by the reduction, the render, and later by 2C2's pick/drag.
//
//   binLo/binHi : inclusive bin span
//   hopLo/hopHi : inclusive span in hops-back-from-newest (0 = newest hop)
//   profile     : 0 = rectangular, 1 = Gaussian across the BIN axis
//   lane        : which output lane this region feeds
struct RG { float binLo, binHi, hopLo, hopHi, profile, gain, enabled, lane; };
static const uint MAXREGIONS = 8u;
static const float PROFILE_RECT = 0.0;
static const float PROFILE_GAUSS = 1.0;

struct PS { float a, b, c, d, e, f, g, h; };
struct SP { float y, p, d, spare; };   // whitened, peak, superflux
// `gen` is the hop this lane slot's flux was computed FROM, so pass B can skip
// slots that already reflect the current stamp. Pass C cannot write here (its
// output is pstate), so there are no threshold/accept fields in this struct;
// the picker's own threshold and accept flag live in the pstate trace ring.
struct LS { float flux, gen, rsvd, spos; };

static const uint NBINS    = 1024u;
static const uint HOPS     = 64u;     // Spectrum ring capacity
static const uint PEAKBASE = 65536u;  // spec[PEAKBASE + k] holds the running peak
static const uint MAXLANES = 16u;
static const uint NLANES   = 3u;      // fixed lanes at 2B, for like-for-like scoring

static const uint HDR_H = 0u;
static const uint HDR_C = 1u;
static const uint HDR_E = 2u;
static const uint HDR_T = 3u;
static const uint HITS_BASE = 16u;
static const uint HITCAP    = 512u;
static const uint TRACE_BASE   = 528u;
// The trace ring is deliberately LONGER than the 64-hop spectrum ring. 64 hops
// is 341 ms, so at 128 BPM a preview frame often contains no kick at all and
// reads as an empty instrument. 256 hops is ~1.37 s, which always shows several
// beats. 256 * NLANES = 768 elements, inside the 1024 reserved from TRACE_BASE.
static const uint TRACE_SLOTS  = 256u;
static const uint PSTATE_TOTAL = 1552u;

uint trace_index(uint gen, uint lane) {
    return TRACE_BASE + (gen % TRACE_SLOTS) * NLANES + lane;
}

// Producer header, captured by the whitening pass from a slot it has verified
// (see whiten.hlsl). NEVER read sample_rate / fft_size / hop_size from
// _Data0[0]: that is an arbitrary unvalidated ring slot, and when it reads zero
// the max(x, 1u) guards silently yield binHz = 1.0 and hopsPerSec = 1.0, which
// redefines every lane as bin-index-as-Hz and collapses the refractory.
float hdr_fft_size(StructuredBuffer<SP> spec, uint slot)   { return max(spec[slot * NBINS + 0u].d, 1.0); }
float hdr_sample_rate(StructuredBuffer<SP> spec, uint slot) { return max(spec[slot * NBINS + 1u].spare, 1.0); }
float hdr_hop_size(StructuredBuffer<SP> spec, uint slot)   { return max(spec[slot * NBINS + 1u].d, 1.0); }
// The generation this spec slot actually holds. 0 means never written.
uint  hdr_gen(StructuredBuffer<SP> spec, uint slot)        { return (uint)max(spec[slot * NBINS + 2u].spare, 0.0); }

// All dynamic-range transforms use log(1 + gamma * X), per the phase doc.
float compress(float x, float gamma) {
    return log(1.0 + gamma * max(x, 0.0));
}

// Gaussian sigma for a region: the authored span is treated as +/-2 sigma, so
// the profile has fallen to ~0.14 at the region edge instead of being cut off.
float region_sigma(RG r) { return max((r.binHi - r.binLo) * 0.25, 0.5); }

// How far outside the authored span a Gaussian still contributes meaningfully.
float region_bin_pad(RG r) {
    return (r.profile == PROFILE_GAUSS) ? (2.0 * region_sigma(r)) : 0.0;
}

// Weight of bin `bin` at `hopsBack` hops behind the newest hop.
//
// The profile shapes the BIN axis only; the hop axis is always a rectangular
// gate. A Gaussian across time would weight a hop by how old it is, which is a
// property of the display and not of the audio, and would make the same onset
// score differently depending on when it was looked at.
float region_weight(RG r, float hopsBack, float bin) {
    if (r.enabled < 0.5) return 0.0;
    if (hopsBack < r.hopLo || hopsBack > r.hopHi) return 0.0;

    if (r.profile == PROFILE_GAUSS) {
        float c = 0.5 * (r.binLo + r.binHi);
        float s = region_sigma(r);
        if (bin < r.binLo - 2.0 * s || bin > r.binHi + 2.0 * s) return 0.0;
        float t = (bin - c) / s;
        return r.gain * exp(-0.5 * t * t);
    }
    if (bin < r.binLo || bin > r.binHi) return 0.0;
    return r.gain;
}

// The ONE spectrogram <-> panel transform. `hopsBack` grows to the left so the
// newest hop sits at the right edge; bin 0 sits at the bottom.
float2 spec_to_panel(float hopsBack, float bin, float nHops, float nBins) {
    return float2(1.0 - hopsBack / max(nHops - 1.0, 1.0),
                  bin / max(nBins - 1.0, 1.0));
}
float2 panel_to_spec(float2 uv, float nHops, float nBins) {
    return float2((1.0 - uv.x) * max(nHops - 1.0, 1.0),
                  uv.y * max(nBins - 1.0, 1.0));
}
