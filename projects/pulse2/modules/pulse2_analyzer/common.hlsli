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

// The region record, profile weighting and spectrogram<->panel transform are
// SHARED with pulse2_console so a box the user drags cannot mean something
// different to the detector than it does on screen.
#include "../_shared/pulse2/regions.hlsli"

struct PS { float a, b, c, d, e, f, g, h; };
struct SP { float y, p, d, spare; };   // whitened, peak, superflux
// `gen` is the hop this lane slot's flux was computed FROM, so pass B can skip
// slots that already reflect the current stamp. Pass C cannot write here (its
// output is pstate), so there are no threshold/accept fields in this struct;
// the picker's own threshold and accept flag live in the pstate trace ring.
struct LS { float flux, gen, rsvd, spos; };

// 2D feature vector, one per (hop slot, lane), computed in a PARALLEL pass.
// The peak-picker is single-threaded, so per-bin reductions must not live there.
//
//   cent : region-normalised spectral centre of mass, 0 = low edge of the
//              lane's own span, 1 = high edge. Lane-independent by construction
//              so one weight set can serve every lane.
//   flatness : exp(mean(log Y)) / mean(Y) over the region, the geometric-to-
//              arithmetic mean ratio. ~1 for noise, ~0 for a tonal peak.
//   decay    : E[n] / E[n-2], the temporal decay ratio. > 1 while energy is
//              arriving, < 1 on a tail.
//   energy   : the region-weighted mean of whitened magnitude, kept so the
//              ratio above can be audited rather than trusted.
struct FS { float cent, flatness, decay, energy, gen, spos, centD, flatD; };

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
