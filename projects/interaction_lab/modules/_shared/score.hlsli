// score.hlsli - the Score contract: a show of acts on one clock, the camera marks of every RAIL act
// and the items of every CARD, the hall the camera travels through, and what the Score resolves at
// the playhead for the program.
//
// The Score (editor) writes it into its state buffer and publishes that buffer as "Score". The
// Program reads the resolved records (which act shows, the hand-off, the light, the card) from it.
// The camera itself travels as the Score's control outputs into the Program's INTERNAL camera
// (expressions on camera_pos_x/y/z, camera_yaw, camera_pitch, camera_fov), so the Program renders
// through the host camera like any other 3D module.
//
// Records (float4; integers are stored as exact float values):
//   0        P0    (acts in the show 1..8, -, -, -)                                             saved
//   1        PM    (format magic, -, -, -)                                                      saved
//   2 + 14a  act a (a < 8), in show order:                                                      saved
//     +0  A  (kind 0 rail | 1 card, duration s, hand-off 0 cut | 1 dip | 2 glide, hand-off s)
//     +1  B  (light 0 day | 1 dusk | 2 night, word 0..5 (cards), marks 2..6 (rails), -)
//     +2 + 2m  rail mark m, in time order: (eye x, y, z, at: 0..1 of the act),
//              then (target x, y, z, field of view in degrees, vertical)
//              card item m (m < 3: 0 the word, 1 a disc, 2 a bar): (x, y, size, shown 0 | 1),
//              then (-, -, -, -). Stage units: the card is 1 tall and 16:9 wide, origin at its
//              centre, y up; size = the word's cap height, the disc's radius, the bar's half length
//   114      V0    (time s, playing 0 | 1, loop 0 the show | 1 the act, working magic)
//   115..120 the editor's working state (Score/sc.hlsli); never saved
//   121      R0    (act A showing, act B coming, hand-off progress 0..1, hand-off kind)   <- program
//   122      R1    (time into A, -, show length s, acts)                                  <- program
//   123      R2    the camera's eye (x, y, z, fov degrees)                                <- program
//   124      R3    the camera's target (x, y, z, -)                                       <- program
//   125      R4    (yaw rad, pitch rad, -, -): the internal camera's own convention
//   126      R5    (light A, light B, kind A, kind B)                                     <- program
//
// A hand-off occupies the LAST `hand-off s` of the act it leaves: cut (none), dip (fade through
// black; the next act appears at the darkest point), glide (between two rails the camera blends
// from this act's pose into the next act's first mark - one camera throughout; with a card it
// dissolves). The last act hands off to the first only while the show loops.
//
// The hall (metres; y up, the hall runs along +z): a stone floor 12 m wide and 40 m long, walls 6 m
// high, open to the sky, two rows of nine columns, and three works on plinths down the middle - a
// sphere (z 12), a standing ring (z 22) and a stack of turned blocks (z 32). A camera that faces +z
// has +x on its right (yaw = atan2(dir.x, dir.z), pitch = asin(dir.y)).
#ifndef SCORE_HLSLI
#define SCORE_HLSLI

#ifndef SC_BUF
#error define SC_BUF (the Score buffer: StructuredBuffer or RWStructuredBuffer of float4) before including score.hlsli
#endif

#define SC_ACTS     8u
#define SC_ACTREC   14u
#define SC_MARKS    6u
#define SC_ITEMS    3u
#define SC_WORDS    6u
#define SC_P0       0u
#define SC_PM       1u
#define SC_ACT0     2u
#define SC_SAVED    114u
#define SC_V0       114u
#define SC_R0       121u
#define SC_R1       122u
#define SC_R2       123u
#define SC_R3       124u
#define SC_R4       125u
#define SC_R5       126u
#define SC_MAGIC    1313.0

#define SC_RAIL     0u
#define SC_CARD     1u
#define SC_CUT      0u
#define SC_DIP      1u
#define SC_GLIDE    2u
#define SC_DAY      0u
#define SC_DUSK     1u
#define SC_NIGHT    2u

