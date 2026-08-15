// FM_Render / antgeo.hlsli — the morphology of a fire ant worker, as vertex-pulled geometry.
//
// WHY RASTERIZED GEOMETRY AND NOT A RAY-MARCHED FIELD. One ant is about thirty primitives:
// five body masses, eighteen leg segments, four antennal segments and two mandibles. Sixty-four
// ants is two thousand. Evaluating that per march step per pixel is hopeless, while pulling
// 227k vertices through the hardware rasterizer with a shared depth buffer is trivial. The
// koi_tank README records the other half of the same lesson: inlining a field function seven
// times took its compile from seconds to minutes and made hot reload unusable.
//
// ---------------------------------------------------------------------------
// THE PROPORTIONS, transcribed from the photograph. All in fractions of body length.
//
// The three tagmata are the easy part. What actually makes a Solenopsis worker recognisable —
// and what a generic "insect" model always gets wrong — is the WAIST: two separate nodes,
// petiole and postpetiole, between mesosoma and gaster. Draw one node, or none, and the result
// reads as a beetle or a wasp no matter how good the shading is.
//
// The legs matter just as much and are just as easy to get wrong. An ant's legs are not evenly
// spread: the front pair reaches forward and sits tucked in, the middle pair is the widest, and
// the rear pair is the longest and trails behind. This show is seen from above, which is
// precisely the view that exposes it.
// ---------------------------------------------------------------------------
#ifndef FM_ANTGEO_HLSLI
#define FM_ANTGEO_HLSLI

#include "../_shared/formic.hlsli"

// --- tessellation and the per-ant vertex budget
// ---------------------------------------------------------------------------
// THESE ARE A CAPACITY, NOT THE MESH.
//
// The vertex count of the draw is fixed at compile time, so the detail ladder can only ever
// spend LESS than what is declared here — it degenerates the surplus. Which means the ceiling
// has to be authored at the HIGHEST tier anyone will ever want, and everything below it is a
// subset. Raising quality later is not a shader tweak, it is a change to this block plus the
// manifest's vertex_count, and the two must agree exactly or the last ant is drawn truncated.
//
// Sized for the HERO tier. The ordinary tiers are subsets picked in scene.hlsl, and Full there
// reproduces the original mesh exactly: 16x10 gaster, 12x8 body, 12x4 nodes, 6-sided tubes.
//
// What the extra budget is spent on is deliberately lopsided. The ellipsoids were already
// smooth enough that doubling them buys very little; the LEG TUBES at six sides are visibly
// hexagonal prisms in any close shot, and that is the thing that looks cheap. So the tubes go
// to twelve sides and the bodies rise modestly.
#define GAS_SL  24u
#define GAS_ST  14u
#define GAS_V   (GAS_SL * GAS_ST * 6u)          // 2016

#define BOD_SL  16u
#define BOD_ST  10u
#define BOD_V   (BOD_SL * BOD_ST * 6u)          // 960

#define NOD_SL  14u
#define NOD_ST   6u
#define NOD_V   (NOD_SL * NOD_ST * 6u)          // 504

#define TUB_S   12u
#define TUB_V   (TUB_S * 6u)                    // 72 per segment

#define LEG_SEG  3u
#define LEG_V   (FM_LEGS * LEG_SEG * TUB_V)     // 1296
#define ANT_SEG  2u
#define ANTN_V  (2u * ANT_SEG * TUB_V)          // 288
#define MAND_V  (2u * TUB_V)                    // 144

#define OFF_GASTER 0u
#define OFF_MESO   (OFF_GASTER + GAS_V)         // 2016
#define OFF_HEAD   (OFF_MESO + BOD_V)           // 2976
#define OFF_PET    (OFF_HEAD + BOD_V)           // 3936
#define OFF_POST   (OFF_PET + NOD_V)            // 4440
#define OFF_LEGS   (OFF_POST + NOD_V)           // 4944
#define OFF_ANTN   (OFF_LEGS + LEG_V)           // 6240
#define OFF_MAND   (OFF_ANTN + ANTN_V)          // 6528
// 6672. The manifest's vertex_count MUST be 6 + FM_MAX_ANTS * this = 854022.
#define VERTS_PER_ANT (OFF_MAND + MAND_V)       // 6672

