// BR_Furnish / furnish.hlsl -- the furniture authority. One thread, once per cook.
//
//   1. read the room (BR_Shell) and resolve every piece: kind, variant, size, parent, local pose
//      from the RELATIONAL generator, plus the persistent hand edits (deltas)
//   2. consume this cook's viewport events (each exactly once, by sequence) into those deltas
//   3. resolve again, compose world poses down the parent tree, measure the design rules (coffee
//      gap, conversation distance, hearth clearance, door swing, overlaps, the walkway from the
//      door to the windows), publish records 0..47 plus the rules and the route
//
// THE GENERATOR RANDOMISES RELATIONSHIPS, NOT COORDINATES. A re-roll picks which way the chairs
// turn, which arm the floor lamp stands by, which variants pair up, which window corner gets the
// fig -- never a free (x, z) per piece -- so every seed is a room someone would actually set up:
// the rug anchors the conversation group, the coffee table keeps its 45 cm from the sofa, side
// tables flank the arms, lamps sit ON tables, shelves fill the chimney alcoves, art hangs over
// the console at eye level, the mirror over the mantel.
//
// EDITS ARE DELTAS in the piece's PARENT frame. Drag the rug and the whole group follows; drag
// the sofa and its side tables, lamps and cushions follow. A lamp dragged onto another table is
// re-hosted there (the delta becomes an absolute pose in the new host's frame).
#include "../_shared/br_records.hlsli"
#include "../_shared/br_furn_defs.hlsli"
#include "furnish_defs.hlsli"
#include "furnish_layout.hlsli"

RWStructuredBuffer<BRRec> Furn : register(u0);

#define PLAN_VERSION 1.3
#define PI 3.14159265

#define H_NONE    0
#define H_MOVE    1
#define H_ROT     2
#define H_WIDTH   3
#define H_DEPTH   4
#define H_SECMOVE 5

#define DB_EDITED 1
#define DB_ABS    2

#define REC_FROZEN 97

groupshared float gClr[1600];
groupshared float gCost[1600];
groupshared float gPen[1600];     // the sweep's step penalty per cell, from its clearance
// The walkway's obstacles, resolved once per solve rather than once per grid cell: xy centre and
// the footprint's right axis (zw), then its forward axis (xy) and half extents (zw). A round piece
// keeps only its radius (gObB.z).
#define OB_MAX 48
groupshared float4 gObA[OB_MAX];
groupshared float4 gObB[OB_MAX];
groupshared uint   gObRound[OB_MAX];

float sane(float v) { return (abs(v) < 1e4) ? v : 0.0; }
float snapTo(float v, float step) { return (step > 1e-4) ? round(v / step) * step : v; }

// ---------------------------------------------------------------------------------------------
// SHELL INPUT
BRRec sh(uint i) { BRRec r; r.head = _Data0[i].head; r.dims = _Data0[i].dims; r.look = _Data0[i].look; r.meta = _Data0[i].meta; return r; }

BROpening defaultOpening(int i)
{
    BROpening o;
    o.kind = OPEN_NONE; o.wall = WALL_W; o.slot = i; o.a = 0; o.width = 1; o.height = 1.8; o.sill = 0.6;
    o.cols = 1; o.rows = 1; o.depth = 0; o.curtains = false; o.radiator = false; o.edited = false; o.active = false; o.alarms = 0;
    if (i == 0 || i == 1) { o.kind = OPEN_DOUBLEHUNG; o.wall = WALL_W; o.a = (i == 0) ? -1.15 : 1.15; o.width = 1.05; o.height = 1.82; o.sill = 0.55; o.cols = 2; o.curtains = true; o.radiator = true; o.active = true; }
    if (i == 3) { o.kind = OPEN_FIREPLACE; o.wall = WALL_N; o.a = 0.0; o.width = 1.80; o.height = 1.24; o.sill = 0.0; o.cols = 0.86; o.rows = 0.80; o.depth = 0.36; o.active = true; }
    if (i == 4) { o.kind = OPEN_DOOR; o.wall = WALL_E; o.a = 1.755; o.width = 0.85; o.height = 2.10; o.sill = 0.0; o.cols = 2; o.rows = 3; o.active = true; }
    return o;
}

// ---------------------------------------------------------------------------------------------
// PIECES + DELTAS
struct Piece
{
    int kind, variant, parent, flags, matA, matB;
    float3 size;
    float4 local;      // pose in the parent frame: (x, z, yaw, y)   (wall frame: x = a, z = inward)
    float2 pos;        // composed world
    float yaw, y0, seed;
    bool present;
};

struct FDelta
{
    float4 pose;       // dx, dz, dyaw, dy  (an absolute local pose when DB_ABS)
    int variantOv, matAOv, matBOv, hideOv;
    float3 dsize;      // dw, dh, dd
    int parentOv;      // 0 none, else parent + 100
    int bits;
};

FDelta zeroDelta()
{
    FDelta d;
    d.pose = 0; d.variantOv = 0; d.matAOv = 0; d.matBOv = 0; d.hideOv = 0; d.dsize = 0; d.parentOv = 0; d.bits = 0;
    return d;
}
FDelta readDelta(BRRec r)
{
    FDelta d;
    d.pose = float4(sane(r.dims.x), sane(r.dims.y), sane(r.dims.z), sane(r.dims.w));
    d.variantOv = (int)clamp(round(sane(r.look.x)), 0.0, 8.0);
    d.matAOv = (int)clamp(round(sane(r.look.y)), 0.0, 40.0);
    d.matBOv = (int)clamp(round(sane(r.look.z)), 0.0, 40.0);
    d.hideOv = (int)clamp(round(sane(r.look.w)), 0.0, 2.0);
    d.dsize = float3(sane(r.meta.x), sane(r.meta.y), sane(r.meta.z));
    d.parentOv = (int)clamp(round(sane(r.head.w)), 0.0, 200.0);
    d.bits = (int)clamp(round(sane(r.head.z)), 0.0, 3.0);
    return d;
}
BRRec writeDelta(FDelta d, int slot)
{
    bool any = dot(abs(d.pose), 1.0) + dot(abs(d.dsize), 1.0) > 1e-5 || d.variantOv != 0 || d.matAOv != 0
            || d.matBOv != 0 || d.hideOv != 0 || d.parentOv != 0;
    BRRec r;
    r.head = float4(ROLE_DELTA, slot, any ? (d.bits | DB_EDITED) : 0, d.parentOv);
    r.dims = d.pose;
    r.look = float4(d.variantOv, d.matAOv, d.matBOv, d.hideOv);
    r.meta = float4(d.dsize, 0);
    return r;
}

// The working set lives in groupshared memory: one thread runs this pass, and passing 30-piece
// arrays by value into every inlined helper blew the 4096-register limit.
groupshared Piece gP[FS_COUNT];
groupshared FDelta gD[FS_COUNT];
groupshared BROpening gOp[SHELL_OPEN_MAX];

// ---------------------------------------------------------------------------------------------
// GENERATOR CONTEXT
struct GCtx
{
    BRRoom R;
    int arr, layer;
    uint seed;
    int fp, door;
    int winWall; float winA;
    int focalWall; float focalA, focalClear;
    float fpA, fpW, fpDepth, fpMantel;
};

float hs(GCtx C, int k) { return brHash01(C.seed * 7919u + (uint)k * 104729u + 17u); }

int oppositeWall(int w) { return (w + 2) % 4; }

// Largest free interval on wall w (along-wall coordinates) that avoids openings and their
// casings, the chimney breast and a door's swing; `need` biases the search toward `prefer`.
float2 freeSpan(GCtx C, int w, float prefer)
{
    float2 e = brWallExtent(C.R, w);
    float bestLen = -1.0, bestC = (e.x + e.y) * 0.5, bestScore = -1e9;
    [loop] for (int si = -1; si < SHELL_OPEN_MAX; si++)
    {
        float s0 = e.x + 0.05;
        if (si >= 0)
        {
            BROpening q = gOp[si];
            if (!q.active || q.wall != w) continue;
            float pad = (q.kind == OPEN_FIREPLACE) ? 0.06 : 0.12;
            s0 = q.a + q.width * 0.5 + pad;
        }
        // reject a start that lies inside another blocked interval
        bool inside = false;
        float s1 = e.y - 0.05;
        [loop] for (int qi = 0; qi < SHELL_OPEN_MAX; qi++)
        {
            BROpening q = gOp[qi];
            if (!q.active || q.wall != w) continue;
            float pad = (q.kind == OPEN_FIREPLACE) ? 0.06 : 0.12;
            float lo = q.a - q.width * 0.5 - pad, hi = q.a + q.width * 0.5 + pad;
            if (q.kind == OPEN_DOOR) hi = max(hi, q.a - q.width * 0.5 + q.width + 0.15);
            if (s0 > lo + 1e-4 && s0 < hi - 1e-4) inside = true;
            if (lo >= s0 - 1e-4) s1 = min(s1, lo);
        }
        if (inside) continue;
        float len = s1 - s0;
        if (len <= 0.0) continue;
        float c = clamp(prefer, s0 + min(len, 1.2) * 0.5, s1 - min(len, 1.2) * 0.5);
        float score = len - abs(c - prefer) * 0.35;
        if (score > bestScore) { bestScore = score; bestLen = len; bestC = (s0 + s1) * 0.5; }
    }
    return float2(bestC, bestLen);
}

int minLayer(int s)
{
    if (s == FS_RUG || s == FS_SOFA || s == FS_CHAIR_A || s == FS_CHAIR_B || s == FS_COFFEE || s == FS_SIDE_A
        || s == FS_LAMP_A || s == FS_FLOORLAMP || s == FS_PENDANT || s == FS_PLANT_A || s == FS_ART_A) return 0;
    if (s == FS_PLANT_C || s == FS_CUSH_C || s == FS_CUSH_D || s == FS_BOOKS_B || s == FS_VASE_B) return 2;
    return 1;
}

int defVariant(GCtx C, int s)
{
    float h = hs(C, 11 + s * 7);
    if (s == FS_SOFA) return (h < 0.55) ? 0 : 1;
    if (s == FS_CHAIR_A || s == FS_CHAIR_B)
    {
        int v = (int)floor(hs(C, 201) * 2.999);
        if (s == FS_CHAIR_B && hs(C, 202) < 0.25) v = (v + 1) % 3;      // a mismatched pair, sometimes
        return v;
    }
    if (s == FS_COFFEE) return (int)floor(h * 2.999);
    if (s == FS_SIDE_A || s == FS_SIDE_B) return (int)floor(hs(C, 301) * 2.999);
    if (s == FS_LAMP_A || s == FS_LAMP_B) return (hs(C, 311) < 0.6) ? 0 : 1;
    if (s == FS_LAMP_C) return (hs(C, 311) < 0.6) ? 1 : 0;
    if (s == FS_FLOORLAMP) return (C.arr == ARR_READING) ? 2 : ((h < 0.65) ? 0 : 1);
    if (s == FS_PENDANT) return (int)floor(h * 2.999);
    if (s == FS_PLANT_A) return 0;
    if (s == FS_PLANT_B) return 1;
    if (s == FS_PLANT_C) return 2;
    if (s == FS_ART_A) return (h < 0.5) ? 1 : 0;
    if (s == FS_ART_B) return (hs(C, 11 + FS_ART_A * 7) < 0.5) ? 0 : 1;
    if (s == FS_MIRROR) return 2;
    if (s == FS_CUSH_C) return 1;
    return 0;
}

