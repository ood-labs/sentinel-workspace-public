// BR_Render / prep.hlsl -- normalise every upstream authority into the renderer's scene buffer.
//
// Inputs (data slots): 0 Shell, 1 Finish, 2 Furnish, 3 Light, 4 Trip, 5 Rug. Any of them may be
// unlinked; this pass substitutes the house defaults so the renderer is never empty. It also
// keeps the frame state TAA needs: frame index, sub-pixel jitter, the previous view-projection,
// and how long the camera has held still.
// Which optional authorities are wired in (flip as each one is added to data_inputs).
#define HAVE_FURNISH 1
#define HAVE_LIGHT 1
#define HAVE_TRIP 1
#define HAVE_RUG 1
#include "../_shared/br_records.hlsli"
#include "../_shared/br_shade.hlsli"
#include "../_shared/br_sky.hlsli"
#include "../_shared/br_sdf.hlsli"
#include "../_shared/br_furniture.hlsli"
#include "../_shared/br_light_defs.hlsli"

#define SC_ROOM      0
#define SC_OPEN0     1
#define SC_SUN       9
#define SC_FRAME     10
#define SC_VP_PREV   11
#define SC_VP_CUR    15
#define SC_COUNTS    19
#define SC_LAMP0     20
#define SC_TRIP      32
#define SC_ANCH0     33
#define SC_RUG       48
#define SC_IVP_CUR   56
#define SC_CAM       60
#define SC_OBJ0      64
#define SC_OBJ_MAX   64
#define SC_OWARP0    128
#define SC_MAT0      192
#define SC_RECORDS   224

RWStructuredBuffer<BRRec> Scene : register(u0);
// the trip records are read back from where this pass copies them (object warps need the anchors)
#define TRIP_REC(i) Scene[SC_TRIP + (i)]
#define TRIP_EXTRA_REC Scene[SC_TRIP + 13]
#include "../_shared/br_trip.hlsli"


// The host generates its own struct type per data input; copy field by field.
BRRec d0(uint i) { BRRec r; r.head = _Data0[i].head; r.dims = _Data0[i].dims; r.look = _Data0[i].look; r.meta = _Data0[i].meta; return r; }
BRRec d1(uint i) { BRRec r; r.head = _Data1[i].head; r.dims = _Data1[i].dims; r.look = _Data1[i].look; r.meta = _Data1[i].meta; return r; }
#if HAVE_FURNISH
BRRec d2(uint i) { BRRec r; r.head = _Data2[i].head; r.dims = _Data2[i].dims; r.look = _Data2[i].look; r.meta = _Data2[i].meta; return r; }
#endif
#if HAVE_LIGHT
BRRec d3(uint i) { BRRec r; r.head = _Data3[i].head; r.dims = _Data3[i].dims; r.look = _Data3[i].look; r.meta = _Data3[i].meta; return r; }
#endif
#if HAVE_TRIP
BRRec d4(uint i) { BRRec r; r.head = _Data4[i].head; r.dims = _Data4[i].dims; r.look = _Data4[i].look; r.meta = _Data4[i].meta; return r; }
#endif
#if HAVE_RUG
BRRec d5(uint i) { BRRec r; r.head = _Data5[i].head; r.dims = _Data5[i].dims; r.look = _Data5[i].look; r.meta = _Data5[i].meta; return r; }
#endif

BRRec rec(float4 h, float4 d, float4 l, float4 m) { BRRec r; r.head = h; r.dims = d; r.look = l; r.meta = m; return r; }
BRRec zeroRec() { return rec(0, 0, 0, 0); }
float sane(float v) { return (abs(v) < 1e6) ? v : 0.0; }

