// KA_Cell / canvas.hlsl — the editor surface's DRAWING.
//
// A draughtsman's PLAN over an ELEVATION of the robot cell, sharing the world X axis and one
// metres-per-pixel scale. Reading it should answer, without opening the renderer: where does every
// machine stand, which way does it face, how big a frame is it, which control channel drives it, how
// tall does it stand, how far can it reach — and, critically, CAN ANY TWO OF THEM HIT EACH OTHER.
//
// That last one is the failure the render cannot show you until it happens, so it is drawn: every
// point of floor that two work envelopes can both reach is shaded alarm red.
//
// This pass draws only the two views, each on its plate. The type and chrome — title, captions, the
// height ruler, the inspector panes, the hover card and the keycap footer — are recorded by
// layout.hlsl and drawn over this by the shared UI kit (ui.hlsl).
//
// Instrument palette (plan_theme.hlsli, through il_core.hlsli): mostly monochrome. Hue is spent on
// exactly three things — the accent for the selection, alarm for a broken cell, and the four-member
// identity set for the control channels, which is a closed unordered set the eye must separate at a
// glance. Frame size is ORDINAL, so it is a value ramp, not a hue.
#include "../_shared/cell.hlsli"
#include "../_shared/ui/il_core.hlsli"
#include "../_shared/ka_ui.hlsli"
#include "layout.hlsli"
#include "ui_frame.hlsli"

StructuredBuffer<KaRec> Cell : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

// ---------------------------------------------------------------------------
// pixel-space drawing primitives
// ---------------------------------------------------------------------------
float strokeAA(float d, float w) { return 1.0 - smoothstep(w - 0.7, w + 0.7, d); }
float discAA(float2 p, float2 c, float r) { return 1.0 - smoothstep(r - 0.8, r + 0.8, length(p - c)); }
float ringAA(float2 p, float2 c, float r, float w) { return strokeAA(abs(length(p - c) - r), w); }
// dashed ring: `dashes` full cycles around the circle, half lit
float dashRingAA(float2 p, float2 c, float r, float w, float dashes)
{
    float2 d = p - c;
    float a = atan2(d.y, d.x) / KA_TAU + 0.5;
    return ringAA(p, c, r, w) * step(frac(a * dashes), 0.5);
}
// the declared cell outline: a stroke centred on the rectangle's edge
float boxEdgeAA(float2 p, float2 lo, float2 hi, float w)
{
    return strokeAA(abs(ilSdBox(p, float4(lo, hi), 0.0)), w);
}

