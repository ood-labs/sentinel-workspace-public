// Pass B — SUPERFLUX.
//
//   D[n,k] = max(0, Y[n,k] - max_{m in [-2,2]} Y[n-1,k+m])
//
// The max-filtered lookback over +/-2 bins is what makes this SuperFlux rather
// than plain spectral flux: it suppresses the flux a vibrato or a slight pitch
// drift would otherwise produce, because a partial sliding by a bin or two
// still finds a large neighbour in the previous frame.
//
// Reads ONLY the completed buffer written by pass A. A fused pass would have
// thread k read Y[n-1, k+/-2] produced by OTHER threads, crossing thread-group
// boundaries at four seams (k = 63/64, 127/128, ...) with no available sync,
// and would be silently wrong exactly there.
//
// One thread per (hop slot, lane); each reduces its own bin span.

#include "common.hlsli"

StructuredBuffer<SP> Spec : register(t0);
StructuredBuffer<PS> Prev : register(t1);
RWStructuredBuffer<LS> Lane : register(u0);

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint idx = tid.x;
    uint slotIdx = idx / MAXLANES;
    uint lane = idx % MAXLANES;
    if (slotIdx >= HOPS || lane >= NLANES) return;

    uint vcount = min(_Data0_ValueCount, NBINS);
    if (vcount == 0u) return;
    uint capacity = max(_Data0_HopCapacity, 1u);

    // Which hop does this slot hold? Taken from pass A's stamp, NEVER from the
    // producer ring. The ring is written continuously by CPU threads and
    // advances between dispatches, so deciding validity from it here let this
    // pass compute flux for a generation pass A had not whitened, pairing a
    // fresh frame against a spec slot a full ring old. That kept the flux
    // DISTRIBUTION plausible while destroying its time structure: measured
    // correlation with the offline reference was 0.30/0.51/0.43 and the 90th
    // percentile ran 8-25x high, which is precision collapse, not a threshold
    // problem.
    //
    // Every slot is recomputed each cook rather than only the freshly arrived
    // ones. It is idempotent (the inputs are stable once stamped) and costs
    // ~64x3 lane reductions, which is far cheaper than the class of ordering
    // bugs the incremental version invited.
    uint myGen = hdr_gen(Spec, slotIdx);
    if (myGen == 0u) return;

    uint prevSlot = (myGen - 1u) % capacity;
    // The previous hop must genuinely be present; otherwise leave the value
    // this slot already holds rather than differencing against an unrelated hop.
    if (hdr_gen(Spec, prevSlot) != myGen - 1u) return;

    // Already computed from this exact hop, so there is nothing to redo. This
    // keeps the every-slot sweep correct but costs only the freshly arrived
    // hops in steady state.
    if ((uint)Lane[slotIdx * MAXLANES + lane].gen == myGen) return;

    // Bin width comes from the header the whitening pass captured off a
    // VERIFIED slot, never from _Data0[0]. Reading the unvalidated element 0
    // was measured returning zeros, which made binHz 1.0 and silently
    // reinterpreted bin indices as Hz: the kick lane became bins 25..199
    // (~0.6-4.7 kHz) and the hat lane emptied entirely.
    float binHz = hdr_sample_rate(Spec, slotIdx) / hdr_fft_size(Spec, slotIdx);
    if (!(binHz > 0.0) || binHz > 1000.0) return;   // keep the previous value

    float lowHz = lane_low_hz;
    float sK = split_kick_hz;
    float sS = max(split_snare_hz, sK + binHz);
    float highHz = min(lane_high_hz, (float)(vcount - 1u) * binHz);

    float g = gamma_comp;
    float acc = 0.0;
    float n = 0.0;

    [loop] for (uint k = 0u; k < vcount; ++k) {
        if (lane_of_bin(k, binHz, lowHz, sK, sS, highHz) != lane) continue;

        float y = compress(Spec[slotIdx * NBINS + k].y, g);

        // max over the previous frame's k-2 .. k+2
        float mx = 0.0;
        [unroll] for (int m = -2; m <= 2; ++m) {
            int kk = (int)k + m;
            if (kk < 0 || kk >= (int)vcount) continue;
            mx = max(mx, compress(Spec[prevSlot * NBINS + (uint)kk].y, g));
        }

        acc += max(0.0, y - mx);        // half-wave rectified: only energy ARRIVING
        n += 1.0;
    }

    // Mean rather than sum, so a lane spanning 900 bins is not automatically
    // louder than one spanning 8 and the lanes share one threshold scale.
    float flux = acc / max(n, 1.0);

    // Hits export timebase. Taken from the whitening pass's guarded capture,
    // NOT re-read from the producer ring: the ring is written continuously by
    // CPU threads and this slot may already hold a newer generation.
    float spos = Spec[slotIdx * NBINS + 0u].spare;

    LS o;
    o.flux = flux;
    o.gen = (float)myGen;
    o.rsvd = 0.0;
    o.spos = spos;
    Lane[slotIdx * MAXLANES + lane] = o;
}
