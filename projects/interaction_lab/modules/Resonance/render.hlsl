// Resonance / render - Pulse's image, with the bars the Script PLAYED lit over it:
//   a warm glow and a warmed face that decay with Ring Time;
//   the bar's first bending mode drawn as its envelope - two hairlines that pinch to nothing at
//   the pins, which is exactly why a glockenspiel bar is held there;
//   a ripple from the contact point (taken from Pulse's World data).
// A strike the Script did not play (muted, or over its cap) shows only Pulse's cool spark.
#include "../Pulse/pulse.hlsli"

StructuredBuffer<PbRec> W : register(t1);       // Pulse's World (data input "World")
StructuredBuffer<PbRec> B : register(t2);       // this node's bars (written by `echo`)
RWTexture2D<float4> OutputUAV : register(u0);

float sdRoundBox(float2 p, float2 b, float r) { float2 q = abs(p) - b + r; return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r; }
float2 upNormal(float2 dir) { float2 n = float2(dir.y, -dir.x); return (n.y > 0.0) ? -n : n; }

float ringEnv(PbRec bar, float t)
{
    if (bar.a.x <= 0.0 || t < bar.a.x) return 0.0;
    return bar.a.y * exp(-(t - bar.a.x) / max(ring_time * 0.45, 0.02));
}

[numthreads(8, 8, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    uint w, h;
    OutputUAV.GetDimensions(w, h);
    if (id.x >= w || id.y >= h) return;
    float2 res = float2(w, h);
    float2 p = (float2(id.xy) + 0.5) * float2(PB_W, PB_H) / res;
    float pxw = PB_W / res.x;
    float t = W[W_HEAD].d;                                     // Pulse's clock (see pulse.hlsli)
    float3 col = pow(saturate(_Tex0.Load(int3(id.xy, 0)).rgb), 2.2);   // to linear
    const float3 warm = float3(1.00, 0.76, 0.46);

    [loop] for (uint i = 0u; i < PB_BARS; i++)
    {
        PbRec bar = B[i];
        float env = ringEnv(bar, t);
        float since = t - bar.a.x;
        if (env < 0.003 && !(bar.a.x > 0.0 && since >= 0.0 && since < 0.8)) continue;
        float2 c, dir;
        float hl;
        pbBar(i, c, dir, hl);
        float2 nu = upNormal(dir);
        float2 rel = p - c;
        float along = dot(rel, dir);
        float across = dot(rel, nu);
        float sd = sdRoundBox(float2(along, across), float2(hl, PB_BAR_T), 2.5);

        // glow, and the face warming under it
        col += warm * env * 0.30 * glow * exp(-max(sd, 0.0) / 12.0);
        float inside = saturate(0.5 - sd / pxw);
        col = lerp(col, col * float3(1.0, 0.86, 0.66) + warm * 0.20 * glow, inside * env);

        // the mode envelope: +-A phi(u), pinched at the nodes
        float u = along / hl;
        if (abs(u) <= 1.0)
        {
            float a = (6.0 + 10.0 * bar.a.y) * env * pbMode(u);
            float dEnv = min(abs(across - a), abs(across + a)) - 0.55;
            col += warm * env * 0.85 * saturate(0.5 - dEnv / pxw);
        }

        // the ripple from where the ball hit
        if (bar.a.x > 0.0 && since >= 0.0 && since < 0.8)
        {
            PbRec sp = W[W_SPARK0 + i];
            float2 q = c + dir * (sp.a.y * 2.0 - 1.0) * hl + nu * PB_BAR_T;
            float r = 10.0 + 110.0 * since;
            float ring = abs(length(p - q) - r) - 0.8;
            col += warm * saturate(0.5 - ring / pxw) * pow(1.0 - since / 0.8, 2.0) * (0.25 + 0.55 * bar.a.y) * glow;
        }
    }
    OutputUAV[id.xy] = float4(pow(saturate(col), 1.0 / 2.2), 1.0);
}
