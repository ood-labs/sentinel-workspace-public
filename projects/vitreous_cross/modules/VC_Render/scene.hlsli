// VC_Render / scene.hlsli — the distance field, the medium stack and the optics.
//
// The whole renderer rests on one idea: this scene is not a set of surfaces with transparency
// painted on, it is a STACK OF MEDIA. Air contains glass slabs; the slabs contain air cavities
// and denser fluid pockets; opaque plates sit inside the glass. A ray therefore does not "hit
// a surface and get shaded" — it crosses interfaces, and at each one the only questions are
// which medium it was in, which medium it is entering, and what the Fresnel split is.
//
// That is why the marcher steps on |sdf| (an UNSIGNED distance to the nearest boundary of any
// shape) rather than on the usual signed union. A signed union can only find the outside of
// the outermost object; the unsigned field finds the next interface no matter which side of
// which shape the ray is currently on, which is exactly what medium tracking needs.
#ifndef VC_SCENE_HLSLI
#define VC_SCENE_HLSLI

#include "../_shared/vitreous.hlsli"

StructuredBuffer<VcRec> Plan : register(t0);

// ---------------------------------------------------------------------------
// Shape identity. Slabs and panels are individually addressable because a ray needs the
// normal of the ONE surface it is standing on; the inclusions are a single fused shape
// because that is what they physically are — one connected body of trapped air.
// ---------------------------------------------------------------------------
#define SH_SLAB_0   0
#define SH_INC      12
#define SH_PANEL_0  13
#define SH_CYC      23
#define SH_NONE     (-1)

#define MED_AIR     (-1)

// Cavity surface deformation, as a fraction of the record's own smallest radius at
// inclusion_wobble = 1. vcIncLipschitz() is derived from this and must be kept in step with it.
#define VC_WOBBLE_K 0.32

// Per-thread scene constants, filled by vcSetupScene() before any march.
static float3 gIncC = float3(0, 0, 0);      // inclusion bounding sphere
static float  gIncR = 0.0;
static float3x3 gRot = float3x3(1,0,0, 0,1,0, 0,0,1);   // assembly local -> world
static float3 gKeyStage = float3(0, 1, 0);  // key direction, in stage space

// ---------------------------------------------------------------------------
// Stage <-> world. The assembly's orientation belongs to VC_Plan, so it arrives on the stage
// record; the renderer only applies it. Marching happens in STAGE space, where every slab is
// axis-aligned and its distance function is a plain box — rotating the ray once at entry is
// far cheaper than rotating twenty boxes at every step.
// ---------------------------------------------------------------------------
float3 vcWorldToStage(float3 v) { return vc_toStage(mul(v, gRot)); }   // mul(v, M) == M^T * v
float3 vcStageToWorld(float3 v) { return mul(gRot, vc_toWorld(v)); }

void vcSetupScene()
{
    VcRec st = Plan[VC_STAGE];
    float yaw = st.pos.x, pitch = st.pos.y;
    float cy = cos(yaw), sy = sin(yaw), cp = cos(pitch), sp = sin(pitch);
    float3x3 Ry = float3x3(cy, 0, sy,  0, 1, 0,  -sy, 0, cy);
    float3x3 Rx = float3x3(1, 0, 0,  0, cp, -sp,  0, sp, cp);
    gRot = mul(Ry, Rx);

    // Bounding sphere over the live inclusions, so the expensive fused field is only evaluated
    // when a sample point is actually near the organic mass. Without this gate the sixteen
    // ellipsoids are paid for on every step of every ray in the frame.
    float3 lo = float3(1e9, 1e9, 1e9), hi = float3(-1e9, -1e9, -1e9);
    bool any = false;
    for (uint i = 0u; i < VC_INCS; i++)
    {
        VcRec r = Plan[VC_INC_0 + i];
        if (r.active > 0.5)
        {
            float3 e = r.dims * 1.35;
            lo = min(lo, r.pos - e);
            hi = max(hi, r.pos + e);
            any = true;
        }
    }
    if (any) { gIncC = (lo + hi) * 0.5; gIncR = length(hi - lo) * 0.5; }
    else     { gIncC = float3(0, 0, 0); gIncR = -1.0; }

    gKeyStage = normalize(vcWorldToStage(normalize(float3(key_dir_x, key_dir_y, key_dir_z))));
}

// ---------------------------------------------------------------------------
// Primitives
// ---------------------------------------------------------------------------

