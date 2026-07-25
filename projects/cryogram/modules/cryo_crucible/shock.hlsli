// CRYOGRAM / SPECIMEN — snare shock record.
//
// Modulating nucleation, growth or anneal changes what the crystal does over
// SECONDS. None of it can read as a beat. A shock is an instantaneous event:
// on every accepted snare onset it punches liquid into the plate at a point and
// throws a radial displacement outward from it, both decaying in a few hundred
// milliseconds.
//
// Struct only. Declare `StructuredBuffer<Shock> Shocks : register(tN);` in the
// consuming shader, then include shock_apply.hlsli for the helpers.

#ifndef CRYO_SHOCK_HLSLI
#define CRYO_SHOCK_HLSLI

struct Shock {
    float2 center;
    float birth;
    float strength;
    float seed;
    float active;
    float2 pad;
};

static const uint CRYO_MAXSHOCK = 8u;

#endif