// material ids, handed to the pixel shader
#define MAT_GASTER 0.0
#define MAT_THORAX 1.0
#define MAT_LIMB   2.0

// --- part placement, in body lengths. z is forward, y is up, x is the ant's right.
// Tightened against the photograph after the first render came back reading as a spider: the
// head was too small, the waist too long, and the gaster stood visibly clear of the mesosoma.
// A real worker is a compact chain of masses that very nearly touch.
static const float3 P_HEAD_C = float3(0.000,  0.012,  0.300);
static const float3 P_HEAD_R = float3(0.135,  0.115,  0.140);
static const float3 P_MESO_C = float3(0.000,  0.000,  0.040);
static const float3 P_MESO_R = float3(0.098,  0.100,  0.175);
static const float3 P_PET_C  = float3(0.000, -0.018, -0.135);
static const float3 P_PET_R  = float3(0.044,  0.050,  0.040);
static const float3 P_POST_C = float3(0.000, -0.014, -0.195);
static const float3 P_POST_R = float3(0.054,  0.058,  0.048);
static const float3 P_GAS_C  = float3(0.000,  0.014, -0.365);
static const float3 P_GAS_R  = float3(0.168,  0.158,  0.208);

// The six corners of a quad, as two triangles. Written out rather than held in a local array,
// because a local array initialised from anything the compiler cannot fold is a documented way
// to get silently wrong values.
float2 agCorner(uint c)
{
    if (c == 0u) return float2(0, 0);
    if (c == 1u) return float2(1, 0);
    if (c == 2u) return float2(1, 1);
    if (c == 3u) return float2(0, 0);
    if (c == 4u) return float2(1, 1);
    return float2(0, 1);
}

// A vertex on the unit sphere for quad `local` of an SL x ST grid.
//
// The (u,v) are generated FROM THE SLICE AND STACK INDICES and interpolated, never recovered in
// the pixel shader from atan2 of the normal — that puts a seam down every body where the
// derivative explodes, and on a glossy chitin surface the seam is a bright line.
float3 agSphereN(uint local, uint SL, uint ST, out float2 uvOut)
{
    uint quad = local / 6u;
    uint corner = local % 6u;
    uint sl = quad % SL;
    uint st = quad / SL;
    float2 co = agCorner(corner);

    float u = ((float)sl + co.x) / (float)SL;
    float v = ((float)st + co.y) / (float)ST;
    uvOut = float2(u, v);

    float theta = u * 6.2831853;
    float phi = v * 3.14159265;
    float sp = sin(phi);
    return float3(sp * cos(theta), cos(phi), sp * sin(theta));
}

// An ellipsoid vertex plus its correct normal. The normal of a scaled sphere is the sphere
// normal divided by the radii, not scaled by them — getting that backwards makes an elongated
// gaster shade as though it were round, which on a mirror-glossy surface is instantly visible.
void agEllipsoid(uint local, uint SL, uint ST, float3 c, float3 r, float taper,
                 out float3 pos, out float3 nrm, out float2 uvOut)
{
    float3 n = agSphereN(local, SL, ST, uvOut);

    // `taper` pinches one end toward a point, which is what turns a plain ellipsoid into a
    // gaster with a tip and a head with a face.
    float k = lerp(1.0, saturate(0.5 + 0.5 * n.z), taper);
    float3 rr = float3(r.x * k, r.y * k, r.z);

    pos = c + n * rr;
    nrm = normalize(n / max(rr, 1e-4));
}

// A tube segment. One ring of `sides` quads between A and B, radius rA to rB.
//
// The side count is a PARAMETER rather than the TUB_S constant, because the detail ladder needs
// a coarser tube out of the same fixed vertex range: the surplus vertices are degenerated by the
// caller and the ring that remains still closes. Halving the quads of a ring by degenerating
// alternate ones would not close it — it would leave a leg with slots cut down its length.
void agTubeN(uint local, float3 A, float3 B, float rA, float rB, uint sides,
             out float3 pos, out float3 nrm)
{
    uint quad = local / 6u;
    uint corner = local % 6u;
    uint side = quad % sides;
    float2 co = agCorner(corner);

    float3 d = B - A;
    float len = length(d);
    float3 dir = (len > 1e-6) ? d / len : float3(0, 1, 0);

    float3 upRef = (abs(dir.y) > 0.94) ? float3(1, 0, 0) : float3(0, 1, 0);
    float3 T = normalize(cross(upRef, dir));
    float3 Bn = cross(dir, T);

    float ang = (((float)side + co.x) / (float)sides) * 6.2831853;
    float3 rad = T * cos(ang) + Bn * sin(ang);

    float t = co.y;
    pos = lerp(A, B, t) + rad * lerp(rA, rB, t);
    nrm = rad;
}

