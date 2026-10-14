// KA_Pose / layout.hlsl — the pose scope's stations, type, chrome and hover, recorded for the shared
// UI kit (ui.hlsl draws them over scope.hlsl's matrix and tool strip).
//
// The four channel stations are kit panes in full: each carries its identity swatch, the pattern it
// runs, its rate and amount, how many live arms it drives, and a phase wheel whose hand is the
// channel's own clock — an established live reading, so the hand takes the accent. Geometry comes
// from pose_frame.hlsli, the same function the drawing uses.
//
// HOVER is read from the pointer each cook and never stored. A matrix row or a tool stem is an arm:
// its row lifts, its stem is ringed, and a card lists its six joints against their limits, its tool
// height and its alarms. A station is a channel: its pane lifts and every arm it drives lifts with it.
#include "../_shared/cell.hlsli"
StructuredBuffer<KaPose> Pose  : register(t0);
StructuredBuffer<KaRec>  Cell  : register(t1);
StructuredBuffer<KaBall> Rally : register(t2);
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"
#include "../_shared/ka_ui.hlsli"
#include "pose_frame.hlsli"

static PoFrame g_F;

float jointOf(KaPose p, uint c)
{
    if (c == 0u) return p.a1;
    if (c == 1u) return p.a2;
    if (c == 2u) return p.a3;
    if (c == 3u) return p.a4;
    if (c == 4u) return p.a5;
    return p.a6;
}

// One channel station: a pane with the identity swatch and name in its header, the live arm count at
// the header's right, the pattern and its rate and amount in the body, the phase wheel at the right.
void station(uint c, uint cnt, int pat, float rate, float amt, float ph, bool hot)
{
    float s = g_F.s;
    float4 r = poStation(g_F, c);
    bool used = cnt > 0u;
    dlRectEdged(r, hot ? IL_RAISE : IL_PANEL, 1.0, IL_RADIUS * s, hot ? IL_RULE : IL_EDGE, 1.0);
    float4 body = r;
    float4 head = ilCutTop(body, ilSnap(IL_HEADER * s));
    dlHLine(head.w, head.x + 1.0, head.z - 1.0, IL_EDGE);
    float hy = ilMid(head).y;
    dlRect(float4(head.x + 10.0 * s, hy - 4.0 * s, head.x + 18.0 * s, hy + 4.0 * s), used ? ptId((int)c) : IL_RULE * 0.55, 1.0, 1.0);
    dlLabel(LB_CH_A + c, head.x + 25.0 * s, hy, IL_T_TITLE * s, used ? IL_INK : IL_DIM, IL_LEFT);
    float x = head.z - 10.0 * s;
    x -= dlLabel(LB_ARMS_U, x, hy, IL_T_CAP * s, IL_DIM, IL_RIGHT) + 4.0 * s;
    dlInt((int)cnt, 1, x, hy, IL_T_VALUE * s, used ? IL_INK : IL_RULE, IL_RIGHT);

    // the phase wheel: twelve o'clock is phase 0, clockwise. A rotating hand is the only readout that
    // shows at a glance whether two channels are in step or drifting. It gives way on a narrow pane.
    float bw = body.z - body.x;
    float wr = min(clamp(0.5 * (body.w - body.y) - 7.0 * s, 0.0, 26.0 * s), 0.5 * (bw - 136.0 * s));
    if (wr >= 9.0 * s)
    {
        float2 wc = float2(body.z - 10.0 * s - wr, ilMid(body).y);
        dlRing(wc, wr, 1.0, IL_EDGE * 1.4, 1.0);
        [loop] for (uint k = 0u; k < 12u; k++)
        {
            float a = (float)k / 12.0 * KA_TAU;
            float2 d = float2(cos(a), sin(a));
            dlLine(wc + d * (wr - 4.0 * s), wc + d * wr, 1.0, IL_RULE, 1.0);
        }
        float2 hd = float2(cos(ph * KA_TAU - KA_PI * 0.5), sin(ph * KA_TAU - KA_PI * 0.5));
        dlLine(wc, wc + hd * (wr - 3.0 * s), 2.0 * s, used ? IL_ACCENT : IL_RULE, 1.0);
        dlCircle(wc, 2.4 * s, used ? IL_ACCENT : IL_RULE, 1.0);
    }

    // what it runs, and how fast and how far
    float bx = body.x + 10.0 * s;
    float y0 = body.y + 15.0 * s;
    dlLabel(LB_PAT_HOLD + (uint)clamp(pat, 0, 11), bx, y0, 14.0 * s, used ? IL_INK : IL_DIM, IL_LEFT);
    float xv = bx + 92.0 * s;
    [loop] for (uint q = 0u; q < 2u; q++)
    {
        float qy = y0 + (20.0 + 16.0 * (float)q) * s;
        dlLabel(q == 0u ? LB_RATE : LB_AMOUNT, bx, qy, IL_T_CAP * s, IL_DIM, IL_LEFT);
        dlNum(q == 0u ? rate : amt, 2, xv, qy, IL_T_VALUE * s, used ? IL_INK : IL_RULE, IL_RIGHT);
        dlLabel(LB_TIMES, xv + 3.0 * s, qy, IL_T_CAP * s, IL_DIM, IL_LEFT);
    }
}

