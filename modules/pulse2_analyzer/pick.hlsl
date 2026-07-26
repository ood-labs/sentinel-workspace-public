// Pass C — PEAK PICKING. Single thread, bounded to at most 16 lanes.
//
//   bg[n]  = moving median of O over a fixed window   (robust background)
//   thr[n] = alpha + lambda * bg[n]
//   accept if O[n] > thr[n], O[n] is a local maximum using a ONE-HOP
//   (5.33 ms) lookahead, and the per-lane refractory has expired.
//
// A median is used rather than a mean so a single loud transient inside the
// window cannot lift the threshold enough to swallow the next hit.
//
// NOTE ON RATES: every rate here is per ANALYSIS HOP, not per cook. A hop is a
// fixed 5.33 ms of audio regardless of how often the module cooks, so refractory
// and envelope release are cook-rate independent by construction rather than by
// _DeltaTime scaling. This is what criterion 4 tests.

#include "common.hlsli"

StructuredBuffer<LS> Lane : register(t0);
StructuredBuffer<PS> Prev : register(t1);
// Bound only to reach the producer header the whitening pass verified; the
// spectrum itself is not used here.
StructuredBuffer<SP> Spec : register(t3);
// 2D features, computed in the parallel `features` pass. Read-only here.
StructuredBuffer<FS> Feat : register(t4);
RWStructuredBuffer<PS> Out : register(u0);

// ---- lateral inhibition (2C3) ---------------------------------------------
//
// The 2C1 snare lane has recall 1.000 but precision 0.31-0.34: on
// four_on_floor_128 it emits 61 detections for 21 true snares, because a kick's
// broadband click deposits real energy across 200-2400 Hz and the snare region
// reduces it as a genuine onset. No threshold fixes this — the event IS there in
// that band; it just belongs to another instrument.
//
// So instead of a per-lane threshold, lanes COMPETE. Each lane subtracts a share
// of its strongest simultaneous rival:
//
//     O'_i[n] = max(0, O_i[n] - g * max_{j != i} O_j[n])
//
// A kick transient raises the kick lane far above the snare lane's leakage, so
// the snare's copy is cancelled while a real snare — which dominates its own
// band — survives. One knob, not a per-pair matrix, because six weights tuned on
// eight patterns would fit the corpus rather than the physics.
//
// The FIRST version of this was instantaneous: it subtracted a share of the
// rival lanes' flux AT THE SAME HOP. Measured on `hats_under_loud_kick_150`
// (zero true snares, so every snare firing is by construction leakage), that
// removed nothing -- snare FP went 284 -> 288 -> 285 -> 279 across
// g = 0 -> 0.15 -> 0.3 -> 0.5. `diag_inhibit.py` shows why:
//
//   at the hops where the snare falsely fires, kick flux is 0.0021 (median)
//   against snare flux 0.1955 -- the rival is SILENT, and the gain needed to
//   suppress would be 8.8, far outside [0,1].
//
//   but within +/-8 hops the kick reaches 0.322, and the distance from each
//   snare FP to the nearest active kick hop is median 8 hops with p25 = p75 = 8.
//
// So the interference is not simultaneous, it is DELAYED by a fixed ~43 ms: the
// kick's decay sweeping up into 200-2400 Hz well after its own transient has
// passed. Flux spikes at the transient, so a same-hop comparison structurally
// cannot see it.
//
// The fix is forward masking, which is also what real hearing does -- a loud
// transient masks quieter events for ~100 ms AFTER it, not just during it:
//
//     R_i[n] = max_{d=0..W} ( exp(-d/tau) * max_{j!=i} O_j[n-d] )
//     O'_i[n] = max(0, O_i[n] - g * R_i[n])
//
// Stateless: the Lane ring already holds 64 hops (341 ms), so the window is
// read directly rather than carried as persistent envelope state.
//
// TWO DELIBERATE CHOICES:
//
// 1. The moving-median BACKGROUND is computed from RAW flux, never from O'.
//    The first version routed both through the same helper "so background and
//    peak agree", which was self-defeating: thr = alpha + lambda*median(O')
//    falls with the signal, so a near-uniform subtraction cancels out of
//    (o - thr) and changes almost nothing. The threshold now stays exactly the
//    2C1 threshold and the inhibited signal has to clear that unchanged bar.
//
// 2. One gain and one time constant, not a per-pair matrix. Six weights tuned
//    on eight patterns would fit the corpus rather than the physics.
//
// Default gain 0.0 = disabled = bit-identical to the scored 2C1 detector
// (verified: every per-lane delta +0.000 across 11 patterns, aggregate 0.7972).
static const uint INHIB_MAXW = 16u;   // 85 ms, spans the measured 43 ms lag

