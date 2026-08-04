// RS_Plan / plan.hlsl — authors one loop of reactor shaft into a durable record buffer.
//
// Single-threaded on purpose: the layout is sequential and the viewport event queue must be
// reduced in order. 74 records is nothing next to any render pass.
//
// PERIODICITY IS STRUCTURAL. Stations are addressed modulo RS_STATIONS and every fixture and
// light lives entirely inside its own station's half-slice, so any per-station value — random
// draw or hand edit — is automatically periodic AND can never overlap its neighbour. The user
// cannot author a seam.
//
// Regeneration is signature-driven. A structural parameter (or the R-key salt) changing the
// signature rebuilds the shaft; anything else preserves the buffer, so dragged fixtures survive
// cooks, saves, presets and undo. Travel is deliberately OUTSIDE the signature: re-rolling the
// machinery must not jog the flight.
#include "../_shared/shaft.hlsli"

RWStructuredBuffer<RsRec> Plan : register(u0);

// Bump whenever the layout algorithm below changes, or a recompile will silently keep serving
// the previously generated shaft out of the persistent buffer.
// 1.1 — fixture placement now clamps against rs_faceLimit(), which accounts for the ROUNDED
// corners. Without this bump the persistent buffer keeps serving blocks that hang outside the
// shaft at the corners, and the fix silently does nothing.
// 1.2 — light radii and the cross-face bar length are now DERIVED from the station inradius
// instead of being absolute constants. Without this bump the persistent buffer keeps serving
// tubes sized for a bore the project no longer has.
#define PLAN_VERSION 1.4

// ---------------------------------------------------------------------------
// The transcribed shaft, written as smooth periodic functions of the station angle rather than
// a table. The reference's shaft breathes and drifts rather than stepping, so the vocabulary
// that describes it is harmonic — and writing it this way means station 11 flows into station 0
// with no hand-checked wrap.
//
// TWIST IS A SWING, NOT A RAMP. A monotonic 120-degree-per-loop spiral would leave the BORE
// seamless (the section is 3-fold symmetric) but would carry every fixture onto its neighbour's
// face at the wrap. A periodic swing gives the same rotating read — near and far sections are
// always rolled differently — and is provably seam-exact.
// ---------------------------------------------------------------------------
void baseStation(uint i, out float2 c, out float rin, out float roll,
                 out float rnd_, out float dens, out float panel)
{
    float a = ((float)i / (float)RS_STATIONS) * 6.2831853;
    c     = float2(sin(a + 0.35) * 0.115, cos(a * 2.0 - 0.65) * 0.095);
    rin   = 1.0 + 0.115 * sin(2.0 * a + 0.85) + 0.055 * cos(3.0 * a - 0.40);
    roll  = 0.46 * sin(a + 0.90) + 0.17 * sin(2.0 * a - 1.30);
    rnd_  = 0.20 + 0.070 * sin(3.0 * a + 2.10);
    dens  = 0.62 + 0.30 * sin(a * 2.0 + 1.70);
    panel = 1.0 + 0.22 * sin(a + 2.40);
}

// Three ranks per station: a big structural block, a medium panel, a small detail. The rank
// hierarchy is the thing that has to survive a re-roll — a flat random size draw turns a
// machined wall into gravel.
void baseFix(uint s, uint k, out float u, out float zoff,
             out float hw, out float pr, out float zh, out float tone)
{
    float a  = ((float)s / (float)RS_STATIONS) * 6.2831853;
    float fk = (float)k;

    if (k == 0u)      { hw = 0.62; pr = 0.290; zh = 0.90; tone = 0.42; }
    else if (k == 1u) { hw = 0.40; pr = 0.185; zh = 0.56; tone = 0.58; }
    else              { hw = 0.24; pr = 0.115; zh = 0.36; tone = 0.72; }

    hw   *= 1.0 + 0.16 * sin(a * 2.0 + fk * 1.9);
    pr   *= 1.0 + 0.22 * sin(a * 3.0 - fk * 2.3);
    zh   *= 1.0 + 0.18 * cos(a + fk * 1.1);
    u     = (fk - 1.0) * 0.42 + 0.30 * sin(a + fk * 2.2);
    zoff  = 0.34 * sin(a * 2.0 + fk * 1.4);
    tone += 0.10 * sin(a * 3.0 + fk);
}

// The fixture vocabulary in force. This is the machinery EXPLORATION AXIS: it changes what the
// shaft is built from, not how it is graded.
int kindFor(int set, uint k, uint s)
{
    uint r = (s + k * 5u) % 3u;
    if (set == 0)                                   // Heat Exchange — the reference
    {
        if (k == 0u) return (r == 1u) ? FK_SLAB : FK_FINS;
        if (k == 1u) return (r == 2u) ? FK_FINS : FK_GRILLE;
        return (r == 1u) ? FK_DRUM : FK_BEAM;
    }
    if (set == 1)                                   // Cargo Deck — stacked freight
    {
        if (k == 0u) return (r == 2u) ? FK_STACK : FK_SLAB;
        if (k == 1u) return (r == 0u) ? FK_SLAB : FK_STACK;
        return (r == 1u) ? FK_BEAM : FK_DRUM;
    }
    if (set == 2)                                   // Sensor Array — instrumented
    {
        if (k == 0u) return (r == 0u) ? FK_GRILLE : FK_DRUM;
        if (k == 1u) return FK_GRILLE;
        return (r == 2u) ? FK_FINS : FK_BEAM;
    }
    if (k == 0u) return FK_SLAB;                    // Bare Structure — girders only
    if (k == 1u) return (r == 1u) ? FK_BEAM : FK_SLAB;
    return FK_BEAM;
}

