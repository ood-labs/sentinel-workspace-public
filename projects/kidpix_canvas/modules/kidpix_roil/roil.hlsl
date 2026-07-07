// kidpix_roil — the multicolor "wacky brush" roil plate (upper-left). A thick chaotic mass of
// overlapping bright hard-edged lobes (red/green/blue/yellow/magenta/cyan) that undulate and
// shift in place. Built as many domain-warped metaballs whose centers orbit on a seamless 6s
// loop; each pixel takes the nearest strong lobe (hard edges, nearest-neighbour paint look), no
// bloom. Premultiplied-alpha on transparent bg. Self-animating on _Time.
#include "../_shared/anim/anim.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

static const float TAU = 6.28318530718;

float h11(float p){ p = frac(p * 0.1031); p *= p + 33.33; p *= p + p; return frac(p); }
float2 h22(float p){ return float2(h11(p * 1.7), h11(p * 3.1 + 5.0)); }

// 8 classic Kid Pix crayon colors
float3 palette(int i)
{
    i = i % 8;
    if (i == 0) return float3(0.92, 0.11, 0.14);   // red
    if (i == 1) return float3(0.13, 0.70, 0.20);   // green
    if (i == 2) return float3(0.12, 0.22, 0.90);   // blue
    if (i == 3) return float3(0.98, 0.85, 0.10);   // yellow
    if (i == 4) return float3(0.90, 0.12, 0.80);   // magenta
    if (i == 5) return float3(0.10, 0.80, 0.85);   // cyan
    if (i == 6) return float3(0.98, 0.55, 0.10);   // orange
    return float3(0.55, 0.20, 0.75);               // purple
}

// value-noise for domain warp
float vnoise(float2 p)
{
    float2 i = floor(p), f = frac(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = h11(dot(i, float2(1.0, 57.0)));
    float b = h11(dot(i + float2(1, 0), float2(1.0, 57.0)));
    float c = h11(dot(i + float2(0, 1), float2(1.0, 57.0)));
    float d = h11(dot(i + float2(1, 1), float2(1.0, 57.0)));
    return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 px = DTid.xy;
    if (px.x >= (uint)_Resolution.x || px.y >= (uint)_Resolution.y) return;
    float2 res = _Resolution.xy;
    float aspect = res.x / res.y;
    float2 uv = ((float2)px + 0.5) / res;

    // anchor the mass as a wide horizontal band near the top of the canvas
    float2 anchor = float2(mass_cx, mass_cy);
    float2 p = (uv - anchor) * float2(aspect, 1.0) / max(mass_scale, 0.01);

    // domain warp the sample point so streaks writhe (more horizontal drift)
    float t = _Time;
    float2 w = float2(vnoise(p * float2(1.6, 3.0) + float2(0.0, t * 0.35)),
                      vnoise(p * float2(1.4, 2.8) + float2(5.0, -t * 0.3)));
    p += (w - 0.5) * float2(warp_amt * 1.6, warp_amt * 0.6);

    int N = clamp((int)lobe_count, 1, 48);
    float bestD = 1e9; int bestI = 0;
    // metaball-ish: nearest orbiting lobe wins. Lobes are ELONGATED horizontally (paint streaks)
    // and spread wide + thin so the mass reads as a horizontal smear band.
    [loop] for (int i = 0; i < 48; i++)
    {
        if (i >= N) break;
        float fi = (float)i;
        // even horizontal march across the band + small vertical scatter
        float uix = (fi + 0.5) / (float)N;
        float2 base = float2((uix * 2.0 - 1.0) * 2.6, (h11(fi * 3.7) - 0.5) * 0.85);
        float ph = h11(fi * 1.13) * TAU;
        float rr = 0.14 + h11(fi * 2.9) * 0.22;
        float2 orb = float2(cos(TAU * _Time / loop_seconds + ph) * 0.14,
                            sin(TAU * _Time / loop_seconds + ph * 1.7) * 0.06);
        float2 c = base + orb;
        float rad = rr * (0.75 + 0.5 * an_loop_noise(_Time, loop_seconds, 1.0, fi * 2.0 + 1.0));
        // elongate: compress x distance so lobes are ~2x wider than tall
        float2 dv = p - c; dv.x *= 0.5;
        float d = length(dv) - rad;
        if (d < bestD) { bestD = d; bestI = i; }
    }

    // hard edge; color spreads evenly along the band (index by lobe order, not hash)
    float aa = 1.2 / res.y / max(mass_scale, 0.01);
    float cov = smoothstep(aa, -aa, bestD);
    int colIdx = (bestI * 3 + (int)floor(h11((float)bestI * 4.4) * 2.0)) % 6;   // spread across 6 crayons
    float3 col = palette(colIdx);

    OutputUAV[px] = float4(col * cov, cov) * intensity;
}
