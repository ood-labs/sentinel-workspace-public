// KA_Cell / layout.hlsl — the cell plan's type, chrome and hover, recorded for the shared UI kit
// (ui.hlsl draws it over canvas.hlsl's plan and elevation).
//
// The strip rects and the metres-to-pixels map come from layout.hlsli, the functions the state pass
// picks with, so a caption, a ruler tick or a frame sits exactly where the drawing and the hit test
// put them. Every number is the live record value: the inspector reads the selected record, the
// cell pane counts the records, and the footer lists the module's real bindings.
//
// HOVER is read from the pointer each cook and never stored. The record under the pointer is found
// by the same rule the state pass applies to a click, so what lifts is what a click would select: it
// gets a ring in BOTH strips (the plan and the elevation share X) and a card with its live values.
#include "../_shared/cell.hlsli"
#include "layout.hlsli"
#include "ui_frame.hlsli"
StructuredBuffer<KaRec> Cell : register(t0);
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"
#include "../_shared/ka_ui.hlsli"

#define NO_UNIT 0xFFFFu
#define ROW_NUM   0u
#define ROW_FRAME 1u
#define ROW_CHAN  2u
#define ROW_DASH  3u

static float g_s;

// The record under a diagram point, +1 (0 = none) — EXACTLY plan.hlsl's pickArm, restated because
// the state pass is the click authority and stays untouched: the target first with a generous grab
// radius, then the live arm whose footprint holds the point, smallest hit wins. Same functions, same
// radii, same aspect metric, so the hover is always the arm a click there would select.
uint hoverPick(KaMap m, float2 uv, int strip)
{
    uint best = 0u; float bestScore = 1e9;
    float2 asp = float2(m.res.x / max(m.res.y, 1.0), 1.0);
    {
        KaRec t = Cell[KA_TARGET];
        float3 tp = ka_targetPos(t);
        float2 hp = (strip == 1) ? kaPlanUV(m, float2(tp.x, tp.z)) : kaElevUV(m, tp.x, tp.y);
        float d = length((uv - hp) * asp);
        if (d < 0.022) { bestScore = d; best = KA_TARGET + 1u; }
    }
    [loop] for (uint i = 0u; i < KA_MAX_ARMS; i++)
    {
        KaRec r = Cell[KA_ARM_0 + i];
        if (r.active < 0.5) continue;
        KaSpec sp = ka_spec(r.kind, r.size.x);
        float2 hp = (strip == 1) ? kaPlanUV(m, r.pos) : kaElevUV(m, r.pos.x, r.size.y + sp.turret * 0.5);
        float rad = max(kaLenX(m, sp.ped_r * 1.15), 0.013);
        float d = length((uv - hp) * asp);
        if (d < rad && d < bestScore) { bestScore = d; best = KA_ARM_0 + i + 1u; }
    }
    return best;
}

// caption, value, unit, left to right; returns the width
float pair(float x, float y, uint capId, float v, int dec, uint unit, float3 vc)
{
    float s = g_s;
    float w = dlLabel(capId, x, y, IL_T_CAP * s, IL_DIM, IL_LEFT) + 4.0 * s;
    w += dlNum(v, dec, x + w, y, IL_T_VALUE * s, vc, IL_LEFT) + 3.0 * s;
    if (unit != NO_UNIT) w += dlLabel(unit, x + w, y, IL_T_CAP * s, IL_DIM, IL_LEFT);
    return w;
}