// ---------------------------------------------------------------- the hall
#define SC_HALL_W    6.0      // walls at x = +-6
#define SC_HALL_L    40.0     // the floor runs z 0..40
#define SC_WALL_H    6.0
#define SC_WALL_T    0.4
#define SC_COL_X     3.5      // the two rows of columns
#define SC_COL_Z0    4.0      // the first column; then every SC_COL_DZ
#define SC_COL_DZ    4.0
#define SC_COL_N     9u
#define SC_COL_R     0.32
#define SC_COL_H     5.2
#define SC_PLINTH_H  1.0
#define SC_PLINTH_HW 0.6
#define SC_SPHERE_R  0.8
#define SC_RING_R    0.9      // the standing ring: its circle, and its tube
#define SC_RING_T    0.2
float scWorkZ(uint w) { return 12.0 + 10.0 * (float)w; }
float scColZ(uint i)  { return SC_COL_Z0 + SC_COL_DZ * (float)i; }
// the stack: three blocks, each half size and turn (radians about y), resting on the one below
float4 scBlock(uint b)
{
    float hw = (b == 0u) ? 0.45 : ((b == 1u) ? 0.34 : 0.24);
    float y0 = SC_PLINTH_H + ((b == 0u) ? 0.0 : ((b == 1u) ? 0.90 : 1.58));
    float turn = 0.42 * (float)b;
    return float4(hw, y0 + hw, turn, 0.0);                // (half size, centre y, turn, -)
}

// where the editor's views look (and where the camera may go): x, y, z bounds
#define SC_X0 -8.0
#define SC_X1  8.0
#define SC_Y0  0.0
#define SC_Y1  12.0
#define SC_Z0 -4.0
#define SC_Z1  44.0
float3 scClampEye(float3 p) { return clamp(p, float3(-9.5, 0.2, -8.0), float3(9.5, 14.0, 48.0)); }

// ---------------------------------------------------------------- records
uint   scActs()            { return clamp((uint)SC_BUF[SC_P0].x, 1u, SC_ACTS); }
uint   scActRec(uint a)    { return SC_ACT0 + min(a, SC_ACTS - 1u) * SC_ACTREC; }
float4 scActA(uint a)      { return SC_BUF[scActRec(a)]; }
float4 scActB(uint a)      { return SC_BUF[scActRec(a) + 1u]; }
uint   scKind(uint a)      { return min((uint)scActA(a).x, 1u); }
float  scDur(uint a)       { return clamp(scActA(a).y, 1.0, 30.0); }
uint   scHand(uint a)      { return min((uint)scActA(a).z, 2u); }
float  scHandLen(uint a)   { return (scHand(a) == SC_CUT) ? 0.0 : clamp(scActA(a).w, 0.25, min(4.0, scDur(a) * 0.5)); }
uint   scLight(uint a)     { return min((uint)scActB(a).x, 2u); }
uint   scWord(uint a)      { return min((uint)scActB(a).y, SC_WORDS - 1u); }
uint   scMarkN(uint a)     { return clamp((uint)scActB(a).z, 2u, SC_MARKS); }
uint   scMarkRec(uint a, uint m) { return scActRec(a) + 2u + 2u * min(m, SC_MARKS - 1u); }
float4 scEyeRec(uint a, uint m)  { return SC_BUF[scMarkRec(a, m)]; }        // (eye, at)
float4 scAimRec(uint a, uint m)  { return SC_BUF[scMarkRec(a, m) + 1u]; }   // (target, fov)
float4 scItem(uint a, uint k)    { return SC_BUF[scMarkRec(a, min(k, SC_ITEMS - 1u))]; }

float scStart(uint a)
{
    float t = 0.0;
    [loop] for (uint i = 0u; i < SC_ACTS; i++) t += (i < min(a, scActs())) ? scDur(i) : 0.0;
    return t;
}
float scTotal() { return scStart(SC_ACTS); }

// ---------------------------------------------------------------- the rail
// A cubic Hermite through the marks at their times, the tangent at an inner mark from its two
// neighbours (Catmull-Rom on uneven spacing), zero at the first and the last: the camera leaves the
// first mark from rest and settles on the last one. Eye, target and lens each follow it.
struct ScPose { float3 eye; float3 target; float fov; };

float4 scHermite(float4 p0, float4 p1, float4 m0, float4 m1, float u)
{
    float u2 = u * u, u3 = u2 * u;
    return (2.0 * u3 - 3.0 * u2 + 1.0) * p0 + (u3 - 2.0 * u2 + u) * m0 + (-2.0 * u3 + 3.0 * u2) * p1 + (u3 - u2) * m1;
}

