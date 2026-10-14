// Resonance / layout - what each bar plays, and the bus as a scope.
//
// Note names come only from the Script (retunes and echoes): no module decides a pitch. The OUT
// row is every strike Pulse appended (read from its World data); the IN row is every echo that
// came back here, and a line joins each echo to the strike it answers, so the round trip is a
// slope you can see. A strike with no line was not played (muted, or over the Script's cap).
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"
#include "../Pulse/pulse.hlsli"

StructuredBuffer<PbRec> W : register(t0);       // Pulse's World (data input)
StructuredBuffer<PbRec> B : register(t1);       // this node's bars

#define SCOPE_SECONDS 4.0

void plate(float4 r, float s) { dlRect(r, IL_PANEL, 0.86, IL_RADIUS * s); }

struct Scope { float4 r; float x0, x1, yOut, yIn; };
Scope scopeGeom(float2 res, float s)
{
    Scope g;
    g.r = float4(16.0 * s, res.y - 48.0 * s - 74.0 * s, res.x - 16.0 * s, res.y - 48.0 * s);
    g.x0 = g.r.x + 168.0 * s;
    g.x1 = g.r.z - 196.0 * s;
    g.yOut = g.r.y + 22.0 * s;
    g.yIn = g.r.w - 22.0 * s;
    return g;
}
// every time here is in Pulse's clock (its now is W_HEAD.d) - this node's _Time started later
static float g_now = 0.0;
float scopeX(Scope g, float t) { return lerp(g.x1, g.x0, saturate((g_now - t) / SCOPE_SECONDS)); }
float2 toOut(float2 p, float2 res) { return p * res / float2(PB_W, PB_H); }

