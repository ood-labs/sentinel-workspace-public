// ---------------------------------------------------------------------------
// CLOTH LAB - XPBD solver.
//
// One dispatch, one thread group, 1024 threads, 2 particles per thread.
// The whole cloth is loaded into groupshared memory, then:
//
//   for each substep:
//     predict positions from velocity + gravity
//     sweep 6 constraint families x 2 colours, barrier between colours
//     recover velocity from the position delta
//
// Small-substep XPBD (Macklin et al. 2019): many substeps with ONE constraint
// sweep each converges far better than one substep with many sweeps, and needs
// no per-constraint lambda accumulation. Because it solves positions with a
// compliance term rather than integrating spring forces, it is stable at any
// stiffness - the cloth can be genuinely inextensible instead of rubbery.
//
// Each family is 2-colourable on a grid: two constraints of a family share a
// vertex only when their owner vertices differ by one step along the family's
// axis, so a single parity bit separates them. Within a colour every write
// targets a distinct vertex, so no atomics are needed.
// ---------------------------------------------------------------------------

#include "cloth_common.hlsli"
#include "../_shared/xpbd/xpbd.hlsli"

// The cloth state is read AND written through the same UAV, with no SRV input
// for it on this pass.
//
// Binding one structured buffer as both SRV (t0) and UAV (u0) on a single pass
// is illegal in D3D11: the runtime drops the SRV to null, the solver reads all
// zeros, decides the cloth is uninitialised, and silently restarts it from rest
// every cook. The symptom is a perfectly flat sheet whose mean speed sits at
// exactly gravity/framerate. Structured buffers do not ping-pong here - only
// texture buffers do.
//
// Reading the UAV is race-free in this shader because every load completes and
// syncs into groupshared before the first store, and the substeps touch nothing
// but groupshared.
RWStructuredBuffer<ClothPoint> State : register(u0);

// Written by the `interact` pass earlier in this same cook.
StructuredBuffer<InteractState> Touch : register(t0);

// 2048 * 12 B = 24576 B, plus 1 KB of packed broken-edge bits.
// D3D11 allows 32 KB of groupshared per group; three separate float arrays
// avoid any float3 stride padding that would put us over.
groupshared float gPx[PCOUNT];
groupshared float gPy[PCOUNT];
groupshared float gPz[PCOUNT];
groupshared uint  gBrk[PCOUNT / 8u];   // 4 bits per particle

float3 gLoad(uint i) { return float3(gPx[i], gPy[i], gPz[i]); }
void   gStore(uint i, float3 p) { gPx[i] = p.x; gPy[i] = p.y; gPz[i] = p.z; }

// ---------------------------------------------------------------------------

// restPosition() lives in cloth_common.hlsli - the renderer needs it too.

// A perfectly flat sheet under purely vertical gravity is a degenerate
// equilibrium: every force stays in the plane, so the cloth drapes without ever
// producing a fold. Spawning with a shallow out-of-plane wave breaks the
// symmetry so folds can develop. Rest lengths come from the grid spacing, not
// from this, so the wrinkle costs no initial strain worth speaking of.
float3 spawnPosition(uint i)
{
    float3 p = restPosition(i);
    float2 t = float2((float)clothX(i) / (float)(GRID_W - 1u),
                      (float)clothY(i) / (float)(GRID_H - 1u));
    p.z += spawn_wrinkle * (sin(t.x * 11.0 + 0.7) * 0.6 +
                            sin(t.x * 27.0 - t.y * 5.0) * 0.4) *
           (0.25 + 0.75 * t.y);
    return p;
}

// Pinned vertices carry zero inverse mass. Derived procedurally so every
// thread agrees without reading shared state.
float invMassFor(uint i)
{
    uint x = clothX(i);
    uint y = clothY(i);
    bool pinned = false;
    if (pin_mode == 0)      pinned = (y == 0u);
    else if (pin_mode == 1) pinned = (y == 0u && (x == 0u || x == GRID_W - 1u));
    else if (pin_mode == 2) pinned = (y == 0u && x == 0u);
    else if (pin_mode == 3) pinned = ((y == 0u || y == GRID_H - 1u) &&
                                      (x == 0u || x == GRID_W - 1u));
    return pinned ? 0.0 : 1.0;
}

uint brokenBits(uint i)
{
    return (gBrk[i >> 3u] >> ((i & 7u) * 4u)) & 0xFu;
}

