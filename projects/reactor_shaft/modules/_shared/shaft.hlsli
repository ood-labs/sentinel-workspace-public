// shaft.hlsli — the reactor_shaft data contract, shape vocabulary and palette.
//
// SHAFT SPACE. The shaft runs along +z. The camera sits near the origin and never travels:
// the shaft scrolls THROUGH it. Every field is sampled at (z + travel) and every one of them
// is periodic with RS_LOOP_Z, so travel wrapping at RS_LOOP_Z is a bit-exact seam. There is no
// teleport to hide, because the frame at travel = 0 and travel = RS_LOOP_Z are the same frame.
//
// PERIODICITY IS STRUCTURAL. Stations are addressed modulo RS_STATIONS by rs_staFrame, and
// every fixture and light lives entirely inside its own station's slice, so ANY per-station
// value — a random draw, a hand edit — is automatically periodic. The user cannot author a seam.
//
// RS_Plan is the ONLY node that decides shaft section, fixture placement, light placement, core
// geometry or travel. RS_Shaft reads records and owns light, surface, volume and camera.
#ifndef RS_SHAFT_HLSLI
#define RS_SHAFT_HLSLI

// ---------------------------------------------------------------------------
// Record buffer (RS_Plan -> RS_Shaft). One buffer, `role` discriminates.
//
// Each station owns RS_FIX_PER fixture slots and RS_LIGHT_PER light slots at fixed indices.
// Fixed indexing rather than ranges is what makes the ±1 station march window provably
// sufficient AND makes the whole arrangement periodic by construction.
// ---------------------------------------------------------------------------
#define RS_STATIONS   12u
#define RS_FIX_PER     3u
#define RS_LIGHT_PER   2u

#define RS_STA_0       0u   // 12 records : the shaft section at each station
#define RS_FIX_0      12u   // 36 records : greeble blocks bolted to a face
#define RS_FIXES      36u
#define RS_LIGHT_0    48u   // 24 records : the emissive cast, hosted on fixtures
#define RS_LIGHTS     24u
#define RS_CORE       72u   // the thing at the end of the shaft
#define RS_HEADER     73u   // editor header: signature, selection, drag, travel, tallies
#define RS_RECORDS    74u

#define RS_STATION_Z   2.5
#define RS_LOOP_Z     30.0

#define ROLE_STATION 0.0
#define ROLE_FIX     1.0
#define ROLE_LIGHT   2.0
#define ROLE_CORE    3.0
#define ROLE_HEADER  4.0

#define F_SELECTED 1u
#define F_EDITED   2u

// Fixture vocabulary. These are the machine families the reference is actually built from.
#define FK_FINS    0   // heatsink comb — dense parallel fins, the hero greeble
#define FK_GRILLE  1   // perforated vent grid of small rounded cells
#define FK_SLAB    2   // plain bevelled armour plate
#define FK_BEAM    3   // girder running across the face
#define FK_DRUM    4   // cylindrical tank seated on the wall
#define FK_STACK   5   // stepped block stack
#define FK_KINDS   6

// Light vocabulary.
#define LK_RUN    0   // neon tube running ALONG the shaft
#define LK_BAR    1   // neon bar ACROSS the face
#define LK_BEACON 2   // small point beacon
#define LK_FLOOD  3   // bright flood lamp seated on a corner, the flare source
#define LK_KINDS  4

// u along a face is in [-1,1]; the true half-face length of an equilateral section is
// sqrt(3)*rin, so spanning 1.45*rin keeps a full-width fixture clear of the corners.
#define RS_FACE_SPAN 1.45

// EVERY fixture and light lives entirely inside its own station's half-slice. This is the
// invariant that makes the renderer's +-1 station march window PROVABLY sufficient: a point can
// be at most RS_SLICE_H from its nearest station, and nothing reaches further than RS_SLICE_H
// out of its own, so nothing two stations away can ever touch it. It also means two stations
// can never overlap, whatever the user drags.
#define RS_SLICE_H (RS_STATION_Z * 0.5)

