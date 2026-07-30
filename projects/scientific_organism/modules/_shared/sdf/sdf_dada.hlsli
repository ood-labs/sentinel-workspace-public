// sdf_dada.hlsli — kind-indexed object vocabulary for the Dada assemblage (desert_totem
// v2). Each object lives in CANONICAL local space: centred at the origin, ~unit sized,
// so an instance's world size comes from its scale, position from its pos, orientation
// from yaw/tilt/roll. Flat pieces (disc/hoop/crescent/lens/harlequin) face +Z by default.
//
// Requires (included FIRST, in this order):
//   sdf_ops.hlsli      (sd_*, op_*)
//   sdf_extras.hlsli   (sd_bezierTube, obj_baluster)
// No nested includes. Uses sd_/op_ prefixes — do NOT enable features:[sdf].
//
// Kinds: 0 sphere 1 box 2 cone 3 disc 4 hoop 5 crescent 6 lens 7 beachball
//        8 baluster 9 bowl 10 harlequin-wedge 11 rod
#ifndef SDF_DADA_HLSLI
#define SDF_DADA_HLSLI

#define DK_SPHERE   0
#define DK_BOX      1
#define DK_CONE     2
#define DK_DISC     3
#define DK_HOOP     4
#define DK_CRESCENT 5
#define DK_LENS     6
#define DK_BEACH    7
#define DK_BALUSTER 8
#define DK_BOWL     9
#define DK_HARLEQ   10
#define DK_ROD      11
#define DK_COUNT    12

// generous local bounding radius (all canonical objects fit); renderers cull with
// this scaled by the instance's max axis. Baluster is the tall outlier at ~0.6 half.
static const float DADA_BOUND_R = 1.45;

// ---- distance in canonical local space --------------------------------------
// p0/p1/p2 carry per-kind shape params (cone radii, hoop tube, crescent pupil, ...).
float dada_obj(float3 p, int kind, float p0, float p1, float p2)
{
    if (kind == DK_SPHERE) return sd_sphere(p, 1.0);
    if (kind == DK_BOX)    return sd_rbox(p, float3(1.0, 1.0, 1.0), 0.05);
    if (kind == DK_CONE)   return sd_cone(p, 1.0, max(p0, 0.01), max(p1, 0.001));

    if (kind == DK_DISC)   return sd_cyl(float3(p.x, p.z, p.y), max(p0, 0.03), 1.0); // thin disc facing +Z, p0=half-thick
    if (kind == DK_HOOP)   return sd_torus(float3(p.x, p.z, p.y), 1.0, max(p0, 0.02)); // ring facing +Z, p0=tube r

    if (kind == DK_CRESCENT)
    {
        float3 q  = float3(p.x, p.z, p.y);                 // disc plane = local XY, facing +Z
        float white = sd_cyl(q, 0.09, 1.0);
        float3 qb = float3(p.x - p0, p.z, p.y - p1);       // offset pupil in-plane
        float black = sd_cyl(qb, 0.12, max(p2, 0.1));
        return min(white, black);
    }
    if (kind == DK_LENS)
    {
        float3 q = float3(p.x, p.z, p.y);
        float ring = sd_torus(q, 1.0, 0.13);
        float disc = sd_cyl(q, 0.06, 0.92);
        return min(ring, disc);
    }
    if (kind == DK_BEACH)  return sd_sphere(p, 1.0);

    if (kind == DK_BALUSTER) return obj_baluster(p, float3(0.0, -0.58, 0.0)); // centre the ~1.16 stack

    if (kind == DK_BOWL)
    {
        float outer = sd_sphere(p, 1.0);
        float inner = sd_sphere(p, 0.80);
        float bowl  = max(max(outer, -inner), p.y);        // lower hemisphere shell
        float stem  = sd_cone(p - float3(0.0, -0.72, 0.0), 0.40, 0.14, 0.34);
        return min(bowl, stem);
    }
    if (kind == DK_HARLEQ)
    {
        float3 hq = p; hq.z *= 2.4;                         // flatten to a wedge/sail
        return sd_cone(hq, 1.0, max(p0, 0.05), 0.03) / 2.4;
    }
    return sd_capsule(p, float3(0.0, -1.0, 0.0), float3(0.0, 1.0, 0.0), max(p0, 0.02)); // rod
}

// ---- procedural sub-material for the multi-colour kinds ----------------------
// Returns true and writes `col` for kinds that colour themselves from local coords
// (crescent, lens, beachball, harlequin); returns false for solid kinds (use palette).
float3 dada_goreColor(int i)
{
    i = ((i % 6) + 6) % 6;
    if (i == 0) return float3(0.82, 0.16, 0.13);
    if (i == 1) return float3(0.90, 0.45, 0.10);
    if (i == 2) return float3(0.93, 0.78, 0.14);
    if (i == 3) return float3(0.22, 0.55, 0.32);
    if (i == 4) return float3(0.16, 0.40, 0.64);
    return float3(0.93, 0.92, 0.88);
}

bool dada_special_albedo(int kind, float3 q, float p0, float p1, float p2, out float3 col)
{
    const float3 WHITE = float3(0.955, 0.945, 0.915);
    const float3 BLACK = float3(0.020, 0.020, 0.024);
    col = WHITE;

    if (kind == DK_CRESCENT)
    {
        float2 d = q.xy - float2(p0, p1);                  // disc plane = local XY
        col = (length(d) < max(p2, 0.1)) ? BLACK : WHITE;
        return true;
    }
    if (kind == DK_LENS)
    {
        float rr = length(q.xy);
        if (rr > 0.90) { col = WHITE; return true; }       // white ring
        float s = (q.x + q.y) * 0.70;
        int b = ((int)floor(s * 1.7 + 16.0)) % 4;
        if (b == 0) col = float3(0.88, 0.11, 0.09);
        else if (b == 1) col = float3(0.14, 0.38, 0.66);
        else if (b == 2) col = float3(0.20, 0.55, 0.30);
        else col = float3(0.95, 0.77, 0.10);
        return true;
    }
    if (kind == DK_BEACH)
    {
        float3 lp = normalize(q + 1e-5);
        float a = atan2(lp.z, lp.x);
        int seg = (int)floor((a / (2.0 * 3.14159265) + 0.5) * 6.0);
        col = lerp(dada_goreColor(seg), float3(0.93, 0.92, 0.88), smoothstep(0.72, 0.92, abs(lp.y)));
        return true;
    }
    if (kind == DK_HARLEQ)
    {
        float a = atan2(q.z, q.x);
        int chk = ((int)floor(a * 3.0 / 3.14159265) + (int)floor(q.y * 3.5)) & 1;
        col = chk ? float3(0.93, 0.78, 0.14) : float3(0.10, 0.10, 0.12);
        return true;
    }
    return false;
}

#endif // SDF_DADA_HLSLI
