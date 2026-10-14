// Score / layout - the editor's panes: the acts on one time axis (the ruler, the blocks with their
// hand-offs, the selected rail's marks as ticks, the playhead), the selected act in SPACE (a rail:
// the plan over the elevation, sharing the hall's z axis, with the rail through its marks; a card:
// its 16:9 stage), the VIEW (the hall in outline from the camera at the playhead, or the card that
// is showing), and the inspectors.
//
// Grey carries the hall and the chrome; amber marks the selection (the act, the mark, the item) and
// the live camera (the playhead, the camera's wedge in the plan and the elevation).
//
// 64 threads: thread 0 records the chrome and reserves three batches - the rail's samples, the
// hall's outline in the view, and the camera over the whole show - which every thread then fills.
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"
#include "../_shared/ui/il_pane.hlsli"
#include "sc.hlsli"

#define RAIL_N     64u          // rail samples, four segments each (eye and aim, plan and elevation)
#define RAIL_SLOTS 4u
#define VIEW_SEGS  199u         // the hall in outline
#define TRACK_N    160u         // the camera over the show: samples, two segments each (height, lens)
#define TRACK_SLOTS 2u

static ScLayout g_L;
static float g_s;
static float2 g_res, g_ptr;
static uint g_mode, g_target, g_act, g_loop;
static int g_sel;
static float g_time, g_secs;
static bool g_playing;
static ScPose g_pose;           // the camera at the playhead
static ScCam g_cam;
static uint g_showAct;          // the act the view shows
static bool g_showCard;

void plate(float4 r) { dlRect(r, IL_PANEL, 0.86, IL_RADIUS * g_s); }
bool hot(float4 r) { return g_mode == DM_NONE && ilIn(g_ptr, r); }
bool liveField(uint f) { return g_mode == DM_FIELD && g_target == f; }

// m:ss.f from whole tenths (integer arithmetic: no 0:60.0)
float timeLabel(float t, float x, float y, float size, float3 col)
{
    uint tt = (uint)round(max(t, 0.0) * 10.0);
    uint m = tt / 600u;
    float a = dlInt((int)m, 1, x, y, size, col, IL_LEFT);
    a += dlLabel(LB_COLON, x + a, y, size, IL_DIM, IL_LEFT);
    return a + dlNumEx((float)(tt % 600u) / 10.0, 1, 2, false, x + a, y, size, col, IL_LEFT);
}

// a drag field: a well with its caption at the left and the value at the right (drawn by the caller)
float4 field(uint f, uint caption)
{
    float s = g_s;
    float4 r = scField(g_L, f, s);
    dlRectEdged(r, hot(r) ? IL_RAISE : IL_WELL, 1.0, 2.0 * s, liveField(f) ? IL_ACCENT : IL_EDGE, 1.0);
    dlLabel(caption, r.x + 8.0 * s, ilMid(r).y, IL_T_CAP * s, IL_DIM, IL_LEFT);
    return r;
}
void fieldNum(uint f, uint caption, float v, int decimals)
{
    float4 r = field(f, caption);
    dlNum(v, decimals, r.z - 8.0 * g_s, ilMid(r).y, IL_T_VALUE * g_s, liveField(f) ? IL_ACCENT : IL_INK, IL_RIGHT);
}
void fieldUnit(uint f, uint caption, float v, int decimals, uint unit)
{
    float s = g_s;
    float4 r = field(f, caption);
    float y = ilMid(r).y;
    float uw = dlLabel(unit, r.z - 8.0 * s, y, IL_T_CAP * s, IL_DIM, IL_RIGHT) + 4.0 * s;
    dlNum(v, decimals, r.z - 8.0 * s - uw, y, IL_T_VALUE * s, liveField(f) ? IL_ACCENT : IL_INK, IL_RIGHT);
}

// ---------------------------------------------------------------- the card (its look is the program's: score.hlsli)
// a card in a 16:9 frame: the stage edits it (hidden things show as outlines), the view shows it
void cardDraw(float4 fr, uint a, bool edit)
{
    float s = g_s;
    float h = fr.w - fr.y;
    float2 c = ilMid(fr);
    uint li = scLight(a);
    dlRect(fr, ptInset(scCardGround(li)), 1.0, 0.0);
    [loop] for (uint k = 0u; k < SC_ITEMS; k++)
    {
        float4 it = scItem(a, k);
        float2 p = float2(c.x + it.x * h, c.y - it.y * h);
        bool shown = it.w > 0.5;
        float3 ink = ptInset(scCardInk(li));
        if (shown)
        {
            if (k == 0u) dlLabel(LB_W_0 + scWord(a), p.x, p.y, scCapToEm(it.z * h), ink, IL_CENTER);
            else if (k == 1u) dlCircle(p, it.z * h, ptInset(scCardDisc(li)), 1.0);
            else dlRect(float4(p.x - it.z * h, p.y - SC_BAR_HT * h, p.x + it.z * h, p.y + SC_BAR_HT * h), ink, 1.0, 0.0);
        }
        else if (edit)
        {
            float2 hx = (k == 0u) ? float2(0.5 * scWordW(scWord(a)) * it.z * h, 0.5 * it.z * h) : ((k == 1u) ? it.zz * h : float2(it.z * h, SC_BAR_HT * h));
            [loop] for (uint e = 0u; e < 4u; e++)          // its box, dashed: corner e to corner e + 1
            {
                uint f = (e + 1u) % 4u;
                float2 c0 = p + hx * float2((e == 1u || e == 2u) ? 1.0 : -1.0, (e >= 2u) ? 1.0 : -1.0);
                float2 c1 = p + hx * float2((f == 1u || f == 2u) ? 1.0 : -1.0, (f >= 2u) ? 1.0 : -1.0);
                dlDashed(c0, c1, 1.0, ink, 0.55, 4.0 * s, 3.0 * s);
            }
        }
    }
}

// ---------------------------------------------------------------- the header and the tools
void header()
{
    float s = g_s;
    float4 hd = g_L.head;
    float hy = ilMid(hd).y;
    float tw = ilLabelW(LB_TITLE, 15.0 * s), sw = ilLabelW(LB_SUBTITLE, 12.0 * s);
    float4 hp = float4(hd.x, hd.y, hd.x + tw + sw + 40.0 * s, hd.w);
    plate(hp);
    dlLabel(LB_TITLE, hp.x + 12.0 * s, hy, 15.0 * s, IL_INK, IL_LEFT);
    dlLabel(LB_SUBTITLE, hp.x + 12.0 * s + tw + 14.0 * s, hy, 12.0 * s, IL_DIM, IL_LEFT);

    float cap = IL_T_CAP * s, val = IL_T_VALUE * s;
    float ww = ilLabelW(LB_TIME, cap) + 2.0 * ilNumW(6u, val) + ilLabelW(LB_SLASH, val) + ilLabelW(LB_ACTW, cap) + ilLabelW(LB_OF, cap) + ilNumW(2u, val) + 90.0 * s;
    float4 cp = float4(hd.z - ww, hd.y, hd.z, hd.w);
    plate(cp);
    float x = cp.x + 12.0 * s;
    x += dlLabel(LB_TIME, x, hy, cap, IL_DIM, IL_LEFT) + 6.0 * s;
    [loop] for (uint k = 0u; k < 2u; k++)                // the playhead / the show's length
    {
        x += timeLabel((k == 0u) ? g_time : scTotal(), x, hy, val, (k == 0u) ? IL_ACCENT : IL_INK) + 4.0 * s;
        if (k == 0u) x += dlLabel(LB_SLASH, x, hy, val, IL_DIM, IL_LEFT) + 4.0 * s;
    }
    x += 14.0 * s;
    x += dlLabel(LB_ACTW, x, hy, cap, IL_DIM, IL_LEFT) + 5.0 * s;
    x += dlInt((int)scShowA() + 1, 1, x, hy, val, IL_ACCENT, IL_LEFT) + 5.0 * s;
    x += dlLabel(LB_OF, x, hy, cap, IL_DIM, IL_LEFT) + 5.0 * s;
    dlInt((int)scActs(), 1, x, hy, val, IL_INK, IL_LEFT);
}

