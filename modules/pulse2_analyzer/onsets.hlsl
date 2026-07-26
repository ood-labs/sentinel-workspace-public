// 2E1 — onset history ring.
//
// The comb filter needs several seconds of continuous onset envelope, but
// `lstate` only holds HOPS (64) hops, 341 ms: less than one beat at any usual
// tempo. This pass copies each newly-judged hop into a long persistent ring so
// the tempo stage has ~4.27 s of history to correlate against.
//
// WHY THE DETECTIONS AND NOT THE ENVELOPE.
//
// This pass originally appended the continuous per-lane flux, on the standard
// reasoning that beat tracking correlates against the detection function and
// that a missed snare is a hole in the evidence while a weak peak is not. That
// is sound for onset detection and MEASURABLY WRONG for tempo here.
//
// The flux envelope never falls to zero between onsets, so a candidate period
// collects background from the gaps it is supposed to be penalised for. On
// breakbeat_170 -- whose hats occupy every even 16th, so period 4 (170 BPM) and
// period 6 (113 BPM, a dotted quarter) both land on an onset every pulse -- the
// gap energy was enough to make the tracker sit on 113 for 90% of frames with a
// 0.3 BPM spread: confidently, stably wrong. Rebuilt from the picker's accepted
// onsets it resolves 168.7.
//
// Measured offline against the detector's OWN accepted hits (not ground truth,
// which would hide every onset the picker misses) across the eight non-held-out
// patterns with a recoverable tempo: picked onsets score 8/8 on metrical level
// where the flux envelope scored 5/8.
//
// The cost is real and is accepted knowingly: a missed onset is now a hole. It
// is affordable because the picker's per-lane F1 is 0.91/0.78/0.97, so holes
// are sparse, and because the comb averages over several beats.
//
// One thread and a catch-up loop, the same discipline as pick.hlsl: hops arrive
// at 187.5 Hz and cooks run near 60 Hz, so roughly three hops land per cook and
// a "write only the newest" design would silently drop two thirds of them.

#include "common.hlsli"

StructuredBuffer<PS> P    : register(t0);   // pstate_prev, stable snapshot
StructuredBuffer<LS> Lane : register(t1);   // lstate, per-hop per-lane flux
RWStructuredBuffer<PS> On : register(u0);   // the ring

// 800 hops at 187.5 hops/s = 4.267 s. Slot 800 is the header, so the ring's own
// slots are never displaced by bookkeeping.
static const uint ORING = 800u;
static const uint OHDR  = 800u;

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x != 0u) return;

    PS H = P[HDR_H];
    uint judged = (uint)max(H.a, 0.0);      // lastJudge + 1, from the picker
    if (judged == 0u) return;

    uint capacity = max(_Data0_HopCapacity, 1u);

    PS h = On[OHDR];
    uint written = (uint)max(h.a, 0.0);     // next generation still to append

    // Two independent floors on where catch-up may start:
    //   - the ring only holds ORING hops, so anything older is unreachable;
    //   - `lstate` only holds `capacity` hops, so anything older no longer has
    //     a flux value to copy. Falling behind that far means the appended
    //     envelope would be built from unrelated slots a full lap of the
    //     producer ring away, which is worse than a gap.
    uint oldestRing = (judged > ORING)    ? (judged - ORING)    : 0u;
    uint oldestFlux = (judged > capacity) ? (judged - capacity) : 0u;
    uint start = max(max(written, oldestRing), oldestFlux);

    // Pass 1: stamp the newly-judged hops as EMPTY. Every hop must carry its own
    // generation stamp even when nothing was detected in it, because a silent
    // hop is evidence -- it is the gap a wrong period has to be penalised for --
    // and an unstamped slot is indistinguishable from a lap-old one downstream.
    // `spos` still comes from lstate so the Onsets port stays inspectable per
    // hop rather than only where an onset happened to land.
    [loop] for (uint gen = start; gen < judged; ++gen) {
        uint ls = (gen % capacity) * MAXLANES;

        float spos = 0.0;
        [loop] for (uint ln = 0u; ln < NLANES; ++ln) {
            LS L = Lane[ls + ln];
            // The stamp guard: a slot whose generation is not this hop holds an
            // unrelated frame and must not contribute.
            if ((uint)L.gen != gen) continue;
            spos = max(spos, L.spos);
        }

        PS v;
        v.a = 0.0;
        v.b = (float)(gen + 1u);   // 1-based stamp; 0 means never written
        v.c = spos;
        v.d = 0.0; v.e = 0.0; v.f = 0.0; v.g = 0.0; v.h = 0.0;
        On[gen % ORING] = v;
    }

    // Pass 2: deposit the picker's accepted onsets into the hops just stamped.
    //
    // The hits ring is scanned ONCE and each hit is written to the slot its own
    // hop names, rather than rescanning all HITCAP records for every hop being
    // caught up. After a long stall the catch-up range reaches ORING hops, and
    // the per-hop form would be 800 * 512 iterations on this single thread --
    // a frame hitch exactly when the graph is already behind.
    //
    // EACH ACCEPTED ONSET COUNTS 1.0, not its detection strength.
    //
    // Depositing `strength` was tried first and is measurably worse: live it
    // left breakbeat_170 at 113.2 where the unit-weight study predicted 168.7.
    // Strength is saturate((o - thr) / thr), so it re-imports the amplitude
    // hierarchy that the comb does not want -- weighting an ideal onset train
    // by true amplitude moves breakbeat_170's 170-vs-113 score ratio from 0.853
    // to 0.750, i.e. FURTHER from the correct answer. Tempo is carried by WHERE
    // onsets fall, not how loud they are, and the loud lanes are also the ones
    // whose syncopation supports the wrong period here.
    //
    // It also matches what the offline study actually measured: the Hits export
    // declares no strength field, so that 8/8 result was unit-weighted, and
    // shipping strength instead would have been a different algorithm from the
    // one the evidence endorsed.
    //
    // Onsets still ACCUMULATE. A kick and a snare landing in the same hop are a
    // stronger beat cue than either alone, and overwriting would make a
    // coincident hit indistinguishable from a bare kick.
    //
    // Keyed on hr.f, the PRODUCER GENERATION, not hr.c. hr.c is hop_index, the
    // 2A1 export contract, which counts hops the picker has processed and is a
    // different number from the generation this ring is indexed by; the two
    // diverge whenever the picker's catch-up clamps to its oldest reachable
    // hop. Using hop_index here matched nothing at all and left the ring empty,
    // which surfaced not as an error but as a flat comb pinned to BPM_MIN.
    //
    // Records outside [start, judged) are skipped, which also covers stale
    // ones: generations are monotonic across playthroughs (the harness
    // watermarks on onset_serial precisely because sample_position is not), so
    // a previous run's records are always older than `start`. Never-written
    // slots read as generation 0, strength 0, and contribute nothing even when
    // `start` is 0.
    [loop] for (uint i = 0u; i < HITCAP; ++i) {
        PS hr = P[HITS_BASE + i];
        uint hgen = (uint)max(hr.f, 0.0);
        if (hgen < start || hgen >= judged) continue;
        On[hgen % ORING].a += 1.0;
    }

    h.a = (float)judged;
    h.b = (float)((judged > 0u) ? ((judged - 1u) % ORING) : 0u);
    h.c = H.d;                     // hopsPerSec, carried for the tempo stage
    h.d = (float)start;            // for diagnosing a catch-up gap
    On[OHDR] = h;
}
