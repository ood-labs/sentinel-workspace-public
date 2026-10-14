// Plotter / present - the sheet as it looks: warm paper with a little grain, the pencil
// underdrawing, the inks laid subtractively (each pen's density darkens the paper toward the pen's
// colour, and past it where the pen dwelt or lines cross), and the pen head on its gantry - its
// shadow longer while the pen is up.
#include "plotter.hlsli"

StructuredBuffer<float4> PL : register(t0);       // the plan: state and pen
StructuredBuffer<uint> G : register(t2);          // the pencil guide
RWTexture2D<float4> OutputUAV : register(u0);     // (slot 1, the sheet, reads as _Tex1)

float hash21(float2 p)
{
    p = frac(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return frac(p.x * p.y);
}

float vnoise(float2 p)
{
    float2 i = floor(p), f = frac(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash21(i), b = hash21(i + float2(1.0, 0.0)), c = hash21(i + float2(0.0, 1.0)), d = hash21(i + float2(1.0, 1.0));
    return lerp(lerp(a, b, u.x), lerp(c, d, u.x), u.y);
}

float disc(float2 p, float2 c, float r, float soft) { return smoothstep(r + soft, r - soft, length(p - c)); }
float ring(float2 p, float2 c, float r, float w) { return smoothstep(0.5 * w + 0.75, 0.5 * w - 0.25, abs(length(p - c) - r)); }

[numthreads(16, 16, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    if (id.x >= (uint)_Resolution.x || id.y >= (uint)_Resolution.y) return;
    float2 p = (float2)id.xy + 0.5;
    float2 uv = p / _Resolution.xy;

    // paper: a long soft grain and a fine tooth, a little darker toward the corners
    float3 paper = srgbToLinear(float3(0.937, 0.914, 0.867));
    float grain = vnoise(p * float2(0.045, 0.012)) * 0.55 + vnoise(p * 0.9) * 0.45;
    paper *= 0.972 + 0.05 * grain;
    float2 vc = uv - 0.5;
    paper *= 1.0 - 0.16 * dot(vc, vc);

    // the pencil underdrawing, broken by the paper's tooth
    uint gv = G[id.y * 1280u + id.x];
    float g = ((gv >> 8) == G[PL_PENCIL_COOK]) ? (float)(gv & 255u) / 255.0 * saturate(pencil) : 0.0;
    g *= 0.55 + 0.45 * vnoise(p * 1.3);
    paper *= 1.0 - 0.5 * g * float3(1.0, 0.99, 0.97);

    // inks, subtractively: density 1 is the pen's own colour, more is darker
    float4 d = _Tex1.Load(int3(id.xy, 0));
    float3 absorb = 0.0;
    [unroll] for (uint k = 0u; k < 4u; k++)
        absorb += d[k] * -log(max(srgbToLinear(plotInk(k)), 0.003));
    float3 col = paper * exp(-absorb);

    // the pen head: 0 down .. 1 up, eased through the drop and the lift
    float4 st = PL[PL_STATE], pen = PL[PL_PEN];
    uint state = (uint)st.x;
    float liftT = clamp(lift, 0.02, 1.0);
    float h = state == ST_DRAW ? 0.0 : (state == ST_DROP ? 1.0 - saturate(st.w / liftT) : (state == ST_LIFT ? saturate(st.w / liftT) : 1.0));
    float2 c = pen.xy;
    float rails = (smoothstep(1.2, 0.2, abs(p.x - c.x - 13.0)) + smoothstep(1.2, 0.2, abs(p.x - c.x + 13.0))) * 0.07;
    col *= 1.0 - rails;
    float shadow = disc(p, c + float2(2.0, 3.0) + h * float2(5.0, 7.0), 8.0 + 2.0 * h, 3.0 + 2.0 * h) * (0.16 - 0.05 * h);
    col *= 1.0 - shadow;
    float3 body = srgbToLinear(float3(0.20, 0.205, 0.215));
    col = lerp(col, body, ring(p, c, 7.0, 1.6) * 0.85);
    col = lerp(col, body, disc(p, c, 1.6, 0.6) * (1.0 - h));
    OutputUAV[id.xy] = float4(linearToSrgb(col), 1.0);
}
