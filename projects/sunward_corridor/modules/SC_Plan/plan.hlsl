// SC_Plan / plan.hlsl — authors one loop of corridor into a durable record buffer.
//
// Single-threaded on purpose: the layout is sequential and the viewport event queue must be
// reduced in order. 24 records is nothing next to any render pass.
//
// PERIODICITY IS STRUCTURAL, NOT A CONSTRAINT. Bay stations are addressed modulo SC_BAYS by
// the Catmull-Rom in corridor.hlsli, so any per-station value — including a random draw or a
// hand edit — is automatically periodic. That is why the infinite flight can never develop a
// seam no matter what the user does to the plan.
//
// Regeneration is signature-driven. A structural parameter (or the R-key salt) changing the
// signature rebuilds the corridor; anything else preserves the buffer, so dragged stations
// survive across cooks, saves, presets and undo. Travel is deliberately OUTSIDE the signature:
// re-rolling the layout must not jog the flight.
#include "../_shared/corridor.hlsli"

RWStructuredBuffer<ScRec> Plan : register(u0);

// The plan buffer is persistent and only rebuilds when its signature changes. Parameters feed
// that signature — SHADER EDITS DO NOT. Bump this whenever the layout algorithm below changes
// or a recompile will silently keep serving the previously generated corridor.
// 1.1 — corridor section changed to portrait (SC_BASE_W/H in corridor.hlsli). Bay sizes are
// generated FROM those constants, so without this bump the persistent buffer would keep
// serving landscape apertures and the change would silently do nothing.
// 1.2 — MK_LENS added to the vocabulary and placed in the default cast. The mass records are
// generated from MASS_KIND, so without this bump the persistent buffer keeps serving the old
// kinds and the new one never appears.
#define PLAN_VERSION 1.2

// ---------------------------------------------------------------------------
// Base corridor, transcribed as smooth periodic functions of the station angle rather than a
// table. The reference corridor drifts and breathes rather than stepping, so the vocabulary
// that describes it is harmonic, and writing it this way means station 11 flows into station 0
// with no hand-checked wrap.
// ---------------------------------------------------------------------------
void baseBay(uint i, out float2 off, out float2 half_, out float roll, out float chk)
{
    float a = ((float)i / (float)SC_BAYS) * 6.2831853;
    off = float2(sin(a) * 0.46 + sin(2.0 * a + 1.10) * 0.17,
                 eye_height + cos(a + 0.60) * 0.20 + sin(3.0 * a) * 0.085);
    half_ = float2(SC_BASE_W * (1.0 + 0.20 * sin(2.0 * a + 0.40)),
                   SC_BASE_H * (1.0 + 0.15 * cos(3.0 * a - 0.90)));
    roll = 0.085 * sin(a + 2.00);
    chk  = 1.0 + 0.22 * sin(2.0 * a + 1.70);
}

// The organic cast, transcribed from where the reference actually puts things.
// (z along the loop, perimeter t), (radius, elongation), kind.
// t: 0 = right wall, 0.25 = ceiling, 0.5 = left wall, 0.75 = floor.
static const float2 MASS_ZT[10] = {
    float2( 5.60, 0.620), float2( 9.50, 0.760), float2(13.00, 0.045), float2(17.50, 0.545),
    float2(21.00, 0.805), float2( 2.00, 0.285), float2( 7.80, 0.020), float2(15.00, 0.720),
    float2(19.50, 0.225), float2(11.20, 0.480)
};
static const float2 MASS_RE[10] = {
    float2(0.80, 2.70), float2(0.46, 1.30), float2(0.40, 1.00), float2(0.52, 1.60),
    float2(0.34, 1.10), float2(0.30, 1.00), float2(0.36, 1.20), float2(0.44, 2.00),
    float2(0.28, 0.90), float2(0.33, 1.10)
};
// Two lenses in the default cast: one on the near left wall where the reference's grid is most
// obviously bent, one further down on the floor so the distortion recurs as you fly.
static const float MASS_KIND[10] = {
    MK_WAVE, MK_LENS, MK_DRUM, MK_SWELL, MK_KNUCKLE,
    MK_DRUM, MK_LENS, MK_WAVE, MK_SWELL, MK_KNUCKLE
};