void tools()
{
    float s = g_s;
    float cap = IL_T_CAP * s;
    float4 pc = scPlayChip(g_L, s);
    dlRectEdged(pc, g_playing ? IL_RAISE * 1.9 : (hot(pc) ? IL_RAISE * 1.45 : IL_RAISE), 1.0, IL_RADIUS * s, g_playing ? IL_RULE : IL_EDGE, 1.0);
    float y = ilMid(pc).y;
    float2 ic = float2(pc.x + 15.0 * s, y);
    if (g_playing) dlRect(float4(ic - 4.5 * s, ic + 4.5 * s), IL_ACCENT, 1.0, 1.0 * s);
    else dlTri(float2(ic.x + 5.0 * s, y), 5.0 * s, 8.0 * s, 3u, IL_INK, 1.0);
    dlLabel(g_playing ? LB_STOP : LB_PLAY, pc.x + 28.0 * s, y, cap, g_playing ? IL_INK : IL_MID, IL_LEFT);
    float4 ls = scLoopSeg(g_L, s);
    int hs = hot(ls) ? ((g_ptr.x < 0.5 * (ls.x + ls.z)) ? 0 : 1) : -1;
    dlSegmented(ls, s, LB_LOOP_0, 2u, (int)g_loop, hs);
    float x = ls.z + 12.0 * s + dlLabel(LB_LOOP_D, ls.z + 12.0 * s, y, cap, IL_DIM, IL_LEFT);
    dlLabelFit(LB_TOOLS_D, g_L.tools.z, y, cap, IL_DIM, IL_RIGHT, g_L.tools.z - x - 24.0 * s);
}

// ---------------------------------------------------------------- SPACE: the plan and the elevation
float2 rot2(float2 v, float t) { float c = cos(t), sn = sin(t); return float2(v.x * c + v.y * sn, -v.x * sn + v.y * c); }

void hallPlan()
{
    float s = g_s;
    float4 P = g_L.plan;
    float k = g_L.k;
    dlRect(P, IL_WELL, 1.0, 2.0 * s);
    float2 f0 = scPlanP(g_L, -SC_HALL_W, 0.0), f1 = scPlanP(g_L, SC_HALL_W, SC_HALL_L);
    dlRect(float4(f0, f1), IL_PANEL * 1.4, 1.0, 0.0);
    [loop] for (uint g = 0u; g <= 10u; g++)
    {
        float2 a = scPlanP(g_L, -SC_HALL_W, 4.0 * g);
        dlVLine(a.x, f0.y, f1.y, IL_GRID * 1.6);
    }
    // the walls, the end wall
    dlRect(float4(scPlanP(g_L, -SC_HALL_W - SC_WALL_T, 0.0), scPlanP(g_L, -SC_HALL_W, SC_HALL_L)), IL_RULE, 1.0, 0.0);
    dlRect(float4(scPlanP(g_L, SC_HALL_W, 0.0), scPlanP(g_L, SC_HALL_W + SC_WALL_T, SC_HALL_L)), IL_RULE, 1.0, 0.0);
    dlRect(float4(scPlanP(g_L, -SC_HALL_W - SC_WALL_T, SC_HALL_L), scPlanP(g_L, SC_HALL_W + SC_WALL_T, SC_HALL_L + SC_WALL_T)), IL_RULE, 1.0, 0.0);
    // the columns
    [loop] for (uint i = 0u; i < SC_COL_N; i++)
    {
        dlCircle(scPlanP(g_L, -SC_COL_X, scColZ(i)), SC_COL_R * k, IL_MID * 0.8, 1.0);
        dlCircle(scPlanP(g_L, SC_COL_X, scColZ(i)), SC_COL_R * k, IL_MID * 0.8, 1.0);
    }
    // the plinths and the works on them
    [loop] for (uint w = 0u; w < 3u; w++)
    {
        float z = scWorkZ(w);
        dlRect(float4(scPlanP(g_L, -SC_PLINTH_HW, z - SC_PLINTH_HW), scPlanP(g_L, SC_PLINTH_HW, z + SC_PLINTH_HW)), IL_EDGE * 1.6, 1.0, 0.0);
    }
    dlRing(scPlanP(g_L, 0.0, scWorkZ(0u)), SC_SPHERE_R * k, 1.5 * s, IL_INK * 0.85, 1.0);
    dlRectEdged(float4(scPlanP(g_L, -SC_RING_T, scWorkZ(1u) - SC_RING_R - SC_RING_T), scPlanP(g_L, SC_RING_T, scWorkZ(1u) + SC_RING_R + SC_RING_T)), IL_WELL, 1.0, 0.0, IL_INK * 0.85, 1.5 * s);
    [loop] for (uint b = 0u; b < 3u; b++)
    {
        float4 bl = scBlock(b);
        float2 c = float2(0.0, scWorkZ(2u));
        [loop] for (uint e = 0u; e < 4u; e++)
        {
            float2 q0 = float2((e == 0u || e == 3u) ? -bl.x : bl.x, (e < 2u) ? -bl.x : bl.x);
            float2 q1 = float2((e == 0u || e == 1u) ? bl.x : -bl.x, (e == 0u || e == 3u) ? -bl.x : bl.x);
            float2 a0 = c + rot2(q0, bl.z), a1 = c + rot2(q1, bl.z);
            dlLine(scPlanP(g_L, a0.x, a0.y), scPlanP(g_L, a1.x, a1.y), 1.25 * s, IL_INK * (0.85 - 0.12 * b), 1.0);
        }
    }
}