// The same procedural room BR_Shell builds with its defaults (used only while it is unlinked).
BRRec defaultOpening(int i)
{
    // head (role, kind, wall, slot)  dims (a, w, h, sill)  look (cols, rows, depth, curtains)  meta (radiator, edited, active, alarms)
    if (i == 0) return rec(float4(ROLE_OPEN, OPEN_DOUBLEHUNG, WALL_W, 0), float4(-1.15, 1.05, 1.82, 0.55), float4(2, 1, 0, 1), float4(1, 0, 1, 0));
    if (i == 1) return rec(float4(ROLE_OPEN, OPEN_DOUBLEHUNG, WALL_W, 1), float4(1.15, 1.05, 1.82, 0.55), float4(2, 1, 0, 1), float4(1, 0, 1, 0));
    if (i == 3) return rec(float4(ROLE_OPEN, OPEN_FIREPLACE, WALL_N, 3), float4(0.0, 1.80, 1.24, 0.0), float4(0.86, 0.80, 0.36, 0), float4(0, 0, 1, 0));
    if (i == 4) return rec(float4(ROLE_OPEN, OPEN_DOOR, WALL_E, 4), float4(1.755, 0.85, 2.10, 0.0), float4(2, 3, 0, 0), float4(0, 0, 1, 0));
    return rec(float4(ROLE_OPEN, OPEN_NONE, WALL_W, i), float4(0, 1, 1.8, 0.6), float4(1, 1, 0, 0), float4(0, 0, 0, 0));
}

float halton(uint i, uint b)
{
    float f = 1.0, r = 0.0;
    uint n = i;
    [loop] for (int k = 0; k < 8 && n > 0u; k++) { f /= (float)b; r += f * (float)(n % b); n /= b; }
    return r;
}

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    // ---- frame state (read previous BEFORE anything is overwritten)
    BRRec fr = Scene[SC_FRAME];
    bool init = !(abs(fr.head.x - 77.0) < 0.5);
    float frame = init ? 0.0 : sane(fr.dims.x) + 1.0;
    if (frame > 1.0e6) frame = 0.0;
    float4 oldCur[4];
    [unroll] for (int r = 0; r < 4; r++) oldCur[r] = init ? float4(0, 0, 0, 0) : Scene[SC_VP_CUR + r].dims;
    float motion = 0.0;
    [unroll] for (int r2 = 0; r2 < 4; r2++)
    {
        float4 d = _ViewProjMatrix[r2] - oldCur[r2];
        motion += abs(d.x) + abs(d.y) + abs(d.z) + abs(d.w);
    }
    float staticFrames = (motion < 1e-5 && !init) ? sane(fr.dims.w) + 1.0 : 0.0;
    if (reset_accum != 0) staticFrames = 0.0;
    // switching the review view restarts accumulation, so no diagnostic lingers in history
    if (!init && abs(fr.meta.x - (float)view) > 0.5) staticFrames = 0.0;
    uint fi = (uint)frame;
    float2 jit = (taa != 0) ? float2(halton((fi % 16u) + 1u, 2u), halton((fi % 16u) + 1u, 3u)) - 0.5 : float2(0, 0);
    float dt = clamp(_DeltaTime, 0.0, 0.1);
    float t = init ? 0.0 : sane(fr.look.w) + dt;
    if (t > 1.0e5) t = 0.0;

    [unroll] for (int r3 = 0; r3 < 4; r3++)
    {
        Scene[SC_VP_PREV + r3] = rec(float4(76, r3, 0, 0), init ? _ViewProjMatrix[r3] : oldCur[r3], 0, 0);
        Scene[SC_VP_CUR + r3] = rec(float4(76, r3, 0, 0), _ViewProjMatrix[r3], 0, 0);
    }
    // the inverse view-projection and the eye, for a consumer that rebuilds world positions from
    // depth (BR_Lens falls back on them when an image's own camera header cannot be read)
    [unroll] for (int r4 = 0; r4 < 4; r4++) Scene[SC_IVP_CUR + r4] = rec(float4(75, r4, 0, 0), _InvViewProjMatrix[r4], 0, 0);
    Scene[SC_CAM] = rec(float4(74, 0, 0, 0), float4(_CameraPos, 0.0), 0, 0);
    // meta.y: the app clock this cook ran at, so a reader can tell which cook's scene it was handed
    Scene[SC_FRAME] = rec(float4(77, 0, 0, 0), float4(frame, jit, staticFrames), float4(motion, 0.0, dt, t), float4((float)view, _Time, 0, 0));

    // ---- room + openings
    bool haveShell = _Data0_Count >= 13u && abs(_Data0[0].head.x - ROLE_ROOM) < 0.5;
    if (haveShell)
    {
        Scene[SC_ROOM] = d0(0);
        [unroll] for (int i = 0; i < 8; i++) Scene[SC_OPEN0 + i] = d0(5 + i);
    }
    else
    {
        BRRoom R = brDefaultRoom();
        Scene[SC_ROOM] = rec(float4(ROLE_ROOM, 0, R.floorPattern, R.flags), float4(R.x0, R.x1, R.z0, R.z1),
                             float4(R.H, R.T, R.baseH, R.crown), float4(R.railH, R.plankW, 0, 0));
        [unroll] for (int i2 = 0; i2 < 8; i2++) Scene[SC_OPEN0 + i2] = defaultOpening(i2);
    }

    // ---- materials
    bool haveFinish = _Data1_Count >= (uint)MAT_SLOTS && abs(_Data1[0].head.x - ROLE_MAT) < 0.5;
    [loop] for (int m = 0; m < MAT_SLOTS; m++)
    {
        if (haveFinish) Scene[SC_MAT0 + m] = d1(m);
        else Scene[SC_MAT0 + m] = brMatToRec(brDefaultMat(m));
    }

    // ---- sun + sky (BR_Light is the authority; these parameters are only its stand-in)
