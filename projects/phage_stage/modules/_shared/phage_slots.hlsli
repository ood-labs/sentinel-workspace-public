// PHAGE slot layout and the posed mount record, shared by every node that addresses fixtures
// without needing the construction model itself (Lighting, LED, the Surface's mirror of it).
#ifndef PHAGE_SLOTS_HLSLI
#define PHAGE_SLOTS_HLSLI
#define PH_TAU 6.2831853
#define PH_DESIGN_COUNT 20
#define PH_SLOTS 248
#define PH_MOVER0 0
#define PH_MOVERS 128
#define PH_STROBE0 128
#define PH_STROBES 48
#define PH_BAR0 176
#define PH_BARS 64
#define PH_AXIS0 240
#define PH_AXES 8
#define PH_BAR_SEGS 12
#define PH_MEMBERS 256
// kind: 0 mover, 1 strobe, 2 pixel bar, 3 kinetic axis. up = fixture local +y (away from its
// base), fwd = local +z. A mover's beam at pan 0, tilt 0 leaves along -fwd; tilt +90 runs along up.
// A strobe emits along fwd with its tube along up. extra = (family, index in family, leg or -1, part).
// rest = the same mount at the rest pose (chase order stays put while the truss moves), w = shuffle.
// Families: movers 0 plate outer, 1 plate inner, 2 capsid, 3 knee, 4 collar, 5 booth, 6 foot;
// strobes 10 collar, 11 plate, 12 knee, 13 foot, 14 capsid, 15 booth; bars 20 leg upper,
// 21 leg lower, 22 plate edge, 23 sheath, 24 collar, 25 capsid square, 26 capsid link, 27 booth;
// axes 30 body, 31 capsid, 32 leg.
struct PhMount{float3 position;float fixture_id;float3 up;float kind;float3 fwd;float active;float4 extra;float4 rest;};
#endif
