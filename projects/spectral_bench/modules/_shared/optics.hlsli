// optics.hlsli — the 2D light-transport kernel for spectral_bench.
//
// ONE implementation of intersection, refraction, reflection and dispersion, called by TWO nodes
// at two different budgets:
//
//   LT_Bench  traces a CHIEF path (3 wavelengths, the selected emitter) to draw the diagram and
//             to answer "did light actually reach this element".
//   LT_Trace  traces the full spectral fan (up to 48 wavelengths x 12 rays x 2 branches).
//
// They must not be two implementations. A diagram that reconstructs the path with its own maths
// will eventually disagree with the renderer, and the disagreement presents as a physics bug in
// a picture rather than as a mismatch between two files.
//
// CONVENTIONS
//   Bench space, y DOWN. Angles are radians, atan2(y, x), so a positive angle rotates from +x
//   toward +y = DOWNWARD on screen. Every readout converts to degrees at the last moment.
//
//   `hdg` means a different thing per element kind, and this is the one place it is written down:
//     PRISM            axis from the APEX toward the base midpoint
//     LENS             the optical axis
//     MIRROR/SPLITTER/
//     SCREEN/BLOCK     the surface NORMAL (the face runs perpendicular to it)
//     SLAB             the normal of the first face pair
#ifndef SPECTRAL_OPTICS_HLSLI
#define SPECTRAL_OPTICS_HLSLI

#include "../_shared/bench.hlsli"

#define LT_EPS  1e-5
#define LT_FAR  1e9

float2 ltDir(float a)  { return float2(cos(a), sin(a)); }
float2 ltPerp(float2 v) { return float2(-v.y, v.x); }

// ---------------------------------------------------------------------------------------------
// Spectral colour.
//
// The palette of this whole piece is DERIVED, not chosen: fan colours come from the actual CIE
// observer at the actual wavelength being traced. Analytic multi-lobe Gaussian fit to the 1931
// 2-degree colour matching functions (Wyman/Sloan/Shirley, JCGT 2013), then XYZ -> linear sRGB.
// ---------------------------------------------------------------------------------------------
float ltGauss(float x, float mu, float s1, float s2)
{
    float t = (x - mu) * ((x < mu) ? (1.0 / max(s1, 1e-4)) : (1.0 / max(s2, 1e-4)));
    return exp(-0.5 * t * t);
}

float3 ltWavelengthXYZ(float wl)
{
    float x = 1.056 * ltGauss(wl, 599.8, 37.9, 31.0)
            + 0.362 * ltGauss(wl, 442.0, 16.0, 26.7)
            - 0.065 * ltGauss(wl, 501.1, 20.4, 26.2);
    float y = 0.821 * ltGauss(wl, 568.8, 46.9, 40.5)
            + 0.286 * ltGauss(wl, 530.9, 16.3, 31.1);
    float z = 1.217 * ltGauss(wl, 437.0, 11.8, 36.0)
            + 0.681 * ltGauss(wl, 459.0, 26.0, 13.8);
    return float3(x, y, z);
}

// Linear sRGB. Negative components are real (the spectral locus is outside the sRGB gamut) and
// are clamped, which is exactly what a camera does to a monochromatic source.
float3 ltWavelengthRGB(float wl)
{
    float3 c = ltWavelengthXYZ(wl);
    float3 rgb = float3(
        dot(c, float3( 3.2406, -1.5372, -0.4986)),
        dot(c, float3(-0.9689,  1.8758,  0.0415)),
        dot(c, float3( 0.0557, -0.2040,  1.0570)));
    return max(rgb, 0.0);
}

// The luminous weight of a wavelength, so a flat-energy white beam integrates to something that
// reads as white rather than as green. Normalized so the whole visible band sums to ~1 per
// sample when divided by the sample count.
float ltLuminousWeight(float wl)
{
    return max(ltWavelengthXYZ(wl).y, 0.0);
}

