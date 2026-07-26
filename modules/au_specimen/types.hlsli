#ifndef AU_SPECIMEN_TYPES_HLSLI
#define AU_SPECIMEN_TYPES_HLSLI

// AUTOPSIA — stimulus record injected by the operator's stylus.
// 48 bytes, frozen contract shared with au_stylus.
struct StimulusRecord {
    float2 position;   // normalized plate coordinates
    float2 direction;  // unit drag direction
    float radius;      // normalized influence radius
    float strength;    // 0..1 magnitude
    float age;         // seconds since deposit
    float mode;        // 0 = attract / mass, 1 = vortex / incision
    uint id;
    uint flags;        // bit0 = active
    float2 pad;
};

bool stimulusActive(StimulusRecord s) {
    return (s.flags & 1u) != 0u && s.strength > 0.0005;
}

StimulusRecord emptyStimulus() {
    StimulusRecord s;
    s.position = float2(0.5, 0.5);
    s.direction = float2(0.0, 1.0);
    s.radius = 0.0;
    s.strength = 0.0;
    s.age = 0.0;
    s.mode = 0.0;
    s.id = 0u;
    s.flags = 0u;
    s.pad = float2(0.0, 0.0);
    return s;
}

// ---- value noise -----------------------------------------------------------

float au_hash21(float2 p) {
    p = frac(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return frac(p.x * p.y);
}

float2 au_hash22(float2 p) {
    float3 a = frac(p.xyx * float3(123.34, 234.34, 345.65));
    a += dot(a, a + 34.45);
    return frac(float2(a.x * a.y, a.y * a.z));
}

// Jittered-lattice nucleation. Returns a field of discrete compact peaks —
// the specimen's cells. Unlike fbm these are genuinely separable, which is what
// lets the observing Features node resolve them as individual masses.
float au_nuclei(float2 p, float sharpness) {
    float2 cp = p;
    float2 ci = floor(cp);
    float best = 0.0;
    [unroll] for (int dy = -1; dy <= 1; ++dy) {
        [unroll] for (int dx = -1; dx <= 1; ++dx) {
            float2 g = ci + float2(dx, dy);
            float2 j = au_hash22(g);
            float2 centre = g + 0.25 + j * 0.5;
            float2 d = cp - centre;
            float amp = 0.65 + 0.35 * j.x;          // cells vary in strength
            best = max(best, exp(-dot(d, d) * max(sharpness, 0.5)) * amp);
        }
    }
    return best;
}

float au_vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = frac(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = au_hash21(i);
    float b = au_hash21(i + float2(1.0, 0.0));
    float c = au_hash21(i + float2(0.0, 1.0));
    float d = au_hash21(i + float2(1.0, 1.0));
    return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
}

float au_fbm(float2 p, int octaves) {
    float sum = 0.0;
    float amp = 0.5;
    float norm = 0.0;
    [loop] for (int o = 0; o < octaves; ++o) {
        sum += au_vnoise(p) * amp;
        norm += amp;
        p = p * 2.03 + float2(17.1, 9.7);
        amp *= 0.5;
    }
    return sum / max(norm, 1e-5);
}

#endif
