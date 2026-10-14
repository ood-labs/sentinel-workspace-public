// KA_Rally / layout.hlsl — the rally court's PLAY pane, type, chrome and hover, recorded for the
// shared UI kit (ui.hlsl draws them over court.hlsl's court plan and flight profile). Geometry comes
// from court_frame.hlsli, the same function the drawing uses; every readout is the live rally record.
//
// The PLAY pane answers "is it rallying, and how well": the state, the current run of hits (the
// score), the best run, the length of each of the last 24 rallies (history.hlsl keeps them), the ball,
// and who is on it. HOVER is read from the pointer each cook and never stored: the player under it is
// ringed and a card gives its role, its timing, its hits and the reach the election tests it on.
#include "../_shared/cell.hlsli"
StructuredBuffer<KaBall> Rally : register(t0);
StructuredBuffer<KaRec>  Cell  : register(t1);
StructuredBuffer<float4> Hist  : register(t2);
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"
#include "../_shared/ka_ui.hlsli"
#include "court_frame.hlsli"

#define HIST_N 24u
#define HIST_MAGIC 260941.0

static CtFrame g_F;

// Footer legend marker widths, in LG_* order: channel swatches, elected, benched, reach, path.
float legendMW(uint k, float s) { return ((k == 0u) ? 37.0 : ((k == 4u) ? 18.0 : 12.0)) * s; }

// The player card: tag and channel, role, timing (seconds to its contact while elected, seconds of
// follow-through left while recovering), its hit tally, its swing and the reach it is elected on.
void playerCard(uint i, float2 p, float2 R)
{
    float s = g_F.s;
    float cap = IL_T_CAP * s, val = IL_T_VALUE * s;
    KaRec r = Cell[KA_ARM_0 + i];
    KaBall a = Rally[KA_ARM_0 + i];
    float4 c = kaCard(p, float2(228.0, 116.0) * s, float4(0.0, 0.0, R), s);
    float x = c.x + 10.0 * s, x1 = c.z - 10.0 * s, y = c.y + 15.0 * s;
    float w = dlLabel(LB_ARM, x, y, IL_T_TITLE * s, IL_DIM, IL_LEFT);
    dlInt((int)i, 2, x + w + 6.0 * s, y, 14.0 * s, IL_INK, IL_LEFT);
    uint g = (uint)clamp(r.grp, 0.0, 3.0);
    float cw = dlLabel(LB_CH_A + g, x1, y, cap, IL_MID, IL_RIGHT);
    dlRect(float4(x1 - cw - 14.0 * s, y - 4.0 * s, x1 - cw - 6.0 * s, y + 4.0 * s), ptId((int)g), 1.0, 1.0);

    y += 19.0 * s;
    bool plays = a.role != KA_ROLE_NONE;
    bool elected = a.role == KA_ROLE_STRIKE || a.role == KA_ROLE_RECEIVE;
    if (plays) dlLabel(LB_RO_WATCH + (uint)clamp(a.role, 1.0, 4.0) - 1u, x, y, IL_T_BODY * s, elected ? IL_ACCENT : IL_INK, IL_LEFT);
    else
    {
        float bw = dlLabel(LB_BENCHED, x, y, IL_T_BODY * s, IL_DIM, IL_LEFT);
        dlLabel(LB_BENCH_NOTE, x + bw + 8.0 * s, y, cap, IL_DIM, IL_LEFT);
    }
    float xv = x1 - ilLabelW(LB_MPS, cap) - 4.0 * s;
    [loop] for (uint k = 0u; k < 4u; k++)
    {
        float ky = y + (18.0 + 17.0 * (float)k) * s;
        bool timing = elected || a.role == KA_ROLE_RECOVER;
        uint capId = (k == 0u) ? (a.role == KA_ROLE_RECOVER ? LB_RECOVERS : LB_CONTACT_IN)
                   : ((k == 1u) ? LB_HITS_T : ((k == 2u) ? LB_SWING : LB_REACH_S));
        dlLabel(capId, x, ky, cap, IL_DIM, IL_LEFT);
        // the swing is the one being solved while elected, and the one just made while recovering
        bool has = (k == 1u || k == 3u) || timing;
        if (!has) { dlLabel(LB_DASH, xv, ky, val, IL_RULE, IL_RIGHT); continue; }
        float v = (k == 0u) ? abs(a.radius) : ((k == 1u) ? a.rallyCount : ((k == 2u) ? a.power : ctPlayReach(r)));
        dlNum(v, (k == 1u) ? 0 : 1, xv, ky, val, (k == 0u && elected) ? IL_ACCENT : IL_INK, IL_RIGHT);
        if (k != 1u) dlLabel((k == 0u) ? LB_SEC : ((k == 2u) ? LB_MPS : LB_M), xv + 4.0 * s, ky, cap, IL_DIM, IL_LEFT);
    }
}

