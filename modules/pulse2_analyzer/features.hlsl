// Pass B2 — PER-REGION FEATURE VECTOR (2D).
//
// WHY THIS EXISTS. 2C3 established, by measurement, that the snare lane's false
// positives cannot be removed by any level- or timing-based rule:
//
//   - `hats_only_150` (96 hats, no kick) produces ZERO snare false positives,
//     while every kick produces almost exactly one (27 kicks -> 27 FP,
//     48 -> 48). The false positive IS the kick.
//   - it arrives a fixed 8 hops (43 ms) after the kick transient, on the kick's
//     decay, when the kick lane itself is already silent (flux 0.0021).
//   - it is not quieter than a real snare, so no threshold separates it, and
//     suppressing its peak merely MOVES the detection inside the decay bump.
//
// What differs is TIMBRE. Inside 200-2400 Hz a kick's decay is the tail of its
// harmonic series, so its energy piles up against the low edge of the band and
// is tonal. A real snare is a noise burst: energy spread across the whole band,
// high geometric-to-arithmetic mean ratio. Centroid and flatness see that
// difference directly; flux cannot see it at all.
//
// One thread per (hop slot, lane), mirroring flux.hlsl exactly — same region
// records, same weights, same guards — so a feature and the flux it qualifies
// can never be computed over different bins.

#include "common.hlsli"

StructuredBuffer<SP> Spec : register(t0);
StructuredBuffer<RG> Rgn  : register(t3);
RWStructuredBuffer<FS> Feat : register(u0);

// Floor for the log in the flatness ratio. Whitened magnitude is 0..1-ish, and
// a true zero would send log to -inf and take the geometric mean to 0 for the
// whole region, reporting "perfectly tonal" for a band that is merely empty.
static const float FLAT_EPS = 1e-6;

