// Pass A — ADAPTIVE SPECTRAL WHITENING ONLY.
//
//   P[n,k] = max(r * P[n-1,k], |X[n,k]|)
//   Y[n,k] = |X[n,k]| / max(P[n,k], 1e-4)
//
// One thread per bin, so the recursion over hops is thread-local and needs no
// synchronisation. This is what removes the per-bin dynamic-range problem that
// made one global threshold floor simultaneously starve the hi-hat lane and
// over-trigger the kick lane: every bin ends up normalised to 0..1 against its
// OWN recent history, so no per-lane floor is required.
//
// Writes a COMPLETED whitened buffer. Pass B reads only this.

#include "common.hlsli"

StructuredBuffer<PS> Prev : register(t1);
RWStructuredBuffer<SP> Spec : register(u0);

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint k = tid.x;
    if (k >= NBINS) return;

    uint vcount = min(_Data0_ValueCount, NBINS);
    if (vcount == 0u || k >= vcount) return;

    uint latest = _Data0_Generation;
    if (latest == 0u) return;
    uint capacity = max(_Data0_HopCapacity, 1u);

    // Chronological catch-up. Resume at the oldest RETAINED generation when we
    // are more than `capacity` hops behind, rather than replaying a ring that
    // has already been overwritten.
    uint cursor = (uint)max(Prev[HDR_H].a, 0.0);
    uint oldest = (latest >= capacity) ? (latest - capacity + 1u) : 0u;
    uint start = max(cursor, oldest);

    float P = Spec[PEAKBASE + k].p;
    if (P <= 0.0) P = max(peak_floor, 1e-12);

    float r = clamp(whiten_decay, 0.5, 0.99999);

    [loop] for (uint gen = start; gen <= latest; ++gen) {
        uint slot = gen % capacity;
        uint base = slot * vcount;
        if (base + vcount > (uint)_Data0_Count) continue;
        if (_Data0[base].generation_counter != gen) continue;   // stale slot
        // A record whose format header is zero is not a valid record. The ring
        // is written continuously by the producer's CPU threads, and a slot can
        // present a matching generation_counter while its header fields are not
        // yet visible. Downstream passes divide by these, so an unguarded zero
        // silently redefines the analysis grid rather than failing.
        if (_Data0[base].sample_rate == 0u || _Data0[base].fft_size == 0u
            || _Data0[base].hop_size == 0u) continue;

        float mag = max(_Data0[base + k].magnitude, 0.0);

        P = max(r * P, mag);
        // The floor is what keeps a silent band from normalising its own dither
        // to full scale; it is authored and measured, see the manifest note.
        P = clamp(P, max(peak_floor, 1e-12), 1e4);   // stability over long runs

        float Y = saturate(mag / max(P, max(peak_floor, 1e-12)));

        SP s;
        s.y = Y;
        s.p = P;
        // Bins 0 and 1 of each slot carry that hop's producer header. It is
        // captured HERE because this is the only pass that verifies
        // generation_counter == gen AND a non-zero header; a later pass
        // re-reading the ring can find the slot already overwritten by the
        // producer's CPU threads and pick up a different hop's timestamp or a
        // half-written header. Both bins sit below lane_low_hz, so nothing in
        // the lane reduction reads them.
        //   bin 0: .spare = sample_position, .d = fft_size
        //   bin 1: .spare = sample_rate,     .d = hop_size
        //   bin 2: .spare = generation actually whitened into this slot
        //
        // The bin-2 stamp is what lets pass B know which hop a spec slot really
        // holds. Pass B must NOT re-derive that from the producer ring: the ring
        // advances between dispatches, so pass B would compute flux for a
        // generation this pass never whitened and silently read a slot still
        // holding data from a full ring ago.
        s.spare = 0.0;
        s.d = 0.0;
        if (k == 0u) {
            s.spare = (float)_Data0[base].sample_position;
            s.d     = (float)_Data0[base].fft_size;
        } else if (k == 1u) {
            s.spare = (float)_Data0[base].sample_rate;
            s.d     = (float)_Data0[base].hop_size;
        } else if (k == 2u) {
            s.spare = (float)gen;
        }
        Spec[slot * NBINS + k] = s;
    }

    // Persist the running peak for the next cook. Partial-write persistence of
    // this buffer is proven, not assumed (see the 2E1 step-0 micro-proof).
    SP pk = Spec[PEAKBASE + k];
    pk.p = P;
    Spec[PEAKBASE + k] = pk;
}