void layout()
{
    float2 R = _Resolution.xy;
    float s = g_F.s;
    dlBegin(R);
    float cap = IL_T_CAP * s, val = IL_T_VALUE * s;

    KaBall hdr = Rally[KA_HEADER];
    int striker = (int)hdr.strikerIdx;
    int lastS = (int)hdr.lastIdx;
    bool dropped = hdr.dropFlag > 0.5;

    // ---- hover: the player under the pointer on the court, measured where court.hlsl draws it
    float2 uv = _ViewportPointerPosition, p = uv * R;
    int hov = -1;
    float2 hovC = float2(0.0, 0.0);
    float hovR = 0.0;
    if (all(uv >= 0.0) && all(uv <= 1.0) && ilIn(p, g_F.court))
    {
        float best = 1e9;
        [loop] for (uint i = 0u; i < KA_MAX_ARMS; i++)
        {
            KaRec r = Cell[KA_ARM_0 + i];
            if (r.active < 0.5) continue;
            float2 c = ctPlanPx(g_F, r.pos);
            float pr = max(ka_spec(r.kind, r.size.x).ped_r * g_F.ppm, 2.4);
            float d = length(p - c);
            if (d < max(pr * 1.8, 10.0 * s) && d < best) { best = d; hov = (int)i; hovC = c; hovR = pr; }
        }
    }

    // ---- title row
    float4 hb = g_F.head;
    float hy = ilMid(hb).y;
    float tw = dlLabel(LB_TITLE, hb.x, hy, 14.0 * s, IL_INK, IL_LEFT);
    dlLabel(LB_SUBTITLE, hb.x + tw + 10.0 * s, hy, 12.0 * s, IL_DIM, IL_LEFT);

    // ---- the court: frame, caption, the grid's key
    float4 cr = g_F.court;
    dlBorderRect(cr, IL_RADIUS * s, IL_EDGE, 1.0);
    dlLabel(LB_COURT, cr.x + 10.0 * s, cr.y + 14.0 * s, IL_T_TITLE * s, IL_DIM, IL_LEFT);
    dlLabel(LB_GRID, cr.z - 10.0 * s, cr.w - 12.0 * s, cap, IL_DIM, IL_RIGHT);

    // ---- the flight profile: frame, caption and its span, the strike plane's height in the gutter,
    // and a tick each second along the floor so a CONTACT IN reading can be found on the arc
    float4 fr = g_F.fly;
    dlBorderRect(fr, IL_RADIUS * s, IL_EDGE, 1.0);
    float fw = dlLabel(LB_FLIGHT, fr.x + 8.0 * s, fr.y + 14.0 * s, IL_T_TITLE * s, IL_DIM, IL_LEFT);
    dlLabel(LB_NEXT_4S, fr.x + 14.0 * s + fw, fr.y + 14.0 * s, cap, IL_DIM, IL_LEFT);
    float shY = ctFlyY(g_F, strike_h);
    dlLabel(LB_STRIKE, fr.x + 8.0 * s, shY, cap, IL_DIM, IL_LEFT);
    float sx = g_F.plot.x - 6.0 * s;
    sx -= dlLabel(LB_M, sx, shY, cap, IL_DIM, IL_RIGHT) + 3.0 * s;
    dlNum(strike_h, 1, sx, shY, val, IL_MID, IL_RIGHT);
    [unroll] for (int tk = 1; tk < (int)CT_SPAN_S; tk++)
        dlVLine(ctFlyX(g_F, (float)tk), g_F.plot.w, g_F.plot.w + 4.0 * s, IL_DIM);

    // ---- PLAY: the state, the score, the run of rallies, the ball, and who is on it
    float4 body = dlPane(g_F.side, s, LB_PLAY, hdr.role == KA_PLAY_LIVE);
    dlClip(g_F.side);
    float x0 = body.x + 10.0 * s, x1 = body.z - 10.0 * s;
    float xu = x1 - ilLabelW(LB_MPS, cap);             // the unit column
    float xv = xu - 4.0 * s;
    float y = body.y + 22.0 * s;
    uint st = (uint)clamp(hdr.role, 0.0, 2.0);
    dlLabel(LB_ST_IDLE + st, x0, y, 20.0 * s, st == 1u ? IL_ACCENT : (st == 2u ? IL_ALARM : IL_DIM), IL_LEFT);

    // the rally count is the score: the hero number
    y += 34.0 * s;
    dlLabel(LB_RALLY, x0, y - 6.0 * s, cap, IL_DIM, IL_LEFT);
    dlLabel(LB_HITS, x0, y + 8.0 * s, cap, IL_DIM, IL_LEFT);
    dlInt((int)hdr.rallyCount, 1, x1, y, 26.0 * s, IL_INK, IL_RIGHT);
    y += 30.0 * s;
    float rowH = 18.0 * s;
    dlLabel(LB_BEST, x0, y, cap, IL_DIM, IL_LEFT);
    dlLabel(LB_HITS_U, xu, y, cap, IL_DIM, IL_LEFT);
    dlInt((int)hdr.a6, 1, xv, y, val, IL_INK, IL_RIGHT);
    y += rowH;
    dlLabel(LB_PLAYERS, x0, y, cap, IL_DIM, IL_LEFT);
    dlInt((int)hdr.a2, 1, xv, y, val, IL_INK, IL_RIGHT);
    y += 14.0 * s;
    dlHLine(y, body.x + 1.0, body.z - 1.0, IL_EDGE);

    // the last 24 rallies, oldest left: one bar per rally, its height the hits it lasted
    float4 h0 = Hist[0];
    uint recorded = (h0.w == HIST_MAGIC) ? (uint)h0.z : 0u;
    uint shown = min(recorded, HIST_N);
    float top = 1.0, sum = 0.0;
    [loop] for (uint q = 0u; q < shown; q++)
    {
        float len = Hist[1u + ((recorded - shown + q) % HIST_N)].x;
        top = max(top, len);
        sum += len;
    }
    y += 16.0 * s;
    dlLabel(LB_HISTORY, x0, y, cap, IL_DIM, IL_LEFT);
    float4 ch = float4(x0, y + 12.0 * s, x1, y + 70.0 * s);
    dlRect(ch, IL_WELL, 1.0, 2.0 * s);
    if (shown > 0u)
    {
        float mean = sum / (float)shown;
        float mx = x1;
        mx -= dlLabel(LB_HITS_U, mx, y, cap, IL_DIM, IL_RIGHT) + 4.0 * s;
        mx -= dlNum(mean, 1, mx, y, val, IL_INK, IL_RIGHT) + 4.0 * s;
        dlLabel(LB_MEAN, mx, y, cap, IL_DIM, IL_RIGHT);
        float bw = (ch.z - ch.x - 4.0 * s) / (float)HIST_N;
        [loop] for (uint b = 0u; b < shown; b++)
        {
            float len = Hist[1u + ((recorded - shown + b) % HIST_N)].x;
            float bx = ch.z - 2.0 * s - (float)(shown - b) * bw;
            float bh = (ch.w - ch.y - 6.0 * s) * saturate(len / top);
            // the newest rally is the live reading; the rest are history
            dlRect(float4(bx + 1.0, ch.w - 3.0 * s - max(bh, 1.0), bx + bw - 1.0, ch.w - 3.0 * s), (b + 1u == shown) ? IL_INK : IL_MID * 0.8, 1.0, 0.0);
        }
        float my = ch.w - 3.0 * s - (ch.w - ch.y - 6.0 * s) * saturate(mean / top);
        dlDashed(float2(ch.x + 2.0 * s, my), float2(ch.z - 2.0 * s, my), 1.0, IL_INK, 0.6, 4.0 * s, 3.0 * s);
    }
    else dlLabel(LB_NO_HISTORY, ilMid(ch).x, ilMid(ch).y, cap, IL_DIM, IL_CENTER);
    y = ch.w + 12.0 * s;
    dlHLine(y, body.x + 1.0, body.z - 1.0, IL_EDGE);

    // the ball
    y += 16.0 * s;
    [loop] for (uint k = 0u; k < 2u; k++)
    {
        float by = y + (float)k * rowH;
        dlLabel(k == 0u ? LB_BALL_H : LB_BALL_V, x0, by, cap, IL_DIM, IL_LEFT);
        dlNum(k == 0u ? hdr.pos.y : length(hdr.vel), 1, xv, by, val, IL_INK, IL_RIGHT);
        dlLabel(k == 0u ? LB_M : LB_MPS, xu, by, cap, IL_DIM, IL_LEFT);
    }
    y += 2.0 * rowH - 4.0 * s;
    dlHLine(y, body.x + 1.0, body.z - 1.0, IL_EDGE);

    // who is on it, how long they have, and who hit it last. Arms are tagged by record index.
    y += 16.0 * s;
    bool hasS = striker >= 0, hasL = lastS >= 0;
    [loop] for (uint w = 0u; w < 3u; w++)
    {
        float wy = y + (float)w * rowH;
        dlLabel(w == 0u ? LB_STRIKER : (w == 1u ? LB_CONTACT_IN : LB_LAST), x0, wy, cap, IL_DIM, IL_LEFT);
        bool has = (w == 2u) ? hasL : hasS;
        if (!has)
        {
            dlLabel(LB_DASH, xv, wy, val, (w == 0u && dropped) ? IL_ALARM : IL_RULE, IL_RIGHT);
            continue;
        }
        if (w == 1u)
        {
            dlNum(Rally[KA_ARM_0 + (uint)striker].radius, 1, xv, wy, val, IL_ACCENT, IL_RIGHT);
            dlLabel(LB_SEC, xu, wy, cap, IL_DIM, IL_LEFT);
        }
        else dlInt(w == 0u ? striker : lastS, 2, xv, wy, val, w == 0u ? IL_ACCENT : IL_MID, IL_RIGHT);
    }
    y += 3.0 * rowH;
    if (dropped) dlLabel(LB_NO_REACH, x0, y + 4.0 * s, IL_T_TITLE * s, IL_ALARM, IL_LEFT);
    dlClipReset();

    // ---- footer: the one gesture, then (right) the legend for the court's marks, most needed first
    // (the channel colours); what will not fit beside the hint is dropped from the least needed end
    float4 ft = g_F.foot;
    float fy = ilMid(ft).y;
    float hintEnd = ft.x + kaHint(ft.x, fy, s, LB_K_HOVER, LB_D_HOVER);
    float lw = 0.0;
    uint nL = 0u;
    [loop] for (uint li = 0u; li < 5u; li++)
    {
        float w = legendMW(li, s) + 6.0 * s + ilLabelW(LB_LG_CHANNEL + li, cap) + ((li > 0u) ? 18.0 * s : 0.0);
        if (hintEnd + lw + w > ft.z) break;
        lw += w;
        nL++;
    }
    float lx = ft.z - lw;
    [loop] for (uint lj = 0u; lj < nL; lj++)
    {
        if (lj > 0u) lx += 18.0 * s;
        float mw = legendMW(lj, s);
        float2 mc = float2(lx + 0.5 * mw, fy);
        if (lj == 0u)
        {
            [unroll] for (int k2 = 0; k2 < 4; k2++)
                dlCircle(float2(lx + 3.5 * s + 10.0 * s * (float)k2, fy), 3.5 * s, ptId(k2), 1.0);
        }
        else if (lj == 1u) dlRing(mc, 4.5 * s, 1.5, IL_ACCENT, 1.0);
        else if (lj == 2u) dlRing(mc, 4.5 * s, 1.0, IL_RULE * 0.7, 1.0);
        else if (lj == 3u) dlEllipse(mc, float2(5.5, 5.5) * s, 1.0, IL_RULE, 1.0, 2.0 * s, 2.0 * s);
        else dlDashed(float2(lx, fy), float2(lx + mw, fy), 1.2, IL_MID, 0.9, 2.0 * s, 2.5 * s);
        lx += mw + 6.0 * s;
        lx += dlLabel(LB_LG_CHANNEL + lj, lx, fy, cap, IL_DIM, IL_LEFT);
    }

    // ---- hover: the player's ring, then its card over everything
    if (hov >= 0)
    {
        dlClip(cr);
        dlRing(hovC, max(hovR * 2.6, 12.0 * s), 1.25 * s, IL_INK, 0.85);
        dlClipReset();
        if (tooltips != 0) playerCard((uint)hov, p, R);     // Tooltips off: the ring stays, the card goes
    }
    dlFinish();
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    KaRec chdr = Cell[KA_HEADER];
    g_F = ctFrame(_Resolution.xy, max(chdr.bias, 4.0), max(chdr.flags, 4.0));
    if (gi == 0u) layout();
    dlEnd(gi);
}
