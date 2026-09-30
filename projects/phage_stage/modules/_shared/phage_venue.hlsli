// The Venue publishes ONE packed float4 buffer (a Module takes at most eight data inputs):
// [0..4] room settings (fill, material, tint, bounds, finish), [8 + 3k] 96 bar emitters (a, b, radiance),
// [296 + 4j] 256 architecture boxes (center, extent, surface, rotation), [1320 + 2i] 3072 people (p, look).
#ifndef PHAGE_VENUE_HLSLI
#define PHAGE_VENUE_HLSLI
#define PV_ROOM 0
#define PV_EMIT 8
#define PV_ARCH 296
#define PV_CROWD 1320
#define PV_COUNT 7464
#define PV_EMITTERS 96
#define PV_BOXES 256
#define PV_PEOPLE 3072
#endif
