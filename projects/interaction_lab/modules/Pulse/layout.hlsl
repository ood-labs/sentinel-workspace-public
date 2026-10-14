// Pulse / layout - the machine's overlay: the strikes it has sent, as a scope strip.
//
// One tick per Impact event appended to EventOut "Impacts", taller for a harder hit. What happens
// to them next - played, dropped, echoed - is shown downstream in Resonance.
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"
#include "pulse.hlsli"

StructuredBuffer<PbRec> W : register(t0);

#define SCOPE_SECONDS 4.0

void plate(float4 r, float s) { dlRect(r, IL_PANEL, 0.86, IL_RADIUS * s); }

struct Strip { float4 r; float x0, x1, y; };
Strip stripGeom(float2 res, float s)
{
    Strip g;
    g.r = float4(16.0 * s, res.y - 48.0 * s - 40.0 * s, res.x - 16.0 * s, res.y - 48.0 * s);
    g.x0 = g.r.x + 168.0 * s;
    g.x1 = g.r.z - 150.0 * s;
    g.y = ilMid(g.r).y;
    return g;
}
float stripX(Strip g, float t) { return lerp(g.x1, g.x0, saturate((_Time - t) / SCOPE_SECONDS)); }

void layout()
{
    float2 res = _Resolution.xy;
    float s = ilCtx(res).s;
    dlBegin(res);

    // header
    float4 hr = float4(16.0 * s, 14.0 * s, 0.0, 44.0 * s);
    float tw = ilLabelW(LB_TITLE, 15.0 * s), sw = ilLabelW(LB_SUBTITLE, 12.0 * s);
    hr.z = hr.x + tw + sw + 40.0 * s;
    plate(hr, s);
    float hy = ilMid(hr).y;
    dlLabel(LB_TITLE, hr.x + 12.0 * s, hy, 15.0 * s, IL_INK, IL_LEFT);
    dlLabel(LB_SUBTITLE, hr.x + 12.0 * s + tw + 14.0 * s, hy, 12.0 * s, IL_DIM, IL_LEFT);
    if ((W[W_HEAD].f & 1u) != 0u)
    {
        float aw = ilLabelW(LB_AUTO, IL_T_CAP * s) + 30.0 * s;
        float4 ar = float4(hr.z + 8.0 * s, hr.y, hr.z + 8.0 * s + aw, hr.w);
        plate(ar, s);
        dlCircle(float2(ar.x + 12.0 * s, hy), 3.0 * s, IL_INK, 1.0);
        dlLabel(LB_AUTO, ar.x + 21.0 * s, hy, IL_T_CAP * s, IL_INK, IL_LEFT);
    }

    // the strip
    Strip g = stripGeom(res, s);
    plate(g.r, s);
    float lx = g.r.x + 12.0 * s;
    dlLabel(LB_S_OUT, lx, g.y, IL_T_TITLE * s, IL_INK, IL_LEFT);
    dlLabel(LB_S_OUT_D, lx + 34.0 * s, g.y, IL_T_CAP * s, IL_DIM, IL_LEFT);
    dlHLine(g.y, g.x0, g.x1, IL_RULE);
    [loop] for (uint k = 0u; k <= 4u; k++)
    {
        float x = lerp(g.x0, g.x1, (float)k / 4.0);
        dlVLine(x, g.y - 13.0 * s, g.y - 9.0 * s, IL_DIM);
    }
    dlBatch(PB_HIST, 0u);                       // batch 0: one tick per strike
    float cx = g.r.z - 12.0 * s;
    dlLabel(LB_S_STRIKES, g.x1 + 24.0 * s, g.y, IL_T_CAP * s, IL_DIM, IL_LEFT);
    dlInt((int)W[W_STATS].c, 1, cx, g.y, IL_T_VALUE * s, IL_INK, IL_RIGHT);

    // hint bar
    float kh = 18.0 * s;
    float bx = 16.0 * s, by = res.y - 26.0 * s;
    float total = 0.0;
    [loop] for (uint k1 = 0u; k1 < 4u; k1++)
        total += ilLabelW(LB_K_CLICK + k1, IL_T_CAP * s) + 12.0 * s + 6.0 * s + ilLabelW(LB_D_CLICK + k1, IL_T_CAP * s) + 16.0 * s;
    plate(float4(bx, by - 15.0 * s, bx + total + 8.0 * s, by + 15.0 * s), s);
    bx += 10.0 * s;
    [loop] for (uint k2 = 0u; k2 < 4u; k2++)
    {
        float kw = ilLabelW(LB_K_CLICK + k2, IL_T_CAP * s) + 12.0 * s;
        float dw = ilLabelW(LB_D_CLICK + k2, IL_T_CAP * s);
        dlKeycap(float4(bx, by - kh * 0.5, bx + kw, by + kh * 0.5), s, LB_K_CLICK + k2);
        dlLabel(LB_D_CLICK + k2, bx + kw + 6.0 * s, by, IL_T_CAP * s, IL_DIM, IL_LEFT);
        bx += kw + 6.0 * s + dw + 16.0 * s;
    }
    dlFinish();
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    if (gi == 0u) layout();
    dlSync();
    float2 res = _Resolution.xy;
    float s = ilCtx(res).s;
    Strip g = stripGeom(res, s);
    ILBatch strikes = dlGetBatch(0u);
    uint i = gi;                                 // PB_HIST == IL_LAYOUT_THREADS: one each
    if (i < strikes.count)
    {
        dlAt(strikes, i);
        PbRec h = W[W_HIST0 + i];
        float age = _Time - h.a.x;
        if (h.a.x > 0.0 && age > -0.05 && age < SCOPE_SECONDS)
        {
            float x = stripX(g, h.a.x);
            float tall = (4.0 + 8.0 * saturate(h.b.x / 1200.0)) * s;
            dlLine(float2(x, g.y - tall), float2(x, g.y + tall), 1.5 * s, IL_INK, 1.0 - 0.6 * saturate(age / SCOPE_SECONDS));
        }
    }
    dlEnd(gi);
}