int2 defMats(GCtx C, int s, int k, int v)
{
    int2 m = fkMats(k, v);
    if (s == FS_SOFA) m.x = (hs(C, 401) < 0.6) ? MAT_LINEN : MAT_VELVET;
    if (s == FS_CUSH_A || s == FS_CUSH_B) m.x = (hs(C, 411) < 0.5) ? MAT_VELVET : MAT_LEATHER;
    if (s == FS_CUSH_C) m.x = MAT_LINEN;
    if (s == FS_CUSH_D) m.x = MAT_VELVET;
    return m;
}

float3 sizeClamp(int k, float3 s)
{
    if (k == FK_SOFA)    return float3(clamp(s.x, 1.30, 3.40), s.y, clamp(s.z, 0.80, 1.15));
    if (k == FK_RUG)     return float3(clamp(s.x, 1.20, 6.00), s.y, clamp(s.z, 1.20, 6.00));
    if (k == FK_COFFEE)  return float3(clamp(s.x, 0.50, 1.80), s.y, clamp(s.z, 0.45, 1.20));
    if (k == FK_CONSOLE) return float3(clamp(s.x, 0.80, 2.40), s.y, clamp(s.z, 0.30, 0.55));
    if (k == FK_SHELF)   return float3(clamp(s.x, 0.60, 2.40), clamp(s.y, 0.90, 2.60), clamp(s.z, 0.25, 0.45));
    if (k == FK_ART)     return float3(clamp(s.x, 0.30, 2.40), clamp(s.y, 0.30, 1.80), s.z);
    return max(s, 0.02);
}

// ---------------------------------------------------------------------------------------------
// THE GROUP: sofa, chairs, coffee table and rug, in GROUP coordinates (x right, z toward the
// focal wall), by arrangement. p* = (x, z, yaw); rug = (cx, cz, width, depth).
void groupPoses(GCtx C, float3 sS, float3 sA, float3 sB, float3 sC,
                out float3 pS, out float3 pA, out float3 pB, out float3 pC, out float4 rug)
{
    float gap = coffee_gap;
    float dCh = max(sA.z, sB.z), wCh = max(sA.x, sB.x);
    if (C.arr == ARR_FACING)
    {
        float toe = lerp(0.05, 0.20, hs(C, 502));
        pC = float3(0, 0, PI * 0.5);
        pS = float3(-(sC.z * 0.5 + gap + sS.z * 0.5), 0, PI * 0.5);
        float xc = sC.z * 0.5 + 0.45 + dCh * 0.5;
        float zc = wCh * 0.5 + 0.07;
        pA = float3(xc, zc, -PI * 0.5 - toe);
        pB = float3(xc, -zc, -PI * 0.5 + toe);
        float x0 = pS.x + sS.z * 0.5 - 0.42, x1 = xc - dCh * 0.5 + 0.38;
        float hz = max(sS.x * 0.5 + 0.22, zc + wCh * 0.5 + 0.12);
        rug = float4((x0 + x1) * 0.5, 0, ceil((x1 - x0) * 10.0) / 10.0, ceil(2.0 * hz * 10.0) / 10.0);
        return;
    }
    if (C.arr == ARR_READING)
    {
        float toe = lerp(0.18, 0.42, hs(C, 503));
        pC = float3(0, 0, 0);
        pS = float3(0, -(sC.z * 0.5 + gap + sS.z * 0.5), 0);
        float zc = sC.z * 0.5 + 0.52 + dCh * 0.5;
        float xc = wCh * 0.5 + 0.12;
        pA = float3(-xc, zc, PI - toe);
        pB = float3(xc, zc, -(PI - toe));
        float hx = max(sS.x * 0.5 + 0.30, xc + wCh * 0.5 + 0.06);
        float z0 = pS.y + sS.z * 0.5 - 0.42, z1 = zc - dCh * 0.5 + 0.38;
        rug = float4(0, (z0 + z1) * 0.5, ceil(2.0 * hx * 10.0) / 10.0, ceil((z1 - z0) * 10.0) / 10.0);
        return;
    }
    // HEARTH and VIEW: sofa facing the focal wall, a chair turned in at each end of the table
    float tilt = lerp(0.12, 0.38, hs(C, 501));
    pC = float3(0, 0, 0);
    pS = float3(0, -(sC.z * 0.5 + gap + sS.z * 0.5), 0);
    float xA = sC.x * 0.5 + 0.40 + sA.z * 0.5;
    float xB = sC.x * 0.5 + 0.40 + sB.z * 0.5;
    float zc = 0.10;
    pA = float3(-xA, zc, PI * 0.5 - tilt);
    pB = float3(xB, zc, -(PI * 0.5 - tilt));
    float hx = max(max(xA, xB) - dCh * 0.5 + 0.32, sS.x * 0.5 + 0.30);
    float z0 = pS.y + sS.z * 0.5 - 0.42;
    float z1 = max(sC.z * 0.5 + 0.50, zc + wCh * 0.5 + 0.12);
    rug = float4(0, (z0 + z1) * 0.5, ceil(2.0 * hx * 10.0) / 10.0, ceil((z1 - z0) * 10.0) / 10.0);
}

// half extents of a (w, d) box rotated by yaw, along the frame's x and z
float2 rotHalf(float2 wd, float yaw)
{
    float c = abs(cos(yaw)), s = abs(sin(yaw));
    return float2(c * wd.x * 0.5 + s * wd.y * 0.5, s * wd.x * 0.5 + c * wd.y * 0.5);
}

// How far in from its host's back edge a cushion stands so that it rests on the back: the back
// cushions of a sofa, lounge chair or wingback, the bare upholstered back of the club chair. Fitted
// against the SDF models (br_furniture.hlsli seatModel / smallModel) to ~3 mm of squash; the
// lumbar is 2 cm slimmer through the back.
float cushionRest(int hostKind, int hostVariant, int cushionVariant)
{
    float k = (hostKind == FK_CHAIR) ? ((hostVariant == 1) ? 0.34 : (hostVariant == 2) ? 0.45 : 0.485) : 0.49;
    return k - ((cushionVariant == 1) ? 0.022 : 0.0);
}

