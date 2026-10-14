// br_trip.hlsli -- the trip: what BR_Trip decides, and the functions that apply it. The renderer
// and BR_Trip's own editor include the same file, so the pattern previewed on the unfolded room
// is the pattern on the walls, and the swim drawn on the lattice is the swim on the rug.
//
// What a "replication" trip actually looks like (and what this does about it):
//   breathing   surfaces and objects swell and recede on slow cycles      -> object warps, texture breathing
//   drifting    textures swim, twist and drip IN PLACE (they never slide away) -> bounded texture swim
//   geometry    fine symmetric lattices emerge from plain surfaces, crawl and morph -> surface patterns
//   colour      hues deepen and slowly drift                              -> pattern tint + BR_Lens
//   (tracers -- trails behind moving light -- were tried in BR_Lens and removed: too much)
// Everything is driven by a TRIP CLOCK that BR_Trip integrates (tempo changes never jump a phase).
//
// CONTRACT: the including pass defines TRIP_REC(i), returning record i of the trip layout below
// (BR_Trip reads its own buffer; BR_Render reads the copy prep.hlsl made into its scene buffer).
//
// TRIP BUFFER (32 records)
//   0       HEADER  head (ROLE_TRIP, version, anchor count, seed)
//                   dims (dose x envelope, breathe, drift, melt)       effective amplitudes 0..1
//                   look (geometry, colour, push, motif)
//                        push = OVERDRIVE: how far the dose is set past 1 (0..2), times the
//                        envelope. 0..1 is the calibrated trip and stays exactly as it was; past
//                        it every channel's amplitude and spatial frequency grow (tripAmp,
//                        tripFreq) and BR_Trip runs the clock faster, so the room can be pushed
//                        too far on purpose.
//                   meta (trip time s, envelope 0..1, worst Lipschitz, tempo)
//   1..12   ANCHOR  head (ROLE_ANCHOR, kind, host, enabled)
//                   dims (world centre xyz, radius m)
//                   look (strength 0..1, rate Hz, phase rad, seed)
//                   meta (host normal xyz, slot)
//   13      DIAG    head (ROLE_TRIP_ED, 2, 0, 0) dims (per-kind counts B, M, S, G) look (F, alarms, 0, 0)
//   14      EDITOR  BR_Trip private      15  FROZEN signature      16..27  DELTAS per anchor slot
//   28      GLOBAL DELTA (BR_Trip private: re-roll, dose, motif, add, hold)
//   30      EXTRA   head (ROLE_TRIP_X, 0, 0, 0) dims (swim scale, flow clock, bloom clock, furniture)
//                   furniture: how much the furniture itself swells, slumps and twists (0 = it
//                   holds its shape), separate from the breathing of the field and the plants
//                   The clocks are INTEGRATED by BR_Trip (drift x dose and geometry x dose per trip
//                   second): anything that travels or turns reads them, so a slider never jumps it.
//                   (BR_Render's prep copies it to the scene slot after the anchors; a pass that
//                   reads the trip from somewhere other than TRIP_REC(30) defines TRIP_EXTRA_REC)
#ifndef BR_TRIP_HLSLI
#define BR_TRIP_HLSLI

#define TRIP_RECORDS  32
#define TRIP_HEADER   0
#define TRIP_ANCH0    1
#define TRIP_ANCH_MAX 12
#define TRIP_DIAG     13
#define TRIP_EDITOR   14
#define TRIP_FROZEN   15
#define TRIP_DELTA0   16
#define TRIP_EXTRA    30          // (28 is BR_Trip's global editor delta)
#ifndef TRIP_EXTRA_REC
#define TRIP_EXTRA_REC TRIP_REC(TRIP_EXTRA)
#endif

#define TK_NONE    0
#define TK_BREATHE 1      // swell and recede
#define TK_MELT    2      // sag and drip
#define TK_SWIRL   3      // twist and untwist
#define TK_BLOOM   4      // geometry blooms out of the surface in travelling rings
#define TK_FLOW    5      // textures stream across the surface and back
#define TK_COUNT   6

#define TH_FLOOR 0
#define TH_CEIL  1
#define TH_WALL0 2        // 2..5: walls S, E, N, W
#define TH_OBJ0  16       // 16 + furniture slot: the anchor lives on that piece

