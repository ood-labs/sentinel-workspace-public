// Detection. One thread per lane.
//
// Per analysis hop, for each lane:
//
//   E     = weighted mean of the band's magnitude bins
//   flux  = max(0, dB(E) - rolling dB baseline of this band)
//   fire  = flux > threshold  AND  refractory elapsed
//
// That is all of it. `flux` is exactly the value the trace strip draws and
// `threshold` is exactly the line drawn across it, so a hit that did not happen
// is always explainable by looking at the picture.
//
// Working in dB above the band's OWN rolling level makes the threshold
// independent of input gain — which is why the module has no per-lane gain
// control. A gain would scale E and the baseline together and cancel out of the
// difference, so the knob would be a measurable no-op on detection.

#include "bands.hlsli"

StructuredBuffer<float4>   Bands : register(t1);
RWStructuredBuffer<float4> Det   : register(u0);

// Implemented locally rather than pulled from the audio feature library, so the
// hop-catch-up bound is visible next to the loop it protects. Without it a
// fresh cursor of 0 against a generation counter in the millions would spin the
// loop a million times on the first cook.
uint abCatchupStart(uint cursor, uint latest, uint capacity) {
    uint oldest = (latest + 1u > capacity) ? (latest + 1u - capacity) : 0u;
    return max(cursor, oldest);
}