// ---------------------------------------------------------------------------------------------
// RESOLVE: generator + deltas -> local poses (composition happens afterwards)
void resolvePieces(GCtx C, out float2 gO, out float gYaw)
{
    bool sofaToWall = false;
    // 1. kind, variant, presence, size, materials
    [loop] for (int s = 0; s < FS_COUNT; s++)
    {
        Piece p;
        p.kind = fsKind(s);
        int nv = fkVariants(p.kind);
        int v = defVariant(C, s);
        if (gD[s].variantOv > 0) v = (gD[s].variantOv - 1) % max(nv, 1);
        p.variant = clamp(v, 0, nv - 1);
        p.size = fkSize(p.kind, p.variant);
        int2 m = defMats(C, s, p.kind, p.variant);
        p.matA = (gD[s].matAOv > 0) ? gD[s].matAOv - 1 : m.x;
        p.matB = (gD[s].matBOv > 0) ? gD[s].matBOv - 1 : m.y;
        p.present = minLayer(s) <= C.layer;
        if ((s == FS_LOGS || s == FS_MIRROR || s == FS_VASE_B) && C.fp < 0) p.present = false;
        p.flags = (fkIsLamp(p.kind)) ? FF_LIT : 0;
        p.parent = FP_WORLD;
        p.local = 0;
        p.pos = 0; p.yaw = 0; p.y0 = 0;
        p.seed = hs(C, 900 + s);
        gP[s] = p;
    }

    // 2. sizes that follow relationships (before deltas): console fits behind the sofa
    float3 sS = sizeClamp(FK_SOFA, gP[FS_SOFA].size + gD[FS_SOFA].dsize);
    gP[FS_CONSOLE].size.x = min(gP[FS_CONSOLE].size.x, sS.x - 0.25);
    [loop] for (int s2 = 0; s2 < FS_COUNT; s2++)
    {
        if (s2 == FS_RUG) continue;
        gP[s2].size = sizeClamp(gP[s2].kind, gP[s2].size + gD[s2].dsize);
    }
    sS = gP[FS_SOFA].size;
    float3 sA = gP[FS_CHAIR_A].size, sB = gP[FS_CHAIR_B].size, sC = gP[FS_COFFEE].size;
    if (gP[FS_COFFEE].variant != 0) sC.z = sC.x;           // round tables and ottomans are square in plan

    // 3. the group, in group coordinates
    float3 pS, pA, pB, pC; float4 rug;
    groupPoses(C, sS, sA, sB, sC, pS, pA, pB, pC, rug);
    gP[FS_RUG].size = sizeClamp(FK_RUG, float3(rug.z, 0.012, rug.w) + gD[FS_RUG].dsize);
    if (gP[FS_RUG].variant == 2) gP[FS_RUG].size.xz += 0.6;

    // group extents (group frame)
    bool consoleBehind = C.layer >= 1 && C.arr != ARR_READING;
    sofaToWall = C.arr == ARR_READING;
    float zMax = -1e9, zMin = 1e9, xMin = 1e9, xMax = -1e9;
    float3 gp[4] = { pS, pA, pB, pC };
    float3 gs[4] = { sS, sA, sB, sC };
    [unroll] for (int gi = 0; gi < 4; gi++)
    {
        float2 hh = rotHalf(gs[gi].xz, gp[gi].z);
        zMax = max(zMax, gp[gi].y + hh.y); zMin = min(zMin, gp[gi].y - hh.y);
        xMax = max(xMax, gp[gi].x + hh.x); xMin = min(xMin, gp[gi].x - hh.x);
    }
    zMax = max(zMax, rug.y + rug.w * 0.5); zMin = min(zMin, rug.y - rug.w * 0.5);
    xMax = max(xMax, rug.x + rug.z * 0.5); xMin = min(xMin, rug.x - rug.z * 0.5);
    // the side tables at the sofa's arms are part of the group's footprint: a FACING sofa turns
    // them toward the focal wall, where they would otherwise eat the hearth's clearance
    if (gP[FS_SIDE_A].present || gP[FS_SIDE_B].present)
    {
        float wing = sS.x * 0.5 + 0.03 + gP[FS_SIDE_A].size.x;
        float2 hw = rotHalf(float2(2.0 * wing, sS.z), pS.z);
        zMax = max(zMax, pS.y + hw.y); zMin = min(zMin, pS.y - hw.y);
        xMax = max(xMax, pS.x + hw.x); xMin = min(xMin, pS.x - hw.x);
    }

    int fw = C.focalWall;
    float2 nF = brWallNormal(fw);
    gYaw = yawOf2(-nF);
    float Laxis = brWallAlongX(fw) ? (C.R.z1 - C.R.z0) : (C.R.x1 - C.R.x0);
    float D0;
    if (C.arr == ARR_READING)
    {
        D0 = Laxis - 0.04 + (pS.y - sS.z * 0.5);
    }
    else
    {
        float zBack = zMin;
        float conD = gP[FS_CONSOLE].size.z;
        float zCon = pS.y - sS.z * 0.5 - 0.04 - conD;
        if (C.arr == ARR_FACING) zCon = zMin;                  // a facing sofa has its back to a side
        float clear = (C.arr == ARR_VIEW) ? 0.85 : 0.95;
        D0 = C.focalClear + clear + zMax;
        float backNeed = 0.85;
        if (consoleBehind && C.arr != ARR_FACING)
        {
            if (D0 - zCon > Laxis - backNeed) consoleBehind = false;      // no room: the console goes to a wall
            else zBack = min(zBack, zCon);
        }
        if (C.arr == ARR_FACING) consoleBehind = false;
        if (D0 - zBack > Laxis - backNeed)
        {
            // The room is too shallow for a walkway on both sides of the group. A designer gives up
            // the one behind: the sofa goes back to the wall (and its console finds another
            // wall), keeping the hearth and the route past it generous.
            consoleBehind = false;
            float zSofaBack = pS.y - sS.z * 0.5;
            if (C.arr != ARR_FACING) D0 = Laxis - 0.10 + min(zSofaBack, rug.y - rug.w * 0.5);
            else D0 = max(Laxis - backNeed + zMin, C.focalClear + 0.55 + zMax);
            sofaToWall = C.arr != ARR_FACING;
        }
    }
    gO = brWallPoint(C.R, fw, C.focalA, D0);
    // lateral: keep a walkway past both ends of the group
    float2 tW = right2(gYaw);
    float u0 = dot(gO, tW);
    float2 c00 = float2(C.R.x0, C.R.z0), c11 = float2(C.R.x1, C.R.z1);
    float umin = min(dot(c00, tW), dot(c11, tW)), umax = max(dot(c00, tW), dot(c11, tW));
    float side = 0.65;
    // a hearth on a SIDE wall is a keep-clear zone, not just a wall: the group stays its slab plus
    // 0.8 m away from it (when the hearth is the focal wall, D0 already keeps that distance)
    if (C.fp >= 0 && gOp[C.fp].wall != fw)
    {
        float along = dot(-brWallNormal(gOp[C.fp].wall), tW);
        float keep = C.fpDepth + 0.48 + 0.80 - side;
        if (along > 0.5) umax -= keep;
        else if (along < -0.5) umin += keep;
    }
    float lo = (umin + side) - (u0 + xMin), hi = (umax - side) - (u0 + xMax);
    float shift = (lo <= hi) ? clamp(0.0, lo, hi) : (lo + hi) * 0.5;
    gO += tW * shift;

    // 4. local poses -----------------------------------------------------------------------
    // the rug is the group's root, everything else in the group hangs off it
    gP[FS_RUG].parent = FP_WORLD;
    float2 rugW = toWorld2(gO, gYaw, rug.xy);
    gP[FS_RUG].local = float4(rugW, gYaw, 0);
    gP[FS_SOFA].parent = FS_RUG;    gP[FS_SOFA].local = float4(pS.xy - rug.xy, pS.z, 0);
    gP[FS_CHAIR_A].parent = FS_RUG; gP[FS_CHAIR_A].local = float4(pA.xy - rug.xy, pA.z, 0);
    gP[FS_CHAIR_B].parent = FS_RUG; gP[FS_CHAIR_B].local = float4(pB.xy - rug.xy, pB.z, 0);
    gP[FS_COFFEE].parent = FS_RUG;  gP[FS_COFFEE].local = float4(pC.xy - rug.xy, pC.z, 0);

    // side tables flank the arms, lamps sit on them
    float3 sSide = gP[FS_SIDE_A].size;
    float sx = sS.x * 0.5 + 0.03 + sSide.x * 0.5;
    float sz = -sS.z * 0.5 + sSide.z * 0.5 + 0.06;
    gP[FS_SIDE_A].parent = FS_SOFA; gP[FS_SIDE_A].local = float4(-sx, sz, 0, 0);
    gP[FS_SIDE_B].parent = FS_SOFA; gP[FS_SIDE_B].local = float4(sx, sz, 0, 0);
    gP[FS_LAMP_A].parent = FS_SIDE_A; gP[FS_LAMP_A].local = float4(0, -0.03, 0, 0);
    gP[FS_LAMP_B].parent = FS_SIDE_B; gP[FS_LAMP_B].local = float4(0, -0.03, 0, 0);

    // the floor lamp stands outside an arm; an arc lamp leans its shade over the end seat
    float lside = gP[FS_SIDE_B].present ? ((hs(C, 601) < 0.5) ? -1.0 : 1.0) : 1.0;
    bool sideHere = (lside < 0.0) ? gP[FS_SIDE_A].present : gP[FS_SIDE_B].present;
    float lx = lside * (sS.x * 0.5 + (sideHere ? sSide.x + 0.05 : 0.0) + 0.26);
    gP[FS_FLOORLAMP].parent = FS_SOFA;
    if (gP[FS_FLOORLAMP].variant == 0)
    {
        float2 lp = float2(lx, -sS.z * 0.5 + 0.14);
        float2 tgt = float2(lside * (sS.x * 0.5 - 0.48), sS.z * 0.5 + 0.30);
        gP[FS_FLOORLAMP].local = float4(lp, yawOf2(tgt - lp), 0);
    }
    else gP[FS_FLOORLAMP].local = float4(lx, -sS.z * 0.5 + 0.22, 0, 0);

    // pendant over the coffee table on a 70 cm drop below a short cord
    gP[FS_PENDANT].parent = FS_COFFEE;
    gP[FS_PENDANT].local = float4(0, 0, 0, C.R.H - 0.70 - gP[FS_PENDANT].size.y);

    // cushions against the arms (and one in the middle), one on chair A. Each stands in from its
    // host's back edge just far enough to rest on the back cushions with ~3 mm of squash --
    // measured against the two SDF models (seatModel, smallModel), not guessed: at the old 0.33 m
    // every cushion sat 10 cm deep inside the backs, its velvet face poking through the linen.
    float armW = (gP[FS_SOFA].variant == 1) ? 0.19 : 0.16;
    float cx = sS.x * 0.5 - armW - 0.25;
    gP[FS_CUSH_A].parent = FS_SOFA; gP[FS_CUSH_A].local = float4(-cx, -sS.z * 0.5 + cushionRest(FK_SOFA, gP[FS_SOFA].variant, gP[FS_CUSH_A].variant), 0.12, 0);
    gP[FS_CUSH_B].parent = FS_SOFA; gP[FS_CUSH_B].local = float4(cx, -sS.z * 0.5 + cushionRest(FK_SOFA, gP[FS_SOFA].variant, gP[FS_CUSH_B].variant), -0.10, 0);
    gP[FS_CUSH_C].parent = FS_SOFA; gP[FS_CUSH_C].local = float4(0.05, -sS.z * 0.5 + cushionRest(FK_SOFA, gP[FS_SOFA].variant, gP[FS_CUSH_C].variant), 0.03, 0);
    gP[FS_CUSH_D].parent = FS_CHAIR_A; gP[FS_CUSH_D].local = float4(0, -sA.z * 0.5 + cushionRest(FK_CHAIR, gP[FS_CHAIR_A].variant, gP[FS_CUSH_D].variant), 0.0, 0);

    // things on the coffee table
    bool roundC = gP[FS_COFFEE].variant != 0;
    gP[FS_BOOKS_A].parent = FS_COFFEE;
    gP[FS_BOOKS_A].local = roundC ? float4(-0.16, -0.08, 0.35, 0) : float4(-sC.x * 0.5 + 0.27, -0.05, 0.28, 0);
    gP[FS_VASE_A].parent = FS_COFFEE;
    gP[FS_VASE_A].local = roundC ? float4(0.18, 0.10, 0, 0) : float4(sC.x * 0.5 - 0.22, 0.07, 0, 0);
    if (gP[FS_COFFEE].variant == 2) { gP[FS_VASE_A].present = false; }     // nothing tall on an ottoman

    // console: behind the floating sofa, or against the longest free wall
    float3 sCon = gP[FS_CONSOLE].size;
    if (consoleBehind)
    {
        gP[FS_CONSOLE].parent = FS_SOFA;
        gP[FS_CONSOLE].local = float4(0, -(sS.z * 0.5 + 0.04 + sCon.z * 0.5), 0, 0);
    }
    else
    {
        int cw = (C.winWall >= 0) ? oppositeWall(C.winWall) : oppositeWall(fw);
        if (cw == fw || (C.arr == ARR_READING && cw == oppositeWall(fw))) cw = (fw + 1) % 4;
        float2 sp = freeSpan(C, cw, (brWallExtent(C.R, cw).x + brWallExtent(C.R, cw).y) * 0.5);
        gP[FS_CONSOLE].parent = FP_WALL0 - cw;
        gP[FS_CONSOLE].local = float4(sp.x, sCon.z * 0.5 + 0.01, 0, 0);
        if (sp.y < sCon.x + 0.1) gP[FS_CONSOLE].present = false;
    }
    gP[FS_LAMP_C].parent = FS_CONSOLE;  gP[FS_LAMP_C].local = float4(sCon.x * 0.5 - 0.24, 0.0, 0, 0);
    gP[FS_BOOKS_B].parent = FS_CONSOLE; gP[FS_BOOKS_B].local = float4(-sCon.x * 0.5 + 0.30, 0.02, 0.3, 0);
    if (!gP[FS_CONSOLE].present) { gP[FS_LAMP_C].present = false; gP[FS_BOOKS_B].present = false; }

    // shelves fill the chimney alcoves (or flank the focal wall when there is no breast)
    {
        int sw = (C.fp >= 0) ? gOp[C.fp].wall : fw;
        float2 e = brWallExtent(C.R, sw);
        float ca = (C.fp >= 0) ? C.fpA : (e.x + e.y) * 0.5;
        float cw2 = (C.fp >= 0) ? C.fpW : 1.6;
        float aL0 = e.x + 0.06, aL1 = ca - cw2 * 0.5 - 0.06;
        float aR0 = ca + cw2 * 0.5 + 0.06, aR1 = e.y - 0.06;
        // a window or door on that wall closes its alcove side
        [loop] for (int qi = 0; qi < SHELL_OPEN_MAX; qi++)
        {
            BROpening q = gOp[qi];
            if (!q.active || q.wall != sw || qi == C.fp) continue;
            float qlo = q.a - q.width * 0.5 - 0.12, qhi = q.a + q.width * 0.5 + 0.12;
            if (q.a < ca) aL0 = max(aL0, qhi); else aR1 = min(aR1, qlo);
        }
        [unroll] for (int k = 0; k < 2; k++)
        {
            int s = (k == 0) ? FS_SHELF_A : FS_SHELF_B;
            float a0 = (k == 0) ? aL0 : aR0, a1 = (k == 0) ? aL1 : aR1;
            float avail = a1 - a0;
            if (gD[s].variantOv == 0)
            {
                gP[s].variant = (avail >= 1.55) ? 1 : 0;
                gP[s].size = sizeClamp(FK_SHELF, fkSize(FK_SHELF, gP[s].variant) + gD[s].dsize);
            }
            if (avail < gP[s].size.x + 0.04) gP[s].present = false;
            gP[s].parent = FP_WALL0 - sw;
            gP[s].local = float4((a0 + a1) * 0.5, gP[s].size.z * 0.5 + 0.005, 0, 0);
        }
    }

    // plants: the fig in a window corner, the snake plant past the free arm, an olive opposite
    {
        int ww = (C.winWall >= 0) ? C.winWall : oppositeWall(fw);
        float2 e = brWallExtent(C.R, ww);
        bool lowEnd = hs(C, 611) < 0.5;
        // prefer the corner farther from the door
        if (C.door >= 0)
        {
            float2 dp = brWallPoint(C.R, gOp[C.door].wall, gOp[C.door].a, 0.0);
            float2 cl = brWallPoint(C.R, ww, e.x, 0.0), ch = brWallPoint(C.R, ww, e.y, 0.0);
            lowEnd = length(cl - dp) > length(ch - dp);
        }
        float rA = gP[FS_PLANT_A].size.x * 0.5, rC = gP[FS_PLANT_C].size.x * 0.5;
        float aA = lowEnd ? e.x + rA + 0.02 : e.y - rA - 0.02;
        float aC = lowEnd ? e.y - rC - 0.02 : e.x + rC + 0.02;
        gP[FS_PLANT_A].parent = FP_WALL0 - ww; gP[FS_PLANT_A].local = float4(aA, rA + 0.04, 0, 0);
        gP[FS_PLANT_C].parent = FP_WALL0 - ww; gP[FS_PLANT_C].local = float4(aC, rC + 0.04, 0, 0);
        float pside = -lside;
        float px = pside * (sS.x * 0.5 + ((pside < 0.0) ? (gP[FS_SIDE_A].present ? sSide.x : 0.0) : (gP[FS_SIDE_B].present ? sSide.x : 0.0)) + 0.30);
        // with the sofa against a wall the pot keeps clear of the plaster instead of sinking into it
        float pzB = sofaToWall ? max(0.12, gP[FS_PLANT_B].size.x * 0.5 + 0.03) : 0.12;
        gP[FS_PLANT_B].parent = FS_SOFA; gP[FS_PLANT_B].local = float4(px, -sS.z * 0.5 + pzB, 0, 0);
    }

    // art: over the sofa or console on the wall behind the group; a canvas on a side wall
    {
        int aw = oppositeWall(fw);
        float2 e = brWallExtent(C.R, aw);
        float2 sofaW = toWorld2(gO, gYaw, pS.xy);
        float aPref = brWallAlongX(aw) ? sofaW.x : sofaW.y;
        float2 sp = freeSpan(C, aw, aPref);
        float aArt = clamp(aPref, sp.x - sp.y * 0.5 + gP[FS_ART_A].size.x * 0.5 + 0.05, sp.x + sp.y * 0.5 - gP[FS_ART_A].size.x * 0.5 - 0.05);
        float y0 = sofaToWall ? sS.y + 0.24 : 1.57 - gP[FS_ART_A].size.y * 0.5;
        gP[FS_ART_A].parent = FP_WALL0 - aw;
        gP[FS_ART_A].local = float4(aArt, 0.0, 0, y0);
        if (sp.y < gP[FS_ART_A].size.x + 0.1) gP[FS_ART_A].present = false;

        int bw = (fw + 1) % 4;
        if (C.door >= 0 && gOp[C.door].wall == bw) bw = (fw + 3) % 4;
        if (C.winWall == bw) bw = (bw + 2) % 4;
        float2 e2 = brWallExtent(C.R, bw);
        float2 sp2 = freeSpan(C, bw, (e2.x + e2.y) * 0.5);
        gP[FS_ART_B].parent = FP_WALL0 - bw;
        gP[FS_ART_B].local = float4(sp2.x, 0.0, 0, 1.57 - gP[FS_ART_B].size.y * 0.5);
        if (sp2.y < gP[FS_ART_B].size.x + 0.3) gP[FS_ART_B].present = false;
    }

    // mantel: the mirror above it, a vase on it, logs in the grate
    if (C.fp >= 0)
    {
        gP[FS_MIRROR].parent = FP_WALL0 - gOp[C.fp].wall;
        gP[FS_MIRROR].local = float4(C.fpA, C.fpDepth + 0.005, 0, C.fpMantel + 0.22);
        gP[FS_VASE_B].parent = FP_MANTEL; gP[FS_VASE_B].local = float4(-(C.fpW * 0.5 - 0.32), 0.0, 0, 0);
        gP[FS_LOGS].parent = FP_FIREBOX; gP[FS_LOGS].local = 0;
    }

    // 5. hand edits on top -------------------------------------------------------------------
    [loop] for (int s3 = 0; s3 < FS_COUNT; s3++)
    {
        FDelta d = gD[s3];
        if (d.parentOv > 0) gP[s3].parent = d.parentOv - 100;
        if ((d.bits & DB_ABS) != 0) gP[s3].local = d.pose;
        else gP[s3].local += d.pose;
        if (d.hideOv == 1) gP[s3].present = true;
        if (d.hideOv == 2) gP[s3].present = false;
        if (!gP[s3].present) gP[s3].flags |= FF_HIDDEN;
        if ((d.bits & DB_EDITED) != 0 || d.hideOv != 0 || d.variantOv != 0 || d.matAOv != 0 || dot(abs(d.pose), 1.0) > 1e-5 || dot(abs(d.dsize), 1.0) > 1e-5)
            gP[s3].flags |= FF_EDITED;
    }
}

