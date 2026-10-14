// Relief - a hypsometric plate: an island's terrain tinted by elevation through the Ramp Desk's
// palette, shaded by a low sun, with contours, a coastline and a legend that reads the palette back.
//
// ONE pass, by design. The node runs `execution: on_dirty` and the pass is `time_dependent: false`,
// so it renders when the Palette's generation moves (an edit on the desk), when a parameter changes,
// or on a reload - and not otherwise. A single pass cannot be left half-updated by pass order
// (on 0.6.3 passes run in reverse manifest order), so the terrain is evaluated here per pixel
// instead of being cached by a pass of its own: three height samples a pixel, on demand.
#define IL_TYPE_TEX _Tex1
#include "_labels.generated.hlsli"           // before il_text: it turns on the label functions
#include "../_shared/ui/il_text.hlsli"

StructuredBuffer<float4> P : register(t0);        // the Ramp Desk's Palette (data input)
#define PAL_BUFFER P
#include "../_shared/palette.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

#define MAP     float4(28.0, 28.0, 1092.0, 692.0)
#define CENTRE  float2(560.0, 360.0)
#define UNIT    230.0                              // px per terrain unit
#define MPP     90.0                               // metres per px: the plate is 96 km across
#define ZX      1.0                                // relief exaggeration for the shading

static uint g_seed;

// ---------------------------------------------------------------- terrain
float2 grad(int2 i)
{
    uint h = ilHashU((uint)i.x * 1597334677u ^ (uint)i.y * 3812015801u ^ g_seed * 2654435761u);
    float a = (float)(h & 0xFFFFu) * (6.2831853 / 65536.0);
    return float2(cos(a), sin(a));
}

// gradient noise with a quintic fade: smooth derivatives, so the hill shading shows no grid
float gnoise(float2 p)
{
    int2 i = (int2)floor(p);
    float2 f = p - floor(p);
    float2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    float a = dot(grad(i), f);
    float b = dot(grad(i + int2(1, 0)), f - float2(1.0, 0.0));
    float c = dot(grad(i + int2(0, 1)), f - float2(0.0, 1.0));
    float d = dot(grad(i + int2(1, 1)), f - float2(1.0, 1.0));
    return 1.6 * lerp(lerp(a, b, u.x), lerp(c, d, u.x), u.y);
}

static const float2x2 ROT = float2x2(0.80, -0.60, 0.60, 0.80);

float fbm(float2 p, uint oct)
{
    float a = 0.0, amp = 0.5;
    [loop] for (uint i = 0u; i < oct; i++)
    {
        a += amp * gnoise(p);
        p = mul(ROT, p) * 2.03 + 17.1;
        amp *= 0.5;
    }
    return a;
}

// ridges sharpen where the octave below was already high: ranges, not bumps
float ridged(float2 p, uint oct)
{
    float a = 0.0, amp = 0.5, w = 1.0;
    [loop] for (uint i = 0u; i < oct; i++)
    {
        float n = 1.0 - abs(gnoise(p));
        n *= n;
        a += amp * n * w;
        w = saturate(n * 1.6);
        p = mul(ROT, p) * 2.1 - 9.3;
        amp *= 0.5;
    }
    return a;
}

// metres above the present sea. Land gathers toward the middle of the plate (an island, whatever
// the seed) and the sea floor deepens toward the frame; the coast and the ranges are the noise's.
float terrain(float2 q)
{
    float2 w = float2(fbm(q * 0.5 + 3.1, 3u), fbm(q * 0.5 - 5.7, 3u));
    float2 qw = q + 0.5 * w;
    float r = length(q * float2(0.62, 0.95));
    float base = fbm(qw * 0.8, 5u) + 0.36 * (1.0 - smoothstep(0.1, 1.9, r)) - 0.21;
    float land = smoothstep(0.0, 0.30, base);
    float mount = ridged(qw * 1.35 + 4.0, 4u);
    float h = base * 2400.0 + land * mount * 2500.0 - 100.0;
    // a shelf: shallow water lingers off the coast before the slope drops away; then the deep
    if (h < 0.0) h = -pow(min(abs(h) / 3600.0, 4.0), 1.3) * 3600.0;
    h -= 2700.0 * smoothstep(1.1, 2.7, r) * (1.0 - land);
    return h;
}

// ---------------------------------------------------------------- the plate
float3 tintAt(float t, bool hasPal)
{
    return hasPal ? palSample(t) : lerp(float3(0.16, 0.16, 0.17), float3(0.92, 0.92, 0.91), saturate(t));
}

float nice(float range)
{
    float raw = range / 4.0;
    float m = pow(10.0, floor(log10(raw)));
    float r = raw / m;
    return m * (r < 1.5 ? 1.0 : (r < 3.5 ? 2.5 : (r < 7.5 ? 5.0 : 10.0)));
}