#define TM_GIRIH   0      // pattern motif (an exploration axis, shipped as an enum)
#define TM_LATTICE 1
#define TM_MANDALA 2
#define TM_MOIRE   3

struct BRTrip
{
    float dose, breathe, drift, melt;
    float geometry, colour, motif, push;
    float time, env, lip, tempo;
    float scale;          // the swim's spatial scale: 1 = the original broad swim, smaller = finer
    float flowT, bloomT;  // integrated clocks: how far things have travelled / turned
    float objects;        // the FURNITURE channel: object warps' share (1 when unlinked: as before)
    int anchors;
};
struct BRAnchor
{
    int kind, host, slot;
    bool on;
    float3 c;
    float radius, strength, rate, phase, seed;
    float3 n;
};

BRTrip tripDecode(BRRec r)
{
    BRTrip T;
    bool ok = abs(r.head.x - ROLE_TRIP) < 0.5;
    T.dose = ok ? saturate(r.dims.x) : 0.0; T.breathe = saturate(r.dims.y); T.drift = saturate(r.dims.z); T.melt = saturate(r.dims.w);
    T.geometry = saturate(r.look.x); T.colour = saturate(r.look.y); T.motif = r.look.w;
    T.push = (ok && abs(r.look.z) < 10.0) ? clamp(r.look.z, 0.0, 2.0) : 0.0;
    T.time = (abs(r.meta.x) < 1e6) ? r.meta.x : 0.0; T.env = saturate(r.meta.y); T.lip = max(r.meta.z, 1.0); T.tempo = r.meta.w;
    T.anchors = ok ? clamp((int)round(r.head.z), 0, TRIP_ANCH_MAX) : 0;
    T.scale = 1.0; T.flowT = 0.0; T.bloomT = 0.0; T.objects = 1.0;
    return T;
}
// OVERDRIVE multipliers: 1 up to a full dose, then growing with the push -- amplitudes to 4.2x
// and spatial frequencies to 2.6x at a dose of 3
float tripAmp(BRTrip T)  { return 1.0 + 1.6 * T.push; }
float tripFreq(BRTrip T) { return 1.0 + 0.8 * T.push; }
BRAnchor tripAnchorDecode(BRRec r)
{
    BRAnchor A;
    A.kind = (int)round(r.head.y); A.host = (int)round(r.head.z);
    A.on = abs(r.head.x - ROLE_ANCHOR) < 0.5 && r.head.w > 0.5 && A.kind > TK_NONE && A.kind < TK_COUNT;
    A.c = r.dims.xyz; A.radius = max(r.dims.w, 0.05);
    A.strength = saturate(r.look.x); A.rate = r.look.y; A.phase = r.look.z; A.seed = r.look.w;
    A.n = r.meta.xyz; A.slot = (int)round(r.meta.w);
    return A;
}
BRTrip tripHeader()
{
    BRTrip T = tripDecode(TRIP_REC(TRIP_HEADER));
    BRRec x = TRIP_EXTRA_REC;
    if (abs(x.head.x - ROLE_TRIP_X) < 0.5 && abs(x.dims.x) < 10.0)
    {
        T.scale = clamp(x.dims.x, 0.1, 2.0);
        T.flowT = (abs(x.dims.y) < 1e6) ? x.dims.y : 0.0;
        T.bloomT = (abs(x.dims.z) < 1e6) ? x.dims.z : 0.0;
        T.objects = saturate(x.dims.w);
    }
    return T;
}
BRAnchor tripAnchor(int i) { return tripAnchorDecode(TRIP_REC(TRIP_ANCH0 + i)); }

// The dose envelope over trip time: 0 steady, 1 waves (the trip swells and ebbs over a minute or
// so, never quite letting go), 2 come up (rises over two and a half trip minutes from a restart).
float tripEnvelope(int arcKind, float t)
{
    if (arcKind == 1) return 0.58 + 0.42 * (0.5 + 0.5 * sin(t * 6.2831853 / 78.0)) * (0.85 + 0.15 * sin(t * 6.2831853 / 23.0 + 1.1));
    if (arcKind == 2) return smoothstep(0.0, 1.0, t / 150.0);
    return 1.0;
}