void layout()
{
    float2 res = _Resolution.xy;
    float s = ilCtx(res).s;
    g_now = W[W_HEAD].d;
    dlBegin(res);

    float4 hr = float4(16.0 * s, 14.0 * s, 0.0, 44.0 * s);
    float tw = ilLabelW(LB_TITLE, 15.0 * s), sw = ilLabelW(LB_SUBTITLE, 12.0 * s);
    hr.z = hr.x + tw + sw + 40.0 * s;
    plate(hr, s);
    float hy = ilMid(hr).y;
    dlLabel(LB_TITLE, hr.x + 12.0 * s, hy, 15.0 * s, IL_INK, IL_LEFT);
    dlLabel(LB_SUBTITLE, hr.x + 12.0 * s + tw + 14.0 * s, hy, 12.0 * s, IL_DIM, IL_LEFT);

    // what each bar plays (as told by the Script), under the bar's centre
    bool anyNote = false;
    [loop] for (uint i = 0u; i < PB_BARS; i++)
    {
        PbRec bar = B[i];
        if (bar.f == 0u) continue;
        anyNote = true;
        float2 c, dir;
        float hl;
        pbBar(i, c, dir, hl);
        float2 nd = float2(dir.y, -dir.x);
        nd = (nd.y < 0.0) ? -nd : nd;
        float2 q = toOut(c + nd * 24.0, res);
        uint note = (uint)bar.b.x;
        float since = g_now - bar.a.x;
        bool ringing = bar.a.x > 0.0 && since >= 0.0 && since < ring_time;
        float3 ink = ringing ? lerp(IL_ACCENT, IL_MID, saturate(since / max(ring_time, 0.05))) : IL_MID;
        float pw = ilLabelW(LB_PC_C + note % 12u, IL_T_BODY * s);
        float ow = ilNumW(1u, IL_T_CAP * s);
        float x = q.x - 0.5 * (pw + 2.0 * s + ow);
        x += dlLabel(LB_PC_C + note % 12u, x, q.y, IL_T_BODY * s, ink, IL_LEFT) + 2.0 * s;
        dlInt((int)(note / 12u) - 1, 1, x, q.y + 2.0 * s, IL_T_CAP * s, ringing ? ink : IL_DIM, IL_LEFT);
    }

    // the scope
    Scope g = scopeGeom(res, s);
    plate(g.r, s);
    float lx = g.r.x + 12.0 * s;
    dlLabel(LB_S_OUT, lx, g.yOut, IL_T_TITLE * s, IL_INK, IL_LEFT);
    dlLabel(LB_S_OUT_D, lx + 34.0 * s, g.yOut, IL_T_CAP * s, IL_DIM, IL_LEFT);
    dlLabel(LB_S_IN, lx, g.yIn, IL_T_TITLE * s, IL_INK, IL_LEFT);
    dlLabel(LB_S_IN_D, lx + 34.0 * s, g.yIn, IL_T_CAP * s, IL_DIM, IL_LEFT);
    dlHLine(g.yOut, g.x0, g.x1, IL_RULE);
    dlHLine(g.yIn, g.x0, g.x1, IL_RULE);
    [loop] for (uint k = 0u; k <= 4u; k++)
    {
        float x = lerp(g.x0, g.x1, (float)k / 4.0);
        dlVLine(x, g.yOut + 7.0 * s, g.yIn - 7.0 * s, IL_GRID);
    }
    dlLabel(LB_S_AGO, g.x0 - 6.0 * s, ilMid(g.r).y, IL_T_CAP * s, IL_DIM, IL_RIGHT);   // off the plot,
    dlLabel(LB_S_NOW, g.x1 + 6.0 * s, ilMid(g.r).y, IL_T_CAP * s, IL_DIM, IL_LEFT);    // so links stay clear
    dlBatch(PB_HIST, 0u);                       // batch 0: strikes on the OUT row
    dlBatch(PB_HIST * 2u, 1u);                  // batch 1: echoes on the IN row + their links

    // the counts are of what the scope shows, so a strike without a link is one you can count
    uint inView = 0u, playedInView = 0u;
    [loop] for (uint m = 0u; m < PB_HIST; m++)
    {
        float ao = g_now - W[W_HIST0 + m].a.x, ai = g_now - B[B_HIST0 + m].a.x;
        inView += (W[W_HIST0 + m].a.x > 0.0 && ao > -0.05 && ao < SCOPE_SECONDS) ? 1u : 0u;
        playedInView += (B[B_HIST0 + m].a.x > 0.0 && ai > -0.05 && ai < SCOPE_SECONDS) ? 1u : 0u;
    }
    float cx = g.r.z - 12.0 * s;
    float vs = IL_T_VALUE * s;
    float xl = g.x1 + 44.0 * s;
    float rowMid = ilMid(g.r).y;
    PbRec bh = B[B_HEAD];
    dlLabel(LB_S_STRIKES, xl, g.yOut, IL_T_CAP * s, IL_DIM, IL_LEFT);
    dlInt((int)inView, 1, cx, g.yOut, vs, IL_INK, IL_RIGHT);
    dlLabel(LB_S_PLAYED, xl, rowMid, IL_T_CAP * s, IL_DIM, IL_LEFT);
    dlInt((int)playedInView, 1, cx, rowMid, vs, IL_INK, IL_RIGHT);
    dlLabel(LB_S_TRIP, xl, g.yIn, IL_T_CAP * s, IL_DIM, IL_LEFT);
    float msw = dlLabel(LB_S_MS, cx, g.yIn, IL_T_CAP * s, IL_DIM, IL_RIGHT);
    // a live reading while echoes are arriving; the last value, dimmed, once they stop (muted)
    if (bh.a.x > 0.0) dlNum(bh.a.y, 0, cx - msw - 4.0 * s, g.yIn, vs, playedInView > 0u ? IL_ACCENT : IL_DIM, IL_RIGHT);
    if (!anyNote) dlLabel(LB_WAITING, 0.5 * (g.x0 + g.x1), g.r.y - 14.0 * s, IL_T_CAP * s, IL_MID, IL_CENTER);

    float4 fr = float4(16.0 * s, res.y - 41.0 * s, 16.0 * s + ilLabelW(LB_FOOT, IL_T_CAP * s) + 24.0 * s, res.y - 11.0 * s);
    plate(fr, s);
    dlLabel(LB_FOOT, fr.x + 12.0 * s, ilMid(fr).y, IL_T_CAP * s, IL_DIM, IL_LEFT);
    dlFinish();
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    if (gi == 0u) layout();
    dlSync();
    g_now = W[W_HEAD].d;
    float2 res = _Resolution.xy;
    float s = ilCtx(res).s;
    Scope g = scopeGeom(res, s);

    // PB_HIST == IL_LAYOUT_THREADS: one strike and one echo per thread
    ILBatch strikes = dlGetBatch(0u);
    if (gi < strikes.count)
    {
        dlAt(strikes, gi);
        PbRec h = W[W_HIST0 + gi];
        float age = g_now - h.a.x;
        if (h.a.x > 0.0 && age > -0.05 && age < SCOPE_SECONDS)
        {
            float x = scopeX(g, h.a.x);
            float tall = (4.0 + 8.0 * saturate(h.b.x / 1200.0)) * s;
            dlLine(float2(x, g.yOut - tall), float2(x, g.yOut + tall), 1.5 * s, IL_INK, 1.0 - 0.6 * saturate(age / SCOPE_SECONDS));
        }
    }
    ILBatch echoes = dlGetBatch(1u);
    dlAtSpan(echoes, gi, 2u);
    PbRec e = B[B_HIST0 + gi];
    float age = g_now - e.a.x;
    if (e.a.x > 0.0 && age > -0.05 && age < SCOPE_SECONDS)
    {
        float x = scopeX(g, e.a.x);
        float fade = 1.0 - 0.6 * saturate(age / SCOPE_SECONDS);
        if (e.b.x > 0.0)
            dlLine(float2(scopeX(g, e.b.x), g.yOut + 5.0 * s), float2(x, g.yIn - 5.0 * s), 1.0 * s, IL_MID, 0.55 * fade);
        float tall = (4.0 + 8.0 * e.c) * s;
        dlLine(float2(x, g.yIn - tall), float2(x, g.yIn + tall), 1.5 * s, IL_INK, fade);
    }
    dlEnd(gi);
}
