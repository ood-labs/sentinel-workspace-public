#ifndef SENTINEL_XPBD_HLSLI
#define SENTINEL_XPBD_HLSLI

// Sentinel XPBD (Extended Position Based Dynamics) constraint vocabulary.
//
// Solves POSITIONS directly with a compliance term instead of integrating
// spring forces, so it is unconditionally stable at any stiffness. A mass-spring
// model is only conditionally stable, which caps usable stiffness and makes
// cloth read as rubber; XPBD can be genuinely inextensible.
//
// Every function here is pure: it takes positions and inverse masses and returns
// position DELTAS. It never touches groupshared, a buffer, or a parameter, so a
// consumer module owns its own storage layout and dispatch shape. Callers are
// expected to add the deltas and handle their own synchronisation.
//
// ---------------------------------------------------------------------------
// The substep rule
// ---------------------------------------------------------------------------
// Small-substep XPBD (Macklin et al. 2019): MANY substeps with ONE constraint
// sweep each converges far better than one substep with many sweeps, for the
// same total work, and needs no per-constraint lambda accumulation. Prefer
// raising the substep count over raising the sweep count.
//
// ---------------------------------------------------------------------------
// Calibrating compliance (read this before choosing a range)
// ---------------------------------------------------------------------------
// alphaTilde = compliance / h^2, and it only bites when it is comparable to the
// constraint's inverse-mass denominator (~1-2). The trap is that a constraint
// runs substeps * sweeps times per cook, so CUMULATIVE enforcement approaches
// total even when each application looks gentle. Calibrate against the product,
// never against a single application.
//
// Measured on a 64x32 cloth at 16 substeps x 3 sweeps (h^2 ~= 1.1e-6):
//
//   compliance 1e-8 -> alphaTilde ~0.01  effectively rigid
//   compliance 1e-6 -> alphaTilde ~0.9   firm
//   compliance 1e-4 -> alphaTilde ~90    soft but clearly present
//   compliance 1e-3 -> alphaTilde ~900   nearly inert per application, yet
//                                        still ~2% of the error per COOK
//
// Constraints that should be fully enforced (stretch, in a cloth) want the rigid
// end. Constraints that must stay partial (bending) need the soft end, or the
// surface irons itself flat and stops reading as fabric.
//
// ---------------------------------------------------------------------------
// Graph colouring on a regular grid
// ---------------------------------------------------------------------------
// Gauss-Seidel needs constraints in a sweep to touch disjoint vertices. On a
// grid this is a parity question, and the answer differs by constraint shape:
//
//   distance, axis-aligned (i, i+1)      2 colours on x parity
//   distance, vertical     (i, i+W)      2 colours on y parity
//   distance, diagonal     (i, i+W+1)    2 colours on x parity
//   distance, antidiagonal (i+W, i+1)    2 colours on x parity
//   curvature triplet      (i-1, i, i+1) 3 colours on centre index mod 3
//
// Triplets need THREE because centres 1 OR 2 apart share a vertex. Within a
// colour every write targets a distinct vertex, so no atomics are needed.
// ---------------------------------------------------------------------------

// stiffness 0..1 -> compliance, log-mapped between two exponents.
float xpbd_compliance(float stiffness, float softExp, float hardExp)
{
    return pow(10.0, lerp(softExp, hardExp, saturate(stiffness)));
}

float xpbd_alpha_tilde(float compliance, float h)
{
    return compliance / max(h * h, 1e-12);
}

// ---------------------------------------------------------------------------
// Distance constraint. Holds |pi - pj| at rest.
// ---------------------------------------------------------------------------
void xpbd_distance_delta(float3 pi, float3 pj, float wi, float wj,
                         float rest, float alphaTilde,
                         out float3 dpi, out float3 dpj)
{
    dpi = float3(0.0, 0.0, 0.0);
    dpj = float3(0.0, 0.0, 0.0);

    float wsum = wi + wj;
    if (wsum <= 0.0) return;

    float3 d = pi - pj;
    float len = length(d);
    if (len < 1e-7) return;

    float3 n = d / len;
    float lambda = -(len - rest) / (wsum + alphaTilde);
    dpi =  n * (lambda * wi);
    dpj = -n * (lambda * wj);
}