// world frame of a parent code: origin xz, yaw, base height
void parentFrame(GCtx C, int parent, out float2 o, out float yaw, out float y)
{
    o = 0; yaw = 0; y = 0;
    if (parent >= 0 && parent < FS_COUNT)
    {
        Piece h = gP[parent];
        o = h.pos; yaw = h.yaw;
        y = (h.kind == FK_COFFEE || h.kind == FK_SIDE || h.kind == FK_CONSOLE || h.kind == FK_SOFA || h.kind == FK_CHAIR || h.kind == FK_SHELF)
            ? h.y0 + fkHostTop(h.kind, h.variant, h.size) : h.y0;
        return;
    }
    if (parent == FP_MANTEL || parent == FP_FIREBOX)
    {
        BROpening f = gOp[max(C.fp, 0)];
        float2 n = brWallNormal(f.wall);
        yaw = yawOf2(n);
        float inward = (parent == FP_MANTEL) ? C.fpDepth + 0.07 : C.fpDepth - 0.21;
        o = brWallPoint(C.R, f.wall, C.fpA, inward);
        y = (parent == FP_MANTEL) ? C.fpMantel : 0.035;
        return;
    }
}

void composeWorld(GCtx C)
{
    [loop] for (int pz = 0; pz < 4; pz++)
    {
        [loop] for (int s = 0; s < FS_COUNT; s++)
        {
            Piece p = gP[s];
            int par = p.parent;
            if (par == FP_WORLD)
            {
                p.pos = p.local.xy; p.yaw = p.local.z; p.y0 = p.local.w;
            }
            else if (par <= FP_WALL0 && par >= FP_WALL0 - 3)
            {
                int w = FP_WALL0 - par;
                float2 n = brWallNormal(w);
                p.pos = brWallPoint(C.R, w, p.local.x, p.local.y);
                p.yaw = yawOf2(n) + p.local.z;
                p.y0 = p.local.w;
            }
            else
            {
                float2 o; float yw, y;
                parentFrame(C, par, o, yw, y);
                p.pos = toWorld2(o, yw, p.local.xy);
                p.yaw = yw + p.local.z;
                bool onTop = p.kind == FK_TABLELAMP || p.kind == FK_CUSHION || p.kind == FK_BOOKS || p.kind == FK_VASE
                          || par == FP_MANTEL || par == FP_FIREBOX;
                p.y0 = (p.kind == FK_PENDANT) ? p.local.w : (onTop ? y + p.local.w : p.local.w);
                // a thing that sits on a hidden host is hidden with it
                if (par >= 0 && par < FS_COUNT && onTop && (gP[par].flags & FF_HIDDEN) != 0) p.flags |= FF_HIDDEN;
            }
            p.yaw = wrapPi(p.yaw);
            gP[s] = p;
        }
    }
}

// ---------------------------------------------------------------------------------------------
// GEOMETRY TESTS
float2 halfWD(Piece p)
{
    if (p.kind == FK_FLOORLAMP && p.variant == 0) return float2(0.17, 0.17);
    float2 h = p.size.xz * 0.5;
    if (p.kind == FK_COFFEE && p.variant != 0) h = float2(p.size.x, p.size.x) * 0.5;
    return h;
}

// overlap depth of two oriented rectangles (SAT); <= 0 when apart
float rectOverlap(float2 ca, float ya, float2 ha, float2 cb, float yb, float2 hb)
{
    float2 ax[4] = { right2(ya), fwd2(ya), right2(yb), fwd2(yb) };
    float best = 1e9;
    [unroll] for (int i = 0; i < 4; i++)
    {
        float2 a = ax[i];
        float ra = ha.x * abs(dot(right2(ya), a)) + ha.y * abs(dot(fwd2(ya), a));
        float rb = hb.x * abs(dot(right2(yb), a)) + hb.y * abs(dot(fwd2(yb), a));
        float d = abs(dot(cb - ca, a));
        best = min(best, ra + rb - d);
    }
    return best;
}

bool inDoorSwing(BROpening o, BRRoom R, float2 p, out float2 hinge)
{
    float hw = o.width * 0.5;
    hinge = brWallPoint(R, o.wall, o.a - hw, 0.0);
    float2 n = brWallNormal(o.wall);
    float2 along = brWallAlongX(o.wall) ? float2(1, 0) : float2(0, 1);
    float2 d = p - hinge;
    return length(d) < o.width && dot(d, n) > 0.0 && dot(d, along) > 0.0;
}

// ---------------------------------------------------------------------------------------------
// PICKING
struct FPick { int slot; int handle; int surface; };

float2 knobPos(Piece p, FLayout L)
{
    float2 h = halfWD(p);
    return p.pos + fwd2(p.yaw) * (h.y + fKnobPx(L) / L.s);
}

bool resizable(int k, bool depth)
{
    if (depth) return k == FK_RUG || k == FK_COFFEE || k == FK_SOFA;
    return k == FK_RUG || k == FK_SOFA || k == FK_COFFEE || k == FK_CONSOLE || k == FK_SHELF || k == FK_ART;
}