#if HAVE_LIGHT
    bool haveLight = _Data3_Count >= 10u && abs(_Data3[0].head.x - ROLE_SUN) < 0.5;
#else
    bool haveLight = false;
#endif
    float3 sunDir;
    float sunI, skyI, soft, wind, canopy;
#if HAVE_LIGHT
    if (haveLight)
    {
        BRRec L = d3(0);
        sunDir = normalize(L.dims.xyz);
        sunI = L.dims.w; skyI = L.look.x; soft = L.look.y; wind = L.look.z; canopy = L.look.w;
    }
    else
#endif
    {
        float az = radians(sun_azimuth), el = radians(sun_elevation);
        sunDir = normalize(float3(sin(az) * cos(el), sin(el), cos(az) * cos(el)));
        sunI = sun_intensity; skyI = sky_intensity; soft = sun_softness; wind = tree_wind; canopy = tree_density;
    }
    float3 sunRad = brSunColour(sunDir) * sunI;
    Scene[SC_SUN] = rec(float4(ROLE_SUN, haveLight ? 1 : 0, 0, 0), float4(sunDir, sunI), float4(sunRad, soft), float4(skyI, wind, canopy, t));

    // ---- furniture: every visible piece becomes a render object, compacted, with a world
    // bounding sphere so the scene field can skip what is far away; lamps become light records
    int lamps = 0;
    [loop] for (int l = 0; l < 12; l++) Scene[SC_LAMP0 + l] = zeroRec();
    Scene[SC_TRIP] = zeroRec();
    [loop] for (int a = 0; a < 15; a++) Scene[SC_ANCH0 + a] = zeroRec();
    [loop] for (int g = 0; g < 8; g++) Scene[SC_RUG + g] = zeroRec();
    // ---- the trip (BR_Trip): header + 12 anchors, copied as published, BEFORE the furniture so
    // each piece's warp can be worked out from the anchors once per frame
#if HAVE_TRIP
    bool haveTrip = _Data4_Count >= 13u && abs(_Data4[0].head.x - ROLE_TRIP) < 0.5;
    if (haveTrip)
    {
        [loop] for (int ti = 0; ti < 13; ti++) Scene[SC_TRIP + ti] = d4((uint)ti);
        // the extra globals (swim scale) ride in the 13th slot after the anchors
        if (_Data4_Count > (uint)TRIP_EXTRA) Scene[SC_TRIP + 13] = d4((uint)TRIP_EXTRA);
    }
#else
    bool haveTrip = false;
#endif
    // ---- the rug's design (BR_Rug): header + 7 colours, copied as published
