// BR_Light / light.hlsl -- the lighting authority. One thread, once per cook.
//
// Owns the SUN (from time of day, date, latitude and the building's compass bearing), every LAMP
// the furniture authority placed (on/off, dimmer, colour temperature) and the FIRE in the grate.
// Positions are never re-decided here: lamps are found in BR_Furnish's records by their slot role,
// the fireplace in BR_Shell's openings.
//
// Edits are deltas over the parameters: dragging the sun along its path offsets the time of day,
// dragging a lamp's light-pool ring scales its power, chips switch lamps and warm or cool them.
#include "../_shared/br_records.hlsli"
#include "../_shared/br_furn_defs.hlsli"
#include "../_shared/br_light_defs.hlsli"
#include "light_layout.hlsli"

RWStructuredBuffer<BRRec> Light : register(u0);

#define PLAN_VERSION 1.0
#define NROLES 6            // five lamp roles + the fire

static const int ROLE_SLOT[5] = { 7, 8, 9, 10, 27 };     // BR_Furnish: lamp A, lamp B, floor lamp, pendant, lamp C

float sane(float v) { return (abs(v) < 1e5) ? v : 0.0; }

BRRec sh(uint i) { BRRec r; r.head = _Data0[i].head; r.dims = _Data0[i].dims; r.look = _Data0[i].look; r.meta = _Data0[i].meta; return r; }
BRRec fu(uint i) { BRRec r; r.head = _Data1[i].head; r.dims = _Data1[i].dims; r.look = _Data1[i].look; r.meta = _Data1[i].meta; return r; }

float basePower(int kind) { return (kind == FK_FLOORLAMP) ? 0.9 : (kind == FK_PENDANT) ? 0.7 : 0.5; }

// the irradiance a lamp lays on the floor at horizontal distance r (straight down is open); the
// radius at which it falls to E is light_layout's lRingRadius
float floorE(float P, float h, float r) { return P * h / pow(max(r * r + h * h, 1e-4), 1.5); }