// An anchor's pulse right now: -1..1 on its own cycle (rate is per trip-second).
float tripPulse(BRAnchor A, float t) { return sin(t * A.rate * 6.2831853 + A.phase); }
// How much of an anchor reaches p: a smooth gaussian, 1 at the centre, ~0 past 1.8 radii.
float tripFall(BRAnchor A, float3 p) { float3 d = p - A.c; return exp(-dot(d, d) / (A.radius * A.radius)); }

float2 tpRot(float2 p, float a) { float c = cos(a), s = sin(a); return float2(c * p.x - s * p.y, s * p.x + c * p.y); }
float tpSeg(float2 p, float2 a, float2 b) { float2 pa = p - a, ba = b - a; float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-9)); return length(pa - ba * h); }
float tpHash(float2 c) { return frac(sin(dot(c, float2(12.9898, 78.233))) * 43758.5453); }

// ---------------------------------------------------------------------------------------------
// SURFACE COORDINATES: the 2D frame a pattern is drawn in on each kind of surface, in metres.
// Walls: (along, height) with along increasing to the viewer's right; floor and ceiling: (x, z).
float2 tripSurfaceUV(float3 p, float3 n)
{
    float3 an = abs(n);
    if (an.y > 0.7) return p.xz;
    // a wall: its along axis is the viewer's right facing it (tangent = (n.z, -n.x) in xz)
    float2 tg = normalize(float2(n.z, -n.x) + 1e-6);
    return float2(dot(p.xz, tg), p.y);
}

