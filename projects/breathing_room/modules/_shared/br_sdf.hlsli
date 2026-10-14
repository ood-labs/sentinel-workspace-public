// br_sdf.hlsli -- signed distance primitives for breathing_room (exact where it matters).
#ifndef BR_SDF_HLSLI
#define BR_SDF_HLSLI

float sdBoxE(float3 p, float3 b)
{
    float3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}
float sdRBox(float3 p, float3 b, float r)
{
    float3 q = abs(p) - (b - r);
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - r;
}
// axis-aligned box given by min/max corners
float sdAabb(float3 p, float3 lo, float3 hi)
{
    return sdBoxE(p - (lo + hi) * 0.5, (hi - lo) * 0.5);
}
float sdRAabb(float3 p, float3 lo, float3 hi, float r)
{
    return sdRBox(p - (lo + hi) * 0.5, (hi - lo) * 0.5, r);
}
float sdBox2(float2 p, float2 b)
{
    float2 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}
// capped cylinder along y: half height h, radius r
float sdCylY(float3 p, float h, float r)
{
    float2 d = abs(float2(length(p.xz), p.y)) - float2(r, h);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}
// rounded capped cylinder along y
float sdRCylY(float3 p, float h, float r, float rr)
{
    float2 d = float2(length(p.xz) - r + rr, abs(p.y) - h + rr);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0)) - rr;
}
float sdCapsuleSeg(float3 p, float3 a, float3 b, float r)
{
    float3 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-8));
    return length(pa - ba * h) - r;
}
// round cone between two spheres
float sdRoundCone(float3 p, float3 a, float3 b, float r1, float r2)
{
    float3 ba = b - a;
    float l2 = dot(ba, ba);
    float rr = r1 - r2;
    float a2 = l2 - rr * rr;
    float il2 = 1.0 / max(l2, 1e-8);
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
float sdEllipsoid(float3 p, float3 r)
{
    float k0 = length(p / r);
    float k1 = length(p / (r * r));
    return k0 * (k0 - 1.0) / max(k1, 1e-8);
}
float sdTorusY(float3 p, float R, float r)
{
    float2 q = float2(length(p.xz) - R, p.y);
    return length(q) - r;
}

float sminK(float a, float b, float k)
{
    float h = saturate(0.5 + 0.5 * (b - a) / max(k, 1e-6));
    return lerp(b, a, h) - k * h * (1.0 - h);
}
float smaxK(float a, float b, float k) { return -sminK(-a, -b, k); }

float2 rot2(float2 p, float a) { float c = cos(a), s = sin(a); return float2(c * p.x - s * p.y, s * p.x + c * p.y); }

// Closest-hit carrier. `mat` is a material slot, `part` a per-part id (seeds pattern variation and
// lets the shader tell e.g. a sash from a casing), `obj` the render-object index (-1 = shell).
struct SHit
{
    float d;
    int mat;
    int part;
    int obj;
};
SHit shit(float d, int mat, int part, int obj) { SHit h; h.d = d; h.mat = mat; h.part = part; h.obj = obj; return h; }
void hmin(inout SHit h, float d, int mat, int part, int obj)
{
    if (d < h.d) { h.d = d; h.mat = mat; h.part = part; h.obj = obj; }
}

#endif