// The hovered record's place in both strips: one ring in the plan, one in the elevation.
void hotRings(uint idx, KaMap m, float2 R, float4 pr, float4 er)
{
    float s = g_s;
    float2 pc, ec;
    float rp, re;
    if (idx == KA_TARGET)
    {
        float3 tp = ka_targetPos(Cell[KA_TARGET]);
        pc = kaPlanUV(m, float2(tp.x, tp.z)) * R;
        ec = kaElevUV(m, tp.x, tp.y) * R;
        rp = 13.0 * s; re = 11.0 * s;
    }
    else
    {
        KaRec r = Cell[idx];
        KaSpec sp = ka_spec(r.kind, r.size.x);
        float ped = max(kaLenX(m, sp.ped_r) * R.x, 2.4);
        pc = kaPlanUV(m, r.pos) * R;
        ec = kaElevUV(m, r.pos.x, r.size.y + sp.turret * 0.5) * R;
        rp = max(ped * 2.5, 9.0 * s); re = max(ped * 1.7, 8.0 * s);
    }
    dlClip(pr);
    dlRing(pc, rp, 1.25 * s, IL_INK, 0.85);
    dlClip(er);
    dlRing(ec, re, 1.25 * s, IL_INK, 0.85);
    dlClipReset();
}

// The hover card: who it is and its live values, beside the pointer, flipped off the edges.
void hoverCard(uint idx, float2 p, float2 R)
{
    float s = g_s;
    float cap = IL_T_CAP * s;
    if (idx == KA_TARGET)
    {
        KaRec t = Cell[KA_TARGET];
        float3 tp = ka_targetPos(t);
        float4 c = kaCard(p, float2(224.0, 84.0) * s, float4(0.0, 0.0, R), s);
        float x = c.x + 10.0 * s, y = c.y + 15.0 * s;
        float w = dlLabel(LB_TARGET, x, y, IL_T_TITLE * s, IL_INK, IL_LEFT);
        dlLabel(LB_T_LIVE, x + w + 8.0 * s, y, cap, IL_DIM, IL_LEFT);
        if (((uint)t.flags & KF_EDITED) != 0u) dlLabel(LB_EDITED, c.z - 10.0 * s, y, cap, IL_MID, IL_RIGHT);
        [loop] for (uint q = 0u; q < 5u; q++)
        {
            float qy = y + (20.0 + 17.0 * (float)(q >> 1)) * s;
            float qx = ((q & 1u) != 0u) ? x + 106.0 * s : x;
            float v = (q == 0u) ? tp.x : ((q == 1u) ? tp.z : ((q == 2u) ? tp.y : ((q == 3u) ? t.size.y : t.yaw)));
            uint qc = (q == 0u) ? LB_R_X : ((q == 1u) ? LB_R_Z : ((q == 2u) ? LB_T_HEIGHT : ((q == 3u) ? LB_T_ORBIT : LB_T_RATE)));
            pair(qx, qy, qc, v, (q == 4u) ? 2 : 1, (q == 4u) ? LB_REV_S : LB_M, IL_INK);
        }
        return;
    }
    KaRec r = Cell[idx];
    KaSpec sp = ka_spec(r.kind, r.size.x);
    uint fl = (uint)r.flags;
    float4 c = kaCard(p, float2(232.0, 100.0) * s, float4(0.0, 0.0, R), s);
    float x = c.x + 10.0 * s, y = c.y + 15.0 * s;
    float w = dlLabel(LB_ARM, x, y, IL_T_TITLE * s, IL_DIM, IL_LEFT);
    dlInt((int)(idx - KA_ARM_0), 2, x + w + 6.0 * s, y, 14.0 * s, IL_INK, IL_LEFT);
    float rx = c.z - 10.0 * s;
    if ((fl & KF_OUTSIDE) != 0u) rx -= dlLabel(LB_OUTSIDE, rx, y, cap, IL_ALARM, IL_RIGHT) + 8.0 * s;
    if ((fl & KF_OVERLAP) != 0u) rx -= dlLabel(LB_CLASH, rx, y, cap, IL_ALARM, IL_RIGHT) + 8.0 * s;
    if ((fl & KF_EDITED) != 0u) dlLabel(LB_EDITED, rx, y, cap, IL_MID, IL_RIGHT);
    // channel (its identity colour) and frame size (its value on the ordinal ramp)
    y += 19.0 * s;
    uint g = (uint)clamp(r.grp, 0.0, 3.0), kk = (uint)clamp(r.kind, 0.0, 2.0);
    dlRect(float4(x, y - 4.0 * s, x + 8.0 * s, y + 4.0 * s), ptId((int)g), 1.0, 1.0);
    float cx = x + 14.0 * s;
    cx += dlLabel(LB_R_CHANNEL, cx, y, cap, IL_DIM, IL_LEFT) + 5.0 * s;
    cx += dlLabel(LB_CH_A + g, cx, y, IL_T_BODY * s, ptId((int)g), IL_LEFT) + 14.0 * s;
    cx += dlLabel(LB_F_COMPACT + kk, cx, y, IL_T_BODY * s, ptRamp(0.30 + (float)kk * 0.35), IL_LEFT) + 4.0 * s;
    dlLabel(LB_FRAME_U, cx, y, IL_T_BODY * s, IL_DIM, IL_LEFT);
    // where it stands and how much air it owns, two to a row
    float yaw = degrees(atan2(sin(r.yaw), cos(r.yaw)));
    [loop] for (uint q = 0u; q < 6u; q++)
    {
        float qy = y + (18.0 + 17.0 * (float)(q >> 1)) * s;
        float qx = ((q & 1u) != 0u) ? x + 110.0 * s : x;
        float v = (q == 0u) ? r.pos.x : ((q == 1u) ? r.pos.y : ((q == 2u) ? yaw
                : ((q == 3u) ? ka_reach(sp) : ((q == 4u) ? ka_rise(sp, r.size.y) : r.size.y))));
        uint qc = (q == 0u) ? LB_R_X : ((q == 1u) ? LB_R_Z : ((q == 2u) ? LB_R_HEADING
                : ((q == 3u) ? LB_R_REACH : ((q == 4u) ? LB_R_RISE : LB_R_PEDESTAL))));
        pair(qx, qy, qc, v, (q == 2u) ? 0 : 1, (q == 2u) ? LB_DEG : LB_M, IL_INK);
    }
}

