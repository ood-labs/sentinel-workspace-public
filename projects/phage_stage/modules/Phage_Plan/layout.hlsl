// Phage_Plan / layout - the construction plan's type, recorded for the shared UI kit (ui.hlsl draws
// it over preview.hlsl's drawing). Positions come from the projection the drawing and the picking
// share (layout.hlsli); the readouts from the records marks.hlsl writes at PM_REC. The legs are
// numbered at their feet (the selected one in accent), and the handle the pointer is over - found by
// the same pick the editor runs on a press (pick.hlsli) - takes a hot ring and a card: the leg, what
// a press there would do, its reach, and its hand edits. While a handle is dragged the card follows
// it with the edits live.
StructuredBuffer<float4> E:register(t0);
#include "plan_design.hlsli"
#include "../_shared/phage_anatomy.hlsli"
#include "layout.hlsli"
#include "pick.hlsli"
#include "../_shared/ph_marks.hlsli"
#include "plan_marks.hlsli"
StructuredBuffer<PhMark> Marks:register(t1);
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"

// A key and what it does; returns the width used.
float hint(float x, float y, float s, uint key, uint does)
{
    float kw = ilLabelW(key, IL_T_CAP * s) + 12.0 * s, kh = 18.0 * s;
    dlKeycap(float4(x, y - 0.5 * kh, x + kw, y + 0.5 * kh), s, key);
    return kw + 6.0 * s + dlLabel(does, x + kw + 6.0 * s, y, IL_T_CAP * s, IL_DIM, IL_LEFT) + 16.0 * s;
}

// A signed offset, its unit and the direction word ("+0.40 m out"); returns the width used.
float offset(float v, uint word, float x, float y, float s)
{
    float w = dlNumSigned(v, 2, x, y, IL_T_VALUE * s, abs(v) > 0.005 ? IL_INK : IL_DIM, IL_LEFT) + 3.0 * s;
    w += dlLabel(LB_M, x + w, y, IL_T_CAP * s, IL_DIM, IL_LEFT) + 4.0 * s;
    return w + dlLabel(word, x + w, y, IL_T_CAP * s, IL_DIM, IL_LEFT) + 12.0 * s;
}

// The card for the leg under the pointer (kind as planPick returns it) or the one being dragged.
void legCard(uint leg, int kind, bool moving, float2 p, float2 R, float s, PhDesign D)
{
    PhPose P0 = phRest();
    float reach = phReach(D, P0, leg);
    float4 ed = E[4 + leg];
    float2 size = float2(372.0, 84.0) * s;
    float2 o = p + 18.0 * s;
    if (o.x + size.x > R.x - 6.0) o.x = p.x - 18.0 * s - size.x;
    if (o.y + size.y > R.y - 6.0) o.y = p.y - 18.0 * s - size.y;
    float4 c = float4(o, o + size);
    dlRectEdged(c, IL_RAISE, 0.96, IL_RADIUS * s, IL_EDGE, 1.0);
    float x = c.x + 10.0 * s, y1 = c.y + 17.0 * s, y2 = c.y + 42.0 * s, y3 = c.y + 66.0 * s;
    x += dlLabel(LB_LEG, x, y1, IL_T_TITLE * s, IL_INK, IL_LEFT) + 5.0 * s;
    x += dlInt((int)leg + 1, 1, x, y1, IL_T_VALUE * s, IL_INK, IL_LEFT) + 10.0 * s;
    if ((int)E[0].x - 1 == (int)leg) dlLabel(LB_SELECTED, x, y1, IL_T_BODY * s, IL_DIM, IL_LEFT);
    bool bad = reach > 0.985;
    float rx = c.z - 10.0 * s;
    rx -= dlLabel(LB_PCT, rx, y1, IL_T_CAP * s, IL_DIM, IL_RIGHT) + 3.0 * s;
    rx -= dlInt((int)round(reach * 100.0), 1, rx, y1, IL_T_VALUE * s, bad ? IL_ALARM : IL_INK, IL_RIGHT) + 6.0 * s;
    dlLabel(LB_REACH, rx, y1, IL_T_TITLE * s, IL_DIM, IL_RIGHT);
    // what a press here does, or that it is moving
    if (moving) dlLabel(kind == 2 ? LB_MOVING_KNEE : LB_MOVING_FOOT, c.x + 10.0 * s, y2, IL_T_TITLE * s, IL_INK, IL_LEFT);
    else hint(c.x + 10.0 * s, y2, s, kind == 0 ? LB_K_CLICK : LB_K_DRAG, kind == 0 ? LB_V_SELECT : kind == 2 ? LB_V_KNEE : LB_V_FOOT);
    // the hand edits on this leg, against its stance
    x = c.x + 10.0 * s;
    if (all(abs(ed) < 0.005)) dlLabel(LB_NO_EDITS, x, y3, IL_T_BODY * s, IL_DIM, IL_LEFT);
    else
    {
        x += dlLabel(LB_FOOT, x, y3, IL_T_CAP * s, IL_DIM, IL_LEFT) + 6.0 * s;
        x += offset(ed.x, LB_W_OUT, x, y3, s);
        x += offset(ed.y, LB_W_ACROSS, x, y3, s) + 6.0 * s;
        x += dlLabel(LB_KNEE, x, y3, IL_T_CAP * s, IL_DIM, IL_LEFT) + 6.0 * s;
        x += offset(ed.z, LB_W_OUT, x, y3, s);
        offset(ed.w, LB_W_UP, x, y3, s);
    }
}

