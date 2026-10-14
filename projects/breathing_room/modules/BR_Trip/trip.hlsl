// BR_Trip / trip.hlsl -- the TRIP authority. One thread, once per cook.
//
// Anchors are attached to FEATURES of the room, never to free coordinates: the rug's medallion,
// the ceiling over the pendant, the longest plain wall, the chimney breast and the mantel, a
// picture, the floor between the sofa and the hearth, the sofa itself, the coffee table... When
// the shell or the furniture changes, every anchor follows its feature. A re-roll changes WHICH
// features carry WHICH effect, how fast and how strongly -- the relationships, not the places --
// with guarantees: geometry always blooms somewhere, at least five anchors run, never more than
// ten, and objects only take effects an object can do.
//
// Hand edits are deltas over that procedural result (move an anchor to another surface or onto a
// piece of furniture, resize it, change its kind, strength, rate, switch it off), so a re-roll or
// a moved sofa never erases them. The trip CLOCK is integrated here (tempo changes never jump a
// phase), and the dose envelope (steady, waves, come-up) is applied to the published dose.
//
// Every event is handled in one if/else chain with no `continue`: FXC drops stores made before a
// mid-body `continue` (BR_Light hit it), so this loop has a single exit from the start.
#include "../_shared/br_records.hlsli"
#include "../_shared/br_furn_defs.hlsli"
RWStructuredBuffer<BRRec> Trip : register(u0);
#define TRIP_REC(i) Trip[i]
#include "../_shared/br_shade.hlsli"
#include "../_shared/br_trip.hlsli"
#include "trip_layout.hlsli"

#define PLAN_VERSION 1.0
#define H_NONE   0
#define H_MOVE   1
#define H_RADIUS 2
#define GLOBAL_DELTA (TRIP_DELTA0 + 12)
// BR_Furnish's slots this authority attaches to (furnish_defs.hlsli: FS_*)
#define FS_SOFA_SLOT   1
#define FS_COFFEE_SLOT 4
#define FS_PENDANT_SLOT 10
#define FS_PLANT_SLOT  14
#define FS_ART_SLOT    17
#define FS_COUNT_SLOTS 30

float sane(float v) { return (abs(v) < 1e5) ? v : 0.0; }
BRRec sh(uint i) { BRRec r; r.head = _Data0[i].head; r.dims = _Data0[i].dims; r.look = _Data0[i].look; r.meta = _Data0[i].meta; return r; }
BRRec fu(uint i) { BRRec r; r.head = _Data1[i].head; r.dims = _Data1[i].dims; r.look = _Data1[i].look; r.meta = _Data1[i].meta; return r; }

// the 12 feature slots
#define F_RUG       0
#define F_CEIL      1
#define F_WALL      2
#define F_BREAST    3
#define F_MANTEL    4
#define F_ART       5
#define F_FLOORFLOW 6
#define F_CEILWIN   7
#define F_SOFA      8
#define F_PLANT     9
#define F_TABLE     10
#define F_CORNER    11