void hallElev()
{
    float s = g_s;
    float4 E = g_L.elev;
    float k = g_L.k;
    dlRect(E, IL_WELL, 1.0, 2.0 * s);
    float2 g0 = scElevP(g_L, 0.0, 0.0), g1 = scElevP(g_L, 0.0, SC_HALL_L);
    dlRect(float4(g0.x, g0.y - 2.0 * s, g1.x, g0.y), IL_RULE, 1.0, 0.0);
    float2 w0 = scElevP(g_L, SC_WALL_H, 0.0), w1 = scElevP(g_L, SC_WALL_H, SC_HALL_L);
    dlDashed(w0, w1, 1.0, IL_RULE, 1.0, 5.0 * s, 4.0 * s);
    dlLine(w1, g1, 1.0, IL_RULE, 1.0);
    [loop] for (uint i = 0u; i < SC_COL_N; i++)
    {
        float2 b = scElevP(g_L, 0.0, scColZ(i) - SC_COL_R), t = scElevP(g_L, SC_COL_H, scColZ(i) + SC_COL_R);
        dlRect(float4(b.x, t.y, t.x, b.y), IL_MID * 0.55, 1.0, 0.0);
    }
    [loop] for (uint w = 0u; w < 3u; w++)
    {
        float z = scWorkZ(w);
        float2 b = scElevP(g_L, 0.0, z - SC_PLINTH_HW), t = scElevP(g_L, SC_PLINTH_H, z + SC_PLINTH_HW);
        dlRect(float4(b.x, t.y, t.x, b.y), IL_EDGE * 1.6, 1.0, 0.0);
    }
    dlRing(scElevP(g_L, SC_PLINTH_H + SC_SPHERE_R, scWorkZ(0u)), SC_SPHERE_R * k, 1.5 * s, IL_INK * 0.85, 1.0);
    dlRing(scElevP(g_L, SC_PLINTH_H + SC_RING_R + SC_RING_T, scWorkZ(1u)), SC_RING_R * k, 2.0 * SC_RING_T * k, IL_INK * 0.85, 1.0);
    [loop] for (uint bk = 0u; bk < 3u; bk++)
    {
        float4 bl = scBlock(bk);
        float hz = bl.x * (abs(cos(bl.z)) + abs(sin(bl.z)));
        float2 b = scElevP(g_L, bl.y - bl.x, scWorkZ(2u) - hz), t = scElevP(g_L, bl.y + bl.x, scWorkZ(2u) + hz);
        dlRectEdged(float4(b.x, t.y, t.x, b.y), IL_WELL, 1.0, 0.0, IL_INK * (0.85 - 0.12 * bk), 1.25 * s);
    }
}

// the marks of the selected rail, both views; and the live camera's wedge
void railMarks()
{
    float s = g_s;
    uint n = scMarkN(g_act);
    [loop] for (uint m = 0u; m < SC_MARKS; m++)
    {
        if (m >= n) continue;
        float4 er = scEyeRec(g_act, m), ar = scAimRec(g_act, m);
        bool sel = (int)m == g_sel;
        bool held = sel && g_mode >= DM_EYE_P && g_mode <= DM_LOOK;
        float3 ink = sel ? IL_ACCENT : IL_INK;
        float2 ep = scPlanP(g_L, er.x, er.z), ap = scPlanP(g_L, ar.x, ar.z);
        float2 ee = scElevP(g_L, er.y, er.z), ae = scElevP(g_L, ar.y, ar.z);
        dlLine(ep, ap, 1.0, sel ? IL_ACCENT * 0.6 : IL_RULE * 1.4, 1.0);
        dlLine(ee, ae, 1.0, sel ? IL_ACCENT * 0.6 : IL_RULE * 1.4, 1.0);
        float r = (held ? 6.0 : 5.0) * s;
        bool he = !sel && g_mode == DM_NONE && (length(g_ptr - ep) < 9.0 * s || length(g_ptr - ee) < 9.0 * s);
        bool ha = !sel && g_mode == DM_NONE && (length(g_ptr - ap) < 9.0 * s || length(g_ptr - ae) < 9.0 * s);
        dlRect(float4(ep - r, ep + r), he ? IL_INK : ink, 1.0, 1.0 * s);
        dlRect(float4(ee - r, ee + r), he ? IL_INK : ink, 1.0, 1.0 * s);
        dlRing(ap, 5.0 * s, (ha ? 2.5 : 1.75) * s, ink, 1.0);
        dlRing(ae, 5.0 * s, (ha ? 2.5 : 1.75) * s, ink, 1.0);
        dlInt((int)m + 1, 1, ep.x + 9.0 * s, ep.y - 9.0 * s, IL_T_CAP * s, sel ? IL_ACCENT : IL_MID, IL_LEFT);
    }
    // the live camera: where it stands and what it takes in, in both views
    float2 yp = S[SC_R4].xy;
    float vf = radians(g_pose.fov) * 0.5;
    float hf = atan(tan(vf) * 16.0 / 9.0);
    float len = 5.0;
    float2 ep = scPlanP(g_L, g_pose.eye.x, g_pose.eye.z), ee = scElevP(g_L, g_pose.eye.y, g_pose.eye.z);
    float2 dl = float2(sin(yp.x - hf), cos(yp.x - hf)), dr = float2(sin(yp.x + hf), cos(yp.x + hf));
    dlLine(ep, scPlanP(g_L, g_pose.eye.x + dl.x * len, g_pose.eye.z + dl.y * len), 1.25 * s, IL_ACCENT, 0.9);
    dlLine(ep, scPlanP(g_L, g_pose.eye.x + dr.x * len, g_pose.eye.z + dr.y * len), 1.25 * s, IL_ACCENT, 0.9);
    float cz = cos(yp.x);                                // the elevation sees the z part of the heading
    float2 du = float2(sin(yp.y + vf), cos(yp.y + vf) * cz), dd = float2(sin(yp.y - vf), cos(yp.y - vf) * cz);
    dlLine(ee, scElevP(g_L, g_pose.eye.y + du.x * len, g_pose.eye.z + du.y * len), 1.25 * s, IL_ACCENT, 0.9);
    dlLine(ee, scElevP(g_L, g_pose.eye.y + dd.x * len, g_pose.eye.z + dd.y * len), 1.25 * s, IL_ACCENT, 0.9);
    dlCircle(ep, 3.0 * s, IL_ACCENT, 1.0);
    dlCircle(ee, 3.0 * s, IL_ACCENT, 1.0);
}

void space()
{
    float s = g_s;
    bool rail = scKind(g_act) == SC_RAIL;
    float4 head = ilPaneHead(g_L.space, s);
    dlPane(g_L.space, s, rail ? LB_SPACE : LB_STAGE, true);
    float tw = ilLabelW(rail ? LB_SPACE : LB_STAGE, IL_T_TITLE * s);
    dlLabelFit(rail ? LB_RAIL_D : LB_STAGE_D, head.x + 22.0 * s + tw, ilMid(head).y, IL_T_CAP * s, IL_DIM, IL_LEFT, head.z - head.x - tw - 32.0 * s);
    float cap = IL_T_CAP * s;
    if (rail)
    {
        dlLabel(LB_PLAN, g_L.plan.x, g_L.plan.y - 8.0 * s, cap, IL_DIM, IL_LEFT);
        dlLabel(LB_ELEV, g_L.elev.x, g_L.elev.y - 8.0 * s, cap, IL_DIM, IL_LEFT);
        dlLabel(LB_AX_X, g_L.plan.x - 14.0 * s, ilMid(g_L.plan).y, cap, IL_DIM, IL_CENTER);
        dlLabel(LB_AX_Y, g_L.elev.x - 14.0 * s, ilMid(g_L.elev).y, cap, IL_DIM, IL_CENTER);
        hallPlan();
        hallElev();
        // z every 8 m under the elevation (the axis both views share)
        [loop] for (uint z = 0u; z <= 5u; z++)
        {
            float2 p = scElevP(g_L, 0.0, 8.0 * z);
            dlVLine(p.x, g_L.elev.w, g_L.elev.w + 4.0 * s, IL_RULE);
            dlInt((int)(8u * z), 1, p.x, g_L.elev.w + 11.0 * s, cap, IL_DIM, IL_CENTER);
        }
    }
}

