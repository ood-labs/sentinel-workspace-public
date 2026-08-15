// KA_Pose / scope.hlsl — the choreography instrument.
//
// Deliberately NOT a second plan. The plan answers "where does everything stand"; this answers
// "what is every joint doing right now, on whose clock, and is anything about to break".
//
// It is shaped like a teach pendant because that is what a draughtsman would draw for a machine
// organised by JOINTS AND TIME rather than by floor space: four channel stations across the top
// carrying the live phase of each clock, a joint matrix of one row per machine by six columns
// per axis, and a tool-height strip along the bottom with the floor drawn on it.
//
// The failure modes live in the diagram: a joint sitting on its limit turns its bar red, and a
// tool that has gone through the floor drops into a red band below the floor line. Neither is
// visible in the render until it has already happened.
#include "../_shared/cell.hlsli"
#include "../_shared/plan_theme.hlsli"
#include "../_shared/microfont.hlsli"
#include "../_shared/glyphs.hlsli"

StructuredBuffer<KaPose> Pose  : register(t0);
StructuredBuffer<KaRec>  Cell  : register(t1);
StructuredBuffer<KaBall> Rally : register(t2);
RWTexture2D<float4> OutputUAV : register(u0);

#define SC_STAT_Y0   30.0
#define SC_STAT_Y1  124.0
#define SC_MAT_Y0   140.0
#define SC_MAT_Y1   524.0
#define SC_TOOL_Y0  538.0
#define SC_TOOL_Y1  622.0
#define SC_GUT_X0    16.0
#define SC_COL_X0    84.0
#define SC_COL_X1  1008.0

float segD(float2 p, float2 a, float2 b)
{
    float2 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return length(pa - ba * h);
}
float strokeAA(float d, float w) { return 1.0 - smoothstep(w - 0.7, w + 0.7, d); }
float discAA(float2 p, float2 c, float r) { return 1.0 - smoothstep(r - 0.8, r + 0.8, length(p - c)); }
float ringAA(float2 p, float2 c, float r, float w) { return strokeAA(abs(length(p - c) - r), w); }
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
float sintAt(float2 p, float2 org, float h, float v, uint digits)
{
    float cw = txtW(h, 1u);
    float g = (v < -0.5) ? txtAt(p, org, h, uint2(MF_DASH, 0u), 1u) : 0.0;
    return max(g, numAt(p, float2(org.x + cw, org.y), h, (uint)min(abs(v), 99999.0), digits));
}

void patName(int pat, out uint2 packed, out uint count)
{
    if (pat == 1)       { packed = uint2(mf_pack1(LW, LA, LV, LE, 0u), 0u); count = 4u; }
    else if (pat == 2)  { packed = uint2(mf_pack1(LR, LI, LP, LP, LL), 0u); count = 5u; }
    else if (pat == 3)  { packed = uint2(mf_pack1(LS, LP, LI, LR, LL), 0u); count = 5u; }
    else if (pat == 4)  { packed = uint2(mf_pack1(LC, LA, LN, LO, LN), 0u); count = 5u; }
    else if (pat == 5)  { packed = uint2(mf_pack1(LB, LR, LE, LT, LH), 0u); count = 5u; }
    else if (pat == 6)  { packed = uint2(mf_pack1(LA, LI, LM, 0u, 0u), 0u); count = 3u; }
    else if (pat == 7)  { packed = uint2(mf_pack1(LS, LC, LA, LN, 0u), 0u); count = 4u; }
    else if (pat == 8)  { packed = uint2(mf_pack1(LS, LW, LA, LY, 0u), 0u); count = 4u; }
    else if (pat == 9)  { packed = uint2(mf_pack1(LD, LR, LI, LF, LT), 0u); count = 5u; }
    else if (pat == 10) { packed = uint2(mf_pack1(LS, LA, LL, LU, LT), 0u); count = 5u; }
    else if (pat == 11) { packed = uint2(mf_pack1(LF, LO, LL, LD, 0u), 0u); count = 4u; }
    else                { packed = uint2(mf_pack1(LH, LO, LL, LD, 0u), 0u); count = 4u; }
}

