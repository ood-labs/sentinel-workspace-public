// Display spectrogram history: log rebin -> running-peak equalisation -> gamma.
//
// One thread per DISPLAY bin, so the per-bin running-peak recursion over hops is
// thread-local and needs no synchronisation, exactly as in the analyzer's
// whitening pass.
//
// The three stages do different jobs and none is decoration:
//   log rebin      - a linear bin axis spends three quarters of its height on
//                    5-20 kHz and crushes the kick band into a few pixels.
//   equalisation   - without it the low end saturates white and everything
//                    above ~2 kHz reads as black, because broadband musical
//                    energy falls off steeply with frequency.
//   dB + gamma     - the level below the running peak is mapped across a
//                    decibel range, then gamma 0.45 lifts the mid greys.
//                    Displaying the raw v/P ratio instead saturates to white
//                    wherever content is near its recent peak.

#include "types.hlsli"

RWStructuredBuffer<DH> Hist : register(u0);

[numthreads(64, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint b = tid.x;
    if (b >= DISP_BINS) return;

    uint vcount = _Data0_ValueCount;
    if (vcount == 0u) return;
    uint latest = _Data0_Generation;
    if (latest == 0u) return;
    uint capacity = max(_Data0_HopCapacity, 1u);

    // Resume at the oldest RETAINED generation when further behind than the
    // producer ring, rather than replaying hops that have been overwritten.
    uint cursor = (uint)max(Hist[CURSOR_IDX].v, 0.0);
    uint oldest = (latest >= capacity) ? (latest - capacity + 1u) : 0u;
    uint start = max(cursor + 1u, oldest);

    float P = Hist[EQ_BASE + b].v;
    float r = clamp(eq_decay, 0.5, 0.99999);
    float floorv = max(eq_floor, 1e-12);

    [loop] for (uint gen = start; gen <= latest; ++gen) {
        uint slot = gen % capacity;
        uint base = slot * vcount;
        if (base + vcount > (uint)_Data0_Count) continue;
        if (_Data0[base].generation_counter != gen) continue;      // stale slot
        if (_Data0[base].sample_rate == 0u || _Data0[base].fft_size == 0u) continue;

        float binHz = (float)_Data0[base].sample_rate / (float)_Data0[base].fft_size;

        // Source bins covered by this display row. At the bottom of a log axis
        // one display row is a fraction of a bin, at the top it is dozens, so
        // the reduction is a MAX: a peak-preserving reduction keeps a narrow
        // transient visible instead of averaging it into the noise around it.
        float f0 = P2_AXIS_LO_HZ * pow(P2_AXIS_HI_HZ / P2_AXIS_LO_HZ,
                                       (float)b / (float)DISP_BINS);
        float f1 = P2_AXIS_LO_HZ * pow(P2_AXIS_HI_HZ / P2_AXIS_LO_HZ,
                                       (float)(b + 1u) / (float)DISP_BINS);
        // At the BOTTOM of a log axis a display row is a FRACTION of a source
        // bin, so a max-reduce over the covering range repeats one bin's value
        // across many rows and paints a solid block. Interpolate there instead;
        // max-reduce only where a row genuinely spans more than one bin.
        float b0 = f0 / binHz, b1 = f1 / binHz;
        float v = 0.0;
        if (b1 - b0 < 1.0) {
            float fc = clamp((b0 + b1) * 0.5, 0.0, (float)(vcount - 1u));
            uint  ka = (uint)floor(fc);
            uint  kb = min(ka + 1u, vcount - 1u);
            v = lerp(_Data0[base + ka].magnitude,
                     _Data0[base + kb].magnitude, frac(fc));
        } else {
            int k0 = (int)max(floor(b0), 0.0);
            int k1 = (int)min(max(ceil(b1), (float)(k0 + 1)), (float)(vcount - 1u));
            [loop] for (int k = k0; k <= k1; ++k)
                v = max(v, _Data0[base + (uint)k].magnitude);
        }

        P = max(r * P, v);
        P = clamp(P, floorv, 1e4);

        // Map the level BELOW the running peak across a decibel range rather
        // than displaying the raw ratio. v/P sits near 1 for any sustained
        // content, so the raw ratio saturates to white across most of the frame
        // and destroys exactly the structure the console exists to show.
        float rel = v / max(P, floorv);
        float t = saturate(1.0 + (20.0 * log10(max(rel, 1e-8))) / max(disp_range, 6.0));

        DH o;
        o.v = v;
        o.eq = pow(t, max(disp_gamma, 0.05));
        o.r0 = 0.0; o.r1 = 0.0;
        Hist[(gen % DISP_HOPS) * DISP_BINS + b] = o;
    }

    DH pk = Hist[EQ_BASE + b];
    pk.v = P;
    Hist[EQ_BASE + b] = pk;

    // Every thread in this dispatch shares one _Data0_Generation snapshot, so
    // thread 0 can record where the append reached for all of them.
    if (b == 0u) {
        DH c;
        c.v = (float)latest;
        c.eq = 0.0;
        c.r0 = (float)(latest % DISP_HOPS);
        c.r1 = 0.0;
        Hist[CURSOR_IDX] = c;
    }
}