// ---------------------------------------------------------------------------
// Wind and aerodynamics.
//
// A uniform force field cannot make cloth flap - it just pushes the whole sheet
// downwind and it hangs there at an angle. What produces flapping is an
// AERODYNAMIC force that depends on the surface's own orientation: each patch
// feels a pressure proportional to the square of the wind component along its
// normal, so a patch turning edge-on sheds force, over-swings, catches the wind
// again on the other side, and the sheet self-oscillates.
// ---------------------------------------------------------------------------

float3 clothNormal(uint i)
{
    uint x = clothX(i);
    uint y = clothY(i);
    uint xm = (x > 0u)            ? i - 1u     : i;
    uint xp = (x + 1u < GRID_W)   ? i + 1u     : i;
    uint ym = (y > 0u)            ? i - GRID_W : i;
    uint yp = (y + 1u < GRID_H)   ? i + GRID_W : i;

    float3 n = cross(gLoad(xp) - gLoad(xm), gLoad(yp) - gLoad(ym));
    float l = length(n);
    return (l > 1e-8) ? n / l : float3(0.0, 0.0, 1.0);
}

// Evaluated once per cook, not per substep: gusts vary over tenths of a second
// while a substep is sub-millisecond, so per-substep noise would be 16x the
// cost for no visible difference.
float3 windAt(uint i)
{
    if (wind_speed <= 0.0001) return float3(0.0, 0.0, 0.0);

    float az = radians(wind_azimuth);
    float el = radians(wind_elevation);
    float3 dir = float3(sin(az) * cos(el), sin(el), cos(az) * cos(el));

    float3 r = restPosition(i);
    float3 wp = r * gust_scale + float3(0.0, 0.0, _Time * gust_rate);

    // fbm3D takes an octave count and already returns a roughly -1..1 signal.
    float g = fbm3D(wp, 3);
    float3 w = dir * wind_speed * (1.0 + gust_amount * g);

    if (turbulence > 0.0001)
    {
        float3 t = float3(fbm3D(wp + 11.3, 2), fbm3D(wp + 27.7, 2), fbm3D(wp + 41.1, 2));
        w += t * turbulence * wind_speed * 0.35;
    }
    return w;
}

// Returns an ACCELERATION, not a force. Aerodynamic force scales with patch
// area and so does patch mass, so the area cancels; particle mass here is
// uniform (1.0), so folding an area factor in would just make wind ~140x too
// weak relative to gravity.
float3 aeroAccel(float3 n, float3 v, float3 wind)
{
    float3 vr = v - wind;                 // velocity of the patch through the air
    float vn = dot(n, vr);
    float3 vt = vr - vn * n;

    // Pressure term is signed-square so it always opposes the through-normal
    // motion regardless of which face is upwind.
    float3 a = -(aero_drag * abs(vn) * vn) * n;
    // Crude tangential lift; this is what adds the edge flutter.
    a -= aero_lift * abs(vn) * vt;
    return a;
}

// ---------------------------------------------------------------------------

void solveDistance(uint i, uint j, float rest, float alphaTilde)
{
    float3 dpi, dpj;
    xpbd_distance_delta(gLoad(i), gLoad(j), invMassFor(i), invMassFor(j),
                        rest, alphaTilde, dpi, dpj);
    gStore(i, gLoad(i) + dpi);
    gStore(j, gLoad(j) + dpj);
}

// ---------------------------------------------------------------------------
// Bending, sign-aware.
//
// The earlier model constrained the DISTANCE between 2-away vertices. That is
// exactly satisfied by an INVERTED fold: once a crease folds back through
// itself, |p_i - p_i+2| still equals its rest length, the constraint reports no
// error, and nothing ever flattens it. Sharp creases therefore locked and the
// sheet stayed knotted.
//
// This constrains the curvature vector instead - how far the centre vertex sits
// from the midpoint of its two neighbours - which is zero only when the triplet
// is straight. It has one preferred state, so it always pushes a fold open
// rather than accepting it folded.
//
// Triplets centred 1 or 2 apart share a vertex, so the centre index needs THREE
// colours rather than two.
// ---------------------------------------------------------------------------
void solveBend(uint a, uint b, uint c, float alphaTilde)
{
    float3 da, db, dc;
    xpbd_curvature_delta(gLoad(a), gLoad(b), gLoad(c),
                         invMassFor(a), invMassFor(b), invMassFor(c),
                         alphaTilde, da, db, dc);
    gStore(a, gLoad(a) + da);
    gStore(b, gLoad(b) + db);
    gStore(c, gLoad(c) + dc);
}

