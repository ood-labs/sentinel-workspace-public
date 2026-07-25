// CRYOGRAM / RELIEF — kick-triggered ground swells.
//
// Each kick spawns ONE pulse at a single point and the terrain rises out of
// that point, rather than the whole massif scaling as one object. Pulses are
// independent records with their own centre, birth time and strength, so
// several can overlap and interfere while older ones relax.
//
// The centre is chosen from a CONFIRMED TRACK when one is available, so the
// swell erupts at a place the instrument has actually identified — the audio
// layer picks from the measurement layer instead of inventing a coordinate.
// Falls back to a deterministic scatter when nothing is confirmed yet.
//
// Buffer: 16 pulses + header at [16] = (prevKick, nextIdx, -, -, ...)

struct Pulse {
    float2 center;
    float birth;
    float strength;
    float seed;
    float active;
    float2 pad;
};

StructuredBuffer<Pulse> Prev : register(t0);
RWStructuredBuffer<Pulse> Out : register(u0);

static const uint MAXPULSE = 16u;

Pulse emptyPulse() {
    Pulse p;
    p.center = float2(0.5, 0.5);
    p.birth = -1000.0;
    p.strength = 0.0;
    p.seed = 0.0;
    p.active = 0.0;
    p.pad = float2(0.0, 0.0);
    return p;
}

uint pulseHash(uint v) {
    v = v * 747796405u + 2891336453u;
    v = ((v >> ((v >> 28u) + 4u)) ^ v) * 277803737u;
    return (v >> 22u) ^ v;
}

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    [loop] for (uint i = 0u; i < MAXPULSE; ++i) {
        Pulse p = Prev[i];
        if (p.active > 0.5 && (_Time - p.birth) > pulse_life) p = emptyPulse();
        Out[i] = p;
    }

    Pulse hdr = Prev[MAXPULSE];
    float prevCount = hdr.center.x;
    float nextIdx = hdr.center.y;
    float initFlag = hdr.strength;

    // Trigger on the detector's ACCEPTED-ONSET COUNTER, not on the envelope
    // crossing a threshold. The envelope has to decay back below the threshold
    // before it can arm again, so at 133bpm with a 0.24s release any kick
    // landing during the previous decay was silently swallowed — which is
    // exactly the "it misses most of them" symptom. The counter is exact: one
    // increment per accepted onset, no threshold, nothing to miss.
    float delta = kick_count_in - prevCount;

    // first cook, counter reset, or a long stall: resync without a burst
    bool resync = (initFlag < 0.5) || (delta < 0.0) || (delta > 16.0);
    bool fire = !resync && (delta >= 1.0);

    if (fire) {
        uint idx = (uint)max(nextIdx, 0.0);
        uint h = pulseHash(idx * 2654435761u + 12345u);

        // prefer a confirmed identity as the eruption point
        float2 center = float2(-1.0, -1.0);
        uint tCount = min(_Data1_Count, 97u);
        uint confirmed = 0u;
        [loop] for (uint t = 0u; t < tCount; ++t) {
            if (_Data1[t].active < 0.5) continue;
            if (_Data1[t].confidence < pulse_track_confidence) continue;
            confirmed++;
        }
        if (confirmed > 0u && pulse_on_tracks > 0.5) {
            uint want = h % confirmed;
            uint seen = 0u;
            [loop] for (uint t2 = 0u; t2 < tCount; ++t2) {
                if (_Data1[t2].active < 0.5) continue;
                if (_Data1[t2].confidence < pulse_track_confidence) continue;
                if (seen == want) { center = _Data1[t2].position; break; }
                seen++;
            }
        }
        if (center.x < 0.0) {
            center = float2((float)(h & 0xFFFFu) / 65535.0,
                            (float)((h >> 16u) & 0xFFFFu) / 65535.0);
            center = 0.5 + (center - 0.5) * 0.86;      // keep off the extreme edge
        }

        Pulse np = emptyPulse();
        np.center = saturate(center);
        np.birth = _Time;
        // Every accepted kick must produce a VISIBLE swell. The envelope only
        // modulates above a guaranteed floor — it can no longer scale a hit
        // down to nothing just because it was sampled mid-decay.
        np.strength = clamp(kick_level * pulse_strength_gain,
                            pulse_min_strength, 1.0);
        np.seed = (float)(h & 0xFFFu) / 4095.0;
        np.active = 1.0;
        Out[idx % MAXPULSE] = np;

        nextIdx = nextIdx + 1.0;
        if (nextIdx > 1.0e6) nextIdx = 0.0;
    }

    Pulse nh = emptyPulse();
    nh.center = float2(kick_count_in, nextIdx);
    nh.strength = 1.0;              // init marker
    nh.active = 0.0;
    Out[MAXPULSE] = nh;
}