// the stage's frame and the selected item's outline and size handle, over the card
void stageOverlay()
{
    float s = g_s;
    if (scKind(g_act) == SC_CARD)
    {
        dlBorderRect(ilInset(g_L.stage, -1.0), 0.0, IL_RULE, 1.0);
        if (g_sel >= 0)
        {
            uint k = (uint)g_sel;
            float4 it = scItem(g_act, k);
            float2 c = scStageP(g_L, it.xy);
            float2 hx = scItemHalf(g_L, k, it, scWord(g_act));
            float pad = 5.0 * s;
            if (k == 1u) dlRing(c, hx.x + pad, 1.5 * s, IL_ACCENT, 1.0);
            else dlBorderRect(float4(c - hx - pad, c + hx + pad), 2.0 * s, IL_ACCENT, 1.5 * s);
            float2 hp = scItemHandle(g_L, k, it, scWord(g_act));
            bool hh = g_mode == DM_ISIZE || (g_mode == DM_NONE && length(g_ptr - hp) < 8.0 * s);
            dlRect(float4(hp - 4.5 * s, hp + 4.5 * s), hh ? IL_INK : IL_ACCENT, 1.0, 1.0 * s);
        }
    }
}

// batch 0: rail sample i - the eye's path and the aim's path, in the plan and the elevation
void railItem(uint i, ILBatch b)
{
    dlAtSpan(b, i, RAIL_SLOTS);
    if (scKind(g_act) != SC_RAIL) return;
    float s = g_s;
    float d = scDur(g_act);
    ScPose p0 = (ScPose)0, p1 = (ScPose)0;
    [loop] for (uint j = 0u; j < 2u; j++)               // one scPose, compiled once
    {
        ScPose q = scPose(g_act, d * (float)(i + j) / (float)RAIL_N);
        if (j == 0u) p0 = q;
        else p1 = q;
    }
    dlLine(scPlanP(g_L, p0.eye.x, p0.eye.z), scPlanP(g_L, p1.eye.x, p1.eye.z), 1.5 * s, IL_INK * 0.9, 1.0);
    dlLine(scElevP(g_L, p0.eye.y, p0.eye.z), scElevP(g_L, p1.eye.y, p1.eye.z), 1.5 * s, IL_INK * 0.9, 1.0);
    dlLine(scPlanP(g_L, p0.target.x, p0.target.z), scPlanP(g_L, p1.target.x, p1.target.z), 1.0, IL_MID * 0.7, (i % 2u == 0u) ? 1.0 : 0.0);
    dlLine(scElevP(g_L, p0.target.y, p0.target.z), scElevP(g_L, p1.target.y, p1.target.z), 1.0, IL_MID * 0.7, (i % 2u == 0u) ? 1.0 : 0.0);
}

// ---------------------------------------------------------------- VIEW: the hall in outline
// segment i of the hall: (a, b) in metres, and how much it matters (0 architecture .. 1 the works)
float3 boxCorner(float3 c, float3 h, float t, uint bits)
{
    float3 q = float3(((bits & 1u) != 0u) ? h.x : -h.x, ((bits & 2u) != 0u) ? h.y : -h.y, ((bits & 4u) != 0u) ? h.z : -h.z);
    float2 xz = rot2(q.xz, t);
    return c + float3(xz.x, q.y, xz.y);
}
void boxEdge(float3 c, float3 h, float t, uint e, out float3 a, out float3 b)
{
    uint axis = e / 4u, o = e % 4u;
    uint lo = (axis == 0u) ? ((o & 1u) << 1) | ((o & 2u) << 1) : ((axis == 1u) ? (o & 1u) | ((o & 2u) << 1) : (o & 1u) | ((o & 2u)));
    uint bit = 1u << axis;
    a = boxCorner(c, h, t, lo);
    b = boxCorner(c, h, t, lo | bit);
}
void hallSeg(uint i, out float3 a, out float3 b, out float w)
{
    a = 0.0; b = 0.0; w = 0.0;
    float3 eye = g_pose.eye;
    if (i < 7u) { float x = -SC_HALL_W + 2.0 * i; a = float3(x, 0.0, 0.0); b = float3(x, 0.0, SC_HALL_L); }
    else if (i < 18u) { float z = 4.0 * (i - 7u); a = float3(-SC_HALL_W, 0.0, z); b = float3(SC_HALL_W, 0.0, z); }
    else if (i < 25u)
    {
        uint j = i - 18u;
        float sx = (j % 2u == 0u) ? -SC_HALL_W : SC_HALL_W;
        uint q = j / 2u;
        if (j == 6u) { a = float3(-SC_HALL_W, SC_WALL_H, SC_HALL_L); b = float3(SC_HALL_W, SC_WALL_H, SC_HALL_L); }
        else if (q == 0u) { a = float3(sx, SC_WALL_H, 0.0); b = float3(sx, SC_WALL_H, SC_HALL_L); }
        else { float z = (q == 1u) ? 0.0 : SC_HALL_L; a = float3(sx, 0.0, z); b = float3(sx, SC_WALL_H, z); }
        w = 0.15;
    }
    else if (i < 79u)
    {
        uint j = i - 25u;
        uint col = j / 3u, part = j % 3u;
        float2 c = float2((col < SC_COL_N) ? -SC_COL_X : SC_COL_X, scColZ(col % SC_COL_N));
        float2 v = normalize(c - eye.xz + float2(1e-4, 0.0));
        float2 side = float2(-v.y, v.x) * SC_COL_R;
        float2 l = c - side, r = c + side;
        if (part == 0u) { a = float3(l.x, 0.0, l.y); b = float3(l.x, SC_COL_H, l.y); }
        else if (part == 1u) { a = float3(r.x, 0.0, r.y); b = float3(r.x, SC_COL_H, r.y); }
        else { a = float3(l.x, SC_COL_H, l.y); b = float3(r.x, SC_COL_H, r.y); }
        w = 0.35;
    }
    else if (i < 115u)
    {
        uint j = i - 79u;
        boxEdge(float3(0.0, 0.5 * SC_PLINTH_H, scWorkZ(j / 12u)), float3(SC_PLINTH_HW, 0.5 * SC_PLINTH_H, SC_PLINTH_HW), 0.0, j % 12u, a, b);
        w = 0.4;
    }
    else if (i < 131u)
    {
        // the sphere's outline: a circle across the line of sight
        uint j = i - 115u;
        float3 c = float3(0.0, SC_PLINTH_H + SC_SPHERE_R, scWorkZ(0u));
        float a0 = IL_TAU * j / 16.0, a1 = IL_TAU * (j + 1u) / 16.0;
        a = c + SC_SPHERE_R * (cos(a0) * g_cam.r + sin(a0) * g_cam.u);
        b = c + SC_SPHERE_R * (cos(a1) * g_cam.r + sin(a1) * g_cam.u);
        w = 1.0;
    }
    else if (i < 163u)
    {
        // the ring: its outer and inner edges, in its own plane (y, z)
        uint j = i - 131u;
        float rad = (j < 16u) ? SC_RING_R + SC_RING_T : SC_RING_R - SC_RING_T;
        uint q = j % 16u;
        float3 c = float3(0.0, SC_PLINTH_H + SC_RING_R + SC_RING_T, scWorkZ(1u));
        float a0 = IL_TAU * q / 16.0, a1 = IL_TAU * (q + 1u) / 16.0;
        a = c + rad * float3(0.0, sin(a0), cos(a0));
        b = c + rad * float3(0.0, sin(a1), cos(a1));
        w = 1.0;
    }
    else if (i < VIEW_SEGS)
    {
        uint j = i - 163u;
        float4 bl = scBlock(j / 12u);
        boxEdge(float3(0.0, bl.y, scWorkZ(2u)), bl.xxx, bl.z, j % 12u, a, b);
        w = 1.0;
    }
}