// Region-weighted moments of one hop slot. Returns weighted (sum y, sum w,
// sum y*binPos, sum w*log y) so the caller can form every feature from one
// sweep instead of re-reading the spectrum per feature.
// `useFlux` selects WHICH spectrum the moments are taken over:
//   false -> .y, the whitened magnitude: the total sound present in the band.
//   true  -> .d, SuperFlux: only the energy ARRIVING at this hop.
//
// The distinction decides the hard case. When a snare lands on top of a kick,
// the kick's sustained decay dominates the band, so the MIXTURE's centroid is
// dragged down and a real snare reads as kick-like -- measured on
// four_on_floor_128, where precision is already 1.000 and recall only 0.667,
// so what remains is rejecting genuine snares. A decaying kick contributes
// almost no new energy, while a snare onset contributes nearly all of it, so
// moments over .d describe the snare alone rather than the sum.
void region_moments(uint slotIdx, uint lane, uint vcount, float g, bool useFlux,
                    out float sy, out float sw, out float syk, out float slog,
                    out float lo, out float hi) {
    sy = 0.0; sw = 0.0; syk = 0.0; slog = 0.0;
    lo = 1e9; hi = -1e9;

    [loop] for (uint ri = 0u; ri < P2_MAXREGIONS; ++ri) {
        RG r = Rgn[ri];
        if (r.enabled < 0.5 || (uint)r.lane != lane) continue;

        float pad = p2_region_bin_pad(r);
        int k0 = (int)max(r.binLo - pad, 0.0);
        int k1 = (int)min(r.binHi + pad, (float)(vcount - 1u));
        lo = min(lo, (float)k0);
        hi = max(hi, (float)k1);

        [loop] for (int k = k0; k <= k1; ++k) {
            float w = p2_region_weight(r, 0.0, (float)k);
            if (w <= 0.0) continue;

            SP s = Spec[slotIdx * NBINS + (uint)k];
            float y = compress(useFlux ? s.d : s.y, g);
            sy   += w * y;
            sw   += w;
            syk  += w * y * (float)k;
            slog += w * log(max(y, FLAT_EPS));
        }
    }
}

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint idx = tid.x;
    uint slotIdx = idx / MAXLANES;
    uint lane = idx % MAXLANES;
    if (slotIdx >= HOPS || lane >= NLANES) return;

    uint vcount = min(_Data0_ValueCount, NBINS);
    if (vcount == 0u) return;
    uint capacity = max(_Data0_HopCapacity, 1u);

    // Same stamp discipline as flux.hlsl: trust pass A's generation stamp, never
    // the producer ring, which advances between dispatches.
    uint myGen = hdr_gen(Spec, slotIdx);
    if (myGen == 0u) return;

    // Idempotent re-sweep, cheap in steady state.
    if ((uint)Feat[slotIdx * MAXLANES + lane].gen == myGen) return;

    float g = gamma_comp;

    float sy, sw, syk, slog, lo, hi;
    region_moments(slotIdx, lane, vcount, g, false, sy, sw, syk, slog, lo, hi);
    if (sw <= 0.0 || hi < lo) return;

    float meanY = sy / sw;
    float geoY  = exp(slog / sw);

    // Flatness: geometric/arithmetic mean. ~1 noise-like, ->0 tonal.
    float flatness = (meanY > 1e-9) ? saturate(geoY / meanY) : 0.0;

    // Centroid, normalised across THIS lane's own span so lanes are comparable.
    float span = max(hi - lo, 1.0);
    float cent = (sy > 1e-9) ? saturate(((syk / sy) - lo) / span) : 0.0;

    // The same two moments over ARRIVING energy rather than total energy. Kept
    // as separate features instead of replacing the pair above, so the fit
    // decides between them on measured evidence rather than on this comment.
    float f_sy, f_sw, f_syk, f_slog, f_lo, f_hi;
    region_moments(slotIdx, lane, vcount, g, true,
                   f_sy, f_sw, f_syk, f_slog, f_lo, f_hi);
    float meanD = (f_sw > 0.0) ? (f_sy / f_sw) : 0.0;
    float geoD  = (f_sw > 0.0) ? exp(f_slog / f_sw) : 0.0;
    float flatD = (meanD > 1e-9) ? saturate(geoD / meanD) : 0.0;
    float centD = (f_sy > 1e-9) ? saturate(((f_syk / f_sy) - lo) / span) : 0.0;

    // Temporal decay ratio, two hops back (10.7 ms) rather than one: at one hop
    // the difference between an attack and a tail is inside the noise.
    //
    // Expressed as E[n] / (E[n] + E[n-2]), NOT the raw quotient E[n]/E[n-2].
    // The raw form was measured first and is unusable: when the earlier hop is
    // near-silent the quotient explodes (observed values past 1.2e6), which both
    // swamps any weighted sum it appears in and destroys its own rank statistic
    // (AUC 0.647). The bounded form carries identical information -- > 0.5 means
    // energy arriving, < 0.5 a tail, 0.5 steady -- on a scale that can actually
    // be combined with the other features.
    float decay = 0.5;
    if (myGen >= 2u) {
        uint pslot = (myGen - 2u) % capacity;
        if (hdr_gen(Spec, pslot) == myGen - 2u) {
            float p_sy, p_sw, p_syk, p_slog, p_lo, p_hi;
            region_moments(pslot, lane, vcount, g, false,
                           p_sy, p_sw, p_syk, p_slog, p_lo, p_hi);
            float prevE = (p_sw > 0.0) ? (p_sy / p_sw) : 0.0;
            float den = meanY + prevE;
            decay = (den > 1e-9) ? saturate(meanY / den) : 0.5;
        }
    }

    FS o;
    o.cent = cent;
    o.flatness = flatness;
    o.decay    = decay;
    o.energy   = meanY;
    o.gen      = (float)myGen;
    o.spos     = Spec[slotIdx * NBINS + 0u].spare;
    o.centD    = centD;
    o.flatD    = flatD;
    Feat[slotIdx * MAXLANES + lane] = o;
}