void sweepBending(uint tid, bool horizontal, float alphaTilde)
{
    [loop]
    for (uint col = 0u; col < 3u; ++col)
    {
        [loop]
        for (uint s = 0u; s < PER_THREAD; ++s)
        {
            uint i = tid + s * SOLVE_GROUP;
            uint x = clothX(i);
            uint y = clothY(i);

            bool ok = false;
            uint a = i;
            uint c = i;

            if (horizontal)
            {
                if (x >= 1u)
                {
                    if (x + 1u < GRID_W)
                    {
                        if ((x % 3u) == col)
                        {
                            a = i - 1u;
                            c = i + 1u;
                            // Dead if either structural edge spanned by the
                            // triplet has torn.
                            ok = ((brokenBits(a) & 0x1u) == 0u) &&
                                 ((brokenBits(i) & 0x1u) == 0u);
                        }
                    }
                }
            }
            else
            {
                if (y >= 1u)
                {
                    if (y + 1u < GRID_H)
                    {
                        if ((y % 3u) == col)
                        {
                            a = i - GRID_W;
                            c = i + GRID_W;
                            ok = ((brokenBits(a) & 0x2u) == 0u) &&
                                 ((brokenBits(i) & 0x2u) == 0u);
                        }
                    }
                }
            }

            if (ok) solveBend(a, i, c, alphaTilde);
        }

        GroupMemoryBarrierWithGroupSync();
    }
}

// One family = two barrier-separated colour sweeps.
void sweepFamily(uint tid, uint fam, float rest, float alphaTilde)
{
    [loop]
    for (uint c = 0u; c < 2u; ++c)
    {
        [loop]
        for (uint s = 0u; s < PER_THREAD; ++s)
        {
            uint i = tid + s * SOLVE_GROUP;
            uint x = clothX(i);
            uint y = clothY(i);
            uint bits = brokenBits(i);

            uint a = i;
            uint b = i;
            uint col = 0u;
            bool valid = false;
            bool broken = false;

            if (fam == FAM_H)
            {
                valid = (x + 1u < GRID_W);
                a = i; b = i + 1u;
                col = x & 1u;
                broken = (bits & 0x1u) != 0u;
            }
            else if (fam == FAM_V)
            {
                valid = (y + 1u < GRID_H);
                a = i; b = i + GRID_W;
                col = y & 1u;
                broken = (bits & 0x2u) != 0u;
            }
            else if (fam == FAM_D)
            {
                valid = (x + 1u < GRID_W) && (y + 1u < GRID_H);
                a = i; b = i + GRID_W + 1u;
                col = x & 1u;
                broken = (bits & 0x4u) != 0u;
            }
            else   // FAM_A
            {
                valid = (x + 1u < GRID_W) && (y + 1u < GRID_H);
                a = i + GRID_W; b = i + 1u;
                col = x & 1u;
                broken = (bits & 0x8u) != 0u;
            }

            // No early-out before the barrier: the guard wraps only the solve,
            // so every thread reaches the sync below.
            if (valid && !broken && col == c)
                solveDistance(a, b, rest, alphaTilde);
        }

        GroupMemoryBarrierWithGroupSync();
    }
}

// ---------------------------------------------------------------------------
// Colliders.
//
// Resolved as position projections after the constraint sweeps, which is the
// PBD-native way: push the vertex to the surface, then kill part of the
// tangential motion it made this substep to model friction. Each thread only
// touches its own vertices, so this needs no colouring.
// ---------------------------------------------------------------------------

float3 colliderCenter(uint s)
{
    // Getter rather than an array: initialising a local array from cbuffer
    // values is one of the documented ways to silently get wrong data here.
    if (s == 0u) return sphere_a_pos;
    if (s == 1u) return sphere_b_pos;
    return sphere_c_pos;
}

float colliderRadius(uint s)
{
    if (s == 0u) return sphere_a_radius;
    if (s == 1u) return sphere_b_radius;
    return sphere_c_radius;
}

// Removes a fraction of the tangential sliding the vertex did during THIS
// substep. `friction` is that fraction directly, 0 = frictionless, 1 = fully
// static.
//
// Critically this is applied exactly once per substep, in the final collision
// pass only. Applying it in every interleaved pass compounded it - each call
// re-measured the whole substep displacement and shaved it again, which glued
// the cloth to the collider so it had to STRETCH to conform instead of sliding.
// Measured on a sphere drape: 1.8% peak strain frictionless, 18% at friction 0.3
// with the compounding version.
// Friction and collider projections come from _shared/xpbd/xpbd.hlsli.

