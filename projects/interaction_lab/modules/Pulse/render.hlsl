// Pulse / render - the machine: aluminium bars pinned at their nodes on dark felt, ivory balls,
// and a cool spark wherever the GPU registered a strike. That spark is all this node can show of
// the music: whether the strike was PLAYED is the Script's decision, and its answer lands
// downstream in Resonance, which lights the bars it played over this image.
#include "pulse.hlsli"

StructuredBuffer<PbRec> W : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

float sdRoundBox(float2 p, float2 b, float r) { float2 q = abs(p) - b + r; return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r; }
float sdSeg(float2 p, float2 a, float2 b) { float2 pa = p - a, ba = b - a; return length(pa - ba * saturate(dot(pa, ba) / dot(ba, ba))); }

float2 upNormal(float2 dir) { float2 n = float2(dir.y, -dir.x); return (n.y > 0.0) ? -n : n; }

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint w, h;
    OutputUAV.GetDimensions(w, h);
    if (id.x >= w || id.y >= h) return;
    float2 res = float2(w, h);
    float2 p = (float2(id.xy) + 0.5) * float2(PB_W, PB_H) / res;
    float pxw = PB_W / res.x;                                  // design px per device px
    float t = _Time;

    // felt: graphite, lit from above the frame
    float lit = exp(-length((p - float2(640.0, -160.0)) / float2(980.0, 760.0)));
    float3 col = float3(0.010, 0.0105, 0.012) + float3(0.034, 0.032, 0.030) * lit;
    col *= 1.0 - 0.25 * smoothstep(0.55, 1.15, length((p - float2(640.0, 360.0)) / float2(760.0, 520.0)));

    // shadows first: bars, then balls (soft, offset down and right, as the light sits up left)
    float shade = 1.0;
    [loop] for (uint i = 0u; i < PB_BARS; i++)
    {
        float2 c, dir;
        float hl;
        pbBar(i, c, dir, hl);
        float2 nu = upNormal(dir);
        float2 rel = p - c - float2(7.0, 12.0);
        float sd = sdRoundBox(float2(dot(rel, dir), dot(rel, nu)), float2(hl, PB_BAR_T), 3.0);
        shade *= 1.0 - 0.55 * (1.0 - smoothstep(-3.0, 14.0, sd));
    }
    [loop] for (uint k = 0u; k < PB_BALLS; k++)
    {
        PbRec b = W[W_BALL0 + k];
        if (b.c <= 0.0) continue;
        float sd = length(p - b.a - float2(5.0, 9.0)) - b.c;
        shade *= 1.0 - 0.5 * (1.0 - smoothstep(-4.0, 10.0, sd));
    }
    col *= shade;

    // bars
    [loop] for (uint i2 = 0u; i2 < PB_BARS; i2++)
    {
        float2 c, dir;
        float hl;
        pbBar(i2, c, dir, hl);
        float2 nu = upNormal(dir);
        float2 rel = p - c;
        float along = dot(rel, dir);
        float across = dot(rel, nu);
        float sd = sdRoundBox(float2(along, across), float2(hl, PB_BAR_T), 2.5);

        float cov = saturate(0.5 - sd / pxw);
        if (cov > 0.0)
        {
            float wv = clamp(across / PB_BAR_T, -1.0, 1.0);      // -1 underside .. +1 top face
            float metal = 0.20 + 0.42 * smoothstep(-1.0, 0.9, wv);
            metal += 0.012 * sin(along * 1.7 + (float)i2 * 3.1) + 0.008 * sin(along * 0.43);
            float spec = 0.55 * exp(-pow((wv - 0.52) / 0.16, 2.0));
            float endDark = smoothstep(hl - 9.0, hl, abs(along));
            float3 bc = float3(0.78, 0.80, 0.83) * metal * (1.0 - 0.35 * endDark) + spec * float3(0.95, 0.96, 1.0);
            // the pins at the two nodes
            float pin = min(length(float2(along - PB_NODE * hl, across)), length(float2(along + PB_NODE * hl, across))) - 2.3;
            float pinCov = saturate(0.5 - pin / pxw);
            bc = lerp(bc, float3(0.07, 0.07, 0.075), pinCov);
            bc += float3(0.35, 0.36, 0.38) * saturate(0.5 - abs(pin + 0.6) / pxw) * 0.6;
            col = lerp(col, bc, cov);
        }
    }

    // balls: ivory, lit from the upper left
    [loop] for (uint k2 = 0u; k2 < PB_BALLS; k2++)
    {
        PbRec b = W[W_BALL0 + k2];
        if (b.c <= 0.0) continue;
        float2 d = p - b.a;
        float sd = length(d) - b.c;
        if (sd > 2.0 * pxw) continue;
        float2 nxy = d / b.c;
        float3 n = float3(nxy, sqrt(saturate(1.0 - dot(nxy, nxy))));
        float3 L = normalize(float3(-0.45, -0.65, 0.62));
        float dif = saturate(dot(n, L));
        float spc = pow(saturate(dot(n, normalize(L + float3(0.0, 0.0, 1.0)))), 60.0);
        float3 bc = float3(0.86, 0.83, 0.77) * (0.16 + 0.84 * dif) + spc * 0.55;
        bc *= 1.0 - 0.35 * smoothstep(0.55, 1.0, length(nxy)) * saturate(nxy.y + 0.3);   // felt bounce darkens the base
        col = lerp(col, bc, saturate(0.5 - sd / pxw));
    }

    // strike sparks (cool) - the GPU's own, immediate signal
    [loop] for (uint i4 = 0u; i4 < PB_BARS; i4++)
    {
        PbRec sp = W[W_SPARK0 + i4];
        float a = t - sp.a.x;
        if (sp.a.x <= 0.0 || a < 0.0 || a > 0.28) continue;
        float2 c, dir;
        float hl;
        pbBar(i4, c, dir, hl);
        float2 nu = upNormal(dir);
        float2 q = c + dir * (sp.a.y * 2.0 - 1.0) * hl + nu * PB_BAR_T;
        float fade = pow(1.0 - a / 0.28, 2.0) * saturate(sp.b.x / 900.0 + 0.35);
        float glow = exp(-length(p - q) / 5.0);
        float rays = 1e9;
        [unroll] for (uint r = 0u; r < 5u; r++)
        {
            float th = 1.5708 + ((float)r - 2.0) * 0.5;          // a fan above the contact
            float2 rd = dir * cos(th) + nu * sin(th);
            float2 s0 = q + rd * (3.0 + 30.0 * a), s1 = q + rd * (9.0 + 52.0 * a);
            rays = min(rays, sdSeg(p, s0, s1));
        }
        col += float3(0.80, 0.90, 1.0) * fade * (glow * 0.9 + saturate(0.5 - (rays - 0.6) / pxw) * 0.8);
    }

    OutputUAV[id.xy] = float4(pow(saturate(col), 1.0 / 2.2), 1.0);
}