FPick pickPlan(float2 px, FLayout L, int sel)
{
    FPick pk; pk.slot = -1; pk.handle = H_NONE; pk.surface = 0;
    float2 w = fPlanWorld(L, px);
    float tol = 5.0 / L.s;
    // 1. handles of the selection
    if (sel >= 0 && sel < FS_COUNT && (gP[sel].flags & FF_HIDDEN) == 0)
    {
        Piece p = gP[sel];
        float2 h = halfWD(p);
        if (length(px - fPlanPx(L, knobPos(p, L))) < fKnobGrab(L)) { pk.slot = sel; pk.handle = H_ROT; return pk; }
        if (resizable(p.kind, false) && length(px - fPlanPx(L, p.pos + right2(p.yaw) * h.x)) < fGripGrab(L)) { pk.slot = sel; pk.handle = H_WIDTH; return pk; }
        if (resizable(p.kind, true) && length(px - fPlanPx(L, p.pos - fwd2(p.yaw) * h.y)) < fGripGrab(L)) { pk.slot = sel; pk.handle = H_DEPTH; return pk; }
    }
    // 2. things on top, smallest first; 3. floor pieces, smallest first; 4. pendant; 5. art; 6. rug
    float bestArea = 1e9;
    [loop] for (int pz = 0; pz < 5; pz++)
    {
        [loop] for (int s = 0; s < FS_COUNT; s++)
        {
            Piece p = gP[s];
            if ((p.flags & FF_HIDDEN) != 0 || p.kind == FK_NONE) continue;
            int cls = (p.kind == FK_TABLELAMP || p.kind == FK_CUSHION || p.kind == FK_BOOKS || p.kind == FK_VASE || p.kind == FK_LOGS) ? 0
                    : (p.kind == FK_PENDANT) ? 2 : (p.kind == FK_ART) ? 3 : (p.kind == FK_RUG) ? 4 : 1;
            if (cls != pz) continue;
            float2 h = halfWD(p);
            float d;
            if (p.kind == FK_PENDANT) d = length(w - p.pos) - 0.10;
            else if (p.kind == FK_ART) d = footSd(w, p.pos + fwd2(p.yaw) * 0.02, p.yaw, float2(h.x, 0.06));
            else if (fkRound(p.kind, p.variant)) d = length(w - p.pos) - h.x;
            else d = footSd(w, p.pos, p.yaw, h);
            float area = h.x * h.y;
            if (d < tol && area < bestArea) { bestArea = area; pk.slot = s; pk.handle = H_MOVE; }
        }
        if (pk.slot >= 0) return pk;
    }
    return pk;
}

FPick pickSection(float2 px, FLayout L, FSection S, BRRoom R)
{
    FPick pk; pk.slot = -1; pk.handle = H_NONE; pk.surface = 1;
    float2 uy = fSecUY(S, px);
    float bestD = -1e9;
    [loop] for (int s = 0; s < FS_COUNT; s++)
    {
        Piece p = gP[s];
        if ((p.flags & FF_HIDDEN) != 0 || p.kind == FK_NONE || p.kind == FK_RUG) continue;
        float dep = fSecDepth(S, R, p.pos);
        if (dep > S.cutD || dep < -0.5) continue;
        float2 h = halfWD(p);
        float2 hp = rotHalf(h * 2.0, p.yaw - yawOf2(-S.n));
        float u = fSecU(S, p.pos);
        float y0 = p.y0, y1 = p.y0 + p.size.y;
        if (p.kind == FK_PENDANT) y1 = R.H;
        if (uy.x > u - hp.x - 0.02 && uy.x < u + hp.x + 0.02 && uy.y > y0 - 0.02 && uy.y < y1 + 0.02 && dep > bestD)
        {
            bestD = dep; pk.slot = s; pk.handle = H_SECMOVE;
        }
    }
    return pk;
}

// Which host's top is under world point w (for re-hosting a dragged ON piece)?
int hostUnder(float2 w, int self, int kind)
{
    bool cushion = kind == FK_CUSHION;
    [loop] for (int s = 0; s < FS_COUNT; s++)
    {
        if (s == self) continue;
        Piece h = gP[s];
        if ((h.flags & FF_HIDDEN) != 0) continue;
        bool ok = cushion ? (h.kind == FK_SOFA || h.kind == FK_CHAIR) : (h.kind == FK_COFFEE || h.kind == FK_SIDE || h.kind == FK_CONSOLE);
        if (!ok) continue;
        float2 hh = halfWD(h);
        float d = fkRound(h.kind, h.variant) ? length(w - h.pos) - hh.x : footSd(w, h.pos, h.yaw, hh);
        if (d < -0.02) return s;
    }
    return -1;
}

// ---------------------------------------------------------------------------------------------
// VERBS -- one implementation, two triggers (keys and inspector chips)
#define V_NONE      0
#define V_VARIANT   1
#define V_MATERIAL  2
#define V_HIDE      3
#define V_RESET     4
#define V_RESET_ALL 5
#define V_REROLL    6
#define V_UNHIDE    7

int chipVerb(int chip, int sel)
{
    if (sel >= 0) return (chip == 0) ? V_VARIANT : (chip == 1) ? V_MATERIAL : (chip == 2) ? V_HIDE : V_RESET;
    return (chip == 0) ? V_REROLL : (chip == 1) ? V_UNHIDE : (chip == 3) ? V_RESET_ALL : V_NONE;
}

void applyVerb(int verb, int sel, inout float reroll)
{
    if (verb == V_RESET_ALL) { [loop] for (int i = 0; i < FS_COUNT; i++) gD[i] = zeroDelta(); return; }
    if (verb == V_REROLL) { reroll += 1.0; return; }
    if (verb == V_UNHIDE) { [loop] for (int i2 = 0; i2 < FS_COUNT; i2++) if (gD[i2].hideOv == 2) gD[i2].hideOv = 0; return; }
    if (sel < 0 || sel >= FS_COUNT) return;
    FDelta d = gD[sel];
    Piece p = gP[sel];
    if (verb == V_VARIANT)
    {
        int nv = fkVariants(p.kind);
        d.variantOv = ((p.variant + 1) % max(nv, 1)) + 1;
        d.dsize = 0;
    }
    else if (verb == V_MATERIAL) d.matAOv = fkNextMat(p.kind, p.matA) + 1;
    else if (verb == V_HIDE)     d.hideOv = ((p.flags & FF_HIDDEN) != 0) ? 1 : 2;
    else if (verb == V_RESET)    d = zeroDelta();
    gD[sel] = d;
}

// ---------------------------------------------------------------------------------------------