// Stratified placement for the randomizer. A uniform draw along 24 units of corridor reliably
// leaves half the loop bare and piles three masses on one station. Giving each mass its own
// slice of the loop and jittering INSIDE it keeps a random seed reading as a corridor.
float2 stratifiedMass(uint i, float s, float rs)
{
    float slice = SC_LOOP_Z / (float)SC_MASSES;
    float z = ((float)i + 0.15 + 0.70 * sc_rnd(rs, 41.0)) * slice + sc_rnd(s, 77.0) * slice;
    // Perimeter is biased AWAY from the ceiling: the reference hangs its mass off the floor
    // and the lower walls, and a uniform draw around the perimeter loses that instantly.
    float t = sc_rnd(rs, 42.0);
    t = frac(0.48 + (t - 0.5) * 0.72);
    return float2(sc_wrapZ(z), t);
}

void buildBays(float s)
{
    uint want = (uint)clamp((float)bay_count, 0.0, (float)SC_BAYS);
    float v = saturate(variation);
    for (uint i = 0u; i < SC_BAYS; i++)
    {
        ScRec r = (ScRec)0;
        // A randomization stream kept separate from r.seed, so re-rolling ONE station with N
        // does not shift what every other station drew.
        float rs = s * 11.7 + (float)i * 29.3 + 101.0;

        float2 bo, bh; float br, bc;
        baseBay(i, bo, bh, br, bc);

        // Position goes free under variation. The aperture RHYTHM does not: the base curve
        // encodes a pinch/flare cadence, and a flat random draw per station turns a corridor
        // into a lumpy gut. Randomizing the magnitude around each station's own value keeps a
        // random corridor composed.
        float2 rndOff = float2((sc_rnd(rs, 3.0) - 0.5) * 1.30,
                               eye_height + (sc_rnd(rs, 4.0) - 0.5) * 0.62);
        float2 rndHalf = bh * float2(lerp(0.80, 1.28, sc_rnd(rs, 5.0)),
                                     lerp(0.82, 1.22, sc_rnd(rs, 6.0)));

        float2 off  = lerp(bo, rndOff, v) * bend;
        float2 half_ = float2(SC_BASE_W, SC_BASE_H)
                     + (lerp(bh, rndHalf, v) - float2(SC_BASE_W, SC_BASE_H)) * flare;
        float roll  = lerp(br, (sc_rnd(rs, 7.0) - 0.5) * 0.55, v) * bend;
        float chk   = lerp(bc, lerp(0.65, 1.55, sc_rnd(rs, 8.0)), v);

        r.pos    = off;
        r.size   = max(half_ * aperture, float2(0.30, 0.24));
        r.role   = ROLE_BAY;
        // Palette zoning: at variation 0 the whole corridor is the reference chord. As it
        // rises, stations start defecting to a neighbouring set, which reads as coloured
        // zones sliding past rather than as noise.
        r.kind   = (sc_rnd(rs, 9.0) < v * 0.55)
                     ? min(floor(sc_rnd(rs, 10.0) * (float)SC_PALSETS), (float)(SC_PALSETS - 1))
                     : (float)palette_set;
        r.seed   = s * 3.3 + (float)i * 17.0 + 1.0;
        r.tone   = saturate(accent * lerp(1.0, lerp(0.35, 1.85, sc_rnd(rs, 11.0)), v));
        r.grp    = roll;
        r.phase  = max(chk, 0.25);
        r.flags  = 0.0;
        r.active = (i < want) ? 1.0 : 0.0;
        Plan[SC_BAY_0 + i] = r;
    }
}

