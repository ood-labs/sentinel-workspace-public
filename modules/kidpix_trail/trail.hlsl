// kidpix_trail — the writhing green palm-tree stamp trail (lower-left). A meandering Catmull-Rom
// spline whose control points writhe on a seamless 6s loop; a small procedural palm-tree glyph is
// stamped upright at evenly spaced arc positions along it (a cloner along a path). Hard-edged flat
// green paint, premultiplied RGBA. Self-animating on _Time.
#include "../_shared/anim/anim.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

static const float TAU = 6.28318530718;
float h11(float p){ p = frac(p * 0.1031); p *= p + 33.33; p *= p + p; return frac(p); }

// control point of the loopy trail in canvas UV, animated to writhe
float2 ctrlPt(int i, int n)
{
    float a = ((float)i / (float)n) * TAU;
    // a wobbly loop centered lower-left, with a tail wander
    float rad = 0.15 + 0.06 * sin(a * 2.0 + h11((float)i) * 6.0);
    float2 c = float2(trail_cx, trail_cy) + float2(cos(a), sin(a) * 0.85) * rad * trail_scale;
    // per-point writhe, seamless loop
    float2 wr = float2(an_loop_noise(_Time, loop_seconds, 2.0, (float)i * 1.7 + 1.0) - 0.5,
                       an_loop_noise(_Time, loop_seconds, 2.0, (float)i * 2.3 + 4.0) - 0.5);
    return c + wr * writhe_amt;
}

float2 catmull(float2 p0, float2 p1, float2 p2, float2 p3, float t)
{
    float t2 = t * t, t3 = t2 * t;
    return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3);
}

float sdSeg(float2 p, float2 a, float2 b)
{
    float2 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * h);
}

// palm-tree glyph in local aspect-corrected space q (roughly [-1,1]); returns coverage
float palmGlyph(float2 q)
{
    float d = 1e9;
    // trunk: short slightly-curved segment rising to the crown
    d = min(d, sdSeg(q, float2(0.0, -0.9), float2(0.06, -0.1)));
    d = min(d, sdSeg(q, float2(0.06, -0.1), float2(0.0, 0.15)));
    float trunk = smoothstep(0.16, 0.10, d);
    // fronds fanning from the crown (0,0.15)
    float2 crown = float2(0.0, 0.15);
    float fr = 1e9;
    fr = min(fr, sdSeg(q, crown, float2(-0.75, 0.35)));
    fr = min(fr, sdSeg(q, float2(-0.75, 0.35), float2(-0.95, 0.15)));
    fr = min(fr, sdSeg(q, crown, float2(0.75, 0.35)));
    fr = min(fr, sdSeg(q, float2(0.75, 0.35), float2(0.95, 0.15)));
    fr = min(fr, sdSeg(q, crown, float2(-0.45, 0.7)));
    fr = min(fr, sdSeg(q, crown, float2(0.45, 0.7)));
    fr = min(fr, sdSeg(q, crown, float2(0.0, 0.95)));
    float fronds = smoothstep(0.15, 0.09, fr);
    return saturate(max(trunk, fronds));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 res = _Resolution.xy;
    float aspect = res.x / res.y;
    float2 uv = ((float2)px + 0.5) / res;
    float2 p = uv * float2(aspect, 1.0);          // isotropic canvas space

    int NC = 7;                                    // control points of the loop
    int M = clamp((int)palm_count, 1, 80);         // palms stamped along it
    float sz = palm_size;

    float cov = 0.0;
    [loop] for (int i = 0; i < 80; i++)
    {
        if (i >= M) break;
        float t = (float)i / (float)M;             // 0..1 along the closed loop
        float fseg = t * (float)NC;
        int seg = (int)fseg;
        float lt = frac(fseg);
        float2 p0 = ctrlPt((seg - 1 + NC) % NC, NC);
        float2 p1 = ctrlPt(seg % NC, NC);
        float2 p2 = ctrlPt((seg + 1) % NC, NC);
        float2 p3 = ctrlPt((seg + 2) % NC, NC);
        float2 pos = catmull(p0, p1, p2, p3, lt);  // canvas UV
        float2 posA = pos * float2(aspect, 1.0);   // isotropic

        float2 d = (p - posA) / max(sz, 1e-4);     // local space
        if (dot(d, d) > 1.6) continue;             // bbox reject
        cov = max(cov, palmGlyph(d));
    }

    float3 green = float3(0.16, 0.62, 0.18);
    OutputUAV[px] = float4(green * cov, cov) * intensity;
}
