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
    //
    // Gated on the OBSERVATION being sane, not on the clamped result. Clamping
    // with a floor of 1.0 and then testing `period < 1.0` is dead code, and the
    // case it was meant to catch is real: the comb publishes a period of zero on
    // the first cooks while its ring is still empty, which clamps to 1.0 and
    // means one beat PER HOP -- roughly 187 a second -- flooding the 512-slot
    // ring and the beat counter until the tempo loop drags it back.
    if (period < 1.0) {
        if (periodObs <= 1.0) { Q.f = (float)judged; Out[BHDR] = Q; return; }
        period = clamp(periodObs, 1.0, 1000.0);
        phase  = phaseObs;
        Q.f    = (float)judged;
    }

    uint start  = (uint)max(Q.f, 0.0);
    uint oldest = (judged > ORING) ? (judged - ORING) : 0u;
    start = max(start, oldest);
    // `beats` is persistent and `judged` is not derived from it, so an
    // asymmetric clear can leave a resume point ahead of the producer. Every
    // span below is UNSIGNED: one hop of that and `judged - start` wraps to
    // ~4.3e9, saturating both loop gains, and `Q.f` latches the stale value so
    // the accumulator stalls for good rather than recovering.
    start = min(start, judged);

    // ---- onset-anchored emission -------------------------------------------
    // An emitted beat is timed by the hop its cycle landed on, and that hop
    // inherits every bit of scatter in the comb's phase argmax -- measured as a
    // placement residual that is neither a fixed time nor a fixed phase offset
    // (+0.154 beat on four_on_floor_128, -0.084 on syncopated_funk_105) and that
    // moved 56 -> 72 ms between two identical runs. The picked onsets do not
    // have that problem: they sit +8.2 ms from ground truth with a kick F1 of
    // 0.976. So a beat is snapped onto the nearest picked onset and inherits the
    // picker's accuracy instead of the argmax's scatter.
    //
    // THE SEARCH HAS TO SEE BOTH SIDES, WHICH COSTS LATENCY. Beats are decided
    // for generations up to `judged`, so an onset LATER than the beat has not
    // been stamped yet -- searching only what exists would snap exclusively
    // backwards and replace a symmetric scatter with a systematic early bias.
    // Holding the decision back by the window width makes the window whole.
    //
    // The cost is real and is the reason this is a parameter: beat records are
    // published `win` hops later in wall-clock than they would otherwise be.
    // Their sample positions are unaffected -- the timestamp gets MORE accurate,
    // not later -- so anything scoring or rendering by sample position gains,
    // and only a live pulse used as an instantaneous trigger pays.
    int win = (int)clamp(beat_snap * period, 0.0, 60.0);
    uint limit = (judged > (uint)win) ? (judged - (uint)win) : 0u;
    limit = max(limit, start);

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

    [loop] for (uint gen = start; gen < limit; ++gen) {
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

        // Snap to the NEAREST picked onset inside the window. Nearest rather
        // than strongest: the accumulator already decided which beat this is,
        // and the only question left is which hop timestamps it best.
        //
        // A miss is not a failure. With no onset in the window the beat keeps
        // the accumulator's own hop, which is what free-wheeling through a
        // quiet bar or a syncopated gap has to do.
        uint bestG = gen;
        int  bestD = win + 1;
        [loop] for (int k = -win; k <= win; ++k) {
            int g2 = (int)gen + k;
            if (g2 < 0 || (uint)g2 >= judged) continue;
            uint gu = (uint)g2;
            PS c = On[gu % ORING];
            if ((uint)c.b != gu + 1u) continue;   // stale or unwritten hop
            if (c.a <= 0.0 || c.c <= 0.0) continue;   // no onset landed here
            int dd = abs(k);
            if (dd < bestD) { bestD = dd; bestG = gu; }
        }
        PS anchor = On[bestG % ORING];

        beats += 1.0;
        PS hr;
        hr.a = (float)BEAT_LANE;
        hr.b = beats;                 // this ring's own serial, 1-based
        // The hop the TIMESTAMP came from, which after snapping is the onset's
        // hop rather than the accumulator's. The decision generation is kept
        // separately in .f so the two stay distinguishable.
        hr.c = (float)bestG;
        hr.d = anchor.c;
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
    // The skew is deliberate and must track the snap window. `phaseObs`
    // describes hop `judged-1`, while the accumulator has only been advanced to
    // `limit` so that the snap search can see both sides of a beat. Comparing
    // the two without carrying the accumulator forward across that gap would
    // feed the loop a standing error of the window's width and make the beat
    // clock chase its own emission latency.
    float skew = (float)(int)(judged - 1u - limit);
    float errRaw = frac(phaseObs - (phase + skew * inc) + 0.5) - 0.5;

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
    float errSm = atan2(pv.y, pv.x) / TAU_2PI;

    // Consecutive cooks whose period observation disagreed with the tracked
    // period. Lives in the aux record because it has to survive the cook.
    float outliers = aux.g;

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
    // The span the accumulator ACTUALLY advanced, which is start -> limit, not
    // start -> judged. The two are equal only while the snap window is zero.
    // With a window open, `start` is the previous cook's `limit`, so
    // `judged - start` is about three hops plus the whole window -- at a window
    // of 32 hops that inflates both loop gains by an order of magnitude every
    // cook, which is a fair description of a loop that settles with a standing
    // phase error.
    float advanced = saturate((float)(limit - start) / max(period, 1.0));

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
        //
        // OUTLIERS ARE REJECTED, NOT AVERAGED. The comb intermittently picks a
        // metrical RELATIVE rather than the beat -- on four_on_floor_128 the
        // published period is 88.2 hops most of the time and jumps to 131.8 (a
        // 3:2 dotted quarter) on roughly one cook in six. An exponential tracker
        // converges to the MEAN of its input, so those excursions pulled the
        // tracked period to 93.6 against a true 88.2: six percent slow, which
        // drifts a quarter of a beat every four or five beats and is more than
        // the continuity tolerance allows. The period looked healthy in every
        // median-based summary, which is why this survived so long.
        //
        // A jump to a different metrical level is not weak evidence about this
        // tempo, it is evidence about a different one, and averaging the two
        // produces a number that describes neither.
        if (periodObs > 1.0) {
            float rel = abs(periodObs - period) / max(period, 1e-3);
            if (rel <= tempo_reject) {
                period += mu_tempo * (periodObs - period) * advanced;
                // DECREMENTED, NOT RESET. A reset makes the rejection a trap:
                // the loop only has to be fed one agreeing sample now and then
                // to hold a wrong period forever, and syncopated_funk_105 did
                // exactly that -- parked at 80.3 hops while the comb reported
                // 107.2 for the majority of the run, with the disagreement
                // counter climbing to 146 and being knocked back to zero before
                // it could ever re-acquire. Counting net evidence instead means
                // a genuine minority of outliers still decays away (a one-in-six
                // excursion nets -4 every six cooks and never trips) while a
                // sustained majority accumulates and wins.
                outliers = max(outliers - 1.0, 0.0);
            } else {
                // Held, not discarded outright. A genuine tempo change also
                // reads as a sustained outlier, so once the observation has
                // disagreed for long enough to be a fact rather than a glitch,
                // the loop re-acquires. The window travels with the period, so a
                // ramp stays inside it and is tracked normally.
                outliers += 1.0;
                if (outliers > tempo_reacquire_cooks) {
                    period = periodObs;
                    outliers = 0.0;
                }
            }
        }
    }

    aux.g = outliers;
    Out[BAUX] = aux;

    Q.a = frac(phase + 1.0);
    Q.b = period;
    Q.c = (period > 1.0) ? (60.0 * max(oh.c, 1.0) / period) : 0.0;   // locked BPM
    Q.d = confS;
    Q.e = locked ? 0.0 : 1.0;      // free-wheeling
    // Resume where the accumulator actually stopped, not at `judged` -- the held
    // back hops have not been advanced through and must not be skipped.
    Q.f = (float)limit;
    Q.g = beats;
    Q.h = pulse;
    Out[BHDR] = Q;
}