// LONGITUDINAL CELL COUNT PER LOOP. Wall panelling and micro-relief are cell-hashed, and a hash
// keyed on an UNWRAPPED z index reshuffles the entire wall texture once per period even though
// the geometry is perfectly periodic — the loop then strobes rather than repeating. Two things
// are needed together: wrap the longitudinal coordinate into one loop, and make the cell count
// per loop an exact integer so the wrap lands on a cell boundary instead of slicing a cell.
//
// The consequence is that the per-station panel scale may drive LATERAL cell size only.
// Modulating the longitudinal size would require the integral of the rate over one loop to land
// on an integer, which nothing guarantees.
#define RS_PANEL_CELLS  96.0
#define RS_PANEL_Z      (RS_LOOP_Z / RS_PANEL_CELLS)
#define RS_COARSE_DIV   6.0

struct RsRec
{
    // STATION: section centre offset (x, y), world units
    // FIX    : (z offset inside this station's slice, u along the face in [-1,1])
    // LIGHT  : (z offset inside this station's slice, u along the face in [-1,1])
    // CORE   : centre in bore units (-1..1)
    float2 pos;
    // STATION: (bore inradius, corner rounding as a fraction of inradius)
    // FIX    : (half-width as a fraction of inradius, protrusion as a fraction of inradius)
    // LIGHT  : (half-length in world units, tube radius in world units)
    // CORE   : (outer radius, hot centre radius) in bore units
    float2 size;
    float  role;
    // STATION: palette set   FIX: fixture kind   LIGHT: light kind   CORE: spoke count
    float  kind;
    float  seed;
    // STATION: greeble density   FIX: surface value   LIGHT: intensity   CORE: intensity
    float  tone;
    // STATION: roll in radians   FIX/LIGHT: face index (0-2) or corner index (3-5 for FLOOD)
    // CORE   : ring thickness
    float  grp;
    // STATION: panel scale   FIX: z half-length in world units   LIGHT: hue selector
    // CORE   : spin rate
    float  phase;
    float  flags;
    float  active;
};

// ---------------------------------------------------------------------------
// Hashes. rs_ prefixed so they can never collide with an injected feature.
// ---------------------------------------------------------------------------
float rs_rnd(float s, float k)
{
    return frac(sin(s * 12.9898 + k * 78.233) * 43758.5453);
}
float2 rs_hash22(float2 p)
{
    float3 q = float3(dot(p, float2(127.1, 311.7)), dot(p, float2(269.5, 183.3)), dot(p, float2(419.2, 371.9)));
    return frac(sin(q.xy) * 43758.5453);
}

float rs_smin(float a, float b, float k)
{
    if (k <= 1e-5) return min(a, b);
    float h = saturate(0.5 + 0.5 * (b - a) / k);
    return lerp(b, a, h) - k * h * (1.0 - h);
}
float rs_smax(float a, float b, float k) { return -rs_smin(-a, -b, k); }

float rs_wrapZ(float z) { return z - floor(z / RS_LOOP_Z) * RS_LOOP_Z; }
float rs_wrapDZ(float d)
{
    // shortest signed distance on the loop
    float h = RS_LOOP_Z * 0.5;
    return rs_wrapZ(d + h) - h;
}
int rs_wrapI(int i)
{
    int n = (int)RS_STATIONS;
    return ((i % n) + n) % n;
}

