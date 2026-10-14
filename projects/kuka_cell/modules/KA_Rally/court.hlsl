// KA_Rally / court.hlsl — the rally instrument's DRAWING.
//
// A COURT PLAN over a FLIGHT PROFILE. Those are the two things a rally is made of: where on the
// floor the ball is going, and the shape of the arc that takes it there.
//
// The profile strip is deliberately FORWARD-looking rather than a history trace. A record of
// where the ball has been is nostalgia; what you actually want to know is whether this arc comes
// down through strike height inside somebody's reach, and when. Both strips are drawn from the
// trajectory records the election itself used, so the diagram cannot show a different arc from
// the one the arms are playing.
//
// The failure mode is in the diagram: a predicted contact point that no arm can reach turns
// alarm red and the readout says DROP. That is the one state that ends a rally.
//
// This pass draws the two views on their plates. The PLAY pane, every caption and readout, the
// hover card, the legend and the footer are recorded by layout.hlsl and drawn over this by the
// shared UI kit (ui.hlsl).
#include "../_shared/cell.hlsli"
#include "../_shared/ui/il_core.hlsli"
#include "../_shared/ka_ui.hlsli"
#include "court_frame.hlsli"

StructuredBuffer<KaBall> Rally : register(t0);
StructuredBuffer<KaRec>  Cell  : register(t1);
RWTexture2D<float4> OutputUAV : register(u0);