// Surface wobble on the inclusions. Deliberately trigonometric rather than value noise:
// this expression is inlined into the march loop AND into the four taps of every normal, and
// a lattice noise there costs minutes of fxc for detail nobody can see at this scale.
// Its Lipschitz contribution is bounded by amp * freq, which vcIncLipschitz() reports so the
// marcher can shorten its step by exactly that and no more.
float vcWobble(float3 q, float seed, float amp, float freq)
{
    float3 a = q * freq + seed;
    return amp * (sin(a.x) * sin(a.y * 1.13) * sin(a.z * 0.87) * 0.62
                + sin(a.x * 2.1 + 1.7) * sin(a.y * 1.87) * sin(a.z * 2.31) * 0.24);
}

float vcSlabSDF(uint i, float3 p)
{
    VcRec r = Plan[VC_SLAB_0 + i];
    if (r.active < 0.5) return 1e6;
    return vc_roundBox(p - r.pos, r.dims, r.p0);
}

float vcPanelSDF(uint j, float3 p)
{
    VcRec r = Plan[VC_PANEL_0 + j];
    if (r.active < 0.5) return 1e6;
    return vc_box(p - r.pos, r.dims);
}

// The fused organic mass, plus the material of whichever record dominates at this point.
float vcIncSDF(float3 p, out int mat)
{
    float d = 1e9, plain = 1e9, kMax = 0.0, bestOwn = 1e9;
    mat = MAT_CAVITY;
    for (uint i = 0u; i < VC_INCS; i++)
    {
        VcRec r = Plan[VC_INC_0 + i];
        if (r.active > 0.5)
        {
            float3 q = p - r.pos;
            // Amplitude is a FRACTION OF THE RECORD'S OWN RADIUS, so a small bubble is
            // deformed as much as a large one in proportion rather than in absolute units —
            // otherwise one setting either flattens the small lobes or leaves the large ones
            // looking machined. At 0.11 the deformation was 7% of the radius and read as
            // perfect spheres; the reference's masses are visibly irregular.
            float amp = r.p1 * VC_WOBBLE_K * min(r.dims.x, min(r.dims.y, r.dims.z));
            float di = vc_ellipsoid(q, r.dims) - vcWobble(q, r.seed, amp, wobble_freq);
            float kk = max(r.p0, 0.005);
            plain = min(plain, di);
            kMax = max(kMax, kk);
            d = vc_fuse(d, di, kk);
            // material follows the NEAREST contributing record, so a dense pocket keeps its
            // own index of refraction even where it has fused into the cavity beside it
            if (di < bestOwn) { bestOwn = di; mat = (int)r.mat; }
        }
    }
    // Iterated smooth-min compounds: sixteen fuses accumulate sixteen blend radii and inflate
    // a phantom shell well outside every contributing ellipsoid. Bounding the result at
    // (plain min - one blend radius) caps the inflation at what a single fuse can do.
    return max(d, plain - kMax);
}

// How much shorter the marcher must step because the wobble bends the field.
//
// This is not a fudge factor — it is the audited Lipschitz bound of the displacement, and it
// has to track VC_WOBBLE_K. Raise the amplitude without raising this and the marcher
// overshoots the displaced surface, which shows up as speckled holes in the membranes rather
// than as anything recognisable as a stepping problem.
float vcIncLipschitz()
{
    float amp = VC_WOBBLE_K * 0.30;                // the largest inclusion's amplitude
    return 1.0 + amp * wobble_freq * 0.9;
}