// Kept branchless with respect to per-thread data: the pinned test is applied
// as a select at the very end rather than as an early return, and the collider
// loop is bounded by a uniform. An early return here puts the loop that follows
// it into varying flow, and the compiler then refuses the barrier at the call
// site (X4026: sync in varying flow control).
float3 resolveCollisions(uint i, float3 p, float3 prevP, bool withFriction)
{
    float3 original = p;
    float thick = cloth_thickness;

    // Two passes over the collider set.
    //
    // A single pass resolves each collider in isolation, so a vertex caught
    // between two of them (cloth wedged where a sphere nearly touches the floor)
    // gets pushed out of the ground, then shoved back under it by the sphere, and
    // the substep ends violating the ground. Its neighbours then get dragged, and
    // the sheet reports enormous strain - measured 56% peak where the gap between
    // sphere and floor was thinner than the cloth. Two passes let the pair
    // co-converge. A genuinely impossible pinch still cannot be satisfied, but it
    // degrades to a small steady error instead of a fight.
    [loop]
    for (uint cpass = 0u; cpass < 2u; ++cpass)   // `pass` is an HLSL reserved word
    {
        if (ground_enabled != 0)
        {
            bool onGround;
            p = xpbd_plane_project(p, ground_y + thick, onGround);
            if (onGround && withFriction)
                p = xpbd_friction(p, prevP, float3(0.0, 1.0, 0.0), friction);
        }

        [loop]
        for (uint s = 0u; s < 3u; ++s)
        {
            if ((int)s >= collider_count) break;

            bool onSphere;
            float3 nrm;
            p = xpbd_sphere_project(p, colliderCenter(s), colliderRadius(s) + thick,
                                    onSphere, nrm);
            if (onSphere && withFriction)
                p = xpbd_friction(p, prevP, nrm, friction);
        }
    }
    return (invMassFor(i) > 0.0) ? p : original;
}

// ---------------------------------------------------------------------------
// Grab.
//
// A soft position constraint rather than a hard vertex teleport: the whole
// brush-sized patch is pulled toward the target while keeping its rest shape,
// so grabbing feels like taking hold of a handful of fabric instead of dragging
// one infinitely strong point. Weighting by REST distance keeps the affected
// patch coherent even when the cloth is already crumpled.
// ---------------------------------------------------------------------------
float3 applyGrab(uint i, float3 p, InteractState st)
{
    if (st.active < 0.5) return p;
    if ((uint)st.tool != TOOL_GRAB) return p;
    if (st.index < 0.0) return p;
    if (invMassFor(i) <= 0.0) return p;

    float3 restG = restPosition((uint)st.index);
    float3 restI = restPosition(i);
    float w = saturate(1.0 - length(restI - restG) / max(st.radius, 1e-4));
    if (w <= 0.0) return p;
    w = w * w * (3.0 - 2.0 * w);

    float3 want = st.target + (restI - restG);
    return lerp(p, want, saturate(w * grab_strength));
}

// ---------------------------------------------------------------------------
// Long-range attachments (Kim / Chentanez / Mueller-Fischer 2012).
//
// This is the constraint that makes a deep sheet actually inextensible. Local
// edge sweeps carry a pin's influence roughly one row per iteration, so a
// 32-row cloth hanging from two corners stretches tens of percent regardless of
// edge stiffness or substep count - measured here at 61% with 16 substeps and
// 32% with 40. Tying every vertex directly to its nearest anchor with an
// INEQUALITY on the rest distance fixes that in a single sweep.
//
// Two properties make it nearly free: the anchor has infinite mass, so the
// whole correction goes to the free vertex and no colouring is needed (each
// thread writes only its own vertices), and the rest shape is flat, so the
// Euclidean rest distance IS the geodesic distance across the sheet.
// ---------------------------------------------------------------------------

// Applies the inequality against ONE anchor. Called for EVERY anchor rather than
// only the nearest.
//
// Selecting a single nearest anchor is what produced the phantom tether: with
// four corners, vertices on the centre line are equidistant from the left and
// right corners, the tie-break flipped the chosen anchor discontinuously, and
// each side got pulled toward a different corner - a hard crease down the middle,
// worst near the top edge where both top corners dominate. Every anchor is an
// independent valid bound, so applying all of them is both more correct and
// continuous.
void applyAnchorLimit(uint i, uint anchorIndex, float capScale, float slack, float strength)
{
    float3 anchor = restPosition(anchorIndex);
    float restDist = length(restPosition(i) - anchor);
    gStore(i, xpbd_long_range(gLoad(i), anchor, restDist * capScale * slack, strength));
}