// A random draw of the three faces is a PERMUTATION, never three free draws. That single choice
// removes the whole class of "two blocks fused into one lump at the same z" failures without a
// rejection loop, and it is still a real relational re-roll: which wall carries the big block.
static const int RS_PERM[18] = { 0,1,2,  0,2,1,  1,0,2,  1,2,0,  2,0,1,  2,1,0 };

void buildStations(float s)
{
    uint want = (uint)clamp((float)station_count, 0.0, (float)RS_STATIONS);
    float v = saturate(variation);
    for (uint i = 0u; i < RS_STATIONS; i++)
    {
        RsRec r = (RsRec)0;
        // A stream kept separate from r.seed so re-rolling ONE station with N does not shift
        // what every other station drew.
        float rs = s * 11.7 + (float)i * 29.3 + 101.0;

        float2 bc; float brin, broll, brnd, bdens, bpanel;
        baseStation(i, bc, brin, broll, brnd, bdens, bpanel);

        // Magnitudes randomize AROUND each station's own value rather than being redrawn flat:
        // the base curve encodes a pinch/flare cadence, and a flat draw per station turns a
        // machined shaft into a lumpy gut.
        float2 rc  = float2((rs_rnd(rs, 3.0) - 0.5) * 0.42, (rs_rnd(rs, 4.0) - 0.5) * 0.42);
        float rrin = brin * lerp(0.84, 1.20, rs_rnd(rs, 5.0));
        float rrol = (rs_rnd(rs, 6.0) - 0.5) * 1.30;

        r.pos    = lerp(bc, rc, v) * drift;
        // The centre may never wander far enough to put the flight axis outside the bore; that
        // is the one arrangement no seed is allowed to produce.
        float rr = max(lerp(brin, rrin, v) * bore, 0.45);
        r.pos    = clamp(r.pos, -0.34 * rr, 0.34 * rr);
        r.size   = float2(rr, clamp(lerp(brnd, lerp(0.08, 0.40, rs_rnd(rs, 7.0)), v) * corner, 0.02, 0.60));
        r.role   = ROLE_STATION;
        // Palette zoning: at variation 0 the whole shaft carries the reference chord; as it
        // rises stations start defecting, which reads as coloured zones sliding past.
        r.kind   = (rs_rnd(rs, 9.0) < v * 0.5)
                     ? min(floor(rs_rnd(rs, 10.0) * (float)RS_PALSETS), (float)(RS_PALSETS - 1))
                     : (float)palette_set;
        r.seed   = s * 3.3 + (float)i * 17.0 + 1.0;
        r.tone   = saturate(lerp(bdens, lerp(0.30, 1.0, rs_rnd(rs, 11.0)), v) * density);
        r.grp    = lerp(broll, rrol, v) * twist;
        r.phase  = max(lerp(bpanel, lerp(0.55, 1.60, rs_rnd(rs, 12.0)), v), 0.20);
        r.flags  = 0.0;
        r.active = (i < want) ? 1.0 : 0.0;
        Plan[RS_STA_0 + i] = r;
    }
}

void buildFixtures(float s)
{
    uint want = (uint)clamp((float)fix_count, 0.0, (float)RS_FIX_PER);
    float v = saturate(variation);
    for (uint i = 0u; i < RS_STATIONS; i++)
    {
        float srs = s * 5.9 + (float)i * 61.7 + 7.0;
        int permBase = (int)min(floor(rs_rnd(srs, 21.0) * 6.0), 5.0) * 3;
        bool usePerm = (rs_rnd(srs, 22.0) < v);

        for (uint k = 0u; k < RS_FIX_PER; k++)
        {
            RsRec r = (RsRec)0;
            float rs = s * 13.1 + (float)i * 37.7 + (float)k * 91.3 + 211.0;

            float bu, bz, bhw, bpr, bzh, btone;
            baseFix(i, k, bu, bz, bhw, bpr, bzh, btone);

            int face = usePerm ? RS_PERM[permBase + (int)k] : (int)((k + i) % 3u);

            // Temper the extremes toward the rank's own value: a slender detail drawn at the
            // low end of a flat range reads as wire, and a big block drawn at the high end
            // swallows the station. Randomizing a ratio around the rank keeps the hierarchy.
            float rhw = bhw * lerp(0.72, 1.34, rs_rnd(rs, 3.0));
            float rpr = bpr * lerp(0.70, 1.42, rs_rnd(rs, 4.0));
            float rzh = bzh * lerp(0.66, 1.40, rs_rnd(rs, 5.0));
            float ru  = (rs_rnd(rs, 6.0) - 0.5) * 1.44;
            float rz  = (rs_rnd(rs, 7.0) - 0.5) * 2.0 * RS_SLICE_H;

            float u  = lerp(bu, ru, v);
            float hw = lerp(bhw, rhw, v) * fix_scale;
            float pr = lerp(bpr, rpr, v) * fix_scale;
            float zh = lerp(bzh, rzh, v);
            float zo = lerp(bz, rz, v);

            // GUARANTEE 1 — the block stays ON the face it is bolted to, allowing for the fact
            // that the corners are ROUNDED and the flat part of a face is therefore shorter
            // than the ideal sqrt(3) inradii.
            float lim = rs_faceLimit(Plan[RS_STA_0 + i].size.y);
            u  = clamp(u, -(lim - 0.10) / RS_FACE_SPAN, (lim - 0.10) / RS_FACE_SPAN);
            hw = clamp(hw, 0.04, max(lim - RS_FACE_SPAN * abs(u), 0.06));
            // GUARANTEE 2 — the block never intrudes into the flight tube. Protrusion is a
            // fraction of the inradius, so the cap is expressed in the same units and holds at
            // every bore setting.
            float rin = max(Plan[RS_STA_0 + i].size.x, 0.30);
            float prMax = max((rin - flight_clear - 0.34 * rin) / rin, 0.02);
            pr = clamp(pr, 0.01, min(prMax, 0.42));
            // GUARANTEE 3 — the block stays inside its own station's slice.
            rs_fitSlice(zo, zh);

            r.pos    = float2(zo, u);
            r.size   = float2(hw, pr);
            r.role   = ROLE_FIX;
            r.kind   = (rs_rnd(rs, 8.0) < v)
                         ? min(floor(rs_rnd(rs, 9.0) * (float)FK_KINDS), (float)(FK_KINDS - 1))
                         : (float)kindFor(greeble_set, k, i);
            r.seed   = s * 7.1 + (float)i * 23.0 + (float)k * 3.7 + 5.0;
            r.tone   = saturate(lerp(btone, lerp(0.22, 0.92, rs_rnd(rs, 10.0)), v));
            r.grp    = (float)face;
            r.phase  = zh;
            r.flags  = 0.0;
            r.active = (k < want) ? 1.0 : 0.0;
            Plan[RS_FIX_0 + i * RS_FIX_PER + k] = r;
        }
    }
}