// batch 1: segment i of the hall, clipped at the near plane and projected into the view
void viewItem(uint i, ILBatch b)
{
    dlAt(b, i);
    if (g_showCard) return;
    float3 a, c;
    float w;
    hallSeg(i, a, c, w);
    float3 qa = scToCam(g_cam, a), qc = scToCam(g_cam, c);
    float zn = 0.05;
    if (qa.z < zn && qc.z < zn) return;
    if (qa.z < zn) qa = lerp(qa, qc, (zn - qa.z) / (qc.z - qa.z));
    if (qc.z < zn) qc = lerp(qc, qa, (zn - qc.z) / (qa.z - qc.z));
    float fade = saturate(1.25 - 0.5 * (qa.z + qc.z) / 45.0);
    float3 col = lerp(IL_RULE * 1.5, IL_INK, w);
    dlLine(scCamPx(g_L, g_cam, qa), scCamPx(g_L, g_cam, qc), (w > 0.9 ? 1.5 : 1.0) * g_s, col, lerp(0.35, 1.0, fade));
}

void view()
{
    float s = g_s;
    float4 head = ilPaneHead(g_L.viewPane, s);
    dlPane(g_L.viewPane, s, LB_VIEW, true);
    float tw = ilLabelW(LB_VIEW, IL_T_TITLE * s);
    dlLabelFit(LB_VIEW_D, head.x + 22.0 * s + tw, ilMid(head).y, IL_T_CAP * s, IL_DIM, IL_LEFT, head.z - head.x - tw - 32.0 * s);
    float4 V = g_L.view;
    if (!g_showCard)
    {
        dlRect(V, IL_FIELD, 1.0, 0.0);
        // thirds, faint
        [loop] for (uint t = 1u; t < 3u; t++)
        {
            dlVLine(lerp(V.x, V.z, t / 3.0), V.y, V.w, IL_GRID * 1.4);
            dlHLine(lerp(V.y, V.w, t / 3.0), V.x, V.z, IL_GRID * 1.4);
        }
    }
}

// both card frames - the stage's, to edit, and the view's when a card is showing - from one loop,
// so cardDraw compiles once
void cards()
{
    [loop] for (uint c = 0u; c < 2u; c++)
    {
        bool on = (c == 0u) ? scKind(g_act) == SC_CARD : g_showCard;
        if (on) cardDraw((c == 0u) ? g_L.stage : g_L.view, (c == 0u) ? g_act : g_showAct, c == 0u);
    }
}

// the view's frame (amber while it aims), then the lens, the eye's height, the distance to the aim
void viewOverlay()
{
    float s = g_s;
    float4 V = g_L.view;
    dlBorderRect(ilInset(V, -1.0), 0.0, (g_mode == DM_LOOK) ? IL_ACCENT : IL_RULE, 1.0);
    float cap = IL_T_CAP * s, val = IL_T_VALUE * s;
    float y = V.w + 12.0 * s;
    if (g_showCard) dlLabel(LB_VIEW_CARD, V.x, y, cap, IL_DIM, IL_LEFT);
    else
    {
        float x = V.x;
        [loop] for (uint k = 0u; k < 3u; k++)
        {
            float v = (k == 0u) ? g_pose.fov : ((k == 1u) ? g_pose.eye.y : length(g_pose.target - g_pose.eye));
            x += dlLabel((k == 0u) ? LB_FOV : ((k == 1u) ? LB_EYE : LB_TOAIM), x, y, cap, IL_DIM, IL_LEFT) + 5.0 * s;
            x += dlNum(v, (k == 0u) ? 1 : 2, x, y, val, IL_INK, IL_LEFT) + 3.0 * s;
            x += dlLabel((k == 0u) ? LB_DEG : LB_MU, x, y, cap, IL_DIM, IL_LEFT) + 16.0 * s;
        }
    }
}

// ---------------------------------------------------------------- the MARK / ITEM inspector
void inspector()
{
    float s = g_s;
    bool rail = scKind(g_act) == SC_RAIL;
    float4 head = ilPaneHead(g_L.insp, s);
    dlPane(g_L.insp, s, rail ? LB_MARK : LB_ITEM, g_sel >= 0);
    float cap = IL_T_CAP * s, val = IL_T_VALUE * s;
    float hy = ilMid(head).y;
    float x = head.x + 22.0 * s + ilLabelW(rail ? LB_MARK : LB_ITEM, IL_T_TITLE * s);
    if (g_sel < 0)
    {
        dlLabelFit(rail ? LB_MARK_NONE : LB_ITEM_NONE, x, hy, cap, IL_DIM, IL_LEFT, head.z - x - 10.0 * s);
        return;
    }
    if (rail)
    {
        x += dlInt(g_sel + 1, 1, x, hy, val, IL_ACCENT, IL_LEFT) + 5.0 * s;
        x += dlLabel(LB_OF, x, hy, cap, IL_DIM, IL_LEFT) + 5.0 * s;
        dlInt((int)scMarkN(g_act), 1, x, hy, val, IL_INK, IL_LEFT);
        float4 er = scEyeRec(g_act, (uint)g_sel), ar = scAimRec(g_act, (uint)g_sel);
        // one loop, so the field is compiled once: at %, fov, then eye and aim x y z
        [loop] for (uint f = F_AT; f <= F_TZ; f++)
        {
            float4 xyz = float4(f == F_EX || f == F_TX, f == F_EY || f == F_TY, f == F_EZ || f == F_TZ, 0.0);
            float v = (f == F_AT) ? er.w * 100.0 : ((f == F_FOV) ? ar.w : dot((f < F_TX) ? er : ar, xyz));
            fieldUnit(f, LB_F_0 + f, v, (f <= F_FOV) ? 1 : 2, (f == F_AT) ? LB_PCT : ((f == F_FOV) ? LB_DEG : LB_MU));
        }
    }
    else
    {
        dlLabel(LB_IT_0 + (uint)g_sel, x, hy, cap, IL_ACCENT, IL_LEFT);
        float4 it = scItem(g_act, (uint)g_sel);
        [loop] for (uint f = F_IX; f <= F_IS; f++)
            fieldNum(f, LB_F_8 + (f - F_IX), dot(it.xyz, float3(f == F_IX, f == F_IY, f == F_IS)), 3);
        float4 sc = scShownChip(g_L, s);
        dlChip(sc, s, (it.w > 0.5) ? LB_SHOWN : LB_HIDDEN, it.w > 0.5, hot(sc), false);
    }
}