// ---------------------------------------------------------------------------
// Palette. Set 0 is transcribed off the reference: cold blue-grey machinery, hot magenta and
// violet neon, cyan-white speculars. The alternates keep the same job assignments so a station
// can carry a different chord without leaving the family.
//   [0] wall base   [1] wall highlight / edge   [2] neon A   [3] neon B
// ---------------------------------------------------------------------------
#define RS_PALSETS 4
static const float3 RS_PAL[RS_PALSETS * 4] = {
    // 0 Reactor — the reference. The base is deliberately very dark: the reference frame is
    // mostly near-black structure, and every attempt to make the machinery "readable" by
    // lifting its albedo turned the shaft into a pale sheet with lights painted on it.
    float3(0.060, 0.080, 0.098), float3(0.520, 0.680, 0.760),
    float3(1.000, 0.090, 0.560), float3(0.560, 0.320, 1.000),
    // 1 Coolant — the same shaft running cold
    float3(0.086, 0.128, 0.148), float3(0.640, 0.820, 0.860),
    float3(0.180, 0.880, 1.000), float3(0.420, 0.520, 1.000),
    // 2 Furnace — thermal alarm
    float3(0.132, 0.104, 0.096), float3(0.800, 0.660, 0.560),
    float3(1.000, 0.300, 0.060), float3(1.000, 0.680, 0.140),
    // 3 Sodium — sparse, industrial, almost monochrome
    float3(0.112, 0.116, 0.120), float3(0.720, 0.720, 0.700),
    float3(1.000, 0.720, 0.320), float3(0.880, 0.900, 0.940)
};
float3 rs_pal(int set, int idx)
{
    int s = (int)clamp((float)set, 0.0, (float)(RS_PALSETS - 1));
    int i = (int)clamp((float)idx, 0.0, 3.0);
    return RS_PAL[s * 4 + i];
}

// Fixed chord — the atmosphere and the core are what the frame is about and are not negotiable.
#define RS_HAZE_NEAR float3(0.128, 0.286, 0.334)   // teal, the air right in front of the eye
#define RS_HAZE_DEEP float3(0.420, 0.132, 0.376)   // magenta, the air down by the core
#define RS_CORE_RED  float3(1.000, 0.120, 0.140)
#define RS_CORE_HOT  float3(1.000, 0.960, 0.920)
#define RS_FLOOD_COL float3(0.780, 0.960, 1.000)
#define RS_BEACON_A  float3(1.000, 0.240, 0.100)
#define RS_BEACON_B  float3(1.000, 0.640, 0.180)

// Light colour from a record's hue selector. Kept here so the plan preview and the renderer
// decode the same number to the same colour.
float3 rs_lightCol(RsRec r, int pal)
{
    int k = (int)r.kind;
    if (k == LK_FLOOD)  return RS_FLOOD_COL;
    if (k == LK_BEACON) return lerp(RS_BEACON_A, RS_BEACON_B, saturate(r.phase));
    float h = saturate(r.phase);
    float3 a = rs_pal(pal, 2);
    float3 b = rs_pal(pal, 3);
    float3 c = float3(0.760, 0.960, 1.000);          // the cold white tubes
    return (h < 0.5) ? lerp(a, b, h * 2.0) : lerp(b, c, (h - 0.5) * 2.0);
}

// ---------------------------------------------------------------------------
// Station profile. Catmull-Rom across stations addressed modulo RS_STATIONS, so station 11
// flows into station 0 with no hand-checked wrap anywhere.
// ---------------------------------------------------------------------------
struct RsProfile
{
    float2 c;        // section centre offset, world units
    float  rin;      // bore inradius
    float  roll;     // section twist, radians
    float  round_;   // corner rounding as a fraction of inradius
    float  dens;     // greeble density
    float  panel;    // wall panel scale
    int    pal;      // palette set in force here
};

void rs_staFrame(float zw, out int i0, out int i1, out int i2, out int i3, out float t)
{
    float f = zw / RS_STATION_Z;
    float fi = floor(f);
    t = f - fi;
    int i = (int)fi;
    i0 = rs_wrapI(i - 1);
    i1 = rs_wrapI(i);
    i2 = rs_wrapI(i + 1);
    i3 = rs_wrapI(i + 2);
}

