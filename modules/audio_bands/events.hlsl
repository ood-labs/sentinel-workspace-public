// Band editing. Pointer drag in, band edges and thresholds out. One thread.
//
// Three gestures, all of them acting on the band you actually grabbed:
//
//   left-drag on a band's threshold bar -> set that lane's threshold
//   left-drag anywhere else on a band   -> move the band
//   middle/right-drag on a band         -> resize it about its centre
//
// There is no lane selector and no create gesture. All three bands always
// exist, so you point at the one you mean; a selector would only be a way to
// aim at a band you are already touching.
//
// Move and resize work in LOG-AXIS coordinates, not Hz, so a drag feels the
// same at 50 Hz as at 10 kHz and a band keeps its musical interval as it
// travels rather than stretching.
//
// The button and the grabbed band are latched on press and held for the whole
// drag. Re-picking every frame would drop the edit whenever the pointer moved
// fast or a cook arrived with no events, and would let a drag jump between
// bands as it passed over them.

#include "bands.hlsli"

RWStructuredBuffer<float4> Bands : register(u0);

// Opening positions, so the module detects immediately before anyone has
// dragged anything.
//
// Snare sits on its NOISE BURST at 1.5-5 kHz, not on its 180-420 Hz
// fundamental. The fundamental is the obvious choice and it is wrong: a kick's
// body covers the same span, so a snare band placed there fires on kicks too
// and measured roughly twice the true snare count on every corpus pattern.
// Raising its threshold did not help, because the kick's energy there is
// comparable to the snare's.
static const float SEED_LO[3]  = { 45.0,  1500.0, 6200.0  };
static const float SEED_HI[3]  = { 110.0, 5000.0, 14000.0 };
static const float SEED_THR[3] = { 8.0,   8.0,    8.0     };

static const float MODE_MOVE   = 1.0;
static const float MODE_RESIZE = 2.0;
static const float MODE_THRESH = 3.0;
static const float MODE_INERT  = 4.0;

// Grab tolerance around the threshold bar, as a multiple of the UI unit so it
// stays the same physical size as the bar it grabs at every panel size.
// Deliberately small: the bar crosses the whole band, and a generous zone would
// steal moves.
static const float THR_GRAB_UNITS = 4.5;