// ---------------------------------------------------------------- ACTS: the ruler and the lane
void acts()
{
    float s = g_s;
    float4 head = ilPaneHead(g_L.acts, s);
    dlPane(g_L.acts, s, LB_ACTS, true);
    float tw = ilLabelW(LB_ACTS, IL_T_TITLE * s);
    float cap = IL_T_CAP * s;
    dlLabelFit(LB_ACTS_D, head.x + 22.0 * s + tw, ilMid(head).y, cap, IL_DIM, IL_LEFT, head.z - head.x - tw - 32.0 * s);
    float4 R = g_L.ruler, N = g_L.lane;
    float secs = g_secs;
    // the ruler: a tick a second, a number every five
    dlRect(R, hot(R) || g_mode == DM_SCRUB ? IL_RAISE : IL_WELL, 1.0, 2.0 * s);
    uint whole = (uint)secs;
    [loop] for (uint t = 0u; t <= 240u; t++)
    {
        if (t > whole) continue;
        float x = scTX(g_L, secs, (float)t);
        bool major = t % 5u == 0u;
        dlVLine(x, R.w - (major ? 9.0 : 5.0) * s, R.w, major ? IL_DIM : IL_RULE);
        if (major && x < R.z - 12.0 * s) dlInt((int)t, 1, x + 3.0 * s, R.y + 7.0 * s, cap, IL_DIM, IL_LEFT);
    }
    // the acts
    uint n = scActs();
    float t0 = 0.0;
    float4 band = scTickBand(g_L, s);
    [loop] for (uint a = 0u; a < SC_ACTS; a++)
    {
        if (a >= n) continue;
        float d = scDur(a);
        float x0 = scTX(g_L, secs, t0), x1 = scTX(g_L, secs, t0 + d);
        float4 blk = float4(x0 + 1.0 * s, N.y, x1 - 1.0 * s, band.y - 2.0 * s);
        bool sel = a == g_act, moving = g_mode == DM_MOVEACT && g_target == a;
        bool hv = hot(blk);
        bool rail = scKind(a) == SC_RAIL;
        float3 face = moving ? IL_WELL : (sel ? IL_RAISE * 1.9 : (hv ? IL_RAISE * 1.45 : IL_RAISE));
        dlRectEdged(blk, face, 1.0, 2.0 * s, sel ? IL_ACCENT : IL_EDGE, sel ? 1.5 * s : 1.0);
        // the hand-off: a dip falls to black and rises, a glide crosses over; a cut is the edge itself
        float hl = scHandLen(a);
        uint hk = scHand(a);
        bool hands = hk != SC_CUT && (a + 1u < n || g_loop == 0u);
        float hx = hands ? scTX(g_L, secs, t0 + d - hl) : blk.z;
        // (in the top row only: the bottom row's word or light runs the block's full width)
        float gt = blk.y + 4.0 * s, gb = lerp(blk.y, blk.w, 0.56);
        if (hands)
        {
            if (hk == SC_DIP)
            {
                float2 mid = float2(0.5 * (hx + blk.z), gb);
                dlLine(float2(hx, gt), mid, 1.0, IL_MID, 1.0);
                dlLine(mid, float2(blk.z, gt), 1.0, IL_MID, 1.0);
            }
            else
            {
                dlLine(float2(hx, gb), float2(blk.z, gt), 1.0, IL_MID, 1.0);
                dlLine(float2(hx, gt), float2(blk.z, gb), 1.0, IL_MID * 0.6, 1.0);
            }
        }
        // number, kind, length; a card's word or a rail's light
        float ty = blk.y + 12.0 * s;
        float room = blk.z - blk.x - 12.0 * s;
        float x = blk.x + 7.0 * s;
        if (room > 14.0 * s)
        {
            x += dlInt((int)a + 1, 1, x, ty, IL_T_VALUE * s, sel ? IL_ACCENT : IL_INK, IL_LEFT) + 5.0 * s;
            dlLabelFit(LB_K_0 + scKind(a), x, ty, cap, sel ? IL_INK : IL_MID, IL_LEFT, hx - x - 6.0 * s);
            float by = blk.w - 11.0 * s;
            float nw = dlNum(d, 1, blk.x + 7.0 * s, by, cap, IL_DIM, IL_LEFT);
            float x2 = blk.x + 7.0 * s + nw + 2.0 * s;
            x2 += dlLabel(LB_SEC, x2, by, cap, IL_DIM, IL_LEFT) + 8.0 * s;
            if (rail) dlLabelFit(LB_LI_0 + scLight(a), x2, by, cap, IL_DIM, IL_LEFT, blk.z - x2 - 6.0 * s);
            else dlLabelFit(LB_W_0 + scWord(a), x2, by, cap * 0.9, IL_DIM, IL_LEFT, blk.z - x2 - 6.0 * s);
        }
        // the selected rail's marks, as ticks in the band beneath it
        if (sel && rail)
        {
            dlRect(float4(x0 + 1.0 * s, band.y, x1 - 1.0 * s, band.w), IL_WELL, 1.0, 1.0 * s);
            [loop] for (uint m = 0u; m < SC_MARKS; m++)
            {
                if (m >= scMarkN(a)) continue;
                float tx = scTX(g_L, secs, t0 + saturate(scEyeRec(a, m).w) * d);
                bool ms = (int)m == g_sel;
                bool mh = g_mode == DM_NONE && ilIn(g_ptr, band) && abs(g_ptr.x - tx) < 6.0 * s;
                dlDiamond(float2(tx, ilMid(band).y), (ms || mh) ? 5.5 * s : 4.5 * s, 0.0, ms ? IL_ACCENT : (mh ? IL_INK : IL_MID), 1.0);
            }
        }
        t0 += d;
    }
    // a reorder in progress: where the act will land
    if (g_mode == DM_MOVEACT)
    {
        uint drop = (uint)S[SC_V5].y, from = (uint)S[SC_V5].x;
        float tl = 0.0;
        uint seen = 0u;
        float xd = N.z;
        [loop] for (uint b = 0u; b < SC_ACTS; b++)
        {
            if (b >= n || b == from) continue;
            if (seen == drop) xd = min(xd, scTX(g_L, secs, tl));
            tl += scDur(b);
            seen++;
        }
        float tf = 0.0;
        [loop] for (uint c = 0u; c < SC_ACTS; c++) tf += (c < from) ? scDur(c) : 0.0;
        // without the moved act the others close up: the drop sits where their run reaches
        float xs = scTX(g_L, secs, 0.0);
        float offset = (drop >= from) ? scDur(from) : 0.0;
        xd = (seen == drop && drop >= n - 1u) ? scTX(g_L, secs, tl) : xd;
        dlRect(float4(xd - 1.5 * s, N.y - 4.0 * s, xd + 1.5 * s, N.w + 4.0 * s), IL_ACCENT, 1.0, 1.0);
        float2 dp = S[SC_V2].zw - S[SC_V2].xy;
        float4 gb = float4(scTX(g_L, secs, tf) + dp.x, N.y + 6.0 * s, scTX(g_L, secs, tf + scDur(from)) + dp.x, band.y - 8.0 * s);
        dlBorderRect(gb, 2.0 * s, IL_ACCENT, 1.5 * s);
        xs += offset * 0.0;
    }
}