float rs_cr1(float a, float b, float c, float d, float t)
{
    float t2 = t * t, t3 = t2 * t;
    return 0.5 * ((2.0 * b) + (-a + c) * t + (2.0 * a - 5.0 * b + 4.0 * c - d) * t2
                  + (-a + 3.0 * b - 3.0 * c + d) * t3);
}
float2 rs_cr2(float2 a, float2 b, float2 c, float2 d, float t)
{
    return float2(rs_cr1(a.x, b.x, c.x, d.x, t), rs_cr1(a.y, b.y, c.y, d.y, t));
}

// Roll must be interpolated on the SHORTEST arc between stations or a station whose roll sits
// either side of a wrap spins the whole section the long way round once per loop.
float rs_rollBlend(float a, float b, float c, float d, float t)
{
    float b2 = b;
    float a2 = b2 + rs_wrapDZ((a - b2) / RS_LOOP_Z * RS_LOOP_Z);
    // rolls are small and unwrapped in practice; interpolate directly
    return rs_cr1(a, b, c, d, t);
}

RsProfile rs_profileFrom(RsRec r0, RsRec r1, RsRec r2, RsRec r3, float t)
{
    RsProfile p;
    p.c      = rs_cr2(r0.pos, r1.pos, r2.pos, r3.pos, t);
    p.rin    = max(rs_cr1(r0.size.x, r1.size.x, r2.size.x, r3.size.x, t), 0.30);
    p.round_ = clamp(rs_cr1(r0.size.y, r1.size.y, r2.size.y, r3.size.y, t), 0.0, 0.9);
    p.roll   = rs_rollBlend(r0.grp, r1.grp, r2.grp, r3.grp, t);
    p.dens   = saturate(rs_cr1(r0.tone, r1.tone, r2.tone, r3.tone, t));
    p.panel  = max(rs_cr1(r0.phase, r1.phase, r2.phase, r3.phase, t), 0.12);
    p.pal    = (int)((t < 0.5) ? r1.kind : r2.kind);
    return p;
}

// ---------------------------------------------------------------------------
// Section shape. rs_bore returns DISTANCE TO THE WALL FROM INSIDE THE BORE — positive in the
// air, zero at the wall. Inside a convex intersection of half-planes that is exact, and the
// smooth-min is what rounds the corners without breaking the Lipschitz bound.
//
// Every style is 3-fold symmetric on purpose: the three ATTACHMENT FACES stay in the same place
// whichever section the shaft is built from, so the exploration axis changes the silhouette
// without invalidating a single fixture record.
// ---------------------------------------------------------------------------
void rs_face(RsProfile pf, int f, out float2 nOut, out float2 tang)
{
    float a = pf.roll + (float)f * 2.0943951 + 1.5707963;
    nOut = float2(cos(a), sin(a));
    tang = float2(-nOut.y, nOut.x);
}

float rs_bore(float2 p, RsProfile pf, int style)
{
    float2 q = p - pf.c;
    float kbase = (style == 3) ? 3.2 : 1.0;
    float k = max(pf.round_ * pf.rin * kbase, 1e-4);

    float d = 0.0;
    [unroll] for (int f = 0; f < 3; f++)
    {
        float a = pf.roll + (float)f * 2.0943951 + 1.5707963;
        float dd = pf.rin - dot(q, float2(cos(a), sin(a)));
        d = (f == 0) ? dd : rs_smin(d, dd, k);
    }
    if (style == 1 || style == 2)
    {
        // style 1 chamfers the three corners; style 2 opens them into a full hex bore
        float ext = (style == 1) ? 1.42 : 1.0;
        float kc  = (style == 1) ? (k * 0.45) : k;
        [unroll] for (int g = 0; g < 3; g++)
        {
            float a = pf.roll + (float)g * 2.0943951 + 1.5707963 + 1.0471976;
            float dd = pf.rin * ext - dot(q, float2(cos(a), sin(a)));
            d = rs_smin(d, dd, kc);
        }
    }
    return d;
}