void buildMasses(float s)
{
    uint want = (uint)clamp((float)mass_count, 0.0, (float)SC_MASSES);
    float v = saturate(variation);
    for (uint i = 0u; i < SC_MASSES; i++)
    {
        ScRec r = (ScRec)0;
        float rs = s * 13.1 + (float)i * 37.7 + 211.0;

        float2 rndZT = stratifiedMass(i, s, rs);
        // Size hierarchy is preserved: the table already says one hero fold and a supporting
        // cast, and a flat random radius destroys that read. The magnitude randomizes around
        // each slot's own rank instead.
        float2 rndRE = MASS_RE[i] * float2(lerp(0.68, 1.42, sc_rnd(rs, 3.0)),
                                           lerp(0.70, 1.55, sc_rnd(rs, 4.0)));

        float2 zt = lerp(MASS_ZT[i], rndZT, v);
        float2 re = lerp(MASS_RE[i], rndRE, v);
        float kind = (sc_rnd(rs, 5.0) < v)
                       ? min(floor(sc_rnd(rs, 6.0) * (float)MK_KINDS), (float)(MK_KINDS - 1))
                       : MASS_KIND[i];

        r.pos    = float2(sc_wrapZ(zt.x), frac(zt.y + 1.0));
        r.size   = float2(max(re.x * mass_scale, 0.04), max(re.y, 0.35));
        r.role   = ROLE_MASS;
        r.kind   = kind;
        r.seed   = s * 7.1 + (float)i * 23.0 + 5.0;
        r.tone   = lerp(0.55, 1.0, sc_rnd(rs, 12.0));           // sheen
        r.grp    = lerp(0.55, 1.05, sc_rnd(rs, 13.0));          // squash into the wall
        r.phase  = lerp(0.14, 0.34, sc_rnd(rs, 14.0));          // fusion softness
        r.flags  = 0.0;
        r.active = (i < want) ? 1.0 : 0.0;
        Plan[SC_MASS_0 + i] = r;
    }
}

// The sun is rebuilt only on a signature change; its APPEARANCE-only fields are refreshed
// every cook further down so tuning the disc never wipes a dragged corridor.
void buildSky()
{
    ScRec r = (ScRec)0;
    r.pos    = float2(sun_x, sun_y);
    r.size   = float2(sun_radius, sun_radius * 0.175);
    r.role   = ROLE_SKY;
    r.kind   = (float)stripe_count;
    r.seed   = 19.0;
    r.tone   = horizon;
    r.grp    = 0.30;
    r.phase  = -0.60;
    r.flags  = 0.0;
    r.active = 1.0;
    Plan[SC_SKY] = r;
}

// ---------------------------------------------------------------------------
// Profile lookup against the live buffer. Pick and draw both route through this so a handle
// is always grabbable exactly where it is drawn.
// ---------------------------------------------------------------------------
ScProfile profileAtZ(float zw)
{
    int i0, i1, i2, i3; float t;
    sc_bayFrame(zw, i0, i1, i2, i3, t);
    return sc_profileFrom(Plan[SC_BAY_0 + (uint)i0], Plan[SC_BAY_0 + (uint)i1],
                          Plan[SC_BAY_0 + (uint)i2], Plan[SC_BAY_0 + (uint)i3], t);
}