// ---------------------------------------------------------------- the camera over the show
// Two strips under the lane share its time axis: the eye's height and the lens, sampled from the same
// resolve the reducer runs for the live camera (score.hlsli), so a glide reads as a blend, a cut as a
// step, and a card as the pose the camera holds for the next rail (dimmed: nothing shows it).
bool trackOn() { return g_L.track.w > g_L.track.y + 1.0; }
float4 trackStrip(uint k)
{
    float4 T = g_L.track;
    float mid = 0.5 * (T.y + T.w);
    return (k == 0u) ? float4(T.x, T.y, T.z, mid - 3.0 * g_s) : float4(T.x, mid + 3.0 * g_s, T.z, T.w);
}
float trackY(uint k, float v)
{
    float4 r = trackStrip(k);
    float n = (k == 0u) ? v / SC_Y1 : (v - 10.0) / 80.0;
    return lerp(r.w - 3.0 * g_s, r.y + 3.0 * g_s, saturate(n));
}
void trackChrome()
{
    if (!trackOn()) return;
    float s = g_s;
    float cap = IL_T_CAP * s;
    [loop] for (uint k = 0u; k < 2u; k++)
    {
        float4 r = trackStrip(k);
        dlRect(r, IL_WELL, 1.0, 2.0 * s);
        dlLabel(LB_TRK_H + k, r.x + 7.0 * s, r.y + 9.0 * s, cap, IL_DIM, IL_LEFT);
    }
    float wy = trackY(0u, SC_WALL_H);
    float4 h = trackStrip(0u);
    dlDashed(float2(h.x, wy), float2(h.z, wy), 1.0, IL_RULE, 1.0, 4.0 * s, 4.0 * s);
    dlLabel(LB_TRK_W, h.z - 6.0 * s, wy - 7.0 * s, cap, IL_DIM, IL_RIGHT);
}
// batch 2: sample i to sample i + 1 of the show, in both strips
void trackItem(uint i, ILBatch b)
{
    dlAtSpan(b, i, TRACK_SLOTS);
    if (!trackOn()) return;
    float total = scTotal();
    float2 y0 = 0.0, y1 = 0.0;
    float t0 = 0.0, t1 = 0.0;
    bool card = false;
    [loop] for (uint j = 0u; j < 2u; j++)                // one resolve, compiled once
    {
        float t = min(total * (float)(i + j) / (float)TRACK_N, total - 1e-3);
        ScShow r = scResolve(t, g_loop == 0u);
        float2 y = float2(trackY(0u, r.pose.eye.y), trackY(1u, r.pose.fov));
        if (j == 0u) { y0 = y; t0 = t; card = scKind((r.u < 0.5) ? r.A : r.B) == SC_CARD; }
        else { y1 = y; t1 = t; }
    }
    float x0 = scTX(g_L, g_secs, t0), x1 = scTX(g_L, g_secs, t1);
    float a = card ? 0.3 : 1.0;
    dlLine(float2(x0, y0.x), float2(x1, y1.x), 1.5 * g_s, IL_INK, a);
    dlLine(float2(x0, y0.y), float2(x1, y1.y), 1.5 * g_s, IL_MID, a);
}
// the playhead, over the lane and both strips, with the live camera's reading on each
void playhead()
{
    float s = g_s;
    float4 R = g_L.ruler;
    float px = scTX(g_L, g_secs, g_time);
    float yb = trackOn() ? g_L.track.w : g_L.lane.w;
    dlRect(float4(px - 0.75 * s, R.y, px + 0.75 * s, yb), IL_ACCENT, 1.0, 0.0);
    dlTri(float2(px, R.y + 8.0 * s), 5.0 * s, 8.0 * s, 0u, IL_ACCENT, 1.0);
    if (trackOn())
    {
        dlCircle(float2(px, trackY(0u, g_pose.eye.y)), 3.5 * s, IL_ACCENT, 1.0);
        dlCircle(float2(px, trackY(1u, g_pose.fov)), 3.5 * s, IL_ACCENT, 1.0);
    }
}