// The card for arm i: its tag, its channel, what drives it (its channel's pattern, or its rally role),
// the six joints in degrees against their limits (the hovered column brightened, a joint on its limit
// in alarm), its tool height, and its alarms.
void armCard(uint i, int joint, float2 p, float2 R, int4 pats)
{
    float s = g_F.s;
    float cap = IL_T_CAP * s, val = IL_T_VALUE * s;
    KaPose q = Pose[KA_ARM_0 + i];
    KaBall rb = Rally[KA_ARM_0 + i];
    uint al = (uint)q.alarm;
    float4 c = kaCard(p, float2(236.0, 172.0) * s, float4(0.0, 0.0, R), s);
    float x = c.x + 10.0 * s, x1 = c.z - 10.0 * s, y = c.y + 15.0 * s;
    float w = dlLabel(LB_ARM, x, y, IL_T_TITLE * s, IL_DIM, IL_LEFT);
    dlInt((int)i, 2, x + w + 6.0 * s, y, 14.0 * s, IL_INK, IL_LEFT);
    uint g = (uint)clamp(q.chan, 0.0, 3.0);
    float cw = dlLabel(LB_CH_A + g, x1, y, IL_T_TITLE * s, IL_MID, IL_RIGHT);
    dlRect(float4(x1 - cw - 14.0 * s, y - 4.0 * s, x1 - cw - 6.0 * s, y + 4.0 * s), ptId((int)g), 1.0, 1.0);

    // what drives it: the rally, or its channel's pattern
    y += 19.0 * s;
    if (rb.role != KA_ROLE_NONE)
    {
        uint ro = (uint)clamp(rb.role, 1.0, 4.0) - 1u;
        bool elected = rb.role == KA_ROLE_STRIKE || rb.role == KA_ROLE_RECEIVE;
        float rw = dlLabel(LB_RALLY, x, y, cap, IL_DIM, IL_LEFT);
        dlLabel(LB_RO_WATCH + ro, x + rw + 7.0 * s, y, IL_T_BODY * s, elected ? IL_ACCENT : IL_INK, IL_LEFT);
    }
    else dlLabel(LB_PAT_HOLD + (uint)clamp(pats[g], 0, 11), x, y, IL_T_BODY * s, IL_INK, IL_LEFT);
    dlLabel(LB_LIMITS, x1, y, cap, IL_DIM, IL_RIGHT);

    // the joints
    float xv = x + 84.0 * s;
    [loop] for (uint j = 0u; j < 6u; j++)
    {
        float jy = y + (17.0 + 15.0 * (float)j) * s;
        float2 lim = KA_LIM[j];
        float v = jointOf(q, j);
        bool atLim = ka_jointOnStop(v, j);
        bool here = (int)j == joint;
        dlLabel(LB_J_A1 + j, x, jy, cap, here ? IL_INK : IL_DIM, IL_LEFT);
        dlNum(degrees(v), 1, xv, jy, val, atLim ? IL_ALARM : IL_INK, IL_RIGHT);
        dlLabel(LB_DEG, xv + 3.0 * s, jy, cap, IL_DIM, IL_LEFT);
        float lx = x1;
        lx -= dlInt((int)round(degrees(lim.y)), 1, lx, jy, cap, IL_DIM, IL_RIGHT) + 3.0 * s;
        lx -= dlLabel(LB_SLASH, lx, jy, cap, IL_RULE, IL_RIGHT) + 3.0 * s;
        dlInt((int)round(degrees(lim.x)), 1, lx, jy, cap, IL_DIM, IL_RIGHT);
    }

    // the tool, and what is broken
    float ty = y + (17.0 + 15.0 * 6.0 + 4.0) * s;
    float tw = dlLabel(LB_TOOL, x, ty, cap, IL_DIM, IL_LEFT);
    bool flo = (al & KA_ALARM_FLOOR) != 0u;
    float nx = x + tw + 6.0 * s;
    nx += dlNum(q.tool.y, 2, nx, ty, val, flo ? IL_ALARM : IL_INK, IL_LEFT) + 3.0 * s;
    dlLabel(LB_M, nx, ty, cap, IL_DIM, IL_LEFT);
    float ax = x1;
    if ((al & KA_ALARM_SELF) != 0u) ax -= dlLabel(LB_SELF_TAG, ax, ty, cap, IL_ALARM, IL_RIGHT) + 8.0 * s;
    if ((al & KA_ALARM_LIMIT) != 0u || ka_armOnStop(q)) ax -= dlLabel(LB_LIMIT_TAG, ax, ty, cap, IL_ALARM, IL_RIGHT) + 8.0 * s;
    if (flo) dlLabel(LB_FLOOR_TAG, ax, ty, cap, IL_ALARM, IL_RIGHT);
}