float lane_raw(uint slot, uint lane) {
    return Lane[slot * MAXLANES + lane].flux;
}

// Decaying envelope of the strongest RIVAL lane over the preceding window.
float rival_env(uint gen, uint lane, uint capacity, uint oldest) {
    if (inhibit_gain <= 0.0) return 0.0;
    float tau = max(inhibit_tau_hops, 0.5);
    uint W = min((uint)ceil(3.0 * tau), INHIB_MAXW);

    float R = 0.0;
    [loop] for (uint d = 0u; d <= W; ++d) {
        if (d > gen) break;
        uint g2 = gen - d;
        if (g2 < oldest) break;
        uint s2 = g2 % capacity;

        // DIRECTIONAL: only LOWER-frequency lanes may mask this one.
        //
        // Symmetric masking was measured and rejected. It reaches the target
        // (snare FP 284 -> 174) but destroys the kick lane doing it: hat flux
        // p99 is 1.0359 against kick 0.4984, and hats at 150 BPM fire
        // continuously, so at tau=12 the hat envelope never decays and lays a
        // permanent masking floor over the sparse kick lane. Kick recall fell
        // 0.948 -> 0.063.
        //
        // The measured leak is one-way and cannot run the other way: hats
        // occupy 2400-20000 Hz and have NO energy in the kick's 25-200 Hz
        // region, so a hat physically cannot mask a kick. Restricting rivals to
        // j < lane makes lane 0 unmaskable by construction, which preserves
        // kick recall exactly rather than by tuning.
        //
        // ASSUMPTION: regions are authored in ascending frequency order
        // (0 kick, 1 snare, 2 hat), which is the 2C1 seed contract. Reordering
        // regions to be non-monotonic in frequency would invalidate this.
        float rv = 0.0;
        [loop] for (uint j = 0u; j < lane; ++j) {
            rv = max(rv, lane_raw(s2, j));
        }
        R = max(R, exp(-(float)d / tau) * rv);
    }
    return R;
}

float lane_flux(uint gen, uint slot, uint lane, uint capacity, uint oldest) {
    float o = lane_raw(slot, lane);
    if (inhibit_gain <= 0.0) return o;
    return max(0.0, o - inhibit_gain * rival_env(gen, lane, capacity, oldest));
}

// ---- 2D weighted decision --------------------------------------------------
//
// A linear score over the parallel pass's feature vector:
//
//     s = bias + w_cent*cent + w_flat*flatness + w_decay*decay + w_energy*energy
//     keep the detection when s > 0
//
// This is what replaces bare flux thresholding, and it is the only thing that
// CAN work here: 2C3 proved the kick's decay is a real onset in the snare's
// band, equal in level and offset in time, so it differs from a snare only in
// timbre.
//
// The weights are MEASURED, not chosen. `diag_features.py` collects the feature
// vector at every snare firing on the eight non-held-out patterns and labels it
// against ground truth; `fit_classifier.py` fits this model to that data. On
// 115 true / 255 false firings the unclassified lane scores F1 0.474 and the
// fitted decision 0.766. Re-run both to change these numbers; do not hand-edit
// them, and do not fit them on a held-out pattern.
//
// Mode 0 = Off reproduces the scored 2C1 detector exactly.
float classify_score(FS fv) {
    return classify_bias
         + w_cent   * fv.cent
         + w_flat   * fv.flatness
         + w_decay  * fv.decay
         + w_energy * fv.energy
         + w_centD  * fv.centD
         + w_flatD  * fv.flatD;
}

