// furnish_defs.hlsli -- BR_Furnish's slot roles, relationship frames and footprint geometry, shared
// by the authority pass (furnish.hlsl) and the canvas so both read the records the same way.
//
// A SLOT IS A ROLE. Slot 1 is always "the sofa", slot 7 always "the lamp on side table A". So a
// hand edit (a variant, a material, a nudge) belongs to a role and survives a re-roll of the
// arrangement, and a renderer or a lighting authority can address "the floor lamp" directly.
//
// Every piece has a PARENT and a local pose in that parent's frame. The conversation group hangs
// off the rug (move the rug, the group comes with it), side tables hang off the sofa, a table
// lamp sits ON its side table, shelves and art belong to a wall, a vase to the mantel. The
// published record carries the composed WORLD pose and the parent code, so consumers never have
// to walk the tree.
#ifndef FURNISH_DEFS_HLSLI
#define FURNISH_DEFS_HLSLI

#include "../_shared/br_records.hlsli"
#include "../_shared/br_furn_defs.hlsli"

#define FS_RUG        0
#define FS_SOFA       1
#define FS_CHAIR_A    2
#define FS_CHAIR_B    3
#define FS_COFFEE     4
#define FS_SIDE_A     5
#define FS_SIDE_B     6
#define FS_LAMP_A     7
#define FS_LAMP_B     8
#define FS_FLOORLAMP  9
#define FS_PENDANT    10
#define FS_SHELF_A    11
#define FS_SHELF_B    12
#define FS_CONSOLE    13
#define FS_PLANT_A    14
#define FS_PLANT_B    15
#define FS_PLANT_C    16
#define FS_ART_A      17
#define FS_ART_B      18
#define FS_MIRROR     19
#define FS_CUSH_A     20
#define FS_CUSH_B     21
#define FS_CUSH_C     22
#define FS_CUSH_D     23
#define FS_BOOKS_A    24
#define FS_VASE_A     25
#define FS_BOOKS_B    26
#define FS_LAMP_C     27
#define FS_VASE_B     28
#define FS_LOGS       29
#define FS_COUNT      30

// parent codes (record meta.w): >= 0 is a slot; the rest are frames of the room itself
#define FP_WORLD    -1
#define FP_WALL0    -2          // wall w is -2 - w (S E N W = -2 -3 -4 -5)
#define FP_MANTEL   -6
#define FP_FIREBOX  -7

// published extras
#define FURN_RULES    99        // design-rule readouts
#define FURN_ROUTE0   100       // 12 records = 24 route points (xz pairs)
#define FURN_ROUTE_N  24

// rule alarm bits (rules record meta.x)
#define RULE_COFFEE   1
#define RULE_CONVERSE 2
#define RULE_WALKWAY  4
#define RULE_HEARTH   8
#define RULE_DOOR     16
#define RULE_OVERLAP  32
#define RULE_BLOCKED  64

#define ARR_HEARTH  0
#define ARR_FACING  1
#define ARR_VIEW    2
#define ARR_READING 3

int fsKind(int s)
{
    if (s == FS_RUG) return FK_RUG;
    if (s == FS_SOFA) return FK_SOFA;
    if (s == FS_CHAIR_A || s == FS_CHAIR_B) return FK_CHAIR;
    if (s == FS_COFFEE) return FK_COFFEE;
    if (s == FS_SIDE_A || s == FS_SIDE_B) return FK_SIDE;
    if (s == FS_LAMP_A || s == FS_LAMP_B || s == FS_LAMP_C) return FK_TABLELAMP;
    if (s == FS_FLOORLAMP) return FK_FLOORLAMP;
    if (s == FS_PENDANT) return FK_PENDANT;
    if (s == FS_SHELF_A || s == FS_SHELF_B) return FK_SHELF;
    if (s == FS_CONSOLE) return FK_CONSOLE;
    if (s >= FS_PLANT_A && s <= FS_PLANT_C) return FK_PLANT;
    if (s == FS_ART_A || s == FS_ART_B || s == FS_MIRROR) return FK_ART;
    if (s >= FS_CUSH_A && s <= FS_CUSH_D) return FK_CUSHION;
    if (s == FS_BOOKS_A || s == FS_BOOKS_B) return FK_BOOKS;
    if (s == FS_VASE_A || s == FS_VASE_B) return FK_VASE;
    if (s == FS_LOGS) return FK_LOGS;
    return FK_NONE;
}

// Pieces that stand on the floor and take up walking room (the rug does not).
bool fkIsFloorBody(int k)
{
    return k == FK_SOFA || k == FK_CHAIR || k == FK_COFFEE || k == FK_SIDE || k == FK_FLOORLAMP
        || k == FK_SHELF || k == FK_CONSOLE || k == FK_PLANT;
}
bool fkIsSeat(int k) { return k == FK_SOFA || k == FK_CHAIR; }

// Height of the surface an ON piece sits on, in the host's local frame.
float fkHostTop(int k, int v, float3 size)
{
    if (k == FK_SOFA) return 0.45;
    if (k == FK_CHAIR) return (v == 0) ? 0.41 : 0.43;
    return size.y;
}
// Footprint radius used for picking round things.
bool fkRound(int k, int v)
{
    return (k == FK_SIDE && v != 1) || (k == FK_COFFEE && v != 0) || k == FK_FLOORLAMP || k == FK_PLANT
        || k == FK_TABLELAMP || k == FK_PENDANT || k == FK_VASE;
}

float2 fwd2(float yaw) { return float2(sin(yaw), cos(yaw)); }
float2 right2(float yaw) { return float2(cos(yaw), -sin(yaw)); }
float2 toWorld2(float2 o, float yaw, float2 l) { return o + right2(yaw) * l.x + fwd2(yaw) * l.y; }
float2 toLocal2(float2 o, float yaw, float2 w) { float2 d = w - o; return float2(dot(d, right2(yaw)), dot(d, fwd2(yaw))); }
float yawOf2(float2 f) { return atan2(f.x, f.y); }
float wrapPi(float a) { return a - 6.2831853 * floor((a + 3.14159265) / 6.2831853); }

// Signed distance from world point p (xz) to a piece's footprint rectangle.
float footSd(float2 p, float2 c, float yaw, float2 halfWD)
{
    float2 l = toLocal2(c, yaw, p);
    float2 q = abs(l) - halfWD;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}

// Record accessors
struct FPiece
{
    int slot, kind, variant, parent, flags, matA, matB;
    float2 pos;
    float yaw, y0, seed;
    float3 size;
};
FPiece fpFromRec(BRRec r)
{
    FPiece p;
    p.kind = (int)round(r.head.y); p.variant = (int)round(r.head.z); p.slot = (int)round(r.head.w);
    p.pos = r.dims.xy; p.yaw = r.dims.z; p.y0 = r.dims.w;
    p.size = r.look.xyz; p.seed = r.look.w;
    p.matA = (int)round(r.meta.x); p.matB = (int)round(r.meta.y); p.flags = (int)round(r.meta.z); p.parent = (int)round(r.meta.w);
    return p;
}
BRRec fpToRec(FPiece p)
{
    BRRec r;
    r.head = float4(ROLE_FURN, p.kind, p.variant, p.slot);
    r.dims = float4(p.pos, p.yaw, p.y0);
    r.look = float4(p.size, p.seed);
    r.meta = float4(p.matA, p.matB, p.flags, p.parent);
    return r;
}
bool fpVisible(FPiece p) { return p.kind != FK_NONE && (p.flags & FF_HIDDEN) == 0; }

#endif
