// sdf_objects.hlsli — kind-indexed vocabulary of raymarched 3D objects.
// Requires sdf_ops.hlsli included FIRST. Each object lives in local space:
// ground plane at y = 0, footprint roughly within |x|,|z| < 0.5, height <= ~1.7.
// obj_sdf() returns float2(distance, material). Vary silhouettes with `seed`.
//
// Kinds: 0 Crate, 1 Column, 2 Chair, 3 Table, 4 Tower, 5 Arch, 6 Tree, 7 Lamp
// All instances fit inside a bounding sphere at OBJ_BOUND_C, radius OBJ_BOUND_R
// (in local space) — scene renderers use it for per-pixel ray culling.
#ifndef SDF_OBJECTS_HLSLI
#define SDF_OBJECTS_HLSLI

#define MAT_GROUND   0.0
#define MAT_BODY     1.0
#define MAT_ACCENT   2.0
#define MAT_METAL    3.0
#define MAT_EMISSIVE 4.0
#define MAT_FOLIAGE  5.0

#define OBJ_KIND_COUNT 8
static const float3 OBJ_BOUND_C = float3(0.0, 0.75, 0.0);
static const float  OBJ_BOUND_R = 1.25;

float2 obj_crate(float3 p, float seed)
{
    float s = 0.26 + 0.10 * sd_hash11(seed * 7.1);
    float body = sd_rbox(p - float3(0.0, s, 0.0), float3(s, s, s), 0.02);
    // recessed panel band
    float band = sd_box(p - float3(0.0, s, 0.0), float3(s * 1.02, s * 0.28, s * 1.02));
    float2 res = float2(op_sub(body, band) , MAT_BODY);
    return op_matmin(res, float2(max(body, band), MAT_ACCENT));
}

float2 obj_column(float3 p, float seed)
{
    float h = 0.55 + 0.35 * sd_hash11(seed * 3.7);
    float shaft = sd_cone(p - float3(0.0, h, 0.0), h, 0.13, 0.10);
    float base = sd_rbox(p - float3(0.0, 0.05, 0.0), float3(0.19, 0.05, 0.19), 0.015);
    float cap  = sd_rbox(p - float3(0.0, 2.0 * h + 0.04, 0.0), float3(0.17, 0.04, 0.17), 0.015);
    float2 res = float2(op_fillet_union(shaft, base, 0.03), MAT_BODY);
    return op_matmin(res, float2(cap, MAT_ACCENT));
}

float2 obj_chair(float3 p, float seed)
{
    float lean = 0.12 + 0.10 * sd_hash11(seed * 5.3);
    float seatH = 0.40;
    float seat = sd_rbox(p - float3(0.0, seatH, 0.0), float3(0.26, 0.035, 0.24), 0.03);
    float3 bq = p - float3(0.0, seatH + 0.30, -0.235);
    bq = sd_rotX(bq, -lean);
    float back = sd_rbox(bq, float3(0.26, 0.30, 0.022), 0.03);
    // 4 legs via XZ mirror: one round cone evaluates all four
    float3 lq = sd_mirrorXZ(p, float2(0.21, 0.19));
    float legs = sd_rcone(lq, float3(0.0, seatH - 0.03, 0.0), float3(0.045, 0.012, 0.045), 0.024, 0.014);
    float2 res = float2(legs, MAT_METAL);
    res = op_matmin(res, float2(back, MAT_BODY));
    return op_matmin(res, float2(seat, MAT_ACCENT));
}

float2 obj_table(float3 p, float seed)
{
    float topR = 0.32 + 0.10 * sd_hash11(seed * 2.9);
    float h = 0.48;
    float top = sd_cyl(p - float3(0.0, h, 0.0), 0.022, topR);
    float col = sd_cone(p - float3(0.0, h * 0.5, 0.0), h * 0.5, 0.055, 0.035);
    float base = sd_cyl(p - float3(0.0, 0.02, 0.0), 0.02, topR * 0.55);
    float body = op_fillet_union(col, base, 0.03);
    float2 res = float2(body, MAT_METAL);
    return op_matmin(res, float2(top, MAT_ACCENT));
}

