// Handles / render - the PROGRAM: a lamp and three blocks on a drafting table, top-down.
//
// Per pixel: the floor (paper grey, a drafting grid), lit by a spot lamp with distance falloff
// and a soft shadow traced toward the lamp through the occluder field (penumbra from the lamp's
// size). Blocks are lit from above with a bevel that catches the lamp. Linear light, filmic
// tonemap, display gamma. The editor overlay is drawn by the `editor` pass, never here.
#include "../_shared/ui/il_core.hlsli"
#include "handles.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

float3 lampColour(float w)
{
    float3 neutral = float3(1.00, 0.95, 0.88);    // ~4500 K
    float3 tungsten = float3(1.00, 0.68, 0.38);   // ~2700 K
    return lerp(neutral, tungsten, saturate(w));
}

// Fraction of the lamp disc visible from q: clearance h at distance t against the penumbra cone
// whose radius at t is size * t / dist.
float softShadow(float2 q, float2 dir, float dist, HdScene S)
{
    float res = 1.0;
    float t = 0.003;
    [loop] for (int i = 0; i < 48; i++)
    {
        if (t >= dist - 0.004) break;
        float h = hdField(q + dir * t, S);
        res = min(res, h * dist / (softness * t + 1e-5));
        if (res < 0.002) break;
        t += clamp(h, 0.002, 0.05);
    }
    return smoothstep(0.0, 1.0, saturate(res));
}

float3 acesFit(float3 x) { return saturate((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14)); }

float gridLine(float c, float step, float px)
{
    float d = abs(frac(c / step + 0.5) - 0.5) * step;
    return 1.0 - smoothstep(0.0, px * 1.25, d);
}

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    float2 res = _Resolution.xy;
    if (id.x >= (uint)res.x || id.y >= (uint)res.y) return;
    float2 uv = (float2(id.xy) + 0.5) / res;
    HdScene S = hdScene(res);
    float2 q = hdStage(uv, S.aspect);
    float px = 1.0 / res.y;

    // --- the table: paper grey, a faint drafting grid, centred
    float2 g = q - float2(0.5 * S.aspect, 0.5);
    float minor = max(gridLine(g.x, 0.05, px), gridLine(g.y, 0.05, px));
    float major = max(gridLine(g.x, 0.25, px), gridLine(g.y, 0.25, px));
    float grain = ilHash21(floor(q * res.y * 0.5)) - 0.5;
    float3 albedo = float3(0.30, 0.305, 0.31) * (1.0 + 0.035 * grain);
    albedo *= 1.0 - grid * (0.10 * minor + 0.16 * major);

    // --- the lamp
    float2 v = q - S.pos[H_LAMP];
    float dist = max(length(v), 1e-4);
    float2 toLamp = -v / dist;
    float2 aim = hdDir(S.rot[H_LAMP]);
    float half = 0.5 * cone * (IL_PI / 180.0);
    float feather = 0.10 + 0.25 * saturate(softness / 0.08);
    float spot = smoothstep(cos(min(half + feather, IL_PI)), cos(max(half - feather, 0.0)), dot(-toLamp, aim));
    float fall = intensity / (1.0 + (dist * dist) / (0.30 * 0.30));
    float3 L = lampColour(warmth) * fall * spot;

    uint oid;
    float sd = hdField(q, S, oid);
    float3 col;
    if (sd > 0.0)
    {
        float sh = (spot > 0.001) ? softShadow(q, toLamp, dist, S) : 0.0;
        float ao = 1.0 - 0.42 * exp(-sd / 0.010);
        col = albedo * (ambient + L * sh) * ao;
    }
    else
    {
        // a block's top: matte warm white, lit unshadowed; the bevel faces the lamp or turns away
        float e = 0.0015;
        float2 n = normalize(float2(hdField(q + float2(e, 0.0), S) - hdField(q - float2(e, 0.0), S),
                                    hdField(q + float2(0.0, e), S) - hdField(q - float2(0.0, e), S)) + 1e-6);
        float bevel = smoothstep(-0.007, 0.0, sd);
        float face = dot(n, toLamp);
        float3 top = float3(0.74, 0.72, 0.68);
        float lit = 1.0 + bevel * (0.85 * max(face, 0.0) - 0.55 * max(-face, 0.0));
        col = top * (ambient * 1.6 + L * 0.82 * lit);
    }

    // --- the fixture itself: a dark body with its lens facing the aim
    float body = length(v) - 0.013;
    float lens = max(body + 0.004, -dot(v, aim) + 0.004);
    col = lerp(col, float3(0.020, 0.020, 0.022), 1.0 - smoothstep(-px, px, body));
    col = lerp(col, lampColour(warmth) * 3.0, (1.0 - smoothstep(-px, px, lens)) * saturate(intensity));

    col = acesFit(col * 1.15);
    OutputUAV[id.xy] = float4(pow(col, 1.0 / 2.2), 1.0);
}