// A wavelength sample for lane `i` of `n`, plus the source spectrum's power there.
float ltLaneWavelength(uint i, uint n, int spectrum, float band0, float band1)
{
    float t = (n <= 1u) ? 0.5 : ((float)i / (float)(n - 1u));
    if (spectrum == SP_TRIAD)
    {
        // Three discrete laser lines. Not a continuum — the fan becomes three hard beams, which
        // is a completely different and equally real look.
        uint k = (uint)floor(t * 2.999);
        return (k == 0u) ? 450.0 : ((k == 1u) ? 532.0 : 638.0);
    }
    if (spectrum == SP_BAND)
    {
        float c = clamp(band0, WL_MIN, WL_MAX);
        float w = clamp(band1, 4.0, 300.0);
        return clamp(c + (t - 0.5) * w, 380.0, 740.0);
    }
    return lerp(WL_MIN, WL_MAX, t);
}

float ltSpectrumPower(float wl, int spectrum)
{
    if (spectrum == SP_TUNGSTEN)
    {
        // Warm roll-off: strongly red-weighted, which pushes the fan's energy toward the long end
        // and makes the violet tail almost vanish. A tungsten bench really does look like this.
        float t = saturate((wl - WL_MIN) / (WL_MAX - WL_MIN));
        return lerp(0.18, 1.0, t * t);
    }
    if (spectrum == SP_TRIAD) return 1.0;
    return 1.0;
}

// ---------------------------------------------------------------------------------------------
// Dielectric interface behaviour.
// ---------------------------------------------------------------------------------------------

// Unpolarized Fresnel reflectance. Returns 1.0 on total internal reflection.
float ltFresnel(float cosi, float n1, float n2)
{
    float ci = saturate(abs(cosi));
    float eta = n1 / max(n2, 1e-4);
    float st2 = eta * eta * (1.0 - ci * ci);
    if (st2 >= 1.0) return 1.0;                 // TIR
    float ct = sqrt(1.0 - st2);
    float rs = (n1 * ci - n2 * ct) / max(n1 * ci + n2 * ct, 1e-6);
    float rp = (n1 * ct - n2 * ci) / max(n1 * ct + n2 * ci, 1e-6);
    return saturate(0.5 * (rs * rs + rp * rp));
}

// `n` must face AGAINST the incident direction (dot(n, d) < 0).
float2 ltReflect2(float2 d, float2 n) { return d - 2.0 * dot(d, n) * n; }

// ---------------------------------------------------------------------------------------------
// MINIMUM DEVIATION.
//
// A prism's orientation is not a free parameter to be dialled in: there is exactly one where the
// ray passes symmetrically, the deviation is stationary, and the spectrum comes out at its
// brightest and least smeared. It is the setting every prism photograph is shot at, including
// the reference. So it is DERIVED from the incoming ray and the glass rather than guessed —
// the same rule as deriving a magnitude from an upstream record, applied to an angle.
//
//   D_min = 2 * asin(n * sin(A/2)) - A
//
// and inside the glass the ray runs parallel to the base, so the apex->base axis is simply
// perpendicular to the internal ray — which is the direction the beam is being bent toward.
float ltMinDeviation(float apex, float n)
{
    float A = clamp(apex, 0.12, 2.5);
    float s = clamp(n * sin(A * 0.5), -1.0, 1.0);
    return 2.0 * asin(s) - A;
}

// `side` +1 bends the beam toward +y (downward on screen), -1 upward.
float ltPrismMinDevHdg(float inHeading, float apex, float n, float side)
{
    float D = ltMinDeviation(apex, n);
    float internal = inHeading + sign(side) * D * 0.5;
    float2 u = ltPerp(ltDir(internal)) * sign(side);   // apex -> base points the way we bend
    return atan2(u.y, u.x);
}

// Returns false on total internal reflection, in which case `outDir` is the reflected direction.
bool ltRefract2(float2 d, float2 n, float n1, float n2, out float2 outDir)
{
    float eta = n1 / max(n2, 1e-4);
    float ci = -dot(d, n);
    float st2 = eta * eta * (1.0 - ci * ci);
    if (st2 >= 1.0) { outDir = ltReflect2(d, n); return false; }
    outDir = normalize(eta * d + (eta * ci - sqrt(1.0 - st2)) * n);
    return true;
}

// ---------------------------------------------------------------------------------------------
// Geometry. Every body is CONVEX, so intersection is one interval [tEnter, tExit] and the same
// clip routine serves triangles, rectangles and lenses.
// ---------------------------------------------------------------------------------------------
struct LtSpan
{
    float  tEnter, tExit;
    float2 nEnter, nExit;   // outward normals at the two bounds
    bool   valid;
};

