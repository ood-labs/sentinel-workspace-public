// Phage_Kinetics / layout - the motion-control canvas's type and axis meters, recorded for the shared
// UI kit (ui.hlsl draws them over preview.hlsl's plan and elevation). One meter row per axis (BODY,
// CAPSID, six LEGs), two channels each: a track with the zero tick, the travel from zero, the target
// tick, the live position (accent: an established live reading), velocity under it, and the value;
// while an axis is still travelling, a dashed run from where it is to where it is going, and the
// target's value after the live one. The legs are numbered at their feet in the plan so LEG n reads
// against the steel. Point at a row, or at a leg, the capsid or the body in either view: the row
// lifts and shows its travel limits, and marks.hlsl lights the same axis in both views.
StructuredBuffer<float4> DesignIn:register(t0);
StructuredBuffer<float4> A:register(t1);
float4 phD(uint i){return DesignIn[i];}
#include "../_shared/phage_anatomy.hlsli"
#include "kin_common.hlsli"
#include "kin_view.hlsli"
#include "kin_hover.hlsli"
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"

float2 axisRange(uint k, uint c) { if (k == 0u) return c == 0u ? float2(-2.4, 2.0) : float2(-30.0, 30.0); if (k == 1u) return c == 0u ? float2(0.0, 360.0) : float2(-1.2, 2.4); return c == 0u ? float2(-2.5, 2.5) : float2(0.0, 4.5); }
float limitsHint(uint k, uint c) { return k == 0u ? (c == 0u ? 1.0 : 14.0) : k == 1u ? (c == 0u ? 120.0 : 1.4) : (c == 0u ? 2.6 : 3.8); }
uint axisLabel(uint k, uint c) { return k == 0u ? (c == 0u ? LB_HEIGHT : LB_YAW) : k == 1u ? (c == 0u ? LB_SPIN : LB_SHEATH) : (c == 0u ? LB_SWING : LB_LIFT); }
bool axisDegrees(uint k, uint c) { return (k == 0u && c == 1u) || (k == 1u && c == 0u); }

