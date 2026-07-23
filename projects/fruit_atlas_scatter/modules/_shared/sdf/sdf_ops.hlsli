// sdf_ops.hlsli — SDF primitives, booleans, and transforms for procedural geometry.
// Self-contained: no nested includes. Include ORDER in a module shader:
//   #include "../_shared/sdf/sdf_ops.hlsli"
//   #include "../_shared/sdf/sdf_objects.hlsli"   (optional: object vocabulary)
//   #include "../_shared/sdf/sdf_shading.hlsli"   (needs a sceneMap definition later in file)
// Naming uses sd_/op_ prefixes so these NEVER collide with the engine `sdf` feature
// library (sdSphere/opUnion/...). Do not enable `features: [sdf]` alongside this file.
#ifndef SDF_OPS_HLSLI
#define SDF_OPS_HLSLI

// ---- hashes -----------------------------------------------------------------
float sd_hash11(float p) { p = frac(p * 0.1031); p *= p + 33.33; p *= p + p; return frac(p); }
float sd_hash21(float2 p) { float3 p3 = frac(float3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return frac((p3.x + p3.y) * p3.z); }

// ---- transforms ---------------------------------------------------------------
float2 sd_rot2(float2 v, float a)
{
    float c = cos(a); float s = sin(a);
    return float2(c * v.x - s * v.y, s * v.x + c * v.y);
}
// rotate p around Y axis (yaw), for placing objects
float3 sd_rotY(float3 p, float a) { p.xz = sd_rot2(p.xz, a); return p; }
float3 sd_rotX(float3 p, float a) { p.zy = sd_rot2(p.zy, a); return p; }

// mirror across X and Z: evaluate one corner, get all four (legs, pillars)
float3 sd_mirrorXZ(float3 p, float2 offset)
{
    return float3(abs(p.x) - offset.x, p.y, abs(p.z) - offset.y);
}

// infinite repetition on XZ with cell size c (city blocks, columns)
float3 sd_repXZ(float3 p, float2 c)
{
    p.xz = p.xz - c * round(p.xz / c);
    return p;
}

// ---- primitives (exact) --------------------------------------------------------
float sd_sphere(float3 p, float r) { return length(p) - r; }

float sd_box(float3 p, float3 b)
{
    float3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

float sd_rbox(float3 p, float3 b, float r)
{
    float3 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - r;
}

// capped cylinder along Y: halfHeight h, radius r
float sd_cyl(float3 p, float h, float r)
{
    float2 d = abs(float2(length(p.xz), p.y)) - float2(r, h);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}

// capped cone along Y: halfHeight h, bottom radius r1 (at -h), top radius r2 (at +h)
float sd_cone(float3 p, float h, float r1, float r2)
{
    float2 q = float2(length(p.xz), p.y);
    float2 k1 = float2(r2, h);
    float2 k2 = float2(r2 - r1, 2.0 * h);
    float2 ca = float2(q.x - min(q.x, (q.y < 0.0) ? r1 : r2), abs(q.y) - h);
    float2 cb = q - k1 + k2 * clamp(dot(k1 - q, k2) / dot(k2, k2), 0.0, 1.0);
    float s = (cb.x < 0.0 && ca.y < 0.0) ? -1.0 : 1.0;
    return s * sqrt(min(dot(ca, ca), dot(cb, cb)));
}

// round cone between two arbitrary points (tapered legs, branches)
float sd_rcone(float3 p, float3 a, float3 b, float r1, float r2)
{
    float3 ba = b - a;
    float l2 = dot(ba, ba);
    float rr = r1 - r2;
    float a2 = l2 - rr * rr;
    float il2 = 1.0 / l2;
    float3 pa = p - a;
    float y = dot(pa, ba);
    float z = y - l2;
    float3 xv = pa * l2 - ba * y;
    float x2 = dot(xv, xv);
    float y2 = y * y * l2;
    float z2 = z * z * l2;
    float k = sign(rr) * rr * rr * x2;
    if (sign(z) * a2 * z2 > k) return sqrt(x2 + z2) * il2 - r2;
    if (sign(y) * a2 * y2 < k) return sqrt(x2 + y2) * il2 - r1;
    return (sqrt(x2 * a2 * il2) + y * rr) * il2 - r1;
}

// capsule between two points
float sd_capsule(float3 p, float3 a, float3 b, float r)
{
    float3 pa = p - a;
    float3 ba = b - a;
    float h = saturate(dot(pa, ba) / dot(ba, ba));
    return length(pa - ba * h) - r;
}

float sd_torus(float3 p, float R, float r)
{
    float2 q = float2(length(p.xz) - R, p.y);
    return length(q) - r;
}

// ---- booleans -------------------------------------------------------------------
float op_sub(float d, float cut) { return max(d, -cut); }

// smooth union (organic blend; radius k is approximate, not dimensionally exact)
float op_smin(float a, float b, float k)
{
    float h = saturate(0.5 + 0.5 * (b - a) / max(k, 1e-5));
    return lerp(b, a, h) - k * h * (1.0 - h);
}
// smooth subtraction
float op_ssub(float d, float cut, float k)
{
    float h = saturate(0.5 - 0.5 * (d + cut) / max(k, 1e-5));
    return lerp(d, -cut, h) + k * h * (1.0 - h);
}

// EXACT quarter-circle fillet union: radius r is a true dimension.
// Use this instead of op_smin when the spec calls out a fillet radius.
float op_fillet_union(float d1, float d2, float r)
{
    float2 u = max(float2(r - d1, r - d2), 0.0);
    return max(r, min(d1, d2)) - length(u);
}

// 45-degree chamfer union, chamfer size r
float op_chamfer_union(float d1, float d2, float r)
{
    return min(min(d1, d2), (d1 - r + d2) * 0.7071);
}

// material-carrying min: x = distance, y = material id
float2 op_matmin(float2 a, float2 b) { return (a.x < b.x) ? a : b; }

#endif // SDF_OPS_HLSLI