void ltSpanInit(out LtSpan s)
{
    s.tEnter = -LT_FAR; s.tExit = LT_FAR;
    s.nEnter = float2(0, -1); s.nExit = float2(0, 1);
    s.valid = true;
}

// Clip against the half-space { x : dot(nOut, x) <= d }, nOut pointing OUT of the body.
void ltClipPlane(inout LtSpan s, float2 ro, float2 rd, float2 nOut, float d)
{
    if (!s.valid) return;
    float den = dot(nOut, rd);
    float num = d - dot(nOut, ro);
    if (abs(den) < LT_EPS) { if (num < 0.0) s.valid = false; return; }
    float t = num / den;
    if (den < 0.0) { if (t > s.tEnter) { s.tEnter = t; s.nEnter = nOut; } }   // entering
    else           { if (t < s.tExit)  { s.tExit  = t; s.nExit  = nOut; } }   // leaving
    if (s.tEnter > s.tExit) s.valid = false;
}

// Clip against a disc of radius R centred at c. Used by the lens, whose body is the intersection
// of two discs — so a lens costs exactly the same routine as a prism.
void ltClipDisc(inout LtSpan s, float2 ro, float2 rd, float2 c, float R)
{
    if (!s.valid) return;
    float2 oc = ro - c;
    float b = dot(oc, rd);
    float cq = dot(oc, oc) - R * R;
    float disc = b * b - cq;
    if (disc <= 0.0) { s.valid = false; return; }
    float sq = sqrt(disc);
    float t0 = -b - sq, t1 = -b + sq;
    if (t0 > s.tEnter) { s.tEnter = t0; s.nEnter = normalize((ro + rd * t0) - c); }
    if (t1 < s.tExit)  { s.tExit  = t1; s.nExit  = normalize((ro + rd * t1) - c); }
    if (s.tEnter > s.tExit) s.valid = false;
}

// The three vertices of a prism, in bench space. Isoceles, apex angle `apex`, side length `side`,
// centred on its CENTROID so that rotating it does not also translate it.
void ltPrismVerts(float2 c, float hdg, float side, float apex,
                  out float2 pa, out float2 pb, out float2 pc)
{
    float2 ax = ltDir(hdg);
    float2 pp = ltPerp(ax);
    float ha = clamp(apex, 0.12, 2.5) * 0.5;
    float H = side * cos(ha);            // apex -> base distance
    float W = side * sin(ha);            // half base width
    pa = c - ax * (H * 2.0 / 3.0);       // apex
    float2 bm = c + ax * (H / 3.0);
    pb = bm - pp * W;
    pc = bm + pp * W;
}

// PLACING A PRISM ON A BEAM IS NOT THE SAME AS PUTTING ITS CENTROID ON THE BEAM.
//
// At minimum deviation the internal ray runs PARALLEL TO THE BASE, which means it does not pass
// through the centroid — it runs about H/6 nearer the apex. Centre a prism on the ray and the
// beam enters within a hair of the base vertex, skims the edge, and the fan is thrown by a sliver
// of glass instead of by the body. It looks like a refraction bug and it is a placement bug.
//
// So the prism is positioned by its ENTRY POINT: shift it perpendicular to the arriving ray until
// the midpoint of the entry face lands on that ray.
float2 ltPrismCentreOnRay(float2 pos, float hdg, float sideLen, float apex, float2 ro, float2 rd)
{
    float2 pa, pb, pc;
    ltPrismVerts(pos, hdg, max(sideLen, 1e-4), apex, pa, pb, pc);
    float2 m1 = (pa + pb) * 0.5;
    float2 m2 = (pa + pc) * 0.5;
    float2 n1 = normalize(ltPerp(pb - pa)); if (dot(n1, pos - pa) > 0.0) n1 = -n1;
    float2 n2 = normalize(ltPerp(pc - pa)); if (dot(n2, pos - pa) > 0.0) n2 = -n2;
    float2 E = (dot(n1, rd) < dot(n2, rd)) ? m1 : m2;   // the face most opposed to the ray
    float2 pd = ltPerp(rd);
    return pos + pd * dot(ro - E, pd);
}

// Half-aperture of a biconvex lens: DERIVED from curvature and centre thickness rather than
// carried as a third parameter that could disagree with them.
float ltLensAperture(float R, float th)
{
    float k = max(R - th * 0.5, 0.0);
    return sqrt(max(R * R - k * k, 1e-8));
}