// ---------------------------------------------------------------- ACT: the selected act's settings
void actInspector()
{
    float s = g_s;
    float4 head = ilPaneHead(g_L.actInsp, s);
    dlPane(g_L.actInsp, s, LB_ACT, true);
    float cap = IL_T_CAP * s, val = IL_T_VALUE * s;
    float hy = ilMid(head).y;
    float x = head.x + 22.0 * s + ilLabelW(LB_ACT, IL_T_TITLE * s);
    x += dlInt((int)g_act + 1, 1, x, hy, val, IL_ACCENT, IL_LEFT) + 5.0 * s;
    x += dlLabel(LB_OF, x, hy, cap, IL_DIM, IL_LEFT) + 5.0 * s;
    dlInt((int)scActs(), 1, x, hy, val, IL_INK, IL_LEFT);
    bool rail = scKind(g_act) == SC_RAIL;
    // kind, hand-off, light - one loop, so the segmented control compiles once - and a card's word, a
    // button with its caption inside
    [loop] for (uint row = 0u; row < 4u; row++)
    {
        if (row == 3u && rail) break;
        float4 r = scActRow(g_L, row, s);
        if (row == 3u)
        {
            dlRectEdged(r, hot(r) ? IL_RAISE * 1.45 : IL_RAISE, 1.0, IL_RADIUS * s, IL_EDGE, 1.0);
            dlLabel(LB_WORDL, r.x + 8.0 * s, ilMid(r).y, cap, IL_DIM, IL_LEFT);
            dlLabel(LB_W_0 + scWord(g_act), r.z - 10.0 * s, ilMid(r).y, IL_T_BODY * s, IL_INK, IL_RIGHT);
        }
        else
        {
            dlLabel((row == 0u) ? LB_KIND : ((row == 1u) ? LB_HAND : LB_LIGHT), r.x + 2.0 * s, r.y - 9.0 * s, cap, IL_DIM, IL_LEFT);
            uint nSeg = (row == 0u) ? 2u : 3u;
            uint first = (row == 0u) ? LB_KS_0 : ((row == 1u) ? LB_H_0 : LB_LI_0);
            uint cur = (row == 0u) ? scKind(g_act) : ((row == 1u) ? scHand(g_act) : scLight(g_act));
            int hs = hot(r) ? (int)min((uint)((g_ptr.x - r.x) / ((r.z - r.x) / (float)nSeg)), nSeg - 1u) : -1;
            dlSegmented(r, s, first, nSeg, (int)cur, hs);
        }
    }
    // length, hand-off length
    [loop] for (uint f = F_DUR; f <= F_HLEN; f++)
        fieldUnit(f, LB_F_11 + (f - F_DUR), (f == F_DUR) ? scDur(g_act) : scActA(g_act).w, (f == F_DUR) ? 1 : 2, LB_SEC);
    // when it runs, under the last row
    float4 r1 = scActRow(g_L, rail ? 1u : 3u, s);
    float y = r1.w + 20.0 * s;
    float x2 = r1.x;
    [loop] for (uint k = 0u; k < 2u; k++)                // starts, ends
    {
        x2 += dlLabel(LB_STARTS + k, x2, y, cap, IL_DIM, IL_LEFT) + 5.0 * s;
        x2 += timeLabel(scStart(g_act) + ((k == 1u) ? scDur(g_act) : 0.0), x2, y, val, IL_INK) + 14.0 * s;
    }
    if (g_act + 1u == scActs())
        dlLabelFit((g_loop == 0u) ? LB_LAST_LOOP : LB_LAST_END, r1.x, y + 18.0 * s, cap, IL_DIM, IL_LEFT, r1.z - r1.x);
}

// ---------------------------------------------------------------- hint bar
void hints()
{
    float s = g_s;
    float kh = 18.0 * s;
    float bx = g_L.hint.x, by = ilMid(g_L.hint).y;
    float total = 0.0;
    [loop] for (uint a = 0u; a < 7u; a++)
        total += ilLabelW(LB_H_K0 + 2u * a, IL_T_CAP * s) + 12.0 * s + 6.0 * s + ilLabelW(LB_H_D0 + 2u * a, IL_T_CAP * s) + 16.0 * s;
    plate(float4(bx, by - 15.0 * s, bx + total + 8.0 * s, by + 15.0 * s));
    bx += 10.0 * s;
    [loop] for (uint b = 0u; b < 7u; b++)
    {
        float kw = ilLabelW(LB_H_K0 + 2u * b, IL_T_CAP * s) + 12.0 * s;
        float dw = ilLabelW(LB_H_D0 + 2u * b, IL_T_CAP * s);
        dlKeycap(float4(bx, by - kh * 0.5, bx + kw, by + kh * 0.5), s, LB_H_K0 + 2u * b);
        dlLabel(LB_H_D0 + 2u * b, bx + kw + 6.0 * s, by, IL_T_CAP * s, IL_DIM, IL_LEFT);
        bx += kw + 6.0 * s + dw + 16.0 * s;
    }
}

// ---------------------------------------------------------------- thread 0
void layout()
{
    dlBegin(g_res);
    header();
    plate(g_L.block);
    tools();
    space();
    dlClip(g_L.space);
    dlBatch(RAIL_N * RAIL_SLOTS, 0u);                    // batch 0: the rail
    dlClipReset();
    if (scKind(g_act) == SC_RAIL) railMarks();
    view();
    dlClip(g_L.view);
    dlBatch(VIEW_SEGS, 0u);                              // batch 1: the hall in outline
    dlClipReset();
    cards();
    stageOverlay();
    viewOverlay();
    inspector();
    acts();
    trackChrome();
    dlClip(g_L.track);
    dlBatch(TRACK_N * TRACK_SLOTS, 0u);                  // batch 2: the camera over the show
    dlClipReset();
    playhead();
    actInspector();
    // the splitters' grips, lit while hovered or held
    bool hx = g_mode == DM_SPLITX || (g_mode == DM_NONE && ilIn(g_ptr, g_L.gripX));
    bool hy = g_mode == DM_SPLITY || (g_mode == DM_NONE && ilIn(g_ptr, g_L.gripY));
    float2 mx = float2(g_L.splitXAt, ilMid(g_L.upper).y), my = float2(ilMid(g_L.inner).x, g_L.splitYAt);
    dlRect(float4(mx.x - 1.5 * g_s, mx.y - 18.0 * g_s, mx.x + 1.5 * g_s, mx.y + 18.0 * g_s), hx ? (g_mode == DM_SPLITX ? IL_ACCENT : IL_INK) : IL_RULE, 1.0, 1.5 * g_s);
    dlRect(float4(my.x - 18.0 * g_s, my.y - 1.5 * g_s, my.x + 18.0 * g_s, my.y + 1.5 * g_s), hy ? (g_mode == DM_SPLITY ? IL_ACCENT : IL_INK) : IL_RULE, 1.0, 1.5 * g_s);
    hints();
    dlFinish();
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    g_res = _Resolution.xy;
    g_s = ilCtx(g_res).s;
    float4 v0 = S[SC_V0], v1 = S[SC_V1], v3 = S[SC_V3], v4 = S[SC_V4];
    g_L = scLayout(g_res, g_s, v4.xy);
    g_mode = (uint)v1.z;
    g_target = (uint)v1.w;
    g_act = min((uint)v3.x, scActs() - 1u);
    g_sel = (int)v3.y;
    g_time = v0.x;
    g_playing = v0.y > 0.5;
    g_loop = (uint)v0.z;
    g_secs = scLaneSecs(v4.z);
    g_ptr = (g_mode != DM_NONE) ? S[SC_V2].zw : _ViewportPointerPosition * g_res;
    g_pose.eye = S[SC_R2].xyz;
    g_pose.fov = S[SC_R2].w;
    g_pose.target = S[SC_R3].xyz;
    g_cam = scCam(g_pose, (g_L.view.z - g_L.view.x) / max(g_L.view.w - g_L.view.y, 1.0));
    // what the view shows: the side of a hand-off that dominates
    float u = scShowMix();
    g_showAct = (u < 0.5) ? scShowA() : scShowB();
    g_showCard = scKind(g_showAct) == SC_CARD;

    if (gi == 0u) layout();
    dlSync();

    railItem(gi, dlGetBatch(0u));                        // RAIL_N == IL_LAYOUT_THREADS
    ILBatch bv = dlGetBatch(1u);
    [loop] for (uint v = gi; v < VIEW_SEGS; v += IL_LAYOUT_THREADS) viewItem(v, bv);
    ILBatch bt = dlGetBatch(2u);
    [loop] for (uint t = gi; t < TRACK_N; t += IL_LAYOUT_THREADS) trackItem(t, bt);
    dlEnd(gi);
}
