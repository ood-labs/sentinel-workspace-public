// 2E2 — dual-loop PLL, confidence, free-wheel, beat emission.
//
// The comb reports a fresh tempo and phase every cook, which is an ESTIMATE and
// not a clock. 2E1 measured what that costs: sparse_90 reaches the right period
// and holds it for only 24% of frames, and a shuffle gives a per-frame argmax
// several defensible periods to alternate between. Re-deciding the beat from
// scratch every 16 ms cannot produce a steady pulse no matter how good the
// evidence is.
//
// So this pass owns a phase accumulator that FREE-RUNS at its own period and is
// only nudged by the observation. Two loops, deliberately at different speeds:
//
//   phase loop  (mu_phase)  corrects WHERE the beat falls -- fast, because a
//                           listener notices a beat in the wrong place at once.
//   tempo loop  (mu_tempo)  corrects HOW FAST it runs -- an order of magnitude
//                           slower, because tempo is a property of the music and
//                           a tracker that changes its mind about it every frame
//                           is the failure 2E1 ended with.
//
// The slow tempo loop is what turns an unstable estimate into a usable clock: a
// single bad frame moves the period by 2% of its error and is averaged out,
// while a genuine tempo change still arrives within a few beats.
//
// WHY THE PHASE KEEPS RUNNING WHEN CONFIDENCE DROPS. Stopping would restart the
// beat from an arbitrary place when the signal returns. Free-wheeling holds the
// grid so a quiet bar, a breakdown or a missed onset costs nothing, which is
// what a performer expects. Emission is gated separately -- see below.

#include "common.hlsli"

StructuredBuffer<PS> T  : register(t0);    // tstate, the tempo stage's output
StructuredBuffer<PS> On : register(t1);    // onset ring, for per-hop sample position
RWStructuredBuffer<PS> Out : register(u0); // beats: this pass's OWN ring + state