// Applies to the snare lane only at mode 1. The weights were fitted on snare
// firings, so applying them to kick or hat would be extrapolation, not
// generalisation -- those lanes already score 0.91 and 0.96 and have nothing to
// gain and everything to lose. Mode 2 exists to TEST that claim, not to be a
// default.
bool classify_ok(uint lane, FS fv) {
    if (classify_mode < 0.5) return true;
    bool applies = (classify_mode < 1.5) ? (lane == 1u) : true;
    if (!applies) return true;
    return classify_score(fv) > 0.0;
}

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    // pstate is persistent and commit mirrors it into pstate_prev, so there is
    // no full-buffer copy here: a 1552-element copy on ONE thread every cook
    // would dominate this node's frame budget.
    PS H = Prev[HDR_H];
    PS C = Prev[HDR_C];
    PS E = Prev[HDR_E];

    uint vcount = min(_Data0_ValueCount, NBINS);
    if (vcount == 0u) return;
    uint latest = _Data0_Generation;
    if (latest == 0u) return;
    uint capacity = max(_Data0_HopCapacity, 1u);

    // Hop rate comes from the header the whitening pass captured off a VERIFIED
    // slot, never from _Data0[0]. Element 0 was measured returning zeros, and
    // the max(x, 1u) guards then yield hopsPerSec = 1.0, which shrinks the
    // refractory from ~10 hops to 0.055 and lets every lane retrigger on
    // consecutive hops. Any validated slot carries the same session constants,
    // so the newest one is used and a wild value keeps the previous state.
    float hopsPerSec = hdr_sample_rate(Spec, latest % capacity)
                     / hdr_hop_size(Spec, latest % capacity);
    if (!(hopsPerSec > 1.5)) return;
    float hopDt = 1.0 / max(hopsPerSec, 1e-3);

    uint cursor = (uint)max(H.a, 0.0);
    uint oldest = (latest >= capacity) ? (latest - capacity + 1u) : 0u;
    uint start = max(cursor, oldest);

    float hopCount = H.b;

    // Adaptive detectors manufacture confident onsets on a noise floor, so gate
    // on the engine's own capture level rather than on our normalised energy,
    // which by construction cannot tell noise from music.
    //
    // The level output is instantaneous and measurably drops to exactly 0.0
    // between transients even on continuous material, so comparing it directly
    // makes the gate chatter and silently drop hops. Hold it open for
    // gate_hold_s after the last above-floor reading: brief dips stay open, a
    // real noise floor or silence still closes it and STAYS closed, which is
    // the condition 2E2 tests.
    float hold = H.g;
    if (gate_level >= signal_floor) hold = gate_hold_s;
    bool gated = (hold <= 0.0);
    H.h = gated ? 0.0 : 1.0;

    uint M = (uint)clamp(median_window, 4.0, 32.0);
    float refHops = refractory_s * hopsPerSec;
    float relK = exp(-hopDt / 0.16);

    // One-hop lookahead: hop n can only be judged once n+1 exists, so stop one
    // short of the newest generation and leave it for the next cook.
    uint lastJudge = (latest >= 1u) ? (latest - 1u) : 0u;

    [loop] for (uint gen = start; gen <= lastJudge; ++gen) {
        uint slot = gen % capacity;
        uint prevSlot = (gen == 0u) ? slot : ((gen - 1u) % capacity);
        uint nextSlot = (gen + 1u) % capacity;

        [loop] for (uint lane = 0u; lane < NLANES; ++lane) {
            float o = lane_flux(gen, slot, lane, capacity, oldest);
            float oPrev = lane_flux((gen == 0u) ? gen : (gen - 1u),
                                    prevSlot, lane, capacity, oldest);
            float oNext = lane_flux(gen + 1u, nextSlot, lane, capacity, oldest);

            // ---- moving median over the last M hops ----------------------
            float w[32];
            [unroll] for (uint z = 0u; z < 32u; ++z) w[z] = 0.0;

            uint cnt = 0u;
            [loop] for (uint m = 0u; m < M; ++m) {
                if (m > gen) break;
                uint s2 = (gen - m) % capacity;
                // RAW, not inhibited -- see choice (1) above. This keeps thr
                // exactly the 2C1 threshold instead of letting it sag with the
                // signal and cancel the inhibition out.
                w[cnt] = lane_raw(s2, lane);
                cnt++;
            }
            // insertion sort, bounded by M <= 32
            [loop] for (uint a = 1u; a < cnt; ++a) {
                float key = w[a];
                uint b = a;
                [loop] while (b > 0u && w[b - 1u] > key) { w[b] = w[b - 1u]; b--; }
                w[b] = key;
            }
            float bg = (cnt == 0u) ? 0.0 : w[cnt / 2u];

            float thr = pick_alpha + pick_lambda * bg;

            bool isPeak = (o > thr) && (o >= oPrev) && (o >= oNext);
            float lastHop = (lane == 0u) ? E.e : ((lane == 1u) ? E.f : E.g);
            bool refOk = (hopCount - lastHop) > refHops;

            // The 2D verdict. Deliberately gates ACCEPTANCE only, and does not
            // touch the refractory: a rejected candidate must not consume the
            // lane's refractory window, or suppressing one false positive would
            // block the real onset arriving a few hops later.
            FS fv = Feat[slot * MAXLANES + lane];
            bool classOk = classify_ok(lane, fv);

            float strength = 0.0;
            if (!gated && isPeak && refOk && classOk) {
                strength = saturate((o - thr) / max(thr, 1e-4));
                if (lane == 0u) { E.e = hopCount; C.a += 1.0; }
                else if (lane == 1u) { E.f = hopCount; C.b += 1.0; }
                else { E.g = hopCount; C.c += 1.0; }
                C.d += 1.0;

                // ---- Hits export (2A1 contract) --------------------------
                C.e += 1.0;
                PS hr;
                hr.a = (float)lane;
                hr.b = C.e;
                hr.c = hopCount;
                hr.d = Lane[slot * MAXLANES + lane].spos;
                hr.e = strength;
                hr.f = 0.0; hr.g = 0.0; hr.h = 0.0;
                Out[HITS_BASE + (((uint)C.e - 1u) % HITCAP)] = hr;
            }

            // Record the trace so the preview shows the SAME threshold the
            // picker used, rather than a second implementation that could drift.
            // The 2D feature vector rides along in the spare fields: it is what
            // the console renders as the per-hit verdict, and what the offline
            // separability study reads, so display, study and decision are all
            // looking at one set of numbers.
            // A candidate is a hop the picker WOULD have fired on if the
            // classifier had not vetoed it: past threshold, a local maximum, and
            // clear of the refractory. Tracing it is what lets the console show
            // what the verdict SUPPRESSED rather than only what it passed --
            // without it, a classifier doing nothing and a classifier rejecting
            // everything look identical on screen.
            //
            // Encoded as -1, not 2, so every existing reader that tests
            // `f2 > 0.5` (the console's firing flash, diag_features.py) keeps
            // meaning exactly "fired" and cannot silently start counting
            // rejections as detections.
            bool candidate = (!gated && isPeak && refOk);

            PS tr;
            tr.a = o; tr.b = thr;
            tr.c = (strength > 0.0) ? 1.0 : (candidate ? -1.0 : 0.0);
            tr.d = Lane[slot * MAXLANES + lane].spos;
            tr.e = fv.cent; tr.f = fv.flatness; tr.g = fv.decay;
            // The verdict itself, so the console renders the SAME number the
            // picker decided on rather than recomputing it from the weights and
            // risking a display that disagrees with the detector.
            tr.h = classify_score(fv);
            Out[trace_index(gen, lane)] = tr;

            // Envelopes: instant attack, per-hop release.
            if (lane == 0u) E.a = max(E.a * relK, strength);
            else if (lane == 1u) E.b = max(E.b * relK, strength);
            else E.c = max(E.c * relK, strength);
        }

        // Per-hop decay of the gate hold: a fixed 5.33 ms of audio per step,
        // so this is cook-rate independent by construction.
        hold = max(hold - hopDt, 0.0);
        gated = (hold <= 0.0);
        H.h = gated ? 0.0 : 1.0;

        hopCount += 1.0;
    }

    H.g = hold;
    H.a = (float)(lastJudge + 1u);
    H.b = hopCount;
    H.c = (float)latest;
    H.d = hopsPerSec;
    H.e = hdr_sample_rate(Spec, latest % capacity);
    H.f = hdr_hop_size(Spec, latest % capacity);

    Out[HDR_H] = H;
    Out[HDR_C] = C;
    Out[HDR_E] = E;
}