void layout()
{
    float2 R = _Resolution.xy;
    float s = kvS(R);
    dlBegin(R);
    bool ok = _Data0_Count >= 17 && DesignIn[16].w == 260929;

    // header: title, then who drives the axes
    float hy = 0.5 * kvHead(R) - 2.0 * s;
    float tw = dlLabel(LB_TITLE, 14.0 * s, hy, 14.0 * s, IL_INK, IL_LEFT);
    dlLabel(LB_SUBTITLE, 14.0 * s + tw + 10.0 * s, hy, 12.0 * s, IL_DIM, IL_LEFT);
    uint mode = (uint)A[24].y;
    uint lab = mode == 0u ? LB_PROGRAMMER : mode == 1u ? LB_MANUAL : mode == 2u ? LB_DEMO : LB_REST_HOLD;
    float x = R.x - 14.0 * s;
    x -= dlLabel(lab, x, hy, IL_T_TITLE * s, mode == 0u ? IL_ACCENT : IL_INK, IL_RIGHT) + 7.0 * s;   // amber while the live programmer drives
    dlLabel(LB_DRIVE, x, hy, IL_T_TITLE * s, IL_DIM, IL_RIGHT);
    if (!ok)
    {
        dlLabel(LB_WAITING, 0.5 * R.x, 0.3 * R.y, IL_T_BODY * s, IL_DIM, IL_CENTER);
        dlFinish();
        return;
    }
    PhDesign D = phLoad();
    PhPose P = PH_POSE_FROM(A);
    int hk = kvHoverAxis(R, D, P);

    // the two views: a frame and a caption (preview.hlsl fills them and draws the truss)
    float4 pr = kvPlanRect(R), er = kvElevRect(R);
    dlBorderRect(pr, IL_RADIUS * s, IL_EDGE, 1.0);
    dlLabel(LB_PLAN_LIVE, pr.x + 10.0 * s, pr.y + 14.0 * s, IL_T_TITLE * s, IL_DIM, IL_LEFT);
    dlBorderRect(er, IL_RADIUS * s, IL_EDGE, 1.0);
    dlLabel(LB_FRONT, er.x + 10.0 * s, er.y + 14.0 * s, IL_T_TITLE * s, IL_DIM, IL_LEFT);

    // leg numbers at the live feet in plan, pushed out from the body along each leg
    float2 c0 = kvPlan(float3(0.0, 0.0, 0.0), R);
    [loop] for (uint leg = 0u; leg < 6u; leg++)
    {
        float2 a = kvPlan(phAnkle(D, P, leg), R), d = normalize(a - c0 + 1e-4);
        bool hot = hk == 2 + (int)leg;
        dlInt((int)leg + 1, 1, a.x + d.x * 17.0 * s, a.y + d.y * 17.0 * s, IL_T_VALUE * s, hot ? IL_INK : IL_DIM, IL_CENTER);
    }

    // axis meters
    float top = kvRowTop(R), rowH = kvRowH(R);
    if (hk >= 0) dlRect(float4(12.0, top + hk * rowH, R.x - 12.0, top + (hk + 1) * rowH), IL_INK, 0.05, 0.0);
    [loop] for (uint k = 0u; k < 8u; k++)
    {
        float y0 = top + k * rowH, yc = y0 + 0.5 * rowH;
        bool hot = (int)k == hk;
        float nw = dlLabel(k == 0u ? LB_BODY : k == 1u ? LB_CAPSID : LB_LEG, 14.0 * s, yc, IL_T_TITLE * s, IL_INK, IL_LEFT);
        if (k >= 2u) dlInt((int)k - 1, 1, 14.0 * s + nw + 6.0 * s, yc, IL_T_VALUE * s, IL_INK, IL_LEFT);
        float4 s0 = A[3u * k], s1 = A[3u * k + 1u];
        [loop] for (uint cc = 0u; cc < 2u; cc++)
        {
            float x0 = R.x * (cc == 0u ? 0.13 : 0.57), x1 = R.x * (cc == 0u ? 0.53 : 0.97);
            float2 rg = axisRange(k, cc);
            bool deg = axisDegrees(k, cc);
            float pos = cc == 0u ? s0.x : s0.y, tgt = cc == 0u ? s1.x : s1.y, vel = cc == 0u ? s0.z : s0.w;
            if (k == 1u && cc == 0u) { pos = frac(pos / 360.0) * 360.0; tgt = frac(tgt / 360.0) * 360.0; }
            float cy = y0 + 0.3 * rowH;
            float aw = dlLabel(axisLabel(k, cc), x0, cy, IL_T_CAP * s, hot ? IL_MID : IL_DIM, IL_LEFT);
            if (hot)
            {
                // the travel limits, on the caption line of the row under the pointer
                float lx = x0 + aw + 10.0 * s;
                lx += dlNum(rg.x, deg ? 0 : 1, lx, cy, IL_T_CAP * s, IL_MID, IL_LEFT) + 4.0 * s;
                lx += dlLabel(LB_TO, lx, cy, IL_T_CAP * s, IL_DIM, IL_LEFT) + 4.0 * s;
                lx += dlNum(rg.y, deg ? 0 : 1, lx, cy, IL_T_CAP * s, IL_MID, IL_LEFT) + 3.0 * s;
                dlLabel(deg ? LB_DEG : LB_M, lx, cy, IL_T_CAP * s, IL_DIM, IL_LEFT);
            }
            float ty = y0 + 0.66 * rowH, tx0 = x0, tx1 = x1 - 112.0 * s;
            float px = lerp(tx0, tx1, saturate((pos - rg.x) / (rg.y - rg.x)));
            float pt = lerp(tx0, tx1, saturate((tgt - rg.x) / (rg.y - rg.x)));
            float pz = lerp(tx0, tx1, saturate((0.0 - rg.x) / (rg.y - rg.x)));
            bool moving = abs(tgt - pos) > 0.004 * (rg.y - rg.x);
            dlRectEdged(float4(tx0, ty - 2.0 * s, tx1, ty + 2.0 * s), IL_WELL, 1.0, 2.0 * s, IL_EDGE, 1.0);
            dlRect(float4(min(pz, px), ty - 2.0 * s, max(pz, px), ty + 2.0 * s), IL_MID * 0.8, 1.0, 1.0);
            dlRect(float4(pz - 0.5, ty - 5.0 * s, pz + 0.5, ty + 5.0 * s), IL_DIM, 1.0, 0.0);
            if (moving) dlDashed(float2(px, ty), float2(pt, ty), 1.0 * s, IL_INK, 0.6, 3.0 * s, 3.0 * s);
            dlRect(float4(pt - 0.75 * s, ty - 7.0 * s, pt + 0.75 * s, ty + 7.0 * s), IL_INK, 1.0, 0.0);
            dlCircle(float2(px, ty), 3.5 * s, IL_ACCENT, 1.0);
            float vn = saturate(abs(vel) / max(1e-3, limitsHint(k, cc)));
            if (vn > 0.002) dlRect(float4(tx0, ty + 6.0 * s, tx0 + vn * (tx1 - tx0) * 0.3, ty + 7.5 * s), IL_DIM, 1.0, 0.0);
            // the value, then (while it travels) where it is going
            float vx = tx1 + 14.0 * s;
            vx += dlNum(pos, 1, vx, ty, IL_T_VALUE * s, IL_INK, IL_LEFT) + 3.0 * s;
            vx += dlLabel(deg ? LB_DEG : LB_M, vx, ty, IL_T_CAP * s, IL_DIM, IL_LEFT) + 8.0 * s;
            if (moving && round(pos * 10.0) != round(tgt * 10.0))      // only a target the readout can tell apart
            {
                vx += dlLabel(LB_TO, vx, ty, IL_T_CAP * s, IL_DIM, IL_LEFT) + 4.0 * s;
                dlNum(tgt, 1, vx, ty, IL_T_CAP * s, IL_MID, IL_LEFT);
            }
        }
        if (k < 7u) dlHLine(y0 + rowH, 12.0, R.x - 12.0, IL_GRID);
    }
    dlFinish();
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    if (gi == 0u) layout();
    dlEnd(gi);
}
