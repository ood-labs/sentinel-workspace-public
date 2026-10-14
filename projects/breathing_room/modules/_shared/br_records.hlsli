// br_records.hlsli -- the breathing_room record contract.
//
// Every authority in this project publishes 64-byte records: four float4 fields named
// head / dims / look / meta, discriminated by head.x (the ROLE). One layout for every buffer
// means a consumer can read any authority's records with the same struct and a role test, and
// a field can be repurposed without a manifest schema change (the schema names stay generic on
// purpose; the semantics live here, in one place).
//
// WORLD FRAME. Metres, Y up, floor at y = 0. Sentinel's camera is left-handed: with +X to the
// right and +Y up, +Z points away from the viewer. Plans are drawn north-up with +X east and
// +Z north, which is the same handedness seen from above.
//
// Walls are indexed S, E, N, W (0..3). Each wall has an inward normal n and a tangent t that is
// the VIEWER'S RIGHT when standing in the room facing that wall. Openings are positioned by an
// absolute along-wall coordinate `a` (world x for S/N walls, world z for E/W walls), so moving one
// wall never slides the openings on its neighbours.
#ifndef BR_RECORDS_HLSLI
#define BR_RECORDS_HLSLI

struct BRRec
{
    float4 head;
    float4 dims;
    float4 look;
    float4 meta;
};

// ---------------------------------------------------------------------------------------------
// ROLES (head.x). Ranges are disjoint per authority so a mixed read can never confuse them.
#define ROLE_NONE      0.0
// BR_Shell
#define ROLE_ROOM      1.0
#define ROLE_WALL      2.0
#define ROLE_OPEN      3.0
#define ROLE_SHELL_ED  9.0
#define ROLE_DELTA     8.0
// BR_Finish
#define ROLE_MAT       20.0
#define ROLE_FINISH_ED 29.0     // the board's editor header (selection), record FINISH_EDITOR
// BR_Furnish
#define ROLE_FURN      30.0
#define ROLE_FURN_ED   39.0
// BR_Light
#define ROLE_SUN       40.0
#define ROLE_LAMP      41.0
#define LAMP_KIND_FIRE 99       // the renderer's light record for the fire in the grate
#define ROLE_LIGHT_ED  49.0
// BR_Trip
#define ROLE_TRIP      50.0
#define ROLE_ANCHOR    51.0
#define ROLE_TRIP_X    52.0     // the trip's extra globals (br_trip.hlsli TRIP_EXTRA)
#define ROLE_TRIP_ED   59.0
// BR_Rug
#define ROLE_RUG       60.0
#define ROLE_RUG_ED    69.0

bool brRole(BRRec r, float role) { return abs(r.head.x - role) < 0.5; }

// ---------------------------------------------------------------------------------------------
// SHELL LAYOUT (BR_Shell "Shell" buffer, 32 records)
//   0        ROOM    head (role, style, floorPattern, flags)
//                    dims (x0, x1, z0, z1)             interior faces
//                    look (H, T, baseboardH, crownSize)
//                    meta (railH, plankW, version, generation)
//   1..4     WALL    head (role, wall, matOverride, treatment)
//                    dims (a0, a1, plane, length)      along-wall extent, interior-face coordinate
//                    look (nx, nz, tx, tz)             inward normal, viewer's-right tangent
//                    meta (openings, alarmBits, 0, active)
//   5..12    OPEN    head (role, kind, wall, slot)
//                    dims (a, width, height, sill)
//                    look (cols, rows, depth, curtains)
//                    meta (radiator, edited, active, alarmBits)
//   15       EDITOR  selection / drag / event watermark (BR_Shell private)
//   16..31   DELTA   persistent hand edits (BR_Shell private)
#define SHELL_RECORDS      32
#define SHELL_ROOM         0
#define SHELL_WALL0        1
#define SHELL_OPEN0        5
#define SHELL_OPEN_MAX     8
#define SHELL_EDITOR       15
#define SHELL_DELTA_ROOM   16
#define SHELL_DELTA_OPEN0  21

#define ROOM_FLAG_CROWN     1
#define ROOM_FLAG_RAIL      2
#define ROOM_FLAG_RADIATORS 4
#define ROOM_FLAG_CURTAINS  8

#define FLOOR_HERRINGBONE 0
#define FLOOR_CHEVRON     1
#define FLOOR_PLANK       2
#define FLOOR_BASKET      3

#define WALL_S 0
#define WALL_E 1
#define WALL_N 2
#define WALL_W 3

#define OPEN_NONE        0
#define OPEN_DOUBLEHUNG  1
#define OPEN_CASEMENT    2
#define OPEN_PICTURE     3
#define OPEN_FRENCH      4
#define OPEN_DOOR        5
#define OPEN_ARCH        6
#define OPEN_FIREPLACE   7
#define OPEN_KIND_COUNT  8

#define ALARM_OVERLAP   1
#define ALARM_CORNER    2
#define ALARM_HEAD      4
#define ALARM_TOO_WIDE  8

bool brOpenIsWindow(int k)  { return k == OPEN_DOUBLEHUNG || k == OPEN_CASEMENT || k == OPEN_PICTURE; }
bool brOpenIsGlazed(int k)  { return brOpenIsWindow(k) || k == OPEN_FRENCH; }
bool brOpenToFloor(int k)   { return k == OPEN_FRENCH || k == OPEN_DOOR || k == OPEN_ARCH; }
bool brOpenIsHole(int k)    { return k != OPEN_FIREPLACE && k != OPEN_NONE; }  // cuts the wall through