// ---------------------------------------------------------------------------------------------
// GEOMETRY: the lattices that emerge from plain surfaces. Built with HANKIN'S METHOD, the
// construction behind historical Islamic star patterns: from the midpoint of every tile edge two
// rays leave at a "contact angle" and run until they meet their mirror images. Neighbouring tiles
// share those midpoints, so the lines join into ONE continuous lattice by construction, and the
// contact angle is a single lever that morphs the stars (hexagons -> six-point stars -> rosettes).
// Animating it per tile, on each tile's own phase, makes the whole lattice breathe and shift
// shape while staying joined. Returns x = line coverage (0..1, anti-aliased for a pixel footprint
// fp in metres), y = a hue coordinate 0..1 for the line tint, z = a cell term for a faint emboss.
float4 tpHex(float2 p, float size)
{
    // hex lattice, centre spacing `size`, neighbours at 0, 60, 120 ... degrees: local coords + id
    const float2 s = float2(1.0, 1.7320508);
    float2 q = p / size;
    float4 hc = floor(float4(q, q - float2(0.5, 1.0)) / s.xyxy) + 0.5;
    float4 h = float4(q - hc.xy * s, q - (hc.zw + 0.5) * s);
    return (dot(h.xy, h.xy) < dot(h.zw, h.zw)) ? float4(h.xy * size, hc.xy) : float4(h.zw * size, hc.zw + 0.5);
}
float4 tpSquare(float2 p, float size)
{
    float2 c = floor(p / size) + 0.5;
    return float4(p - c * size, c);
}
// distance to the Hankin rays of a regular tile with N edges, inradius h, contact angle theta
float tpHankin(float2 lp, float h, float N, float theta)
{
    float r = length(lp);
    float a = (r > 1e-7) ? atan2(lp.y, lp.x) : 0.0;
    float P = 6.2831853 / N;
    float a1 = a - P * floor(a / P);
    float a2 = P * 0.5 - abs(a1 - P * 0.5);          // fold: 0 = edge midpoint, P/2 = vertex
    float2 f = float2(cos(a2), sin(a2)) * r;
    float2 M = float2(h, 0.0);
    float2 d = float2(-sin(theta), cos(theta));
    float sLen = h / max(sin(theta) + cos(theta) / tan(P * 0.5), 1e-4);
    return tpSeg(f, M, M + d * sLen);
}
// distance to the tile's own edges
float tpTileEdge(float2 lp, float h, float N)
{
    float r = length(lp);
    float a = (r > 1e-7) ? atan2(lp.y, lp.x) : 0.0;
    float P = 6.2831853 / N;
    float a1 = a - P * floor(a / P);
    float a2 = P * 0.5 - abs(a1 - P * 0.5);
    return abs(r * cos(a2) - h);
}
// `fadeRef`: the footprint at which the lines stop being drawable (the renderer passes ~6 mm and
// lets finer-than-pixel lines fade; the editor passes a huge value and draws the structure).
float3 tripPattern(float2 uv, float t, float motif, float fp, float scale, float fadeRef)
{
    int m = clamp((int)round(motif), 0, 3);
    float w = max(0.0035, fp * 1.5);                   // line width: 3.5 mm, or a pixel and a half
    float fade = saturate(1.6 - fp / fadeRef);         // too fine for the pixel: fade, don't alias
    float2 p = tpRot(uv, 0.06 * sin(t * 0.017));       // the whole lattice turns, very slowly
    if (m == TM_MOIRE)
    {
        // two gratings a few degrees apart: the interference crawls as they turn
        float g = 0.022 * scale;
        float a1 = 0.07 * sin(t * 0.05), a2 = -0.05 + 0.06 * sin(t * 0.031 + 1.0);
        float2 p1 = tpRot(p, a1), p2 = tpRot(p, a2);
        float l1 = abs(frac(p1.x / g) - 0.5) * g, l2 = abs(frac(p2.x / (g * 1.04)) - 0.5) * g * 1.04;
        float rr = length(p - float2(0.7, 1.3) * scale);
        float l3 = abs(frac(rr / (g * 1.6) - t * 0.05) - 0.5) * g * 1.6;
        float d = min(min(l1, l2), l3 * 1.4);
        float lineM = 1.0 - smoothstep(w * 0.4, w * 1.2, d);
        float hue = frac(p1.x * 0.9 + p2.y * 0.7 + t * 0.011);
        return float3(lineM * fade * 0.8, hue, 0.5 + 0.5 * cos((p1.x / g - p2.x / (g * 1.04)) * 6.2831853));
    }
    bool hexT = (m != TM_LATTICE);
    float N = hexT ? 6.0 : 4.0;
    float size = ((m == TM_MANDALA) ? 0.62 : (hexT ? 0.30 : 0.26)) * scale;
    float4 cell = hexT ? tpHex(p, size) : tpSquare(p, size);
    float cellH = tpHash(cell.zw);
    float h = size * 0.5;
    // each tile breathes its contact angle on its own phase: stars open and close across the wall
    float th1 = (hexT ? 0.96 : 1.18) + 0.20 * sin(t * 0.21 + cellH * 6.2831853);
    float th2 = th1 + (hexT ? 0.40 : 0.34) * (0.8 + 0.2 * sin(t * 0.13 + cellH * 3.1));
    float d = min(tpHankin(cell.xy, h, N, th1), tpHankin(cell.xy, h, N, th2));
    float dEdge = tpTileEdge(cell.xy, h, N);
    if (m == TM_MANDALA)
    {
        // rings of rosettes inside each big tile, counter-turning
        float r = length(cell.xy);
        float rings = abs(frac(r / (size * 0.11) - t * 0.03) - 0.5) * size * 0.11;
        d = min(d, rings * 1.4 + max(r - h * 0.8, 0.0) * 3.0);
        d = min(d, tpHankin(tpRot(cell.xy, t * 0.04), h * 0.55, 12.0, th1 * 0.8));
    }
    // a finer self-similar layer a third the size, turned 30 degrees, drawn fainter
    float4 c2 = hexT ? tpHex(tpRot(p, 0.5235988) + 0.11, size / 3.0) : tpSquare(tpRot(p, 0.7853982) + 0.07, size / 3.0);
    float d2 = tpHankin(c2.xy, size / 6.0, N, th1 + 0.15);
    float w2 = w * 0.75;
    float lineA = 1.0 - smoothstep(w * 0.4, w * 1.2, d);
    float lineE = (1.0 - smoothstep(w * 0.3, w * 1.0, dEdge)) * 0.35;
    float lineB = (1.0 - smoothstep(w2 * 0.4, w2 * 1.2, d2)) * 0.4 * saturate(1.6 - fp / (fadeRef * 0.5));
    float hue = frac(cellH * 0.23 + length(cell.xy) / size * 0.9 + t * 0.017);
    float fill = saturate(1.0 - length(cell.xy) / h);
    return float3(max(max(lineA, lineE), lineB) * fade, hue, fill);
}
// jewel tones that drift through the hue coordinate: deep, not neon
float3 tripTint(float hue)
{
    float3 c = 0.55 + 0.45 * cos(6.2831853 * (hue + float3(0.0, 0.33, 0.67)));
    return lerp(dot(c, float3(0.3, 0.6, 0.1)).xxx, c, 0.75);
}