#if HAVE_RUG
    if (_Data5_Count >= 8u && abs(_Data5[0].head.x - ROLE_RUG) < 0.5)
    {
        [loop] for (int gi = 0; gi < 8; gi++) Scene[SC_RUG + gi] = d5((uint)gi);
    }
#endif
    BRTrip TT = tripHeader();
    // the trip moves the image even when the camera holds still (its clock runs while dose > 0);
    // a held trip (tempo 0) is a still and may accumulate like one
    float warpMotion = (TT.dose > 0.0 && TT.tempo > 0.0) ? TT.dose : 0.0;
    BRRec frNow = Scene[SC_FRAME];
    frNow.look.y = warpMotion;
    Scene[SC_FRAME] = frNow;
    int objs = 0;
    float roomH = Scene[SC_ROOM].look.x;
#if HAVE_FURNISH
    bool haveFurn = _Data2_Count >= 30u && abs(_Data2[0].head.x - ROLE_FURN) < 0.5;
    if (haveFurn)
    {
        [loop] for (int fi = 0; fi < 48; fi++)
        {
            BRRec r = d2((uint)fi);
            if (abs(r.head.x - ROLE_FURN) > 0.5) continue;
            int kind = (int)round(r.head.y), v = (int)round(r.head.z), slot = (int)round(r.head.w);
            int flags = (int)round(r.meta.z);
            if (kind <= FK_NONE || kind >= FK_KIND_COUNT || (flags & FF_HIDDEN) != 0) continue;
            float3 S = max(r.look.xyz, 0.01);
            float yaw = r.dims.z, y0 = r.dims.w;
            float2 fw = float2(sin(yaw), cos(yaw)), rt = float2(cos(yaw), -sin(yaw));
            float3 bl = fkBoundCentre(kind, v, S, roomH, y0);
            float br = fkBoundRadius(kind, v, S, roomH, y0);
            float3 bc = float3(r.dims.x + rt.x * bl.x + fw.x * bl.z, y0 + bl.y, r.dims.y + rt.y * bl.x + fw.y * bl.z);
            int mats = clamp((int)round(r.meta.x), 0, 31) + 32 * clamp((int)round(r.meta.y), 0, 31);
            // a lamp: BR_Light owns it by furniture slot (on/off, dimmer, colour temperature);
            // unlinked, the furniture's own LIT flag and a 2700 K bulb sized by kind stand in
            if (fkIsLamp(kind))
            {
                bool on = (flags & FF_LIT) != 0;
                float power = (kind == FK_FLOORLAMP) ? 0.9 : (kind == FK_PENDANT) ? 0.7 : 0.5;
                float3 lc = brKelvin(2700.0);
#if HAVE_LIGHT
                if (haveLight)
                {
                    [loop] for (int li = LIGHT_LAMP0; li < LIGHT_LAMP0 + LIGHT_LAMP_N; li++)
                    {
                        BRRec lr = d3((uint)li);
                        if (abs(lr.head.x - ROLE_LAMP) > 0.5 || (int)round(lr.head.y) != slot) continue;
                        on = lr.head.z > 0.5; power = max(sane(lr.dims.x), 0.0); lc = max(lr.look.rgb, 0.0);
                        break;
                    }
                }
#endif
                flags = on ? (flags | FF_LIT) : (flags & ~FF_LIT);
                if (on && power > 1e-4 && lamps < 11)
                {
                    float3 bLoc = fkBulbLocal(kind, v, S);
                    float3 bp = float3(r.dims.x + rt.x * bLoc.x + fw.x * bLoc.z, y0 + bLoc.y, r.dims.y + rt.y * bLoc.x + fw.y * bLoc.z);
                    Scene[SC_LAMP0 + lamps] = rec(float4(ROLE_LAMP, kind, objs, v), float4(bp, power), float4(lc, 1.0), float4(yaw, 0, 0, 0));
                    lamps++;
                }
            }
            // this piece's trip warp, worked out once per frame (furnMap only applies it). Lamps
            // hold still: the march sliced through their thin shades under a warp, and a lamp's
            // trip is the light it throws (BR_Lens draws rainbows off it)
            float sAmp = 0.0;
            float4 wp = float4(0.0, 0.11, 0.0, 0.0);
            if (!fkIsLamp(kind)) wp = tripObjectParams(slot, r.look.w, TT, sAmp);
            float reach = tripObjectReach(S, wp, sAmp);
            Scene[SC_OWARP0 + objs] = rec(wp, float4(sAmp, reach, fkRadialReach(kind, v, S), 0), 0, 0);
            Scene[SC_OBJ0 + objs] = rec(float4(kind, v, mats, slot + 64 * (flags & 15)), float4(r.dims.xy, yaw, y0), float4(S, r.look.w), float4(bc, br + reach));
            objs++;
            if (objs >= SC_OBJ_MAX) break;
        }
    }