float jointOf(KaPose p, uint c)
{
    if (c == 0u) return p.a1;
    if (c == 1u) return p.a2;
    if (c == 2u) return p.a3;
    if (c == 3u) return p.a4;
    if (c == 4u) return p.a5;
    return p.a6;
}
float homeOf(uint c)
{
    if (c == 0u) return KA_HOME_A1;
    if (c == 1u) return KA_HOME_A2;
    if (c == 2u) return KA_HOME_A3;
    if (c == 3u) return KA_HOME_A4;
    if (c == 4u) return KA_HOME_A5;
    return KA_HOME_A6;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    uint2 pixel = DTid.xy;
    if (pixel.x >= W || pixel.y >= H) return;
    float2 P = (float2)pixel + 0.5;

    KaPose hdr = Pose[KA_HEADER];
    float4 acc  = float4(hdr.tool.x, hdr.tool.y, hdr.tool.z, hdr.elbow.x);
    float liveN = hdr.elbow.y;
    float alarmN = hdr.elbow.z;
    float floorN = hdr.alarm;
    float limitN = hdr.live;
    float maxTool = max(hdr.a5, 1.0);
    int4 pats = int4((int)hdr.a1, (int)hdr.a2, (int)hdr.a3, (int)hdr.a4);
    float4 rates = float4(rate_a, rate_b, rate_c, rate_d);
    float4 amps  = float4(amp_a, amp_b, amp_c, amp_d);

    float3 col = PT_FIELD;

    // ================= title =================
    {
        float h = 11.0, y = 9.0, x = SC_GUT_X0;
        float ink = txtAt(P, float2(x, y), h, uint2(mf_pack1(LK, LU, LK, LA, 0u), 0u), 4u);
        ink = max(ink, txtAt(P, float2(x + txtW(h, 5u), y), h, uint2(mf_pack1(LP, LO, LS, LE, 0u), 0u), 4u));
        col = lerp(col, PT_INK, ink);

        float rx = SC_COL_X1;
        // LIMIT nn
        float g = 0.0;
        rx -= txtW(h, 3u); g = max(g, numAt(P, float2(rx, y), h, (uint)limitN, 2u));
        rx -= txtW(h, 6u); g = max(g, txtAt(P, float2(rx, y), h, uint2(mf_pack1(LL, LI, LM, LI, LT), 0u), 5u));
        col = lerp(col, (limitN > 0.5) ? PT_ALARM : PT_DIM, g);
        // FLOOR nn
        float g2 = 0.0;
        rx -= txtW(h, 3u); g2 = max(g2, numAt(P, float2(rx, y), h, (uint)floorN, 2u));
        rx -= txtW(h, 6u); g2 = max(g2, txtAt(P, float2(rx, y), h, uint2(mf_pack1(LF, LL, LO, LO, LR), 0u), 5u));
        col = lerp(col, (floorN > 0.5) ? PT_ALARM : PT_DIM, g2);
        // ARMS nn
        float g3 = 0.0;
        rx -= txtW(h, 3u); g3 = max(g3, numAt(P, float2(rx, y), h, (uint)liveN, 2u));
        rx -= txtW(h, 5u); g3 = max(g3, txtAt(P, float2(rx, y), h, uint2(mf_pack1(LA, LR, LM, LS, 0u), 0u), 4u));
        col = lerp(col, PT_DIM, g3);
    }

    // ================= channel stations =================
    {
        float bw = (SC_COL_X1 - SC_GUT_X0 - 3.0 * 8.0) * 0.25;
        for (uint c = 0u; c < 4u; c++)
        {
            float2 lo = float2(SC_GUT_X0 + (float)c * (bw + 8.0), SC_STAT_Y0);
            float2 hi = float2(lo.x + bw, SC_STAT_Y1);
            if (P.x < lo.x - 2.0 || P.x > hi.x + 2.0 || P.y < lo.y - 2.0 || P.y > hi.y + 2.0) continue;

            uint cnt = 0u;
            for (uint i = 0u; i < KA_MAX_ARMS; i++)
            {
                KaPose q = Pose[KA_ARM_0 + i];
                if (q.live > 0.5 && (uint)q.chan == c) cnt++;
            }
            bool used = cnt > 0u;
            float3 idc = used ? ptId((int)c) : PT_RULE * 0.55;

            col = lerp(col, PT_WELL, boxFill(P, lo, hi));
            col = lerp(col, PT_RULE * (used ? 0.9 : 0.5), boxEdgeAA(P, lo, hi, 0.8));

            float h = 10.0;
            col = lerp(col, idc, boxFill(P, lo + float2(9, 10), lo + float2(17, 18)));
            col = lerp(col, used ? PT_INK : PT_RULE * 0.7,
                       txtAt(P, lo + float2(22, 10), h, uint2(mf_pack1(LC, LH, c, 0u, 0u), 0u), 3u));
            uint2 pn; uint pc; patName(pats[c], pn, pc);
            col = lerp(col, used ? PT_MID : PT_RULE * 0.7, txtAt(P, lo + float2(22, 28), h, pn, pc));

            // arms on this channel
            float h2 = 9.0;
            col = lerp(col, PT_DIM, txtAt(P, lo + float2(9, 50), h2, uint2(mf_pack1(LA, LR, LM, LS, 0u), 0u), 4u));
            col = lerp(col, used ? PT_INK : PT_RULE * 0.7, numAt(P, lo + float2(9 + txtW(h2, 5u), 50), h2, cnt, 2u));
            // rate / amount
            col = lerp(col, PT_DIM, txtAt(P, lo + float2(9, 64), h2, uint2(mf_pack1(LR, LA, LT, LE, 0u), 0u), 4u));
            col = lerp(col, PT_MID, dec1At(P, lo + float2(9 + txtW(h2, 5u), 64), h2, rates[c], 1u));
            col = lerp(col, PT_DIM, txtAt(P, lo + float2(9, 78), h2, uint2(mf_pack1(LA, LM, LT, 0u, 0u), 0u), 3u));
            col = lerp(col, PT_MID, dec1At(P, lo + float2(9 + txtW(h2, 5u), 78), h2, amps[c] * master_amp, 1u));

            // PHASE WHEEL — an established live reading, which is the second thing the accent
            // is reserved for. A rotating hand is the only readout that shows at a glance
            // whether two channels are in step or drifting.
            float2 wc = float2(hi.x - 34.0, lo.y + 48.0);
            float wr = 26.0;
            col = lerp(col, PT_GRID * 2.2, ringAA(P, wc, wr, 0.8));
            for (uint tk = 0u; tk < 12u; tk++)
            {
                float a = (float)tk / 12.0 * KA_TAU;
                float2 d = float2(cos(a), sin(a));
                col = lerp(col, PT_RULE, strokeAA(segD(P, wc + d * (wr - 4.0), wc + d * wr), 0.55));
            }
            float ph = frac(acc[c] + phase);
            float2 hd = float2(cos(ph * KA_TAU - KA_PI * 0.5), sin(ph * KA_TAU - KA_PI * 0.5));
            col = lerp(col, used ? PT_ACCENT : PT_RULE, strokeAA(segD(P, wc, wc + hd * (wr - 3.0)), 1.1));
            col = lerp(col, used ? PT_ACCENT : PT_RULE, discAA(P, wc, 2.2));
        }
    }

    // ================= joint matrix =================
    float colW = (SC_COL_X1 - SC_COL_X0) / 6.0;
    {
        // column headers
        float h = 9.0;
        for (uint c = 0u; c < 6u; c++)
        {
            float cx = SC_COL_X0 + (float)c * colW;
            col = lerp(col, PT_DIM, txtAt(P, float2(cx + 6.0, SC_MAT_Y0 - 12.0), h,
                                          uint2(mf_pack1(LA, c + 1u, 0u, 0u, 0u), 0u), 2u));
            col = lerp(col, PT_RULE * 0.5, strokeAA(abs(P.x - cx), 0.5) *
                       ((P.y > SC_MAT_Y0 && P.y < SC_MAT_Y1) ? 1.0 : 0.0));
        }
        col = lerp(col, PT_DIM, txtAt(P, float2(SC_GUT_X0, SC_MAT_Y0 - 12.0), h,
                                      uint2(mf_pack1(LA, LR, LM, 0u, 0u), 0u), 3u));
        col = lerp(col, PT_RULE * 0.7, strokeAA(abs(P.y - SC_MAT_Y0 + 3.0), 0.5) *
                   ((P.x > SC_GUT_X0 && P.x < SC_COL_X1) ? 1.0 : 0.0));
    }

    if (P.y >= SC_MAT_Y0 && P.y <= SC_MAT_Y1 && P.x >= SC_GUT_X0 && P.x <= SC_COL_X1)
    {
        float n = max(liveN, 1.0);
        // Rows grow to fill when the cell is small and compress to 4 px when it is full. A fixed
        // small row wasted two thirds of the matrix at the counts people actually run.
        float rowH = clamp((SC_MAT_Y1 - SC_MAT_Y0) / n, 4.0, 26.0);
        int row = (int)floor((P.y - SC_MAT_Y0) / rowH);
        if (row >= 0 && (float)row < n)
        {
            // resolve the ordinal to a record index
            uint found = 0xFFFFFFFFu; uint ord = 0u;
            for (uint i = 0u; i < KA_MAX_ARMS; i++)
            {
                if (Pose[KA_ARM_0 + i].live > 0.5)
                {
                    if ((int)ord == row) { found = i; break; }
                    ord++;
                }
            }
            if (found != 0xFFFFFFFFu)
            {
                KaPose q = Pose[KA_ARM_0 + found];
                KaRec  r = Cell[KA_ARM_0 + found];
                bool isSel = ((uint)r.flags & KF_SELECTED) != 0u;
                float ry = SC_MAT_Y0 + (float)row * rowH;
                float cy = ry + rowH * 0.5;
                uint al = (uint)q.alarm;

                // zebra the rows so a 48-row matrix stays trackable across 900 pixels
                col = lerp(col, PT_WELL, ((row & 1) == 0) ? 0.55 : 0.0);
                if (isSel) col = lerp(col, PT_ACCENT * 0.16, 1.0);
                if ((al & KA_ALARM_FLOOR) != 0u) col = lerp(col, PT_ALARM * 0.22, 1.0);

                // gutter: identity swatch + index. An arm that has been taken over by the rally
                // is no longer running its channel pattern, so the matrix has to say so or the
                // reader will look for a pattern that is not driving it.
                float3 idc = ptId((int)q.chan);
                KaBall rb = Rally[KA_ARM_0 + found];
                if (rb.role == KA_ROLE_STRIKE || rb.role == KA_ROLE_RECEIVE) idc = PT_ACCENT;
                else if (rb.role != KA_ROLE_NONE) idc = lerp(idc, PT_INK, 0.45);
                col = lerp(col, idc, boxFill(P, float2(SC_GUT_X0, cy - 3.0), float2(SC_GUT_X0 + 6.0, cy + 3.0)));
                if (rowH >= 8.0)
                    col = lerp(col, isSel ? PT_ACCENT : PT_DIM,
                               numAt(P, float2(SC_GUT_X0 + 11.0, cy - 3.5), 7.0, found, 2u));

                // six joint bars
                int cIdx = (int)floor((P.x - SC_COL_X0) / colW);
                if (cIdx >= 0 && cIdx < 6)
                {
                    uint cu = (uint)cIdx;
                    float cx0 = SC_COL_X0 + (float)cIdx * colW + 7.0;
                    float cx1 = SC_COL_X0 + (float)(cIdx + 1) * colW - 7.0;
                    float2 lim = KA_LIM[cu];
                    float v = jointOf(q, cu);
                    float hm = homeOf(cu);
                    float tv = saturate((v - lim.x) / max(lim.y - lim.x, 1e-4));
                    float th = saturate((hm - lim.x) / max(lim.y - lim.x, 1e-4));
                    float xv = lerp(cx0, cx1, tv);
                    float xh = lerp(cx0, cx1, th);
                    float bh = max(rowH * 0.30, 1.6);

                    // At-limit is a per-joint fact, so it is tested per joint. A whole-arm flag
                    // would paint six bars red because one of them clipped.
                    bool atLim = (tv < 0.005) || (tv > 0.995);

                    col = lerp(col, PT_GRID * 1.7, strokeAA(abs(P.y - cy), 0.5) *
                               ((P.x >= cx0 && P.x <= cx1) ? 1.0 : 0.0));
                    col = lerp(col, PT_RULE * 0.9, strokeAA(segD(P, float2(cx0, cy - bh), float2(cx0, cy + bh)), 0.5));
                    col = lerp(col, PT_RULE * 0.9, strokeAA(segD(P, float2(cx1, cy - bh), float2(cx1, cy + bh)), 0.5));
                    col = lerp(col, PT_RULE * 0.75, strokeAA(segD(P, float2(xh, cy - bh * 0.7), float2(xh, cy + bh * 0.7)), 0.5));

                    float3 bc = atLim ? PT_ALARM : (isSel ? PT_ACCENT : PT_MID);
                    float bar = boxFill(P, float2(min(xh, xv), cy - bh), float2(max(xh, xv), cy + bh));
                    col = lerp(col, bc * 0.8, bar);
                    col = lerp(col, atLim ? PT_ALARM : PT_INK,
                               strokeAA(segD(P, float2(xv, cy - bh * 1.25), float2(xv, cy + bh * 1.25)), 0.8));
                }
            }
        }
    }

    // ================= tool height strip =================
    {
        float2 lo = float2(SC_GUT_X0, SC_TOOL_Y0), hi = float2(SC_COL_X1, SC_TOOL_Y1);
        if (P.x >= lo.x - 2.0 && P.x <= hi.x + 2.0 && P.y >= lo.y - 14.0 && P.y <= hi.y + 2.0)
        {
            col = lerp(col, PT_WELL, boxFill(P, lo, hi));
            float h = 9.0;
            col = lerp(col, PT_DIM, txtAt(P, float2(lo.x, lo.y - 12.0), h,
                                          uint2(mf_pack1(LT, LO, LO, LL, 0u), 0u), 4u));
            col = lerp(col, PT_DIM, txtAt(P, float2(lo.x + txtW(h, 5u), lo.y - 12.0), h,
                                          uint2(mf_pack1(LH, LG, LT, 0u, 0u), 0u), 3u));

            // The floor sits 12 px up from the bottom so there is somewhere for a tool that has
            // gone THROUGH it to be drawn. A violation you cannot plot is a violation you find
            // out about from the render.
            float fy = hi.y - 12.0;
            float top = lo.y + 8.0;
            float ppm = (fy - top) / max(maxTool * 1.10, 0.5);

            col = lerp(col, PT_ALARM * 0.16, boxFill(P, float2(lo.x, fy), hi));
            for (uint k = 1u; k < 10u; k++)
            {
                float ty = fy - (float)k * ppm;
                if (ty < top) continue;
                col = lerp(col, PT_GRID * 1.6, strokeAA(abs(P.y - ty), 0.5) *
                           ((P.x > lo.x && P.x < hi.x) ? 1.0 : 0.0));
            }

            float n = max(liveN, 1.0);
            uint ord = 0u;
            for (uint i = 0u; i < KA_MAX_ARMS; i++)
            {
                KaPose q = Pose[KA_ARM_0 + i];
                if (q.live < 0.5) continue;
                float px = lerp(lo.x + 10.0, hi.x - 10.0, (n > 1.0) ? ((float)ord / (n - 1.0)) : 0.5);
                ord++;
                float py = fy - q.tool.y * ppm;
                bool bad = ((uint)q.alarm & KA_ALARM_FLOOR) != 0u;
                float3 dc = bad ? PT_ALARM : ptId((int)q.chan);
                col = lerp(col, dc * 0.45, strokeAA(segD(P, float2(px, fy), float2(px, py)), 0.5));
                col = lerp(col, dc, discAA(P, float2(px, py), bad ? 3.2 : 2.4));
            }

            // the target height, as the line the AIM channel is trying to reach
            {
                KaRec t = Cell[KA_TARGET];
                float ty = fy - ka_targetPos(t).y * ppm;
                if (ty > top)
                    col = lerp(col, PT_INK * 0.85, strokeAA(abs(P.y - ty), 0.5) *
                               step(frac(P.x * 0.09), 0.5) * 0.9);
            }

            col = lerp(col, PT_RULE * 1.4, strokeAA(abs(P.y - fy), 0.9) *
                       ((P.x > lo.x && P.x < hi.x) ? 1.0 : 0.0));
            col = lerp(col, PT_RULE * 0.7, boxEdgeAA(P, lo, hi, 0.8));
        }
    }

    OutputUAV[pixel] = float4(col, 1.0);
}
