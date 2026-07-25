// CRYOGRAM / PULSE — onset detection and tempo tracking from Mel Bands.
//
// Audio In publishes perceptual band energy; it does not publish beats. Nothing
// upstream knows what a kick is. This node invents that.
//
// Per analysis hop (187.5/s at 48kHz with hop 256):
//   1. log-compress each of the 138 mel bands
//   2. half-wave-rectified SPECTRAL FLUX per lane — sum of positive frame-to-
//      frame energy increases. Rectification is the whole point: a note ending
//      is not an onset, only energy ARRIVING is.
//   3. adaptive threshold per lane = EMA(flux) + k * EMA(|flux - EMA|). Self
//      calibrating, so it survives a quiet intro and a loud drop without any
//      authored absolute number.
//   4. refractory gate per lane so one transient cannot fire three times
//   5. autocorrelate our OWN 512-hop onset history (the node retains only 64)
//      to estimate tempo, with half/double-time correction
//   6. phase-locked loop: free-run the beat phase, nudge it whenever a kick
//      lands near the prediction
//
// State buffer layout (element = 8 floats, 32 bytes):
//   [0    .. 511]  history ring: per-hop flux and onset strength
//   [512  .. 649]  previous log band energies (.a only)
//   [650]  A: cursor, hopCount, bpm, beatPhase, lastTime, tempoLag, tempoConf, beatPulse
//   [651]  B: kickEnv, snareEnv, hihatEnv, kickCount, snareCount, hihatCount, onsetCount, level
//   [652]  C: lowE, midE, highE, muLow, muMid, muHigh, devLow, devMid
//   [653]  D: devHigh, lastKickHop, lastSnareHop, lastHihatHop, thrLow, thrMid, thrHigh, spare

struct PS { float a, b, c, d, e, f, g, h; };

StructuredBuffer<PS> Prev : register(t1);
StructuredBuffer<float4> AC : register(t2);
RWStructuredBuffer<PS> Out : register(u0);