[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    float2 res = (_Resolution.x >= 64.0) ? _Resolution.xy : float2(1280.0, 900.0);
    bool haveShell = _Data0_Count >= 13u && abs(_Data0[0].head.x - ROLE_ROOM) < 0.5;
    BRRoom R = brDefaultRoom();
    if (haveShell) R = brRoomFromRec(sh(0));
    bool haveFurn = _Data1_Count >= 30u;

    // ---- persistent state
    BRRec ed = Light[LIGHT_EDITOR];
    bool fresh = !(abs(ed.head.x - ROLE_LIGHT_ED) < 0.5) || abs(sane(ed.head.w) - PLAN_VERSION) > 0.01;
    if (fresh)
    {
        BRRec z; z.head = float4(ROLE_DELTA, 0, 0, 0); z.dims = 0; z.look = 0; z.meta = 0;
        [loop] for (int i = LIGHT_DELTA0; i < LIGHT_RECORDS; i++) Light[i] = z;
        ed.head = float4(ROLE_LIGHT_ED, -1, 0, PLAN_VERSION); ed.dims = 0; ed.look = 0; ed.meta = 0;
    }
    BRRec dT = Light[LIGHT_DELTA0];
    float timeDelta = sane(dT.dims.x);
    float4 rd[NROLES];        // per role: on override (0 none, 1 on, 2 off), power log2, kelvin delta, edited
    [unroll] for (int k = 0; k < NROLES; k++)
    {
        BRRec r = Light[LIGHT_DELTA0 + 1 + k];
        rd[k] = float4(clamp(round(sane(r.dims.x)), 0.0, 2.0), clamp(sane(r.dims.y), -6.0, 6.0), clamp(sane(r.dims.z), -3000.0, 3000.0), 0);
    }
    int sel = (int)round(sane(ed.head.y));
    if (sel < -1 || sel >= NROLES) sel = -1;
    int handle = (int)round(sane(ed.dims.x));
    int dragActive = (int)round(sane(ed.dims.y));
    uint lastSeq = asuint(ed.meta.x);
    float handled = sane(ed.meta.y);
    float4 probe = ed.look;          // the last press: canvas px, rack row, switch hit (diagnostic)

    LLayout L = lLayout(res, R);

    // ---- the lamps the furniture placed: bulb position, kind, height of the bulb over the floor
    float3 bulb[NROLES];
    int kindOf[NROLES];
    bool exists[NROLES];
    [unroll] for (int i2 = 0; i2 < NROLES; i2++) { bulb[i2] = 0; kindOf[i2] = 0; exists[i2] = false; }
    if (haveFurn)
    {
        [unroll] for (int i3 = 0; i3 < 5; i3++)
        {
            BRRec f = fu((uint)ROLE_SLOT[i3]);
            int kind = (int)round(f.head.y), v = (int)round(f.head.z);
            int flags = (int)round(f.meta.z);
            if (!fkIsLamp(kind) || (flags & FF_HIDDEN) != 0) continue;
            float yaw = f.dims.z;
            float3 bl = fkBulbLocal(kind, v, f.look.xyz);
            float2 fw = float2(sin(yaw), cos(yaw)), rt = float2(cos(yaw), -sin(yaw));
            bulb[i3] = float3(f.dims.x + rt.x * bl.x + fw.x * bl.z, f.dims.w + bl.y, f.dims.y + rt.y * bl.x + fw.y * bl.z);
            kindOf[i3] = kind;
            exists[i3] = true;
        }
    }
    // the fire sits in the first fireplace
    [loop] for (int oi = 0; oi < SHELL_OPEN_MAX; oi++)
    {
        if (!haveShell) break;
        BROpening o = brOpeningFromRec(sh(5 + (uint)oi));
        if (!o.active || o.kind != OPEN_FIREPLACE) continue;
        float2 c = brWallPoint(R, o.wall, o.a, o.depth - 0.20);
        bulb[5] = float3(c.x, 0.26, c.y);
        exists[5] = true;
        break;
    }

    // ---- events, each consumed once by sequence
    uint n = _ViewportEventCount;
    uint ringMax = 0u;
    [loop] for (uint ri = 0u; ri < n; ri++) ringMax = max(ringMax, _ViewportEvents[ri].sequence);
    if (n > 0u && ringMax < lastSeq) lastSeq = 0u;
    uint newLast = lastSeq;
    float2 sr = brSunriseSunset((float)day_of_year, latitude);
    // ONE exit per event: no `continue` after a store. FXC dropped a store made before a mid-body
    // `continue` in this loop (the rack switch's hit was seen, its toggle never reached the
    // record), so every verb is one branch of a single if/else chain, and every rd write uses a
    // static index.
    [loop] for (uint ei = 0u; ei < n; ei++)
    {
        ViewportEvent ev = _ViewportEvents[ei];
        bool isFresh = ev.sequence > lastSeq || (lastSeq - ev.sequence) > (1u << 20);
        if (isFresh)
        {
            newLast = (ev.sequence > lastSeq) ? max(newLast, ev.sequence) : ev.sequence;
            handled += 1.0;
            float2 px = ev.position * res;
            float tNow = clamp(time_of_day + timeDelta, 0.0, 24.0);
            bool press = ev.type == 2u && ev.code == 0u && ev.phase == 1u;
            bool release = ev.type == 2u && ev.code == 0u && ev.phase == 3u;
            bool dragMove = ev.type == 5u && ev.code == 3u && (ev.phase == 6u || ev.phase == 7u);
            bool dragEnd = ev.type == 5u && ev.code == 3u && (ev.phase == 7u || ev.phase == 8u);
            int chip = press ? lChipAt(L, px) : -1;
            bool onSw = false;
            int row = (press && chip < 0) ? lRowAt(L, px, onSw) : -1;
            bool sunTo = false;
            if (press) probe = float4(px, (float)row, onSw ? 1.0 : 0.0);

            if (chip >= 0 && sel >= 0)
            {
                // chips for the selected light: on/off, warmer, cooler, reset
                [unroll] for (int kc = 0; kc < NROLES; kc++)
                {
                    if (kc == sel)
                    {
                        bool onNow = (rd[kc].x == 1.0) ? true : ((rd[kc].x == 2.0) ? false : ((kc == 5) ? fire != 0 : lamps_on != 0));
                        if (chip == 0) rd[kc].x = onNow ? 2.0 : 1.0;
                        else if (chip == 1) rd[kc].z -= 300.0;
                        else if (chip == 2) rd[kc].z += 300.0;
                        else rd[kc] = 0;
                    }
                }
            }
            else if (chip >= 0)
            {
                // golden hour, blue hour, midday, reset everything
                float2 sg = brSunriseSunset((float)day_of_year, latitude);
                float target = tNow;
                if (chip == 0) target = sg.y - 0.75;
                else if (chip == 1) target = sg.y + 0.35;
                else if (chip == 2) target = 13.0;
                if (chip < 3) timeDelta = target - time_of_day;
                else { timeDelta = 0.0; [unroll] for (int z2 = 0; z2 < NROLES; z2++) rd[z2] = 0; }
            }
            else if (row >= 0)
            {
                // the rack: a row selects its light, its switch turns it on or off
                [unroll] for (int kk = 0; kk < NROLES; kk++)
                {
                    if (kk == row && exists[kk])
                    {
                        if (onSw)
                        {
                            bool onNow = (rd[kk].x == 1.0) ? true : ((rd[kk].x == 2.0) ? false : ((kk == 5) ? fire != 0 : lamps_on != 0));
                            rd[kk].x = onNow ? 2.0 : 1.0;
                        }
                        sel = kk;
                    }
                }
                handle = H_NONE; dragActive = 0;
            }
            else if (press)
            {
                handle = H_NONE; dragActive = 0;
                if (lInRect(px, L.chartBody, 0.0))
                {
                    handle = H_SUN; sel = -1; sunTo = true;       // grab the sun (or jump it here)
                }
                else if (lInRect(px, L.dayBody, 0.0))
                {
                    handle = H_DAY; sel = -1;
                    timeDelta = clamp(lDayH(L, px.x), 0.0, 24.0) - time_of_day;
                }
                else if (lInRect(px, L.planBody, 0.0))
                {
                    // a lamp dot selects, its middle ring drags its power (the layout's hover asks
                    // the same question of the published records)
                    float pw[NROLES];
                    [unroll] for (int k2 = 0; k2 < NROLES; k2++)
                        pw[k2] = ((k2 == 5) ? 1.2 * fire_power : basePower(kindOf[k2]) * lamp_master) * exp2(rd[k2].y);
                    bool ring = false;
                    int hit = lLightAt(L, px, bulb, pw, exists, ring);
                    sel = hit;
                    if (hit >= 0 && ring) handle = H_RING;
                }
                if (handle != H_NONE) dragActive = 1;
            }
            else if (release)
            {
                handle = H_NONE; dragActive = 0;
            }
            else if (dragMove)
            {
                if (handle == H_SUN) sunTo = true;
                else if (handle == H_DAY) timeDelta = clamp(lDayH(L, px.x), 0.0, 24.0) - time_of_day;
                else if (handle == H_RING)
                {
                    [unroll] for (int kr = 0; kr < NROLES; kr++)
                    {
                        if (kr == sel)
                        {
                            float r = length(lPlanWorld(L, px) - bulb[kr].xz);
                            float h = max(bulb[kr].y, 0.1);
                            float Pnew = LIGHT_RING_E * pow(r * r + h * h, 1.5) / h;
                            float Pbase = (kr == 5) ? 1.2 * fire_power : basePower(kindOf[kr]) * lamp_master;
                            rd[kr].y = clamp(log2(max(Pnew, 1e-4) / max(Pbase, 1e-4)), -6.0, 6.0);
                        }
                    }
                }
            }
            if (sunTo)
            {
                // the time on today's path whose sun is nearest the pointer
                timeDelta = lSunTimeAt(L, px, (float)day_of_year, latitude, sr, tNow) - time_of_day;
            }
            if (dragEnd) { handle = H_NONE; dragActive = 0; }
        }
    }

    // ---- resolve and publish
    float tod = clamp(time_of_day + timeDelta, 0.0, 24.0);
    float2 ea = brSolarPosition(tod, (float)day_of_year, latitude);
    float3 sd = brSunDir(ea.x, ea.y, compass);
    BRRec sun;
    sun.head = float4(ROLE_SUN, 1, 0, 0);
    sun.dims = float4(sd, sun_intensity);
    sun.look = float4(sky_gain, sun_softness, wind, trees);
    sun.meta = float4(tod, day_of_year, latitude, compass);
    Light[LIGHT_SUN] = sun;

    [unroll] for (int k3 = 0; k3 < NROLES; k3++)
    {
        float4 d = rd[k3];
        bool isFire = k3 == 5;
        bool onDef = isFire ? fire != 0 : lamps_on != 0;
        bool on = exists[k3] && ((d.x == 1.0) ? true : ((d.x == 2.0) ? false : onDef));
        float K = isFire ? 1850.0 + d.z : lamp_kelvin + d.z;
        float P = (isFire ? 1.2 * fire_power : basePower(kindOf[k3]) * lamp_master) * exp2(d.y);
        BRRec r;
        r.head = float4(ROLE_LAMP, isFire ? LIGHT_FIRE_SLOT : ROLE_SLOT[min(k3, 4)], on ? 1 : 0, kindOf[k3]);
        r.dims = float4(P, K, isFire ? fire_flicker : 0.0, exists[k3] ? 1.0 : 0.0);
        r.look = float4(brKelvin(K), 1.0);
        r.meta = float4(bulb[k3], 0);
        Light[isFire ? LIGHT_FIRE : LIGHT_LAMP0 + k3] = r;
        BRRec dr;
        bool any = d.x != 0.0 || abs(d.y) > 1e-4 || abs(d.z) > 0.5;
        dr.head = float4(ROLE_DELTA, k3, any ? 1 : 0, 0);
        dr.dims = float4(d.x, d.y, d.z, 0);
        dr.look = 0; dr.meta = 0;
        Light[LIGHT_DELTA0 + 1 + k3] = dr;
    }
    // unused lamp records (the fire lives at LIGHT_FIRE, after them)
    [unroll] for (int k4 = 5; k4 < 8; k4++) { BRRec z; z.head = 0; z.dims = 0; z.look = 0; z.meta = 0; Light[LIGHT_LAMP0 + k4] = z; }

    // the day: sunrise, sunset, and the golden hours (sun under 6 degrees)
    float golden0 = sr.x, golden1 = sr.y;
    [loop] for (int gi = 0; gi < 96; gi++)
    {
        float t = lerp(sr.x, 12.0, (float)gi / 96.0);
        if (degrees(brSolarPosition(t, (float)day_of_year, latitude).x) < 6.0) golden0 = t;
        float t2 = lerp(sr.y, 12.0, (float)gi / 96.0);
        if (degrees(brSolarPosition(t2, (float)day_of_year, latitude).x) < 6.0) golden1 = t2;
    }
    BRRec rules;
    rules.head = float4(ROLE_LIGHT_ED, 1, 0, 0);
    rules.dims = float4(sr.x, sr.y, golden0, golden1);
    rules.look = float4(degrees(ea.x), degrees(ea.y), tod, 0);
    rules.meta = 0;
    Light[LIGHT_RULES] = rules;

    dT.head = float4(ROLE_DELTA, 99, abs(timeDelta) > 1e-4 ? 1 : 0, 0);
    dT.dims = float4(timeDelta, 0, 0, 0); dT.look = 0; dT.meta = 0;
    Light[LIGHT_DELTA0] = dT;

    ed.head = float4(ROLE_LIGHT_ED, sel, 0, PLAN_VERSION);
    ed.dims = float4(handle, dragActive, 0, 0);
    ed.look = probe;
    ed.meta = float4(asfloat(newLast), handled, res);
    Light[LIGHT_EDITOR] = ed;
}