void layout()
{
    float2 R = _Resolution.xy;
    float s = g_F.s;
    dlBegin(R);

    KaPose hdr = Pose[KA_HEADER];
    float4 acc = float4(hdr.tool.x, hdr.tool.y, hdr.tool.z, hdr.elbow.x);
    float liveN = hdr.elbow.y;
    float floorN = hdr.alarm;
    float limitN = 0.0;      // arms with a joint on its stop (ka_armOnStop), not only the solver's clamps
    [loop] for (uint ai = 0u; ai < KA_MAX_ARMS; ai++)
    {
        KaPose qa = Pose[KA_ARM_0 + ai];
        if (qa.live > 0.5 && ((((uint)qa.alarm & KA_ALARM_LIMIT) != 0u) || ka_armOnStop(qa))) limitN += 1.0;
    }
    int4 pats = int4((int)hdr.a1, (int)hdr.a2, (int)hdr.a3, (int)hdr.a4);
    float4 rates = float4(rate_a, rate_b, rate_c, rate_d);
    float4 amps = float4(amp_a, amp_b, amp_c, amp_d) * master_amp;
    float val = IL_T_VALUE * s, cap = IL_T_CAP * s;
    float n = max(liveN, 1.0);
    float rowH = poRowH(g_F, liveN);
    float ppm = poToolPpm(g_F, hdr.a5);

    // ---- hover: an arm (a matrix row, or its tool stem) or a channel (a station)
    float2 uv = _ViewportPointerPosition, p = uv * R;
    bool inside = all(uv >= 0.0) && all(uv <= 1.0);
    int hovOrd = -1, hovJoint = -1, hovChan = -1;
    if (inside && ilIn(p, g_F.rows))
    {
        int row = (int)floor((p.y - g_F.rows.y) / rowH);
        if (row >= 0 && (float)row < n) hovOrd = row;
        int cj = (int)floor((p.x - g_F.colX0) / g_F.colW);
        if (cj >= 0 && cj < 6) hovJoint = cj;
    }
    else if (inside && ilIn(p, g_F.tool))
    {
        float u = (p.x - (g_F.plot.x + 10.0 * s)) / max(g_F.plot.z - g_F.plot.x - 20.0 * s, 1.0);
        int o = (n > 1.0) ? (int)round(u * (n - 1.0)) : 0;
        if (o >= 0 && (float)o < n && abs(p.x - poStemX(g_F, (uint)o, n)) < 6.0 * s) hovOrd = o;
    }
    else if (inside)
    {
        [unroll] for (uint c4 = 0u; c4 < 4u; c4++) if (ilIn(p, poStation(g_F, c4))) hovChan = (int)c4;
    }

    // ---- title row: the brand and the view; the live arm count and the two broken states, right
    float4 hb = g_F.head;
    float hy = ilMid(hb).y;
    float tw = dlLabel(LB_TITLE, hb.x, hy, 14.0 * s, IL_INK, IL_LEFT);
    dlLabel(LB_SUBTITLE, hb.x + tw + 10.0 * s, hy, 12.0 * s, IL_DIM, IL_LEFT);
    bool lim = limitN > 0.5, flo = floorN > 0.5;
    float x = hb.z;
    x -= dlInt((int)limitN, 1, x, hy, val, lim ? IL_ALARM : IL_INK, IL_RIGHT) + 6.0 * s;
    x -= dlLabel(LB_ON_LIMIT, x, hy, IL_T_TITLE * s, lim ? IL_ALARM : IL_DIM, IL_RIGHT) + 22.0 * s;
    x -= dlInt((int)floorN, 1, x, hy, val, flo ? IL_ALARM : IL_INK, IL_RIGHT) + 6.0 * s;
    x -= dlLabel(LB_FLOORED, x, hy, IL_T_TITLE * s, flo ? IL_ALARM : IL_DIM, IL_RIGHT) + 22.0 * s;
    x -= dlInt((int)liveN, 1, x, hy, val, IL_INK, IL_RIGHT) + 6.0 * s;
    dlLabel(LB_ARMS, x, hy, IL_T_TITLE * s, IL_DIM, IL_RIGHT);

    // ---- the four stations
    uint4 cnt = uint4(0u, 0u, 0u, 0u);
    [loop] for (uint i = 0u; i < KA_MAX_ARMS; i++)
    {
        KaPose q = Pose[KA_ARM_0 + i];
        if (q.live < 0.5) continue;
        uint g = (uint)q.chan;
        cnt += uint4(g == 0u, g == 1u, g == 2u, g == 3u);
    }
    [loop] for (uint c = 0u; c < 4u; c++)
        station(c, cnt[c], pats[c], rates[c], amps[c], frac(acc[c] + phase), (int)c == hovChan);

    // ---- the joint matrix: frame, the axis header, one live arm per row
    float4 mt = g_F.mat;
    dlBorderRect(mt, IL_RADIUS * s, IL_EDGE, 1.0);
    float my = 0.5 * (mt.y + g_F.rows.y);
    dlLabel(LB_ARM, mt.x + 8.0 * s, my, cap, IL_DIM, IL_LEFT);
    [loop] for (uint j = 0u; j < 6u; j++)
        dlLabel(LB_J_A1 + j, g_F.colX0 + (float)j * g_F.colW + 7.0 * s, my, cap, (int)j == hovJoint ? IL_INK : IL_DIM, IL_LEFT);
    dlHLine(g_F.rows.y - 1.0, mt.x + 1.0, mt.z - 1.0, IL_EDGE);

    // ---- the tool-height strip: frame and caption in its gutter, under the matrix's ARM column
    float4 tl = g_F.tool;
    dlBorderRect(tl, IL_RADIUS * s, IL_EDGE, 1.0);
    dlLabel(LB_TOOL, tl.x + 8.0 * s, tl.y + 14.0 * s, cap, IL_DIM, IL_LEFT);
    dlLabel(LB_HEIGHT, tl.x + 8.0 * s, tl.y + 27.0 * s, cap, IL_DIM, IL_LEFT);

    // ---- one pass over the live arms: the row numbers (the record index, two digits like every
    // arm tag in this project) and the hover lifts — the hovered arm, or every arm of the hovered
    // channel, lifted in the matrix and ringed on the tool strip
    bool nums = rowH >= 8.0;
    float sz = clamp(rowH * 1.05, 9.0, cap);
    int hovArm = -1;
    uint ord = 0u, nn = (uint)n;
    [loop] for (uint a = 0u; a < KA_MAX_ARMS && ord < nn; a++)
    {
        KaPose q = Pose[KA_ARM_0 + a];
        if (q.live < 0.5) continue;
        float cy = g_F.rows.y + ((float)ord + 0.5) * rowH;
        bool hot = (int)ord == hovOrd || (hovChan >= 0 && (uint)q.chan == (uint)hovChan);
        if ((int)ord == hovOrd) hovArm = (int)a;
        if (hot)
        {
            float4 rr = float4(mt.x + 1.0, cy - 0.5 * rowH, mt.z - 1.0, cy + 0.5 * rowH);
            dlRect(rr, IL_INK, 0.07, 0.0);
            if ((int)ord == hovOrd) dlBorderRect(rr, 0.0, IL_RULE, 1.0);
            float2 tp = float2(poStemX(g_F, ord, n), g_F.plot.w - q.tool.y * ppm);
            dlRing(tp, 6.0 * s, 1.25 * s, IL_INK, 0.9);
        }
        if (nums)
        {
            bool isSel = ((uint)Cell[KA_ARM_0 + a].flags & KF_SELECTED) != 0u;
            dlInt((int)a, 2, mt.x + 19.0 * s, cy, sz, isSel ? IL_ACCENT : (hot ? IL_INK : IL_DIM), IL_LEFT);
        }
        ord++;
    }
    // the joint under the pointer, on the hovered row
    if (hovOrd >= 0 && hovJoint >= 0)
    {
        float cy = g_F.rows.y + ((float)hovOrd + 0.5) * rowH;
        float cx0 = g_F.colX0 + (float)hovJoint * g_F.colW + 3.0 * s;
        dlBorderRect(float4(cx0, cy - 0.5 * rowH + 1.0, cx0 + g_F.colW - 6.0 * s, cy + 0.5 * rowH - 1.0), 2.0 * s, IL_MID, 1.0);
    }

    // ---- footer: the one gesture, then (right) the legend for the gutter swatches and the marks;
    // a legend item that would run into the hint is dropped
    float4 ft = g_F.foot;
    float fy = ilMid(ft).y;
    float hintEnd = ft.x + kaHint(ft.x, fy, s, LB_K_HOVER, LB_D_HOVER);
    float lx = ft.z;
    float3 rallyC = lerp(PT_ID_A, IL_INK, 0.45);
    [loop] for (int lg = 4; lg >= 0; lg--)
    {
        uint id = (lg == 4) ? LB_LG_TARGET : ((lg == 3) ? LB_LG_ALARM : ((lg == 2) ? LB_LG_STRIKE : ((lg == 1) ? LB_LG_RALLY : LB_LG_CHANNEL)));
        float mw = (lg == 4) ? 18.0 * s : ((lg == 0) ? 37.0 * s : 7.0 * s);
        if (lx - ilLabelW(id, cap) - 6.0 * s - mw < hintEnd) break;
        lx -= dlLabel(id, lx, fy, cap, IL_DIM, IL_RIGHT) + 6.0 * s;
        if (lg == 4) dlDashed(float2(lx - mw, fy), float2(lx, fy), 1.0, IL_INK, 0.85, 4.0 * s, 3.0 * s);
        else if (lg == 0)
        {
            [unroll] for (int k2 = 0; k2 < 4; k2++)
                dlRect(float4(lx - mw + 10.0 * s * (float)k2, fy - 3.5 * s, lx - mw + 10.0 * s * (float)k2 + 7.0 * s, fy + 3.5 * s), ptId(k2), 1.0, 1.0);
        }
        else dlRect(float4(lx - mw, fy - 3.5 * s, lx, fy + 3.5 * s), (lg == 3) ? IL_ALARM : ((lg == 2) ? IL_ACCENT : rallyC), 1.0, 1.0);
        lx -= mw + 18.0 * s;
    }

    // Tooltips off: the hovered row and column still lift, the card goes
    if (tooltips != 0 && hovArm >= 0) armCard((uint)hovArm, hovJoint, p, R, pats);
    dlFinish();
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    g_F = poFrame(_Resolution.xy);
    if (gi == 0u) layout();
    dlEnd(gi);
}
