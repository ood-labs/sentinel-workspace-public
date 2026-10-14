// The Venue publishes ONE packed float4 buffer (a Module takes at most eight data inputs):
// [0..4] room settings (fill, material, tint, bounds, finish), [8 + 3k] 64 pixel-run emitters (a, b, radiance),
// [200 + 4j] 256 architecture boxes (center, extent, surface, rotation), [1224 + 2i] 1536 people (p, look).
// bounds = (width, length, height, floor); finish = (floor wear, wall texture, the room's centre along z, -).
#ifndef SS_VENUE_HLSLI
#define SS_VENUE_HLSLI
#define PV_ROOM 0
#define PV_EMIT 8
#define PV_ARCH 200
#define PV_CROWD 1224
#define PV_COUNT 4296
#define PV_EMITTERS 64
#define PV_BOXES 256
#define PV_PEOPLE 1536
#endif
