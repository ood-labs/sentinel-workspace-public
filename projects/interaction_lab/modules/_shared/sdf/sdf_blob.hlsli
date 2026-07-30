// sdf_blob.hlsli — glossy-blob object vocabulary for the `strata` organic plate. Smooth,
// inflated, canonical-local forms meant to be op_smin-blended into an intertwined mass and
// shaded with 2-stop gradients (str_grad). Each object is centred at origin, ~unit sized;
// world size/orientation come from the instance scale/rotation. Flat forms face +Z.
//
// Requires (included FIRST): sdf_ops.hlsli, palette.hlsli. No nested includes.
// Uses sd_/op_ prefixes — do NOT enable features:[sdf].
#ifndef SDF_BLOB_HLSLI
#define SDF_BLOB_HLSLI

#define BK_SPHERE 0
#define BK_TUBE   1   // fat capsule along Y — the woven ribbons
#define BK_TORUS  2   // ring facing +Z
#define BK_SCOOP  3   // sphere with a carved front cavity (the "ear" scoops)
#define BK_RBOX   4   // beveled cube (checker host)
#define BK_LENS   5   // flattened pebble
#define BK_BEAN   6   // two-lobe blend
#define BK_HORN   7   // tapered curved horn
#define BK_COUNT  8

// material classes (record.mat)
#define BM_GLOSS  0   // 2-stop gradient gloss (colA->colB along grad axis)
#define BM_CHROME 1   // black/white swirl + env reflection
#define BM_CHECK  2   // 3-colour grid cube
#define BM_MATTE  3   // flat single palette colour, low spec
#define BM_SOLID  4   // single palette colour (colA), glossy

// generous local bound (all forms fit); renderers cull by this * instance max-axis.
static const float BLOB_BOUND_R = 1.55;

float blob_sdf(float3 p, int kind)
{
    if (kind == BK_SPHERE) return sd_sphere(p, 1.0);
    if (kind == BK_TUBE)   return sd_capsule(p, float3(0, -1.0, 0), float3(0, 1.0, 0), 0.5);
    if (kind == BK_TORUS)  return sd_torus(float3(p.x, p.z, p.y), 1.0, 0.34);
    if (kind == BK_SCOOP)
    {
        float outer = sd_sphere(p, 1.0);
        float cav   = sd_sphere(p - float3(0.0, 0.10, 0.74), 0.78);   // deep front-facing scoop
        return op_ssub(outer, -cav, 0.08);                            // smooth carve
    }
    if (kind == BK_RBOX)   return sd_rbox(p, float3(0.82, 0.82, 0.82), 0.14);
    if (kind == BK_LENS)   { float3 q = p; q.z *= 2.3; return (length(q) - 1.0) / 2.3; }
    if (kind == BK_BEAN)
        return op_smin(sd_sphere(p - float3(0, 0.42, 0), 0.72),
                       sd_sphere(p - float3(0, -0.42, 0), 0.72), 0.38);
    // HORN — tapered, gently bent along +X
    float3 q = p; q.x += q.y * q.y * 0.28;
    return sd_rcone(q, float3(0, -1.0, 0), float3(0.35, 1.0, 0), 0.5, 0.06);
}

// gradient coordinate 0..1 in canonical local space, selected by grad axis code.
float blob_gradT(float3 q, int axis)
{
    if (axis == 1) return q.x * 0.5 + 0.5;
    if (axis == 2) return saturate(length(q) * 0.72);
    if (axis == 3) return q.z * 0.5 + 0.5;
    return q.y * 0.5 + 0.5;                                            // 0 = along Y
}

// base albedo (before env reflection, which the renderer adds for chrome).
// `refl` returns >0 for materials that should mix a studio reflection.
float3 blob_albedo(int mat, int colA, int colB, int gaxis, float3 q, out float refl)
{
    refl = 0.0;
    if (mat == BM_CHROME)
    {
        float a = atan2(q.z, q.x);
        float s = sin(a * 7.0 + q.y * 9.0);                           // rolled-shell stripe
        float3 col = lerp(float3(0.02, 0.02, 0.03), float3(0.96, 0.96, 0.98),
                          smoothstep(-0.10, 0.10, s));                // crisp black/white bands
        refl = 0.6;
        return col;
    }
    if (mat == BM_CHECK)
    {
        int c = (int)floor(q.x * 3.0) + (int)floor(q.y * 3.0) + (int)floor(q.z * 3.0);
        c = ((c % 3) + 3) % 3;
        if (c == 0) return str_palette(STR_LIME);
        if (c == 1) return str_palette(STR_INDIGO);
        return str_palette(STR_ORANGE);
    }
    if (mat == BM_MATTE) return str_palette(colA);
    if (mat == BM_SOLID) { refl = 0.10; return str_palette(colA); }
    // BM_GLOSS
    refl = 0.10;
    return str_grad(colA, colB, blob_gradT(q, gaxis));
}

#endif // SDF_BLOB_HLSLI