float strokeAA(float d, float w) { return 1.0 - smoothstep(w - 0.7, w + 0.7, d); }
float discAA(float2 p, float2 c, float r) { return 1.0 - smoothstep(r - 0.8, r + 0.8, length(p - c)); }
float ringAA(float2 p, float2 c, float r, float w) { return strokeAA(abs(length(p - c) - r), w); }
float dashRingAA(float2 p, float2 c, float r, float w, float dashes)
{
    float2 d = p - c;
    float a = atan2(d.y, d.x) / KA_TAU + 0.5;
    return ringAA(p, c, r, w) * step(frac(a * dashes), 0.5);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    uint2 pixel = DTid.xy;
    if (pixel.x >= W || pixel.y >= H) return;
    float2 P = (float2)pixel + 0.5;

    KaBall hdr = Rally[KA_HEADER];
    KaRec  chdr = Cell[KA_HEADER];
    float cw = max(chdr.bias, 4.0);
    float cd = max(chdr.flags, 4.0);
    int striker = (int)hdr.strikerIdx;
    int lastS = (int)hdr.lastIdx;
    bool dropped = hdr.dropFlag > 0.5;
    bool idle = hdr.role == KA_PLAY_IDLE;

    CtFrame F = ctFrame(float2(W, H), cw, cd);
    float us = F.s;
    float s = F.ppm;                    // one isotropic scale for the court, so a reach circle is a circle
    float2 planC = F.planC;

    float3 outCol = IL_FIELD;

    // ================= court plan =================
    float dCourt = ilSdBox(P, F.court, IL_RADIUS * us);
    if (dCourt < 1.0)
    {
        float3 col = IL_PANEL;
        float2 wp = (P - planC) / s;      // metres, y is world Z

        float2 g1 = abs(frac(wp + 0.5) - 0.5) * s;
        float2 g5 = abs(frac(wp / 5.0 + 0.5) - 0.5) * s * 5.0;
        col = lerp(col, PT_GRID, strokeAA(min(g1.x, g1.y), 0.55) * 0.85);
        col = lerp(col, PT_GRID * 1.9, strokeAA(min(g5.x, g5.y), 0.65));
        col = lerp(col, PT_RULE * 0.8,
                   strokeAA(abs(ilSdBox(P, float4(planC - float2(cw, cd) * 0.5 * s, planC + float2(cw, cd) * 0.5 * s), 0.0)), 0.9));

        // ---- players ----
        for (uint i = 0u; i < KA_MAX_ARMS; i++)
        {
            KaRec r = Cell[KA_ARM_0 + i];
            if (r.active < 0.5) continue;
            KaBall a = Rally[KA_ARM_0 + i];
            float2 c = planC + r.pos * s;
            float pr = max(ka_spec(r.kind, r.size.x).ped_r * s, 2.4);
            bool plays = a.role != KA_ROLE_NONE;

            if (!plays)
            {
                // benched: still drawn, because "why is nobody covering that corner" is a
                // question the diagram has to be able to answer
                col = lerp(col, PT_RULE * 0.5, ringAA(P, c, pr, 0.7) * 0.7);
                continue;
            }

            // the reach the election uses: horizontal, at the strike plane
            float reach = ctPlayReach(r);
            col = lerp(col, PT_RULE * 0.62, dashRingAA(P, c, reach * s, 0.7, 40.0) * 0.75);

            float3 body = ptId((int)r.grp);
            col = lerp(col, body * 0.55, discAA(P, c, pr));
            col = lerp(col, body, ringAA(P, c, pr, 0.9));

            if (a.role == KA_ROLE_STRIKE || a.role == KA_ROLE_RECEIVE)
            {
                // the elected arm and the air it owns: the accent's job here is the live reading
                col = lerp(col, PT_ACCENT, ringAA(P, c, pr * 1.8, 1.2));
                col = lerp(col, PT_ACCENT * 0.85, dashRingAA(P, c, reach * s, 0.9, 40.0));
            }
            else if (a.role == KA_ROLE_RECOVER)
            {
                col = lerp(col, PT_INK, ringAA(P, c, pr * 1.5, 0.8) * 0.8);
            }
            if ((int)i == lastS)
                col = lerp(col, PT_MID, ringAA(P, c, pr * 2.3, 0.6) * 0.6);
        }

        // ---- the predicted arc, projected onto the floor ----
        {
            float2 prev = float2(0, 0); bool have = false;
            for (uint t = 0u; t < KA_TRAJ_N; t++)
            {
                KaBall sm = Rally[KA_TRAJ_0 + t];
                if (sm.role < 0.5) break;
                float2 q = planC + float2(sm.pos.x, sm.pos.z) * s;
                if (have)
                {
                    // dotted, because it is a prediction and should not read as structure
                    float d = ilSdSeg(P, prev, q);
                    col = lerp(col, PT_MID, strokeAA(d, 0.8) * step(frac(length(P - planC) * 0.10), 0.55) * 0.85);
                }
                prev = q; have = true;
            }
        }

        // ---- pass intent: from whoever just hit it, to whoever they aimed at ----
        if (lastS >= 0)
        {
            KaBall la = Rally[KA_ARM_0 + (uint)lastS];
            int aim = (int)la.aimIdx;
            if (aim >= 0 && aim < (int)KA_MAX_ARMS)
            {
                float2 a0 = planC + Cell[KA_ARM_0 + (uint)lastS].pos * s;
                float2 a1 = planC + Cell[KA_ARM_0 + (uint)aim].pos * s;
                float d = ilSdSeg(P, a0, a1);
                col = lerp(col, PT_RULE * 1.25, strokeAA(d, 0.6) * step(frac(length(P - a0) * 0.08), 0.5) * 0.7);
            }
        }

        // ---- the predicted contact ----
        if (!idle)
        {
            if (striker >= 0 || dropped)
            {
                float3 mk = dropped ? PT_ALARM : PT_ACCENT;
                float2 pt = planC + float2(hdr.pos.x, hdr.pos.z) * s;
                if (striker >= 0)
                {
                    KaBall sa = Rally[KA_ARM_0 + (uint)striker];
                    pt = planC + float2(sa.pos.x, sa.pos.z) * s;
                }
                float m = ringAA(P, pt, 8.0, 1.0);
                m = max(m, strokeAA(ilSdSeg(P, pt - float2(13, 0), pt - float2(8, 0)), 0.9));
                m = max(m, strokeAA(ilSdSeg(P, pt + float2(8, 0), pt + float2(13, 0)), 0.9));
                m = max(m, strokeAA(ilSdSeg(P, pt - float2(0, 13), pt - float2(0, 8)), 0.9));
                m = max(m, strokeAA(ilSdSeg(P, pt + float2(0, 8), pt + float2(0, 13)), 0.9));
                col = lerp(col, mk, m);
            }

            // ---- the ball, with its floor shadow ----
            float2 sp = planC + float2(hdr.pos.x, hdr.pos.z) * s;
            col = lerp(col, IL_FIELD, discAA(P, sp, max(hdr.radius * s, 2.0)) * 0.7);
            col = lerp(col, PT_INK, ringAA(P, sp, max(hdr.radius * s, 2.5), 1.2));
            col = lerp(col, PT_INK, discAA(P, sp, 2.0));
        }
        ilOver(outCol, col, ilFill(dCourt));
    }

    // ================= flight profile =================
    float dFly = ilSdBox(P, F.fly, IL_RADIUS * us);
    if (dFly < 1.0)
    {
        float3 col = IL_PANEL;
        float hmax = ctHMax();
        float floorY = F.plot.w;
        float topY = F.plot.y;
        bool inPlotX = P.x >= F.plot.x - 2.0 && P.x <= F.plot.z + 2.0;

        // height gridlines every metre, and the strike plane
        for (uint k = 1u; k < 9u; k++)
        {
            float hy = lerp(floorY, topY, (float)k / hmax);
            if (hy < topY) break;
            col = lerp(col, PT_GRID * 1.7, strokeAA(abs(P.y - hy), 0.5) * (inPlotX ? 1.0 : 0.0));
        }
        float shY = ctFlyY(F, strike_h);
        col = lerp(col, PT_RULE * 1.2, strokeAA(abs(P.y - shY), 0.6) * step(frac(P.x * 0.10), 0.5) * (inPlotX ? 1.0 : 0.0));

        // the arc
        float2 prev = float2(0, 0); bool have = false;
        for (uint t = 0u; t < KA_TRAJ_N; t++)
        {
            KaBall sm = Rally[KA_TRAJ_0 + t];
            if (sm.role < 0.5) break;
            float2 q = float2(ctFlyX(F, sm.radius), ctFlyY(F, sm.pos.y));
            if (have) col = lerp(col, PT_MID, strokeAA(ilSdSeg(P, prev, q), 1.0));
            prev = q; have = true;
        }

        // where it is now, and where it will be struck
        col = lerp(col, PT_INK, discAA(P, float2(F.plot.x, ctFlyY(F, hdr.pos.y)), 3.0));
        if (striker >= 0)
        {
            KaBall sa = Rally[KA_ARM_0 + (uint)striker];
            float2 cpt = float2(ctFlyX(F, sa.radius), shY);
            col = lerp(col, PT_ACCENT, ringAA(P, cpt, 5.5, 1.0));
            col = lerp(col, PT_ACCENT, strokeAA(ilSdSeg(P, cpt - float2(0, 8), cpt + float2(0, 8)), 0.6) * 0.7);
        }
        else if (dropped)
        {
            col = lerp(col, PT_ALARM, strokeAA(abs(P.y - shY), 1.0) * 0.5 * (inPlotX ? 1.0 : 0.0));
        }

        col = lerp(col, PT_RULE * 1.35, strokeAA(abs(P.y - floorY), 0.9) * (inPlotX ? 1.0 : 0.0));
        ilOver(outCol, col, ilFill(dFly));
    }

    OutputUAV[pixel] = float4(outCol, 1.0);
}