// ---------------------------------------------------------------------------
// The armature: the lattice the layout was strung along, rebuilt from the SAME function with
// no seed of its own so the guides it draws are guaranteed to be the guides the records were
// placed on. Drawn heavier and brighter than the record hairlines on purpose — a skeleton at
// hairline weight is indistinguishable from the fifty outlines it exists to explain.
// ---------------------------------------------------------------------------
KaLattice canvasLattice(float s, float v)
{
    KaLattice L;
    L.pitch   = lerp(pitch,         pitch  * lerp(0.62, 1.55, ka_rnd(s, 1.0)), v);
    L.rows    = lerp((float)rows,   floor(lerp(1.0, 6.99, ka_rnd(s, 2.0))),    v);
    L.stagger = lerp(stagger,       ka_srnd(s, 3.0),                            v);
    L.radius  = lerp(radius,        radius * lerp(0.62, 1.55, ka_rnd(s, 4.0)), v);
    L.span    = lerp(span * KA_D2R, lerp(60.0, 320.0, ka_rnd(s, 5.0)) * KA_D2R, v);
    L.skew    = lerp(skew * KA_D2R, ka_srnd(s, 6.0) * 0.85,                     v);
    L.conv    = lerp(converge,      ka_rnd(s, 7.0),                             v);
    L.rows    = max(L.rows, 1.0);
    L.pitch   = max(L.pitch, 0.8);
    return L;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    uint2 pixel = DTid.xy;
    if (pixel.x >= W || pixel.y >= H) return;

    float2 res = float2(W, H);
    float2 uv = ((float2)pixel + 0.5) / res;
    float2 P = (float2)pixel + 0.5;
    float us = kaUiScale(res);

    KaRec hdr = Cell[KA_HEADER];
    float cw      = max(hdr.bias, 0.5);
    float cd      = max(hdr.flags, 0.5);
    float salt    = hdr.seed;
    float maxRise = max(hdr.spare, 0.5);

    // Same map the state pass picked with — _Resolution, not GetDimensions, for exactly that
    // reason. The output pass inherits the root resolution, so under follow_panel the two still
    // agree; if a pass ever gets its own resolution, both must change together.
    KaMap m = kaMap(_Resolution.xy, cw, cd, maxRise);

    float3 outCol = IL_FIELD;

    float4 planR = kcPlanRect(res), elevR = kcElevRect(res);
    float dPlan = ilSdBox(P, planR, IL_RADIUS * us);
    float dElev = ilSdBox(P, elevR, IL_RADIUS * us);

    // ================= plan strip =================
    if (dPlan < 1.0)
    {
        float3 col = IL_PANEL;
        float2 wp = kaUVPlan(m, uv);              // this pixel in metres on the cell floor

        float2 g1 = abs(frac(wp + 0.5) - 0.5) * m.s;
        float2 g5 = abs(frac(wp / 5.0 + 0.5) - 0.5) * m.s * 5.0;
        col = lerp(col, PT_GRID, strokeAA(min(g1.x, g1.y), 0.55) * 0.9);
        col = lerp(col, PT_GRID * 1.9, strokeAA(min(g5.x, g5.y), 0.65));

        // declared cell outline
        float2 cLo = kaPlanUV(m, float2(-cw * 0.5, -cd * 0.5)) * res;
        float2 cHi = kaPlanUV(m, float2( cw * 0.5,  cd * 0.5)) * res;
        col = lerp(col, PT_RULE * 0.8, boxEdgeAA(P, cLo, cHi, 0.9));

        // ---- armature ----
        uint want = (uint)clamp((float)arm_count, 1.0, (float)KA_MAX_ARMS);
        KaLattice L = canvasLattice(seed + salt * 3.19, saturate(variation));
        int arr = (int)clamp((float)arrangement, 0.0, (float)(KA_ARR_COUNT - 1));
        float arm = 0.0;
        float2 prev = float2(0, 0); bool havePrev = false;
        for (uint ai = 0u; ai < want; ai++)
        {
            float2 sp; float shd;
            ka_station(arr, ai, want, L, sp, shd);
            float2 spx = kaPlanUV(m, sp) * res;
            if (havePrev && length(sp - prev) < L.pitch * 2.35)
                arm = max(arm, strokeAA(ilSdSeg(P, kaPlanUV(m, prev) * res, spx), 1.15));
            // the station node: where the lattice says a machine belongs, whether or not one does
            arm = max(arm, ringAA(P, spx, 3.2, 0.8) * 0.8);
            prev = sp; havePrev = true;
        }
        col = lerp(col, PT_MID, arm * 0.85);

        // ---- work envelopes, and the overlap that makes a cell broken ----
        float cover = 0.0, envEdge = 0.0, selEdge = 0.0;
        for (uint i = 0u; i < KA_MAX_ARMS; i++)
        {
            KaRec r = Cell[KA_ARM_0 + i];
            if (r.active < 0.5) continue;
            float2 c = kaPlanUV(m, r.pos) * res;
            float rr = kaLenX(m, ka_reachOf(r)) * res.x;
            if (length(P - c) < rr) cover += 1.0;
            envEdge = max(envEdge, dashRingAA(P, c, rr, 0.75, 46.0));
            if (((uint)r.flags & KF_SELECTED) != 0u) selEdge = max(selEdge, ringAA(P, c, rr, 0.9));
        }
        col = lerp(col, PT_RULE * 0.75, envEdge * 0.75);
        // Shared reach: two machines that can both put a tool here. A low wash, so it reads as
        // an area rather than competing with the records sitting inside it.
        col = lerp(col, PT_ALARM * 0.55, saturate(cover - 1.0) * 0.22);

        // ---- the machines ----
        for (uint j = 0u; j < KA_MAX_ARMS; j++)
        {
            KaRec r = Cell[KA_ARM_0 + j];
            KaSpec sp2 = ka_spec(r.kind, r.size.x);
            float2 c = kaPlanUV(m, r.pos) * res;
            float pr = max(kaLenX(m, sp2.ped_r) * res.x, 2.4);
            uint fl = (uint)r.flags;

            if (r.active < 0.5)
            {
                col = lerp(col, PT_RULE * 0.55, ringAA(P, c, pr, 0.7) * 0.7);
                continue;
            }

            float3 body = ptRamp(0.30 + r.kind * 0.35);   // frame size is ordinal -> value
            col = lerp(col, body * 0.55, discAA(P, c, pr));
            col = lerp(col, body, ringAA(P, c, pr, 1.0));
            col = lerp(col, body * 1.15, discAA(P, c, pr * 0.42));

            // Heading, carrying the CHANNEL identity colour — the one thing about an arm that
            // no value on the footprint can say.
            float2 dir = float2(cos(r.yaw), -sin(r.yaw));   // plan +y is world +Z, drawn downward
            float hl = max(kaLenX(m, ka_reachOf(r) * 0.42) * res.x, pr * 1.8);
            float2 tip = c + dir * hl;
            float2 nrm = float2(-dir.y, dir.x);
            float head = strokeAA(ilSdSeg(P, c + dir * pr * 0.6, tip), 1.35);
            head = max(head, strokeAA(ilSdSeg(P, tip, tip - dir * 5.5 + nrm * 3.6), 1.0));
            head = max(head, strokeAA(ilSdSeg(P, tip, tip - dir * 5.5 - nrm * 3.6), 1.0));
            col = lerp(col, ptId((int)r.grp), head);

            if ((fl & KF_EDITED) != 0u)
                col = lerp(col, PT_INK, ringAA(P, c, pr * 1.55, 0.7) * 0.75);
            if ((fl & KF_OUTSIDE) != 0u)
                col = lerp(col, PT_ALARM, ringAA(P, c, pr * 1.30, 1.1));
            if ((fl & KF_SELECTED) != 0u)
            {
                col = lerp(col, PT_ACCENT, ringAA(P, c, pr * 1.9, 1.2));
                col = lerp(col, PT_ACCENT, strokeAA(ilSdSeg(P, c - float2(pr * 3.2, 0), c - float2(pr * 2.2, 0)), 0.9));
                col = lerp(col, PT_ACCENT, strokeAA(ilSdSeg(P, c + float2(pr * 2.2, 0), c + float2(pr * 3.2, 0)), 0.9));
                col = lerp(col, PT_ACCENT, strokeAA(ilSdSeg(P, c - float2(0, pr * 3.2), c - float2(0, pr * 2.2)), 0.9));
                col = lerp(col, PT_ACCENT, strokeAA(ilSdSeg(P, c + float2(0, pr * 2.2), c + float2(0, pr * 3.2)), 0.9));
            }
        }
        col = lerp(col, PT_ACCENT * 0.9, selEdge * 0.85);

        // ---- the Point At target, drawn last because it sits on top of everything ----
        {
            KaRec t = Cell[KA_TARGET];
            float3 tp = ka_targetPos(t);
            float2 ac = kaPlanUV(m, t.pos) * res;
            float2 lc = kaPlanUV(m, float2(tp.x, tp.z)) * res;
            float orb = kaLenX(m, t.size.y) * res.x;
            bool tsel = ((uint)t.flags & KF_SELECTED) != 0u;
            // PT_INK, not the accent: the accent is the selection's, and a permanently amber
            // mark would make every real selection ambiguous. It earns the accent when picked.
            float3 tc = tsel ? PT_ACCENT : PT_INK;
            float hasOrb = (t.size.y > 0.05) ? 1.0 : 0.0;

            col = lerp(col, PT_RULE * 1.15, dashRingAA(P, ac, orb, 0.7, 64.0) * 0.85 * hasOrb);
            col = lerp(col, PT_RULE * 1.3, ringAA(P, ac, 2.8, 0.7) * hasOrb);
            col = lerp(col, PT_RULE * 1.0, strokeAA(ilSdSeg(P, ac, lc), 0.55) * hasOrb * 0.6);

            col = lerp(col, tc, ringAA(P, lc, 8.0, 1.1));
            col = lerp(col, tc, discAA(P, lc, 2.3));
            col = lerp(col, tc, strokeAA(ilSdSeg(P, lc - float2(15, 0), lc - float2(10, 0)), 0.9));
            col = lerp(col, tc, strokeAA(ilSdSeg(P, lc + float2(10, 0), lc + float2(15, 0)), 0.9));
            col = lerp(col, tc, strokeAA(ilSdSeg(P, lc - float2(0, 15), lc - float2(0, 10)), 0.9));
            col = lerp(col, tc, strokeAA(ilSdSeg(P, lc + float2(0, 10), lc + float2(0, 15)), 0.9));
        }
        ilOver(outCol, col, ilFill(dPlan));
    }

    // ================= elevation strip =================
    if (dElev < 1.0)
    {
        float3 col = IL_PANEL;
        float hm = kaUVElevH(m, uv.y);
        col = lerp(col, PT_GRID, strokeAA(abs(frac(hm + 0.5) - 0.5) * m.s, 0.55) * (hm > -0.02 ? 0.9 : 0.0));

        float halfD = max(cd * 0.5, 0.001);
        for (uint i = 0u; i < KA_MAX_ARMS; i++)
        {
            KaRec r = Cell[KA_ARM_0 + i];
            if (r.active < 0.5) continue;
            KaSpec sp = ka_spec(r.kind, r.size.x);
            bool isSel = ((uint)r.flags & KF_SELECTED) != 0u;

            // Depth is the axis this strip cannot show, so it is carried as a value: machines
            // further back sit further down the ramp. That is what stops the elevation reading
            // as one flat row of identical outlines.
            float dt = saturate((halfD - r.pos.y) / max(cd, 0.001));
            float3 body = isSel ? PT_ACCENT : ptRamp(0.16 + dt * 0.66);

            // The standing posture is the HOME pose. Motion belongs to KA_Pose; this strip is
            // about where a machine stands and how much air it owns.
            KaChain ch = ka_chain(sp, r.size.y, 0.0, KA_HOME_A2, KA_HOME_A3, KA_HOME_A5);
            float2 base = kaElevUV(m, r.pos.x, 0.0) * res;
            float2 shd  = kaElevUV(m, r.pos.x + ch.shoulder.x, ch.shoulder.y) * res;
            float2 elb  = kaElevUV(m, r.pos.x + ch.elbow.x,    ch.elbow.y)    * res;
            float2 wrs  = kaElevUV(m, r.pos.x + ch.wrist.x,    ch.wrist.y)    * res;
            float2 fla  = kaElevUV(m, r.pos.x + ch.flange.x,   ch.flange.y)   * res;

            // reach envelope: the arc of air this machine owns, drawn under everything
            float rr = kaLenX(m, sp.l2 + sp.l3 + sp.l4) * res.x;
            col = lerp(col, PT_GRID * 2.1, dashRingAA(P, shd, rr, 0.6, 44.0) * 0.7);

            float pw = max(kaLenX(m, sp.ped_r) * res.x, 2.2);
            float ph = max(kaLenY(m, r.size.y + sp.ped_h) * res.y, 2.0);
            float g = (ilSdBox(P, float4(base.x - pw, base.y - ph, base.x + pw, base.y), 0.0) <= 0.0) ? 0.55 : 0.0;
            g = max(g, strokeAA(ilSdSeg(P, base - float2(0, ph * 0.9), shd), max(pw * 0.55, 1.6)) * 0.55);
            // Flat-ended members between DRAWN joints: that is what makes a machine legible at
            // forty pixels instead of reading as one melted mass.
            float limb = max(kaLenX(m, sp.ped_r * 0.42) * res.x, 1.3);
            g = max(g, strokeAA(ilSdSeg(P, shd, elb), limb));
            g = max(g, strokeAA(ilSdSeg(P, elb, wrs), limb * 0.82));
            g = max(g, strokeAA(ilSdSeg(P, wrs, fla), limb * 0.62));
            col = lerp(col, body, g);

            col = lerp(col, body * 1.35, ringAA(P, shd, limb * 1.5, 0.9));
            col = lerp(col, body * 1.35, ringAA(P, elb, limb * 1.25, 0.85));
            col = lerp(col, body * 1.35, discAA(P, wrs, limb * 0.85));
            col = lerp(col, ptId((int)r.grp), discAA(P, fla, limb * 0.72));

            if (isSel) col = lerp(col, PT_ACCENT, ringAA(P, shd, limb * 2.6, 1.0) * 0.8);
        }

        // the target, at its true height above the floor with a plumb line down to it
        {
            KaRec t = Cell[KA_TARGET];
            float3 tp = ka_targetPos(t);
            float2 te = kaElevUV(m, tp.x, tp.y) * res;
            float2 tf = kaElevUV(m, tp.x, 0.0) * res;
            bool tsel = ((uint)t.flags & KF_SELECTED) != 0u;
            float3 tc = tsel ? PT_ACCENT : PT_INK;
            float plumb = strokeAA(ilSdSeg(P, te, tf), 0.5) * step(frac((P.y - te.y) * 0.12), 0.5);
            col = lerp(col, PT_RULE * 1.1, plumb * 0.8);
            col = lerp(col, tc, ringAA(P, te, 7.0, 1.0));
            col = lerp(col, tc, discAA(P, te, 2.1));
            col = lerp(col, tc, strokeAA(ilSdSeg(P, te - float2(13, 0), te - float2(9, 0)), 0.8));
            col = lerp(col, tc, strokeAA(ilSdSeg(P, te + float2(9, 0), te + float2(13, 0)), 0.8));
        }

        // the floor, drawn last so nothing stands under it; below it is ground
        float fy = m.elevY * res.y;
        col = lerp(col, PT_RULE * 1.35, strokeAA(abs(P.y - fy), 1.0));
        col = lerp(col, IL_FIELD, step(fy + 1.5, P.y));
        ilOver(outCol, col, ilFill(dElev));
    }

    OutputUAV[pixel] = float4(outCol, 1.0);
}
