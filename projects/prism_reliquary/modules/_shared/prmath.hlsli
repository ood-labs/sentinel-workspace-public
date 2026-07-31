// prism_reliquary / _shared/prmath.hlsli
//
// Low-level math with no creative identity of its own: hashing, value noise, quaternions,
// SDF primitives and operators, and the optics helpers the whole show is built on
// (thin-film interference, Fresnel, ACES).
//
// Deliberately NOT the `sdf`/`noise` feature libraries. This project owns every material
// equation it uses, and redefining an injected built-in is an instant compile failure, so
// everything here carries a `pr_` prefix and the modules declare only `features: [camera]`.

#ifndef PR_MATH_HLSLI
#define PR_MATH_HLSLI

#define PR_PI  3.14159265
#define PR_TAU 6.28318531

// ---------------------------------------------------------------------------
// Hashing and noise
// ---------------------------------------------------------------------------

float pr_hash11(float p) { p = frac(p * 0.1031); p *= p + 33.33; p *= p + p; return frac(p); }

float pr_hash21(float2 p)
{
    float3 q = frac(float3(p.xyx) * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return frac((q.x + q.y) * q.z);
}

float pr_hash31(float3 p)
{
    p = frac(p * float3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.zyx + 31.32);
    return frac((p.x + p.y) * p.z);
}

float3 pr_hash33(float3 p)
{
    p = float3(dot(p, float3(127.1, 311.7, 74.70)),
               dot(p, float3(269.5, 183.3, 246.1)),
               dot(p, float3(113.5, 271.9, 124.6)));
    return frac(sin(p) * 43758.5453);
}

float pr_vnoise(float3 p)
{
    float3 i = floor(p);
    float3 f = frac(p);
    f = f * f * (3.0 - 2.0 * f);
    float2 e = float2(0.0, 1.0);
    return lerp(lerp(lerp(pr_hash31(i + e.xxx), pr_hash31(i + e.yxx), f.x),
                     lerp(pr_hash31(i + e.xyx), pr_hash31(i + e.yyx), f.x), f.y),
                lerp(lerp(pr_hash31(i + e.xxy), pr_hash31(i + e.yxy), f.x),
                     lerp(pr_hash31(i + e.xyy), pr_hash31(i + e.yyy), f.x), f.y), f.z);
}

float pr_fbm(float3 p, int oct)
{
    float s = 0.0, a = 0.5;
    [loop] for (int i = 0; i < oct; i++) { s += a * pr_vnoise(p); p *= 2.03; a *= 0.5; }
    return s;
}

// Ridged variant — the fur uses this so strands read as crests, not lumps.
float pr_ridged(float3 p, int oct)
{
    float s = 0.0, a = 0.5;
    [loop] for (int i = 0; i < oct; i++)
    {
        float n = 1.0 - abs(pr_vnoise(p) * 2.0 - 1.0);
        s += a * n * n;
        p *= 2.07;
        a *= 0.5;
    }
    return s;
}

// ---------------------------------------------------------------------------
// Rotation
// ---------------------------------------------------------------------------

float2 pr_rot2(float2 v, float a)
{
    float s = sin(a), c = cos(a);
    return float2(c * v.x - s * v.y, s * v.x + c * v.y);
}

float4 pr_qaxis(float3 ax, float ang)
{
    float h = ang * 0.5;
    return float4(normalize(ax) * sin(h), cos(h));
}

float4 pr_qmul(float4 a, float4 b)
{
    return float4(a.w * b.xyz + b.w * a.xyz + cross(a.xyz, b.xyz),
                  a.w * b.w - dot(a.xyz, b.xyz));
}

float3 pr_qrot(float4 q, float3 v)
{
    return v + 2.0 * cross(q.xyz, cross(q.xyz, v) + q.w * v);
}

// World -> local. Every SDF in this project uses this and never the forward rotation,
// because marching transforms the sample point into the record's frame.
float3 pr_qinv(float4 q, float3 v)
{
    return pr_qrot(float4(-q.xyz, q.w), v);
}

// e = (pitch about X, yaw about Y, roll about Z), applied Y * X * Z.
float4 pr_qeuler(float3 e)
{
    float4 qy = pr_qaxis(float3(0, 1, 0), e.y);
    float4 qx = pr_qaxis(float3(1, 0, 0), e.x);
    float4 qz = pr_qaxis(float3(0, 0, 1), e.z);
    return pr_qmul(qy, pr_qmul(qx, qz));
}

// ---------------------------------------------------------------------------
// SDF primitives
// ---------------------------------------------------------------------------

float pr_sphere(float3 p, float r) { return length(p) - r; }

float pr_box(float3 p, float3 b)
{
    float3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

float pr_rbox(float3 p, float3 b, float r) { return pr_box(p, b - r) - r; }

// Torus in the XZ plane, hole along +Y.
float pr_torus(float3 p, float R, float r)
{
    float2 q = float2(length(p.xz) - R, p.y);
    return length(q) - r;
}

float pr_cyl(float3 p, float h, float r)
{
    float2 d = abs(float2(length(p.xz), p.y)) - float2(r, h);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}

float pr_capsule(float3 p, float3 a, float3 b, float r)
{
    float3 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * h) - r;
}

// Non-exact but well-behaved ellipsoid bound.
float pr_ellipsoid(float3 p, float3 r)
{
    float k0 = length(p / r);
    float k1 = length(p / (r * r));
    return k0 * (k0 - 1.0) / max(k1, 1e-6);
}

// Octahedron — the gem chips are cut from this.
float pr_octa(float3 p, float s)
{
    p = abs(p);
    return (p.x + p.y + p.z - s) * 0.57735027;
}

// ---------------------------------------------------------------------------
// Operators
// ---------------------------------------------------------------------------

float pr_smin(float a, float b, float k)
{
    if (k <= 1e-5) return min(a, b);
    float h = saturate(0.5 + 0.5 * (b - a) / k);
    return lerp(b, a, h) - k * h * (1.0 - h);
}

float pr_smax(float a, float b, float k)
{
    if (k <= 1e-5) return max(a, b);
    float h = saturate(0.5 - 0.5 * (b - a) / k);
    return lerp(b, a, h) + k * h * (1.0 - h);
}

float pr_ssub(float d, float cut, float k) { return pr_smax(d, -cut, k); }

// Carries (distance, material id) through a union so the shader can identify the hit.
float2 pr_umat(float2 a, float2 b) { return (a.x < b.x) ? a : b; }

// ---------------------------------------------------------------------------
// Optics
// ---------------------------------------------------------------------------

// Cosine palette rainbow. t wraps at 1.
float3 pr_spectral(float t)
{
    return 0.5 + 0.5 * cos(PR_TAU * (t + float3(0.00, 0.33, 0.67)));
}

// Real thin-film interference: optical path difference through a film of thickness
// d_nm at incidence cosI, sampled at three representative wavelengths. The +PI is the
// hard reflection phase shift at the outer boundary. This is what makes the drape read
// as a soap membrane rather than a rainbow gradient painted on glass.
float3 pr_thinfilm(float d_nm, float cosI, float ior)
{
    float sinT2 = (1.0 - cosI * cosI) / max(ior * ior, 1e-4);
    float cosT  = sqrt(saturate(1.0 - sinT2));
    float opd   = 2.0 * ior * d_nm * cosT;
    float3 lam  = float3(612.0, 549.0, 464.0);
    float3 ph   = PR_TAU * opd / lam + PR_PI;
    return 0.5 + 0.5 * cos(ph);
}

float pr_fresnel(float cosI, float f0)
{
    float m = saturate(1.0 - cosI);
    float m2 = m * m;
    return f0 + (1.0 - f0) * m2 * m2 * m;
}

// Wavelength-split Fresnel — the chromatic edge on the glyph and the gems.
float3 pr_fresnel3(float cosI, float f0, float spread)
{
    return float3(pr_fresnel(cosI, f0 * (1.0 - spread)),
                  pr_fresnel(cosI, f0),
                  pr_fresnel(cosI, f0 * (1.0 + spread)));
}

float3 pr_aces(float3 x)
{
    const float a = 2.51, b = 0.03, c = 2.43, d = 0.59, e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

#endif // PR_MATH_HLSLI