// Full convex-body span for a glass element. Returns false when the ray misses.
bool ltGlassSpan(BenchRec e, float2 ro, float2 rd, out LtSpan s)
{
    ltSpanInit(s);
    int k = (int)e.kind;
    float2 c = e.p0;

    if (k == EK_PRISM)
    {
        float2 pa, pb, pc;
        ltPrismVerts(c, e.hdg, max(e.p1.x, 1e-4), e.r0, pa, pb, pc);
        float2 v[3] = { pa, pb, pc };
        [unroll] for (int i = 0; i < 3; ++i)
        {
            float2 a = v[i], b = v[(i + 1) % 3];
            float2 n = normalize(ltPerp(b - a));
            if (dot(n, c - a) > 0.0) n = -n;      // force OUTWARD
            ltClipPlane(s, ro, rd, n, dot(n, a));
        }
    }
    else if (k == EK_SLAB)
    {
        float2 ax = ltDir(e.hdg);
        float2 pp = ltPerp(ax);
        float hx = max(e.p1.y, 1e-4) * 0.5;       // half thickness along the normal
        float hy = max(e.p1.x, 1e-4);             // half width across the face
        ltClipPlane(s, ro, rd,  ax, dot( ax, c) + hx);
        ltClipPlane(s, ro, rd, -ax, dot(-ax, c) + hx);
        ltClipPlane(s, ro, rd,  pp, dot( pp, c) + hy);
        ltClipPlane(s, ro, rd, -pp, dot(-pp, c) + hy);
    }
    else if (k == EK_LENS)
    {
        float2 ax = ltDir(e.hdg);
        float R  = max(e.r0, 1e-3);
        float th = clamp(e.p1.y, 1e-4, 1.98 * R);
        float off = R - th * 0.5;
        ltClipDisc(s, ro, rd, c - ax * off, R);
        ltClipDisc(s, ro, rd, c + ax * off, R);
        // An aperture stop: a real lens is not an infinite intersection of two spheres, it is
        // ground down to a rim. Without this the "lens" quietly becomes a huge glass boulder.
        float ha = min(ltLensAperture(R, th), max(e.p1.x, 1e-4));
        float2 pp = ltPerp(ax);
        ltClipPlane(s, ro, rd,  pp, dot( pp, c) + ha);
        ltClipPlane(s, ro, rd, -pp, dot(-pp, c) + ha);
    }
    else
    {
        s.valid = false;
    }
    return s.valid && s.tExit > LT_EPS;
}

// A planar element (mirror, splitter, screen, block) is a SEGMENT: centre p0, half-length p1.x,
// running perpendicular to the normal `hdg`.
bool ltPlaneHit(BenchRec e, float2 ro, float2 rd, out float t, out float2 n, out float along)
{
    t = LT_FAR; n = float2(0, -1); along = 0.0;
    float2 nn = ltDir(e.hdg);
    float den = dot(nn, rd);
    if (abs(den) < LT_EPS) return false;
    float tt = dot(nn, e.p0 - ro) / den;
    if (tt <= LT_EPS) return false;
    float2 p = ro + rd * tt;
    float2 tg = ltPerp(nn);
    float u = dot(p - e.p0, tg);
    float h = max(e.p1.x, 1e-4);
    if (abs(u) > h) return false;
    t = tt;
    n = (den < 0.0) ? nn : -nn;     // face the incoming ray
    along = u / h;                   // -1..1 across the face, for screen readouts
    return true;
}

// ---------------------------------------------------------------------------------------------
// Scene query. Nearest interaction along a ray, over every active element.
// ---------------------------------------------------------------------------------------------
struct LtScene
{
    float  t;
    float2 n;         // faces the incoming ray
    int    elem;      // record index, -1 = nothing
    int    kind;
    bool   entering;  // for glass: this hit is the OUTER surface
    float  along;     // planar elements: -1..1 across the face
};

void ltSceneInit(out LtScene h)
{
    h.t = LT_FAR; h.n = float2(0, -1); h.elem = -1; h.kind = -1;
    h.entering = false; h.along = 0.0;
}