// How strongly geometry shows at p (0..1): a faint floor everywhere the trip is on, BLOOM anchors
// raising it in a steady pool plus a ring that travels outward on the anchor's own cycle, and a
// little wherever any anchor stirs the surface.
float tripGeometryAt(float3 p, BRTrip T)
{
    if (T.dose <= 0.0 || T.geometry <= 0.0) return 0.0;
    float s = 0.12;
    [loop] for (int i = 0; i < T.anchors; i++)
    {
        BRAnchor A = tripAnchor(i);
        if (A.on)
        {
            float f = tripFall(A, p);
            if (A.kind == TK_BLOOM)
            {
                float r = length(p - A.c);
                float ph = frac(T.time * A.rate + A.phase / 6.2831853);
                float ring = exp(-pow((r - A.radius * 1.6 * ph) / (0.22 * A.radius), 2.0)) * (1.0 - ph);
                s += 1.3 * A.strength * (f * (0.75 + 0.25 * tripPulse(A, T.time)) + ring * 0.8);
            }
            else s += A.strength * f * 0.25;
        }
    }
    return saturate(s * T.geometry * T.dose * 2.4 * tripAmp(T));
}

// ---------------------------------------------------------------------------------------------
// TEXTURE SWIM: where a surface's texture should be read from at p, so wood grain, the rug's
// ornament, the plaster and the fabric weave breathe, twist, drip and stream IN PLACE. Every
// offset is bounded (oscillating), so nothing slides off and nothing tears.
float3 tripSwim(float3 p, float3 n, BRTrip T)
{
    if (T.dose <= 0.0) return p;
    float t = T.time;
    float3 q = p;
    // everywhere: a slow swim along the surface. SWIM SCALE sets its size: at 1 the original
    // broad 60 cm eddies 3.5 cm deep; smaller is finer and shallower in proportion, so the
    // texture shimmers in place instead of being dragged round the room (overdrive: further, finer)
    float AMP = tripAmp(T), F = tripFreq(T);
    float SC = T.scale;
    float a = T.drift * T.dose * AMP;
    if (a > 0.0)
    {
        float3 pf = p * 1.6 * F / SC;
        float3 w = float3(brVN3(pf + float3(0.0, t * 0.10, 0.0)), brVN3(pf + float3(17.3, t * 0.12, 5.1)), brVN3(pf + float3(3.7, 9.1, t * 0.11)));
        q += (w - n * dot(w, n)) * 0.035 * a * SC;
    }
    [loop] for (int i = 0; i < T.anchors; i++)
    {
        BRAnchor A = tripAnchor(i);
        if (A.on && A.host < TH_OBJ0)
        {
            float3 d = p - A.c;
            float f = exp(-dot(d, d) / (A.radius * A.radius));
            float s = A.strength * T.dose * f * AMP;
            float ph = tripPulse(A, t);
            if (s > 1e-4)
            {
                if (A.kind == TK_SWIRL)
                {
                    // rings round the anchor turning against each other, and back: an eddy whose
                    // ring spacing follows the swim scale (one twist of the whole area dragged
                    // everything round with it)
                    float3 ax = normalize(A.n + 1e-6);
                    float3 dpl = d - ax * dot(d, ax);
                    float ang = s * 0.55 * ph * cos(length(dpl) / (0.16 * SC));
                    float3 rot = dpl * cos(ang) + cross(ax, dpl) * sin(ang);
                    q += (rot - dpl);
                }
                else if (A.kind == TK_BREATHE)
                {
                    q -= (d - n * dot(d, n)) * (s * 0.16 * ph);
                }
                else if (A.kind == TK_MELT)
                {
                    // read from higher up: the texture droops, in columns that each drip at their own pace
                    float col = 0.55 + 0.45 * brVN3(float3(tripSurfaceUV(p, n).x * 7.0 / SC, 0.0, A.seed * 9.0 + t * 0.05));
                    q.y += s * 0.13 * (0.6 + 0.4 * ph) * col * T.melt * 2.0;
                }
                else if (A.kind == TK_FLOW)
                {
                    float3 dirW = normalize(cross(A.n, float3(0.31, 0.93, 0.17)) + 1e-6);
                    q -= dirW * (s * 0.09 * SC * sin(t * A.rate * 6.2831853 + dot(d, dirW) * 4.0 / SC + A.phase));
                }
                else if (A.kind == TK_BLOOM)
                {
                    q -= (d - n * dot(d, n)) * (s * 0.07 * ph);
                }
            }
        }
    }
    return q;
}