// The cyclorama: a seamless studio sweep, floor filleted into the back wall. It is real
// geometry rather than a painted backdrop because the reference's contact shadow has to land
// on something, and because refracted rays that exit downward must find a floor there.
//
// It is INTERSECTED ANALYTICALLY rather than marched, for two reasons. First, a floor seen
// from eye height is a grazing plane, and grazing planes are the pathological case for sphere
// tracing: each step advances by the PERPENDICULAR distance, so a ray two degrees below the
// horizon needs several hundred steps to land. At 96 the entire lower half of the frame simply
// failed to find the floor and fell through to the environment — a hard black horizon that
// looked like a shading bug and was a convergence one. Second, taking it out of the step
// function removes a shape from every iteration of every march in the frame.
//
// It also lives in WORLD space. The room is the room; it must not tilt when the assembly's
// orientation changes, and the assembly's orientation is applied in stage space.
bool vcCycHit(float3 o, float3 d, out float t, out float3 n)
{
    t = 1e9;
    n = float3(0, 1, 0);
    float F = cyc_floor, B = cyc_back, R = cyc_fillet;
    float yc = F + R, zc = B + R;
    bool got = false;

    // floor plane, valid beyond the fillet
    if (d.y < -1e-6)
    {
        float tf = (F - o.y) / d.y;
        if (tf > 1e-4 && (o.z + d.z * tf) >= zc) { t = tf; n = float3(0, 1, 0); got = true; }
    }
    // back wall, valid above the fillet
    if (d.z < -1e-6)
    {
        float tw = (B - o.z) / d.z;
        if (tw > 1e-4 && tw < t && (o.y + d.y * tw) >= yc) { t = tw; n = float3(0, 0, 1); got = true; }
    }
    // the fillet itself: a cylinder along x. The room is INSIDE it and the material outside,
    // so the ray leaves the room through the far root, and the surface normal points back
    // toward the axis.
    float a = d.y * d.y + d.z * d.z;
    if (a > 1e-9)
    {
        float oy = o.y - yc, oz = o.z - zc;
        float b = 2.0 * (d.y * oy + d.z * oz);
        float c = oy * oy + oz * oz - R * R;
        float disc = b * b - 4.0 * a * c;
        if (disc >= 0.0)
        {
            float sq = sqrt(disc);
            float tc = (-b + sq) / (2.0 * a);
            if (tc > 1e-4 && tc < t)
            {
                float3 p = o + d * tc;
                if (p.y < yc && p.z < zc)
                {
                    t = tc;
                    n = normalize(float3(0.0, -(p.y - yc), -(p.z - zc)));
                    got = true;
                }
            }
        }
    }
    return got;
}

// Signed union of everything that can block light. Used only by the shadow trace, where the
// medium does not matter and only the silhouette does.
float vcOccluderSDF(float3 p)
{
    float d = 1e9;
    for (uint i = 0u; i < VC_SLABS; i++)  d = min(d, vcSlabSDF(i, p));
    for (uint j = 0u; j < VC_PANELS; j++) d = min(d, vcPanelSDF(j, p));
    if (gIncR > 0.0)
    {
        float bs = length(p - gIncC) - gIncR;
        if (bs < 0.30) { int m; d = min(d, vcIncSDF(p, m)); }
        else           d = min(d, bs);
    }
    return d;
}

// Dispatcher, used only for normals — one shape at a time, never in the march loop.
float vcShapeSDF(int id, float3 p)
{
    if (id == SH_INC) { int m; return vcIncSDF(p, m); }
    if (id >= SH_PANEL_0) return vcPanelSDF((uint)(id - SH_PANEL_0), p);
    return vcSlabSDF((uint)id, p);
}

float3 vcNormal(int id, float3 p)
{
    float e = normal_eps;
    float2 k = float2(1.0, -1.0);
    return normalize(k.xyy * vcShapeSDF(id, p + k.xyy * e) +
                     k.yyx * vcShapeSDF(id, p + k.yyx * e) +
                     k.yxy * vcShapeSDF(id, p + k.yxy * e) +
                     k.xxx * vcShapeSDF(id, p + k.xxx * e));
}

// ---------------------------------------------------------------------------
// The unsigned boundary field. THIS is the marcher's step function: distance to the nearest
// interface of any kind, from either side, plus which shape owns it.
// ---------------------------------------------------------------------------
float vcBoundary(float3 p, out int id)
{
    float best = 1e9;
    id = SH_NONE;

    for (uint i = 0u; i < VC_SLABS; i++)
    {
        float a = abs(vcSlabSDF(i, p));
        if (a < best) { best = a; id = SH_SLAB_0 + (int)i; }
    }
    for (uint j = 0u; j < VC_PANELS; j++)
    {
        float a = abs(vcPanelSDF(j, p));
        if (a < best) { best = a; id = SH_PANEL_0 + (int)j; }
    }
    if (gIncR > 0.0)
    {
        // Outside the gate the bounding sphere's own distance is a valid conservative bound,
        // so the sixteen ellipsoids cost nothing until the ray is actually near the mass.
        float bs = length(p - gIncC) - gIncR;
        if (bs < 0.30)
        {
            int m;
            float a = abs(vcIncSDF(p, m));
            if (a < best) { best = a; id = SH_INC; }
        }
        else if (bs < best) { best = bs; id = SH_INC; }
    }
    // The cyclorama is deliberately NOT here. It is intersected analytically per segment; see
    // vcCycHit(). Leaving it in this loop cost a shape on every step of every ray and still
    // failed to converge on a grazing floor.
    return best;
}