void solveLongRange(uint i, float slack, float strength, float restScale)
{
    if (pin_mode == 4) return;          // Free: nothing is attached
    if (invMassFor(i) <= 0.0) return;   // anchors themselves

    // The cap NEVER tightens below the geometric rest distance.
    //
    // Long-range attachment exists to stop a sheet reaching further than its
    // material allows - a one-sided guard. Letting rest_scale shrink the cap
    // turned it into an active inward pull toward the anchors, which is not what
    // "the cloth wants to be smaller" should mean. Tautness from rest_scale < 1
    // belongs to the distance constraints, which already deliver it. Slack
    // material (rest_scale > 1) does legitimately extend the reach.
    float capScale = max(restScale, 1.0);

    if (pin_mode == 0)
    {
        // Top Edge: the anchor is the vertex directly above in the rest sheet.
        applyAnchorLimit(i, clothIndex(clothX(i), 0u), capScale, slack, strength);
    }
    else if (pin_mode == 1)
    {
        applyAnchorLimit(i, clothIndex(0u, 0u), capScale, slack, strength);
        applyAnchorLimit(i, clothIndex(GRID_W - 1u, 0u), capScale, slack, strength);
    }
    else if (pin_mode == 2)
    {
        applyAnchorLimit(i, clothIndex(0u, 0u), capScale, slack, strength);
    }
    else
    {
        applyAnchorLimit(i, clothIndex(0u, 0u), capScale, slack, strength);
        applyAnchorLimit(i, clothIndex(GRID_W - 1u, 0u), capScale, slack, strength);
        applyAnchorLimit(i, clothIndex(0u, GRID_H - 1u), capScale, slack, strength);
        applyAnchorLimit(i, clothIndex(GRID_W - 1u, GRID_H - 1u), capScale, slack, strength);
    }
}

// ---------------------------------------------------------------------------
// Tearing.
//
// Evaluated once at the end of the cook, after the solver has settled, so a
// transient mid-substep overshoot cannot rip the sheet. Each edge is owned by
// exactly one vertex, so the bits can be accumulated with no atomics and no
// colouring. Once set they persist in the vertex flags until a reset.
//
// The bounds tests are nested rather than &&-ed: HLSL does not guarantee
// short-circuit evaluation, so a combined condition would still issue the
// out-of-range groupshared read.
// ---------------------------------------------------------------------------
uint tearBits(uint i, float3 p, float restX, float restY, float restD)
{
    uint x = clothX(i);
    uint y = clothY(i);
    uint bits = 0u;
    float thr = max(tear_threshold, 0.01);

    if (x + 1u < GRID_W)
    {
        if ((length(gLoad(i + 1u) - p) - restX) / restX > thr) bits |= 0x1u;
    }
    if (y + 1u < GRID_H)
    {
        if ((length(gLoad(i + GRID_W) - p) - restY) / restY > thr) bits |= 0x2u;
    }
    if (x + 1u < GRID_W)
    {
        if (y + 1u < GRID_H)
        {
            if ((length(gLoad(i + GRID_W + 1u) - p) - restD) / restD > thr) bits |= 0x4u;
            if ((length(gLoad(i + 1u) - gLoad(i + GRID_W)) - restD) / restD > thr) bits |= 0x8u;
        }
    }
    return bits;
}

// Compliance mapping and calibration guidance live in _shared/xpbd/xpbd.hlsli.

// ---------------------------------------------------------------------------