// ---------------------------------------------------------------------------
// Curvature (bending) constraint over a straight-at-rest triplet a-b-c.
//
// Use this rather than a distance constraint between the 2-away pair. A distance
// constraint is exactly satisfied by an INVERTED fold: once a crease folds back
// through itself the rest length still holds, the solver reports no error, and
// the crease locks forever - the sheet stays visibly knotted. Constraining the
// curvature vector (how far b sits off the midpoint of a and c) has a single
// preferred state, so it always pushes a fold open.
//
// Gradients: d/db = 1, d/da = d/dc = -1/2.
// ---------------------------------------------------------------------------
void xpbd_curvature_delta(float3 pa, float3 pb, float3 pc,
                          float wa, float wb, float wc,
                          float alphaTilde,
                          out float3 da, out float3 db, out float3 dc)
{
    da = float3(0.0, 0.0, 0.0);
    db = float3(0.0, 0.0, 0.0);
    dc = float3(0.0, 0.0, 0.0);

    float denom = wb + 0.25 * (wa + wc);
    if (denom <= 0.0) return;

    float3 k = pb - 0.5 * (pa + pc);
    float3 lambda = k / (denom + alphaTilde);

    db = -lambda * wb;
    da =  lambda * wa * 0.5;
    dc =  lambda * wc * 0.5;
}

// ---------------------------------------------------------------------------
// Long-range attachment (Kim / Chentanez / Mueller-Fischer 2012).
//
// The constraint that makes a DEEP sheet inextensible. Local edge sweeps carry an
// anchor's influence only about one row per iteration, so a sheet hanging from
// few anchors stretches regardless of edge stiffness or substep count. Tying
// every vertex directly to its nearest anchor with an inequality on the rest
// distance fixes it in one sweep.
//
// Measured on a 32-row cloth, two-corner hang, settled from reset:
//   without: 5.8% peak stretch     with: 1.6%
//
// Nearly free because the anchor has infinite mass (the whole correction goes to
// the free vertex, so no colouring is needed - each thread writes only its own
// vertices) and, for a FLAT rest shape, Euclidean rest distance IS the geodesic
// distance across the sheet.
//
// It is an INEQUALITY: it only ever pulls inward, never pushes out.
// ---------------------------------------------------------------------------
float3 xpbd_long_range(float3 p, float3 anchor, float maxDist, float strength)
{
    float3 d = p - anchor;
    float len = length(d);
    if (len <= maxDist || len < 1e-7) return p;
    float3 target = anchor + d * (maxDist / len);
    return lerp(p, target, saturate(strength));
}

// ---------------------------------------------------------------------------
// Collision projections.
//
// Two ordering rules earned the hard way:
//
// 1. Interleave, do not append. Collisions resolved only AFTER the constraint
//    sweeps leave the stretch they introduce uncorrected for the whole substep.
//    Resolve at the top of each sweep so the distance constraints can absorb it,
//    then once more at the end so a substep cannot end inside a collider.
//
// 2. Apply friction ONCE per substep, in that final pass only. Friction measures
//    the tangential motion of the whole substep; applying it in every interleaved
//    pass re-shaves the same displacement and compounds into glue, and the cloth
//    then STRETCHES to conform to a collider instead of sliding across it.
//    Measured on a sphere drape: 0.78% peak stretch applied once, 18% compounded.
// ---------------------------------------------------------------------------

// Removes a fraction of the tangential motion made since prevP.
// mu is that fraction: 0 frictionless, 1 fully static.
float3 xpbd_friction(float3 p, float3 prevP, float3 nrm, float mu)
{
    float3 dp = p - prevP;
    float3 tangential = dp - dot(dp, nrm) * nrm;
    return p - tangential * saturate(mu);
}

// Half-space y >= planeY.
float3 xpbd_plane_project(float3 p, float planeY, out bool hit)
{
    hit = p.y < planeY;
    if (hit) p.y = planeY;
    return p;
}

float3 xpbd_sphere_project(float3 p, float3 center, float radius,
                           out bool hit, out float3 nrm)
{
    float3 d = p - center;
    float len = length(d);
    hit = (len < radius) && (len > 1e-6);
    nrm = hit ? d / len : float3(0.0, 1.0, 0.0);
    return hit ? center + nrm * radius : p;
}

#endif // SENTINEL_XPBD_HLSLI