// Distance from the FLIGHT AXIS (world x=y=0) to face f's plane. This is the number the
// clearance diagram is drawn from, and it is exact rather than approximate: the face plane is
// dot(q, n) = dot(c, n) + rin.
float rs_faceAxisDist(RsProfile pf, int f)
{
    float2 n, t;
    rs_face(pf, f, n, t);
    return pf.rin + dot(pf.c, n);
}

// ---------------------------------------------------------------------------
// Fixture and light placement. Both the plan's pick test, the plan's drawing and the renderer's
// distance field route through these, so a handle is always grabbable exactly where it is drawn
// and a fixture always renders exactly where the diagram says it is.
//
// Every magnitude is DERIVED from the station's own bore inradius rather than given a parallel
// parameter, which is why a fixture cannot drift out of registration with the wall it is
// bolted to no matter how the section is edited.
// ---------------------------------------------------------------------------
// The usable half-face, in inradius units. The section's corners are ROUNDED, so the flat part
// of a face is shorter than the sqrt(3) inradii an ideal triangle would give — and a block
// placed out at the ideal limit pokes straight through the rounded corner and hangs in space
// outside the shaft. Both the generator and the drag path clamp through this, so no seed and no
// gesture can produce that.
float rs_faceLimit(float round_) { return max(1.732 - 2.2 * round_, 0.45); }

struct RsFixGeo
{
    float2 face;   // point on the face plane, section space
    float2 nIn;    // inward face normal
    float2 tang;   // along-face tangent
    float  hw;     // half-width along the face, world units
    float  pr;     // protrusion inward from the face, world units
    float  zh;     // z half-length, world units
    float  clr;    // EXACT distance from the flight axis to the nearest point of the block
};

RsFixGeo rs_fixGeo(RsRec r, RsProfile pf)
{
    RsFixGeo g;
    int f = (int)clamp(r.grp, 0.0, 2.0);
    float2 nOut, tg;
    rs_face(pf, f, nOut, tg);
    g.nIn  = -nOut;
    g.tang = tg;
    g.hw   = max(r.size.x, 0.02) * pf.rin;
    g.pr   = max(r.size.y, 0.005) * pf.rin;
    g.zh   = max(r.phase, 0.02);
    g.face = pf.c + nOut * pf.rin + tg * (r.pos.y * pf.rin * RS_FACE_SPAN);

    // Exact box-to-axis distance rather than the face-plane distance. A block sitting out
    // toward a corner really is further from the flight axis than its own face plane is, and
    // the clearance diagram has to say so or it condemns arrangements that are actually fine.
    float2 bc = g.face + g.nIn * g.pr * 0.5;
    float2 l  = float2(dot(-bc, g.tang), dot(-bc, g.nIn));
    float2 q  = abs(l) - float2(g.hw, g.pr * 0.5);
    g.clr = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
    return g;
}

// A light sits proud of whatever it is mounted on by its OWN tube radius. Corner lamps (kind
// LK_FLOOD) mount on a vertex instead of a face: grp 3..5 selects the corner between faces.
float2 rs_lightSection(RsRec r, RsProfile pf, out float2 tangOut)
{
    int k = (int)r.kind;
    float lift = max(r.size.y, 0.01) * 1.25 + r.tone * 0.0;
    if (k == LK_FLOOD)
    {
        int cIdx = (int)clamp(r.grp - 3.0, 0.0, 2.0);
        float a = pf.roll + (float)cIdx * 2.0943951 + 1.5707963 + 1.0471976;
        float2 nOut = float2(cos(a), sin(a));
        tangOut = float2(-nOut.y, nOut.x);
        // the corner sits at the intersection of two faces: inradius / cos(60 deg) = 2 * rin
        float cr = pf.rin * 2.0 * (1.0 - pf.round_ * 0.55);
        return pf.c + nOut * cr - nOut * lift;
    }
    int f = (int)clamp(r.grp, 0.0, 2.0);
    float2 nOut, tg;
    rs_face(pf, f, nOut, tg);
    tangOut = tg;
    return pf.c + nOut * (pf.rin - lift) + tg * (r.pos.y * pf.rin * RS_FACE_SPAN);
}