// mark m's (eye, fov) and (target, -) for the curve, and its time in the act (s)
void scMarkPts(uint a, uint m, out float4 e, out float4 g, out float t)
{
    float4 er = scEyeRec(a, m), ar = scAimRec(a, m);
    e = float4(er.xyz, ar.w);
    g = float4(ar.xyz, 0.0);
    t = saturate(er.w) * scDur(a);
}

ScPose scPose(uint a, float t)
{
    uint n = scMarkN(a);
    // the segment: k with time(k) <= t < time(k + 1)
    uint k = 0u;
    [loop] for (uint i = 1u; i + 1u < n; i++) k = (saturate(scEyeRec(a, i).w) * scDur(a) <= t) ? i : k;
    float4 e0, g0, e1, g1, eA, gA, eB, gB;
    float t0, t1, tA, tB;
    scMarkPts(a, k, e0, g0, t0);
    scMarkPts(a, k + 1u, e1, g1, t1);
    scMarkPts(a, (k > 0u) ? k - 1u : k, eA, gA, tA);
    scMarkPts(a, min(k + 2u, n - 1u), eB, gB, tB);
    float span = max(t1 - t0, 1e-3);
    float u = saturate((t - t0) / span);
    // tangents scaled to this segment; zero at the ends of the rail
    float4 me0 = (k > 0u) ? (e1 - eA) / max(t1 - tA, 1e-3) * span : 0.0;
    float4 mg0 = (k > 0u) ? (g1 - gA) / max(t1 - tA, 1e-3) * span : 0.0;
    float4 me1 = (k + 2u < n) ? (eB - e0) / max(tB - t0, 1e-3) * span : 0.0;
    float4 mg1 = (k + 2u < n) ? (gB - g0) / max(tB - t0, 1e-3) * span : 0.0;
    float4 e = scHermite(e0, e1, me0, me1, u);
    float4 g = scHermite(g0, g1, mg0, mg1, u);
    ScPose p;
    p.eye = scClampEye(e.xyz);
    p.target = g.xyz;
    p.fov = clamp(e.w, 12.0, 100.0);
    return p;
}

ScPose scLerpPose(ScPose a, ScPose b, float u)
{
    ScPose p;
    p.eye = lerp(a.eye, b.eye, u);
    p.target = lerp(a.target, b.target, u);
    p.fov = lerp(a.fov, b.fov, u);
    return p;
}

// the internal camera's angles for a pose: yaw = atan2(dir.x, dir.z), pitch = asin(dir.y)
float2 scYawPitch(ScPose p)
{
    float3 d = p.target - p.eye;
    float l = length(d);
    d = (l > 1e-4) ? d / l : float3(0.0, 0.0, 1.0);
    return float2(atan2(d.x, d.z), asin(clamp(d.y, -0.999, 0.999)));
}

// ---------------------------------------------------------------- what the program reads
uint  scShowA()    { return (uint)SC_BUF[SC_R0].x; }
uint  scShowB()    { return (uint)SC_BUF[SC_R0].y; }
float scShowMix()  { return SC_BUF[SC_R0].z; }
uint  scShowHand() { return (uint)SC_BUF[SC_R0].w; }

// ---------------------------------------------------------------- a card's look, per light
// Display colour (module outputs are shown as written), shared so the editor's stage and the program
// agree: paper and ink by day, a plum dusk, a night of near-black and bone.
float3 scCardGround(uint li) { return (li == SC_DAY) ? float3(0.93, 0.91, 0.86) : ((li == SC_DUSK) ? float3(0.25, 0.14, 0.21) : float3(0.05, 0.055, 0.07)); }
float3 scCardInk(uint li)    { return (li == SC_DAY) ? float3(0.11, 0.11, 0.12) : ((li == SC_DUSK) ? float3(0.96, 0.86, 0.74) : float3(0.92, 0.92, 0.88)); }
float3 scCardDisc(uint li)   { return (li == SC_DAY) ? float3(0.80, 0.30, 0.14) : ((li == SC_DUSK) ? float3(0.98, 0.62, 0.30) : float3(0.95, 0.74, 0.36)); }
// The bar's half thickness, as a fraction of the frame's height.
#define SC_BAR_HT 0.012
// A word's em size per unit of its cap height (the bold face of _shared/type: em 48, cap 33.5).
#define SC_EM_PER_CAP 1.4328

#endif