static const uint HIST     = 512u;
static const uint BANDBASE = 512u;
static const uint MAXBAND  = 138u;
static const uint HDR_A    = 650u;
static const uint HDR_B    = 651u;
static const uint HDR_C    = 652u;
static const uint HDR_D    = 653u;
static const uint TOTAL    = 654u;
static const uint RING_CAP = 64u;

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    // carry all state forward
    [loop] for (uint i = 0u; i < TOTAL; ++i) Out[i] = Prev[i];

    PS A = Prev[HDR_A];
    PS B = Prev[HDR_B];
    PS C = Prev[HDR_C];
    PS D = Prev[HDR_D];

    uint vcount = min(_Data0[0].value_count, MAXBAND);
    if (vcount == 0u) return;

    // The Mel Bands port has NO header element: 8832 = 64 hops x 138 bands
    // exactly. _Data0[0] is therefore ring slot 0 band 0, not metadata, and its
    // generation only changes when the ring wraps back to slot 0 — once every
    // 64 hops (~0.34s). Taking it as "latest" made the detector idle and then
    // swallow 64 hops in one burst about three times a second.
    // The true latest generation is the max across all slots.
    uint slots = min((uint)_Data0_Count / max(vcount, 1u), RING_CAP);
    uint latest = 0u;
    [loop] for (uint s = 0u; s < slots; ++s) {
        uint g = _Data0[s * vcount].generation_counter;
        if (g > latest) latest = g;
    }
    if (latest == 0u) return;

    uint sampleRate = max(_Data0[0].sample_rate, 1u);
    uint hopSize = max(_Data0[0].hop_size, 1u);
    float hopsPerSec = (float)sampleRate / (float)hopSize;
    float hopDt = 1.0 / max(hopsPerSec, 1e-3);

    uint cursor = (uint)max(A.a, 0.0);
    float hopCount = A.b;

    // chronological catch-up over retained hops
    uint oldest = (latest >= RING_CAP) ? (latest - RING_CAP + 1u) : 0u;
    uint start = max(cursor, oldest);

    float lowSplit = clamp(low_split, 1.0, (float)vcount - 2.0);
    float midSplit = clamp(mid_split, lowSplit + 1.0, (float)vcount - 1.0);

    [loop] for (uint gen = start; gen <= latest; ++gen) {
        uint slot = gen % RING_CAP;
        uint base = slot * vcount;
        if (base + vcount > (uint)_Data0_Count) continue;
        if (_Data0[base].generation_counter != gen) continue;   // stale slot

        float fluxLow = 0.0, fluxMid = 0.0, fluxHigh = 0.0;
        float eLow = 0.0, eMid = 0.0, eHigh = 0.0;
        float nLow = 0.0, nMid = 0.0, nHigh = 0.0;

        [loop] for (uint b = 0u; b < vcount; ++b) {
            float en = max(_Data0[base + b].energy, 0.0);
            float L = log(1.0 + en * input_gain);

            float p = Out[BANDBASE + b].a;
            float d = max(L - p, 0.0);          // half-wave rectified
            Out[BANDBASE + b].a = L;

            if ((float)b < lowSplit)      { fluxLow  += d; eLow  += L; nLow  += 1.0; }
            else if ((float)b < midSplit) { fluxMid  += d; eMid  += L; nMid  += 1.0; }
            else                          { fluxHigh += d; eHigh += L; nHigh += 1.0; }
        }

        eLow  /= max(nLow, 1.0);
        eMid  /= max(nMid, 1.0);
        eHigh /= max(nHigh, 1.0);

        // ---- adaptive thresholds: EMA mean + EMA deviation ----------------
        float aC = saturate(threshold_adapt);
        C.d = lerp(C.d, fluxLow,  aC);
        C.e = lerp(C.e, fluxMid,  aC);
        C.f = lerp(C.f, fluxHigh, aC);
        C.g = lerp(C.g, abs(fluxLow  - C.d), aC);
        C.h = lerp(C.h, abs(fluxMid  - C.e), aC);
        D.a = lerp(D.a, abs(fluxHigh - C.f), aC);

        float thrLow  = C.d + sensitivity_low  * C.g + threshold_floor;
        float thrMid  = C.e + sensitivity_mid  * C.h + threshold_floor;
        float thrHigh = C.f + sensitivity_high * D.a + threshold_floor;
        D.e = thrLow; D.f = thrMid; D.g = thrHigh;

        // ---- refractory-gated onsets --------------------------------------
        float refL = refractory_low  * hopsPerSec;
        float refM = refractory_mid  * hopsPerSec;
        float refH = refractory_high * hopsPerSec;

        float hitLow = 0.0, hitMid = 0.0, hitHigh = 0.0;
        if (fluxLow > thrLow && (hopCount - D.b) > refL) {
            hitLow = saturate((fluxLow - thrLow) / max(thrLow, 1e-4));
            D.b = hopCount; B.d += 1.0; B.g += 1.0;
        }
        if (fluxMid > thrMid && (hopCount - D.c) > refM) {
            hitMid = saturate((fluxMid - thrMid) / max(thrMid, 1e-4));
            D.c = hopCount; B.e += 1.0; B.g += 1.0;
        }
        if (fluxHigh > thrHigh && (hopCount - D.d) > refH) {
            hitHigh = saturate((fluxHigh - thrHigh) / max(thrHigh, 1e-4));
            D.d = hopCount; B.f += 1.0; B.g += 1.0;
        }

        // ---- envelopes: instant attack, authored release -------------------
        float relK = exp(-hopDt / max(release_time, 0.01));
        B.a = max(B.a * relK, hitLow);
        B.b = max(B.b * relK, hitMid);
        B.c = max(B.c * relK, hitHigh);

        C.a = lerp(C.a, eLow,  saturate(energy_smooth));
        C.b = lerp(C.b, eMid,  saturate(energy_smooth));
        C.c = lerp(C.c, eHigh, saturate(energy_smooth));
        B.h = saturate((C.a + C.b + C.c) / 3.0 * level_gain);

        // ---- history ring ---------------------------------------------------
        uint hslot = ((uint)hopCount) % HIST;
        PS rec;
        rec.a = fluxLow; rec.b = fluxMid; rec.c = fluxHigh;
        rec.d = hitLow;  rec.e = hitMid;  rec.f = hitHigh;
        rec.g = eLow;    rec.h = eHigh;
        Out[hslot] = rec;

        // ---- beat phase advances every hop; a kick corrects it -------------
        float bpm = max(A.c, 1.0);
        float beatPeriod = 60.0 / bpm;
        A.d = frac(A.d + hopDt / beatPeriod);
        if (hitLow > 0.0 && A.g > tempo_lock_min) {
            // signed phase error to the nearest beat, then nudge
            float err = A.d;
            if (err > 0.5) err -= 1.0;
            A.d = frac(A.d - err * saturate(pll_gain));
        }
        A.h = pow(saturate(1.0 - A.d), max(pulse_shape, 0.5));

        hopCount += 1.0;
    }

    // ---- tempo: autocorrelate our own onset history --------------------------
    float since = hopCount - A.e;
    if (since >= tempo_interval && hopCount > 200.0) {
        A.e = hopCount;

        float lagMin = floor(60.0 * hopsPerSec / max(bpm_max, 40.0));
        float lagMax = ceil(60.0 * hopsPerSec / max(bpm_min, 30.0));
        lagMin = clamp(lagMin, 8.0, 250.0);
        lagMax = clamp(lagMax, lagMin + 4.0, 250.0);

        // Correlation scores come from the PARALLEL tempo pass (one thread per
        // lag). Doing the search here meant ~16k iterations and 32k buffer
        // loads on a single GPU lane, invisible to the CPU-side profiler.
        float best = 0.0, bestLag = 0.0, total = 0.0;
        uint lo = (uint)lagMin, hi = (uint)lagMax;

        [loop] for (uint lag = lo; lag <= hi && lag < 256u; ++lag) {
            float s = AC[lag].x;
            total += s;
            if (s > best) { best = s; bestLag = (float)lag; }
        }

        if (bestLag > 0.0 && best > 0.0) {
            // half/double-time correction toward a musically plausible range
            float halfLag = floor(bestLag * 0.5);
            if (halfLag >= lagMin && halfLag < 256.0) {
                float sh = AC[(uint)halfLag].x;
                float candBpm = 60.0 * hopsPerSec / halfLag;
                if (sh > best * half_time_bias && candBpm <= bpm_max) bestLag = halfLag;
            }

            float newBpm = clamp(60.0 * hopsPerSec / bestLag, bpm_min, bpm_max);
            float conf = saturate(best / max(total / max(lagMax - lagMin, 1.0), 1e-6) * 0.25);

            A.c = (A.c < 1.0) ? newBpm : lerp(A.c, newBpm, saturate(tempo_smooth));
            A.f = bestLag;
            A.g = lerp(A.g, conf, 0.35);
        }
    }

    A.a = (float)(latest + 1u);
    A.b = hopCount;

    Out[HDR_A] = A;
    Out[HDR_B] = B;
    Out[HDR_C] = C;
    Out[HDR_D] = D;
}