// Which medium contains this point. Priority is physical: an opaque plate wins over
// everything, an inclusion is a hole in the glass and so wins over a slab, and a slab wins
// over air. Overlapping slabs resolve to the nearest containing one.
int vcMediumAt(float3 p, out float3 tint)
{
    tint = float3(1, 1, 1);

    for (uint j = 0u; j < VC_PANELS; j++)
    {
        if (vcPanelSDF(j, p) < 0.0)
        {
            VcRec r = Plan[VC_PANEL_0 + j];
            tint = r.tint;
            return (int)r.mat;
        }
    }
    if (gIncR > 0.0 && length(p - gIncC) - gIncR < 0.02)
    {
        int m;
        if (vcIncSDF(p, m) < 0.0) return m;
    }
    float bestD = 0.0; int bestM = MED_AIR;
    for (uint i = 0u; i < VC_SLABS; i++)
    {
        float d = vcSlabSDF(i, p);
        if (d < bestD) { bestD = d; bestM = (int)Plan[VC_SLAB_0 + i].mat; tint = Plan[VC_SLAB_0 + i].tint; }
    }
    return bestM;
}

// ---------------------------------------------------------------------------
// Optics
// ---------------------------------------------------------------------------

// Index of refraction at a wavelength. Cauchy's relation, with the dispersion coefficient
// scaled by a control: real optical glass splits by only ~0.008 across the visible band, which
// is invisible at this scale, and the reference plainly does not obey it. The default runs
// several times physical so the fringes read, and `dispersion = 1` is the true material.
float vcIOR(int m, float lambdaUM)
{
    if (m < 0 || m == MAT_CAVITY) return 1.0;    // air does not disperse
    float base = vc_ior(m);
    float B = 0.00354 * dispersion;
    return base + B * (1.0 / (lambdaUM * lambdaUM) - 1.0 / (0.5876 * 0.5876));
}

// Exact unpolarized Fresnel. Schlick is fine for opaque conductors and wrong here: at the
// grazing angles a stack of boxes produces constantly, the difference between Schlick and
// the real curve is the difference between glass and cellophane.
float vcFresnel(float cosI, float n1, float n2)
{
    float eta = n1 / n2;
    float sinT2 = eta * eta * (1.0 - cosI * cosI);
    if (sinT2 >= 1.0) return 1.0;                // total internal reflection
    float cosT = sqrt(1.0 - sinT2);
    float rs = (n1 * cosI - n2 * cosT) / (n1 * cosI + n2 * cosT);
    float rp = (n1 * cosT - n2 * cosI) / (n1 * cosT + n2 * cosI);
    return saturate(0.5 * (rs * rs + rp * rp));
}

// Thin-film interference across a membrane of a given physical thickness — the real Airy
// summation, not a hue ramp. Because the reflectance depends on the optical path difference
// 2*n*d*cos(theta_t) divided by the wavelength, the bands COMPRESS toward grazing incidence
// and MARCH with thickness. That behaviour is the entire tell of a soap membrane, and no
// amount of rainbow gradient reproduces it.
float vcThinFilm(float lambdaNM, float thickNM, float cosI, float n1, float n2)
{
    float eta = n1 / n2;
    float sinT2 = eta * eta * (1.0 - cosI * cosI);
    if (sinT2 >= 1.0) return 1.0;
    float cosT = sqrt(1.0 - sinT2);
    float rs = (n1 * cosI - n2 * cosT) / (n1 * cosI + n2 * cosT);
    float R1 = rs * rs;
    float delta = 12.5663706 * n2 * thickNM * cosT / max(lambdaNM, 1.0);
    float cd = cos(delta);
    float num = 2.0 * R1 * (1.0 - cd);
    float den = 1.0 + R1 * R1 - 2.0 * R1 * cd;
    return saturate(num / max(den, 1e-6));
}

// Membrane thickness at a point, in nanometres. Varying it across the surface is what turns
// a uniform tint into the reference's drifting bands.
float vcFilmThickness(float3 p)
{
    float n = vcWobble(p, 3.7, 1.0, film_grain);
    return film_thickness * (1.0 + film_variance * n);
}

// Wavelength -> linear RGB response. Three overlapping lobes, close enough to CIE for a
// spectral march; the red lobe keeps its short-wavelength tail so violet reads violet rather
// than pure blue.
float3 vcSpectralWeight(float lambdaNM)
{
    float r = exp(-pow((lambdaNM - 600.0) / 52.0, 2.0)) + 0.32 * exp(-pow((lambdaNM - 450.0) / 30.0, 2.0));
    float g = exp(-pow((lambdaNM - 546.0) / 46.0, 2.0));
    float b = exp(-pow((lambdaNM - 456.0) / 42.0, 2.0));
    return float3(r, g, b);
}

#endif
