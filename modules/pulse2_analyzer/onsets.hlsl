// 2E1 — onset history ring.
//
// The comb filter needs several seconds of continuous onset envelope, but
// `lstate` only holds HOPS (64) hops, 341 ms: less than one beat at any usual
// tempo. This pass copies each newly-judged hop into a long persistent ring so
// the tempo stage has ~4.27 s of history to correlate against.
//
// WHY THE ENVELOPE AND NOT THE DETECTIONS. Beat tracking correlates against the
// continuous onset detection function, not the discrete accepted onsets. The
// picker's output is already thresholded and refractory-limited, so a missed
// snare is a hole in the evidence; the raw per-lane flux still carries the
// event that the picker declined to call. The comb filter is far more tolerant
// of a weak peak than of an absent one.
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

    [loop] for (uint gen = start; gen < judged; ++gen) {
        uint ls = (gen % capacity) * MAXLANES;

        // Summed, not maxed. A kick and a snare landing together is a STRONGER
        // beat cue than either alone, and a max would throw that away and make
        // a coincident hit indistinguishable from a bare kick.
        float o = 0.0;
        float spos = 0.0;
        [loop] for (uint ln = 0u; ln < NLANES; ++ln) {
            LS L = Lane[ls + ln];
            // The stamp guard: a slot whose generation is not this hop holds an
            // unrelated frame and must not contribute.
            if ((uint)L.gen != gen) continue;
            o += max(L.flux, 0.0);
            spos = max(spos, L.spos);
        }

        PS v;
        v.a = o;
        v.b = (float)(gen + 1u);   // 1-based stamp; 0 means never written
        v.c = spos;
        v.d = 0.0; v.e = 0.0; v.f = 0.0; v.g = 0.0; v.h = 0.0;
        On[gen % ORING] = v;
    }

    h.a = (float)judged;
    h.b = (float)((judged > 0u) ? ((judged - 1u) % ORING) : 0u);
    h.c = H.d;                     // hopsPerSec, carried for the tempo stage
    h.d = (float)start;            // for diagnosing a catch-up gap
    On[OHDR] = h;
}
