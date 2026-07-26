// Console interaction — viewport events in, region records out.
//
// One thread. Regions are authored by DRAGGING a frequency span on the
// spectrogram, because the choice "which band is the kick" is a spatial
// judgement against visible evidence and a pair of Hz sliders cannot express
// it. Which lane the span belongs to, and its profile, stay ordinary Properties
// enums — those are discrete mode choices, not spatial ones.
//
// The drag is stored in a header record rather than recomputed per frame, so a
// fast pointer or an event-free cook cannot drop an edit in progress.

#include "types.hlsli"

StructuredBuffer<RG>   Prev  : register(t0);
RWStructuredBuffer<RG> Out   : register(u0);

static const uint HDR   = P2_MAXREGIONS;        // 8: drag state
static const uint FLASH = P2_MAXREGIONS + 1u;   // 9: per-region firing flash

// Seeds match the 2C1 tuned configuration, so a fresh console reproduces the
// scored detector exactly rather than starting from an arbitrary layout.
static const float SEED_LO[3] = { 25.0,  200.0,  2400.0  };
static const float SEED_HI[3] = { 200.0, 2400.0, 20000.0 };
static const float SEED_PR[3] = { P2_PROFILE_GAUSS, P2_PROFILE_RECT, P2_PROFILE_RECT };

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    // Bin width comes from the producer's own reported header, never assumed.
    uint capacity = max(_Data0_HopCapacity, 1u);
    uint latest   = _Data0_Generation;
    uint vcount   = max(_Data0_ValueCount, 1u);
    uint sbase    = (latest % capacity) * vcount;
    float binHz = 0.0;
    if (sbase + vcount <= (uint)_Data0_Count
        && _Data0[sbase].sample_rate != 0u && _Data0[sbase].fft_size != 0u) {
        binHz = (float)_Data0[sbase].sample_rate / (float)_Data0[sbase].fft_size;
    }

    RG hdr = Prev[HDR];
    RG fl  = Prev[FLASH];

    // ---- carry previous regions forward, or seed on first run -------------
    bool seeded = (hdr.binLo > 0.5);
    [loop] for (uint i = 0u; i < P2_MAXREGIONS; ++i) {
        RG r;
        if (seeded) {
            r = Prev[i];
        } else if (i < 3u && binHz > 0.0) {
            r.binLo   = max(floor(SEED_LO[i] / binHz), 0.0);
            r.binHi   = min(floor(SEED_HI[i] / binHz), 1023.0);
            r.hopLo   = 0.0;
            r.hopHi   = 255.0;
            r.profile = SEED_PR[i];
            r.gain    = 1.0;
            r.enabled = 1.0;
            r.lane    = (float)i;
        } else {
            r.binLo = 0.0; r.binHi = 0.0; r.hopLo = 0.0; r.hopHi = 0.0;
            r.profile = 0.0; r.gain = 0.0; r.enabled = 0.0; r.lane = 0.0;
        }
        Out[i] = r;
    }
    // Only claim seeded once a real bin width existed, otherwise the first
    // cooks (before audio arrives) would latch a table of empty regions.
    if (!seeded && binHz > 0.0) hdr.binLo = 1.0;

    if (clear_regions > 0.5) {
        [loop] for (uint c = 0u; c < P2_MAXREGIONS; ++c) {
            RG z = Out[c]; z.enabled = 0.0; Out[c] = z;
        }
    }

    // ---- viewport events ---------------------------------------------------
    uint lane = (uint)clamp(active_lane, 0.0, 2.0);
    uint count = min(_ViewportEventCount, 64u);
    float dbgN = fl.enabled + (float)count;   // latched running total
    float dbgL = fl.lane;
    [loop] for (uint e = 0u; e < count; ++e) {
        ViewportEvent ev = _ViewportEvents[e];
        dbgL = (float)(ev.type * 100u + ev.phase);

        bool press   = (ev.type == 2u && ev.code == 0u && ev.phase == 1u);
        bool release = (ev.type == 2u && ev.code == 0u && ev.phase == 3u);
        bool dragUpd = (ev.type == 5u && ev.code == 3u
                        && (ev.phase == 5u || ev.phase == 6u));
        bool dragEnd = (ev.type == 5u && ev.code == 3u && ev.phase == 7u);
        bool cancel  = (ev.type == 5u && ev.phase == 8u);

        // Viewport Y is DOWN; the spectrogram axis is UP. Flip once, here, so
        // every consumer downstream works in one orientation.
        float py = 1.0 - saturate(ev.position.y);
        float px = saturate(ev.position.x);

        if (press || (dragUpd && hdr.binHi < 0.5)) {
            hdr.binHi   = 1.0;      // dragActive
            hdr.hopLo   = px;       // start x
            hdr.hopHi   = py;       // start y
            hdr.profile = px;       // current x
            hdr.gain    = py;       // current y
            hdr.lane    = (float)lane;
        } else if (dragUpd) {
            hdr.profile = px;
            hdr.gain    = py;
        } else if (cancel) {
            hdr.binHi = 0.0;
        } else if ((release || dragEnd) && hdr.binHi > 0.5) {
            hdr.profile = px;
            hdr.gain    = py;

            float t0 = min(hdr.hopHi, hdr.gain);
            float t1 = max(hdr.hopHi, hdr.gain);
            uint  slot = (uint)clamp(hdr.lane, 0.0, 2.0);

            // A click with no vertical travel is not a span. Ignore it rather
            // than collapsing the lane's region to a single bin.
            if (binHz > 0.0 && (t1 - t0) > 0.01) {
                RG r = Out[slot];
                r.binLo   = clamp(p2_axis_to_bin(t0, binHz), 0.0, 1023.0);
                r.binHi   = clamp(p2_axis_to_bin(t1, binHz), 0.0, 1023.0);
                if (r.binHi <= r.binLo) r.binHi = r.binLo + 1.0;
                r.hopLo   = 0.0;
                r.hopHi   = 255.0;
                r.profile = (region_profile >= 0.5) ? P2_PROFILE_GAUSS : P2_PROFILE_RECT;
                r.gain    = region_gain;
                r.enabled = 1.0;
                r.lane    = (float)slot;
                Out[slot] = r;
            }
            hdr.binHi = 0.0;
        }
    }

    // ---- firing flash ------------------------------------------------------
    // Decay is exp(-dt/tau) in WALL CLOCK, not per cook, so the ramp a human
    // sees is identical at 20 Hz and at 60 Hz.
    float k = exp(-max(_DeltaTime, 0.0) / max(flash_tau, 0.02));
    // Six flash slots, not eight: `enabled` and `lane` stay pinned at 0 so this
    // record can never be mistaken for a region by anything that scans the
    // buffer. Three lanes are in use, so six is ample.
    float f[P2_MAXFLASH] = { fl.binLo, fl.binHi, fl.hopLo,
                             fl.hopHi, fl.profile, fl.gain };

    // Trace header: f0 = judged cursor, f2 = latest generation.
    uint tcursor = (uint)max(_Data1[0].f0, 0.0);
    [loop] for (uint j = 0u; j < P2_MAXFLASH; ++j) f[j] *= k;

    // Look back over the last few judged hops for a fire on each region's lane.
    // Short window: the flash only needs to catch the edge, the decay carries
    // the rest.
    [loop] for (uint b = 0u; b < 8u; ++b) {
        if (tcursor < b + 1u) break;
        uint g = tcursor - b - 1u;
        [loop] for (uint rr = 0u; rr < P2_MAXFLASH; ++rr) {
            RG r = Out[rr];
            if (r.enabled < 0.5) continue;
            uint ln = (uint)clamp(r.lane, 0.0, 2.0);
            uint idx = p2_trace_index(g, ln);
            if (idx >= (uint)_Data1_Count) continue;
            if (_Data1[idx].f2 > 0.5) f[rr] = 1.0;
        }
    }

    fl.binLo = f[0]; fl.binHi = f[1]; fl.hopLo = f[2];
    fl.hopHi = f[3]; fl.profile = f[4]; fl.gain = f[5];
    fl.enabled = dbgN; fl.lane = dbgL;

    hdr.enabled = 0.0;   // header records must never read as regions
    Out[HDR]   = hdr;
    Out[FLASH] = fl;

    // ---- publish the three lane spans in Hz -------------------------------
    // Read by the control outputs and driven onto the analyzer's own region
    // parameters through expressions. Hz, not bins, because Hz is what those
    // parameters mean and what survives a change of FFT size.
    RG pub;
    float hz[6] = { 0, 0, 0, 0, 0, 0 };
    [loop] for (uint q = 0u; q < 3u; ++q) {
        RG r = Out[q];
        if (r.enabled > 0.5 && binHz > 0.0) {
            hz[q * 2u]      = r.binLo * binHz;
            hz[q * 2u + 1u] = r.binHi * binHz;
        } else {
            // Publish the seeds rather than zero: a zero-width region driven
            // onto the detector would silently mute the lane.
            hz[q * 2u]      = SEED_LO[q];
            hz[q * 2u + 1u] = SEED_HI[q];
        }
    }
    pub.binLo = hz[0]; pub.binHi = hz[1]; pub.hopLo = hz[2];
    pub.hopHi = hz[3]; pub.profile = hz[4]; pub.gain = hz[5];
    pub.enabled = 0.0; pub.lane = 0.0;
    Out[P2_PUB_IDX] = pub;

    // ---- latch the newest classifier verdict ------------------------------
    // Held rather than sampled, because the card must survive a STILL capture:
    // a snare arrives every ~0.5 s and a frame grabbed between two of them would
    // otherwise show an empty panel and prove nothing.
    //
    // The age counter is what keeps that honest. A held card with no elapsed
    // time is indistinguishable from a frozen one, so the seconds since the
    // latch are displayed next to it.
    RG vd = Prev[P2_VERDICT_IDX];
    vd.gain += max(_DeltaTime, 0.0);

    uint vlane = (uint)clamp(verdict_lane, 0.0, 2.0);
    // Newest first, so the first hit found is the most recent one. 16 hops is
    // 85 ms of audio against a ~16 ms cook, so no candidate can pass through the
    // window unseen even if a cook runs long.
    [loop] for (uint b2 = 0u; b2 < 16u; ++b2) {
        if (tcursor < b2 + 1u) break;
        uint idx2 = p2_trace_index(tcursor - b2 - 1u, vlane);
        if (idx2 >= (uint)_Data1_Count) continue;

        // f2 is the picker's own verdict flag: +1 fired, -1 rejected by the
        // classifier, 0 never a candidate. Only the first two are events.
        float st = _Data1[idx2].f2;
        if (abs(st) < 0.5) continue;

        vd.binLo   = _Data1[idx2].f4;   // centroid
        vd.binHi   = _Data1[idx2].f5;   // flatness
        vd.hopLo   = _Data1[idx2].f6;   // decay
        vd.hopHi   = _Data1[idx2].f7;   // classifier score
        vd.profile = (st > 0.5) ? 1.0 : -1.0;
        vd.gain    = 0.0;
        vd.lane    = (float)vlane;
        break;
    }
    vd.enabled = 0.0;   // must never read as a region
    Out[P2_VERDICT_IDX] = vd;
}