// THE BENCH BUFFER IS ADDRESSED THROUGH A MACRO.
//
// Shader Model 5.0 cannot pass a resource as a function argument, and the two callers hold the
// bench in different resource types — LT_Bench writes it as an RWStructuredBuffer while LT_Trace
// reads it as a StructuredBuffer. Indexing is identical for both, so the consuming shader
// declares its buffer, #defines LT_BENCH to it, and THEN includes this file. There is still
// exactly one copy of the physics.
//
// A consumer that only wants colour and geometry (the canvas) simply does not define LT_BENCH,
// and the scene query below is not compiled at all.
#ifdef LT_BENCH

// `insideElem` is the record index of the body the ray is currently travelling inside (-1 in
// air). A ray inside glass must be able to hit that body's FAR surface, which is the one case a
// naive nearest-hit query gets wrong.
LtScene ltTraceScene(float2 ro, float2 rd, int insideElem, int skipElem)
{
    LtScene best; ltSceneInit(best);

    [loop] for (uint i = 0u; i < (uint)LT_MAX_ELEM; ++i)
    {
        uint idx = (uint)LT_ELEM_BASE + i;
        BenchRec e = LT_BENCH[idx];
        if (e.role != ROLE_ELEMENT || e.active < 0.5) continue;
        if (LtFlagF(e.flags, F_OFF)) continue;

        int k = (int)e.kind;

        if (ltIsGlass(k))
        {
            LtSpan s;
            if (!ltGlassSpan(e, ro, rd, s)) continue;
            if ((int)idx == insideElem)
            {
                // Travelling inside this body: the interaction is the EXIT surface.
                if (s.tExit > LT_EPS && s.tExit < best.t)
                {
                    best.t = s.tExit; best.n = -s.nExit;   // flip: face the ray
                    best.elem = (int)idx; best.kind = k; best.entering = false; best.along = 0.0;
                }
            }
            else
            {
                if (s.tEnter > LT_EPS && s.tEnter < best.t && (int)idx != skipElem)
                {
                    best.t = s.tEnter; best.n = s.nEnter;
                    if (dot(best.n, rd) > 0.0) best.n = -best.n;
                    best.elem = (int)idx; best.kind = k; best.entering = true; best.along = 0.0;
                }
            }
        }
        else
        {
            if ((int)idx == skipElem) continue;
            float t; float2 n; float u;
            if (!ltPlaneHit(e, ro, rd, t, n, u)) continue;
            if (t < best.t)
            {
                best.t = t; best.n = n; best.elem = (int)idx; best.kind = k;
                best.entering = true; best.along = u;
            }
        }
    }
    return best;
}

#endif  // LT_BENCH

// ---------------------------------------------------------------------------------------------
// Event vocabulary. Shared by the path buffer, the renderer and the plan's event ladder, so
// "what happened here" has one spelling everywhere.
// ---------------------------------------------------------------------------------------------
#define EV_EMIT     0
#define EV_ENTER    1   // refracted INTO glass
#define EV_EXIT     2   // refracted OUT of glass  <- the dispersing event
#define EV_MIRROR   3   // specular reflection off a mirror
#define EV_FRESNEL  4   // partial reflection at a dielectric face
#define EV_TIR      5   // total internal reflection
#define EV_SCREEN   6   // landed on a detector
#define EV_ABSORB   7   // hit a block
#define EV_ESCAPE   8   // left the bench without hitting anything
#define EV_EXHAUST  9   // ran out of interaction budget
#define EV_COUNT    10

bool ltEventTerminal(int ev) { return ev >= EV_SCREEN; }

// The bench boundary, so an escaping ray still draws a finite segment instead of vanishing.
// Generous, because a beam leaving the frame is part of the picture.
#define LT_BOUND_MIN (-0.60)
#define LT_BOUND_MAX ( 1.60)

float ltBoundExit(float2 ro, float2 rd)
{
    float t = LT_FAR;
    if (abs(rd.x) > LT_EPS)
    {
        float t0 = (LT_BOUND_MIN - ro.x) / rd.x;
        float t1 = (LT_BOUND_MAX - ro.x) / rd.x;
        float tm = max(t0, t1); if (tm > LT_EPS) t = min(t, tm);
    }
    if (abs(rd.y) > LT_EPS)
    {
        float t0 = (LT_BOUND_MIN - ro.y) / rd.y;
        float t1 = (LT_BOUND_MAX - ro.y) / rd.y;
        float tm = max(t0, t1); if (tm > LT_EPS) t = min(t, tm);
    }
    return min(t, 4.0);
}

#endif