// Wall frames. n = inward normal, t = viewer's right facing the wall from inside.
float2 brWallNormal(int w)
{
    return (w == WALL_S) ? float2(0, 1) : (w == WALL_E) ? float2(-1, 0) : (w == WALL_N) ? float2(0, -1) : float2(1, 0);
}
float2 brWallTangent(int w)
{
    return (w == WALL_S) ? float2(-1, 0) : (w == WALL_E) ? float2(0, -1) : (w == WALL_N) ? float2(1, 0) : float2(0, 1);
}
// Does the wall run along world x (S/N) or world z (E/W)?
bool brWallAlongX(int w) { return w == WALL_S || w == WALL_N; }

struct BRRoom
{
    float x0, x1, z0, z1;   // interior faces
    float H, T;             // ceiling height, wall thickness
    float baseH, crown, railH, plankW;
    int style, floorPattern, flags;
};

BRRoom brRoomFromRec(BRRec r)
{
    BRRoom o;
    o.x0 = r.dims.x; o.x1 = r.dims.y; o.z0 = r.dims.z; o.z1 = r.dims.w;
    o.H = r.look.x; o.T = r.look.y; o.baseH = r.look.z; o.crown = r.look.w;
    o.railH = r.meta.x; o.plankW = r.meta.y;
    o.style = (int)round(r.head.y); o.floorPattern = (int)round(r.head.z); o.flags = (int)round(r.head.w);
    return o;
}

// A room that is always valid, for a consumer whose Shell input is unlinked.
BRRoom brDefaultRoom()
{
    BRRoom o;
    o.x0 = -3.2; o.x1 = 3.2; o.z0 = -2.5; o.z1 = 2.5;
    o.H = 2.85; o.T = 0.30; o.baseH = 0.18; o.crown = 0.11; o.railH = 2.30; o.plankW = 0.09;
    o.style = 0; o.floorPattern = FLOOR_HERRINGBONE; o.flags = ROOM_FLAG_CROWN | ROOM_FLAG_RAIL | ROOM_FLAG_RADIATORS | ROOM_FLAG_CURTAINS;
    return o;
}

// Interior-face coordinate of a wall, and its along-wall extent [a0, a1] in world units.
float brWallPlane(BRRoom r, int w)
{
    return (w == WALL_S) ? r.z0 : (w == WALL_E) ? r.x1 : (w == WALL_N) ? r.z1 : r.x0;
}
float2 brWallExtent(BRRoom r, int w)
{
    return brWallAlongX(w) ? float2(r.x0, r.x1) : float2(r.z0, r.z1);
}
float brWallLength(BRRoom r, int w) { float2 e = brWallExtent(r, w); return e.y - e.x; }

// World XZ of the point at along-wall coordinate `a`, offset `inward` metres into the room.
float2 brWallPoint(BRRoom r, int w, float a, float inward)
{
    float plane = brWallPlane(r, w);
    float2 n = brWallNormal(w);
    float2 p = brWallAlongX(w) ? float2(a, plane) : float2(plane, a);
    return p + n * inward;
}

struct BROpening
{
    int kind, wall, slot;
    float a, width, height, sill;
    float cols, rows, depth;
    bool curtains, radiator, edited, active;
    int alarms;
};

BROpening brOpeningFromRec(BRRec r)
{
    BROpening o;
    o.kind = (int)round(r.head.y); o.wall = (int)round(r.head.z); o.slot = (int)round(r.head.w);
    o.a = r.dims.x; o.width = r.dims.y; o.height = r.dims.z; o.sill = r.dims.w;
    o.cols = r.look.x; o.rows = r.look.y; o.depth = r.look.z; o.curtains = r.look.w > 0.5;
    o.radiator = r.meta.x > 0.5; o.edited = r.meta.y > 0.5; o.active = r.meta.z > 0.5 && o.kind != OPEN_NONE;
    o.alarms = (int)round(r.meta.w);
    return o;
}

// ---------------------------------------------------------------------------------------------
// MATERIAL SLOTS (BR_Finish "Finish" buffer). Fixed semantic ids so geometry can name its
// material without a lookup table; the finish board decides what each slot looks like.
#define MAT_FLOOR      0
#define MAT_WALL       1
#define MAT_CEILING    2
#define MAT_TRIM       3
#define MAT_WINDOW     4
#define MAT_GLASS      5
#define MAT_DOOR       6
#define MAT_STONE      7
#define MAT_IRON       8
#define MAT_SHEER      9
#define MAT_LINEN      10
#define MAT_LEATHER    11
#define MAT_WALNUT     12
#define MAT_BRASS      13
#define MAT_CERAMIC    14
#define MAT_RUG        15
#define MAT_VELVET     16
#define MAT_PAPER      17
#define MAT_LEAF       18
#define MAT_TERRACOTTA 19
#define MAT_SHADE      20
#define MAT_BULB       21
#define MAT_BLACKMETAL 22
#define MAT_MARBLE     23
#define MAT_SLOTS      24
#define FINISH_RECORDS 32
#define FINISH_EDITOR  31       // dims.x = the selected slot, -1 when none (BR_Render's Scope view)

// Stable 32-bit hash for record-level determinism (pcg).
uint brHash(uint v)
{
    uint state = v * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}
float brHash01(uint v) { return (float)(brHash(v) & 0x00FFFFFFu) / 16777216.0; }

#endif
