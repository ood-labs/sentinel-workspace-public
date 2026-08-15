// KA_Cell / canvas.hlsl — the editor surface.
//
// A draughtsman's PLAN over an ELEVATION of the robot cell, sharing the world X axis and one
// metres-per-pixel scale, with an INSPECTOR column carrying the live numbers for whatever is
// selected. Reading it should answer, without opening the renderer: where does every machine
// stand, which way does it face, how big a frame is it, which control channel drives it, how
// tall does it stand, how far can it reach — and, critically, CAN ANY TWO OF THEM HIT EACH
// OTHER.
//
// That last one is the failure the render cannot show you until it happens, so it is drawn:
// every point of floor that two work envelopes can both reach is shaded alarm red.
//
// Instrument palette (plan_theme.hlsli): mostly monochrome. Hue is spent on exactly three
// things — the accent for the selection, alarm for a broken cell, and the four-member identity
// set for the control channels, which is a closed unordered set the eye must separate at a
// glance. Frame size is ORDINAL, so it is a value ramp, not a hue.
#include "../_shared/cell.hlsli"
#include "../_shared/plan_theme.hlsli"
#include "../_shared/microfont.hlsli"
#include "../_shared/glyphs.hlsli"
#include "layout.hlsli"

StructuredBuffer<KaRec> Cell : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

// ---------------------------------------------------------------------------
// pixel-space drawing primitives
// ---------------------------------------------------------------------------
float segD(float2 p, float2 a, float2 b)
{
    float2 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * h);
}
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
float boxEdgeAA(float2 p, float2 lo, float2 hi, float w)
{
    float2 q = max(lo - p, p - hi);
    return strokeAA(abs(length(max(q, 0.0)) + min(max(q.x, q.y), 0.0)), w);
}
float boxFill(float2 p, float2 lo, float2 hi)
{
    return (p.x >= lo.x && p.x <= hi.x && p.y >= lo.y && p.y <= hi.y) ? 1.0 : 0.0;
}

// text: `h` is glyph height in pixels, `org` the top-left pixel of the string
float txtAt(float2 p, float2 org, float h, uint2 packed, uint count)
{
    float cw = h * (5.0 / 7.0) * 1.2;
    return mf_text((p - org) / float2(cw * (float)count, h), packed, count);
}
float numAt(float2 p, float2 org, float h, uint v, uint digits)
{
    float cw = h * (5.0 / 7.0) * 1.2;
    return mf_num((p - org) / float2(cw * (float)digits, h), v, digits);
}
float txtW(float h, uint count) { return h * (5.0 / 7.0) * 1.2 * (float)count; }

