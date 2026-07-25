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
RWStructuredBuffer<PS> Out : register(u0);

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
            float o = Lane[slot * MAXLANES + lane].flux;
            float oPrev = Lane[prevSlot * MAXLANES + lane].flux;
            float oNext = Lane[nextSlot * MAXLANES + lane].flux;

            // ---- moving median over the last M hops ----------------------
            float w[32];
            [unroll] for (uint z = 0u; z < 32u; ++z) w[z] = 0.0;

            uint cnt = 0u;
            [loop] for (uint m = 0u; m < M; ++m) {
                if (m > gen) break;
                uint s2 = (gen - m) % capacity;
                w[cnt] = Lane[s2 * MAXLANES + lane].flux;
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

            float strength = 0.0;
            if (!gated && isPeak && refOk) {
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
            PS tr;
            tr.a = o; tr.b = thr; tr.c = (strength > 0.0) ? 1.0 : 0.0;
            tr.d = Lane[slot * MAXLANES + lane].spos;
            tr.e = 0.0; tr.f = 0.0; tr.g = 0.0; tr.h = 0.0;
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
