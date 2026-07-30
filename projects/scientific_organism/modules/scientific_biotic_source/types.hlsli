#ifndef SCIENTIFIC_BIOTIC_SOURCE_TYPES_HLSLI
#define SCIENTIFIC_BIOTIC_SOURCE_TYPES_HLSLI

struct StimulusRecord {
    float2 position;
    float2 direction;
    float radius;
    float strength;
    float age;
    float mode;
    uint id;
    uint flags;
    float2 pad;
};

bool stimulusActive(StimulusRecord stimulus) {
    return (stimulus.flags & 1u) != 0u;
}

#endif