// Lights are HOSTED. A neon run belongs beside the block it lights, and a corner lamp belongs
// on a corner. Drawing free coordinates for them is what turns a lit machine into fireflies, so
// every light derives its face and its along-face position from a real host record instead.
void buildLights(float s)
{
    uint want = (uint)clamp((float)light_count, 0.0, (float)RS_LIGHT_PER);
    float v = saturate(variation);
    for (uint i = 0u; i < RS_STATIONS; i++)
    {
        for (uint k = 0u; k < RS_LIGHT_PER; k++)
        {
            RsRec r = (RsRec)0;
            float rs = s * 17.3 + (float)i * 43.1 + (float)k * 79.9 + 401.0;

            uint hostSlot = (k == 0u) ? 0u : (uint)(1u + (i % 2u));
            RsRec host = Plan[RS_FIX_0 + i * RS_FIX_PER + hostSlot];
            // DERIVED FROM THE BORE, not given parallel absolute sizes. A tube whose radius is
            // a constant while the shaft's inradius is a parameter looks correct at exactly one
            // Bore setting and like wire or like plumbing at every other.
            float rin = max(Plan[RS_STA_0 + i].size.x, 0.30);

            int kind;
            if (k == 0u)
            {
                kind = LK_RUN;                                   // tube running beside the block
            }
            else
            {
                uint m = i % 4u;
                kind = (m == 1u) ? LK_FLOOD : ((m == 3u) ? LK_BEACON : LK_BAR);
            }
            if (rs_rnd(rs, 2.0) < v * 0.7)
                kind = (int)min(floor(rs_rnd(rs, 3.0) * (float)LK_KINDS), (float)(LK_KINDS - 1));

            float side = (rs_rnd(rs, 4.0) < 0.5) ? -1.0 : 1.0;
            float u, zo, half_, rad, hue, gain;

            if (kind == LK_FLOOD)
            {
                // corner lamps take a corner, not a face: grp 3..5 selects which
                r.grp  = 3.0 + (float)((i + k) % 3u);
                u      = 0.0;
                zo     = host.pos.x + side * 0.22;
                half_  = 0.06 * rin;
                rad    = 0.070 * rin * lerp(0.85, 1.30, rs_rnd(rs, 5.0));
                hue    = 0.0;
                gain   = flood_gain;
            }
            else if (kind == LK_BEACON)
            {
                r.grp  = host.grp;
                u      = clamp(host.pos.y + side * (host.size.x / RS_FACE_SPAN + 0.08), -0.95, 0.95);
                zo     = host.pos.x + side * host.phase * 0.55;
                half_  = 0.028 * rin;
                rad    = 0.032 * rin;
                hue    = rs_rnd(rs, 6.0);
                gain   = light_gain * 0.85;
            }
            else if (kind == LK_BAR)
            {
                // across the face, sitting on the block's shoulder. host.size.x is a FRACTION of
                // the inradius, so it has to be taken back into world units before it becomes a
                // length — the bar was previously about 40% short at the default bore.
                r.grp  = host.grp;
                u      = clamp(host.pos.y, -0.90, 0.90);
                zo     = host.pos.x + side * (host.phase + 0.10 * rin);
                half_  = clamp(host.size.x * rin * 1.05, 0.08 * rin, 1.20 * rin);
                rad    = 0.040 * rin * lerp(0.85, 1.40, rs_rnd(rs, 7.0));
                hue    = rs_rnd(rs, 8.0) * rs_rnd(rs, 16.0) * 0.90;
                gain   = light_gain;
            }
            else                                                 // LK_RUN
            {
                r.grp  = host.grp;
                u      = clamp(host.pos.y + side * (host.size.x / RS_FACE_SPAN + 0.10), -0.95, 0.95);
                zo     = host.pos.x;
                half_  = max(host.phase * 1.05, 0.14);
                rad    = 0.042 * rin * lerp(0.85, 1.35, rs_rnd(rs, 9.0));
                hue    = rs_rnd(rs, 10.0) * rs_rnd(rs, 15.0) * 0.80;   // biased toward the magenta end
                gain   = light_gain;
            }

            // A run extends along z, so it obeys the slice invariant on its own half-length.
            // Everything else is short enough that only its z offset needs fitting.
            float zh = (kind == LK_RUN) ? half_ : max(rad, 0.05);
            rs_fitSlice(zo, zh);
            if (kind == LK_RUN) half_ = zh;

            r.pos    = float2(zo, u);
            r.size   = float2(half_, rad);
            r.role   = ROLE_LIGHT;
            r.kind   = (float)kind;
            r.seed   = s * 9.7 + (float)i * 31.0 + (float)k * 5.3 + 3.0;
            r.tone   = max(gain, 0.0) * lerp(0.78, 1.22, rs_rnd(rs, 11.0));
            r.phase  = hue;
            r.flags  = 0.0;
            r.active = (k < want) ? 1.0 : 0.0;
            Plan[RS_LIGHT_0 + i * RS_LIGHT_PER + k] = r;
        }
    }
}