[numthreads(4, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    uint lane = tid.x;
    if (lane >= AB_LANES) return;

    uint capacity = max(_Data0_HopCapacity, 1u);
    uint latest   = _Data0_Generation;
    uint vcount   = max(_Data0_ValueCount, 1u);
    uint total    = (uint)_Data0_Count;

    float4 A = Det[abStateA(lane)];
    float4 B = Det[abStateB(lane)];
    float4 C = Det[abStateC(lane)];
    // Peak-hold level meter. The raw instantaneous level swings ~40 dB between
    // hits, so displaying it showed a lane reading -85 dB while it was firing
    // steadily. A held peak answers the question the readout is actually for:
    // is there anything in this band at all.
    float levelPeak = C.x;

    float base     = A.x;
    float lastFire = A.y;
    float hopCount = A.z;
    float env      = A.w;
    float count    = B.x;
    uint  cursor   = (uint)max(B.y, 0.0);
    uint  writeIdx = (uint)max(B.z, 0.0);
    // Slowly-decaying peak flux. The trace strip scales itself to this, because
    // a fixed full scale is wrong for every input: measured peaks on real drums
    // run past 24 dB while a quiet pad barely reaches 4, and a clipped trace
    // makes the threshold impossible to place.
    float peakFlux = B.w;

    float4 bnd  = Bands[lane];
    float  loHz = bnd.x;
    float  hiHz = bnd.y;

    // Before the bands are seeded there is nothing meaningful to reduce. Keep
    // decaying the envelope so a stalled input fades out instead of latching.
    if (bnd.z < 0.5 || hiHz <= loHz) {
        env *= exp(-max(_DeltaTime, 0.0) / max(envelope_ms * 0.001, 0.005));
        Det[abStateA(lane)] = float4(base, lastFire, hopCount, env);
        Det[abStateB(lane)] = float4(count, (float)cursor, (float)writeIdx, peakFlux);
        Det[abStateC(lane)] = float4(-120.0, 1.0, 0.0, 0.0);
        return;
    }

    // Threshold rides in the band record, set by its fader on the spectrum.
    float thr   = clamp(bnd.w, 0.0, AB_THRESH_MAX);
    float refMs = (lane == 0u) ? kick_refractory_ms
                : (lane == 1u) ? snare_refractory_ms : hat_refractory_ms;

    uint start = abCatchupStart(cursor, latest, capacity);

    [loop] for (uint g = start; g <= latest; ++g) {
        if (g > start + 64u) break;                 // defensive; capacity is 64

        uint slot  = g % capacity;
        uint sbase = slot * vcount;
        if (sbase + vcount > total) continue;
        // Spectrum has no header record, so this per-record check is the only
        // way to know the slot holds the generation we think it does.
        if (_Data0[sbase].generation_counter != g) continue;

        uint sr = _Data0[sbase].sample_rate;
        uint ff = _Data0[sbase].fft_size;
        uint hs = _Data0[sbase].hop_size;
        if (sr == 0u || ff == 0u || hs == 0u) continue;

        float binHz = (float)sr / (float)ff;
        float hopDt = (float)hs / (float)sr;

        uint b0, b1;
        abBinSpan(loHz, hiHz, band_shape, binHz, b0, b1);
        b1 = min(b1, vcount - 1u);

        float esum = 0.0, wsum = 0.0;
        [loop] for (uint b = b0; b <= b1; ++b) {
            float hz = ((float)b + 0.5) * binHz;
            float w  = abWeight(hz, loHz, hiHz, band_shape);
            if (w <= 0.0) continue;
            esum += w * _Data0[sbase + b].magnitude;
            wsum += w;
        }

        // Dividing by the weight sum is what keeps widening a band from raising
        // its level. Without it every resize would need a threshold re-tune,
        // and the two controls would feel coupled for no reason.
        // Input gain shifts Edb and the baseline together, so flux is untouched
        // by design. Its only job is to lift a quiet source clear of the signal
        // gate below.
        float E   = (wsum > 0.0) ? (esum / wsum) : 0.0;
        float Edb = abSafeDb(E) + input_gain_db;

        // Seed the baseline on the first hop, or the opening frame is one
        // enormous flux against a baseline of zero and every lane fires at once.
        if (hopCount < 0.5) { base = Edb; levelPeak = Edb; }

        // Meter ballistics: instant attack, 25 dB/s release.
        levelPeak = max(Edb, levelPeak - 25.0 * hopDt);

        float flux = max(0.0, Edb - base);

        float a = 1.0 - exp(-hopDt / max(baseline_ms * 0.001, 0.005));
        base += (Edb - base) * a;

        // Fire on a LOCAL PEAK that is above the line, deciding about the
        // previous hop now that this one supplies its right-hand neighbour.
        // One hop of latency, 5.3 ms at the default hop size.
        //
        // Two simpler rules were measured and both fail. Firing on being above
        // threshold fires twice per hit, because a drum's decay stays over the
        // line for longer than any sane refractory. Firing on the upward
        // crossing fixes that but silently swallows hits on busy material: once
        // the flux stops returning below a low threshold between hits there are
        // no further crossings, so LOWERING the threshold made the hat count
        // fall from 41 to 35. A peak is still a peak in both situations.
        float f1 = (writeIdx >= 1u) ? Det[abTraceAt(lane, writeIdx - 1u)].x : -1.0;
        float f2 = (writeIdx >= 2u) ? Det[abTraceAt(lane, writeIdx - 2u)].x : -1.0;

        float refHops = max(refMs * 0.001 / max(hopDt, 1e-5), 1.0);
        // Strictly rising into the peak, so a flat top fires once at its start
        // rather than on every sample of the plateau.
        bool  peak    = (f1 > thr) && (f1 > f2) && (f1 >= flux)
                     && (Edb > AB_SILENCE_DB)
                     && ((hopCount - 1.0 - lastFire) > refHops);

        if (peak) {
            // Patch the accepted flag onto the hop that actually peaked, so the
            // tick the trace draws sits on the peak and not one hop past it.
            float4 t = Det[abTraceAt(lane, writeIdx - 1u)];
            t.z = 1.0;
            Det[abTraceAt(lane, writeIdx - 1u)] = t;

            lastFire = hopCount - 1.0;
            count   += 1.0;
            env      = 1.0;
        } else {
            env *= exp(-hopDt / max(envelope_ms * 0.001, 0.005));
        }

        // Half-life of about four seconds, so the strip scale follows a change
        // of material without twitching on individual hits.
        peakFlux = max(peakFlux * exp(-hopDt / 5.77), flux);

        // Written with the accepted flag clear; the next hop patches it if this
        // one turns out to be the peak. The band's absolute level rides along in
        // .w so stateC can report the value the gate tested.
        Det[abTraceAt(lane, writeIdx)] = float4(flux, thr, 0.0, Edb);
        writeIdx += 1u;
        hopCount += 1.0;
    }

    cursor = latest + 1u;

    // A lane whose held peak never reaches the gate can never fire, so flagging
    // it off the HELD level makes the greyed readout exactly predictive rather
    // than flickering with every gap between hits.
    Det[abStateA(lane)] = float4(base, lastFire, hopCount, saturate(env));
    Det[abStateB(lane)] = float4(count, (float)cursor, (float)writeIdx, peakFlux);
    Det[abStateC(lane)] = float4(levelPeak,
                                 (levelPeak <= AB_SILENCE_DB) ? 1.0 : 0.0, 0.0, 0.0);
}