// Nearest pickable record under a diagram point. Smallest hit wins so a small mass resting on
// a bay handle stays reachable.
uint pickRecord(float2 uv, out int strip)
{
    strip = sc_stripAt(uv);
    uint best = 0u; float bestScore = 1e9;
    float2 asp = float2(_Resolution.x / max(_Resolution.y, 1.0), 1.0);

    if (strip == 3)
    {
        // the sun inset: one target, the disc itself
        return (Plan[SC_SKY].active > 0.5) ? (SC_SKY + 1u) : 0u;
    }
    if (strip == 0) return 0u;

    float cy = (strip == 1) ? SC_PLAN_CY : SC_ELEV_CY;

    for (uint m = 0u; m < SC_MASSES; m++)
    {
        ScRec r = Plan[SC_MASS_0 + m];
        if (r.active > 0.5)
        {
            ScProfile pf = profileAtZ(r.pos.x);
            float2 sec = sc_massSection(r, pf.h);
            float w = (strip == 1) ? (pf.c.x + sec.x) : (pf.c.y + sec.y);
            float2 hp = float2(sc_zToX(r.pos.x), sc_wToY(w, cy));
            float d = length((uv - hp) * asp);
            float rad = max(r.size.x / SC_WORLD_H * SC_STRIP_H, 0.016);
            if (d < rad && d < bestScore) { bestScore = d; best = SC_MASS_0 + m + 1u; }
        }
    }
    if (best != 0u) return best;

    for (uint b = 0u; b < SC_BAYS; b++)
    {
        ScRec r = Plan[SC_BAY_0 + b];
        float w = (strip == 1) ? r.pos.x : r.pos.y;
        float2 hp = float2(sc_zToX((float)b * SC_BAY_Z), sc_wToY(w, cy));
        float d = length((uv - hp) * asp);
        if (d < 0.028 && d < bestScore) { bestScore = d; best = SC_BAY_0 + b + 1u; }
    }
    return best;
}

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    ScRec hdr = Plan[SC_HEADER];
    float initFlag = hdr.tone;
    float salt     = hdr.seed;
    float sel      = hdr.pos.y;      // selected index + 1, 0 = nothing
    float dragOn   = hdr.size.x;     // 0 none, 1 plan strip, 2 elevation strip, 3 sun inset
    float2 grab    = float2(hdr.size.y, hdr.kind);
    float travel   = hdr.grp;        // persistent accumulator, NEVER reset by a rebuild

    uint n = min((uint)_ViewportEventCount, 64u);

    // --- pass 1: keys. R changes the salt, so it must land before the signature test.
    for (uint e = 0u; e < n; e++)
    {
        ViewportEvent ev = _ViewportEvents[e];
        if (ev.type == 4u && ev.phase == 1u)
        {
            uint c = (uint)ev.code;
            if (c == 18u) salt += 1.0;                               // R  reseed
            else if (c == 3u) sel = 0.0;                             // C  clear selection
            else if (sel > 0.5)
            {
                uint idx = (uint)(sel - 1.0);
                ScRec r = Plan[idx];
                uint fl = (uint)r.flags;
                if (c == 11u)                                        // K  cycle kind / palette
                {
                    if (r.role == ROLE_BAY)       r.kind = fmod(r.kind + 1.0, (float)SC_PALSETS);
                    else if (r.role == ROLE_MASS) r.kind = fmod(r.kind + 1.0, (float)MK_KINDS);
                    r.flags = (float)(fl | F_EDITED);
                }
                else if (c == 5u)                                    // E  widen / grow
                {
                    if (r.role == ROLE_BAY)      r.size = min(r.size * 1.12, float2(3.20, 2.40));
                    else if (r.role == ROLE_MASS) r.size.x = min(r.size.x * 1.14, 1.60);
                    else if (r.role == ROLE_SKY)  r.size.x = min(r.size.x * 1.08, 1.60);
                    r.flags = (float)(fl | F_EDITED);
                }
                else if (c == 17u)                                   // Q  narrow / shrink
                {
                    if (r.role == ROLE_BAY)      r.size = max(r.size * 0.893, float2(0.30, 0.24));
                    else if (r.role == ROLE_MASS) r.size.x = max(r.size.x * 0.877, 0.05);
                    else if (r.role == ROLE_SKY)  r.size.x = max(r.size.x * 0.926, 0.06);
                    r.flags = (float)(fl | F_EDITED);
                }
                else if (c == 24u)                                   // X  toggle on/off
                {
                    r.active = (r.active > 0.5) ? 0.0 : 1.0;
                    r.flags = (float)(fl | F_EDITED);
                }
                else if (c == 14u)                                   // N  re-roll this record
                {
                    r.seed += 7.77;
                    if (r.role == ROLE_BAY)
                    {
                        r.grp   = (sc_rnd(r.seed, 1.0) - 0.5) * 0.55;
                        r.phase = lerp(0.65, 1.55, sc_rnd(r.seed, 2.0));
                        r.tone  = saturate(lerp(0.05, 0.55, sc_rnd(r.seed, 3.0)));
                    }
                    else if (r.role == ROLE_MASS)
                    {
                        r.grp   = lerp(0.55, 1.05, sc_rnd(r.seed, 1.0));
                        r.phase = lerp(0.14, 0.34, sc_rnd(r.seed, 2.0));
                        r.size.y = lerp(0.60, 2.80, sc_rnd(r.seed, 3.0));
                    }
                    r.flags = (float)(fl | F_EDITED);
                }
                Plan[idx] = r;
            }
        }
    }

    float sig = seed * 7.31 + (float)bay_count * 1.13 + (float)mass_count * 2.17
              + (float)palette_set * 37.7 + variation * 137.9 + bend * 53.1
              + flare * 97.3 + aperture * 71.3 + eye_height * 61.3
              + mass_scale * 43.9 + accent * 31.7 + salt * 101.3
              + PLAN_VERSION * 911.7;

    if (initFlag < 0.5 || abs(sig - hdr.pos.x) > 1e-4)
    {
        float s = seed + salt * 3.19;
        buildBays(s);
        buildMasses(s);
        buildSky();
        sel = 0.0; dragOn = 0.0;
    }

    // --- pass 2: pointer. Selection and drag share pickRecord() with the canvas.
    for (uint e2 = 0u; e2 < n; e2++)
    {
        ViewportEvent ev = _ViewportEvents[e2];
        if (ev.type == 5u)
        {
            float2 p = ev.position;
            if (ev.code == 1u && ev.phase == 7u)
            {
                int st;
                sel = (float)pickRecord(p, st);
            }
            else if (ev.code == 3u)
            {
                if (ev.phase == 5u)
                {
                    int st;
                    uint hit = pickRecord(p, st);
                    sel = (float)hit;
                    dragOn = 0.0;
                    if (hit != 0u)
                    {
                        uint idx = hit - 1u;
                        ScRec r = Plan[idx];
                        dragOn = (float)st;
                        float cy = (st == 1) ? SC_PLAN_CY : SC_ELEV_CY;
                        if (r.role == ROLE_BAY)
                        {
                            grab = float2(((st == 1) ? r.pos.x : r.pos.y) - sc_yToW(p.y, cy), 0.0);
                        }
                        else if (r.role == ROLE_MASS)
                        {
                            ScProfile pf = profileAtZ(r.pos.x);
                            float2 sec = sc_massSection(r, pf.h);
                            float w = (st == 1) ? (pf.c.x + sec.x) : (pf.c.y + sec.y);
                            grab = float2(r.pos.x - sc_xToZ(p.x), w - sc_yToW(p.y, cy));
                        }
                        else if (r.role == ROLE_SKY)
                        {
                            float2 ic = float2((SC_INSET_X0 + SC_INSET_X1) * 0.5,
                                               (SC_INSET_Y0 + SC_INSET_Y1) * 0.5);
                            float2 ih = float2((SC_INSET_X1 - SC_INSET_X0) * 0.5,
                                               (SC_INSET_Y1 - SC_INSET_Y0) * 0.5);
                            float2 s = float2((p.x - ic.x) / ih.x, -(p.y - ic.y) / ih.y);
                            grab = r.pos - s;
                        }
                    }
                }
                else if (ev.phase == 6u && dragOn > 0.5 && sel > 0.5)
                {
                    uint idx = (uint)(sel - 1.0);
                    ScRec r = Plan[idx];
                    int st = (int)dragOn;
                    float cy = (st == 1) ? SC_PLAN_CY : SC_ELEV_CY;

                    if (r.role == ROLE_BAY)
                    {
                        // The strip decides the axis: the plan strip owns lateral drift, the
                        // elevation strip owns rise and fall. Same handle, two projections —
                        // which is exactly how you draw a corridor on paper.
                        float w = clamp(sc_yToW(p.y, cy) + grab.x, -1.75, 1.75);
                        if (st == 1) r.pos.x = w; else r.pos.y = w;
                        r.active = 1.0;
                        r.flags = (float)(((uint)r.flags) | F_EDITED);
                    }
                    else if (r.role == ROLE_MASS)
                    {
                        r.pos.x = sc_wrapZ(sc_xToZ(p.x) + grab.x);
                        // Recover the perimeter angle from the dragged section point: the
                        // dragged axis takes the new value, the other axis keeps the one this
                        // strip cannot see. That is a true plan/elevation edit rather than two
                        // independent sliders that disagree.
                        ScProfile pf = profileAtZ(r.pos.x);
                        float2 sec = sc_massSection(r, pf.h);
                        float w = sc_yToW(p.y, cy) + grab.y;
                        float2 tgt = (st == 1) ? float2(w - pf.c.x, sec.y)
                                               : float2(sec.x, w - pf.c.y);
                        if (abs(tgt.x) + abs(tgt.y) > 1e-4)
                            r.pos.y = frac(atan2(tgt.y, tgt.x) / 6.2831853 + 1.0);
                        r.flags = (float)(((uint)r.flags) | F_EDITED);
                    }
                    else if (r.role == ROLE_SKY)
                    {
                        float2 ic = float2((SC_INSET_X0 + SC_INSET_X1) * 0.5,
                                           (SC_INSET_Y0 + SC_INSET_Y1) * 0.5);
                        float2 ih = float2((SC_INSET_X1 - SC_INSET_X0) * 0.5,
                                           (SC_INSET_Y1 - SC_INSET_Y0) * 0.5);
                        float2 s = float2((p.x - ic.x) / ih.x, -(p.y - ic.y) / ih.y);
                        r.pos = clamp(s + grab, -1.4, 1.4);
                        r.flags = (float)(((uint)r.flags) | F_EDITED);
                    }
                    Plan[idx] = r;
                }
                else { dragOn = 0.0; }
            }
        }
    }

    // Appearance-only refresh. These are NOT in the signature, so tuning the sun or the stripe
    // pitch never costs the user a corridor they dragged into place.
    {
        ScRec sky = Plan[SC_SKY];
        uint sfl = (uint)sky.flags;
        sky.role = ROLE_SKY;
        sky.kind = (float)stripe_count;
        sky.tone = horizon;
        if ((sfl & F_EDITED) == 0u)
        {
            sky.pos    = float2(sun_x, sun_y);
            sky.size.x = sun_radius;
        }
        sky.size.y = max(sky.size.x * 0.175, 0.012);
        // The small pale sun is DERIVED from the horizon, not given its own coordinates: it
        // has to sit just clear of the sea at every horizon setting, and an absolute offset
        // silently drowns it the moment the tide is raised.
        sky.grp   = 0.24;
        sky.phase = (horizon + 0.17) - sky.pos.y;
        sky.active = 1.0;
        Plan[SC_SKY] = sky;
    }

    // selection flag is derived, never stored twice
    for (uint i = 0u; i < SC_RECORDS - 1u; i++)
    {
        ScRec r = Plan[i];
        uint f = (uint)r.flags;
        f = (sel > 0.5 && (uint)(sel - 1.0) == i) ? (f | F_SELECTED) : (f & ~F_SELECTED);
        r.flags = (float)f;
        Plan[i] = r;
    }

    // TRAVEL. Integrated against _DeltaTime, never rate x absolute time, so changing speed
    // mid-flight does not teleport the corridor. `phase` is the sweepable loop coordinate on
    // top of it: 0 -> 1 is exactly one seamless period.
    travel = frac(travel / SC_LOOP_Z + _DeltaTime * flight_speed / SC_LOOP_Z) * SC_LOOP_Z;
    float travelOut = frac(travel / SC_LOOP_Z + phase) * SC_LOOP_Z;

    uint liveB = 0u, liveM = 0u;
    for (uint a = 0u; a < SC_BAYS;   a++) if (Plan[SC_BAY_0 + a].active  > 0.5) liveB++;
    for (uint b2 = 0u; b2 < SC_MASSES; b2++) if (Plan[SC_MASS_0 + b2].active > 0.5) liveM++;

    hdr.pos    = float2(sig, sel);
    hdr.size   = float2(dragOn, grab.x);
    hdr.role   = ROLE_HEADER;
    hdr.kind   = grab.y;
    hdr.seed   = salt;
    hdr.tone   = 1.0;
    hdr.grp    = travel;                              // persistent accumulator
    hdr.phase  = travelOut;                           // what the renderer flies on
    hdr.flags  = (float)liveB + (float)liveM * 100.0; // packed tallies for the preview
    hdr.active = 1.0;
    Plan[SC_HEADER] = hdr;
}