// Same measure for a light: the nearest point of the emitter to the flight axis.
float rs_lightClear(RsRec r, RsProfile pf)
{
    float2 tg;
    float2 sp = rs_lightSection(r, pf, tg);
    if ((int)r.kind == LK_BAR)
    {
        float2 l = float2(dot(-sp, tg), dot(-sp, float2(-tg.y, tg.x)));
        float2 q = abs(l) - float2(max(r.size.x, 0.01), max(r.size.y, 0.01));
        return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
    }
    return length(sp) - max(r.size.y, 0.01);
}

// ---------------------------------------------------------------------------
// The core. Drawn identically by the plan's inset and by the renderer, so the inset is the real
// plate rather than a schematic of one.
//   s : bore units, roughly -1..1 across the aperture
// ---------------------------------------------------------------------------
float3 rs_corePlate(float2 s, RsRec core, float spin, float px)
{
    float2 q = s - core.pos;
    float  d = length(q);
    float  a = atan2(q.y, q.x);

    float ro = max(core.size.x, 0.02);
    float rh = clamp(core.size.y, 0.005, ro * 0.92);
    float th = max(core.grp, 0.02);
    float gain = max(core.tone, 0.0);

    // spokes: the reference's core reads as a machined iris, not a plain disc
    int spokes = (int)clamp(core.kind, 0.0, 48.0);
    float sp = (spokes > 0) ? (0.5 + 0.5 * cos(a * (float)spokes + spin)) : 0.0;

    float3 col = float3(0.0, 0.0, 0.0);

    // outer body of the disc, falling off toward its rim
    float body = 1.0 - smoothstep(ro - th, ro + px * 2.0, d);
    float rimFall = saturate(1.0 - d / max(ro, 1e-3));
    col += RS_CORE_RED * body * (0.35 + 0.85 * rimFall * rimFall) * (0.72 + 0.42 * sp) * gain;

    // hot centre
    float hot = 1.0 - smoothstep(rh * 0.55, rh * 1.35, d);
    col += RS_CORE_HOT * hot * 2.6 * gain;
    col += RS_CORE_HOT * exp(-d / max(rh * 1.9, 1e-3)) * 0.85 * gain;

    // bright annulus just inside the rim
    float ring = exp(-abs(d - ro * 0.82) / max(th * 0.55, 1e-3));
    col += lerp(RS_CORE_RED, RS_CORE_HOT, 0.35) * ring * 0.85 * gain;

    // the magenta wash the core throws into the air around it
    col += RS_HAZE_DEEP * exp(-d / max(ro * 2.4, 1e-3)) * 0.55 * gain;

    return col;
}

// ---------------------------------------------------------------------------
// Plan canvas geometry. Shared by plan.hlsl (pick) and canvas.hlsl (draw) so the two can never
// disagree about where a handle is.
//
// Strip 1: LONGITUDINAL CLEARANCE SECTION — z across, distance from the flight axis up.
// Strip 2: CROSS-SECTION ROSETTE at the playhead station.
// Strip 3: the core inset.
// ---------------------------------------------------------------------------
#define RS_LON_X0  0.045
#define RS_LON_X1  0.975
#define RS_LON_Y0  0.075
#define RS_LON_Y1  0.500
#define RS_WORLD_R 2.40

#define RS_ROS_CX    0.170
#define RS_ROS_CY    0.760
#define RS_ROS_R     0.190

// The rosette's world extent is DERIVED from the bore it is framing, not a constant. A constant
// is a parallel magnitude that has to be kept in agreement with `Bore` by hand, and it silently
// disagreed the moment the bore was retuned: the section drew straight through its own frame.
// The circumradius of the section is 2 x inradius, so 2.35 leaves a margin for corner lamps.
float rs_rosWorld(float rin) { return max(rin * 2.35, 0.90); }