// The full-detail tube every caller used before the ladder existed.
void agTube(uint local, float3 A, float3 B, float rA, float rB,
            out float3 pos, out float3 nrm)
{
    agTubeN(local, A, B, rA, rB, TUB_S, pos, nrm);
}

// ---------------------------------------------------------------------------
// TWO-BONE IK. Hip and foot are given; the knee is solved for.
//
// The knee is lifted along the component of WORLD UP perpendicular to the hip-foot line, which
// is what puts an ant's knees ABOVE its back — the single most characteristic thing about the
// silhouette from overhead, and the thing that separates an ant from a spider at a glance.
// ---------------------------------------------------------------------------
float3 agSolveKnee(float3 hip, float3 foot, float l1, float l2, float outward)
{
    float3 d = foot - hip;
    float dist = length(d);
    // Clamped strictly inside the reachable annulus. At exactly l1+l2 the square root below is
    // zero and the knee snaps dead straight, which reads as the leg locking for one frame.
    float lo = abs(l1 - l2) + 1e-3;
    float hi = l1 + l2 - 1e-3;
    float dc = clamp(dist, lo, hi);
    float3 dir = (dist > 1e-5) ? d / dist : float3(0, -1, 0);

    float a = (l1 * l1 - l2 * l2 + dc * dc) / (2.0 * dc);
    float h = sqrt(max(l1 * l1 - a * a, 0.0));

    float3 up = float3(0, 1, 0);
    float3 lift = up - dir * dot(up, dir);
    float ll = length(lift);
    lift = (ll > 1e-4) ? lift / ll : float3(0, 1, 0);

    // A little outward bias, away from the body's centre line, so the legs bow out instead of
    // folding into the mesosoma.
    float3 side = float3(d.x, 0.0, d.z);
    float sl = length(side);
    if (sl > 1e-4) lift = normalize(lift + side / sl * outward);

    return hip + dir * a + lift * h;
}

// Where each leg attaches to the mesosoma, in body lengths.
float3 agLegHip(uint leg, float bodyLen)
{
    uint side = leg / 3u;
    uint pairIdx = leg % 3u;
    float sgn = (side == 0u) ? -1.0 : 1.0;
    float fore = (pairIdx == 0u) ? 0.115 : ((pairIdx == 1u) ? 0.030 : -0.075);
    return float3(sgn * 0.082, -0.020, fore) * bodyLen;
}

// Femur and tibia lengths, DERIVED FROM THE SPAN THEY HAVE TO COVER rather than authored as
// constants in body lengths.
//
// They used to be fixed fractions — 0.82, 0.93 and 1.05 body lengths for the three pairs — and
// the stance they had to reach was 0.61, 0.74 and 0.81. Bones 26 to 35% longer than the distance
// between hip and foot have to put that surplus somewhere, and where they put it is the knee: up
// and out, in a high angular peak over the back. That is the single strongest spider cue there
// is, and no amount of tightening the stance fixes it — pull the feet in with the bones left
// alone and the knees jut FURTHER, because there is even more slack to absorb.
//
// So the bones now follow the hip-to-ankle distance. `slack` is the only number that decides how
// bent the leg is, it is the same for every pair, and the rear pair still comes out longest
// because its foot is genuinely further away. A stance change can no longer desynchronise them.
//
// 1.15 keeps a clear, ant-like bend while staying inside what agSolveKnee can solve: at 1.0 the
// leg locks dead straight and the knee vanishes, and below about 1.05 the solver's clamp starts
// snapping it straight for a frame on hard turns.
float2 agLegBones(float hipToAnkle)
{
    float slack = 1.15;
    float total = max(hipToAnkle, 1e-4) * slack;
    // Femur marginally the longer of the two, which is where a real ant's knee sits.
    return float2(total * 0.52, total * 0.48);
}

#endif // FM_ANTGEO_HLSLI
