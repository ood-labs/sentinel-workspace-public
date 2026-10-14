// KA_Robot / scope_layout.hlsl — the Scope's type, recorded for the shared UI kit (scope_raster.hlsl
// draws it over scope.hlsl's underlay and marks).
//
// The Scope is an annotated render, so its type sits on small translucent plates rather than on the
// picture: the title, the live counts, the camera station, and the two numbers that ride beside a
// mark (the selected arm's tag at its base, the ball's speed at the head of its velocity arrow), the
// latter in its mark's own colour and on the same projection the drawing uses (scope_marks.hlsli).
//
// Along the bottom: the camera station (left), then what each mark means and the keys this view
// answers to (right). The legend draws each mark the way scope.hlsl draws it, in the live palette,
// and gives up items from its least needed end rather than run into the camera station.
//
// Nothing is recorded while the Scope is toggled off, so the output is then exactly the Program
// grade — pressing R twice must put you back where you were.
#include "../_shared/cell.hlsli"
StructuredBuffer<KaRec>  Cell  : register(t0);
StructuredBuffer<KaPose> Pose  : register(t1);
StructuredBuffer<KaBall> Rally : register(t2);
StructuredBuffer<KaUi>   Ui    : register(t3);
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"
#include "../_shared/ka_ui.hlsli"
#include "scope_marks.hlsli"

static float g_s;

void plate(float4 r) { dlRect(r, IL_PANEL, 0.86, IL_RADIUS * g_s); }
float intW(int v, float size) { ILNum f = ilFormat((float)v, 0, 1, false); return ilNumW(f.n, size); }
float numW(float v, int dec, float size) { ILNum f = ilFormat(v, dec, 1, false); return ilNumW(f.n, size); }

// The legend: marker widths, and each marker drawn the way scope.hlsl draws the mark it explains.
#define SC_LEGEND_N 6u
float legendMW(uint k, float s) { return ((k == 0u) ? 38.0 : ((k == 1u) ? 18.0 : ((k <= 3u) ? 20.0 : 13.0))) * s; }
void legendMark(uint k, float2 c, float s, ScopePal PAL)
{
    if (k == 0u)            // an arm's base, in its channel's colour
    {
        [unroll] for (int g = 0; g < 4; g++)
            dlRing(c + float2((-15.0 + 10.0 * (float)g) * s, 0.0), 3.5 * s, 1.0, min(ptId(g) * 1.55, 1.0), 1.0);
    }
    else if (k == 1u)       // the contact
    {
        float3 dc = scMark(PT_ACCENT, PAL.decide);
        dlRing(c, 4.5 * s, 1.0, dc, 0.95);
        dlLine(c - float2(9.0 * s, 0.0), c - float2(6.0 * s, 0.0), 1.0, dc, 0.95);
        dlLine(c + float2(6.0 * s, 0.0), c + float2(9.0 * s, 0.0), 1.0, dc, 0.95);
    }
    else if (k == 2u)       // the predicted flight
        dlDashed(c - float2(10.0 * s, 0.0), c + float2(10.0 * s, 0.0), 1.0, scMark(PT_INK, PAL.future), 0.75, 3.0 * s, 2.5 * s);
    else if (k == 3u)       // the velocity arrow
    {
        float3 vc = scMark(PT_INK, PAL.now);
        float2 a1 = c + float2(10.0 * s, 0.0);
        dlLine(c - float2(10.0 * s, 0.0), a1, 1.0, vc, 0.85);
        dlLine(a1, a1 + float2(-5.0, 3.0) * s, 1.0, vc, 0.85);
        dlLine(a1, a1 + float2(-5.0, -3.0) * s, 1.0, vc, 0.85);
    }
    else if (k == 4u)       // the ball
        dlRing(c, 5.0 * s, 1.0, scMark(PT_INK, PAL.subject), 0.9);
    else                    // a tool driven onto a joint limit
    {
        dlCircle(c, 2.6 * s, PT_ALARM, 1.0);
        dlRing(c, 6.0 * s, 1.0, PT_ALARM, 1.0);
    }
}

