#ifndef AU_STYLUS_TYPES_HLSLI
#define AU_STYLUS_TYPES_HLSLI

// AUTOPSIA — operator stimulus. 48 bytes. MUST match au_specimen's contract.
struct StimulusRecord {
    float2 position;
    float2 direction;
    float radius;
    float strength;
    float age;
    float mode;      // 0 = mass, 1 = incision
    uint id;
    uint flags;      // bit0 = active
    float2 pad;
};

#define STIM_SLOTS 16u
#define CTRL_SLOT  16u
#define STIM_ACTIVE 1u
#define CTRL_INIT   2u

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

bool stimActive(StimulusRecord s) { return (s.flags & STIM_ACTIVE) != 0u; }

#endif