[numthreads(1024, 1, 1)]
void main(uint3 gtid : SV_GroupThreadID)
{
    const uint tid = gtid.x;
    const uint i0 = tid;
    const uint i1 = tid + SOLVE_GROUP;

    // ---- load -------------------------------------------------------------
    ClothPoint p0 = State[i0];
    ClothPoint p1 = State[i1];

    InteractState touch = Touch[0];

    // The R key can only bump a counter (a shader cannot write a parameter), so
    // the "already handled" value is parked in particle 0's spare field and
    // every thread compares against the same broadcast read. Reading it here,
    // before any store, keeps it race-free.
    float resetSeen = State[0].pad.x;
    bool resetNow = (reset_cloth != 0) || (touch.resetRequest != resetSeen);

    bool init0 = (p0.flags & CF_INIT) != 0u && !resetNow;
    bool init1 = (p1.flags & CF_INIT) != 0u && !resetNow;

    float3 x0 = init0 ? p0.position : spawnPosition(i0);
    float3 x1 = init1 ? p1.position : spawnPosition(i1);
    float3 v0 = init0 ? p0.velocity : float3(0.0, 0.0, 0.0);
    float3 v1 = init1 ? p1.velocity : float3(0.0, 0.0, 0.0);

    // A single NaN would spread through the whole sheet within a few cooks.
    if (!all(isfinite(x0)) || !all(isfinite(v0))) { x0 = spawnPosition(i0); v0 = 0.0; }
    if (!all(isfinite(x1)) || !all(isfinite(v1))) { x1 = spawnPosition(i1); v1 = 0.0; }

    uint brk0 = init0 ? ((p0.flags >> 8u) & 0xFu) : 0u;
    uint brk1 = init1 ? ((p1.flags >> 8u) & 0xFu) : 0u;

    if (tid < (PCOUNT / 8u)) gBrk[tid] = 0u;
    gStore(i0, x0);
    gStore(i1, x1);
    GroupMemoryBarrierWithGroupSync();

    if (brk0 != 0u) InterlockedOr(gBrk[i0 >> 3u], brk0 << ((i0 & 7u) * 4u));
    if (brk1 != 0u) InterlockedOr(gBrk[i1 >> 3u], brk1 << ((i1 & 7u) * 4u));
    GroupMemoryBarrierWithGroupSync();

    // ---- solver constants -------------------------------------------------
    const float w0 = invMassFor(i0);
    const float w1 = invMassFor(i1);

    float frameDt = clamp(_DeltaTime, 1.0 / 2000.0, 1.0 / 30.0) * time_scale;
    uint  nsub = (uint)clamp(substeps, 2, 40);
    uint  nsweep = (uint)clamp(sweeps, 1, 8);
    float h = frameDt / (float)nsub;
    float invH = 1.0 / max(h, 1e-9);
    float hh = max(h * h, 1e-12);

    // rest_scale changes what the cloth WANTS to be, independently of how hard it
    // insists. Above 1 there is more material than the frame (slack, folds); below
    // 1 the sheet wants to be smaller than its frame and pulls drum-taut. Scaling
    // here means the strain metric and the tear test inherit it automatically.
    float restScale = max(rest_scale, 0.01);
    float restX = restScale * cloth_width / (float)(GRID_W - 1u);
    float restY = restScale * cloth_height / (float)(GRID_H - 1u);
    float restD = sqrt(restX * restX + restY * restY);

    // Compliance ranges calibrated against CUMULATIVE effect, which is the part
    // that is easy to get wrong. alphaTilde = compliance / h^2, and a single
    // application only removes a fraction of the error - but every constraint
    // runs nsub * nsweep times per cook (48 at the defaults). A per-application
    // strength that looks gentle still converges to fully enforced.
    //
    // For the curvature constraint, one application scales curvature by
    // (1 - 1.5 / (denom + alphaTilde)) with denom ~1.5, so over 48 applications:
    //
    //   compliance 1e-3 -> alphaTilde ~900 -> ~7% curvature removed per cook
    //   compliance 1e-4 -> alphaTilde ~90  -> ~50%  (soft cloth)
    //   compliance 1e-6 -> alphaTilde ~0.9 -> ~100% (rigid card)
    //
    // Stretch WANTS to be fully enforced - that is inextensibility. Bending must
    // stay genuinely partial or the sheet irons itself flat and stops reading as
    // fabric at all.
    float aStretch = xpbd_compliance(stretch_stiffness, -1.0, -8.0) / hh;
    float aShear   = xpbd_compliance(shear_stiffness,   -3.0, -7.0) / hh;
    float aBend    = xpbd_compliance(bend_stiffness,    -3.0, -6.5) / hh;

    float3 gravityAccel = float3(0.0, -gravity, 0.0);
    float velDecay = exp(-max(damping, 0.0) * h);
    float lraSlack = 1.0 + max(long_range_slack, 0.0);

    // ---- substeps ---------------------------------------------------------
    // ---- audio strike -----------------------------------------------------
    // A velocity impulse, applied once, before the substeps. An impulse is the
    // right primitive: it is frame-rate independent by construction (a change in
    // velocity, not a force integrated over time), and a taut sheet then rings
    // outward on its own through the distance constraints. No ripple bookkeeping
    // is needed - the solver IS the wave equation here.
    //
    // Falloff is measured in REST space so the struck patch stays coherent even
    // when the sheet is already folded.
    if (touch.strikeArmed > 0.5 && touch.strikeIndex >= 0.0)
    {
        uint si = (uint)touch.strikeIndex;
        float3 restS = restPosition(si);
        float3 dir = clothNormal(si) * touch.strikeSign;
        float r = max(strike_radius, 1e-3);

        float d0 = length(restPosition(i0) - restS);
        float d1 = length(restPosition(i1) - restS);
        // Gaussian-ish bell: a soft centre with no hard edge, so the wavefront
        // that leaves the strike reads as a ripple rather than a stamped disc.
        float f0 = exp(-(d0 * d0) / (r * r));
        float f1 = exp(-(d1 * d1) / (r * r));

        if (w0 > 0.0) v0 += dir * (strike_gain * f0);
        if (w1 > 0.0) v1 += dir * (strike_gain * f1);
    }

    float3 wind0 = windAt(i0);
    float3 wind1 = windAt(i1);

    [loop]
    for (uint sub = 0u; sub < nsub; ++sub)
    {
        // predict
        float3 prev0 = gLoad(i0);
        float3 prev1 = gLoad(i1);

        // Normals read neighbouring vertices, so they must be sampled before ANY
        // thread starts writing predicted positions.
        float3 n0 = clothNormal(i0);
        float3 n1 = clothNormal(i1);
        GroupMemoryBarrierWithGroupSync();

        float3 a0 = gravityAccel + aeroAccel(n0, v0, wind0);
        float3 a1 = gravityAccel + aeroAccel(n1, v1, wind1);

        if (w0 > 0.0) { v0 += a0 * h; gStore(i0, prev0 + v0 * h); }
        else          { v0 = 0.0; gStore(i0, restPosition(i0)); }
        if (w1 > 0.0) { v1 += a1 * h; gStore(i1, prev1 + v1 * h); }
        else          { v1 = 0.0; gStore(i1, restPosition(i1)); }

        GroupMemoryBarrierWithGroupSync();

        // Constraint sweeps. One sweep per substep is the classic small-step
        // XPBD recipe, but a single Gauss-Seidel pass moves information only one
        // edge along a chain, and the two-corner configuration makes the top row
        // a 63-edge tension chain. Extra sweeps per substep are what actually
        // pull peak LOCAL edge strain down; long-range attachment alone bounds
        // radial distance to an anchor and lets strain distribute unevenly.
        [loop]
        for (uint it = 0u; it < nsweep; ++it)
        {
            // Colliders are resolved at the TOP of each sweep, not only at the
            // end of the substep, so the distance constraints that follow can
            // absorb the stretch the projection introduces.
            //
            // Measured: with collisions only after the sweeps, a sphere drape
            // settled at 17% peak stretch, while the identical configuration
            // with no collider measured 0.012%. All of that stretch was
            // collision pushes that nothing subsequently corrected.
            if (collider_count > 0 || ground_enabled != 0)
            {
                gStore(i0, resolveCollisions(i0, gLoad(i0), prev0, false));
                gStore(i1, resolveCollisions(i1, gLoad(i1), prev1, false));
                GroupMemoryBarrierWithGroupSync();
            }

            sweepFamily(tid, FAM_H,  restX,        aStretch);
            sweepFamily(tid, FAM_V,  restY,        aStretch);
            sweepFamily(tid, FAM_D,  restD,        aShear);
            sweepFamily(tid, FAM_A,  restD,        aShear);
            sweepBending(tid, true,  aBend);
            sweepBending(tid, false, aBend);
        }

        // Long-range pass: no colouring needed, each thread touches only its own
        // vertices, so one barrier closes it.
        if (long_range > 0.001)
        {
            solveLongRange(i0, lraSlack, long_range, restScale);
            solveLongRange(i1, lraSlack, long_range, restScale);
            GroupMemoryBarrierWithGroupSync();
        }

        // Grab before the final collision pass so a grabbed patch can still be
        // pushed out of a sphere rather than dragged through it.
        if (touch.active > 0.5)
        {
            gStore(i0, applyGrab(i0, gLoad(i0), touch));
            gStore(i1, applyGrab(i1, gLoad(i1), touch));
            GroupMemoryBarrierWithGroupSync();
        }

        // Final projection so a substep can never end with a vertex inside a
        // collider. This correction is small because the interleaved passes above
        // already did the work, so it leaves little residual stretch.
        if (collider_count > 0 || ground_enabled != 0)
        {
            gStore(i0, resolveCollisions(i0, gLoad(i0), prev0, true));
            gStore(i1, resolveCollisions(i1, gLoad(i1), prev1, true));
            GroupMemoryBarrierWithGroupSync();
        }

        // recover velocity from the actual position change
        if (w0 > 0.0) v0 = (gLoad(i0) - prev0) * invH * velDecay;
        if (w1 > 0.0) v1 = (gLoad(i1) - prev1) * invH * velDecay;
    }

    // ---- local strain, for shading ---------------------------------------
    float3 f0 = gLoad(i0);
    float3 f1 = gLoad(i1);

    // TENSILE strain only - no abs().
    //
    // Using abs() counted compression as strain, and cloth buckles constantly:
    // a sheet piling on the floor squeezes edges to a fraction of their rest
    // length, which reported as "56% strain" and washed the accent warm over a
    // perfectly healthy drape. Compression is what fabric does; only stretch
    // indicates tension, and only stretch should tear.
    // Severed edges are EXCLUDED. Once an edge tears its endpoints separate
    // freely, so its "strain" grows without bound - it measured 1.77 after a few
    // hundred tears and pinned the warm accent along every torn boundary
    // permanently. Only intact edges carry tension.
    float s0 = 0.0, s1 = 0.0;
    {
        uint x = clothX(i0), y = clothY(i0);
        if (x + 1u < GRID_W) { if ((brokenBits(i0) & 0x1u) == 0u)
            s0 = max(s0, (length(gLoad(i0 + 1u)     - f0) - restX) / restX); }
        if (x > 0u)          { if ((brokenBits(i0 - 1u) & 0x1u) == 0u)
            s0 = max(s0, (length(gLoad(i0 - 1u)     - f0) - restX) / restX); }
        if (y + 1u < GRID_H) { if ((brokenBits(i0) & 0x2u) == 0u)
            s0 = max(s0, (length(gLoad(i0 + GRID_W) - f0) - restY) / restY); }
        if (y > 0u)          { if ((brokenBits(i0 - GRID_W) & 0x2u) == 0u)
            s0 = max(s0, (length(gLoad(i0 - GRID_W) - f0) - restY) / restY); }

        x = clothX(i1); y = clothY(i1);
        if (x + 1u < GRID_W) { if ((brokenBits(i1) & 0x1u) == 0u)
            s1 = max(s1, (length(gLoad(i1 + 1u)     - f1) - restX) / restX); }
        if (x > 0u)          { if ((brokenBits(i1 - 1u) & 0x1u) == 0u)
            s1 = max(s1, (length(gLoad(i1 - 1u)     - f1) - restX) / restX); }
        if (y + 1u < GRID_H) { if ((brokenBits(i1) & 0x2u) == 0u)
            s1 = max(s1, (length(gLoad(i1 + GRID_W) - f1) - restY) / restY); }
        if (y > 0u)          { if ((brokenBits(i1 - GRID_W) & 0x2u) == 0u)
            s1 = max(s1, (length(gLoad(i1 - GRID_W) - f1) - restY) / restY); }
    }
    s0 = max(s0, 0.0);
    s1 = max(s1, 0.0);

    // ---- tearing ----------------------------------------------------------
    uint wasBrk0 = brk0;
    uint wasBrk1 = brk1;
    if (tear_enabled != 0)
    {
        brk0 |= tearBits(i0, f0, restX, restY, restD);
        brk1 |= tearBits(i1, f1, restX, restY, restD);
    }

    // Cut tool: sever every edge inside the blade radius. The blade re-picks
    // each cook while the drag is held, so dragging sweeps a continuous slit.
    if (touch.active > 0.5 && (uint)touch.tool == TOOL_CUT && touch.index >= 0.0)
    {
        float3 restC = restPosition((uint)touch.index);
        float bladeR = max(touch.radius * 0.45, 1e-4);
        if (length(restPosition(i0) - restC) < bladeR) brk0 = 0xFu;
        if (length(restPosition(i1) - restC) < bladeR) brk1 = 0xFu;
    }
    bool fresh0 = (brk0 & ~wasBrk0) != 0u;
    bool fresh1 = (brk1 & ~wasBrk1) != 0u;

    // Cook rate is decoupled from display rate, so every smoothing term is
    // expressed against wall time rather than per cook.
    float strainBlend = 1.0 - exp(-14.0 * frameDt);
    float heatDecay = pow(0.5, frameDt / 0.45);

    p0.position = f0;
    p0.velocity = v0;
    p0.invMass  = w0;
    p0.strain   = lerp(init0 ? p0.strain : 0.0, s0, strainBlend);
    p0.flags    = CF_INIT | (brk0 << 8u);
    p0.tearHeat = fresh0 ? 1.0 : (init0 ? p0.tearHeat : 0.0) * heatDecay;
    // Particle 0 carries the consumed reset counter (see resetSeen above).
    p0.pad      = (i0 == 0u) ? float2(touch.resetRequest, 0.0) : float2(0.0, 0.0);
    State[i0] = p0;

    p1.position = f1;
    p1.velocity = v1;
    p1.invMass  = w1;
    p1.strain   = lerp(init1 ? p1.strain : 0.0, s1, strainBlend);
    p1.flags    = CF_INIT | (brk1 << 8u);
    p1.tearHeat = fresh1 ? 1.0 : (init1 ? p1.tearHeat : 0.0) * heatDecay;
    p1.pad      = float2(0.0, 0.0);
    State[i1] = p1;
}