// ---------------------------------------------------------------------------------------------
// SIGNATURE: everything the published records depend on. When it has not changed and no input
// event arrived, the pass does nothing at all -- the persistent buffer still holds last cook's
// records. (Recomputing the walkway route every frame cost 4 ms of a single GPU thread.)
uint mixv(uint h, float v) { h ^= asuint(v); h *= 16777619u; h ^= h >> 13; return h; }
uint mix4(uint h, float4 v) { h = mixv(h, v.x); h = mixv(h, v.y); h = mixv(h, v.z); return mixv(h, v.w); }
uint inputSig(bool haveShell, float reroll, float2 res)
{
    uint h = 2166136261u;
    if (haveShell)
    {
        [loop] for (uint i = 0u; i < 13u; i++) { BRRec r = sh(i); h = mix4(h, r.head); h = mix4(h, r.dims); h = mix4(h, r.look); h = mix4(h, r.meta); }
    }
    [loop] for (int d = 0; d < FS_COUNT; d++) { BRRec r = Furn[FURN_DELTA0 + d]; h = mix4(h, r.head); h = mix4(h, r.dims); h = mix4(h, r.look); h = mix4(h, r.meta); }
    h = mixv(h, (float)arrangement); h = mixv(h, (float)layering); h = mixv(h, (float)variation);
    h = mixv(h, coffee_gap); h = mixv(h, walkway); h = mixv(h, reroll); h = mixv(h, PLAN_VERSION);
    h = mixv(h, res.x); h = mixv(h, res.y);
    return h;
}

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    float2 res = (_Resolution.x >= 64.0) ? _Resolution.xy : float2(1280.0, 960.0);

    // ---- room
    bool haveShell = _Data0_Count >= 13u && abs(_Data0[0].head.x - ROLE_ROOM) < 0.5;
    BRRoom R = brDefaultRoom();
    if (haveShell) R = brRoomFromRec(sh(0));
    [unroll] for (int oi = 0; oi < SHELL_OPEN_MAX; oi++)
    {
        if (haveShell) gOp[oi] = brOpeningFromRec(sh(5 + oi));
        else gOp[oi] = defaultOpening(oi);
    }

    // ---- persistent state
    BRRec ed = Furn[FURN_EDITOR];
    BRRec fz = Furn[REC_FROZEN];
    bool fresh = !(abs(ed.head.x - ROLE_FURN_ED) < 0.5) || abs(sane(ed.head.w) - PLAN_VERSION) > 0.01;
    if (fresh)
    {
        BRRec z; z.head = float4(ROLE_DELTA, 0, 0, 0); z.dims = 0; z.look = 0; z.meta = 0;
        [loop] for (int i = FURN_DELTA0; i < FURN_DELTA0 + FS_COUNT; i++) Furn[i] = z;
        ed.head = float4(ROLE_FURN_ED, -1, -1, PLAN_VERSION); ed.dims = 0; ed.look = 0; ed.meta = 0;
        fz.head = float4(ROLE_FURN_ED, 2, 0, 0); fz.dims = 0; fz.look = 0; fz.meta = 0;
    }
    [loop] for (int di = 0; di < FS_COUNT; di++) gD[di] = readDelta(Furn[FURN_DELTA0 + di]);

    int sel = (int)round(sane(ed.head.y));
    if (sel < -1 || sel >= FS_COUNT) sel = -1;
    int dragActive = (int)round(sane(ed.dims.x));
    int handle = (int)round(sane(ed.dims.y));
    int surface = (int)round(sane(ed.dims.z));
    float reroll = max(round(sane(ed.dims.w)), 0.0);
    float4 startVals = float4(sane(ed.look.x), sane(ed.look.y), sane(ed.look.z), sane(ed.look.w));
    uint lastSeq = asuint(ed.meta.x);
    float handled = sane(ed.meta.y);
    float2 startPx = float2(sane(fz.dims.x), sane(fz.dims.y));
    float2 startSize = float2(sane(fz.dims.z), sane(fz.dims.w));
    float2 grabOff = float2(sane(fz.meta.x), sane(fz.meta.y));
    float4 startDelta = float4(sane(fz.look.x), sane(fz.look.y), sane(fz.look.z), sane(fz.look.w));

    // nothing changed and nobody touched the canvas: keep last cook's records
    {
        uint ne = _ViewportEventCount;
        uint rmax = 0u;
        [loop] for (uint q = 0u; q < ne; q++) rmax = max(rmax, _ViewportEvents[q].sequence);
        uint ls = (ne > 0u && rmax < lastSeq) ? 0u : lastSeq;
        bool anyFresh = false;
        [loop] for (uint q2 = 0u; q2 < ne; q2++)
        {
            ViewportEvent e0 = _ViewportEvents[q2];
            bool fr0 = e0.sequence > ls || (ls - e0.sequence) > (1u << 20);
            if (fr0 && (e0.type == 2u || e0.type == 4u || e0.type == 5u)) anyFresh = true;
        }
        uint sigNow = inputSig(haveShell, reroll, res);
        if (!fresh && !anyFresh && sigNow == asuint(fz.meta.w)) return;
    }

    // ---- context
    GCtx C;
    C.R = R;
    C.arr = clamp(arrangement, 0, 3);
    C.layer = clamp(layering, 0, 2);
    C.seed = (uint)max(variation, 0) + (uint)reroll * 7919u;
    C.fp = -1; C.door = -1;
    C.fpA = 0; C.fpW = 1.8; C.fpDepth = 0.36; C.fpMantel = 1.24;
    int winCount[4] = { 0, 0, 0, 0 };
    float winSum[4] = { 0, 0, 0, 0 };
    [loop] for (int qi = 0; qi < SHELL_OPEN_MAX; qi++)
    {
        BROpening q = gOp[qi];
        if (!q.active) continue;
        if (q.kind == OPEN_FIREPLACE && C.fp < 0) { C.fp = qi; C.fpA = q.a; C.fpW = q.width; C.fpDepth = q.depth; C.fpMantel = q.height; }
        if ((q.kind == OPEN_DOOR || q.kind == OPEN_ARCH) && C.door < 0) C.door = qi;
        if (brOpenIsGlazed(q.kind)) { winCount[q.wall] += 1; winSum[q.wall] += q.a; }
    }
    C.winWall = -1; C.winA = 0;
    int bestW = 0;
    [unroll] for (int w = 0; w < 4; w++) if (winCount[w] > bestW) { bestW = winCount[w]; C.winWall = w; C.winA = winSum[w] / (float)winCount[w]; }
    // the focal wall: the hearth, or the view, or the longest blank wall
    if (C.arr == ARR_VIEW && C.winWall >= 0) { C.focalWall = C.winWall; C.focalA = C.winA; C.focalClear = 0.26; }
    else if (C.fp >= 0) { C.focalWall = gOp[C.fp].wall; C.focalA = C.fpA; C.focalClear = C.fpDepth + 0.48; }
    else
    {
        int fw = (C.winWall >= 0) ? oppositeWall(C.winWall) : WALL_N;
        float2 e = brWallExtent(R, fw);
        C.focalWall = fw; C.focalA = (e.x + e.y) * 0.5; C.focalClear = 0.10;
    }

    float2 gO; float gYaw;
    resolvePieces(C, gO, gYaw);
    composeWorld(C);
    FLayout L = fLayout(res, R);
    int secWall = (int)round(sane(ed.head.z));

    // ---- events, each consumed once by sequence (with the host-counter-reset guard)
    uint n = _ViewportEventCount;
    uint ringMax = 0u;
    [loop] for (uint ri = 0u; ri < n; ri++) ringMax = max(ringMax, _ViewportEvents[ri].sequence);
    if (n > 0u && ringMax < lastSeq) lastSeq = 0u;
    uint newLast = lastSeq;
    BRRec diag = Furn[FURN_DIAG];
    bool anyEvent = false;

    [loop] for (uint ei = 0u; ei < n; ei++)
    {
        // One exit per event: FXC silently drops stores made before a mid-body `continue`, which
        // published a half-resolved plan after a drag (the rug fell back to its catalogue size).
        ViewportEvent ev = _ViewportEvents[ei];
        bool isFresh = ev.sequence > lastSeq || (lastSeq - ev.sequence) > (1u << 20);
        if (isFresh)
        {
            anyEvent = true;
            newLast = (ev.sequence > lastSeq) ? max(newLast, ev.sequence) : ev.sequence;
            handled += 1.0;
            diag.head = float4(ROLE_NONE, ev.type, ev.code, ev.phase);
            diag.dims = float4(ev.flags, ev.sequence, ev.modifiers, ev.value);
            float2 px = ev.position * res;
            bool rep = (ev.flags & VIEWPORT_EVENT_FLAG_REPEAT) != 0u || ev.phase == 2u;

            // ---- press: chips, then pick
            if (ev.type == 2u && ev.code == 0u && ev.phase == 1u)
            {
                int chip = fChipAt(L, px);
                if (chip >= 0)
                {
                    applyVerb(chipVerb(chip, sel), sel, reroll);
                    handle = H_NONE; dragActive = 0;
                    C.seed = (uint)max(variation, 0) + (uint)reroll * 7919u;
                    resolvePieces(C, gO, gYaw);
                    composeWorld(C);
                }
                else
                {
                    FPick pk; pk.slot = -1; pk.handle = H_NONE; pk.surface = 0;
                    int sw = (secWall >= 0 && secWall < 4) ? secWall : C.focalWall;
                    FSection S = fSection(L, R, sw, sane(ed.meta.w) > 0.1 ? sane(ed.meta.w) : 2.5);
                    bool inSec = fInRect(px, L.secR, 0.0);
                    bool inPlan = !inSec && fInRect(px, L.planR, 0.0);
                    if (inSec) pk = pickSection(px, L, S, R);
                    else if (inPlan) pk = pickPlan(px, L, sel);
                    if (inSec || inPlan)
                    {
                        sel = pk.slot; handle = pk.handle; surface = pk.surface;
                        dragActive = 0;
                        startPx = px;
                        if (sel >= 0)
                        {
                            Piece p = gP[sel];
                            float2 pw = fPlanWorld(L, px);
                            grabOff = (surface == 0) ? pw - p.pos : float2(0, 0);
                            startVals = float4(p.pos, p.yaw, p.y0);
                            startSize = p.size.xz;
                            startDelta = gD[sel].pose;
                        }
                    }
                    else startPx = px;                  // inspector / rules panels: no-op
                }
            }
            else if (ev.type == 2u && ev.code == 0u && ev.phase == 3u)
            {
                if (dragActive == 0) handle = H_NONE;
            }
            // ---- drag gesture
            else if (ev.type == 5u && ev.code == 3u)
            {
                if (ev.phase == 5u && handle != H_NONE && sel >= 0) dragActive = 1;
                if ((ev.phase == 6u || ev.phase == 7u) && dragActive > 0 && sel >= 0)
                {
                    Piece p = gP[sel];
                    FDelta d = gD[sel];
                    float2 o; float pyaw, py;
                    bool wallHosted = p.parent <= FP_WALL0 && p.parent >= FP_WALL0 - 3;
                    if (wallHosted) { o = 0; pyaw = 0; py = 0; }
                    else if (p.parent == FP_WORLD) { o = 0; pyaw = 0; py = 0; }
                    else parentFrame(C, p.parent, o, pyaw, py);
                    // the pose this piece would have with a zero delta, in its parent frame
                    float4 baseLocal = ((d.bits & DB_ABS) != 0) ? float4(0, 0, 0, 0) : p.local - d.pose;

                    if (handle == H_MOVE || handle == H_SECMOVE)
                    {
                        float2 target;
                        float dy = 0.0;
                        if (handle == H_MOVE) target = fPlanWorld(L, px) - grabOff;
                        else
                        {
                            int sw = (secWall >= 0 && secWall < 4) ? secWall : C.focalWall;
                            FSection S = fSection(L, R, sw, 2.5);
                            float2 uy0 = fSecUY(S, startPx), uy1 = fSecUY(S, px);
                            target = startVals.xy + S.t * (uy1.x - uy0.x);
                            dy = uy1.y - uy0.y;
                        }
                        bool onTop = p.kind == FK_TABLELAMP || p.kind == FK_CUSHION || p.kind == FK_BOOKS || p.kind == FK_VASE;
                        if (onTop && handle == H_MOVE)
                        {
                            int hu = hostUnder(target, sel, p.kind);
                            if (hu >= 0 && hu != p.parent)
                            {
                                d.parentOv = hu + 100; d.bits |= DB_ABS;
                                p.parent = hu;
                                parentFrame(C, hu, o, pyaw, py);
                                baseLocal = 0;
                                d.pose = float4(0, 0, wrapPi(p.yaw - pyaw), 0);
                            }
                        }
                        if (wallHosted)
                        {
                            int wcur = FP_WALL0 - p.parent;
                            // re-host on another wall when dragged close to it (plan only)
                            if (handle == H_MOVE)
                            {
                                float best = 0.7; int wb = wcur;
                                [unroll] for (int k = 0; k < 4; k++)
                                {
                                    float plane = brWallPlane(R, k);
                                    float perp = brWallAlongX(k) ? abs(target.y - plane) : abs(target.x - plane);
                                    if (perp < best - 0.05) { best = perp; wb = k; }
                                }
                                if (wb != wcur)
                                {
                                    d.parentOv = (FP_WALL0 - wb) + 100; d.bits |= DB_ABS;
                                    p.parent = FP_WALL0 - wb; wcur = wb;
                                    baseLocal = 0;
                                    d.pose = float4(0, p.local.y, 0, p.local.w);
                                }
                            }
                            float a = brWallAlongX(wcur) ? target.x : target.y;
                            float2 e = brWallExtent(R, wcur);
                            float hw = p.size.x * 0.5;
                            a = clamp(snapTo(a, snap), e.x + hw, e.y - hw);
                            float y = p.local.w;
                            if (handle == H_SECMOVE && p.kind == FK_ART) y = clamp(snapTo(startVals.w + dy, snap), 0.15, R.H - p.size.y - 0.05);
                            if ((d.bits & DB_ABS) != 0) { d.pose.x = a; d.pose.w = y; }
                            else { d.pose.x = a - baseLocal.x; d.pose.w = y - baseLocal.w; }
                        }
                        else
                        {
                            float2 local = (p.parent == FP_WORLD) ? target : toLocal2(o, pyaw, target);
                            local = float2(snapTo(local.x, snap), snapTo(local.y, snap));
                            if (onTop && p.parent >= 0)
                            {
                                Piece h = gP[p.parent];
                                float2 hh = halfWD(h) - 0.05;
                                local = clamp(local, -hh, hh);
                            }
                            if ((d.bits & DB_ABS) != 0) d.pose.xy = local;
                            else d.pose.xy = local - baseLocal.xy;
                            if (handle == H_SECMOVE && p.kind == FK_PENDANT)
                            {
                                float y = clamp(snapTo(startVals.w + dy, snap), 1.2, R.H - p.size.y - 0.08);
                                d.pose.w = ((d.bits & DB_ABS) != 0) ? y : y - baseLocal.w;
                            }
                        }
                    }
                    else if (handle == H_ROT)
                    {
                        float2 w = fPlanWorld(L, px);
                        float wy = yawOf2(w - p.pos);
                        float st = (snap > 1e-4) ? 0.2617994 : 0.0;           // 15 degrees
                        if (st > 0.0) wy = round(wy / st) * st;
                        float baseYaw = wallHosted ? yawOf2(brWallNormal(FP_WALL0 - p.parent)) : pyaw;
                        float ly = wrapPi(wy - baseYaw);
                        if ((d.bits & DB_ABS) != 0) d.pose.z = ly;
                        else d.pose.z = wrapPi(ly - baseLocal.z);
                    }
                    else if (handle == H_WIDTH || handle == H_DEPTH)
                    {
                        float2 lw = toLocal2(p.pos, p.yaw, fPlanWorld(L, px));
                        float3 base = p.size - d.dsize;
                        if (handle == H_WIDTH) d.dsize.x = snapTo(2.0 * abs(lw.x), snap) - base.x;
                        else d.dsize.z = snapTo(2.0 * abs(lw.y), snap) - base.z;
                    }
                    d.bits |= DB_EDITED;
                    gD[sel] = d;
                    resolvePieces(C, gO, gYaw);
                    composeWorld(C);
                }
                if (ev.phase == 7u || ev.phase == 8u) { dragActive = 0; handle = H_NONE; }
            }
            // ---- keys
            else if (ev.type == 4u && ev.phase == 1u && !rep)
            {
                uint key = ev.code;
                int verb = V_NONE;
                if (key == 48u) sel = -1;                                   // Escape
                else if (key == 32u) verb = V_RESET_ALL;                    // 0
                else if (key == 22u) verb = V_VARIANT;                      // V
                else if (key == 13u) verb = V_MATERIAL;                     // M
                else if (key == 8u)  verb = V_HIDE;                         // H
                else if (key == 18u) verb = V_RESET;                        // R
                else if (key == 14u) verb = V_REROLL;                       // N
                applyVerb(verb, sel, reroll);
                C.seed = (uint)max(variation, 0) + (uint)reroll * 7919u;
                resolvePieces(C, gO, gYaw);
                composeWorld(C);
            }
        }
    }
    // What is published is resolved once more from the final deltas, outside the event loop, so a
    // codegen surprise inside the loop can never leak a half-resolved plan into the records.
    if (anyEvent)
    {
        C.seed = (uint)max(variation, 0) + (uint)reroll * 7919u;
        resolvePieces(C, gO, gYaw);
        composeWorld(C);
    }

    // ---- section: the selected piece's wall, else the wall the group faces
    secWall = C.focalWall;
    float cutD = 2.6;
    if (sel >= 0)
    {
        Piece sp = gP[sel];
        if (sp.parent <= FP_WALL0 && sp.parent >= FP_WALL0 - 3) { secWall = FP_WALL0 - sp.parent; cutD = 1.8; }
        else if ((sp.parent == FP_MANTEL || sp.parent == FP_FIREBOX) && C.fp >= 0) { secWall = gOp[C.fp].wall; cutD = 1.8; }
    }
    if (secWall == C.focalWall && cutD > 2.0)
    {
        // cut just behind the seats facing this wall, so the whole group is in the drawing
        float2 nw = brWallNormal(secWall);
        float2 p0 = brWallPoint(R, secWall, brWallExtent(R, secWall).x, 0.0);
        float depthAxis = brWallAlongX(secWall) ? (R.z1 - R.z0) : (R.x1 - R.x0);
        cutD = clamp(dot(gP[FS_SOFA].pos - p0, nw) + gP[FS_SOFA].size.z * 0.5 + 0.35, 1.2, depthAxis - 0.15);
    }

    // ---- alarms + rules
    int ruleBits = 0, alarmCount = 0, overlaps = 0;
    BROpening door = gOp[max(C.door, 0)];
    bool haveDoor = C.door >= 0 && door.kind == OPEN_DOOR;
    [loop] for (int ai = 0; ai < FS_COUNT; ai++)
    {
        Piece p = gP[ai];
        if ((p.flags & FF_HIDDEN) != 0 || p.kind == FK_NONE) continue;
        bool alarm = false;
        float2 h = halfWD(p);
        float2 rr = right2(p.yaw) * h.x, ff = fwd2(p.yaw) * h.y;
        float2 cn[4] = { p.pos - rr - ff, p.pos + rr - ff, p.pos + rr + ff, p.pos - rr + ff };
        if (fkIsFloorBody(p.kind) || p.kind == FK_RUG)
        {
            if (fkRound(p.kind, p.variant))
            {
                float rr0 = h.x;
                if (p.pos.x - rr0 < R.x0 - 0.01 || p.pos.x + rr0 > R.x1 + 0.01 || p.pos.y - rr0 < R.z0 - 0.01 || p.pos.y + rr0 > R.z1 + 0.01) alarm = true;
            }
            else
            {
                [unroll] for (int c = 0; c < 4; c++)
                    if (cn[c].x < R.x0 - 0.01 || cn[c].x > R.x1 + 0.01 || cn[c].y < R.z0 - 0.01 || cn[c].y > R.z1 + 0.01) alarm = true;
            }
        }
        if (fkIsFloorBody(p.kind))
        {
            if (haveDoor)
            {
                float2 hg;
                bool hit = false;
                [unroll] for (int c2 = 0; c2 < 4; c2++) if (inDoorSwing(door, R, cn[c2], hg)) hit = true;
                inDoorSwing(door, R, p.pos, hg);
                float2 nn = brWallNormal(door.wall);
                float2 al = brWallAlongX(door.wall) ? float2(1, 0) : float2(0, 1);
                [unroll] for (int k = 0; k < 5; k++)
                {
                    float an = (float)k / 4.0 * 1.5707963;
                    float2 q = hg + (al * cos(an) + nn * sin(an)) * door.width * 0.98;
                    if (footSd(q, p.pos, p.yaw, h) < 0.0) hit = true;
                }
                if (hit) { alarm = true; ruleBits |= RULE_DOOR; }
            }
            [loop] for (int bj = 0; bj < FS_COUNT; bj++)
            {
                if (bj == ai) continue;
                Piece q = gP[bj];
                if ((q.flags & FF_HIDDEN) != 0 || !fkIsFloorBody(q.kind)) continue;
                if (rectOverlap(p.pos, p.yaw, h, q.pos, q.yaw, halfWD(q)) > 0.02) { alarm = true; if (bj > ai) overlaps += 1; }
            }
            // tall pieces in front of a window
            [loop] for (int wi = 0; wi < SHELL_OPEN_MAX; wi++)
            {
                BROpening q = gOp[wi];
                if (!q.active || !brOpenIsWindow(q.kind)) continue;
                if (p.size.y < q.sill + 0.25) continue;
                float2 n2 = brWallNormal(q.wall);
                float2 p0 = brWallPoint(R, q.wall, q.a, 0.0);
                float2 al2 = brWallAlongX(q.wall) ? float2(1, 0) : float2(0, 1);
                float dist = dot(p.pos - p0, n2) - abs(dot(rr, n2)) - abs(dot(ff, n2));
                float lat = abs(dot(p.pos - p0, al2)) - abs(dot(rr, al2)) - abs(dot(ff, al2));
                if (dist < 0.45 && lat < q.width * 0.5 - 0.1) alarm = true;
            }
        }
        if (p.kind == FK_ART)
        {
            int w = (p.parent <= FP_WALL0 && p.parent >= FP_WALL0 - 3) ? FP_WALL0 - p.parent : -1;
            [loop] for (int wi2 = 0; wi2 < SHELL_OPEN_MAX; wi2++)
            {
                BROpening q = gOp[wi2];
                if (!q.active || q.wall != w || q.kind == OPEN_FIREPLACE) continue;
                float a = brWallAlongX(w) ? p.pos.x : p.pos.y;
                bool ov = abs(a - q.a) < (p.size.x + q.width) * 0.5 + 0.08 && p.y0 < q.sill + q.height + 0.09 && p.y0 + p.size.y > q.sill - 0.03;
                if (ov) alarm = true;
            }
            if (p.y0 + p.size.y > R.H - max(R.crown, 0.02)) alarm = true;
        }
        if (alarm) { gP[ai].flags |= FF_ALARM; alarmCount += 1; }
    }
    if (overlaps > 0) ruleBits |= RULE_OVERLAP;

    // coffee gap, measured in the sofa's own frame
    float coffeeGap = 0.0;
    {
        Piece s = gP[FS_SOFA], c = gP[FS_COFFEE];
        float2 hc = halfWD(c);
        float minZ = 1e9;
        if (fkRound(c.kind, c.variant)) minZ = toLocal2(s.pos, s.yaw, c.pos).y - hc.x;
        else
        {
            float2 rr = right2(c.yaw) * hc.x, ff = fwd2(c.yaw) * hc.y;
            float2 cc[4] = { c.pos - rr - ff, c.pos + rr - ff, c.pos + rr + ff, c.pos - rr + ff };
            [unroll] for (int k = 0; k < 4; k++) minZ = min(minZ, toLocal2(s.pos, s.yaw, cc[k]).y);
        }
        coffeeGap = minZ - s.size.z * 0.5;
        bool both = (s.flags & FF_HIDDEN) == 0 && (c.flags & FF_HIDDEN) == 0;
        if (both && (coffeeGap < 0.35 || coffeeGap > 0.58)) ruleBits |= RULE_COFFEE;
        if (!both) coffeeGap = -1.0;
    }

    // conversation: the two outer sofa seats and each chair; the widest pair
    float conv = 0.0;
    float2 convC = 0;
    int seats = 0, onRug = 0;
    {
        float2 pts[4];
        int np = 0;
        Piece s = gP[FS_SOFA];
        if ((s.flags & FF_HIDDEN) == 0)
        {
            float off = max(s.size.x * 0.5 - 0.50, 0.2);
            pts[0] = toWorld2(s.pos, s.yaw, float2(-off, 0.05)); pts[1] = toWorld2(s.pos, s.yaw, float2(off, 0.05)); np = 2;
        }
        Piece ca = gP[FS_CHAIR_A], cb = gP[FS_CHAIR_B];
        if ((ca.flags & FF_HIDDEN) == 0) { pts[np] = ca.pos; np++; }
        if ((cb.flags & FF_HIDDEN) == 0 && np < 4) { pts[np] = cb.pos; np++; }
        [loop] for (int a = 0; a < np; a++)
        {
            convC += pts[a];
            [loop] for (int b = a + 1; b < np; b++) conv = max(conv, length(pts[a] - pts[b]));
        }
        convC /= max((float)np, 1.0);
        if (conv > 3.3) ruleBits |= RULE_CONVERSE;
        // front legs on the rug?
        Piece rg = gP[FS_RUG];
        [loop] for (int si = FS_SOFA; si <= FS_CHAIR_B; si++)
        {
            Piece q = gP[si];
            if ((q.flags & FF_HIDDEN) != 0) continue;
            seats += 1;
            float2 front = q.pos + fwd2(q.yaw) * (q.size.z * 0.5 - 0.08);
            if ((rg.flags & FF_HIDDEN) == 0 && footSd(front, rg.pos, rg.yaw, rg.size.xz * 0.5) < 0.0) onRug += 1;
        }
    }

    // hearth clearance: the nearest floor piece to the hearth slab
    float hearthClear = -1.0;
    if (C.fp >= 0)
    {
        BROpening f = gOp[C.fp];
        float2 n2 = brWallNormal(f.wall);
        // the slab in front of the breast is what must stay clear
        float2 hcen = brWallPoint(R, f.wall, f.a, C.fpDepth + 0.24);
        float hy = yawOf2(n2);
        float2 hh = float2(f.width * 0.5 + 0.12, 0.24);
        hearthClear = 9.0;
        [loop] for (int si = 0; si < FS_COUNT; si++)
        {
            Piece q = gP[si];
            if ((q.flags & FF_HIDDEN) != 0 || !fkIsFloorBody(q.kind)) continue;
            if (q.parent <= FP_WALL0 && q.parent >= FP_WALL0 - 3) continue;       // wall pieces beside the breast
            float2 h = halfWD(q);
            float2 rr = right2(q.yaw) * h.x, ff = fwd2(q.yaw) * h.y;
            float2 cc[4] = { q.pos - rr - ff, q.pos + rr - ff, q.pos + rr + ff, q.pos - rr + ff };
            [unroll] for (int k = 0; k < 4; k++) hearthClear = min(hearthClear, footSd(cc[k], hcen, hy, hh));
            float2 hr = right2(hy) * hh.x, hf = fwd2(hy) * hh.y;
            float2 hc4[4] = { hcen - hr - hf, hcen + hr - hf, hcen + hr + hf, hcen - hr + hf };
            [unroll] for (int k2 = 0; k2 < 4; k2++) hearthClear = min(hearthClear, footSd(hc4[k2], q.pos, q.yaw, h));
        }
        if (hearthClear < 0.75) ruleBits |= RULE_HEARTH;
    }

    // ---- the walkway: a widest-path route from the door to the windows over a clearance grid
    float cs = max(max(R.x1 - R.x0, R.z1 - R.z0) / 38.0, 0.18);
    int nx = clamp((int)ceil((R.x1 - R.x0) / cs), 2, 40), nz = clamp((int)ceil((R.z1 - R.z0) / cs), 2, 40);
    float csx = (R.x1 - R.x0) / (float)nx, csz = (R.z1 - R.z0) / (float)nz;
    // What the walkway must clear: every visible floor piece, the hearth slab and the radiators.
    // Each footprint's axes are worked out here once, not once per cell (that was most of the
    // solve). The distances are the same footSd arithmetic, and min() does not care about order.
    int nOb = 0;
    [loop] for (int si = 0; si < FS_COUNT; si++)
    {
        Piece q = gP[si];
        if ((q.flags & FF_HIDDEN) == 0 && fkIsFloorBody(q.kind))
        {
            float2 h = halfWD(q);
            bool rnd = fkRound(q.kind, q.variant);
            gObA[nOb] = float4(q.pos, right2(q.yaw));
            gObB[nOb] = float4(fwd2(q.yaw), h);
            gObRound[nOb] = rnd ? 1u : 0u;
            nOb++;
        }
    }
    if (C.fp >= 0)
    {
        BROpening f = gOp[C.fp];
        float hd = C.fpDepth + 0.48;
        float fy = yawOf2(brWallNormal(f.wall));
        gObA[nOb] = float4(brWallPoint(R, f.wall, f.a, hd * 0.5), right2(fy));
        gObB[nOb] = float4(fwd2(fy), float2(f.width * 0.5 + 0.12, hd * 0.5));
        gObRound[nOb] = 0u;
        nOb++;
    }
    [loop] for (int wi = 0; wi < SHELL_OPEN_MAX; wi++)
    {
        BROpening q = gOp[wi];
        if (q.active && q.radiator)
        {
            float ry = yawOf2(brWallNormal(q.wall));
            gObA[nOb] = float4(brWallPoint(R, q.wall, q.a, 0.10), right2(ry));
            gObB[nOb] = float4(fwd2(ry), float2(q.width * 0.5 - 0.04, 0.10));
            gObRound[nOb] = 0u;
            nOb++;
        }
    }
    [loop] for (int gz = 0; gz < nz; gz++)
    [loop] for (int gx = 0; gx < nx; gx++)
    {
        float2 c = float2(R.x0 + ((float)gx + 0.5) * csx, R.z0 + ((float)gz + 0.5) * csz);
        float d = min(min(c.x - R.x0, R.x1 - c.x), min(c.y - R.z0, R.z1 - c.y));
        [loop] for (int oi = 0; oi < nOb; oi++)
        {
            float4 A = gObA[oi], B = gObB[oi];
            float od;
            if (gObRound[oi] != 0u) od = length(c - A.xy) - B.z;
            else
            {
                // footSd, with toLocal2's axes precomputed
                float2 dl = c - A.xy;
                float2 qb = abs(float2(dot(dl, A.zw), dot(dl, B.xy))) - B.zw;
                od = length(max(qb, 0.0)) + min(max(qb.x, qb.y), 0.0);
            }
            d = min(d, od);
        }
        gClr[gz * nx + gx] = d;
        gCost[gz * nx + gx] = 1e9;
        // a person keeps away from furniture where the floor allows: a strong pull toward 60 cm
        // of clearance, a wall below 22 cm
        gPen[gz * nx + gx] = (d < 0.22) ? 1e5 : 1.0 + 7.0 * pow(saturate((0.62 - d) / 0.40), 2.0);
    }
    // start just inside the door, target in front of the windows
    bool routeOk = false;
    float routeMin = 0.0, routeLen = 0.0;
    float2 narrow = 0;
    int routeN = 0;
    float2 route[FURN_ROUTE_N];
    [unroll] for (int ri0 = 0; ri0 < FURN_ROUTE_N; ri0++) route[ri0] = 0;
    if (C.door >= 0 && C.winWall >= 0)
    {
        float2 sP = brWallPoint(R, door.wall, door.a, 0.45);
        float2 tP = brWallPoint(R, C.winWall, C.winA, 0.75);
        int2 sc = int2(clamp((int)((sP.x - R.x0) / csx), 0, nx - 1), clamp((int)((sP.y - R.z0) / csz), 0, nz - 1));
        int2 tc = int2(clamp((int)((tP.x - R.x0) / csx), 0, nx - 1), clamp((int)((tP.y - R.z0) / csz), 0, nz - 1));
        gCost[sc.y * nx + sc.x] = 0.0;
        // fast sweeping: costs are path length weighted against squeezing past things. Once a
        // whole pass (both directions) lowers no cell, every later pass would repeat it exactly,
        // so the sweep stops there instead of always running six.
        [loop] for (int it = 0; it < 6; it++)
        {
            bool lowered = false;
            [loop] for (int dirn = 0; dirn < 2; dirn++)
            {
                int stp = (dirn == 0) ? 1 : -1;
                [loop] for (int j = 0; j < nz; j++)
                {
                    int iz = (dirn == 0) ? j : nz - 1 - j;
                    // The cell swept just before this one is the left neighbour, and its new cost
                    // is still in a register: reading it back through shared memory put a store
                    // and a load on the critical path of every step of a serial sweep.
                    float leftCost = 1e9;
                    [loop] for (int i = 0; i < nx; i++)
                    {
                        int ix = (dirn == 0) ? i : nx - 1 - i;
                        int ci = iz * nx + ix;
                        float pen = gPen[ci];
                        float was = gCost[ci];
                        float best = was;
                        if (i > 0) best = min(best, leftCost + csx * pen);
                        int2 nb[3] = { int2(ix, iz - stp), int2(ix - stp, iz - stp), int2(ix + stp, iz - stp) };
                        [unroll] for (int k = 0; k < 3; k++)
                        {
                            int2 q = nb[k];
                            if (q.x < 0 || q.x >= nx || q.y < 0 || q.y >= nz) continue;
                            float len = (k >= 1) ? length(float2(csx, csz)) : csz;
                            best = min(best, gCost[q.y * nx + q.x] + len * pen);
                        }
                        gCost[ci] = best;
                        leftCost = best;
                        if (best < was) lowered = true;
                    }
                }
            }
            if (!lowered) break;
        }
        float tc0 = gCost[tc.y * nx + tc.x];
        if (tc0 < 1e4)
        {
            routeOk = true;
            routeMin = 9.0;
            // walk back down the cost field, recording every few cells
            int2 cur = tc;
            float2 prev = float2(R.x0 + ((float)cur.x + 0.5) * csx, R.z0 + ((float)cur.y + 0.5) * csz);
            int stride2 = max((nx + nz) / 14, 1);
            [loop] for (int st = 0; st < 160; st++)
            {
                float2 cp = float2(R.x0 + ((float)cur.x + 0.5) * csx, R.z0 + ((float)cur.y + 0.5) * csz);
                routeLen += length(cp - prev);
                prev = cp;
                float clr = gClr[cur.y * nx + cur.x];
                bool ends = length(cp - sP) < 0.7 || length(cp - tP) < 0.7;
                if (!ends && clr < routeMin) { routeMin = clr; narrow = cp; }
                if ((st % stride2) == 0 && routeN < FURN_ROUTE_N - 1) { route[routeN] = cp; routeN++; }
                if (cur.x == sc.x && cur.y == sc.y) break;
                int2 nxt = cur; float bc = gCost[cur.y * nx + cur.x];
                [unroll] for (int k = 0; k < 8; k++)
                {
                    int2 o2 = int2((k % 3) - 1, (k / 3) - 1);
                    if (k >= 4) o2 = int2(((k + 1) % 3) - 1, ((k + 1) / 3) - 1);
                    int2 q = cur + o2;
                    if (q.x < 0 || q.x >= nx || q.y < 0 || q.y >= nz) continue;
                    float c2 = gCost[q.y * nx + q.x];
                    if (c2 < bc) { bc = c2; nxt = q; }
                }
                if (nxt.x == cur.x && nxt.y == cur.y) break;
                cur = nxt;
            }
            route[routeN] = sP; routeN++;
            if (routeMin * 2.0 < walkway) ruleBits |= RULE_WALKWAY;
        }
        else ruleBits |= RULE_BLOCKED;
    }

    // ---- publish
    [loop] for (int pi = 0; pi < FURN_MAX; pi++)
    {
        BRRec r;
        if (pi < FS_COUNT)
        {
            Piece p = gP[pi];
            FPiece f;
            f.slot = pi; f.kind = p.kind; f.variant = p.variant; f.parent = p.parent; f.flags = p.flags;
            f.matA = p.matA; f.matB = p.matB; f.pos = p.pos; f.yaw = p.yaw; f.y0 = p.y0; f.seed = p.seed;
            f.size = p.size;
            r = fpToRec(f);
        }
        else
        {
            r.head = float4(ROLE_FURN, FK_NONE, 0, pi); r.dims = 0; r.look = 0; r.meta = float4(0, 0, FF_HIDDEN, FP_WORLD);
        }
        Furn[pi] = r;
    }
    [loop] for (int dj = 0; dj < FS_COUNT; dj++) Furn[FURN_DELTA0 + dj] = writeDelta(gD[dj], dj);

    diag.head.x = ROLE_NONE;
    Furn[FURN_DIAG] = diag;

    BRRec rules;
    rules.head = float4(ROLE_FURN_ED, 1, routeN, ruleBits);
    rules.dims = float4(coffeeGap, conv, routeOk ? routeMin * 2.0 : -1.0, hearthClear);
    rules.look = float4(convC, narrow);
    rules.meta = float4(onRug, seats, routeLen, overlaps);
    Furn[FURN_RULES] = rules;
    [loop] for (int rq = 0; rq < FURN_ROUTE_N / 2; rq++)
    {
        BRRec rr;
        rr.head = float4(ROLE_FURN_ED, 2, rq, 0);
        rr.dims = float4(route[rq * 2], route[rq * 2 + 1]);
        rr.look = float4(gO, gYaw, cutD);
        rr.meta = float4(C.focalWall, secWall, C.fp, C.door);
        Furn[FURN_ROUTE0 + rq] = rr;
    }

    fz.head = float4(ROLE_FURN_ED, 2, 0, 0);
    fz.dims = float4(startPx, startSize);
    fz.look = startDelta;
    fz.meta = float4(grabOff, alarmCount, 0);
    Furn[REC_FROZEN] = fz;
    // the signature of what was just published (deltas are already written above)
    BRRec fzs = Furn[REC_FROZEN];
    fzs.meta.w = asfloat(inputSig(haveShell, reroll, res));
    Furn[REC_FROZEN] = fzs;

    ed.head = float4(ROLE_FURN_ED, sel, secWall, PLAN_VERSION);
    ed.dims = float4(dragActive, handle, surface, reroll);
    ed.look = startVals;
    ed.meta = float4(asfloat(newLast), handled, (float)alarmCount, cutD);
    Furn[FURN_EDITOR] = ed;
}
