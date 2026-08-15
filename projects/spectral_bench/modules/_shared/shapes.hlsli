// shapes.hlsli — 2D signed distance fields, and ONE element-profile function.
//
// The renderer and the plan must agree about where a prism's edge is, down to the pixel: the
// beam is drawn from the traced path and the glass is drawn from its outline, and if those two
// disagree the light appears to enter slightly outside the body. So the profile of every element
// kind is written once, here, and both consumers call it.
#ifndef SPECTRAL_SHAPES_HLSLI
#define SPECTRAL_SHAPES_HLSLI

#include "../_shared/optics.hlsli"

float ltSdSeg(float2 p, float2 a, float2 b)
{
    float2 pa = p - a, ba = b - a;
    float t = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * t);
}

float ltSdBox(float2 p, float2 c, float2 h)
{
    float2 q = abs(p - c) - h;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}

// Negative inside.
float ltSdTri(float2 p, float2 a, float2 b, float2 c)
{
    float2 e0 = b - a, e1 = c - b, e2 = a - c;
    float2 v0 = p - a, v1 = p - b, v2 = p - c;
    float2 q0 = v0 - e0 * saturate(dot(v0, e0) / dot(e0, e0));
    float2 q1 = v1 - e1 * saturate(dot(v1, e1) / dot(e1, e1));
    float2 q2 = v2 - e2 * saturate(dot(v2, e2) / dot(e2, e2));
    float s = sign(e0.x * e2.y - e0.y * e2.x);
    float2 d = min(min(float2(dot(q0, q0), s * (v0.x * e0.y - v0.y * e0.x)),
                       float2(dot(q1, q1), s * (v1.x * e1.y - v1.y * e1.x))),
                       float2(dot(q2, q2), s * (v2.x * e2.y - v2.y * e2.x)));
    return -sqrt(d.x) * sign(d.y);
}

float ltSdArc(float2 p, float2 c, float r, float a0, float a1)
{
    float2 v = p - c;
    float a = atan2(v.y, v.x);
    float lo = min(a0, a1), hi = max(a0, a1);
    float aw = lo + (float)fmod(a - lo + LT_TAU * 4.0, LT_TAU);
    if (aw <= hi) return abs(length(v) - r);
    float2 e0 = c + float2(cos(a0), sin(a0)) * r;
    float2 e1 = c + float2(cos(a1), sin(a1)) * r;
    return min(length(p - e0), length(p - e1));
}

// A conservative radius for cheap rejection. Every consumer loops over 64 element slots per
// pixel, and without a bound that cheap the loop dominates everything else in the shader.
float ltElementBound(BenchRec e)
{
    int k = (int)e.kind;
    if (k == EK_PRISM) return max(e.p1.x, 1e-4) * 1.05;
    if (k == EK_LENS)  return max(max(e.p1.x, e.p1.y), 1e-4) * 1.6;
    return max(e.p1.x, e.p1.y) * 1.15 + 0.004;
}

// The signed distance to an element's TRUE profile, in bench units. Negative inside the body.
// Planar elements (mirror, splitter, screen, block) have a real thickness here so they read as
// objects rather than as lines — a mirror with no substrate looks like a scratch on the image.
float ltElementSDF(BenchRec e, float2 p)
{
    int k = (int)e.kind;
    float2 ax = ltDir(e.hdg);
    float2 pp = ltPerp(ax);

    if (k == EK_PRISM)
    {
        float2 pa, pb, pc;
        ltPrismVerts(e.p0, e.hdg, max(e.p1.x, 1e-4), e.r0, pa, pb, pc);
        return ltSdTri(p, pa, pb, pc);
    }
    if (k == EK_SLAB)
    {
        float2 lp = float2(dot(p - e.p0, pp), dot(p - e.p0, ax));
        return ltSdBox(lp, 0.0.xx, float2(max(e.p1.x, 1e-4), max(e.p1.y, 1e-4) * 0.5));
    }
    if (k == EK_LENS)
    {
        float R = max(e.r0, 1e-3);
        float th = clamp(e.p1.y, 1e-4, 1.98 * R);
        float off = R - th * 0.5;
        float ha = min(ltLensAperture(R, th), max(e.p1.x, 1e-4));
        float d = max(length(p - (e.p0 - ax * off)) - R, length(p - (e.p0 + ax * off)) - R);
        return max(d, abs(dot(p - e.p0, pp)) - ha);
    }

    // Planar family: a slab of substrate behind a face.
    float thick = (k == EK_SCREEN) ? 0.006 : ((k == EK_BLOCK) ? max(e.p1.y, 0.010) : 0.0045);
    float2 lp = float2(dot(p - e.p0, pp), dot(p - e.p0, ax));
    // The substrate sits BEHIND the reflective face (positive along the normal is toward the
    // beam), so the working surface stays exactly where the tracer put it.
    return ltSdBox(lp, float2(0.0, thick * 0.5), float2(max(e.p1.x, 1e-4), thick * 0.5));
}

// Distance to the WORKING FACE alone — the plane the tracer actually reflects or detects on.
float ltElementFace(BenchRec e, float2 p)
{
    float2 ax = ltDir(e.hdg);
    float2 pp = ltPerp(ax);
    float2 lp = float2(dot(p - e.p0, pp), dot(p - e.p0, ax));
    float along = abs(lp.x) - max(e.p1.x, 1e-4);
    return max(abs(lp.y), along);
}

#endif