// signed integer, one leading sign cell
float sintAt(float2 p, float2 org, float h, float v, uint digits)
{
    float cw = txtW(h, 1u);
    float g = (v < -0.5) ? txtAt(p, org, h, uint2(MF_DASH, 0u), 1u) : 0.0;
    return max(g, numAt(p, float2(org.x + cw, org.y), h, (uint)min(abs(v), 99999.0), digits));
}
// signed value with one decimal place — every readout on this canvas is a real live quantity,
// and rounding metres to integers would make a 0.4 m nudge look like nothing happened
float dec1At(float2 p, float2 org, float h, float v, uint intDigits)
{
    float cw = txtW(h, 1u);
    float x = org.x;
    float g = (v < 0.0) ? txtAt(p, float2(x, org.y), h, uint2(MF_DASH, 0u), 1u) : 0.0;
    x += cw;
    // Round to tenths ONCE and split, rather than truncating the whole part and the fraction
    // independently — 2.6 truncates its fraction to 5 and the readout quietly lies.
    uint tenths = (uint)min(abs(v) * 10.0 + 0.5, 99999.0);
    g = max(g, numAt(p, float2(x, org.y), h, tenths / 10u, intDigits));
    x += cw * (float)intDigits;
    g = max(g, txtAt(p, float2(x, org.y), h, uint2(MF_DOT, 0u), 1u));
    x += cw;
    return max(g, numAt(p, float2(x, org.y), h, tenths % 10u, 1u));
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

    KaRec hdr = Cell[KA_HEADER];
    float sel     = hdr.pos.y;
    float liveN   = hdr.grp;
    float clashN  = hdr.kind;
    float cw      = max(hdr.bias, 0.5);
    float cd      = max(hdr.flags, 0.5);
    float salt    = hdr.seed;
    float maxRise = max(hdr.spare, 0.5);

    // Same map the state pass picked with — _Resolution, not GetDimensions, for exactly that
    // reason. This module is fixed-resolution so the two agree; if it ever becomes follow_panel
    // both must change together.
    KaMap m = kaMap(_Resolution.xy, cw, cd, maxRise);

    float3 col = PT_FIELD;

    float2 planLo = float2(KA_X0, KA_PY0) * res, planHi = float2(KA_X1, KA_PY1) * res;
    float2 elevLo = float2(KA_X0, KA_EY0) * res, elevHi = float2(KA_X1, KA_EY1) * res;
    float2 insLo  = float2(KA_IX0, KA_IY0) * res, insHi = float2(KA_IX1, KA_IY1) * res;

    bool inPlan = boxFill(P, planLo, planHi) > 0.5;
    bool inElev = boxFill(P, elevLo, elevHi) > 0.5;
    bool inIns  = boxFill(P, insLo, insHi) > 0.5;

    col = lerp(col, PT_WELL, inPlan ? 1.0 : 0.0);
    col = lerp(col, PT_WELL, inElev ? 1.0 : 0.0);
    col = lerp(col, PT_WELL * 0.72, inIns ? 1.0 : 0.0);

    // ================= plan strip =================
    if (inPlan)
    {
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
                arm = max(arm, strokeAA(segD(P, kaPlanUV(m, prev) * res, spx), 1.15));
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
            float head = strokeAA(segD(P, c + dir * pr * 0.6, tip), 1.35);
            head = max(head, strokeAA(segD(P, tip, tip - dir * 5.5 + nrm * 3.6), 1.0));
            head = max(head, strokeAA(segD(P, tip, tip - dir * 5.5 - nrm * 3.6), 1.0));
            col = lerp(col, ptId((int)r.grp), head);

            if ((fl & KF_EDITED) != 0u)
                col = lerp(col, PT_INK, ringAA(P, c, pr * 1.55, 0.7) * 0.75);
            if ((fl & KF_OUTSIDE) != 0u)
                col = lerp(col, PT_ALARM, ringAA(P, c, pr * 1.30, 1.1));
            if ((fl & KF_SELECTED) != 0u)
            {
                col = lerp(col, PT_ACCENT, ringAA(P, c, pr * 1.9, 1.2));
                col = lerp(col, PT_ACCENT, strokeAA(segD(P, c - float2(pr * 3.2, 0), c - float2(pr * 2.2, 0)), 0.9));
                col = lerp(col, PT_ACCENT, strokeAA(segD(P, c + float2(pr * 2.2, 0), c + float2(pr * 3.2, 0)), 0.9));
                col = lerp(col, PT_ACCENT, strokeAA(segD(P, c - float2(0, pr * 3.2), c - float2(0, pr * 2.2)), 0.9));
                col = lerp(col, PT_ACCENT, strokeAA(segD(P, c + float2(0, pr * 2.2), c + float2(0, pr * 3.2)), 0.9));
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
            col = lerp(col, PT_RULE * 1.0, strokeAA(segD(P, ac, lc), 0.55) * hasOrb * 0.6);

            col = lerp(col, tc, ringAA(P, lc, 8.0, 1.1));
            col = lerp(col, tc, discAA(P, lc, 2.3));
            col = lerp(col, tc, strokeAA(segD(P, lc - float2(15, 0), lc - float2(10, 0)), 0.9));
            col = lerp(col, tc, strokeAA(segD(P, lc + float2(10, 0), lc + float2(15, 0)), 0.9));
            col = lerp(col, tc, strokeAA(segD(P, lc - float2(0, 15), lc - float2(0, 10)), 0.9));
            col = lerp(col, tc, strokeAA(segD(P, lc + float2(0, 10), lc + float2(0, 15)), 0.9));
        }
    }

    // ================= elevation strip =================
    if (inElev)
    {
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
            float g = boxFill(P, float2(base.x - pw, base.y - ph), float2(base.x + pw, base.y)) * 0.55;
            g = max(g, strokeAA(segD(P, base - float2(0, ph * 0.9), shd), max(pw * 0.55, 1.6)) * 0.55);
            // Flat-ended members between DRAWN joints: that is what makes a machine legible at
            // forty pixels instead of reading as one melted mass.
            float limb = max(kaLenX(m, sp.ped_r * 0.42) * res.x, 1.3);
            g = max(g, strokeAA(segD(P, shd, elb), limb));
            g = max(g, strokeAA(segD(P, elb, wrs), limb * 0.82));
            g = max(g, strokeAA(segD(P, wrs, fla), limb * 0.62));
            col = lerp(col, body, g);

            col = lerp(col, body * 1.35, ringAA(P, shd, limb * 1.5, 0.9));
            col = lerp(col, body * 1.35, ringAA(P, elb, limb * 1.25, 0.85));
            col = lerp(col, body * 1.35, discAA(P, wrs, limb * 0.85));
            col = lerp(col, ptId((int)r.grp), discAA(P, fla, limb * 0.72));

            if (isSel) col = lerp(col, PT_ACCENT, ringAA(P, shd, limb * 2.6, 1.0) * 0.8);
        }

        // height ruler, inside the left edge
        for (uint k = 1u; k < 9u; k++)
        {
            float ty = kaElevUV(m, 0.0, (float)k).y * res.y;
            if (ty < elevLo.y + 6.0) continue;
            float tk = strokeAA(segD(P, float2(elevLo.x + 3.0, ty), float2(elevLo.x + 9.0, ty)), 0.6);
            col = lerp(col, PT_RULE, tk);
            col = lerp(col, PT_RULE, numAt(P, float2(elevLo.x + 12.0, ty - 3.5), 7.0, k, 1u) * 0.9);
        }

        // the target, at its true height above the floor with a plumb line down to it
        {
            KaRec t = Cell[KA_TARGET];
            float3 tp = ka_targetPos(t);
            float2 te = kaElevUV(m, tp.x, tp.y) * res;
            float2 tf = kaElevUV(m, tp.x, 0.0) * res;
            bool tsel = ((uint)t.flags & KF_SELECTED) != 0u;
            float3 tc = tsel ? PT_ACCENT : PT_INK;
            float plumb = strokeAA(segD(P, te, tf), 0.5) * step(frac((P.y - te.y) * 0.12), 0.5);
            col = lerp(col, PT_RULE * 1.1, plumb * 0.8);
            col = lerp(col, tc, ringAA(P, te, 7.0, 1.0));
            col = lerp(col, tc, discAA(P, te, 2.1));
            col = lerp(col, tc, strokeAA(segD(P, te - float2(13, 0), te - float2(9, 0)), 0.8));
            col = lerp(col, tc, strokeAA(segD(P, te + float2(9, 0), te + float2(13, 0)), 0.8));
        }

        // the floor, drawn last so nothing stands under it
        float fy = m.elevY * res.y;
        col = lerp(col, PT_RULE * 1.35, strokeAA(abs(P.y - fy), 1.0));
        col = lerp(col, PT_FIELD, step(fy + 1.5, P.y));
    }

    // ================= inspector column =================
    if (inIns)
    {
        float h = 9.0;
        float lh = 13.0;
        float x0 = insLo.x + 9.0;
        float xv = insLo.x + 9.0 + txtW(h, 5u);      // value column
        float y = insLo.y + 10.0;

        uint si = (uint)max(sel - 1.0, 0.0);
        bool isTgt = (sel > 0.5) && (si == KA_TARGET);
        bool has = (sel > 0.5) && !isTgt;
        KaRec sr = Cell[min(si, KA_RECORDS - 1u)];
        KaSpec ss = ka_spec(sr.kind, sr.size.x);

        // --- header: what is selected
        col = lerp(col, (has || isTgt) ? PT_ACCENT : PT_RULE,
                   txtAt(P, float2(x0, y), h,
                         isTgt ? uint2(mf_pack1(LT, LG, LT, 0u, 0u), 0u)
                               : uint2(mf_pack1(LA, LR, LM, 0u, 0u), 0u), 3u));
        if (has)
            col = lerp(col, PT_ACCENT, numAt(P, float2(x0 + txtW(h, 4u), y), h, si - KA_ARM_0, 2u));
        else if (!isTgt)
            col = lerp(col, PT_RULE, txtAt(P, float2(x0 + txtW(h, 4u), y), h,
                                           uint2(mf_pack1(LN, LO, LN, LE, 0u), 0u), 4u));
        y += lh + 4.0;
        col = lerp(col, PT_RULE * 0.7, strokeAA(abs(P.y - y + 5.0), 0.5) * (P.x > insLo.x + 6.0 && P.x < insHi.x - 6.0 ? 1.0 : 0.0));

        float3 vc = PT_INK;
        // With nothing selected the value column shows a dash rather than 0.0 — a zero is a
        // real reading and would say "there is an arm standing at the origin".
        float2 dashOrg = float2(xv + txtW(h, 1u), y);
        // X
        col = lerp(col, PT_DIM, txtAt(P, float2(x0, y), h, uint2(mf_pack1(LX, 0u, 0u, 0u, 0u), 0u), 1u));
        if (has) col = lerp(col, vc, dec1At(P, float2(xv, y), h, sr.pos.x, 2u));
        else     col = lerp(col, PT_RULE, txtAt(P, float2(xv + txtW(h, 1u), y), h, uint2(MF_DASH, 0u), 1u));
        y += lh;
        // Z
        col = lerp(col, PT_DIM, txtAt(P, float2(x0, y), h, uint2(mf_pack1(LZ, 0u, 0u, 0u, 0u), 0u), 1u));
        if (has) col = lerp(col, vc, dec1At(P, float2(xv, y), h, sr.pos.y, 2u));
        else     col = lerp(col, PT_RULE, txtAt(P, float2(xv + txtW(h, 1u), y), h, uint2(MF_DASH, 0u), 1u));
        y += lh;
        // YAW, degrees
        col = lerp(col, PT_DIM, txtAt(P, float2(x0, y), h, uint2(mf_pack1(LY, LA, LW, 0u, 0u), 0u), 3u));
        if (has) col = lerp(col, vc, sintAt(P, float2(xv, y), h, degrees(atan2(sin(sr.yaw), cos(sr.yaw))), 3u));
        else     col = lerp(col, PT_RULE, txtAt(P, float2(xv + txtW(h, 1u), y), h, uint2(MF_DASH, 0u), 1u));
        y += lh;
        // REACH
        col = lerp(col, PT_DIM, txtAt(P, float2(x0, y), h, uint2(mf_pack1(LR, LC, LH, 0u, 0u), 0u), 3u));
        if (has) col = lerp(col, vc, dec1At(P, float2(xv, y), h, ka_reach(ss), 1u));
        else     col = lerp(col, PT_RULE, txtAt(P, float2(xv + txtW(h, 1u), y), h, uint2(MF_DASH, 0u), 1u));
        y += lh;
        // RISE
        col = lerp(col, PT_DIM, txtAt(P, float2(x0, y), h, uint2(mf_pack1(LR, LI, LS, LE, 0u), 0u), 4u));
        if (has) col = lerp(col, vc, dec1At(P, float2(xv, y), h, ka_rise(ss, sr.size.y), 1u));
        else     col = lerp(col, PT_RULE, txtAt(P, float2(xv + txtW(h, 1u), y), h, uint2(MF_DASH, 0u), 1u));
        y += lh;
        // FRAME name
        col = lerp(col, PT_DIM, txtAt(P, float2(x0, y), h, uint2(mf_pack1(LF, LR, LM, 0u, 0u), 0u), 3u));
        if (has)
        {
            uint kk = (uint)clamp(sr.kind, 0.0, 2.0);
            uint2 fn = uint2(mf_pack1(LS, LT, LD, 0u, 0u), 0u);
            if (kk == 0u) fn = uint2(mf_pack1(LC, LM, LP, 0u, 0u), 0u);
            if (kk == 2u) fn = uint2(mf_pack1(LH, LV, LY, 0u, 0u), 0u);
            col = lerp(col, ptRamp(0.30 + sr.kind * 0.35), txtAt(P, float2(xv, y), h, fn, 3u));
        }
        else col = lerp(col, PT_RULE, txtAt(P, float2(xv + txtW(h, 1u), y), h, uint2(MF_DASH, 0u), 1u));
        y += lh;
        // SCALE
        col = lerp(col, PT_DIM, txtAt(P, float2(x0, y), h, uint2(mf_pack1(LS, LC, LL, 0u, 0u), 0u), 3u));
        if (has) col = lerp(col, vc, dec1At(P, float2(xv, y), h, sr.size.x, 1u));
        else     col = lerp(col, PT_RULE, txtAt(P, float2(xv + txtW(h, 1u), y), h, uint2(MF_DASH, 0u), 1u));
        y += lh;
        // PEDESTAL
        col = lerp(col, PT_DIM, txtAt(P, float2(x0, y), h, uint2(mf_pack1(LP, LE, LD, 0u, 0u), 0u), 3u));
        if (has) col = lerp(col, vc, dec1At(P, float2(xv, y), h, sr.size.y, 1u));
        else     col = lerp(col, PT_RULE, txtAt(P, float2(xv + txtW(h, 1u), y), h, uint2(MF_DASH, 0u), 1u));
        y += lh;
        // CHANNEL
        col = lerp(col, PT_DIM, txtAt(P, float2(x0, y), h, uint2(mf_pack1(LC, LH, LN, 0u, 0u), 0u), 3u));
        if (has)
        {
            col = lerp(col, ptId((int)sr.grp), boxFill(P, float2(xv, y), float2(xv + 7.0, y + 7.0)));
            col = lerp(col, ptId((int)sr.grp), numAt(P, float2(xv + 12.0, y), h, (uint)sr.grp, 1u));
        }
        y += lh;
        // PHASE BIAS
        col = lerp(col, PT_DIM, txtAt(P, float2(x0, y), h, uint2(mf_pack1(LB, LI, LA, LS, 0u), 0u), 4u));
        if (has) col = lerp(col, vc, dec1At(P, float2(xv, y), h, sr.bias, 1u));
        else     col = lerp(col, PT_RULE, txtAt(P, float2(xv + txtW(h, 1u), y), h, uint2(MF_DASH, 0u), 1u));
        y += lh + 3.0;

        // state flags for the selected arm — value for "hand edited", alarm for "broken"
        if (has)
        {
            uint fl = (uint)sr.flags;
            float fx = x0;
            if ((fl & KF_EDITED) != 0u)
            {
                col = lerp(col, PT_INK, txtAt(P, float2(fx, y), h, uint2(mf_pack1(LE, LD, LI, LT, 0u), 0u), 4u));
                fx += txtW(h, 5u);
            }
            if ((fl & KF_OVERLAP) != 0u)
            {
                col = lerp(col, PT_ALARM, txtAt(P, float2(fx, y), h, uint2(mf_pack1(LC, LL, LS, LH, 0u), 0u), 4u));
                fx += txtW(h, 5u);
            }
            if ((fl & KF_OUTSIDE) != 0u)
                col = lerp(col, PT_ALARM, txtAt(P, float2(fx, y), h, uint2(mf_pack1(LO, LU, LT, 0u, 0u), 0u), 3u));
        }
        y += lh + 8.0;
        col = lerp(col, PT_RULE * 0.7, strokeAA(abs(P.y - y + 6.0), 0.5) * (P.x > insLo.x + 6.0 && P.x < insHi.x - 6.0 ? 1.0 : 0.0));

        // --- channel legend, with live counts
        col = lerp(col, PT_DIM, txtAt(P, float2(x0, y), h, uint2(mf_pack1(LC, LH, LA, LN, 0u), 0u), 4u));
        y += lh + 2.0;
        for (uint c = 0u; c < 4u; c++)
        {
            uint cnt = 0u;
            for (uint i2 = 0u; i2 < KA_MAX_ARMS; i2++)
            {
                KaRec r2 = Cell[KA_ARM_0 + i2];
                if (r2.active > 0.5 && (uint)r2.grp == c) cnt++;
            }
            bool used = c < (uint)max((float)group_count, 1.0);
            float3 sw = used ? ptId((int)c) : PT_RULE * 0.55;
            col = lerp(col, sw, boxFill(P, float2(x0, y), float2(x0 + 7.0, y + 7.0)));
            col = lerp(col, used ? PT_DIM : PT_RULE * 0.6,
                       txtAt(P, float2(x0 + 12.0, y), h, uint2(mf_pack1(LC, LH, c, 0u, 0u), 0u), 3u));
            col = lerp(col, used ? PT_INK : PT_RULE * 0.6,
                       numAt(P, float2(xv, y), h, cnt, 2u));
            y += lh - 1.0;
        }
        y += 8.0;
        col = lerp(col, PT_RULE * 0.7, strokeAA(abs(P.y - y + 6.0), 0.5) * (P.x > insLo.x + 6.0 && P.x < insHi.x - 6.0 ? 1.0 : 0.0));

        // --- frame legend, ordinal ramp with counts
        col = lerp(col, PT_DIM, txtAt(P, float2(x0, y), h, uint2(mf_pack1(LF, LR, LM, LS, 0u), 0u), 4u));
        y += lh + 2.0;
        for (uint fk = 0u; fk < 3u; fk++)
        {
            uint cnt = 0u;
            for (uint i3 = 0u; i3 < KA_MAX_ARMS; i3++)
            {
                KaRec r3 = Cell[KA_ARM_0 + i3];
                if (r3.active > 0.5 && (uint)r3.kind == fk) cnt++;
            }
            float3 sw = ptRamp(0.30 + (float)fk * 0.35);
            col = lerp(col, sw, boxFill(P, float2(x0, y), float2(x0 + 7.0, y + 7.0)));
            uint2 fn = uint2(mf_pack1(LS, LT, LD, 0u, 0u), 0u);
            if (fk == 0u) fn = uint2(mf_pack1(LC, LM, LP, 0u, 0u), 0u);
            if (fk == 2u) fn = uint2(mf_pack1(LH, LV, LY, 0u, 0u), 0u);
            col = lerp(col, PT_DIM, txtAt(P, float2(x0 + 12.0, y), h, fn, 3u));
            col = lerp(col, PT_INK, numAt(P, float2(xv, y), h, cnt, 2u));
            y += lh - 1.0;
        }
        y += 8.0;
        col = lerp(col, PT_RULE * 0.7, strokeAA(abs(P.y - y + 6.0), 0.5) * (P.x > insLo.x + 6.0 && P.x < insHi.x - 6.0 ? 1.0 : 0.0));

        // --- the target, always live: this is the place every Point At arm is aiming, and its
        // x/z are the ORBITING values, not the anchor, so the numbers move when the mark moves
        {
            KaRec t = Cell[KA_TARGET];
            float3 tp = ka_targetPos(t);
            bool tsel = ((uint)t.flags & KF_SELECTED) != 0u;
            float3 tc = tsel ? PT_ACCENT : PT_INK;
            col = lerp(col, tsel ? PT_ACCENT : PT_DIM,
                       txtAt(P, float2(x0, y), h, uint2(mf_pack1(LT, LG, LT, 0u, 0u), 0u), 3u));
            y += lh + 2.0;
            col = lerp(col, PT_DIM, txtAt(P, float2(x0, y), h, uint2(mf_pack1(LX, 0u, 0u, 0u, 0u), 0u), 1u));
            col = lerp(col, tc, dec1At(P, float2(xv, y), h, tp.x, 2u)); y += lh;
            col = lerp(col, PT_DIM, txtAt(P, float2(x0, y), h, uint2(mf_pack1(LZ, 0u, 0u, 0u, 0u), 0u), 1u));
            col = lerp(col, tc, dec1At(P, float2(xv, y), h, tp.z, 2u)); y += lh;
            col = lerp(col, PT_DIM, txtAt(P, float2(x0, y), h, uint2(mf_pack1(LH, LG, LT, 0u, 0u), 0u), 3u));
            col = lerp(col, tc, dec1At(P, float2(xv, y), h, tp.y, 2u)); y += lh;
            col = lerp(col, PT_DIM, txtAt(P, float2(x0, y), h, uint2(mf_pack1(LO, LR, LB, 0u, 0u), 0u), 3u));
            col = lerp(col, tc, dec1At(P, float2(xv, y), h, t.size.y, 2u)); y += lh + 8.0;
            col = lerp(col, PT_RULE * 0.7, strokeAA(abs(P.y - y + 6.0), 0.5) * (P.x > insLo.x + 6.0 && P.x < insHi.x - 6.0 ? 1.0 : 0.0));
        }

        // --- cell totals
        col = lerp(col, PT_DIM, txtAt(P, float2(x0, y), h, uint2(mf_pack1(LA, LR, LM, LS, 0u), 0u), 4u));
        col = lerp(col, PT_INK, numAt(P, float2(xv, y), h, (uint)liveN, 2u)); y += lh;
        col = lerp(col, (clashN > 0.5) ? PT_ALARM : PT_DIM,
                   txtAt(P, float2(x0, y), h, uint2(mf_pack1(LC, LL, LS, LH, 0u), 0u), 4u));
        col = lerp(col, (clashN > 0.5) ? PT_ALARM : PT_INK,
                   numAt(P, float2(xv, y), h, (uint)clashN, 2u)); y += lh;
        col = lerp(col, PT_DIM, txtAt(P, float2(x0, y), h, uint2(mf_pack1(LC, LE, LL, LL, 0u), 0u), 4u));
        {
            float gg = numAt(P, float2(xv, y), h, (uint)(cw + 0.5), 2u);
            gg = max(gg, txtAt(P, float2(xv + txtW(h, 2u), y), h, uint2(mf_pack1(LX, 0u, 0u, 0u, 0u), 0u), 1u));
            gg = max(gg, numAt(P, float2(xv + txtW(h, 3u), y), h, (uint)(cd + 0.5), 2u));
            col = lerp(col, PT_INK, gg);
        }
        y += lh;
        col = lerp(col, PT_DIM, txtAt(P, float2(x0, y), h, uint2(mf_pack1(LP, LI, LT, LC, LH), 0u), 5u));
        col = lerp(col, PT_INK, dec1At(P, float2(xv, y), h, pitch, 2u));
    }

    // ================= frames and title =================
    col = lerp(col, PT_RULE * 0.8, boxEdgeAA(P, planLo, planHi, 0.8));
    col = lerp(col, PT_RULE * 0.8, boxEdgeAA(P, elevLo, elevHi, 0.8));
    col = lerp(col, PT_RULE * 0.6, boxEdgeAA(P, insLo, insHi, 0.8));

    {
        float h = 11.0, y = 13.0, x = KA_X0 * res.x;
        float ink = txtAt(P, float2(x, y), h, uint2(mf_pack1(LK, LU, LK, LA, 0u), 0u), 4u);
        ink = max(ink, txtAt(P, float2(x + txtW(h, 5u), y), h, uint2(mf_pack1(LC, LE, LL, LL, 0u), 0u), 4u));
        col = lerp(col, PT_INK, ink);

        uint arrIdx = (uint)clamp((float)arrangement, 0.0, 5.0);
        uint2 an = uint2(mf_pack1(LL, LI, LN, LE, 0u), 0u); uint ac = 4u;
        if (arrIdx == 1u) { an = uint2(mf_pack1(LG, LR, LI, LD, 0u), 0u); ac = 4u; }
        if (arrIdx == 2u) { an = uint2(mf_pack1(LR, LI, LN, LG, 0u), 0u); ac = 4u; }
        if (arrIdx == 3u) { an = uint2(mf_pack1(LA, LR, LC, 0u, 0u), 0u); ac = 3u; }
        if (arrIdx == 4u) { an = uint2(mf_pack1(LT, LW, LI, LN, 0u), 0u); ac = 4u; }
        if (arrIdx == 5u) { an = uint2(mf_pack1(LS, LP, LU, LR, 0u), 0u); ac = 4u; }
        col = lerp(col, PT_DIM, txtAt(P, float2(x + txtW(h, 10u), y), h, an, ac));

        float h2 = 9.0;
        col = lerp(col, PT_DIM, txtAt(P, float2(KA_X0 * res.x + 3.0, KA_PY0 * res.y - 11.0), h2,
                                      uint2(mf_pack1(LP, LL, LA, LN, 0u), 0u), 4u));
        col = lerp(col, PT_DIM, txtAt(P, float2(KA_X0 * res.x + 3.0, KA_EY0 * res.y - 11.0), h2,
                                      uint2(mf_pack1(LE, LL, LE, LV, 0u), 0u), 4u));
        col = lerp(col, PT_DIM, txtAt(P, float2(KA_IX0 * res.x + 3.0, KA_IY0 * res.y - 11.0), h2,
                                      uint2(mf_pack1(LS, LE, LL, 0u, 0u), 0u), 3u));
    }

    OutputUAV[pixel] = float4(col, 1.0);
}
