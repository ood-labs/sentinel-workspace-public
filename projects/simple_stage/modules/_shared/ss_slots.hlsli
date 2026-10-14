// SIMPLE STAGE slot layout and the mount record, shared by every node that addresses fixtures without needing the
// construction model itself (Lighting, the Renderer, the canvases). The counts are tools/ss_layout.py's.
#ifndef SS_SLOTS_HLSLI
#define SS_SLOTS_HLSLI
#include "../_shared/ss_layout.hlsli"
#define SS_TAU 6.2831853
// kind: 0 mover, 1 strobe, 2 pixel run. up = fixture local +y (away from its base), fwd = local +z. A mover's beam at
// pan 0, tilt 0 leaves along -fwd; tilt +90 runs along up. A strobe emits along fwd with its tube along up. A run's
// mount is the middle of its pieces, facing along fwd. extra = (family, index in family, group, 0); rest = the mount
// position, w = the shuffle rank. Families: movers 0 front row, 1 back row; strobes 10 truss, 11 floor; runs 20 the
// wall. Groups (the GROUP chase order): 0 front truss, 1 back truss, 2 the floor line, 3 the wall.
struct SsMount{float3 position;float fixture_id;float3 up;float kind;float3 fwd;float active;float4 extra;float4 rest;};
#endif