[numthreads(16, 16, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    if (id.x >= (uint)_Resolution.x || id.y >= (uint)_Resolution.y) return;
    float2 p = float2(id.xy) + 0.5;
    g_seed = (uint)max(seed, 1);
    float4 head = P[PAL_HEAD];
    bool hasPal = head.y == (float)PAL_ENTRIES && head.x >= 2.0;
    float span = max(range_m, 100.0);
    static const float INTERVALS[4] = { 0.0, 100.0, 250.0, 500.0 };
    float interval = INTERVALS[clamp((int)contours, 0, 3)];
    float3 ink = float3(0.17, 0.17, 0.18);
    float3 col = float3(0.925, 0.918, 0.902);          // paper

    float4 mp = MAP;
    if (ilIn(p, mp))
    {
        float2 q = (p - CENTRE) / UNIT;
        float h0 = terrain(q), hx = terrain(q + float2(1.0 / UNIT, 0.0)), hy = terrain(q + float2(0.0, 1.0 / UNIT));
        float e = h0 - sea_level;
        float2 g = float2(hx - h0, hy - h0);              // metres per px
        float gm = length(g) + 1e-3;
        float3 tint = tintAt(0.5 + e / (2.0 * span), hasPal);

        // hill shading against flat ground, a sun at 42 degrees; the sea floor takes a third of it
        float az = radians(light), alt = radians(42.0);
        float3 sun = float3(sin(az) * cos(alt), -cos(az) * cos(alt), sin(alt));
        float3 n = normalize(float3(-g * (ZX / MPP), 1.0));
        float k = shading * (e < 0.0 ? 0.33 : 1.0);
        float lit = saturate(dot(n, sun)) / sin(alt);    // 1 on flat ground
        tint *= clamp(lerp(1.0, lit, 0.75 * k), 0.42, 1.32);

        // contours (index every fifth), lighter under water
        if (interval > 0.0)
        {
            float v = e / interval;
            float d = abs(frac(v + 0.5) - 0.5) * interval / gm;
            float r = round(v);
            bool index = abs(r - 5.0 * floor(r / 5.0 + 0.5)) < 0.5;
            float cov = saturate(0.5 * (index ? 1.2 : 0.6) + 0.5 - d) * (index ? 0.5 : 0.32) * (e < 0.0 ? 0.65 : 1.0);
            tint = lerp(tint, tint * 0.5, cov);
        }
        // the coastline
        float dc = abs(e) / gm;
        tint = lerp(tint, ink, saturate(0.5 * 1.3 + 0.5 - dc) * 0.75);
        col = tint;
    }
    // a double neatline
    float dIn = abs(ilSdBox(p, mp, 0.0)), dOut = abs(ilSdBox(p, ilInset(mp, -5.0), 0.0));
    col = lerp(col, ink, saturate(1.25 - dIn));
    col = lerp(col, ink, saturate(0.9 - dOut) * 0.8);

    // the legend: the palette read back as elevation
    if (p.x > 1104.0)
    {
        float4 bar = float4(1124.0, 84.0, 1144.0, 584.0);
        float c = ilLabel(p, 1118.0, 52.0, 12.0, LB_ELEV, IL_LEFT);
        c = max(c, ilLabel(p, 1118.0 + ilLabelW(LB_ELEV, 12.0) + 6.0, 52.0, 11.0, LB_M, IL_LEFT));
        if (ilIn(p, bar))
        {
            float tb = (bar.w - p.y) / (bar.w - bar.y);
            col = tintAt(tb, hasPal);
        }
        float db = abs(ilSdBox(p, bar, 0.0));
        col = lerp(col, ink, saturate(1.1 - db) * 0.9);
        float step = nice(span);
        int ticks = (int)floor(span / step + 1e-3);
        [loop] for (int i = -ticks; i <= ticks; i++)
        {
            float ev = (float)i * step;
            float y = lerp(bar.w, bar.y, 0.5 + ev / (2.0 * span));
            float len = (i == 0) ? 9.0 : 5.0;
            if (p.y > y - 0.75 && p.y < y + 0.75 && p.x > bar.z && p.x < bar.z + len) c = max(c, 1.0);
            c = max(c, ilNum(p, bar.z + 12.0, y, 11.0, ev, 0, IL_LEFT));
        }
        float y0 = 616.0;
        if (interval > 0.0)
        {
            c = max(c, ilLabel(p, 1118.0, y0, 11.0, LB_CONT, IL_LEFT));
            float x1 = 1118.0 + ilLabelW(LB_CONT, 11.0) + 5.0;
            c = max(c, ilNum(p, x1, y0, 11.0, interval, 0, IL_LEFT));
            c = max(c, ilLabel(p, x1 + ilNumW(3u, 11.0) + 4.0, y0, 11.0, LB_M, IL_LEFT));
        }
        float y1 = y0 + 20.0;
        c = max(c, ilLabel(p, 1118.0, y1, 11.0, LB_SEA, IL_LEFT));
        float x2 = 1118.0 + ilLabelW(LB_SEA, 11.0) + 5.0;
        c = max(c, ilNumSigned(p, x2, y1, 11.0, sea_level, 0, IL_LEFT));
        c = max(c, ilLabel(p, x2 + ilNumW(ilFormat(sea_level, 0, 1, true).n, 11.0) + 4.0, y1, 11.0, LB_M, IL_LEFT));
        float y2 = y1 + 26.0;
        if (hasPal)
        {
            c = max(c, ilLabel(p, 1118.0, y2, 10.5, LB_FROM, IL_LEFT) * 0.75);
            c = max(c, ilLabel(p, 1118.0, y2 + 15.0, 10.5, LB_BLEND_0 + min((uint)head.z, 2u), IL_LEFT) * 0.75);
        }
        else c = max(c, ilLabel(p, 1118.0, y2, 10.5, LB_NOPAL, IL_LEFT) * 0.75);
        col = lerp(col, ink, c);
    }
    OutputUAV[id.xy] = float4(col, 1.0);
}