// kinds a host can carry: surfaces take anything, objects breathe, melt or swirl
bool kindFits(int kind, int host)
{
    if (host >= TH_OBJ0) return kind == TK_BREATHE || kind == TK_MELT || kind == TK_SWIRL;
    if (host == TH_FLOOR || host == TH_CEIL) return kind != TK_MELT;
    return true;
}
int nextKind(int kind, int host)
{
    // the next kind after `kind` (cyclic, 1..TK_COUNT-1) that this host can carry
    int best = TK_BREATHE;
    bool found = false;
    [unroll] for (int i = 1; i < TK_COUNT; i++)
    {
        int k = ((max(kind, 1) - 1 + i) % (TK_COUNT - 1)) + 1;
        if (!found && kindFits(k, host)) { best = k; found = true; }
    }
    return best;
}
float3 hostNormal(int host)
{
    if (host == TH_FLOOR || host >= TH_OBJ0) return float3(0, 1, 0);
    if (host == TH_CEIL) return float3(0, -1, 0);
    float2 n = brWallNormal(host - TH_WALL0);
    return float3(n.x, 0.0, n.y);
}

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    float2 res = (_Resolution.x >= 64.0) ? _Resolution.xy : float2(1280.0, 900.0);
    bool haveShell = _Data0_Count >= 13u && abs(_Data0[0].head.x - ROLE_ROOM) < 0.5;
    BRRoom R = brDefaultRoom();
    if (haveShell) R = brRoomFromRec(sh(0));
    bool haveFurn = _Data1_Count >= 30u && abs(_Data1[0].head.x - ROLE_FURN) < 0.5;
    TLayout L = tLayout(res, R);

    // ---- persistent state
    BRRec ed = Trip[TRIP_EDITOR];
    bool fresh = !(abs(ed.head.x - ROLE_TRIP_ED) < 0.5) || abs(sane(ed.head.w) - PLAN_VERSION) > 0.01;
    if (fresh)
    {
        BRRec z; z.head = float4(ROLE_DELTA, 0, 0, 0); z.dims = 0; z.look = 0; z.meta = 0;
        [loop] for (int i = TRIP_DELTA0; i < TRIP_RECORDS; i++) Trip[i] = z;
        ed.head = float4(ROLE_TRIP_ED, -1, 0, PLAN_VERSION); ed.dims = 0; ed.look = 0; ed.meta = 0;
        BRRec h0; h0.head = 0; h0.dims = 0; h0.look = 0; h0.meta = 0;
        Trip[TRIP_HEADER] = h0;
    }
    BRRec gd = Trip[GLOBAL_DELTA];
    float seedOff = sane(gd.dims.x);
    float doseD = clamp(sane(gd.dims.y), -1.0, 1.0);
    float motifD = sane(gd.dims.z);
    float addArmed = sane(gd.dims.w);
    float hold = sane(gd.look.x);
    float restart = 0.0;
    int sel = (int)round(sane(ed.head.y));
    if (sel < -1 || sel >= TRIP_ANCH_MAX) sel = -1;
    int handle = (int)round(sane(ed.dims.x));
    uint lastSeq = asuint(ed.meta.x);
    float handled = sane(ed.meta.y);
    float4 probe = ed.look;

    // deltas: head (role, slot, edited, 0) dims (host, s1, s2, hasPos)
    //         look (kind override, strength log2, radius log2, rate log2) meta (enable 0/1 on/2 off)
    float4 dPos[TRIP_ANCH_MAX];
    float4 dMod[TRIP_ANCH_MAX];
    float dEn[TRIP_ANCH_MAX];
    [unroll] for (int k0 = 0; k0 < TRIP_ANCH_MAX; k0++)
    {
        BRRec r = Trip[TRIP_DELTA0 + k0];
        dPos[k0] = float4(round(sane(r.dims.x)), sane(r.dims.y), sane(r.dims.z), round(saturate(sane(r.dims.w))));
        dMod[k0] = float4(clamp(round(sane(r.look.x)), 0.0, (float)(TK_COUNT - 1)), clamp(sane(r.look.y), -3.0, 3.0),
                          clamp(sane(r.look.z), -3.0, 3.0), clamp(sane(r.look.w), -3.0, 3.0));
        dEn[k0] = clamp(round(sane(r.meta.x)), 0.0, 2.0);
    }

    // ---- the features
    float3 rugC = float3((R.x0 + R.x1) * 0.5, 0.0, (R.z0 + R.z1) * 0.5);
    float rugR = 0.9;
    float3 pendC = rugC;
    float3 sofaC = rugC + float3(0, 0.4, -1.0);
    float3 fireC = float3((R.x0 + R.x1) * 0.5, 0.0, R.z1);
    bool haveFire = false;
    float fireA = 0.0, fireMh = 1.2, fireDepth = 0.36;
    int fireWall = WALL_N;
    float3 objC[3] = { sofaC, rugC + float3(1.5, 0.6, 0.5), rugC + float3(0, 0.2, 0) };    // sofa, plant, coffee
    bool objOn[3] = { false, false, false };
    int objSlot[3] = { FS_SOFA_SLOT, FS_PLANT_SLOT, FS_COFFEE_SLOT };
    float3 artC = float3(R.x0 + 0.01, 1.6, (R.z0 + R.z1) * 0.5);
    int artWall = WALL_W;
    float artR = 0.45;
    bool haveArt = false;
    if (haveFurn)
    {
        BRRec rug = fu(0);
        if ((int)round(rug.head.y) == FK_RUG && ((int)round(rug.meta.z) & FF_HIDDEN) == 0)
        {
            rugC = float3(rug.dims.x, 0.0, rug.dims.y);
            rugR = 0.42 * min(rug.look.x, rug.look.z);
        }
        BRRec pd = fu(FS_PENDANT_SLOT);
        pendC = ((int)round(pd.head.y) == FK_PENDANT) ? float3(pd.dims.x, R.H, pd.dims.y) : float3(rugC.x, R.H, rugC.z);
        [unroll] for (int oi = 0; oi < 3; oi++)
        {
            BRRec f = fu((uint)objSlot[oi]);
            int fk = (int)round(f.head.y);
            bool vis = fk != FK_NONE && ((int)round(f.meta.z) & FF_HIDDEN) == 0;
            objOn[oi] = vis;
            if (vis) objC[oi] = float3(f.dims.x, f.dims.w + f.look.y * 0.5, f.dims.y);
        }
        sofaC = objC[0];
        BRRec art = fu(FS_ART_SLOT);
        int host = (int)round(art.meta.w);
        if ((int)round(art.head.y) == FK_ART && host <= -2 && ((int)round(art.meta.z) & FF_HIDDEN) == 0)
        {
            haveArt = true;
            artWall = clamp(-2 - host, 0, 3);
            artC = float3(art.dims.x, art.dims.w + art.look.y * 0.5, art.dims.y);
            artR = 0.6 * max(art.look.x, art.look.y);
        }
    }
    else pendC = float3(rugC.x, R.H, rugC.z);
    // the fireplace, and the wall with the longest unbroken span (not the fireplace wall)
    float bestGap = -1.0;
    float3 wallC = float3(R.x0, 1.55, (R.z0 + R.z1) * 0.5);
    int wallW = WALL_W;
    float wallR = 1.2;
    float3 winC = float3(R.x0 + 0.9, R.H, (R.z0 + R.z1) * 0.5);
    float3 cornerC = float3(R.x1, 1.25, R.z0 + 0.8);
    int cornerW = WALL_E;
    bool winFound = false;
    [loop] for (int oi2 = 0; oi2 < SHELL_OPEN_MAX; oi2++)
    {
        if (haveShell)
        {
            BROpening o = brOpeningFromRec(sh(5 + (uint)oi2));
            if (o.active && o.kind == OPEN_FIREPLACE && !haveFire)
            {
                haveFire = true; fireA = o.a; fireMh = o.height; fireWall = o.wall; fireDepth = o.depth;
                float2 p2 = brWallPoint(R, o.wall, o.a, 0.0);
                fireC = float3(p2.x, 0.0, p2.y);
            }
            if (o.active && brOpenIsGlazed(o.kind) && !winFound)
            {
                winFound = true;
                float2 p2 = brWallPoint(R, o.wall, o.a, 0.9);
                winC = float3(p2.x, R.H, p2.y);
            }
        }
    }
    [unroll] for (int w = 0; w < 4; w++)
    {
        float2 ext = brWallExtent(R, w);
        // walk the openings on this wall in along-order, keeping the widest gap
        float cur = ext.x + 0.35;
        float gBest = 0.0, aBest = (ext.x + ext.y) * 0.5;
        bool done = false;
        [loop] for (int pass2 = 0; pass2 < SHELL_OPEN_MAX + 1; pass2++)
        {
            if (!done)
            {
                // the next opening edge after `cur`
                float nextA = ext.y - 0.35, nextEnd = ext.y - 0.35;
                [loop] for (int oi3 = 0; oi3 < SHELL_OPEN_MAX; oi3++)
                {
                    if (haveShell)
                    {
                        BROpening o = brOpeningFromRec(sh(5 + (uint)oi3));
                        float hw = o.width * 0.5 + 0.25;
                        if (o.active && o.wall == w && o.a - hw >= cur - 1e-3 && o.a - hw < nextA) { nextA = o.a - hw; nextEnd = o.a + hw; }
                    }
                }
                float gap = nextA - cur;
                if (gap > gBest) { gBest = gap; aBest = (cur + nextA) * 0.5; }
                cur = max(nextEnd, cur + 0.01);
                done = cur >= ext.y - 0.36;
            }
        }
        bool fireWallHere = haveFire && w == fireWall;
        if (!fireWallHere && gBest > bestGap)
        {
            bestGap = gBest; wallW = w;
            float2 p2 = brWallPoint(R, w, aBest, 0.0);
            wallC = float3(p2.x, 1.55, p2.y);
            wallR = clamp(gBest * 0.32, 0.6, 1.4);
        }
    }
    // the corner wall: the one opposite the plain wall, near its first quarter
    {
        int ow = (wallW + 2) % 4;
        if (haveFire && ow == fireWall) ow = (wallW + 1) % 4;
        float2 ext = brWallExtent(R, ow);
        float2 p2 = brWallPoint(R, ow, lerp(ext.x, ext.y, 0.22), 0.0);
        cornerC = float3(p2.x, 1.25, p2.y);
        cornerW = ow;
    }
    // two anchors never share a spot: if the plain wall is the picture's wall, the breathing moves
    // along it, away from the picture, to whichever side has more wall
    if (haveArt && wallW == artWall)
    {
        float aWall = brWallAlongX(wallW) ? wallC.x : wallC.z;
        float aArt = brWallAlongX(wallW) ? artC.x : artC.z;
        float sep = artR + wallR * 0.75;
        if (abs(aWall - aArt) < sep)
        {
            float2 ext = brWallExtent(R, wallW);
            float side = ((ext.y - aArt) > (aArt - ext.x)) ? 1.0 : -1.0;
            float aNew = clamp(aArt + side * sep, ext.x + wallR * 0.6, ext.y - wallR * 0.6);
            float2 p2 = brWallPoint(R, wallW, aNew, 0.0);
            wallC = float3(p2.x, wallC.y, p2.y);
            wallR = min(wallR, max(abs(aNew - aArt) - artR * 0.5, 0.5));
        }
    }
    // on the chimney breast's own face (it stands proud of the wall plane), and on the mantel's
    float2 bp = brWallPoint(R, fireWall, fireA, fireDepth);
    float2 mp = brWallPoint(R, fireWall, fireA, fireDepth + 0.08);
    float3 breastC = float3(bp.x, fireMh + 0.55, bp.y);
    float3 mantelC = float3(mp.x, fireMh - 0.02, mp.y);
    float3 flowC = lerp(sofaC, haveFire ? fireC : rugC, 0.5); flowC.y = 0.0;

    // ---- the procedural anchors (variation 0 is the designed arrangement)
    int gKind[TRIP_ANCH_MAX] = { TK_SWIRL, TK_BLOOM, TK_BREATHE, TK_BLOOM, TK_MELT, TK_SWIRL, TK_FLOW, TK_BREATHE, TK_BREATHE, TK_SWIRL, TK_MELT, TK_FLOW };
    int gHost[TRIP_ANCH_MAX] = { TH_FLOOR, TH_CEIL, TH_WALL0 + wallW, TH_WALL0 + fireWall, TH_WALL0 + fireWall, TH_WALL0 + artWall,
                                 TH_FLOOR, TH_CEIL, TH_OBJ0 + FS_SOFA_SLOT, TH_OBJ0 + FS_PLANT_SLOT, TH_OBJ0 + FS_COFFEE_SLOT, TH_WALL0 + cornerW };
    float3 gC[TRIP_ANCH_MAX] = { rugC, pendC, wallC, breastC, mantelC, artC, flowC, winC, objC[0], objC[1], objC[2], cornerC };
    float gRad[TRIP_ANCH_MAX] = { rugR, 1.35, wallR, 0.55, 0.62, artR, 1.15, 1.2, 0.9, 0.6, 0.6, 0.9 };
    bool gOn[TRIP_ANCH_MAX] = { true, true, true, haveFire, haveFire, haveArt, true, false, objOn[0], false, objOn[2], false };
    float gStr[TRIP_ANCH_MAX] = { 0.75, 0.8, 0.7, 0.6, 0.55, 0.6, 0.5, 0.6, 0.7, 0.6, 0.6, 0.5 };
    float gRate[TRIP_ANCH_MAX] = { 0.07, 0.09, 0.12, 0.08, 0.06, 0.1, 0.07, 0.11, 0.13, 0.09, 0.05, 0.08 };
    int v = variation + (int)round(seedOff);
    if (v != 0)
    {
        int nOn = 0;
        [unroll] for (int i = 0; i < TRIP_ANCH_MAX; i++)
        {
            uint hs = (uint)(v * 7919 + i * 104729 + 17);
            float u0 = brHash01(hs), u1 = brHash01(hs + 1u), u2 = brHash01(hs + 2u), u3 = brHash01(hs + 3u);
            bool can = true;
            if ((i == F_BREAST || i == F_MANTEL) && !haveFire) can = false;
            if (i == F_ART && !haveArt) can = false;
            if (i == F_SOFA && !objOn[0]) can = false;
            if (i == F_PLANT && !objOn[1]) can = false;
            if (i == F_TABLE && !objOn[2]) can = false;
            gOn[i] = can && u0 < 0.7;
            int kk = 1 + (int)floor(u1 * 5.0);
            if (!kindFits(kk, gHost[i])) kk = nextKind(kk, gHost[i]);
            gKind[i] = kk;
            gRate[i] = 0.05 + 0.11 * u2;
            gStr[i] = 0.5 + 0.4 * u3;
            if (gOn[i]) nOn++;
        }
        // guarantees: geometry blooms somewhere (the ceiling over the pendant), at least five run
        gOn[F_CEIL] = true; gKind[F_CEIL] = TK_BLOOM;
        [unroll] for (int j = 0; j < TRIP_ANCH_MAX; j++)
        {
            bool can = !((j == F_BREAST || j == F_MANTEL) && !haveFire) && !(j == F_ART && !haveArt);
            if (nOn < 5 && !gOn[j] && can && j < F_SOFA) { gOn[j] = true; nOn++; }
        }
        // ...and never more than ten
        [unroll] for (int j2 = TRIP_ANCH_MAX - 1; j2 >= 0; j2--)
        {
            if (nOn > 10 && gOn[j2] && j2 != F_CEIL) { gOn[j2] = false; nOn--; }
        }
    }

    // ---- events, each consumed once by sequence; ONE exit per event
    uint n = _ViewportEventCount;
    uint ringMax = 0u;
    [loop] for (uint ri = 0u; ri < n; ri++) ringMax = max(ringMax, _ViewportEvents[ri].sequence);
    if (n > 0u && ringMax < lastSeq) lastSeq = 0u;
    uint newLast = lastSeq;
    [loop] for (uint ei = 0u; ei < n; ei++)
    {
        ViewportEvent ev = _ViewportEvents[ei];
        bool isFresh = ev.sequence > lastSeq || (lastSeq - ev.sequence) > (1u << 20);
        if (isFresh)
        {
            newLast = (ev.sequence > lastSeq) ? max(newLast, ev.sequence) : ev.sequence;
            handled += 1.0;
            float2 px = ev.position * res;
            bool press = ev.type == 2u && ev.code == 0u && ev.phase == 1u;
            bool release = ev.type == 2u && ev.code == 0u && ev.phase == 3u;
            bool dragMove = ev.type == 5u && ev.code == 3u && (ev.phase == 6u || ev.phase == 7u);
            bool dragEnd = ev.type == 5u && ev.code == 3u && (ev.phase == 7u || ev.phase == 8u);
            int chip = press ? tChipAt(L, px) : -1;
            bool inNet = tInRect(px, L.netR, 0.0);
            // the surface (or the piece of furniture) under the pointer
            int pHost = -1; float3 pW = 0, pN = 0;
            bool onSurf = tNetToWorld(L, tNetXY(L, px), pHost, pW, pN);
            int pObj = -1;
            if (onSurf && pHost == TH_FLOOR && haveFurn)
            {
                [loop] for (int fs = 1; fs < FS_COUNT_SLOTS; fs++)
                {
                    BRRec f = fu((uint)fs);
                    int fk = (int)round(f.head.y);
                    // lamps hold still (BR_Render): an anchor dropped on one lands on the floor
                    if (pObj < 0 && fk != FK_NONE && fk != FK_RUG && !fkIsLamp(fk) && fkHosting(fk) == FH_FLOOR && ((int)round(f.meta.z) & FF_HIDDEN) == 0)
                    {
                        float2 dd = pW.xz - f.dims.xy;
                        float yaw = f.dims.z;
                        float2 lq = float2(dot(dd, float2(cos(yaw), -sin(yaw))), dot(dd, float2(sin(yaw), cos(yaw))));
                        if (all(abs(lq) < f.look.xz * 0.5)) pObj = fs;
                    }
                }
            }
            if (press) probe = float4(px, (float)chip, onSurf ? (float)pHost : -1.0);

            if (chip >= 0 && sel >= 0)
            {
                [unroll] for (int kc = 0; kc < TRIP_ANCH_MAX; kc++)
                {
                    if (kc == sel)
                    {
                        int hostNow = (dPos[kc].w > 0.5) ? (int)dPos[kc].x : gHost[kc];
                        int kindNow = (dMod[kc].x > 0.5) ? (int)dMod[kc].x : gKind[kc];
                        bool onNow = (dEn[kc] == 1.0) ? true : ((dEn[kc] == 2.0) ? false : gOn[kc]);
                        if (chip == 0) dMod[kc].x = (float)nextKind(kindNow, hostNow);
                        else if (chip == 1) dEn[kc] = onNow ? 2.0 : 1.0;
                        else if (chip == 2) dMod[kc].y = min(dMod[kc].y + 0.32, 3.0);
                        else if (chip == 3) dMod[kc].y = max(dMod[kc].y - 0.32, -3.0);
                        else if (chip == 4) dMod[kc].w = min(dMod[kc].w + 0.32, 3.0);
                        else if (chip == 5) dMod[kc].w = max(dMod[kc].w - 0.32, -3.0);
                        else if (chip == 6) { dPos[kc] = 0; dMod[kc] = 0; dEn[kc] = 0; }
                    }
                }
                if (chip == 7) sel = -1;
                handle = H_NONE;
            }
            else if (chip >= 0)
            {
                if (chip == 0) seedOff += 1.0;                              // re-roll
                else if (chip == 1) motifD += 1.0;                          // next motif
                else if (chip == 2) doseD = max(doseD - 0.1, -1.0);         // calmer
                else if (chip == 3) doseD = min(doseD + 0.1, 1.0);          // deeper
                else if (chip == 4) addArmed = 1.0 - addArmed;              // add (arms the next click)
                else if (chip == 5) restart = 1.0;                          // restart the trip clock
                else if (chip == 6)
                {
                    seedOff = 0.0; doseD = 0.0; motifD = 0.0; addArmed = 0.0; hold = 0.0;
                    [unroll] for (int z2 = 0; z2 < TRIP_ANCH_MAX; z2++) { dPos[z2] = 0; dMod[z2] = 0; dEn[z2] = 0; }
                }
                else if (chip == 7) hold = 1.0 - hold;                      // hold / run
                handle = H_NONE;
            }
            else if (press && inNet)
            {
                handle = H_NONE;
                if (addArmed > 0.5 && onSurf)
                {
                    // the first slot that is not running takes the new anchor, here
                    int slotNew = -1;
                    [unroll] for (int ka = 0; ka < TRIP_ANCH_MAX; ka++)
                    {
                        bool onNow = (dEn[ka] == 1.0) ? true : ((dEn[ka] == 2.0) ? false : gOn[ka]);
                        if (slotNew < 0 && !onNow) slotNew = ka;
                    }
                    [unroll] for (int kb = 0; kb < TRIP_ANCH_MAX; kb++)
                    {
                        if (kb == slotNew)
                        {
                            int host = (pObj >= 0) ? TH_OBJ0 + pObj : pHost;
                            float2 sc = (pHost == TH_FLOOR || pHost == TH_CEIL) ? pW.xz : float2(brWallAlongX(pHost - TH_WALL0) ? pW.x : pW.z, pW.y);
                            dPos[kb] = float4((float)host, sc, 1.0);
                            dMod[kb] = float4((float)((host >= TH_OBJ0) ? TK_BREATHE : TK_BLOOM), 0.0, 0.0, 0.0);
                            dEn[kb] = 1.0;
                            sel = kb;
                        }
                    }
                    addArmed = 0.0;
                }
                else
                {
                    // pick: the nearest running anchor's centre (move), or its ring (radius)
                    int hit = -1; bool ring = false; float best = TRIP_GRAB * L.s;
                    [unroll] for (int kp = 0; kp < TRIP_ANCH_MAX; kp++)
                    {
                        bool onNow = (dEn[kp] == 1.0) ? true : ((dEn[kp] == 2.0) ? false : gOn[kp]);
                        BRAnchor A = tripAnchor(kp);       // last cook's published anchor: what the canvas drew
                        if (onNow && A.on)
                        {
                            tPickTest(L, px, tAnchorPx(L, A), A.radius * L.scale, kp, best, hit, ring);
                        }
                    }
                    sel = hit;
                    if (hit >= 0) handle = ring ? H_RADIUS : H_MOVE;
                }
            }
            else if (release || dragEnd)
            {
                handle = H_NONE;
            }
            else if (dragMove && handle == H_MOVE && onSurf)
            {
                [unroll] for (int km = 0; km < TRIP_ANCH_MAX; km++)
                {
                    if (km == sel)
                    {
                        // dropped on a piece of furniture, the anchor becomes that piece's
                        int host = (pObj >= 0) ? TH_OBJ0 + pObj : pHost;
                        float2 sc = (pHost == TH_FLOOR || pHost == TH_CEIL) ? pW.xz : float2(brWallAlongX(pHost - TH_WALL0) ? pW.x : pW.z, pW.y);
                        dPos[km] = float4((float)host, sc, 1.0);
                        int kindNow = (dMod[km].x > 0.5) ? (int)dMod[km].x : gKind[km];
                        if (!kindFits(kindNow, host)) dMod[km].x = (float)nextKind(kindNow, host);
                    }
                }
            }
            else if (dragMove && handle == H_RADIUS)
            {
                [unroll] for (int kr = 0; kr < TRIP_ANCH_MAX; kr++)
                {
                    if (kr == sel)
                    {
                        BRAnchor A = tripAnchor(kr);
                        float want = clamp(length(px - tAnchorPx(L, A)) / L.scale, 0.15, 3.0);
                        dMod[kr].z = clamp(log2(want / max(gRad[kr], 0.05)), -3.0, 3.0);
                    }
                }
            }
        }
    }

    // ---- the trip clock and the dose envelope
    BRRec hd = Trip[TRIP_HEADER];
    float tPrev = (abs(hd.head.x - ROLE_TRIP) < 0.5) ? sane(hd.meta.x) : 0.0;
    float dt = clamp(_DeltaTime, 0.0, 0.1);
    // a dose past 1 is OVERDRIVE (br_trip.hlsli): the full trip, pushed. Its clock runs faster as
    // well -- integrated here, so pushing never jumps a phase -- and every channel grows from the push.
    float doseRaw = clamp(dose + doseD, 0.0, 3.0);
    float over = max(doseRaw - 1.0, 0.0);
    float tt = (restart > 0.5) ? 0.0 : tPrev + dt * tempo * (1.0 - saturate(hold)) * (1.0 + 0.6 * over);
    if (tt > 86400.0) tt = 0.0;
    float env = tripEnvelope(arc, tt);
    float doseEff = saturate(doseRaw) * env;
    float push = over * env;
    float motifEff = (float)(((int)round(motif + motifD) % 4 + 4) % 4);

    // ---- resolve and publish the anchors
    float worstL = 1.0;
    float4 counts = 0;
    float flows = 0.0;
    [unroll] for (int k3 = 0; k3 < TRIP_ANCH_MAX; k3++)
    {
        bool on = (dEn[k3] == 1.0) ? true : ((dEn[k3] == 2.0) ? false : gOn[k3]);
        int host = (dPos[k3].w > 0.5) ? (int)dPos[k3].x : gHost[k3];
        int kind = (dMod[k3].x > 0.5) ? (int)dMod[k3].x : gKind[k3];
        if (!kindFits(kind, host)) kind = nextKind(kind, host);
        float3 c = gC[k3];
        if (dPos[k3].w > 0.5)
        {
            if (host == TH_FLOOR) c = float3(dPos[k3].y, 0.0, dPos[k3].z);
            else if (host == TH_CEIL) c = float3(dPos[k3].y, R.H, dPos[k3].z);
            else if (host >= TH_WALL0 && host < TH_WALL0 + 4)
            {
                float2 p2 = brWallPoint(R, host - TH_WALL0, dPos[k3].y, 0.0);
                c = float3(p2.x, dPos[k3].z, p2.y);
            }
            else if (host >= TH_OBJ0 && haveFurn)
            {
                BRRec f = fu((uint)clamp(host - TH_OBJ0, 0, FURN_MAX - 1));
                c = float3(f.dims.x, f.dims.w + f.look.y * 0.5, f.dims.y);
            }
        }
        float rad = clamp(gRad[k3] * exp2(dMod[k3].z), 0.15, 3.0);
        float str = saturate(gStr[k3] * exp2(dMod[k3].y));
        float rate = clamp(gRate[k3] * exp2(dMod[k3].w), 0.01, 1.0);
        float phase = brHash01((uint)(k3 * 7717 + 31 + v * 13)) * 6.2831853;
        float seed = brHash01((uint)(k3 * 3301 + 7 + v * 29));
        BRRec a;
        a.head = float4(ROLE_ANCHOR, kind, host, on ? 1 : 0);
        a.dims = float4(c, rad);
        a.look = float4(str, rate, phase, seed);
        a.meta = float4(hostNormal(host), k3);
        Trip[TRIP_ANCH0 + k3] = a;
        if (on)
        {
            if (kind == TK_BREATHE) counts.x += 1.0;
            else if (kind == TK_MELT) counts.y += 1.0;
            else if (kind == TK_SWIRL) counts.z += 1.0;
            else if (kind == TK_BLOOM) counts.w += 1.0;
            else flows += 1.0;
            // the stretch an object warp puts on the distance field (tripObjectWarp's bound)
            if (host >= TH_OBJ0)
            {
                float Lk = 1.0;
                float pa = (1.0 + 1.6 * push) * saturate(furniture);
                if (kind == TK_MELT) Lk = 1.0 + 0.07 * str * doseEff * pa * 1.5 * 6.0;
                else if (kind == TK_SWIRL) Lk = 1.0 + 0.55 * str * doseEff * pa * 0.9;
                else Lk = 1.0 + 0.035 * str * doseEff * pa;
                worstL = max(worstL, Lk);
            }
        }
        BRRec dr;
        bool any = dPos[k3].w > 0.5 || dMod[k3].x > 0.5 || abs(dMod[k3].y) > 1e-4 || abs(dMod[k3].z) > 1e-4 || abs(dMod[k3].w) > 1e-4 || dEn[k3] > 0.5;
        dr.head = float4(ROLE_DELTA, k3, any ? 1 : 0, 0);
        dr.dims = dPos[k3];
        dr.look = dMod[k3];
        dr.meta = float4(dEn[k3], 0, 0, 0);
        Trip[TRIP_DELTA0 + k3] = dr;
    }

    BRRec h;
    h.head = float4(ROLE_TRIP, PLAN_VERSION, TRIP_ANCH_MAX, (float)v);
    h.dims = float4(doseEff, breathe, drift, melt);
    h.look = float4(geometry, colour, push, motifEff);    // z: overdrive (the dose past 1)
    h.meta = float4(tt, env, worstL, tempo * (1.0 - saturate(hold)));
    Trip[TRIP_HEADER] = h;
    // the extra globals: the swim's spatial scale, and two INTEGRATED clocks -- how far things
    // have travelled (drift) and turned (geometry). Anything that travels or turns reads these, so
    // moving a slider changes its speed and never jumps where it has got to.
    BRRec hxPrev = Trip[TRIP_EXTRA];
    bool hxOk = abs(hxPrev.head.x - ROLE_TRIP_X) < 0.5 && restart < 0.5;
    float stepT = dt * tempo * (1.0 - saturate(hold)) * (1.0 + 0.6 * over);
    float ampK = 1.0 + 1.6 * push;
    float flowT = (hxOk ? sane(hxPrev.dims.y) : 0.0) + stepT * saturate(drift) * doseEff * ampK;
    float bloomT = (hxOk ? sane(hxPrev.dims.z) : 0.0) + stepT * saturate(geometry) * doseEff * ampK;
    if (abs(flowT) > 1e5) flowT = 0.0;
    if (abs(bloomT) > 1e5) bloomT = 0.0;
    BRRec hx;
    hx.head = float4(ROLE_TRIP_X, 0, 0, 0);
    hx.dims = float4(clamp(swim_scale, 0.1, 2.0), flowT, bloomT, saturate(furniture));
    hx.look = 0; hx.meta = 0;
    Trip[TRIP_EXTRA] = hx;

    BRRec dg;
    dg.head = float4(ROLE_TRIP_ED, 2, 0, 0);
    dg.dims = counts;
    dg.look = float4(flows, worstL > 1.6 ? 1.0 : 0.0, addArmed, hold);
    dg.meta = float4(saturate(dose + doseD), 0, 0, 0);
    Trip[TRIP_DIAG] = dg;

    BRRec g2;
    g2.head = float4(ROLE_DELTA, 99, (abs(seedOff) + abs(doseD) + abs(motifD) + addArmed + hold > 0.0) ? 1 : 0, 0);
    g2.dims = float4(seedOff, doseD, motifD, addArmed);
    g2.look = float4(hold, 0, 0, 0);
    g2.meta = 0;
    Trip[GLOBAL_DELTA] = g2;

    ed.head = float4(ROLE_TRIP_ED, sel, 0, PLAN_VERSION);
    ed.dims = float4(handle, 0, 0, 0);
    ed.look = probe;
    ed.meta = float4(asfloat(newLast), handled, res);
    Trip[TRIP_EDITOR] = ed;
}
