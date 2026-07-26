// 2E1 — Comb Filter Matrix over (tau, theta).
//
// One thread per candidate (period, phase) pair. For each, sum the onset
// envelope at NPULSE positions spaced tau hops apart starting at phase theta:
// a real beat grid lands every pulse on an onset and scores high, a wrong
// period or phase lands most pulses in the gaps between them.
//
// Period and phase fall out of ONE structure, which is why the research
// specifies a matrix rather than an autocorrelation followed by a separate
// phase search: autocorrelation is phase-blind by construction, so the phase
// would have to be recovered afterwards from the same evidence anyway.
//
// TAU IS SPACED GEOMETRICALLY, not linearly. Tempo perception is ratio-based --
// the musical distance from 60 to 66 BPM equals that from 120 to 132 -- so a
// linear lag grid would spend most of its resolution on slow tempi nobody is
// playing and leave the fast end coarse. Geometric spacing gives every octave
// the same number of candidates.
//
// THETA IS NORMALISED PHASE, not an absolute hop offset. Each tau has its own
// period, so a fixed offset grid would mean something different for every row
// and the matrix would not be rectangular in any useful sense. theta/NTHETA is
// the fraction of a beat, so column j means the same musical position in every
// row.

#include "common.hlsli"

StructuredBuffer<PS> On  : register(t0);   // onset ring
RWStructuredBuffer<PS> C : register(u0);   // (tau, theta) matrix

static const uint  ORING  = 800u;
static const uint  OHDR   = 800u;
static const uint  NTAU   = 100u;
static const uint  NTHETA = 160u;
// NPULSE IS FIXED, AND IT HAS TO BE.
//
// It is tempting to fit as many periods as the ring holds -- a 60 BPM candidate
// spans 750 of 800 hops with 4 pulses while a 200 BPM one spans 225 and appears
// to "waste" the rest. That reasoning was tried and MEASURED, and it is wrong:
// every row's score is a MEAN, so a row averaging 4 samples has three times the
// variance of one averaging 12, and argmax over the grid is biased toward
// whichever rows are noisiest. Making the count depend on tau makes the variance
// depend on tau, which is a bias with no musical meaning at all.
//
// Measured on breakbeat_170: with the count fitted to the ring (4..12 pulses)
// the raw peak moved from 112.93 down to 67.76 BPM -- further from the true 170,
// not closer, because the 4-pulse slow rows now had the noisiest estimates.
// A fixed count gives every candidate the same estimator variance, which is the
// property cross-row comparison actually needs.
static const uint  NPULSE = 4u;            // beats correlated per candidate
static const float BPM_MIN = 60.0;
static const float BPM_MAX = 200.0;

// Sample the ring at a fractional hop offset back from `newest`, linearly
// interpolated. Nearest-neighbour quantises every candidate period to whole
// hops (5.33 ms), which at 170 BPM is 1.5% of a beat and smears the correlation
// peak across neighbouring taus.
//
// INDEXED BY INTEGER SUBTRACTION, NEVER BY BUILDING A FLOAT POSITION.
// The obvious form is `f = (float)newest - back` and then floor/frac of f. That
// is wrong here and fails slowly rather than loudly. Generation numbers grow
// without bound at 187.5 per second, and float32 has a 24-bit mantissa, so the
// ULP of the position crosses one eighth of a hop at ~1.18e6 generations
// (1.75 hours) and half a hop at ~6.75e6 (10 hours). The interpolation fraction
// quantises with it, so the comb filter's phase resolution silently degrades
// the longer the instrument is left running -- measured as a 6.8e-2 divergence
// from an offline float64 reference at generation 1180236, with 8 of 100
// periods picking a different winning phase.
//
// `back` stays under 4 * 187.5 = 750, where float32 ulp is 6e-5 hops, so
// splitting IT into whole and fractional parts is safe; only the absolute
// generation number is dangerous.
float ring_at(StructuredBuffer<PS> R, uint newest, float back) {
    if (back < 0.0) return 0.0;

    float fb = floor(back);
    uint  ib = (uint)fb;
    float t  = back - fb;              // 0..1, from a small number
    if (ib > newest) return 0.0;

    // gHi is the newer of the two bracketing hops, gLo one hop older, both by
    // exact uint arithmetic. t = 0 lands exactly on gHi, t -> 1 on gLo.
    uint gHi = newest - ib;
    uint gLo = (gHi >= 1u) ? (gHi - 1u) : gHi;

    PS a = R[gHi % ORING];
    PS b = R[gLo % ORING];
    // Stamp guard: a slot holding a different generation is a lap-old value, so
    // it contributes nothing rather than a stale onset at a plausible time.
    // (The stamp is a float too, but it only has to stay integer-exact, which
    // float32 is up to 2^24 = 16.7e6 generations, ~24 hours.)
    float va = ((uint)a.b == gHi + 1u) ? a.a : 0.0;
    float vb = ((uint)b.b == gLo + 1u) ? b.a : 0.0;
    return lerp(va, vb, t);
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint ti = tid.x, th = tid.y;
    // The allocation is rectangular and the dispatch rounds up to whole groups,
    // so the tail threads of each row are out of domain.
    if (ti >= NTAU || th >= NTHETA) return;

    PS h = On[OHDR];
    uint judged = (uint)max(h.a, 0.0);
    if (judged == 0u) return;
    uint newest = judged - 1u;

    float hps = max(h.c, 1.0);             // hops per second, from the producer

    float bpm = BPM_MIN * pow(BPM_MAX / BPM_MIN, (float)ti / (float)(NTAU - 1u));
    float tau = (60.0 / bpm) * hps;        // beat period in hops
    float off = ((float)th / (float)NTHETA) * tau;

    float acc = 0.0;
    [loop] for (uint p = 0u; p < NPULSE; ++p) {
        acc += ring_at(On, newest, off + (float)p * tau);
    }

    PS v;
    v.a = acc / (float)NPULSE;
    v.b = bpm;
    v.c = tau;
    v.d = off;
    v.e = 0.0; v.f = 0.0; v.g = 0.0; v.h = 0.0;
    C[ti * NTHETA + th] = v;
}