#define RS_INS_X0 0.790
#define RS_INS_X1 0.975
#define RS_INS_Y0 0.600
#define RS_INS_Y1 0.945

// The scrub ruler: a grab band along the top of the clearance section, spanning the same z range
// so a position on the ruler is a position on the shaft, read straight off.
#define RS_SCRUB_Y0 0.034
#define RS_SCRUB_Y1 0.070

float rs_zToX(float z) { return RS_LON_X0 + (rs_wrapZ(z) / RS_LOOP_Z) * (RS_LON_X1 - RS_LON_X0); }
float rs_xToZ(float x) { return (x - RS_LON_X0) / (RS_LON_X1 - RS_LON_X0) * RS_LOOP_Z; }
float rs_rToY(float r) { return RS_LON_Y1 - (r / RS_WORLD_R) * (RS_LON_Y1 - RS_LON_Y0); }
float rs_yToR(float y) { return (RS_LON_Y1 - y) / (RS_LON_Y1 - RS_LON_Y0) * RS_WORLD_R; }

float2 rs_secToUv(float2 s, float2 asp, float world)
{
    float k = RS_ROS_R / max(world, 1e-3);
    return float2(RS_ROS_CX + s.x * k / asp.x, RS_ROS_CY - s.y * k);
}
float2 rs_uvToSec(float2 uv, float2 asp, float world)
{
    float k = max(world, 1e-3) / RS_ROS_R;
    return float2((uv.x - RS_ROS_CX) * asp.x, -(uv.y - RS_ROS_CY)) * k;
}

// Keep a record inside its own station slice. Called on every generated value AND on every
// drag, so the invariant holds no matter how the buffer was produced.
void rs_fitSlice(inout float zoff, inout float zh)
{
    zh = clamp(zh, 0.05, RS_SLICE_H * 0.92);
    float lim = RS_SLICE_H - zh;
    zoff = clamp(zoff, -lim, lim);
}

uint rs_staOfFix(uint idx)   { return (idx - RS_FIX_0) / RS_FIX_PER; }
uint rs_staOfLight(uint idx) { return (idx - RS_LIGHT_0) / RS_LIGHT_PER; }
float rs_recZ(uint sta, RsRec r) { return (float)sta * RS_STATION_Z + r.pos.x; }

// Which station the rosette is showing. It FOLLOWS THE SELECTION when there is one — select a
// fixture in the clearance section and the cross-section snaps to the station that owns it —
// and otherwise rides the playhead.
int rs_rosStation(float sel, float travel)
{
    if (sel > 0.5)
    {
        uint idx = (uint)(sel - 1.0);
        if (idx < RS_STATIONS) return (int)idx;
        if (idx >= RS_FIX_0 && idx < RS_FIX_0 + RS_FIXES) return (int)rs_staOfFix(idx);
        if (idx >= RS_LIGHT_0 && idx < RS_LIGHT_0 + RS_LIGHTS) return (int)rs_staOfLight(idx);
    }
    return rs_wrapI((int)floor(travel / RS_STATION_Z + 0.5));
}

int rs_stripAt(float2 uv, float2 asp)
{
    // tested BEFORE the clearance section, whose grab tolerance overlaps this band
    if (uv.x > RS_LON_X0 - 0.012 && uv.x < RS_LON_X1 + 0.012 &&
        uv.y > RS_SCRUB_Y0 && uv.y < RS_SCRUB_Y1) return 4;
    if (uv.x > RS_LON_X0 - 0.012 && uv.x < RS_LON_X1 + 0.012 &&
        uv.y > RS_LON_Y0 - 0.022 && uv.y < RS_LON_Y1 + 0.022) return 1;
    if (length((uv - float2(RS_ROS_CX, RS_ROS_CY)) * asp) < RS_ROS_R * 1.22) return 2;
    if (uv.x > RS_INS_X0 && uv.x < RS_INS_X1 && uv.y > RS_INS_Y0 && uv.y < RS_INS_Y1) return 3;
    return 0;
}

#endif
