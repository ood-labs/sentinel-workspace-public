// CRYOGRAM / MEASUREMENT — bonded structure over confirmed identities.
//
// Only CONFIRMED tracks are eligible. Provisional detections must not be able
// to create structure, or the lattice flickers with the detector instead of
// describing the specimen.
//
// Each node bonds to its k nearest eligible neighbours inside link_radius,
// deduplicated by emitting an edge only from the lower slot index. Strain is
// measured against the lattice's OWN characteristic spacing (the mean
// nearest-neighbour distance this cook), not against an authored constant — so
// "stretched" always means stretched relative to how tightly this particular
// crystal is currently packed.

struct Filament {
    float2 a;
    float2 b;
    float idA;
    float idB;
    float len;
    float strain;
    float weight;
    float age;
    float2 pad;
};

RWStructuredBuffer<Filament> Out : register(u0);

static const uint MAXN = 48u;
static const uint MAXE = 160u;

Filament emptyFilament() {
    Filament f;
    f.a = float2(0.0, 0.0);
    f.b = float2(0.0, 0.0);
    f.idA = 0.0; f.idB = 0.0;
    f.len = 0.0; f.strain = 0.0;
    f.weight = 0.0; f.age = 0.0;
    f.pad = float2(0.0, 0.0);
    return f;
}

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    float2 P[48];
    float NID[48];
    float NCF[48];
    float NAG[48];
    uint n = 0u;

    // ---- eligibility: confirmed tracks only --------------------------------
    uint tCount = min(_Data0_Count, 97u);
    [loop] for (uint i = 0u; i < tCount; ++i) {
        if (n >= MAXN) break;
        if (_Data0[i].active < 0.5) continue;
        if (_Data0[i].confidence < eligible_confidence) continue;
        P[n] = _Data0[i].position;
        NID[n] = _Data0[i].id;
        NCF[n] = _Data0[i].confidence;
        NAG[n] = _Data0[i].age;
        n++;
    }

    // ---- characteristic spacing = mean nearest-neighbour distance ----------
    float spacing = 0.0;
    if (n > 1u) {
        float sum = 0.0;
        [loop] for (uint s = 0u; s < n; ++s) {
            float best = 1e9;
            [loop] for (uint q = 0u; q < n; ++q) {
                if (q == s) continue;
                best = min(best, distance(P[s], P[q]));
            }
            sum += best;
        }
        spacing = sum / (float)n;
    }
    if (spacing < 1e-4) spacing = 0.05;

    uint deg = (uint)clamp(max_degree, 1, 6);
    uint e = 0u;

    [loop] for (uint a = 0u; a < n; ++a) {
        uint usedLo = 0u, usedHi = 0u;

        [loop] for (uint k = 0u; k < deg; ++k) {
            float bestD = 1e9;
            uint bestJ = 0xFFFFFFFFu;

            [loop] for (uint b = 0u; b < n; ++b) {
                if (b == a) continue;
                bool taken = (b < 32u) ? ((usedLo >> b) & 1u) != 0u
                                       : ((usedHi >> (b - 32u)) & 1u) != 0u;
                if (taken) continue;
                float d = distance(P[a], P[b]);
                if (d < bestD) { bestD = d; bestJ = b; }
            }

            if (bestJ == 0xFFFFFFFFu) break;
            if (bestJ < 32u) usedLo |= (1u << bestJ); else usedHi |= (1u << (bestJ - 32u));
            if (bestD > link_radius) break;          // nearest already too far
            if (bestJ < a) continue;                 // dedupe: emit once, from the lower index
            if (e >= MAXE) break;

            Filament f = emptyFilament();
            f.a = P[a];
            f.b = P[bestJ];
            f.idA = NID[a];
            f.idB = NID[bestJ];
            f.len = bestD;
            f.strain = (bestD - spacing) / spacing;
            f.weight = min(NCF[a], NCF[bestJ]);
            f.age = min(NAG[a], NAG[bestJ]);
            Out[e] = f;
            e++;
        }
        if (e >= MAXE) break;
    }

    [loop] for (uint z = e; z < MAXE; ++z) Out[z] = emptyFilament();

    // header at MAXE: live aggregates
    Filament hdr = emptyFilament();
    hdr.a = float2((float)e, (float)n);
    hdr.b = float2(spacing, 0.0);
    hdr.len = spacing;
    Out[MAXE] = hdr;
}
