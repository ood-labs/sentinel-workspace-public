// br_furn_defs.hlsli -- the furniture catalogue shared by BR_Furnish (layout + plan) and BR_Render
// (the SDF models), so a footprint in the plan and the object in the room are the same numbers.
//
// LOCAL FRAME of every piece: origin at the centre of its footprint on its base plane (y0 above
// the floor), +y up, +z its FRONT (a sofa's seat edge, a lamp's open side, an artwork's face),
// +x its right as you face it. World from local with yaw (0 = facing +Z / north):
//     f = (sin yaw, 0, cos yaw)     r = (cos yaw, 0, -sin yaw)
//     world = pos + r * lx + up * (y0 + ly) + f * lz
#ifndef BR_FURN_DEFS_HLSLI
#define BR_FURN_DEFS_HLSLI

#define FK_NONE       0
#define FK_SOFA       1
#define FK_CHAIR      2
#define FK_COFFEE     3
#define FK_SIDE       4
#define FK_RUG        5
#define FK_FLOORLAMP  6
#define FK_TABLELAMP  7
#define FK_PENDANT    8
#define FK_SHELF      9
#define FK_CONSOLE    10
#define FK_PLANT      11
#define FK_ART        12
#define FK_CUSHION    13
#define FK_BOOKS      14
#define FK_VASE       15
#define FK_LOGS       16
#define FK_KIND_COUNT 17

#define FH_FLOOR 0      // stands on the floor (or the rug)
#define FH_WALL  1      // hangs on a wall face
#define FH_ON    2      // sits on another piece
#define FH_CEIL  3      // hangs from the ceiling

// Furnish buffer layout (112 records)
#define FURN_MAX        48
#define FURN_DELTA0     48      // 48 delta records (hand edits)
#define FURN_EDITOR     96
#define FURN_FROZEN     97
#define FURN_DIAG       98
#define FURN_RECORDS    112

// record: head (role, kind, variant, slot)
//         dims (x, z, yaw, y0)
//         look (w, h, d, seed)
//         meta (matA, matB, flags, host)   flags: 1 edited, 2 hidden, 4 alarm, 8 on (lamps)
//                                           host: -1 none, >= 0 host slot, -2 - wall for wall-hosted
#define FF_EDITED 1
#define FF_HIDDEN 2
#define FF_ALARM  4
#define FF_LIT    8

int fkVariants(int k)
{
    if (k == FK_SOFA || k == FK_CHAIR || k == FK_COFFEE || k == FK_SIDE || k == FK_RUG || k == FK_FLOORLAMP || k == FK_PENDANT || k == FK_PLANT || k == FK_ART) return 3;
    if (k == FK_TABLELAMP || k == FK_SHELF || k == FK_CUSHION) return 2;
    return 1;
}

int fkHosting(int k)
{
    if (k == FK_ART) return FH_WALL;
    if (k == FK_PENDANT) return FH_CEIL;
    if (k == FK_TABLELAMP || k == FK_CUSHION || k == FK_BOOKS || k == FK_VASE) return FH_ON;
    return FH_FLOOR;
}

bool fkIsLamp(int k) { return k == FK_FLOORLAMP || k == FK_TABLELAMP || k == FK_PENDANT; }