void layout()
{
    float2 R = _Resolution.xy;
    float s = g_s;
    dlBegin(R);
    if (Ui[0].shown < 0.5) { dlFinish(); return; }
    float cap = IL_T_CAP * s, val = IL_T_VALUE * s, tt = IL_T_TITLE * s;

    // live counts, from the same records the marks are drawn from
    uint liveN = 0u, alarmN = 0u;
    int sel = -1;
    [loop] for (uint i = 0u; i < KA_MAX_ARMS; i++)
    {
        KaRec r = Cell[KA_ARM_0 + i];
        KaPose q = Pose[KA_ARM_0 + i];
        if (r.active < 0.5 || q.live < 0.5) continue;
        liveN++;
        if ((uint)q.alarm != 0u || ka_armOnStop(q)) alarmN++;
        if (((uint)r.flags & KF_SELECTED) != 0u) sel = (int)i;
    }
    KaBall bh = Rally[KA_HEADER];
    bool rally = bh.role != KA_PLAY_IDLE;
    bool drop = bh.dropFlag > 0.5;
    ScopePal PAL = scopePalette();

    // ---- title plate, top left
    float4 hr = float4(16.0 * s, 14.0 * s, 0.0, 44.0 * s);
    float tw = ilLabelW(LB_TITLE, 14.0 * s), sw = ilLabelW(LB_SUBTITLE, 12.0 * s);
    hr.z = hr.x + tw + sw + 34.0 * s;
    plate(hr);
    float hy = ilMid(hr).y;
    dlLabel(LB_TITLE, hr.x + 12.0 * s, hy, 14.0 * s, IL_INK, IL_LEFT);
    dlLabel(LB_SUBTITLE, hr.x + 22.0 * s + tw, hy, 12.0 * s, IL_DIM, IL_LEFT);

    // ---- counts plate, top right: the rally score (live reading) while a ball is in play, the
    // live arms, and the arms in alarm
    float gap = 18.0 * s, cg = 6.0 * s;
    float wAl = ilLabelW(LB_ALARM, tt) + cg + intW((int)alarmN, val);
    float wAr = ilLabelW(LB_ARMS, tt) + cg + intW((int)liveN, val);
    float wRa = rally ? ilLabelW(LB_RALLY, tt) + cg + intW((int)bh.rallyCount, val) + gap : 0.0;
    float4 cr = float4(R.x - 16.0 * s - (wAl + wAr + wRa + gap + 24.0 * s), hr.y, R.x - 16.0 * s, hr.w);
    plate(cr);
    float x = cr.z - 12.0 * s;
    bool al = alarmN > 0u;
    x -= dlInt((int)alarmN, 1, x, hy, val, al ? IL_ALARM : IL_INK, IL_RIGHT) + cg;
    x -= dlLabel(LB_ALARM, x, hy, tt, al ? IL_ALARM : IL_DIM, IL_RIGHT) + gap;
    x -= dlInt((int)liveN, 1, x, hy, val, IL_INK, IL_RIGHT) + cg;
    x -= dlLabel(LB_ARMS, x, hy, tt, IL_DIM, IL_RIGHT) + gap;
    if (rally)
    {
        x -= dlInt((int)bh.rallyCount, 1, x, hy, val, drop ? IL_ALARM : IL_ACCENT, IL_RIGHT) + cg;
        dlLabel(LB_RALLY, x, hy, tt, drop ? IL_ALARM : IL_DIM, IL_RIGHT);
    }

    // ---- camera station, bottom left: a composed pose can be read off the image and typed back in
    float by = R.y - 26.0 * s;
    float3 cp = _CameraPos;
    float wc = ilLabelW(LB_CAMERA, tt) + 12.0 * s;
    [unroll] for (uint a = 0u; a < 3u; a++)
        wc += ilLabelW(LB_AX_X + a, cap) + 5.0 * s + numW(cp[a], 1, val) + 12.0 * s;
    wc += ilLabelW(LB_M, cap);
    float4 br = float4(16.0 * s, by - 15.0 * s, 16.0 * s + wc + 24.0 * s, by + 15.0 * s);
    plate(br);
    float bx = br.x + 12.0 * s;
    bx += dlLabel(LB_CAMERA, bx, by, tt, IL_DIM, IL_LEFT) + 12.0 * s;
    [loop] for (uint k = 0u; k < 3u; k++)
    {
        bx += dlLabel(LB_AX_X + k, bx, by, cap, IL_DIM, IL_LEFT) + 5.0 * s;
        bx += dlNum(cp[k], 1, bx, by, val, IL_INK, IL_LEFT) + 12.0 * s;
    }
    dlLabel(LB_M, bx - 8.0 * s, by, cap, IL_DIM, IL_LEFT);

    // ---- keys, bottom right: the binding this view declares and the camera's own navigation
    float4 kr = float4(0.0, br.y, R.x - 16.0 * s, br.w);
    float kw = 24.0 * s - 16.0 * s;
    [loop] for (uint h = 0u; h < 4u; h++) kw += kaHintW(s, LB_K_R + h, LB_D_R + h);
    kr.x = kr.z - kw;
    if (kr.x > br.z + 10.0 * s)
    {
        plate(kr);
        float kx = kr.x + 12.0 * s;
        [loop] for (uint h2 = 0u; h2 < 4u; h2++) kx += kaHint(kx, by, s, LB_K_R + h2, LB_D_R + h2);
    }
    else kr.x = kr.z + 10.0 * s;

    // ---- the legend, left of the keys
    float room = (kr.x - 10.0 * s) - (br.z + 10.0 * s) - 24.0 * s;
    float lw = 0.0;
    uint nL = 0u;
    [loop] for (uint li = 0u; li < SC_LEGEND_N; li++)
    {
        float w = legendMW(li, s) + 6.0 * s + ilLabelW(LB_LG_CHANNEL + li, cap) + ((li > 0u) ? 16.0 * s : 0.0);
        if (lw + w > room) break;
        lw += w;
        nL++;
    }
    if (nL > 0u)
    {
        float4 lr = float4(kr.x - 10.0 * s - lw - 24.0 * s, br.y, kr.x - 10.0 * s, br.w);
        plate(lr);
        float lx = lr.x + 12.0 * s;
        [loop] for (uint lj = 0u; lj < nL; lj++)
        {
            float mw = legendMW(lj, s);
            legendMark(lj, float2(lx + 0.5 * mw, by), s, PAL);
            lx += mw + 6.0 * s;
            lx += dlLabel(LB_LG_CHANNEL + lj, lx, by, cap, IL_DIM, IL_LEFT) + 16.0 * s;
        }
    }

    // ---- beside the marks
    // the selected machine's tag, at its base: the plan's inspector names this arm by the same index
    if (sel >= 0)
    {
        KaRec r = Cell[KA_ARM_0 + (uint)sel];
        float2 sb; float zb;
        if (projectPt(float3(r.pos.x, 0.02, r.pos.y), R, sb, zb))
        {
            float aw = ilLabelW(LB_ARM, cap);
            float2 at = sb + float2(15.0 * s, -1.0 * s);
            plate(float4(at.x - 5.0 * s, at.y - 9.0 * s, at.x + aw + 5.0 * s + ilNumW(2u, val) + 5.0 * s, at.y + 9.0 * s));
            dlLabel(LB_ARM, at.x, at.y, cap, IL_DIM, IL_LEFT);
            dlInt(sel, 2, at.x + aw + 5.0 * s, at.y, val, IL_ACCENT, IL_LEFT);
        }
    }
    // the ball's speed, off the head of its velocity arrow (the arrow's length is the same speed)
    float spd = length(bh.vel);
    if (rally && spd > 0.2)
    {
        float2 a0, a1; float za, zt;
        if (projectPt(bh.pos, R, a0, za) && projectPt(bh.pos + bh.vel * 0.33, R, a1, zt))
        {
            float2 u = (a1 - a0) / max(length(a1 - a0), 1e-4);
            float2 n2 = float2(-u.y, u.x);
            float2 at = a1 + n2 * 7.0 + u * 4.0 + float2(0.0, 5.0 * s);
            float nw = numW(spd, 1, val);
            float uw = ilLabelW(LB_MPS, cap);
            plate(float4(at.x - 5.0 * s, at.y - 9.0 * s, at.x + nw + 4.0 * s + uw + 5.0 * s, at.y + 9.0 * s));
            dlNum(spd, 1, at.x, at.y, val, scMark(IL_INK, PAL.now), IL_LEFT);
            dlLabel(LB_MPS, at.x + nw + 4.0 * s, at.y, cap, IL_DIM, IL_LEFT);
        }
    }
    dlFinish();
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    g_s = ilCtx(_Resolution.xy).s;
    if (gi == 0u) layout();
    dlEnd(gi);
}