// ---------------------------------------------------------------------------------------------
// OBJECT WARPS: a piece of furniture breathes, slumps or twists in its own LOCAL frame (feet stay
// on the floor). Split in two so the anchors are walked ONCE per piece per frame (prep.hlsl), not
// once per piece per march step:
//   tripObjectParams  -> float4 (breathe amplitude, breathe rate Hz, breathe phase, slump) + twist
//   tripObjectApply   -> the rest-space point to evaluate the model at, and L, the bound on how
//                        much the warp stretches distance (the caller divides by it: safe march)
float4 tripObjectParams(int slot, float oseed, BRTrip T, out float sAmp)
{
    sAmp = 0.0;
    if (T.dose <= 0.0) return float4(0.0, 0.11, 0.0, 0.0);
    float t = T.time;
    // every piece breathes a little, on its own phase; a BREATHE anchor on it breathes it more
    float bAmp = 0.014 * T.breathe, mAmp = 0.0;
    float bRate = 0.11, bPh = oseed * 6.2831853;
    [loop] for (int i = 0; i < T.anchors; i++)
    {
        BRAnchor A = tripAnchor(i);
        if (A.on && A.host == TH_OBJ0 + slot)
        {
            if (A.kind == TK_BREATHE) { bAmp += 0.045 * A.strength; bRate = A.rate; bPh = A.phase; }
            else if (A.kind == TK_MELT) mAmp += 0.09 * A.strength * (0.6 + 0.4 * tripPulse(A, t));
            else if (A.kind == TK_SWIRL) sAmp += 0.4 * A.strength * tripPulse(A, t);
        }
    }
    // overdrive swells, slumps and twists harder, capped where the march would starve: every
    // amplitude raises the warp's stretch bound, and the bound sets how short the steps get. The
    // FURNITURE channel scales all of it (0: every piece holds its shape)
    float AMP = tripAmp(T) * T.objects;
    sAmp = clamp(sAmp * T.dose * AMP, -1.6, 1.6);
    return float4(min(bAmp * T.dose * AMP, 0.12), bRate, bPh, min(mAmp * T.dose * (0.5 + T.melt) * AMP, 0.22));
}
// `rho` is how far the piece reaches from its own vertical axis. The twist stretches distance by
// rho * twist / height, and it is NOT always inside the footprint box: the arc lamp's dome hangs
// 1.4 m out from its foot, five times its box. Bounded by the box, the twist let the march step
// clean through the 4 mm dome and land on the arm inside it.
float3 tripObjectApply(float3 q, float3 S, float oseed, float4 bp, float sAmp, float rho, float t, out float L)
{
    L = 1.0;
    float H = max(S.y, 0.05);
    float u = saturate(q.y / H);
    float k = 1.0 + bp.x * sin(t * bp.y * 6.2831853 + bp.z);
    float3 r = q / k;
    L = max(k, 1.0 / k);
    if (abs(sAmp) > 1e-4)
    {
        // a twist that grows with height
        r.xz = tpRot(r.xz, -sAmp * u);
        L *= 1.0 + abs(sAmp) * max(rho, length(S.xz) * 0.5) / H;
    }
    if (bp.w > 1e-4)
    {
        // a slump: the top sinks, unevenly across the piece
        float wav = 0.7 + 0.3 * sin(q.x / max(S.x, 0.05) * 7.0 + t * 0.4 + oseed * 5.0);
        r.y += bp.w * H * u * u * wav;
        L *= 1.0 + bp.w * 2.4 + bp.w * H * 2.1 / max(S.x, 0.05);
    }
    return r;
}
// The largest a piece can move under its warp (to grow its bounding sphere).
float tripObjectReach(float3 S, float4 bp, float sAmp)
{
    return (bp.x + bp.w + abs(sAmp) * 0.5) * length(S) + ((bp.x + bp.w + abs(sAmp) > 0.0) ? 0.01 : 0.0);
}

#endif
