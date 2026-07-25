// CRYOGRAM / MEASUREMENT — identity across time.
//
// The Features corner task is memoryless: every cook it hands back an unordered
// bag of points. Nothing downstream can say "this vertex is the same vertex it
// was a second ago" without this node. That is the whole job here — turn
// anonymous detections into persistent tracks with hysteresis, so the
// interpretation layer can encode CONFIDENCE as warmth and AGE as structure.
//
// Greedy nearest-neighbour association, two phases:
//   A. every live track claims its nearest unclaimed corner inside match_radius;
//      unmatched tracks coast on their own velocity and bleed confidence.
//   B. every unclaimed corner spawns a provisional track in a free slot.
//
// A track only becomes CONFIRMED after confidence climbs past the confirm
// threshold, and only dies after it falls to zero. That asymmetry is what stops
// the visuals from flickering on single-cook detector dropouts.

struct Track {
    float2 position;    // normalized analysis space
    float2 velocity;    // normalized units per second
    float age;          // seconds since spawn
    float confidence;   // 0..1, attack/release hysteresis
    float id;           // stable identity
    float active;       // 0 = free slot
};

StructuredBuffer<Track> Prev : register(t2);
RWStructuredBuffer<Track> Out : register(u0);

static const uint MAXT = 96u;
static const uint MAXC = 64u;

Track emptyTrack() {
    Track t;
    t.position = float2(0.0, 0.0);
    t.velocity = float2(0.0, 0.0);
    t.age = 0.0;
    t.confidence = 0.0;
    t.id = 0.0;
    t.active = 0.0;
    return t;
}

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    float2 asize = float2(max(analysis_width, 1), max(analysis_height, 1));

    Track header = Prev[MAXT];
    float lastTime = header.position.x;
    float nextId = header.position.y;
    if (nextId < 1.0) nextId = 1.0;

    float dt = _Time - lastTime;
    if (dt < 0.0 || dt > 0.5) dt = 1.0 / 60.0;      // first run / long stall

    uint cCount = min(_Data0_Count, MAXC);

    uint usedLo = 0u, usedHi = 0u;

    // ---- phase A: existing tracks claim corners ----------------------------
    [loop] for (uint i = 0u; i < MAXT; ++i) {
        Track t = Prev[i];

        if (t.active < 0.5) { Out[i] = emptyTrack(); continue; }

        float bestD = 1e9;
        uint bestC = 0xFFFFFFFFu;
        [loop] for (uint c = 0u; c < cCount; ++c) {
            bool taken = (c < 32u) ? ((usedLo >> c) & 1u) != 0u
                                   : ((usedHi >> (c - 32u)) & 1u) != 0u;
            if (taken) continue;
            float2 p = float2(_Data0[c].x, _Data0[c].y) / asize;
            float d = distance(p, t.position);
            if (d < bestD) { bestD = d; bestC = c; }
        }

        if (bestC != 0xFFFFFFFFu && bestD <= match_radius) {
            if (bestC < 32u) usedLo |= (1u << bestC); else usedHi |= (1u << (bestC - 32u));

            float2 target = float2(_Data0[bestC].x, _Data0[bestC].y) / asize;
            float k = saturate(track_response * dt);
            float2 newPos = lerp(t.position, target, k);

            float2 inst = (newPos - t.position) / max(dt, 1e-4);
            t.velocity = lerp(t.velocity, inst, saturate(velocity_smoothing * dt));
            t.position = newPos;
            t.confidence = min(1.0, t.confidence + attack_rate * dt);
        } else {
            // coast on prediction so a one-cook dropout does not kill identity
            t.position = saturate(t.position + t.velocity * dt * coast_gain);
            t.velocity *= saturate(1.0 - dt * 1.5);
            t.confidence -= release_rate * dt;
        }

        t.age += dt;
        if (t.confidence <= 0.0) t = emptyTrack();
        Out[i] = t;
    }

    // ---- phase B: unclaimed corners spawn provisional tracks ---------------
    uint slot = 0u;
    [loop] for (uint c2 = 0u; c2 < cCount; ++c2) {
        bool taken = (c2 < 32u) ? ((usedLo >> c2) & 1u) != 0u
                                : ((usedHi >> (c2 - 32u)) & 1u) != 0u;
        if (taken) continue;

        [loop] while (slot < MAXT && Out[slot].active > 0.5) slot++;
        if (slot >= MAXT) break;

        Track t = emptyTrack();
        t.position = saturate(float2(_Data0[c2].x, _Data0[c2].y) / asize);
        t.confidence = saturate(spawn_confidence);
        t.id = nextId;
        t.active = 1.0;
        nextId += 1.0;
        if (nextId > 99000.0) nextId = 1.0;
        Out[slot] = t;
        slot++;
    }

    // ---- header: live aggregates for control outputs -----------------------
    float activeCount = 0.0, confirmedCount = 0.0, confSum = 0.0, speedSum = 0.0;
    float2 driftSum = float2(0.0, 0.0);
    [loop] for (uint h = 0u; h < MAXT; ++h) {
        Track t = Out[h];
        if (t.active < 0.5) continue;
        activeCount += 1.0;
        confSum += t.confidence;
        speedSum += length(t.velocity);
        if (t.confidence >= confirm_threshold) {
            confirmedCount += 1.0;
            driftSum += t.velocity;
        }
    }

    Track hdr = emptyTrack();
    hdr.position = float2(_Time, nextId);
    hdr.velocity = float2(activeCount, activeCount > 0.0 ? confSum / activeCount : 0.0);
    hdr.age = activeCount > 0.0 ? speedSum / activeCount : 0.0;
    hdr.confidence = confirmedCount;
    hdr.id = frac((atan2(driftSum.y, driftSum.x) + 3.14159265) / 6.28318531);
    hdr.active = 0.0;
    Out[MAXT] = hdr;
}