float2 obj_tower(float3 p, float seed)
{
    float h1 = 0.7 + 0.8 * sd_hash11(seed * 4.3);
    float h2 = h1 * (0.45 + 0.3 * sd_hash11(seed * 9.7));
    float w1 = 0.26 + 0.08 * sd_hash11(seed * 6.1);
    float w2 = w1 * 0.62;
    float lower = sd_rbox(p - float3(0.0, h1 * 0.5, 0.0), float3(w1, h1 * 0.5, w1), 0.01);
    float upper = sd_rbox(p - float3(0.0, h1 + h2 * 0.5, 0.0), float3(w2, h2 * 0.5, w2), 0.01);
    float roof  = sd_rbox(p - float3(0.0, h1 + h2 + 0.02, 0.0), float3(w2 * 0.55, 0.025, w2 * 0.55), 0.01);
    float2 res = float2(min(lower, upper), MAT_BODY);
    return op_matmin(res, float2(roof, MAT_EMISSIVE));
}

float2 obj_arch(float3 p, float seed)
{
    float w = 0.42 + 0.1 * sd_hash11(seed * 8.9);
    float slab = sd_rbox(p - float3(0.0, 0.5, 0.0), float3(w, 0.5, 0.11), 0.02);
    // tunnel: cylinder along Z + descending box opening
    float3 tq = p - float3(0.0, 0.42, 0.0);
    float tunnel = min(
        length(tq.xy) - w * 0.62,
        sd_box(p - float3(0.0, 0.2, 0.0), float3(w * 0.62, 0.23, 1.0)));
    return float2(op_sub(slab, tunnel), MAT_BODY);
}

float2 obj_tree(float3 p, float seed)
{
    float h = 0.34 + 0.12 * sd_hash11(seed * 3.1);
    float trunk = sd_rcone(p, float3(0.0, 0.0, 0.0), float3(0.0, h + 0.15, 0.0), 0.055, 0.03);
    float r0 = 0.24 + 0.10 * sd_hash11(seed * 5.9);
    float3 c0 = float3(0.0, h + 0.28, 0.0);
    float can = sd_sphere(p - c0, r0);
    float3 o1 = c0 + float3(0.14, 0.12, 0.06) * (0.5 + sd_hash11(seed * 1.7));
    float3 o2 = c0 + float3(-0.12, 0.16, -0.08) * (0.5 + sd_hash11(seed * 2.3));
    can = op_smin(can, sd_sphere(p - o1, r0 * 0.72), 0.08);
    can = op_smin(can, sd_sphere(p - o2, r0 * 0.66), 0.08);
    float2 res = float2(trunk, MAT_BODY);
    return op_matmin(res, float2(can, MAT_FOLIAGE));
}

float2 obj_lamp(float3 p, float seed)
{
    float h = 0.9 + 0.2 * sd_hash11(seed * 4.7);
    float pole = sd_rcone(p, float3(0.0, 0.0, 0.0), float3(0.0, h, 0.0), 0.028, 0.016);
    float base = sd_cyl(p - float3(0.0, 0.025, 0.0), 0.025, 0.07);
    float3 arm_end = float3(0.16, h + 0.02, 0.0);
    float arm = sd_capsule(p, float3(0.0, h, 0.0), arm_end, 0.014);
    float head = sd_sphere(p - (arm_end + float3(0.0, -0.045, 0.0)), 0.05);
    float2 res = float2(min(pole, min(base, arm)), MAT_METAL);
    return op_matmin(res, float2(head, MAT_EMISSIVE));
}

// kind-dispatched object SDF. p in local space, returns (distance, material).
float2 obj_sdf(float3 p, int kind, float seed)
{
    // cheap reject: skip detailed eval when far outside the bounding sphere
    float bound = length(p - OBJ_BOUND_C) - OBJ_BOUND_R;
    if (bound > 0.35) return float2(bound + 0.05, MAT_BODY);

    if (kind <= 0) return obj_crate(p, seed);
    if (kind == 1) return obj_column(p, seed);
    if (kind == 2) return obj_chair(p, seed);
    if (kind == 3) return obj_table(p, seed);
    if (kind == 4) return obj_tower(p, seed);
    if (kind == 5) return obj_arch(p, seed);
    if (kind == 6) return obj_tree(p, seed);
    return obj_lamp(p, seed);
}

#endif // SDF_OBJECTS_HLSLI
