// KA_Rally / court.hlsl — the rally instrument.
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
#include "../_shared/cell.hlsli"
#include "../_shared/plan_theme.hlsli"
#include "../_shared/microfont.hlsli"
#include "../_shared/glyphs.hlsli"

StructuredBuffer<KaBall> Rally : register(t0);
StructuredBuffer<KaRec>  Cell  : register(t1);
RWTexture2D<float4> OutputUAV : register(u0);

#define CT_X0   0.030
#define CT_X1   0.700
#define CT_PY0  0.090
#define CT_PY1  0.790
#define CT_FY0  0.828
#define CT_FY1  0.960
#define CT_IX0  0.722
#define CT_IX1  0.972
#define CT_IY0  0.090
#define CT_IY1  0.960

float segD(float2 p, float2 a, float2 b)
{
    float2 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * h);
}
float strokeAA(float d, float w) { return 1.0 - smoothstep(w - 0.7, w + 0.7, d); }
float discAA(float2 p, float2 c, float r) { return 1.0 - smoothstep(r - 0.8, r + 0.8, length(p - c)); }
float ringAA(float2 p, float2 c, float r, float w) { return strokeAA(abs(length(p - c) - r), w); }
float dashRingAA(float2 p, float2 c, float r, float w, float dashes)
{
    float2 d = p - c;
    float a = atan2(d.y, d.x) / KA_TAU + 0.5;
    return ringAA(p, c, r, w) * step(frac(a * dashes), 0.5);
}
float boxFill(float2 p, float2 lo, float2 hi)
{
    return (p.x >= lo.x && p.x <= hi.x && p.y >= lo.y && p.y <= hi.y) ? 1.0 : 0.0;
}
float boxEdgeAA(float2 p, float2 lo, float2 hi, float w)
{
    float2 q = max(lo - p, p - hi);
    return strokeAA(abs(length(max(q, 0.0)) + min(max(q.x, q.y), 0.0)), w);
}
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
float dec1At(float2 p, float2 org, float h, float v, uint intDigits)
{
    float cw = txtW(h, 1u);
    float x = org.x;
    float g = (v < 0.0) ? txtAt(p, float2(x, org.y), h, uint2(MF_DASH, 0u), 1u) : 0.0;
    x += cw;
    uint tenths = (uint)min(abs(v) * 10.0 + 0.5, 99999.0);
    g = max(g, numAt(p, float2(x, org.y), h, tenths / 10u, intDigits));
    x += cw * (float)intDigits;
    g = max(g, txtAt(p, float2(x, org.y), h, uint2(MF_DOT, 0u), 1u));
    x += cw;
    return max(g, numAt(p, float2(x, org.y), h, tenths % 10u, 1u));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    uint2 pixel = DTid.xy;
    if (pixel.x >= W || pixel.y >= H) return;
    float2 res = float2(W, H);
    float2 P = (float2)pixel + 0.5;

    KaBall hdr = Rally[KA_HEADER];
    KaRec  chdr = Cell[KA_HEADER];
    float cw = max(chdr.bias, 4.0);
    float cd = max(chdr.flags, 4.0);
    int striker = (int)hdr.strikerIdx;
    int lastS = (int)hdr.lastIdx;
    bool dropped = hdr.dropFlag > 0.5;
    bool idle = hdr.role == KA_PLAY_IDLE;

    float3 col = PT_FIELD;

    float2 planLo = float2(CT_X0, CT_PY0) * res, planHi = float2(CT_X1, CT_PY1) * res;
    float2 flyLo  = float2(CT_X0, CT_FY0) * res, flyHi  = float2(CT_X1, CT_FY1) * res;
    float2 insLo  = float2(CT_IX0, CT_IY0) * res, insHi = float2(CT_IX1, CT_IY1) * res;

    bool inPlan = boxFill(P, planLo, planHi) > 0.5;
    bool inFly  = boxFill(P, flyLo, flyHi) > 0.5;
    bool inIns  = boxFill(P, insLo, insHi) > 0.5;
    col = lerp(col, PT_WELL, (inPlan || inFly) ? 1.0 : 0.0);
    col = lerp(col, PT_WELL * 0.72, inIns ? 1.0 : 0.0);

    // one isotropic scale for the court, so a reach circle is a circle
    float s = min((CT_X1 - CT_X0) * res.x / cw, (CT_PY1 - CT_PY0) * res.y / cd);
    float2 planC = float2((CT_X0 + CT_X1) * 0.5, (CT_PY0 + CT_PY1) * 0.5) * res;

    // ================= court plan =================
    if (inPlan)
    {
        float2 wp = (P - planC) / s;      // metres, y is world Z

        float2 g1 = abs(frac(wp + 0.5) - 0.5) * s;
        float2 g5 = abs(frac(wp / 5.0 + 0.5) - 0.5) * s * 5.0;
        col = lerp(col, PT_GRID, strokeAA(min(g1.x, g1.y), 0.55) * 0.85);
        col = lerp(col, PT_GRID * 1.9, strokeAA(min(g5.x, g5.y), 0.65));
        col = lerp(col, PT_RULE * 0.8,
                   boxEdgeAA(P, planC - float2(cw, cd) * 0.5 * s, planC + float2(cw, cd) * 0.5 * s, 0.9));

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

            float reach = ka_reachOf(r) * 0.88;
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
                    float d = segD(P, prev, q);
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
                float d = segD(P, a0, a1);
                col = lerp(col, PT_RULE * 1.25, strokeAA(d, 0.6) * step(frac(segD(P, a0, a0) * 0.0 + length(P - a0) * 0.08), 0.5) * 0.7);
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
                m = max(m, strokeAA(segD(P, pt - float2(13, 0), pt - float2(8, 0)), 0.9));
                m = max(m, strokeAA(segD(P, pt + float2(8, 0), pt + float2(13, 0)), 0.9));
                m = max(m, strokeAA(segD(P, pt - float2(0, 13), pt - float2(0, 8)), 0.9));
                m = max(m, strokeAA(segD(P, pt + float2(0, 8), pt + float2(0, 13)), 0.9));
                col = lerp(col, mk, m);
            }

            // ---- the ball, with its floor shadow ----
            float2 sp = planC + float2(hdr.pos.x, hdr.pos.z) * s;
            col = lerp(col, PT_FIELD, discAA(P, sp, max(hdr.radius * s, 2.0)) * 0.7);
            col = lerp(col, PT_INK, ringAA(P, sp, max(hdr.radius * s, 2.5), 1.2));
            col = lerp(col, PT_INK, discAA(P, sp, 2.0));
        }
    }

    // ================= flight profile =================
    if (inFly)
    {
        float t0 = flyLo.y, t1 = flyHi.y;
        float hmax = max(strike_h * 2.2, 4.0);
        float span = 4.0;                                    // seconds shown
        float px0 = flyLo.x + 26.0, px1 = flyHi.x - 8.0;
        float floorY = t1 - 9.0;
        float topY = t0 + 8.0;

        // height gridlines every metre, and the strike plane
        for (uint k = 1u; k < 9u; k++)
        {
            float hy = lerp(floorY, topY, (float)k / hmax);
            if (hy < topY) continue;
            col = lerp(col, PT_GRID * 1.7, strokeAA(abs(P.y - hy), 0.5));
        }
        float shY = lerp(floorY, topY, strike_h / hmax);
        col = lerp(col, PT_RULE * 1.2, strokeAA(abs(P.y - shY), 0.6) * step(frac(P.x * 0.10), 0.5));

        // the arc
        float2 prev = float2(0, 0); bool have = false;
        for (uint t = 0u; t < KA_TRAJ_N; t++)
        {
            KaBall sm = Rally[KA_TRAJ_0 + t];
            if (sm.role < 0.5) break;
            float2 q = float2(lerp(px0, px1, saturate(sm.radius / span)),
                              lerp(floorY, topY, saturate(sm.pos.y / hmax)));
            if (have) col = lerp(col, PT_MID, strokeAA(segD(P, prev, q), 1.0));
            prev = q; have = true;
        }

        // where it is now, and where it will be struck
        col = lerp(col, PT_INK, discAA(P, float2(px0, lerp(floorY, topY, saturate(hdr.pos.y / hmax))), 3.0));
        if (striker >= 0)
        {
            KaBall sa = Rally[KA_ARM_0 + (uint)striker];
            float2 cpt = float2(lerp(px0, px1, saturate(sa.radius / span)), shY);
            col = lerp(col, PT_ACCENT, ringAA(P, cpt, 5.5, 1.0));
            col = lerp(col, PT_ACCENT, strokeAA(segD(P, cpt - float2(0, 8), cpt + float2(0, 8)), 0.6) * 0.7);
        }
        else if (dropped)
        {
            col = lerp(col, PT_ALARM, strokeAA(abs(P.y - shY), 1.0) * 0.5);
        }

        col = lerp(col, PT_RULE * 1.35, strokeAA(abs(P.y - floorY), 0.9));
        col = lerp(col, PT_DIM, numAt(P, float2(flyLo.x + 5.0, shY - 3.5), 7.0, (uint)strike_h, 1u) * 0.9);
    }

    // ================= inspector =================
    if (inIns)
    {
        float h = 9.0, lh = 13.0;
        float x0 = insLo.x + 9.0;
        float xv = x0 + txtW(h, 6u);
        float y = insLo.y + 10.0;

        // play state
        uint2 st = uint2(mf_pack1(LI, LD, LL, LE, 0u), 0u); uint stc = 4u;
        float3 stc3 = PT_RULE;
        if (hdr.role == KA_PLAY_LIVE) { st = uint2(mf_pack1(LL, LI, LV, LE, 0u), 0u); stc = 4u; stc3 = PT_ACCENT; }
        if (hdr.role == KA_PLAY_DROP) { st = uint2(mf_pack1(LD, LR, LO, LP, 0u), 0u); stc = 4u; stc3 = PT_ALARM; }
        col = lerp(col, stc3, txtAt(P, float2(x0, y), h, st, stc));
        y += lh + 4.0;

        // the rally count, which is the score
        col = lerp(col, PT_DIM, txtAt(P, float2(x0, y), h, uint2(mf_pack1(LR, LA, LL, LL, LY), 0u), 5u));
        col = lerp(col, PT_INK, numAt(P, float2(xv, y), h, (uint)hdr.rallyCount, 3u)); y += lh;
        col = lerp(col, PT_DIM, txtAt(P, float2(x0, y), h, uint2(mf_pack1(LP, LL, LY, LR, LS), 0u), 5u));
        col = lerp(col, PT_INK, numAt(P, float2(xv, y), h, (uint)hdr.a2, 2u)); y += lh + 6.0;

        col = lerp(col, PT_DIM, txtAt(P, float2(x0, y), h, uint2(mf_pack1(LH, LG, LT, 0u, 0u), 0u), 3u));
        col = lerp(col, PT_MID, dec1At(P, float2(xv, y), h, hdr.pos.y, 2u)); y += lh;
        col = lerp(col, PT_DIM, txtAt(P, float2(x0, y), h, uint2(mf_pack1(LS, LP, LD, 0u, 0u), 0u), 3u));
        col = lerp(col, PT_MID, dec1At(P, float2(xv, y), h, length(hdr.vel), 2u)); y += lh + 6.0;

        // who is on it, and how long they have
        col = lerp(col, PT_DIM, txtAt(P, float2(x0, y), h, uint2(mf_pack1(LH, LI, LT, 0u, 0u), 0u), 3u));
        if (striker >= 0) col = lerp(col, PT_ACCENT, numAt(P, float2(xv, y), h, (uint)striker, 2u));
        else col = lerp(col, dropped ? PT_ALARM : PT_RULE, txtAt(P, float2(xv, y), h, uint2(MF_DASH, 0u), 1u));
        y += lh;
        col = lerp(col, PT_DIM, txtAt(P, float2(x0, y), h, uint2(mf_pack1(LI, LN, 0u, 0u, 0u), 0u), 2u));
        if (striker >= 0)
            col = lerp(col, PT_ACCENT, dec1At(P, float2(xv, y), h, Rally[KA_ARM_0 + (uint)striker].radius, 1u));
        else col = lerp(col, PT_RULE, txtAt(P, float2(xv, y), h, uint2(MF_DASH, 0u), 1u));
        y += lh;
        col = lerp(col, PT_DIM, txtAt(P, float2(x0, y), h, uint2(mf_pack1(LL, LA, LS, LT, 0u), 0u), 4u));
        if (lastS >= 0) col = lerp(col, PT_MID, numAt(P, float2(xv, y), h, (uint)lastS, 2u));
        else col = lerp(col, PT_RULE, txtAt(P, float2(xv, y), h, uint2(MF_DASH, 0u), 1u));
        y += lh + 8.0;

        if (dropped)
            col = lerp(col, PT_ALARM, txtAt(P, float2(x0, y), h,
                                            uint2(mf_pack1(LN, LO, 0u, 0u, 0u), 0u), 2u));
        if (dropped)
            col = lerp(col, PT_ALARM, txtAt(P, float2(x0 + txtW(h, 3u), y), h,
                                            uint2(mf_pack1(LR, LE, LA, LC, LH), 0u), 5u));
    }

    // ================= frames and title =================
    col = lerp(col, PT_RULE * 0.8, boxEdgeAA(P, planLo, planHi, 0.8));
    col = lerp(col, PT_RULE * 0.8, boxEdgeAA(P, flyLo, flyHi, 0.8));
    col = lerp(col, PT_RULE * 0.6, boxEdgeAA(P, insLo, insHi, 0.8));
    {
        float h = 11.0, y = 12.0, x = CT_X0 * res.x;
        float ink = txtAt(P, float2(x, y), h, uint2(mf_pack1(LK, LU, LK, LA, 0u), 0u), 4u);
        ink = max(ink, txtAt(P, float2(x + txtW(h, 5u), y), h, uint2(mf_pack1(LR, LA, LL, LL, LY), 0u), 5u));
        col = lerp(col, PT_INK, ink);
        float h2 = 9.0;
        col = lerp(col, PT_DIM, txtAt(P, float2(CT_X0 * res.x + 3.0, CT_PY0 * res.y - 11.0), h2,
                                      uint2(mf_pack1(LC, LO, LU, LR, LT), 0u), 5u));
        col = lerp(col, PT_DIM, txtAt(P, float2(CT_X0 * res.x + 3.0, CT_FY0 * res.y - 11.0), h2,
                                      uint2(mf_pack1(LF, LL, LI, LG, LH), 0u), 5u));
        col = lerp(col, PT_DIM, txtAt(P, float2(CT_IX0 * res.x + 3.0, CT_IY0 * res.y - 11.0), h2,
                                      uint2(mf_pack1(LP, LL, LA, LY, 0u), 0u), 4u));
    }

    OutputUAV[pixel] = float4(col, 1.0);
}
