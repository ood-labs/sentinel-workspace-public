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
StructuredBuffer<RG> Rgn  : register(t3);
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

    float g = gamma_comp;
    float acc = 0.0;
    float wsum = 0.0;

    // Region-weighted reduction (2C1). The lane's bins and their weights come
    // from the region buffer rather than a hard frequency split, so a
    // programmatic region and a console-drawn one take the identical path.
    // Only this lane's regions are visited, and only over their own bin spans.
    [loop] for (uint ri = 0u; ri < P2_MAXREGIONS; ++ri) {
        RG r = Rgn[ri];
        if (r.enabled < 0.5 || (uint)r.lane != lane) continue;

        float pad = p2_region_bin_pad(r);
        int k0 = (int)max(r.binLo - pad, 0.0);
        int k1 = (int)min(r.binHi + pad, (float)(vcount - 1u));

        [loop] for (int k = k0; k <= k1; ++k) {
            float w = p2_region_weight(r, 0.0, (float)k);
            if (w <= 0.0) continue;

            float y = compress(Spec[slotIdx * NBINS + (uint)k].y, g);

            // max over the previous frame's k-2 .. k+2
            float mx = 0.0;
            [unroll] for (int m = -2; m <= 2; ++m) {
                int kk = k + m;
                if (kk < 0 || kk >= (int)vcount) continue;
                mx = max(mx, compress(Spec[prevSlot * NBINS + (uint)kk].y, g));
            }

            acc += w * max(0.0, y - mx);   // half-wave rectified: arriving energy only
            wsum += w;
        }
    }

    // Weighted MEAN rather than sum, so a lane spanning 900 bins is not
    // automatically louder than one spanning 8 and the lanes share one
    // threshold scale. With a rectangular region of unit gain this is exactly
    // the 2B fixed-lane mean.
    float flux = acc / max(wsum, 1e-6);

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