void layout()
{
    float2 R = _Resolution.xy;
    float s = plS();
    dlBegin(R);
    int sel = (int)E[0].x - 1;
    bool sym = E[3].x > 0.5, dragging = E[0].z > 0.5 && sel >= 0;
    float4 pr = planRect(), sr = sectRect();
    PhDesign D = phLoad();
    PhPose P0 = phRest();

    // header: title, then the stance and symmetry on the right
    float hy = 0.5 * plHead() - 2.0 * s;
    float tw = dlLabel(LB_TITLE, 14.0 * s, hy, 14.0 * s, IL_INK, IL_LEFT);
    dlLabel(LB_SUBTITLE, 14.0 * s + tw + 10.0 * s, hy, 12.0 * s, IL_DIM, IL_LEFT);
    float x = R.x - 14.0 * s;
    x -= dlLabel(sym ? LB_SYM_ON : LB_SYM_OFF, x, hy, IL_T_TITLE * s, sym ? IL_INK : IL_DIM, IL_RIGHT) + 22.0 * s;
    x -= dlLabel(LB_ST_REFERENCE + (uint)stance, x, hy, IL_T_TITLE * s, IL_INK, IL_RIGHT) + 7.0 * s;
    dlLabel(LB_STANCE, x, hy, IL_T_TITLE * s, IL_DIM, IL_RIGHT);

    // hover: the handle the pointer is over, by the editor's own pick (never stored)
    float2 uv = _ViewportPointerPosition, p = uv * R;
    int2 hv = (!dragging && all(uv >= 0.0) && all(uv <= 1.0)) ? planPick(p, sel, D, P0) : int2(-1, 0);

    // plan: caption, the audience edge, the DJ booth, the leg numbers at the feet
    dlBorderRect(pr, IL_RADIUS * s, IL_EDGE, 1.0);
    dlLabel(LB_PLAN, pr.x + 10.0 * s, pr.y + 14.0 * s, IL_T_TITLE * s, IL_DIM, IL_LEFT);
    float lip = Marks[PM_REC + 2].fill.x;
    dlLabel(LB_AUDIENCE, planCenter().x, min(planPx(float3(0.0, 0.0, lip + 17.0)).y, pr.w - 14.0 * s), IL_T_TITLE * s, IL_DIM, IL_CENTER);
    float2 dj = planPx(float3(0.0, 0.0, 0.2));
    dlLabel(LB_DJ, dj.x, dj.y, IL_T_CAP * s, IL_DIM, IL_CENTER);
    float2 c0 = planCenter();
    [loop] for (uint leg = 0u; leg < 6u; leg++)
    {
        float2 a = planPx(phAnkle(D, P0, leg)), d = normalize(a - c0 + 1e-4);
        float3 col = sel == (int)leg ? IL_ACCENT : (hv.x == (int)leg ? IL_INK : IL_DIM);
        dlInt((int)leg + 1, 1, a.x + d.x * 26.0 * s, a.y + d.y * 26.0 * s, IL_T_VALUE * s, col, IL_CENTER);
    }

    // section: caption with the leg it cuts, the head plane, then the leg's readouts
    dlBorderRect(sr, IL_RADIUS * s, IL_EDGE, 1.0);
    float cy = sr.y + 14.0 * s;
    float cw = dlLabel(LB_SECTION, sr.x + 10.0 * s, cy, IL_T_TITLE * s, IL_DIM, IL_LEFT);
    uint li = (uint)Marks[PM_REC + 2].fill.y;
    dlInt((int)li + 1, 1, sr.x + 16.0 * s + cw, cy, IL_T_VALUE * s, sel >= 0 ? IL_ACCENT : IL_INK, IL_LEFT);
    float2 o = sectOrigin();
    dlLabel(LB_HEAD, sr.x + 10.0 * s, o.y - 2.0 * sectScale() - 10.0 * s, IL_T_CAP * s, IL_DIM, IL_LEFT);
    float4 L = Marks[PM_REC + 1].fill;
    bool badR = L.w > 0.5;
    float ry = sr.y + 34.0 * s, rx = sr.x + 10.0 * s;
    rx += dlLabel(LB_UPPER, rx, ry, IL_T_TITLE * s, IL_DIM, IL_LEFT) + 6.0 * s;
    rx += dlNum(L.x, 1, rx, ry, IL_T_VALUE * s, IL_INK, IL_LEFT) + 2.0 * s;
    rx += dlLabel(LB_M, rx, ry, IL_T_CAP * s, IL_DIM, IL_LEFT) + 18.0 * s;
    rx += dlLabel(LB_LOWER, rx, ry, IL_T_TITLE * s, IL_DIM, IL_LEFT) + 6.0 * s;
    rx += dlNum(L.y, 1, rx, ry, IL_T_VALUE * s, IL_INK, IL_LEFT) + 2.0 * s;
    rx += dlLabel(LB_M, rx, ry, IL_T_CAP * s, IL_DIM, IL_LEFT) + 18.0 * s;
    rx += dlLabel(LB_REACH, rx, ry, IL_T_TITLE * s, IL_DIM, IL_LEFT) + 6.0 * s;
    rx += dlInt((int)L.z, 1, rx, ry, IL_T_VALUE * s, badR ? IL_ALARM : IL_INK, IL_LEFT) + 2.0 * s;
    rx += dlLabel(LB_PCT, rx, ry, IL_T_CAP * s, IL_DIM, IL_LEFT) + 16.0 * s;
    if (badR) dlLabel(LB_OUT, rx, ry, IL_T_TITLE * s, IL_ALARM, IL_LEFT);

    // the hot handle: one value step up, just outside the handle's own ring
    if (hv.x >= 0)
    {
        uint hl = (uint)hv.x;
        if (hv.y == 2) dlRing(sectPx(phKnee(D, P0, hl), phLegAz(hl)), 15.0, 1.5, IL_INK, 0.9);
        else dlRing(planPx(phAnkle(D, P0, hl)), 13.0, 1.5, IL_INK, hv.y == 1 ? 0.9 : 0.5);
    }

    // footer: the gestures, then the fixture counts in their identity colours
    float fy = R.y - 0.5 * plFoot();
    float hx = 14.0 * s;
    hx += hint(hx, fy, s, LB_K_DRAG, LB_D_DRAG);
    hx += hint(hx, fy, s, LB_K_LEG, LB_D_LEG);
    hx += hint(hx, fy, s, LB_K_S, LB_D_S);
    hx += hint(hx, fy, s, LB_K_R, LB_D_R);
    hint(hx, fy, s, LB_K_ESC, LB_D_ESC);
    float4 counts = Marks[PM_REC].fill;
    float fx = R.x - 14.0 * s;
    [loop] for (int t = 2; t >= 0; t--)
    {
        fx -= dlInt((int)counts[t], 1, fx, fy, IL_T_VALUE * s, IL_INK, IL_RIGHT) + 6.0 * s;
        fx -= dlLabel(LB_T_MOVERS + (uint)t, fx, fy, IL_T_TITLE * s, IL_DIM, IL_RIGHT) + 7.0 * s;
        dlCircle(float2(fx - 3.0 * s, fy), 3.0 * s, ptId(t), 1.0);
        fx -= 24.0 * s;
    }

    // the card (Tooltips): the leg being dragged, else the handle under the pointer; the rings stay
    if (tooltips != 0)
    {
        if (dragging) legCard((uint)sel, E[0].y > 1.5 ? 2 : 1, true, p, R, s, D);
        else if (hv.x >= 0) legCard((uint)hv.x, hv.y, false, p, R, s, D);
    }
    dlFinish();
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    if (gi == 0u) layout();
    dlEnd(gi);
}