#endif
    [loop] for (int o = objs; o < SC_OBJ_MAX; o++) { Scene[SC_OBJ0 + o] = zeroRec(); Scene[SC_OWARP0 + o] = zeroRec(); }

    // ---- the fire in the grate (BR_Light switches it and sets its power; the flame centre comes
    // from the renderer's own fireplace record, so it cannot drift from the firebox it burns in)
#if HAVE_LIGHT
    if (haveLight && lamps < 12)
    {
        BRRec fz = d3(LIGHT_FIRE);
        bool fireOn = abs(fz.head.x - ROLE_LAMP) < 0.5 && fz.head.z > 0.5 && sane(fz.dims.x) > 1e-4;
        int fo = -1;
        [loop] for (int oi = 0; oi < SHELL_OPEN_MAX; oi++)
        {
            BROpening op = brOpeningFromRec(Scene[SC_OPEN0 + oi]);
            if (op.active && op.kind == OPEN_FIREPLACE) { fo = oi; break; }
        }
        if (fireOn && fo >= 0)
        {
            BROpening op = brOpeningFromRec(Scene[SC_OPEN0 + fo]);
            BRRoom R = brRoomFromRec(Scene[SC_ROOM]);
            float2 c = brWallPoint(R, op.wall, op.a, op.depth - 0.20);
            float2 mn = brWallNormal(op.wall);
            float flick = saturate(sane(fz.dims.z));
            // a fire breathes: several incommensurate rates, so it never visibly repeats
            float fl = sin(t * 7.3) * 0.35 + sin(t * 13.1 + 1.7) * 0.25 + sin(t * 23.7 + 0.4) * 0.15 + sin(t * 3.1 + 2.2) * 0.25;
            float P = sane(fz.dims.x) * (1.0 + flick * 0.30 * fl);
            float3 pos = float3(c.x, op.sill + 0.24 + flick * 0.03 * sin(t * 6.1), c.y)
                       + float3(-mn.y, 0.0, mn.x) * flick * 0.025 * sin(t * 4.3 + 0.7);
            Scene[SC_LAMP0 + lamps] = rec(float4(ROLE_LAMP, LAMP_KIND_FIRE, fo, 0), float4(pos, P), float4(max(fz.look.rgb, 0.0), 1.0),
                                          float4(mn, flick, sane(fz.dims.x)));
            lamps++;
        }
    }
#endif
    // BR_Finish's selection, for the Scope view
    float finishSel = -1.0;
    if (haveFinish && _Data1_Count > (uint)FINISH_EDITOR && abs(_Data1[FINISH_EDITOR].head.x - ROLE_FINISH_ED) < 0.5)
        finishSel = clamp(round(_Data1[FINISH_EDITOR].dims.x), -1.0, (float)(MAT_SLOTS - 1));
    Scene[SC_COUNTS] = rec(float4(78, 0, 0, 0), float4(objs, lamps, haveTrip ? TRIP_ANCH_MAX : 0, 0), float4(haveShell ? 1 : 0, haveFinish ? 1 : 0, haveLight ? 1 : 0, haveTrip ? 1 : 0), float4(finishSel, 0, 0, 0));
}
