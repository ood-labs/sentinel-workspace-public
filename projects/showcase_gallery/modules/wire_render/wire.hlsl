// wire_render — the sharp line-art plate: thin ellipse rings, loose curved strands, and a
// triangulated cage (ref #7 white circles + stray wires; ref #8 chrome tri-cage). Bright thin
// lines on transparent bg (premultiplied RGBA), seedable. 2D screen-space, stays razor-sharp
// (frames the distorted mass). Isotropic distances via aspect correction.
#include "../_shared/palette.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

float h11(float p) { p = frac(p * 0.1031); p *= p + 33.33; p *= p + p; return frac(p); }
float2 rot2(float2 v, float a) { float c = cos(a), s = sin(a); return float2(c * v.x - s * v.y, s * v.x + c * v.y); }
float sdSeg(float2 p, float2 a, float2 b)
{
    float2 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / dot(ba, ba));
    return length(pa - ba * h);
}
float sdBezier2(float2 p, float2 a, float2 b, float2 c)   // 8-segment quadratic bezier
{
    float d = 1e9; float2 prev = a;
    [unroll] for (int i = 1; i <= 8; i++)
    {
        float t = (float)i / 8.0;
        float2 pt = lerp(lerp(a, b, t), lerp(b, c, t), t);
        d = min(d, sdSeg(p, prev, pt)); prev = pt;
    }
    return d;
}
void over(inout float3 rgb, inout float cov, float3 c, float a)
{ rgb = c * a + rgb * (1.0 - a); cov = a + cov * (1.0 - a); }

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 res = _Resolution.xy;
    float aspect = res.x / res.y;
    // isotropic space: y in [0,1], x in [0,aspect]
    float2 p = (((float2)px + 0.5) / res) * float2(aspect, 1.0);
    float2 ctr = float2(aspect * 0.5, 0.5);
    float aa = 1.4 / res.y;

    float3 lite = float3(0.90, 0.91, 0.93);
    float3 rgb = 0.0; float cov = 0.0;
    float w = 0.0010 * wire_width;

    // ---- ellipse rings (thin white circles / ellipses) ----
    int nr = clamp((int)ring_count, 0, 6);
    [loop] for (int r = 0; r < nr; r++)
    {
        float2 c = ctr + (float2(h11(wire_seed * 2.1 + r * 3.3), h11(wire_seed * 4.7 + r * 1.9)) - 0.5) * float2(0.9 * aspect, 1.2);
        float rad = (0.10 + h11(wire_seed + r * 7.0) * 0.22) * wire_scale;
        float ecc = 0.65 + h11(wire_seed * 3.1 + r) * 0.5;
        float rot = h11(wire_seed * 5.5 + r * 2.7) * 6.2831;
        float2 q = rot2(p - c, -rot);
        float e = abs(length(q / float2(rad * ecc, rad)) - 1.0) * (rad * ecc);
        float strk = smoothstep(w + aa, w, e);
        over(rgb, cov, lite, strk * wire_bright);
    }

    // ---- loose curved strands (stray thin wires) ----
    int ns = clamp((int)strand_count, 0, 8);
    [loop] for (int s = 0; s < ns; s++)
    {
        float2 a = float2(h11(wire_seed * 1.3 + s * 9.7) * aspect, h11(wire_seed * 2.9 + s * 4.1));
        float2 cc = float2(h11(wire_seed * 6.1 + s * 2.3) * aspect, h11(wire_seed * 3.7 + s * 8.9));
        float2 b = (a + cc) * 0.5 + (float2(h11(wire_seed + s), h11(wire_seed * 7.3 + s)) - 0.5) * float2(0.7 * aspect, 0.9);
        float d = sdBezier2(p, a, b, cc);
        float sw = w * 0.7;
        float strk = smoothstep(sw + aa, sw, d);
        over(rgb, cov, lite, strk * wire_bright * 0.7);   // fainter than rings
    }

    // ---- triangulated cage (seeded vertices, cross-linked struts) ----
    int nc = clamp((int)cage_points, 0, 8);
    if (nc >= 3)
    {
        float2 V[8];
        [loop] for (int i = 0; i < nc; i++)
            V[i] = ctr + (float2(h11(wire_seed * 8.3 + i * 5.1), h11(wire_seed * 2.2 + i * 6.6)) - 0.5) * float2(0.85 * aspect, 1.15) * wire_scale;
        [loop] for (int j = 0; j < nc; j++)
        {
            float dd = min(sdSeg(p, V[j], V[(j + 1) % nc]), sdSeg(p, V[j], V[(j + 2) % nc]));
            float strk = smoothstep(w + aa, w, dd);
            over(rgb, cov, lite, strk * wire_bright * 0.85);
        }
    }

    OutputUAV[px] = float4(rgb * wire_opacity, cov * wire_opacity);  // premultiplied
}
