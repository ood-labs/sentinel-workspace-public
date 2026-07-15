// marks — the sharp graphic overlay (top plate). Red rule lines, solid red squares, rivet
// dots, a thin registration frame + corner ticks: the hard 2D marks that FRAME the mass in
// ref #7. Premultiplied-alpha RGBA (transparent except the marks), seedable placement so the
// framing reshuffles with the composition. 2D screen-space, no distortion.
#include "../_shared/palette.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

float h11(float p) { p = frac(p * 0.1031); p *= p + 33.33; p *= p + p; return frac(p); }
float2 h22(float p) { return float2(h11(p), h11(p + 17.3)); }

// premultiplied "over": src (straight color `c`, coverage `a`) onto accumulator (premult rgb, cov)
void over(inout float3 rgb, inout float cov, float3 c, float a)
{
    rgb = c * a + rgb * (1.0 - a);
    cov = a + cov * (1.0 - a);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 res = _Resolution.xy;
    float2 uv = ((float2)px + 0.5) / res;
    float aspect = res.x / res.y;
    float aa = 1.4 / res.y;

    float3 red = str_palette(STR_RED);
    float3 lite = float3(0.86, 0.87, 0.88);
    float3 dark = float3(0.20, 0.21, 0.23);

    float3 rgb = 0.0; float cov = 0.0;

    // ---- registration frame (thin inset rectangle) + corner ticks ----
    if (frame_amt > 0.5)
    {
        float2 m = float2(0.055, 0.055 / aspect);       // inset margins (square in pixels)
        float2 d = min(uv - m, (1.0 - m) - uv);         // dist to frame rect edges
        float edge = min(d.x, d.y);
        float fw = 0.0016;
        float strk = smoothstep(fw + aa, fw, abs(edge)) * step(-fw - aa, edge);
        over(rgb, cov, lite, strk * 0.7);
        // corner L-ticks
        float2 c0 = m, c1 = float2(1.0 - m.x, 1.0 - m.y);
        float tick = 0.030;
        [unroll] for (int cxi = 0; cxi < 2; cxi++)
        [unroll] for (int cyi = 0; cyi < 2; cyi++)
        {
            float2 cc = float2(cxi == 0 ? c0.x : c1.x, cyi == 0 ? c0.y : c1.y);
            float2 q = uv - cc;
            float hx = smoothstep(fw + aa, fw, abs(q.y)) * step(0.0, tick - abs(q.x)) * step(-tick, sign(0.5 - cxi) * q.x);
            float vy = smoothstep(fw + aa, fw, abs(q.x)) * step(0.0, tick - abs(q.y)) * step(-tick, sign(0.5 - cyi) * q.y);
            over(rgb, cov, lite, max(hx, vy) * 0.9);
        }
    }

    // ---- red rule lines (full-width horizontals) ----
    int nr = clamp((int)rule_count, 0, 3);
    [loop] for (int r = 0; r < nr; r++)
    {
        float ry = 0.14 + h11(mark_seed * 2.3 + r * 9.1) * 0.72;
        float rw = 0.0011 * mark_scale;
        float strk = smoothstep(rw + aa, rw, abs(uv.y - ry));
        over(rgb, cov, red, strk);
    }

    // ---- solid red squares ----
    int ns = clamp((int)square_count, 0, 5);
    [loop] for (int s = 0; s < ns; s++)
    {
        float2 c = float2(0.10 + h11(mark_seed * 3.7 + s * 4.4) * 0.80,
                          0.10 + h11(mark_seed * 5.1 + s * 6.7) * 0.80);
        float hs = (0.012 + h11(mark_seed + s) * 0.006) * mark_scale;
        float2 q = abs(uv - c) - float2(hs, hs * aspect);
        float box = smoothstep(aa, 0.0, max(q.x, q.y));
        over(rgb, cov, red, box);
    }

    // ---- rivet / screw dots (light ring + centre) ----
    int nv = clamp((int)rivet_count, 0, 12);
    [loop] for (int v = 0; v < nv; v++)
    {
        float2 c = float2(0.08 + h11(mark_seed * 7.9 + v * 2.1) * 0.84,
                          0.08 + h11(mark_seed * 1.7 + v * 3.9) * 0.84);
        float2 q = (uv - c) * float2(1.0, 1.0 / aspect);   // isotropic
        float rr = (0.006 + h11(mark_seed + v * 5.0) * 0.003) * mark_scale;
        float dist = length(q);
        float ring = smoothstep(0.0009 + aa, 0.0009, abs(dist - rr));
        float dot = smoothstep(rr * 0.42 + aa, rr * 0.42, dist);
        over(rgb, cov, dark, ring * 0.8);
        over(rgb, cov, lite, dot * 0.9);
    }

    OutputUAV[px] = float4(rgb * (mark_opacity), cov * mark_opacity);  // premultiplied
}