// default size (w along local x, h, d along local z)
float3 fkSize(int k, int v)
{
    if (k == FK_SOFA)      return (v == 0) ? float3(2.20, 0.84, 0.95) : (v == 1) ? float3(2.10, 0.79, 0.92) : float3(1.62, 0.84, 0.92);
    if (k == FK_CHAIR)     return (v == 0) ? float3(0.84, 0.78, 0.88) : (v == 1) ? float3(0.90, 0.80, 0.90) : float3(0.82, 1.14, 0.86);
    if (k == FK_COFFEE)    return (v == 0) ? float3(1.25, 0.40, 0.68) : (v == 1) ? float3(0.95, 0.36, 0.95) : float3(0.90, 0.42, 0.90);
    if (k == FK_SIDE)      return (v == 0) ? float3(0.50, 0.56, 0.50) : (v == 1) ? float3(0.46, 0.55, 0.46) : float3(0.42, 0.48, 0.42);
    if (k == FK_RUG)       return (v == 0) ? float3(2.50, 0.012, 3.40) : (v == 1) ? float3(3.00, 0.012, 4.00) : float3(2.00, 0.012, 3.00);
    if (k == FK_FLOORLAMP) return (v == 0) ? float3(0.40, 1.95, 0.40) : (v == 1) ? float3(0.58, 1.62, 0.58) : float3(0.34, 1.66, 0.34);
    if (k == FK_TABLELAMP) return (v == 0) ? float3(0.38, 0.64, 0.38) : float3(0.30, 0.58, 0.30);
    if (k == FK_PENDANT)   return (v == 0) ? float3(0.40, 0.40, 0.40) : (v == 1) ? float3(0.50, 0.56, 0.50) : float3(0.46, 0.30, 0.46);
    if (k == FK_SHELF)     return (v == 0) ? float3(0.95, 2.10, 0.34) : float3(1.40, 1.92, 0.36);
    if (k == FK_CONSOLE)   return float3(1.60, 0.62, 0.42);
    if (k == FK_PLANT)     return (v == 0) ? float3(0.80, 1.78, 0.80) : (v == 1) ? float3(0.42, 0.88, 0.42) : float3(0.70, 1.50, 0.70);
    if (k == FK_ART)       return (v == 0) ? float3(0.64, 0.84, 0.035) : (v == 1) ? float3(1.10, 0.76, 0.045) : float3(0.80, 0.80, 0.035);
    if (k == FK_CUSHION)   return (v == 0) ? float3(0.46, 0.46, 0.15) : float3(0.56, 0.36, 0.14);
    if (k == FK_BOOKS)     return float3(0.28, 0.13, 0.21);
    if (k == FK_VASE)      return float3(0.18, 0.58, 0.18);
    if (k == FK_LOGS)      return float3(0.58, 0.22, 0.30);
    return float3(0.5, 0.5, 0.5);
}

// default materials (A = main body, B = secondary)
int2 fkMats(int k, int v)
{
    if (k == FK_SOFA)      return int2(MAT_LINEN, MAT_WALNUT);
    if (k == FK_CHAIR)     return (v == 0) ? int2(MAT_LEATHER, MAT_WALNUT) : (v == 1) ? int2(MAT_VELVET, MAT_WALNUT) : int2(MAT_LINEN, MAT_WALNUT);
    if (k == FK_COFFEE)    return (v == 0) ? int2(MAT_WALNUT, MAT_WALNUT) : (v == 1) ? int2(MAT_MARBLE, MAT_BRASS) : int2(MAT_VELVET, MAT_WALNUT);
    if (k == FK_SIDE)      return (v == 2) ? int2(MAT_CERAMIC, MAT_CERAMIC) : int2(MAT_WALNUT, MAT_BRASS);
    if (k == FK_RUG)       return int2(MAT_RUG, MAT_RUG);
    if (k == FK_FLOORLAMP) return (v == 1) ? int2(MAT_WALNUT, MAT_SHADE) : int2(MAT_BRASS, MAT_SHADE);
    if (k == FK_TABLELAMP) return (v == 0) ? int2(MAT_CERAMIC, MAT_SHADE) : int2(MAT_BRASS, MAT_SHADE);
    if (k == FK_PENDANT)   return (v == 2) ? int2(MAT_BRASS, MAT_SHADE) : int2(MAT_SHADE, MAT_BRASS);
    if (k == FK_SHELF)     return int2(MAT_WALNUT, MAT_PAPER);
    if (k == FK_CONSOLE)   return int2(MAT_WALNUT, MAT_BRASS);
    if (k == FK_PLANT)     return (v == 2) ? int2(MAT_LEAF, MAT_CERAMIC) : int2(MAT_LEAF, MAT_TERRACOTTA);
    if (k == FK_ART)       return (v == 2) ? int2(MAT_BRASS, MAT_GLASS) : (v == 1) ? int2(MAT_PAPER, MAT_PAPER) : int2(MAT_BLACKMETAL, MAT_PAPER);
    if (k == FK_CUSHION)   return int2(MAT_VELVET, MAT_VELVET);
    if (k == FK_BOOKS)     return int2(MAT_PAPER, MAT_PAPER);
    if (k == FK_VASE)      return int2(MAT_CERAMIC, MAT_LEAF);
    if (k == FK_LOGS)      return int2(MAT_WALNUT, MAT_BLACKMETAL);
    return int2(MAT_WALNUT, MAT_WALNUT);
}

