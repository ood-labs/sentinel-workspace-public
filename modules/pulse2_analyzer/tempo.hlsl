// 2E1 — tempo prior, harmonic suppression, peak pick, confidence.
//
// Turns 100 per-period scores into one tempo, one beat phase and one honest
// confidence. Single thread, but it now reads 100 elements rather than the
// 16000 the matrix holds, because tmax.hlsl did the reduction in parallel.
//
// Three corrections are applied in order, and the order matters: the prior
// reshapes the landscape, so suppressing harmonics before it would subtract
// neighbours that the prior is about to re-weight.

#include "common.hlsli"

StructuredBuffer<PS> M   : register(t0);   // per-tau maxima
StructuredBuffer<PS> P   : register(t1);   // pstate_prev, for the signal gate
RWStructuredBuffer<PS> T : register(u0);   // tempo state

static const uint  NTAU    = 100u;
static const float BPM_MIN = 60.0;
static const float BPM_MAX = 200.0;

// Steps per octave on the geometric tau grid:
//   ratio per step r = (BPM_MAX/BPM_MIN)^(1/(NTAU-1))
//   steps per octave = log(2)/log(r) = (NTAU-1)*log(2)/log(BPM_MAX/BPM_MIN)
// = 99 * 0.6931 / 1.2040 = 56.99. Rounded to 57, which is 0.02 of a step -- far
// inside the grid resolution, so no interpolation is needed for the harmonic
// lookup itself.
static const int OCTAVE_STEPS = 57;

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x != 0u) return;

    float raw[NTAU], prior[NTAU];
    float sumAll = 0.0;

    // ---- 1. log-Gaussian tempo prior --------------------------------------
    // Human tempo perception is centred near 120 BPM and symmetric in OCTAVES,
    // not in BPM: 60 and 240 are equally far from 120 musically, while a linear
    // prior would treat 60 as much closer.
    //
    // SIGMA IS 1.2 OCTAVES, NOT THE 0.8 THE RESEARCH SPECIFIED. Swept offline
    // against the real onset rings of the nine non-held-out patterns: 0.8 and
    // 1.0 both score 6/8 and pull sparse_90 (a genuine 90 BPM) up to 121.5,
    // because at 0.8 the prior's 0.415-octave penalty outweighs sparse_90's
    // evidence. 1.2 recovers it for 7/8. This is an INTERIOR optimum, not an
    // edge -- 1.6 collapses dense_140 and tempo_ramp_120_132 to 62 BPM -- which
    // is the reassurance that it is a real width rather than a fitted one.
    [loop] for (uint i = 0u; i < NTAU; ++i) {
        PS m = M[i];
        float bpm = max(m.b, 1.0);
        float oct = log2(bpm / 120.0) / max(tempo_sigma, 1e-3);
        float w = exp(-0.5 * oct * oct);
        raw[i]   = m.a;
        prior[i] = m.a * w;
        sumAll  += m.a;
    }

    // ---- 2. harmonic suppression ------------------------------------------
    // C'(tau) = C(tau) - gamma * (C(tau/2) + C(2 tau)).
    //
    // A perfect beat grid at 120 BPM also scores well at 60 (every other pulse
    // lands) and at 240 (every pulse lands, plus the gaps). Half the period is
    // DOUBLE the BPM, so it sits +OCTAVE_STEPS up this grid.
    //
    // SHIPPED AT gamma = 0, WHICH DISABLES IT. The mechanism stays implemented
    // and exposed, but every non-zero gamma scored WORSE on the real onset
    // rings -- 0.25 and 0.5 each cost two patterns at every sigma tested.
    // The formula is symmetric, so it penalises a candidate whenever its octave
    // NEIGHBOURS are strong, and a true tempo whose half also scores well is
    // punished just as hard as a spurious harmonic. Measured: it took a correct
    // dense_140 (140.6) to 111.6 and a correct sparse_90 (89.6) to 115.7.
    //
    // It also cannot address the error actually seen. breakbeat_170 resolves to
    // 112.93 = 170 * 2/3, a dotted quarter -- a 3:2 relation, not an octave --
    // which sits 33 grid steps away, not 57. Suppressing the 3:2 relatives as
    // well was tried offline and fixed nothing.
    float best = -1.0e30;
    uint  bi = 0u;
    float sup[NTAU];
    [loop] for (uint i2 = 0u; i2 < NTAU; ++i2) {
        int up = (int)i2 + OCTAVE_STEPS;
        int dn = (int)i2 - OCTAVE_STEPS;
        // The index is clamped as well as guarded. A ternary does not stop the
        // compiler evaluating the array access on both branches, and `up` runs
        // to 156 on a 100-element array -- which is a hard X3504 at compile
        // time, not a silent read.
        uint upi = (uint)clamp(up, 0, (int)NTAU - 1);
        uint dni = (uint)clamp(dn, 0, (int)NTAU - 1);
        float hi = (up < (int)NTAU) ? prior[upi] : 0.0;
        float lo = (dn >= 0)        ? prior[dni] : 0.0;
        sup[i2] = prior[i2] - tempo_gamma * (hi + lo);
        if (sup[i2] > best) { best = sup[i2]; bi = i2; }
    }

    // ---- 3. sub-grid refinement -------------------------------------------
    // Parabolic interpolation in LOG BPM, matching the grid's own spacing. The
    // grid step is 1.22%, which at 120 BPM is 1.46 BPM -- on its own that is
    // marginal against a 2 BPM accuracy target, so the peak is refined rather
    // than reported at grid resolution.
    float bpm = max(M[bi].b, 1.0);
    if (bi > 0u && bi + 1u < NTAU) {
        float y0 = sup[bi - 1u], y1 = sup[bi], y2 = sup[bi + 1u];
        float den = (y0 - 2.0 * y1 + y2);
        if (abs(den) > 1e-9) {
            float d = clamp(0.5 * (y0 - y2) / den, -1.0, 1.0);
            float r = pow(BPM_MAX / BPM_MIN, 1.0 / (float)(NTAU - 1u));
            bpm *= pow(r, d);
        }
    }

    // ---- 4. confidence -----------------------------------------------------
    // Peak-to-average of the RAW comb output, not the suppressed one: the prior
    // and the suppression are assumptions this stage imposed, and letting them
    // inflate the confidence would report certainty about its own bias.
    float meanAll = sumAll / (float)NTAU;
    float par = (meanAll > 1e-9) ? (raw[bi] / meanAll) : 0.0;
    // par = 1 is a flat landscape (no periodicity at all); CONF_FULL is the
    // ratio treated as fully locked. Both ends are clamped, so confidence can
    // never exceed 1 no matter how spiky one frame happens to be.
    float conf = saturate((par - 1.0) / max(conf_full - 1.0, 1e-3));

    // A SIGNAL GATE, not just a numeric one. Adaptive thresholds normalise to
    // whatever is present, so a comb filter fed a noise floor still finds its
    // best-fitting period and reports it confidently -- this is precisely how
    // cryo_pulse came to claim 99% confidence at -44 dBFS. Confidence is forced
    // to zero when the producer says there is no signal, rather than trusting
    // the ratio to notice.
    float signalPresent = P[HDR_H].h;
    if (signalPresent < 0.5) conf = 0.0;

    PS o = T[0];
    // Hold the last TRUSTED BPM, where trusted means it met the lock threshold
    // -- not merely that confidence was non-zero.
    //
    // `conf > 0.0` is too weak, and the difference is what 2E2 criterion 2
    // measures. When music stops, the comb's ring drains over the next four
    // seconds and confidence falls gradually; every frame of that decay still
    // has conf > 0, so the reported BPM tracked the garbage all the way down
    // and froze wherever it happened to end. Measured drift from the last
    // confident value: 42 BPM into digital silence, 102 BPM into a noise floor.
    // Freezing at the last value that cleared `lock_conf` holds it to zero.
    o.a = (conf >= lock_conf) ? bpm : o.a;
    o.b = M[bi].d;              // beat phase, fraction of a beat
    o.c = conf;
    // The period OF THE BPM THIS STAGE ACTUALLY REPORTS, derived from o.a rather
    // than from the current argmax.
    //
    // Publishing the raw grid tau throws away the sub-grid refinement for every
    // consumer that works in periods -- measured as a PLL running at 124.6 BPM
    // while its own emitted beats averaged 128.6. But refining the CURRENT
    // argmax is not enough either, because o.a is HELD at the last value that
    // cleared lock_conf while the argmax keeps moving. The two then describe
    // different tempi: measured on four_on_floor_128, a reported 127.6 BPM
    // alongside a published period of 93.7 hops, which is 120.1 BPM. The phase
    // loop spent the whole pattern pushing against that gap, which is exactly
    // what a continuity score punishes.
    //
    // hps is recovered from the grid's own relation tau = 60*hps/bpm, so it
    // needs no extra plumbing from the producer.
    float hps = M[bi].c * max(M[bi].b, 1.0) / 60.0;
    o.d = 60.0 * hps / max(o.a, 1.0);
    o.e = (float)bi;
    o.f = par;
    o.g = raw[bi];
    o.h = signalPresent;
    T[0] = o;
}