// Row k of the SELECTION pane: its caption, how it is shown, and the value with its unit.
// An arm has ten rows, the target five; with nothing selected the arm's captions keep their place
// and every value is a dash — a zero is a real reading and would say an arm stands at the origin.
uint selRow(uint k, uint mode, KaRec r, out float v, out int dec, out uint unit, out uint kind)
{
    v = 0.0; dec = 1; unit = LB_M; kind = ROW_NUM;
    if (mode == 2u)                                    // the target: its anchor and orbit
    {
        if (k == 0u) { v = r.pos.x; return LB_R_X; }
        if (k == 1u) { v = r.pos.y; return LB_R_Z; }
        if (k == 2u) { v = r.size.x; return LB_T_HEIGHT; }
        if (k == 3u) { v = r.size.y; return LB_T_ORBIT; }
        v = r.yaw; dec = 2; unit = LB_REV_S; return LB_T_RATE;
    }
    if (mode == 0u) { kind = ROW_DASH; return LB_R_X + k; }
    KaSpec sp = ka_spec(r.kind, r.size.x);
    if (k == 0u) v = r.pos.x;
    else if (k == 1u) v = r.pos.y;
    else if (k == 2u) { v = degrees(atan2(sin(r.yaw), cos(r.yaw))); dec = 0; unit = LB_DEG; }
    else if (k == 3u) v = ka_reach(sp);
    else if (k == 4u) v = ka_rise(sp, r.size.y);
    else if (k == 5u) kind = ROW_FRAME;
    else if (k == 6u) { v = r.size.x; dec = 2; unit = LB_TIMES; }
    else if (k == 7u) v = r.size.y;
    else if (k == 8u) kind = ROW_CHAN;
    else { v = r.bias; dec = 2; unit = NO_UNIT; }
    return LB_R_X + k;
}