static const uint ORING = 800u;
static const uint OHDR  = 800u;
// This pass owns `beats` outright: ring 0..511, state and serial in 512.
//
// It was first written to append into the picker's hits ring in `pstate`,
// sharing that serial counter so the harness's serial-keyed dedupe would work
// unchanged. That does not work, and fails silently rather than loudly: two
// passes writing one buffer are ping-ponged onto separate physical sides, so
// this pass's state element read back perfectly through both Trace and its
// control outputs while every write it made to the shared ring and counter was
// discarded each cook by a `commit` reading the picker's side. The symptom was
// a beat count climbing past 23 with not one beat record in the ring.
//
// Beats therefore carry their OWN serial sequence, which is why the harness
// keys records by (lane, serial) instead of by serial alone.
static const uint BRING = 512u;
static const uint BHDR  = 512u;
static const uint BAUX  = 513u;   // circular phase-average phasor
static const uint BEAT_LANE = 3u;
static const float TAU_2PI = 6.283185307;

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x != 0u) return;

    // The ring header, not pstate's, defines how far this pass may advance:
    // sample positions come from the ring, so running past it would emit beats
    // with no timestamp to attach them to.
    PS oh = On[OHDR];
    uint judged = (uint)max(oh.a, 0.0);
    if (judged == 0u) return;

    PS tm = T[0];
    float phaseObs  = saturate(tm.b);
    float conf      = saturate(tm.c);
    float periodObs = tm.d;
    float present   = tm.h;

    PS Q = Out[BHDR];
    float phase  = Q.a;
    float period = Q.b;
    float confS  = Q.d;
    float beats  = Q.g;

    // Cold start, and recovery from a period that never became sane.
    if (period < 1.0) {
        period = clamp(periodObs, 1.0, 1000.0);
        phase  = phaseObs;
        Q.f    = (float)judged;
        if (period < 1.0) { Out[BHDR] = Q; return; }
    }

    uint start  = (uint)max(Q.f, 0.0);
    uint oldest = (judged > ORING) ? (judged - ORING) : 0u;
    start = max(start, oldest);

    // ---- advance the accumulator hop by hop --------------------------------
    // Per hop, not per cook. A cook covers about three hops and a beat lands on
    // one particular hop; advancing per cook would quantise every beat to the
    // cook boundary and add up to 16 ms of jitter to a measurement whose
    // continuity tolerance is a fraction of a beat.
    float inc = 1.0 / max(period, 1.0);
    float pulse = 0.0;
    // Every path that completes a beat cycle without emitting a record is
    // counted. A dropped beat is invisible in any summary statistic -- the
    // tempo stays right, the confidence stays high, and only a continuity score
    // notices -- so the two suppression paths are instrumented separately
    // rather than inferred from the gap between the ref and est beat counts.
    PS dbg = Out[BAUX];
    float dropSig = dbg.d, dropRing = dbg.e, cycles = dbg.f;

    [loop] for (uint gen = start; gen < judged; ++gen) {
        phase += inc;
        if (phase < 1.0) continue;
        phase -= 1.0;
        cycles += 1.0;

        // GATED ON SIGNAL, NOT ON CONFIDENCE. Free-wheeling through a quiet
        // passage should keep the beat; free-wheeling through a noise floor
        // must not manufacture one. This is the exact behaviour 2E2 criterion 2
        // tests, and the exact behaviour cryo_pulse got wrong when it reported
        // 99% confidence at -44 dBFS.
        if (present < 0.5) { dropSig += 1.0; continue; }

        PS s = On[gen % ORING];
        // A beat whose hop is not in the ring has no sample position, and the
        // scorer times beats by sample position. Emitting it with a zero would
        // place it at the start of the file rather than lose it, which is worse.
        if ((uint)s.b != gen + 1u || s.c <= 0.0) { dropRing += 1.0; continue; }

        beats += 1.0;
        PS hr;
        hr.a = (float)BEAT_LANE;
        hr.b = beats;                 // this ring's own serial, 1-based
        // Generation, where an onset record carries hopCount. The two differ by
        // a small constant and the scorer times everything by sample_position,
        // so this stays informational -- but it is the honest number for a beat
        // that was decided on a generation.
        hr.c = (float)gen;
        hr.d = s.c;
        hr.e = 1.0;
        hr.f = (float)gen;
        hr.g = 0.0; hr.h = 0.0;
        Out[((uint)beats - 1u) % BRING] = hr;

        pulse = 1.0;
    }

    // ---- correct against the observation -----------------------------------
    confS = lerp(confS, conf, 0.2);

    // ---- circular average of the phase ERROR -------------------------------
    // The comb re-picks its argmax phase from scratch every cook and on dense
    // material several phases fit almost equally well, so the raw pick jumps
    // around: measured, a standard deviation of 0.256 of a BEAT on dense_140.
    // It has to be smoothed before a loop can use it.
    //
    // SMOOTH THE ERROR, NOT THE OBSERVATION. `phaseObs` is measured backwards
    // from the newest hop, so as the newest hop advances a perfectly stationary
    // beat grid still makes it sweep through a full turn -- it is a rotating
    // quantity by construction and its circular mean is uniform. Averaging it
    // directly was tried and the vector strength sat at 0.15 on EVERY pattern,
    // steady material and dense alike, which is the signature of averaging away
    // a real signal rather than of a noisy one.
    //
    // The difference between the observation and the accumulator is what is
    // stationary while locked, so that is what gets averaged.
    //
    // Averaged AS A PHASOR, not as a number: the error is circular, and an
    // arithmetic mean of +0.49 and -0.49 is 0 when the right answer is +/-0.5.
    //
    // Integrating this error into the PERIOD was also tried and is strictly
    // worse -- with an observation this noisy the integral is a noise amplifier
    // and dense_140's continuity fell from 0.32 to 0.10.
    //
    // The one-hop skew is deliberate: phaseObs describes hop `judged-1` while
    // the accumulator has been advanced through `judged`.
    float errRaw = frac(phaseObs - (phase - inc) + 0.5) - 0.5;

    PS aux = Out[BAUX];
    aux.d = dropSig; aux.e = dropRing; aux.f = cycles;
    float2 pv = float2(aux.a, aux.b);
    float ang = TAU_2PI * errRaw;
    float2 obs = float2(cos(ang), sin(ang));
    pv = (dot(pv, pv) < 1e-8) ? obs : lerp(pv, obs, saturate(phase_smooth));
    aux.a = pv.x; aux.b = pv.y;
    // The phasor's LENGTH is the standard vector strength: 1 when the
    // observation has agreed with the accumulator, falling toward 0 as the two
    // scatter. That is a direct measure of how much the phase reference
    // deserves to be believed, which the peak-to-average confidence does not
    // capture at all.
    float coh = saturate(length(pv));
    aux.c = coh;
    Out[BAUX] = aux;
    float errSm = atan2(pv.y, pv.x) / TAU_2PI;

    // THE GAINS ARE PER BEAT, NOT PER COOK, AND THE DIFFERENCE IS A FACTOR OF
    // ABOUT TWENTY-EIGHT. The correction runs once per cook; a cook covers
    // roughly three hops while a beat spans eighty-odd, so a "gain" of 0.15
    // applied every cook is a loop gain near 3.0 per beat. That is not a
    // slightly-too-fast loop, it is an overdamped one: it parks the accumulator
    // on the observed phase and then RESISTS advancing past it, so the beat rate
    // itself comes out wrong. Measured on dense_140, whose period was correct at
    // 80.9 hops (140 BPM) throughout: 28 phase cycles completed where the period
    // implies 46, with not one beat suppressed by either gate.
    //
    // It is also a correctness bug beyond this corpus. Cooks-per-beat depends on
    // frame rate, so the unnormalised loop tracked differently at 60 fps than at
    // 30, and differently again whenever the graph got heavier.
    //
    // Scaling by the beats actually elapsed this cook makes both gains mean what
    // their names say -- fraction of the error corrected per BEAT -- and makes
    // the loop independent of cook rate.
    float advanced = saturate((float)(judged - start) / max(period, 1.0));

    bool locked = (conf >= lock_conf) && (present >= 0.5);
    if (locked) {
        // Signed phase error in [-0.5, 0.5), circularly smoothed above, so a
        // beat 1% late and one 99% early are the same small correction rather
        // than opposite full-beat lurches.
        float err = errSm;

        // THE CORRECTION MUST NOT CROSS THE WRAP. Beats are emitted by the
        // accumulator crossing 1.0 inside the hop loop; a correction applied
        // out here that carries phase over either end adds or removes a beat
        // without going through that path at all.
        //
        //   forward  (0.98 -> 1.04 -> frac 0.04): the beat for this cycle never
        //            fired and now never will -- a silent drop.
        //   backward (0.02 -> -0.04 -> frac 0.96): the beat fired moments ago
        //            and the next hop fires it again -- a duplicate.
        //
        // Both are rare and both are fatal to a continuity score, which is a
        // LONGEST RUN and so is destroyed by isolated events rather than by
        // average error. Measured on the emitted train before this clamp:
        // four_on_floor_128 ran 10.3% of intervals at 2x the period and 5.1% at
        // one to four HOPS, and dense_140 emitted 52 beats against 47 real ones
        // while its reported BPM stayed correct at 140.3. CMLc was 0.21 and 0.05
        // against a 0.75 criterion.
        //
        // Clamping instead of wrapping keeps exactly one beat per cycle: a
        // forward-crossing correction parks phase just below the boundary so the
        // beat fires on the very next hop through the normal path, and a
        // backward-crossing one parks it at zero so the beat that just fired is
        // not fired twice. The unapplied remainder is a few percent of a beat and
        // is corrected on the following cooks, so accuracy is unchanged -- only
        // the beat train's integrity is restored.
        phase = clamp(phase + mu_phase * err * advanced, 0.0, 0.999999);
        // The tempo loop tracks the comb's own period rather than integrating
        // the phase error. Tried both: with an observation whose phase scatters
        // by a quarter of a beat, an integral term is a noise amplifier, and it
        // cost dense_140 two thirds of its continuity. The period is measured
        // directly and well; the phase is what needed the smoothing.
        if (periodObs > 1.0) period += mu_tempo * (periodObs - period) * advanced;
    }

    Q.a = frac(phase + 1.0);
    Q.b = period;
    Q.c = (period > 1.0) ? (60.0 * max(oh.c, 1.0) / period) : 0.0;   // locked BPM
    Q.d = confS;
    Q.e = locked ? 0.0 : 1.0;      // free-wheeling
    Q.f = (float)judged;
    Q.g = beats;
    Q.h = pulse;
    Out[BHDR] = Q;
}