void buildCore()
{
    RsRec r = (RsRec)0;
    r.pos    = float2(core_x, core_y);
    r.size   = float2(core_radius, core_radius * core_hot);
    r.role   = ROLE_CORE;
    r.kind   = (float)core_spokes;
    r.seed   = 19.0;
    r.tone   = core_gain;
    r.grp    = core_ring;
    r.phase  = core_spin;
    r.flags  = 0.0;
    r.active = 1.0;
    Plan[RS_CORE] = r;
}

// ---------------------------------------------------------------------------
// Profile lookup against the LIVE buffer. Pick and draw both route through this, so a handle is
// always grabbable exactly where it is drawn.
// ---------------------------------------------------------------------------
RsProfile profileAtZ(float zw)
{
    int i0, i1, i2, i3; float t;
    rs_staFrame(rs_wrapZ(zw), i0, i1, i2, i3, t);
    return rs_profileFrom(Plan[RS_STA_0 + (uint)i0], Plan[RS_STA_0 + (uint)i1],
                          Plan[RS_STA_0 + (uint)i2], Plan[RS_STA_0 + (uint)i3], t);
}

// Nearest pickable record. Smallest hit wins, so a beacon sitting on a big slab stays reachable.
uint pickRecord(float2 uv, float2 asp, float travel, float sel, out int strip)
{
    strip = rs_stripAt(uv, asp);
    uint best = 0u; float bestScore = 1e9;

    if (strip == 3) return RS_CORE + 1u;

    if (strip == 1)
    {
        // --- the clearance section: lights, then fixtures, then station handles
        for (uint li = 0u; li < RS_LIGHTS; li++)
        {
            RsRec r = Plan[RS_LIGHT_0 + li];
            uint sta = rs_staOfLight(RS_LIGHT_0 + li);
            float zw = rs_recZ(sta, r);
            RsProfile pf = profileAtZ(zw);
            float2 hp = float2(rs_zToX(zw), rs_rToY(rs_lightClear(r, pf)));
            float d = length((uv - hp) * asp);
            if (d < 0.017 && d < bestScore) { bestScore = d; best = RS_LIGHT_0 + li + 1u; }
        }
        if (best != 0u) return best;

        for (uint fi = 0u; fi < RS_FIXES; fi++)
        {
            RsRec r = Plan[RS_FIX_0 + fi];
            uint sta = rs_staOfFix(RS_FIX_0 + fi);
            float zw = rs_recZ(sta, r);
            RsProfile pf = profileAtZ(zw);
            RsFixGeo g = rs_fixGeo(r, pf);
            float yLo = rs_rToY(rs_faceAxisDist(pf, (int)clamp(r.grp, 0.0, 2.0)));  // the face
            float yHi = rs_rToY(g.clr);                                             // inner surface
            // the z test wraps on the loop, so a station-0 fixture reaching back past the seam
            // is still grabbable at the right-hand end of the strip
            float dzx = abs(rs_wrapDZ(rs_xToZ(uv.x) - zw)) / RS_LOOP_Z * (RS_LON_X1 - RS_LON_X0);
            float halfX = (g.zh / RS_LOOP_Z) * (RS_LON_X1 - RS_LON_X0);
            float2 q = float2(dzx - max(halfX, 0.004),
                              abs(uv.y - (yLo + yHi) * 0.5) - max(abs(yLo - yHi) * 0.5, 0.006));
            float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
            if (d < 0.010 && d < bestScore) { bestScore = d + 0.006; best = RS_FIX_0 + fi + 1u; }
        }
        if (best != 0u) return best;

        for (uint si = 0u; si < RS_STATIONS; si++)
        {
            RsProfile pf = profileAtZ((float)si * RS_STATION_Z);
            float2 hp = float2(rs_zToX((float)si * RS_STATION_Z), rs_rToY(pf.rin));
            float d = length((uv - hp) * asp);
            if (d < 0.021 && d < bestScore) { bestScore = d; best = RS_STA_0 + si + 1u; }
        }
        return best;
    }

    if (strip == 2)
    {
        // --- the cross-section rosette: everything belonging to the shown station
        int sta = rs_rosStation(sel, travel);
        RsProfile pf = profileAtZ((float)sta * RS_STATION_Z);
        float2 s = rs_uvToSec(uv, asp, rs_rosWorld(pf.rin));

        for (uint lk = 0u; lk < RS_LIGHT_PER; lk++)
        {
            uint idx = RS_LIGHT_0 + (uint)sta * RS_LIGHT_PER + lk;
            RsRec r = Plan[idx];
            float2 tg; float2 sp = rs_lightSection(r, pf, tg);
            float d = length(s - sp);
            float rad = max(r.size.y * 2.2, 0.09);
            if (d < rad && d < bestScore) { bestScore = d; best = idx + 1u; }
        }
        if (best != 0u) return best;

        for (uint fk = 0u; fk < RS_FIX_PER; fk++)
        {
            uint idx = RS_FIX_0 + (uint)sta * RS_FIX_PER + fk;
            RsRec r = Plan[idx];
            RsFixGeo g = rs_fixGeo(r, pf);
            float2 d2 = s - g.face - g.nIn * g.pr * 0.5;
            float2 q = abs(float2(dot(d2, g.tang), dot(d2, g.nIn))) - float2(g.hw, g.pr * 0.5 + 0.02);
            float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
            if (d < 0.06 && d < bestScore) { bestScore = d + 0.02; best = idx + 1u; }
        }
        if (best != 0u) return best;

        // empty rosette space grabs the station itself, which is where its 2D centre offset —
        // the one value no longitudinal view can show — is edited
        return RS_STA_0 + (uint)sta + 1u;
    }
    return 0u;
}

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    RsRec hdr = Plan[RS_HEADER];
    float initFlag = hdr.tone;
    // TRANSPORT. Space toggles this, and travel integrates against it. A key cannot write a host
    // parameter, but pause is not a speed VALUE anyway — it is transport state, and keeping the
    // two separate means Flight Speed still means what it says while paused, and resuming does
    // not have to remember and restore a number.
    //
    // Packed into the header's init flag: 2 = paused, 3 = running, below 0.5 = never initialised.
    // The legacy value 1.0 (written before transport existed) must decode as RUNNING — encoding
    // paused as 1.0 instead made every already-saved project open frozen with no visible cause.
    float running = (initFlag < 1.5) ? 1.0 : ((initFlag > 2.5) ? 1.0 : 0.0);
    float salt     = hdr.seed;
    float sel      = hdr.pos.y;      // selected index + 1, 0 = nothing
    float dragOn   = hdr.size.x;     // 0 none, 1 clearance section, 2 rosette, 3 core inset
    float2 grab    = float2(hdr.size.y, hdr.kind);
    float travel   = hdr.grp;        // persistent accumulator, NEVER reset by a rebuild

    float2 asp = float2(_Resolution.x / max(_Resolution.y, 1.0), 1.0);
    uint n = min((uint)_ViewportEventCount, 64u);

    // --- pass 1: keys. R changes the salt, so it must land before the signature test.
    for (uint e = 0u; e < n; e++)
    {
        ViewportEvent ev = _ViewportEvents[e];
        if (ev.type == 4u && ev.phase == 1u)
        {
            uint c = (uint)ev.code;
            if (c == 18u) salt += 1.0;                               // R  reseed
            else if (c == 51u) running = 1.0 - running;              // SPACE  play / pause
            else if (c == 3u) sel = 0.0;                             // C  clear selection
            else if (sel > 0.5)
            {
                uint idx = (uint)(sel - 1.0);
                RsRec r = Plan[idx];
                uint fl = (uint)r.flags;
                bool isFix = (r.role == ROLE_FIX);
                bool isLit = (r.role == ROLE_LIGHT);
                bool isSta = (r.role == ROLE_STATION);

                if (c == 11u)                                        // K  cycle kind
                {
                    if (isFix)      r.kind = fmod(r.kind + 1.0, (float)FK_KINDS);
                    else if (isLit) r.kind = fmod(r.kind + 1.0, (float)LK_KINDS);
                    else if (isSta) r.kind = fmod(r.kind + 1.0, (float)RS_PALSETS);
                    else            r.kind = fmod(r.kind + 1.0, 25.0);   // core spokes
                    r.flags = (float)(fl | F_EDITED);
                }
                else if (c == 6u)                                    // F  cycle face / corner
                {
                    if (isFix) r.grp = fmod(r.grp + 1.0, 3.0);
                    else if (isLit)
                    {
                        // a corner lamp cycles corners, everything else cycles faces
                        r.grp = (r.kind == (float)LK_FLOOD) ? (3.0 + fmod(r.grp - 3.0 + 1.0, 3.0))
                                                            : fmod(r.grp + 1.0, 3.0);
                    }
                    r.flags = (float)(fl | F_EDITED);
                }
                else if (c == 5u)                                    // E  widen / grow
                {
                    if (isFix)      r.size.x = min(r.size.x * 1.13,
                                        max(rs_faceLimit(Plan[RS_STA_0 + rs_staOfFix(idx)].size.y)
                                            - RS_FACE_SPAN * abs(r.pos.y), 0.06));
                    else if (isLit) r.size.x = min(r.size.x * 1.13, 1.40);
                    else if (isSta) r.size.x = min(r.size.x * 1.08, 2.60);
                    else            r.size.x = min(r.size.x * 1.08, 1.40);
                    r.flags = (float)(fl | F_EDITED);
                }
                else if (c == 17u)                                   // Q  narrow / shrink
                {
                    if (isFix)      r.size.x = max(r.size.x * 0.885, 0.04);
                    else if (isLit) r.size.x = max(r.size.x * 0.885, 0.04);
                    else if (isSta) r.size.x = max(r.size.x * 0.926, 0.45);
                    else            r.size.x = max(r.size.x * 0.926, 0.05);
                    r.flags = (float)(fl | F_EDITED);
                }
                else if (c == 1u || c == 4u)                         // A / D  z run shorter / longer
                {
                    float m = (c == 1u) ? 0.87 : 1.15;
                    if (isFix)
                    {
                        float zo = r.pos.x, zh = r.phase * m;
                        rs_fitSlice(zo, zh);
                        r.pos.x = zo; r.phase = zh;
                    }
                    else if (isLit && r.kind == (float)LK_RUN)
                    {
                        float zo = r.pos.x, zh = r.size.x * m;
                        rs_fitSlice(zo, zh);
                        r.pos.x = zo; r.size.x = zh;
                    }
                    else if (isSta) r.size.y = clamp(r.size.y * m, 0.02, 0.60);
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
                    if (isFix)
                    {
                        r.tone   = saturate(lerp(0.22, 0.92, rs_rnd(r.seed, 1.0)));
                        float zo = (rs_rnd(r.seed, 2.0) - 0.5) * 2.0 * RS_SLICE_H;
                        float zh = r.phase * lerp(0.7, 1.4, rs_rnd(r.seed, 3.0));
                        rs_fitSlice(zo, zh);
                        r.pos.x = zo; r.phase = zh;
                        r.kind = min(floor(rs_rnd(r.seed, 4.0) * (float)FK_KINDS), (float)(FK_KINDS - 1));
                    }
                    else if (isLit)
                    {
                        r.phase = rs_rnd(r.seed, 1.0);
                        r.size.y = clamp(r.size.y * lerp(0.7, 1.5, rs_rnd(r.seed, 2.0)), 0.012, 0.16);
                        r.tone = max(r.tone, 0.05) * lerp(0.7, 1.4, rs_rnd(r.seed, 3.0));
                    }
                    else if (isSta)
                    {
                        r.grp   = (rs_rnd(r.seed, 1.0) - 0.5) * 1.30 * twist;
                        r.phase = lerp(0.55, 1.60, rs_rnd(r.seed, 2.0));
                        r.tone  = saturate(lerp(0.30, 1.0, rs_rnd(r.seed, 3.0)));
                    }
                    r.flags = (float)(fl | F_EDITED);
                }
                Plan[idx] = r;
            }
        }
    }

    float sig = seed * 7.31 + (float)station_count * 1.13 + (float)fix_count * 2.17
              + (float)light_count * 3.11 + (float)palette_set * 37.7 + (float)greeble_set * 57.1
              + variation * 137.9 + bore * 53.1 + drift * 97.3 + twist * 71.3
              + corner * 61.3 + fix_scale * 43.9 + density * 31.7 + flight_clear * 83.9
              + light_gain * 13.7 + flood_gain * 19.3 + salt * 101.3
              + PLAN_VERSION * 911.7;

    if (initFlag < 0.5 || abs(sig - hdr.pos.x) > 1e-4)
    {
        float s = seed + salt * 3.19;
        buildStations(s);
        buildFixtures(s);
        buildLights(s);
        buildCore();
        sel = 0.0; dragOn = 0.0;
    }

    float travelPreview = frac(travel / RS_LOOP_Z + phase) * RS_LOOP_Z;

    // --- pass 2: pointer. Selection and drag share pickRecord() with the canvas.
    for (uint e2 = 0u; e2 < n; e2++)
    {
        ViewportEvent ev = _ViewportEvents[e2];
        if (ev.type != 5u) continue;
        float2 p = ev.position;

        if (ev.code == 1u && ev.phase == 7u)
        {
            int st;
            uint hit = pickRecord(p, asp, travelPreview, sel, st);
            // A click on the scrub ruler JUMPS the flight and leaves the selection alone — it is
            // a transport gesture, not a picking one, and clearing the selection every time you
            // move the playhead would make editing one station while scrubbing impossible.
            if (st == 4) travel = rs_wrapZ(rs_xToZ(p.x) - phase * RS_LOOP_Z);
            else         sel = (float)hit;
        }
        else if (ev.code == 3u)
        {
            if (ev.phase == 5u)
            {
                int st;
                uint hit = pickRecord(p, asp, travelPreview, sel, st);
                dragOn = 0.0;
                if (st == 4)
                {
                    dragOn = 4.0;
                    travel = rs_wrapZ(rs_xToZ(p.x) - phase * RS_LOOP_Z);
                }
                else if (hit == 0u) { sel = 0.0; }
                if (st != 4) sel = (float)hit;
                if (hit != 0u && st != 4)
                {
                    uint idx = hit - 1u;
                    RsRec r = Plan[idx];
                    dragOn = (float)st;
                    if (st == 1)
                    {
                        // grab the offset between the pointer and the record so the handle does
                        // not jump to the cursor on the first update
                        if (r.role == ROLE_FIX || r.role == ROLE_LIGHT)
                        {
                            uint sta = (r.role == ROLE_FIX) ? rs_staOfFix(idx) : rs_staOfLight(idx);
                            grab = float2(rs_recZ(sta, r) - rs_xToZ(p.x), 0.0);
                            RsProfile pf = profileAtZ(rs_recZ(sta, r));
                            if (r.role == ROLE_FIX)
                            {
                                RsFixGeo g = rs_fixGeo(r, pf);
                                grab.y = g.clr - rs_yToR(p.y);
                            }
                        }
                        else if (r.role == ROLE_STATION)
                        {
                            grab = float2(0.0, r.size.x - rs_yToR(p.y));
                        }
                    }
                    else if (st == 2)
                    {
                        RsProfile pf = profileAtZ((float)rs_rosStation(sel, travelPreview) * RS_STATION_Z);
                        float2 s = rs_uvToSec(p, asp, rs_rosWorld(pf.rin));
                        if (r.role == ROLE_STATION) grab = r.pos - s;
                        else                        grab = float2(0.0, 0.0);
                    }
                    else if (st == 3)
                    {
                        float2 ic = float2((RS_INS_X0 + RS_INS_X1) * 0.5, (RS_INS_Y0 + RS_INS_Y1) * 0.5);
                        float2 ih = float2((RS_INS_X1 - RS_INS_X0) * 0.5, (RS_INS_Y1 - RS_INS_Y0) * 0.5);
                        float2 s = float2((p.x - ic.x) / ih.x, -(p.y - ic.y) / ih.y);
                        grab = r.pos - s;
                    }
                }
            }
            else if (ev.phase == 6u && dragOn > 3.5)
            {
                // scrubbing: no selection required, and none is disturbed
                travel = rs_wrapZ(rs_xToZ(p.x) - phase * RS_LOOP_Z);
            }
            else if (ev.phase == 6u && dragOn > 0.5 && sel > 0.5)
            {
                uint idx = (uint)(sel - 1.0);
                RsRec r = Plan[idx];
                int st = (int)dragOn;

                if (st == 1)
                {
                    // THE CLEARANCE SECTION OWNS THE AXIAL EDITS: where along the shaft a thing
                    // sits, and how far it reaches into the bore.
                    if (r.role == ROLE_FIX || r.role == ROLE_LIGHT)
                    {
                        uint sta = (r.role == ROLE_FIX) ? rs_staOfFix(idx) : rs_staOfLight(idx);
                        float zw = rs_xToZ(p.x) + grab.x;
                        float zo = zw - (float)sta * RS_STATION_Z;
                        float zh = (r.role == ROLE_FIX) ? r.phase
                                 : ((r.kind == (float)LK_RUN) ? r.size.x : max(r.size.y, 0.05));
                        rs_fitSlice(zo, zh);
                        r.pos.x = zo;
                        if (r.role == ROLE_FIX) r.phase = zh;
                        else if (r.kind == (float)LK_RUN) r.size.x = zh;

                        if (r.role == ROLE_FIX)
                        {
                            RsProfile pf = profileAtZ(rs_recZ(sta, r));
                            int f = (int)clamp(r.grp, 0.0, 2.0);
                            float faceD = rs_faceAxisDist(pf, f);
                            float want = rs_yToR(p.y) + grab.y;      // target inner radius
                            float pr = (faceD - want) / max(pf.rin, 1e-3);
                            r.size.y = clamp(pr, 0.01, 0.42);
                        }
                    }
                    else if (r.role == ROLE_STATION)
                    {
                        r.size.x = clamp(rs_yToR(p.y) + grab.y, 0.45, 2.60);
                    }
                    r.active = 1.0;
                    r.flags = (float)(((uint)r.flags) | F_EDITED);
                }
                else if (st == 2)
                {
                    // THE ROSETTE OWNS THE SECTION EDITS: which face carries a thing, where it
                    // sits along that face, and the 2D centre drift of the bore. Same handle,
                    // two projections — which is how you draw a shaft on paper.
                    if (r.role == ROLE_STATION)
                    {
                        // the SAME profile the grab was taken against: r.size.x is this
                        // station's own inradius, but the rosette is drawn at the Catmull-Rom
                        // interpolated value, and mixing the two makes the handle drift
                        RsProfile rp = profileAtZ((float)rs_rosStation(sel, travelPreview) * RS_STATION_Z);
                        float2 s = rs_uvToSec(p, asp, rs_rosWorld(rp.rin)) + grab;
                        r.pos = clamp(s, -0.34 * r.size.x, 0.34 * r.size.x);
                    }
                    else if (r.role == ROLE_FIX || r.role == ROLE_LIGHT)
                    {
                        uint sta = (r.role == ROLE_FIX) ? rs_staOfFix(idx) : rs_staOfLight(idx);
                        RsProfile pf = profileAtZ(rs_recZ(sta, r));
                        float2 s = rs_uvToSec(p, asp, rs_rosWorld(pf.rin)) - pf.c;
                        // recover BOTH the face and the along-face parameter from one drag: the
                        // nearest face plane wins, which is what makes dragging a block round a
                        // corner onto the next wall a single continuous gesture
                        int bestF = 0; float bestD = -1e9;
                        [unroll] for (int f = 0; f < 3; f++)
                        {
                            float a = pf.roll + (float)f * 2.0943951 + 1.5707963;
                            float dd = dot(s, float2(cos(a), sin(a)));
                            if (dd > bestD) { bestD = dd; bestF = f; }
                        }
                        bool isFlood = (r.role == ROLE_LIGHT && r.kind == (float)LK_FLOOD);
                        if (!isFlood)
                        {
                            float2 nOut, tg;
                            rs_face(pf, bestF, nOut, tg);
                            float lim = rs_faceLimit(pf.round_);
                            float umax = max((lim - 0.10) / RS_FACE_SPAN, 0.05);
                            r.grp = (float)bestF;
                            r.pos.y = clamp(dot(s, tg) / max(pf.rin * RS_FACE_SPAN, 1e-3), -umax, umax);
                            if (r.role == ROLE_FIX)
                                r.size.x = min(r.size.x, max(lim - RS_FACE_SPAN * abs(r.pos.y), 0.06));
                        }
                        else
                        {
                            // a corner lamp snaps to the nearest corner instead
                            int bc = 0; float bd = -1e9;
                            [unroll] for (int g2 = 0; g2 < 3; g2++)
                            {
                                float a = pf.roll + (float)g2 * 2.0943951 + 1.5707963 + 1.0471976;
                                float dd = dot(s, float2(cos(a), sin(a)));
                                if (dd > bd) { bd = dd; bc = g2; }
                            }
                            r.grp = 3.0 + (float)bc;
                        }
                    }
                    r.active = 1.0;
                    r.flags = (float)(((uint)r.flags) | F_EDITED);
                }
                else if (st == 3)
                {
                    float2 ic = float2((RS_INS_X0 + RS_INS_X1) * 0.5, (RS_INS_Y0 + RS_INS_Y1) * 0.5);
                    float2 ih = float2((RS_INS_X1 - RS_INS_X0) * 0.5, (RS_INS_Y1 - RS_INS_Y0) * 0.5);
                    float2 s = float2((p.x - ic.x) / ih.x, -(p.y - ic.y) / ih.y);
                    r.pos = clamp(s + grab, -1.2, 1.2);
                    r.flags = (float)(((uint)r.flags) | F_EDITED);
                }
                Plan[idx] = r;
            }
            else { dragOn = 0.0; }
        }
    }

    // Appearance-only refresh. These are NOT in the signature, so tuning the core never costs
    // the user a shaft they dragged into place.
    {
        RsRec cr = Plan[RS_CORE];
        uint cfl = (uint)cr.flags;
        cr.role  = ROLE_CORE;
        cr.kind  = (float)core_spokes;
        cr.tone  = core_gain;
        cr.grp   = core_ring;
        cr.phase = core_spin;
        if ((cfl & F_EDITED) == 0u) cr.pos = float2(core_x, core_y);
        cr.size  = float2(core_radius, max(core_radius * core_hot, 0.004));
        cr.active = 1.0;
        Plan[RS_CORE] = cr;
    }

    // selection flag is derived, never stored twice
    for (uint i = 0u; i < RS_RECORDS - 1u; i++)
    {
        RsRec r = Plan[i];
        uint f = (uint)r.flags;
        f = (sel > 0.5 && (uint)(sel - 1.0) == i) ? (f | F_SELECTED) : (f & ~F_SELECTED);
        r.flags = (float)f;
        Plan[i] = r;
    }

    // TRAVEL. Integrated against _DeltaTime, never rate x absolute time, so changing speed
    // mid-flight does not teleport the shaft. `phase` is the sweepable loop coordinate on top
    // of it: 0 -> 1 is exactly one seamless period.
    // `running` gates the integration rather than the speed, so pausing holds the shaft exactly
    // where it is and resuming carries straight on from there. Phase still scrubs while paused,
    // which is what makes Space the natural way to stop and edit a station.
    //
    // A HELD SCRUB OWNS TRAVEL. Without this the integration keeps advancing underneath the drag
    // and the playhead creeps away from the pointer while you hold it — the ruler would feel
    // like it was fighting you rather than driving. Releasing resumes from wherever you dropped
    // it, because travel is an absolute position and the scrub just wrote one.
    float scrubbing = (dragOn > 3.5) ? 1.0 : 0.0;
    travel = frac(travel / RS_LOOP_Z
                + _DeltaTime * flight_speed * running * (1.0 - scrubbing) / RS_LOOP_Z) * RS_LOOP_Z;
    float travelOut = frac(travel / RS_LOOP_Z + phase) * RS_LOOP_Z;

    // Tallies, and the one number the renderer cannot tell you: how many fixtures are currently
    // intruding into the flight tube.
    uint liveF = 0u, liveL = 0u, viol = 0u;
    for (uint a = 0u; a < RS_FIXES; a++)
    {
        RsRec r = Plan[RS_FIX_0 + a];
        if (r.active < 0.5) continue;
        liveF++;
        RsProfile pf = profileAtZ(rs_recZ(rs_staOfFix(RS_FIX_0 + a), r));
        if (rs_fixGeo(r, pf).clr < flight_clear) viol++;
    }
    for (uint b = 0u; b < RS_LIGHTS; b++) if (Plan[RS_LIGHT_0 + b].active > 0.5) liveL++;

    hdr.pos    = float2(sig, sel);
    hdr.size   = float2(dragOn, grab.x);
    hdr.role   = ROLE_HEADER;
    hdr.kind   = grab.y;
    hdr.seed   = salt;
    hdr.tone   = 2.0 + running;                       // init flag + transport state
    hdr.grp    = travel;                                            // persistent accumulator
    hdr.phase  = travelOut;                                         // what the renderer flies on
    // Packed for the preview AND for the renderer: liveF (0-36) | liveL (0-24) << 64 |
    // clearance violations (0-36) << 4096 | section style << 262144. The section shape is a
    // PLACEMENT decision, so the plan owns it and the renderer reads it from here rather than
    // carrying a second copy that could disagree.
    hdr.flags  = (float)liveF + (float)liveL * 64.0 + (float)viol * 4096.0
               + (float)section_style * 262144.0;
    hdr.active = 1.0;
    Plan[RS_HEADER] = hdr;
}
