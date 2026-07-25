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
//   [654]  E: hitSerial (BASELINE ONLY)
//   [655 .. 1166]  hits ring (BASELINE ONLY): lane, serial, hop, samplePos, strength
//
// BASELINE COPY. Detection maths is identical to modules/cryo_pulse. The only
// addition is the accepted-onset ring at [655..1166], written after the
// existing acceptance tests and read out by the hitsexport pass. Nothing above
// reads it, so it cannot influence detection.

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
static const uint HDR_E    = 654u;   // baseline: hit serial counter
static const uint HITS_BASE = 655u;  // baseline: accepted-onset ring
static const uint HITCAP   = 512u;   // holds a whole 20 s corpus pattern
static const uint TOTAL    = 1167u;
static const uint RING_CAP = 64u;

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    // carry all state forward
    [loop] for (uint i = 0u; i < TOTAL; ++i) Out[i] = Prev[i];

    PS A = Prev[HDR_A];
    PS B = Prev[HDR_B];
    PS C = Prev[HDR_C];
    PS D = Prev[HDR_D];
    PS E = Prev[HDR_E];   // baseline: hit serial counter

    // Sentinel 0.5.49 injects generation metadata per data input, so the
    // latest generation no longer has to be inferred. Element zero of Spectrum
    // and Mel Bands is ring slot zero, NOT a header, and reading its generation
    // goes stale until the 64-hop ring wraps (~341ms) — which is what made this
    // detector appear to run at 3fps. These uniforms remove the ambiguity.
    uint vcount = min(_Data0_ValueCount, MAXBAND);
    if (vcount == 0u) return;

    uint capacity = max(_Data0_HopCapacity, 1u);
    uint latest = _Data0_Generation;
    if (latest == 0u) return;

    uint sampleRate = max(_Data0[0].sample_rate, 1u);
    uint hopSize = max(_Data0[0].hop_size, 1u);
    float hopsPerSec = (float)sampleRate / (float)hopSize;
    float hopDt = 1.0 / max(hopsPerSec, 1e-3);

    uint cursor = (uint)max(A.a, 0.0);
    float hopCount = A.b;

    // chronological catch-up over retained hops
    uint oldest = (latest >= capacity) ? (latest - capacity + 1u) : 0u;
    uint start = max(cursor, oldest);

    // ---- signal gate -------------------------------------------------------
    // Adaptive thresholds normalise to whatever reaches them, so on a noise
    // floor they will happily manufacture confident onsets — this detector
    // previously reported BPM 96 at 99% confidence on a dead endpoint. Gate on
    // the engine's own capture level (driven in via expression), not on our own
    // normalised energy, which cannot tell noise from music by construction.
    bool gated = (gate_level < signal_floor);
    D.h = gated ? 0.0 : 1.0;

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
        bool firedLow = false, firedMid = false, firedHigh = false;
        if (gated) {
            // still advance history and thresholds so the detector re-acquires
            // instantly when signal returns, but accept no onsets
        }
        else if (fluxLow > thrLow && (hopCount - D.b) > refL) {
            hitLow = saturate((fluxLow - thrLow) / max(thrLow, 1e-4));
            D.b = hopCount; B.d += 1.0; B.g += 1.0; firedLow = true;
        }
        if (!gated && fluxMid > thrMid && (hopCount - D.c) > refM) {
            hitMid = saturate((fluxMid - thrMid) / max(thrMid, 1e-4));
            D.c = hopCount; B.e += 1.0; B.g += 1.0; firedMid = true;
        }
        if (!gated && fluxHigh > thrHigh && (hopCount - D.d) > refH) {
            hitHigh = saturate((fluxHigh - thrHigh) / max(thrHigh, 1e-4));
            D.d = hopCount; B.f += 1.0; B.g += 1.0; firedHigh = true;
        }

        // ---- BASELINE ONLY: export accepted onsets with their sample position.
        // Purely additive. Nothing above or below reads this ring, so it cannot
        // change what the detector accepts. `sample_position` is the producer's
        // own timestamp for this hop, which is the harness timebase.
        float hopSamplePos = (float)_Data0[base].sample_position;
        if (firedLow) {
            E.a += 1.0;
            PS hr; hr.a = 0.0; hr.b = E.a; hr.c = hopCount; hr.d = hopSamplePos;
            hr.e = hitLow; hr.f = 0.0; hr.g = 0.0; hr.h = 0.0;
            Out[HITS_BASE + (((uint)E.a - 1u) % HITCAP)] = hr;
        }
        if (firedMid) {
            E.a += 1.0;
            PS hr; hr.a = 1.0; hr.b = E.a; hr.c = hopCount; hr.d = hopSamplePos;
            hr.e = hitMid; hr.f = 0.0; hr.g = 0.0; hr.h = 0.0;
            Out[HITS_BASE + (((uint)E.a - 1u) % HITCAP)] = hr;
        }
        if (firedHigh) {
            E.a += 1.0;
            PS hr; hr.a = 2.0; hr.b = E.a; hr.c = hopCount; hr.d = hopSamplePos;
            hr.e = hitHigh; hr.f = 0.0; hr.g = 0.0; hr.h = 0.0;
            Out[HITS_BASE + (((uint)E.a - 1u) % HITCAP)] = hr;
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
        float phasePrev = A.d;
        A.d = frac(A.d + hopDt / beatPeriod);

        // BASELINE ONLY: emit a beat event on each phase wrap, as lane 3. The
        // PLL already computes this phase; reading its wrap adds no maths and
        // gives the harness a beat TRAIN rather than a polled scalar, which is
        // what CMLc/AMLc require. Envelope-threshold triggering is deliberately
        // avoided here (see the phase doc's second CRYOGRAM trap).
        if (!gated && A.d < phasePrev && A.g > tempo_lock_min) {
            E.a += 1.0;
            PS br; br.a = 3.0; br.b = E.a; br.c = hopCount; br.d = hopSamplePos;
            br.e = A.g; br.f = bpm; br.g = 0.0; br.h = 0.0;
            Out[HITS_BASE + (((uint)E.a - 1u) % HITCAP)] = br;
        }
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
    // Tempo confidence decays toward zero while gated, so a silent or dead
    // endpoint reports "I don't know" instead of a confident wrong answer.
    if (gated) A.g = max(A.g - 0.02, 0.0);

    float since = hopCount - A.e;
    if (!gated && since >= tempo_interval && hopCount > 200.0) {
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
    Out[HDR_E] = E;
}