void layout()
{
    float2 R = _Resolution.xy;
    float s = g_s;
    dlBegin(R);

    KaRec hdr = Cell[KA_HEADER];
    float sel = hdr.pos.y;
    float liveN = hdr.grp, clashN = hdr.kind;
    float cw = max(hdr.bias, 0.5), cd = max(hdr.flags, 0.5), maxRise = max(hdr.spare, 0.5);
    KaMap m = kaMap(R, cw, cd, maxRise);
    float4 pr = kcPlanRect(R), er = kcElevRect(R), ir = kcInspRect(R);
    float cap = IL_T_CAP * s, val = IL_T_VALUE * s;

    // ---- title row: the brand and the view; the arrangement the lattice is strung on, right
    float hy = 0.5 * pr.y;
    float tw = dlLabel(LB_TITLE, pr.x, hy, 14.0 * s, IL_INK, IL_LEFT);
    dlLabel(LB_SUBTITLE, pr.x + tw + 10.0 * s, hy, 12.0 * s, IL_DIM, IL_LEFT);
    uint arr = (uint)clamp((float)arrangement, 0.0, 5.0);
    float ax = ir.z;
    ax -= dlLabel(LB_ARR_LINE + arr, ax, hy, IL_T_TITLE * s, IL_INK, IL_RIGHT) + 7.0 * s;
    dlLabel(LB_ARRANGEMENT, ax, hy, IL_T_TITLE * s, IL_DIM, IL_RIGHT);

    // ---- the plan: frame, caption, the grid's key
    dlBorderRect(pr, IL_RADIUS * s, IL_EDGE, 1.0);
    float pcw = dlLabel(LB_PLAN, pr.x + 10.0 * s, pr.y + 14.0 * s, IL_T_TITLE * s, IL_DIM, IL_LEFT);
    dlLabel(LB_PLAN_NOTE, pr.x + 18.0 * s + pcw, pr.y + 14.0 * s, cap, IL_DIM, IL_LEFT);
    float gkw = dlLabel(LB_GRID, pr.z - 10.0 * s, pr.w - 12.0 * s, cap, IL_DIM, IL_RIGHT);
    // the one alarm the plan draws, keyed where it is read
    float lgx = pr.x + 10.0 * s, lgy = pr.w - 12.0 * s;
    dlRect(float4(lgx, lgy - 4.0 * s, lgx + 12.0 * s, lgy + 4.0 * s), IL_ALARM * 0.55, 0.55, 1.0);
    dlLabelFit(LB_SHARED, lgx + 18.0 * s, lgy, cap, IL_DIM, IL_LEFT, pr.z - gkw - lgx - 40.0 * s);

    // ---- the elevation: frame, caption, and the height ruler on the scale both strips share
    dlBorderRect(er, IL_RADIUS * s, IL_EDGE, 1.0);
    float ecw = dlLabel(LB_ELEVATION, er.x + 10.0 * s, er.y + 14.0 * s, IL_T_TITLE * s, IL_DIM, IL_LEFT);
    dlLabel(LB_ELEV_NOTE, er.x + 18.0 * s + ecw, er.y + 14.0 * s, cap, IL_DIM, IL_LEFT);
    float2 unitAt = float2(-1.0, -1.0);
    [loop] for (uint k = 1u; k < 9u; k++)
    {
        float ty = kaElevUV(m, 0.0, (float)k).y * R.y;
        if (ty < er.y + 26.0 * s) break;               // heights only climb: stop below the caption
        dlHLine(ty, er.x + 3.0 * s, er.x + 9.0 * s, IL_RULE);
        float nw = dlInt((int)k, 1, er.x + 12.0 * s, ty, cap, IL_DIM, IL_LEFT);
        unitAt = float2(er.x + 15.0 * s + nw, ty);
    }
    if (unitAt.x > 0.0) dlLabel(LB_M, unitAt.x, unitAt.y, cap, IL_DIM, IL_LEFT);

    // ---- inspector: what is selected, then the cell as a whole. Clipped to its column.
    dlClip(ir);
    uint si = (uint)max(sel - 1.0, 0.0);
    bool isTgt = (sel > 0.5) && (si == KA_TARGET);
    bool has = (sel > 0.5) && !isTgt;
    uint mode = isTgt ? 2u : (has ? 1u : 0u);
    KaRec sr = Cell[min(si, KA_RECORDS - 1u)];

    float paneA = 258.0 * s;
    float4 ra = float4(ir.x, ir.y, ir.z, min(ir.y + paneA, ir.w));
    float4 ba = dlPane(ra, s, LB_SELECTION, sel > 0.5);
    float x0 = ba.x + 10.0 * s, x1 = ba.z - 10.0 * s;
    float xu = x1 - ilLabelW(LB_DEG, cap);             // the unit column
    float xv = xu - 4.0 * s;                           // values end here
    float y = ba.y + 17.0 * s;
    if (has)
    {
        float w = dlLabel(LB_ARM, x0, y, IL_T_TITLE * s, IL_DIM, IL_LEFT);
        dlInt((int)(si - KA_ARM_0), 2, x0 + w + 7.0 * s, y, 16.0 * s, IL_ACCENT, IL_LEFT);
    }
    else if (isTgt)
    {
        float w = dlLabel(LB_TARGET, x0, y, IL_T_TITLE * s, IL_ACCENT, IL_LEFT);
        dlLabel(LB_T_ANCHOR, x0 + w + 8.0 * s, y, cap, IL_DIM, IL_LEFT);
    }
    else dlLabel(LB_NOTHING, x0, y, IL_T_BODY * s, IL_DIM, IL_LEFT);

    uint rowsN = isTgt ? 5u : 10u;
    float rowH = 17.0 * s;
    [loop] for (uint rk = 0u; rk < rowsN; rk++)
    {
        float ry = ba.y + 40.0 * s + rk * rowH;
        float v; int dec; uint unit, kind;
        uint capId = selRow(rk, mode, sr, v, dec, unit, kind);
        dlLabel(capId, x0, ry, cap, IL_DIM, IL_LEFT);
        if (kind == ROW_DASH) dlLabel(LB_DASH, xv, ry, val, IL_RULE, IL_RIGHT);
        else if (kind == ROW_FRAME)
        {
            uint kk = (uint)clamp(sr.kind, 0.0, 2.0);
            dlLabel(LB_F_COMPACT + kk, xv, ry, IL_T_BODY * s, ptRamp(0.30 + (float)kk * 0.35), IL_RIGHT);
        }
        else if (kind == ROW_CHAN)
        {
            uint g = (uint)clamp(sr.grp, 0.0, 3.0);
            float w = dlLabel(LB_CH_A + g, xv, ry, IL_T_BODY * s, ptId((int)g), IL_RIGHT);
            dlRect(float4(xv - w - 14.0 * s, ry - 4.0 * s, xv - w - 6.0 * s, ry + 4.0 * s), ptId((int)g), 1.0, 1.0);
        }
        else
        {
            dlNum(v, dec, xv, ry, val, isTgt ? IL_ACCENT : IL_INK, IL_RIGHT);
            if (unit != NO_UNIT) dlLabel(unit, xu, ry, cap, IL_DIM, IL_LEFT);
        }
    }
    // the record's state: hand edited (value), switched off (value), broken (alarm)
    float fy0 = ba.y + 40.0 * s + rowsN * rowH + 6.0 * s;
    float fx = x0;
    uint fl = (uint)sr.flags;
    if (has || isTgt)
    {
        if ((fl & KF_EDITED) != 0u) fx += kaTag(fx, fy0, s, LB_EDITED, IL_INK, IL_RULE);
        if (has && sr.active < 0.5) fx += kaTag(fx, fy0, s, LB_OFF, IL_MID, IL_RULE);
        if (has && (fl & KF_OVERLAP) != 0u) fx += kaTag(fx, fy0, s, LB_CLASH, IL_ALARM, IL_ALARM);
        if (has && (fl & KF_OUTSIDE) != 0u) kaTag(fx, fy0, s, LB_OUTSIDE, IL_ALARM, IL_ALARM);
    }

    // ---- CELL: the channel and frame legends with live counts, the live target, the totals
    float4 rb = float4(ir.x, ra.w + 8.0 * s, ir.z, ir.w);
    float4 bb = dlPane(rb, s, LB_CELL, false);
    uint4 chanN = uint4(0u, 0u, 0u, 0u);
    uint3 kindN = uint3(0u, 0u, 0u);
    [loop] for (uint i = 0u; i < KA_MAX_ARMS; i++)
    {
        KaRec r = Cell[KA_ARM_0 + i];
        if (r.active < 0.5) continue;
        uint g = (uint)r.grp, kk = (uint)r.kind;
        chanN += uint4(g == 0u, g == 1u, g == 2u, g == 3u);
        kindN += uint3(kk == 0u, kk == 1u, kk == 2u);
    }
    float bx0 = bb.x + 10.0 * s, bx1 = bb.z - 10.0 * s;
    float half = 0.5 * (bx1 - bx0);
    float lx = bx0, fxl = bx0 + half + 6.0 * s;
    float ly = bb.y + 16.0 * s;
    dlLabel(LB_CHANNELS, lx, ly, cap, IL_DIM, IL_LEFT);
    dlLabel(LB_FRAMES, fxl, ly, cap, IL_DIM, IL_LEFT);
    uint used = (uint)max((float)group_count, 1.0);
    [loop] for (uint c = 0u; c < 4u; c++)
    {
        float cy = ly + (c + 1u) * rowH;
        bool on = c < used;
        dlRect(float4(lx, cy - 4.0 * s, lx + 8.0 * s, cy + 4.0 * s), on ? ptId((int)c) : IL_RULE * 0.55, 1.0, 1.0);
        dlLabel(LB_CH_A + c, lx + 14.0 * s, cy, IL_T_BODY * s, on ? IL_MID : IL_RULE, IL_LEFT);
        dlInt((int)chanN[c], 1, bx0 + half - 6.0 * s, cy, val, on ? IL_INK : IL_RULE, IL_RIGHT);
        if (c < 3u)
        {
            dlRect(float4(fxl, cy - 4.0 * s, fxl + 8.0 * s, cy + 4.0 * s), ptRamp(0.30 + (float)c * 0.35), 1.0, 1.0);
            dlLabel(LB_F_COMPACT + c, fxl + 14.0 * s, cy, IL_T_BODY * s, IL_MID, IL_LEFT);
            dlInt((int)kindN[c], 1, bx1, cy, val, IL_INK, IL_RIGHT);
        }
    }
    float sy = ly + 5.0 * rowH - 2.0 * s;
    dlHLine(sy, bb.x + 1.0, bb.z - 1.0, IL_EDGE);

    // the target, always live: the place every Point At arm is aiming. x / z are the ORBITING
    // values, not the anchor, so the numbers move when the mark moves.
    KaRec t = Cell[KA_TARGET];
    float3 tp = ka_targetPos(t);
    bool tsel = ((uint)t.flags & KF_SELECTED) != 0u;
    float ty0 = sy + 14.0 * s;
    float tcw = dlLabel(LB_TARGET, bx0, ty0, cap, tsel ? IL_ACCENT : IL_DIM, IL_LEFT);
    dlLabel(LB_T_LIVE, bx0 + tcw + 8.0 * s, ty0, cap, IL_DIM, IL_LEFT);
    float xuL = bx0 + half - 6.0 * s - ilLabelW(LB_M, cap), xuR = bx1 - ilLabelW(LB_M, cap);
    [loop] for (uint q = 0u; q < 4u; q++)
    {
        bool right = (q & 1u) != 0u;
        float qy = ty0 + (1u + (q >> 1)) * rowH;
        float qx = right ? fxl : bx0;
        float qu = right ? xuR : xuL;
        float qv = (q == 0u) ? tp.x : ((q == 1u) ? tp.z : ((q == 2u) ? tp.y : t.size.y));
        uint qc = (q == 0u) ? LB_R_X : ((q == 1u) ? LB_R_Z : ((q == 2u) ? LB_T_HEIGHT : LB_T_ORBIT));
        dlLabel(qc, qx, qy, cap, IL_DIM, IL_LEFT);
        dlNum(qv, 1, qu - 3.0 * s, qy, val, tsel ? IL_ACCENT : IL_INK, IL_RIGHT);
        dlLabel(LB_M, qu, qy, cap, IL_DIM, IL_LEFT);
    }
    float sy2 = ty0 + 3.0 * rowH - 2.0 * s;
    dlHLine(sy2, bb.x + 1.0, bb.z - 1.0, IL_EDGE);

    // totals: live arms, the clash count that says the cell is broken, the floor and the pitch
    float ty1 = sy2 + 15.0 * s;
    float xr = bx1;
    dlLabel(LB_ARMS, bx0, ty1, cap, IL_DIM, IL_LEFT);
    xr -= dlInt((int)arm_count, 1, xr, ty1, val, IL_MID, IL_RIGHT) + 4.0 * s;
    xr -= dlLabel(LB_OF, xr, ty1, cap, IL_DIM, IL_RIGHT) + 4.0 * s;
    dlInt((int)liveN, 1, xr, ty1, val, IL_INK, IL_RIGHT);
    bool clash = clashN > 0.5;
    dlLabel(LB_CLASHES, bx0, ty1 + rowH, cap, clash ? IL_ALARM : IL_DIM, IL_LEFT);
    dlInt((int)clashN, 1, bx1, ty1 + rowH, val, clash ? IL_ALARM : IL_INK, IL_RIGHT);
    dlLabel(LB_FLOOR, bx0, ty1 + 2.0 * rowH, cap, IL_DIM, IL_LEFT);
    xr = bx1;
    xr -= dlLabel(LB_M, xr, ty1 + 2.0 * rowH, cap, IL_DIM, IL_RIGHT) + 3.0 * s;
    xr -= dlInt((int)(cd + 0.5), 1, xr, ty1 + 2.0 * rowH, val, IL_INK, IL_RIGHT) + 4.0 * s;
    xr -= dlLabel(LB_TIMES, xr, ty1 + 2.0 * rowH, cap, IL_DIM, IL_RIGHT) + 4.0 * s;
    dlInt((int)(cw + 0.5), 1, xr, ty1 + 2.0 * rowH, val, IL_INK, IL_RIGHT);
    dlLabel(LB_PITCH, bx0, ty1 + 3.0 * rowH, cap, IL_DIM, IL_LEFT);
    xr = bx1;
    xr -= dlLabel(LB_M, xr, ty1 + 3.0 * rowH, cap, IL_DIM, IL_RIGHT) + 3.0 * s;
    dlNum(pitch, 1, xr, ty1 + 3.0 * rowH, val, IL_INK, IL_RIGHT);
    dlClipReset();

    // ---- footer: hover, then the module's bindings in the manifest's order; a hint that would not
    // fit is dropped rather than squeezed
    float fyy = 0.5 * (er.w + R.y);
    float hx = pr.x;
    [loop] for (uint b = 0u; b < 11u; b++)
    {
        float hw = kaHintW(s, LB_K_HOVER + b, LB_D_HOVER + b);
        if (hx + hw - 16.0 * s > ir.z) break;
        hx += kaHint(hx, fyy, s, LB_K_HOVER + b, LB_D_HOVER + b);
    }

    // ---- hover: what a click here would select, unless it already is
    float2 uv = _ViewportPointerPosition;
    if (all(uv >= 0.0) && all(uv <= 1.0))
    {
        int strip = kaStrip(uv);
        uint h = (strip == 0) ? 0u : hoverPick(m, uv, strip);
        if (h != 0u && abs((float)h - sel) > 0.5)
        {
            hotRings(h - 1u, m, R, pr, er);
            if (tooltips != 0) hoverCard(h - 1u, uv * R, R);     // Tooltips off: the rings stay, the card goes
        }
    }
    dlFinish();
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    g_s = kaUiScale(_Resolution.xy);
    if (gi == 0u) layout();
    dlEnd(gi);
}