// The materials the M verb cycles through, per kind (upholstery, woods, metals ...).
int fkNextMat(int k, int cur)
{
    if (k == FK_SOFA || k == FK_CHAIR || k == FK_CUSHION || (k == FK_COFFEE))
    {
        if (cur == MAT_LINEN) return MAT_VELVET;
        if (cur == MAT_VELVET) return MAT_LEATHER;
        if (cur == MAT_LEATHER) return (k == FK_COFFEE) ? MAT_WALNUT : MAT_LINEN;
        if (cur == MAT_WALNUT) return MAT_MARBLE;
        if (cur == MAT_MARBLE) return MAT_LINEN;
        return MAT_LINEN;
    }
    if (k == FK_SIDE || k == FK_CONSOLE || k == FK_SHELF)
        return (cur == MAT_WALNUT) ? MAT_MARBLE : (cur == MAT_MARBLE) ? MAT_CERAMIC : MAT_WALNUT;
    if (k == FK_FLOORLAMP || k == FK_PENDANT)
        return (cur == MAT_BRASS) ? MAT_BLACKMETAL : (cur == MAT_BLACKMETAL) ? MAT_WALNUT : MAT_BRASS;
    if (k == FK_TABLELAMP || k == FK_VASE)
        return (cur == MAT_CERAMIC) ? MAT_TERRACOTTA : (cur == MAT_TERRACOTTA) ? MAT_BRASS : MAT_CERAMIC;
    if (k == FK_ART)
        return (cur == MAT_BLACKMETAL) ? MAT_WALNUT : (cur == MAT_WALNUT) ? MAT_BRASS : MAT_BLACKMETAL;
    if (k == FK_PLANT)
        return (cur == MAT_LEAF) ? MAT_LEAF : MAT_LEAF;
    return cur;
}

float3 fkForward(float yaw) { return float3(sin(yaw), 0.0, cos(yaw)); }
float3 fkRight(float yaw) { return float3(cos(yaw), 0.0, -sin(yaw)); }

// world <-> local (x, z) for a footprint
float2 fkToLocal(float2 wxz, float2 pos, float yaw)
{
    float2 d = wxz - pos;
    return float2(d.x * cos(yaw) - d.y * sin(yaw), d.x * sin(yaw) + d.y * cos(yaw));
}
float2 fkToWorld(float2 lxz, float2 pos, float yaw)
{
    return pos + float2(lxz.x * cos(yaw) + lxz.y * sin(yaw), -lxz.x * sin(yaw) + lxz.y * cos(yaw));
}

// Plan footprint half-extents (some pieces reach past their nominal box: an arc lamp's arm).
float2 fkFootHalf(int k, int v, float3 size)
{
    return size.xz * 0.5;
}

// Bulb position in local space (for the light records), and whether the kind is a lamp.
float3 fkBulbLocal(int kind, int v, float3 S)
{
    if (kind == FK_FLOORLAMP)
    {
        if (v == 0) return float3(0, 1.30 + sin(3.32) * 0.62 - 0.15, 0.62 - cos(3.32) * 0.62);
        return float3(0, (v == 1) ? 1.36 : 1.42, 0);
    }
    if (kind == FK_TABLELAMP) return float3(0, 0.45, 0);
    if (kind == FK_PENDANT) return float3(0, (v == 1) ? 0.27 : (v == 2) ? 0.06 : 0.20, 0);
    return float3(0, S.y * 0.5, 0);
}

#endif