// Narrowest and widest a resize may go, as a fraction of the log axis.
static const float MIN_HALF = 0.004;
static const float MAX_HALF = 0.5;

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    // Bin width from the producer's own header, never assumed. This is what
    // keeps the axis honest when fft_size changes: the Spectrum port always
    // publishes 1024 bins, so at fft 4096 real coverage is only 0-12 kHz and
    // the axis top must follow it down rather than claim 24 kHz.
    uint capacity = max(_Data0_HopCapacity, 1u);
    uint latest   = _Data0_Generation;
    uint vcount   = max(_Data0_ValueCount, 1u);
    uint sbase    = (latest % capacity) * vcount;

    float binHz = 0.0;
    if (sbase + vcount <= (uint)_Data0_Count
        && _Data0[sbase].sample_rate != 0u && _Data0[sbase].fft_size != 0u) {
        binHz = (float)_Data0[sbase].sample_rate / (float)_Data0[sbase].fft_size;
    }
    float hzMax = binHz * (float)(AB_BINS - 1u);
    float H     = _Resolution.y;

    float4 drag = Bands[AB_DRAG];
    float4 grab = Bands[AB_GRAB];
    float4 cur  = Bands[AB_CUR];
    float4 l0   = Bands[0];

    // Seed only once a real bin width exists. Latching before audio arrives
    // would write a table of zero-width bands and silently mute every lane.
    bool seeded = (l0.z > 0.5) && (reset_bands < 0.5);
    if (!seeded && binHz > 0.0) {
        [loop] for (uint i = 0u; i < AB_LANES; ++i) {
            Bands[i] = float4(SEED_LO[i], SEED_HI[i], 1.0, SEED_THR[i]);
        }
        drag.x = 0.0;
    } else if (seeded) {
        // Migration for state saved before thresholds moved into this buffer.
        // Without it those bands restore with a threshold of zero and fire on
        // absolutely everything.
        [loop] for (uint m = 0u; m < AB_LANES; ++m) {
            float4 bm = Bands[m];
            if (bm.w <= 0.0) { bm.w = SEED_THR[m]; Bands[m] = bm; }
        }
    }

    uint count = min(_ViewportEventCount, 64u);

    [loop] for (uint e = 0u; e < count; ++e) {
        ViewportEvent ev = _ViewportEvents[e];

        bool press   = (ev.type == 2u && ev.phase == 1u);
        bool release = (ev.type == 2u && ev.phase == 3u);
        bool dragUpd = (ev.type == 5u && ev.code == 3u
                        && (ev.phase == 5u || ev.phase == 6u));
        bool dragEnd = (ev.type == 5u && ev.code == 3u && ev.phase == 7u);
        bool cancel  = (ev.type == 5u && ev.phase == 8u);

        float px = saturate(ev.position.x);
        float py = saturate(ev.position.y);   // top-down, matches AB_SPEC_BOT

        // Only the spectrum half edits bands. The trace strips below are a
        // readout, and a stray click on them must not redefine a band.
        bool inSpectrum = (py < AB_SPEC_BOT);

        if (press && inSpectrum && binHz > 0.0) {
            // Which band is under the press, if any. Nearest centre wins when
            // two overlap, so a band fully inside another is still reachable.
            int   hit  = -1;
            float best = 1e9;
            [loop] for (uint L = 0u; L < AB_LANES; ++L) {
                float4 b = Bands[L];
                if (b.z < 0.5 || b.y <= b.x) continue;
                float x0 = abHzToX(b.x, hzMax);
                float x1 = abHzToX(b.y, hzMax);
                if (px < x0 || px > x1) continue;
                float d = abs(px - 0.5 * (x0 + x1));
                if (d < best) { best = d; hit = (int)L; }
            }

            drag.x = 1.0;
            drag.y = px;
            drag.z = py;

            if (hit < 0) {
                drag.w = MODE_INERT;      // nothing under the pointer to act on
                grab   = float4(0.0, 0.0, 0.0, 0.0);
            } else {
                float4 b = Bands[(uint)hit];
                grab = float4((float)hit, abHzToX(b.x, hzMax),
                              abHzToX(b.y, hzMax), b.w);

                bool leftBtn = (ev.code == 0u);
                float barY   = abThreshToY(b.w, H);
                bool  onBar  = leftBtn
                             && (abs(py * H - barY) < THR_GRAB_UNITS * abUI(H));

                drag.w = !leftBtn ? MODE_RESIZE
                       : (onBar   ? MODE_THRESH : MODE_MOVE);
            }
            cur = float4(px, py, 0.0, 0.0);
        } else if (dragUpd && drag.x > 0.5) {
            cur = float4(px, py, 0.0, 0.0);
        } else if (cancel) {
            drag.x = 0.0;
        } else if ((release || dragEnd) && drag.x > 0.5) {
            cur = float4(px, py, 0.0, 0.0);
            drag.x = 0.0;
        }
    }

    // ---- apply the live edit ----------------------------------------------
    // Recomputed every cook from the ORIGINAL grabbed geometry, never from the
    // band's current value. Accumulating deltas instead would drift whenever a
    // cook saw two drag updates or none.
    if (drag.x > 0.5 && binHz > 0.0 && drag.w < MODE_INERT) {
        uint  L   = (uint)clamp(grab.x, 0.0, 2.0);
        float4 b  = Bands[L];
        float loX = grab.y;
        float hiX = grab.z;

        if (drag.w == MODE_THRESH) {
            // Absolute, not incremental, so the bar sits under the pointer
            // rather than sliding away from it over a long drag.
            b.w = abYToThresh(cur.y * H, H);
        } else if (drag.w == MODE_MOVE) {
            // Clamp the OFFSET, not the two edges. Clamping edges separately
            // would squash the band flat against the end of the axis.
            float dx = clamp(cur.x - drag.y, -loX, 1.0 - hiX);
            loX += dx;
            hiX += dx;
        } else {
            float c    = 0.5 * (loX + hiX);
            // Exponential, so the width can never cross zero and invert.
            float half = clamp(0.5 * (hiX - loX) * exp((cur.x - drag.y) * 4.0),
                               MIN_HALF, MAX_HALF);
            loX = saturate(c - half);
            hiX = saturate(c + half);
        }

        if (drag.w != MODE_THRESH) {
            float loHz = abXToHz(loX, hzMax);
            float hiHz = abXToHz(hiX, hzMax);
            if (hiHz - loHz < binHz) hiHz = loHz + binHz;
            b.x = loHz;
            b.y = min(hiHz, hzMax);
        }

        b.z = 1.0;
        Bands[L] = b;
    }

    Bands[AB_DRAG] = drag;
    Bands[AB_GRAB] = grab;
    Bands[AB_CUR]  = cur;
}
