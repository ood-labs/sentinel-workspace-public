// BR_Shell / layout.hlsl -- the unfolded room's type, dimensions, handles and cards, recorded into
// the shared UI kit's draw list (ui.hlsl draws it over plate.hlsl's drawing). Every position comes
// from shell_layout.hlsli, the same functions shell.hlsl picks and hit-tests with.
//
// On the drawing: each wall's name in its identity tint with its length, the room's name, area and
// ceiling in the plan, and for the selected opening its edge handles, its width / sill / height
// dimensions in its elevation and its chain (corner, opening, corner) along its wall in the plan.
// A small diamond marks every opening a hand has edited.
//
// The four free corners of the cross: the inspector (what is selected, its measures, and chips
// that are the mouse path to every key verb), the room's measures and its alarms (red is a broken
// opening, nothing else), the scale and north, and the key map.
#include "../_shared/br_records.hlsli"
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"
#include "shell_layout.hlsli"

StructuredBuffer<BRRec> ShellBuf : register(t0);

static float gUi;

float3 wallTint(int w) { return ptSampleColour(ptId(w)); }
BROpening opening(int i) { return brOpeningFromRec(ShellBuf[SHELL_OPEN0 + i]); }

// A number and its unit, right-aligned at xr; returns the width used.
float valueRight(float xr, float y, float v, int dec, uint unit, float3 c)
{
    float w = dlLabel(unit, xr, y, IL_T_CAP * gUi, IL_DIM, IL_RIGHT) + 3.0 * gUi;
    return w + dlNum(v, dec, xr - w, y, IL_T_VALUE * gUi, c, IL_RIGHT);
}
// A row: caption left (dim), value + unit right.
void valueRow(float4 r, uint caption, float v, int dec, uint unit, float3 c)
{
    float y = ilMid(r).y;
    float w = valueRight(r.z, y, v, dec, unit, c);
    dlLabelFit(caption, r.x, y, IL_T_BODY * gUi, IL_DIM, IL_LEFT, (r.z - r.x) - w - 6.0 * gUi);
}

// Architectural dimension line: the run plus 45-degree slashes at both ends.
void dimLine(float2 a, float2 b, float3 c)
{
    float2 dir = normalize(b - a + 1e-6);
    float2 sl = (dir + float2(-dir.y, dir.x)) * 0.7071 * 4.0 * gUi;
    dlLine(a, b, 1.0, c, 1.0);
    dlLine(a - sl, a + sl, 1.4, c, 1.0);
    dlLine(b - sl, b + sl, 1.4, c, 1.0);
}

// Key-map hints: a keycap and what it does.
float hintW(uint key, uint does) { return ilLabelW(key, IL_T_CAP * gUi) + 12.0 * gUi + 6.0 * gUi + ilLabelW(does, IL_T_CAP * gUi) + 14.0 * gUi; }
float hint(float x, float y, uint key, uint does)
{
    float kw = ilLabelW(key, IL_T_CAP * gUi) + 12.0 * gUi, kh = 17.0 * gUi;
    dlKeycap(float4(x, y - 0.5 * kh, x + kw, y + 0.5 * kh), gUi, key);
    return kw + 6.0 * gUi + dlLabel(does, x + kw + 6.0 * gUi, y, IL_T_CAP * gUi, IL_DIM, IL_LEFT) + 14.0 * gUi;
}
// The key map, a row at a time: up to two (key, what it does) pairs, right-aligned.
// (rows 3-5 have two pairs; every id stays in range, because FXC folds both sides of a select)
uint mapKey(int row, int j)
{
    uint second = (row == 4) ? LB_KEY_C : (row == 5) ? LB_KEY_0 : LB_KEY_X;
    uint first = (row == 0) ? LB_K_CLICK : (row <= 2) ? LB_K_DRAG : (row == 3) ? LB_KEY_K : (row == 4) ? LB_KEY_A : (row == 5) ? LB_KEY_R : LB_KEY_ESC;
    return (j == 1) ? second : first;
}
uint mapDoes(int row, int j)
{
    uint second = (row == 3) ? LB_D_TOGGLE : (row == 4) ? LB_D_CURT : LB_D_RALL;
    uint first = (row == 0) ? LB_D_SELECT : (row == 1) ? LB_D_MOVE : (row == 2) ? LB_D_FACE : (row == 3) ? LB_D_KIND : (row == 4) ? LB_D_ADD : (row == 5) ? LB_D_RESET : LB_D_ESC;
    return (j == 1) ? second : first;
}

// An inspector chip: the verb centred, its key at the right.
void chip(float4 r, uint verb, uint key, bool hot, bool down)
{
    dlChip(r, gUi, verb, false, hot, down);
    dlLabel(key, r.z - 8.0 * gUi, ilMid(r).y, IL_T_CAP * gUi, IL_DIM, IL_RIGHT);
}

void layout()
{
    float2 res = _Resolution.xy;
    BRRoom r = brRoomFromRec(ShellBuf[SHELL_ROOM]);
    BRRec ed = ShellBuf[SHELL_EDITOR];
    BRRec fz = ShellBuf[14];
    int selType = (int)round(ed.head.y);
    int selIndex = (int)round(ed.head.z);
    bool selOpen = selType == 1 && selIndex >= 0 && selIndex < SHELL_OPEN_MAX;
    BROpening so = opening(selOpen ? selIndex : 0);       // the selected opening (valid when selOpen)
    ShellLayout L = shellLayout(res, r, fz.dims, fz.look.zw);
    gUi = L.ui;
    float ui = gUi;
    float2 ptr = _ViewportPointerPosition * res;
    bool down = (_ViewportButtons & 1u) != 0u;
    dlBegin(res);

    // ---- title strip
    float hy = ilMid(float4(0, 0, res.x, L.header)).y;
    float x = 14.0 * ui;
    x += dlLabel(LB_TITLE, x, hy, 15.0 * ui, IL_INK, IL_LEFT) + 14.0 * ui;
    x += dlLabel(LB_SUB, x, hy, IL_T_BODY * ui, IL_DIM, IL_LEFT) + 22.0 * ui;
    x += dlLabel(LB_STYLE0 + (uint)clamp(r.style, 0, 3), x, hy, IL_T_BODY * ui, IL_MID, IL_LEFT) + 22.0 * ui;
    float dims3[3] = { r.x1 - r.x0, r.z1 - r.z0, r.H };
    [unroll] for (int k = 0; k < 3; k++)
    {
        x += dlNum(dims3[k], 2, x, hy, IL_T_VALUE * ui, IL_INK, IL_LEFT) + 5.0 * ui;
        if (k < 2) x += dlLabel(LB_X, x, hy, IL_T_CAP * ui, IL_DIM, IL_LEFT) + 5.0 * ui;
    }
    dlLabel(LB_M, x - 2.0 * ui, hy, IL_T_CAP * ui, IL_DIM, IL_LEFT);
    dlHLine(L.header - 0.5, 0.0, res.x, IL_RULE);

    // ---- wall names and lengths, outside each elevation, in the wall's identity tint
    [loop] for (int w = 0; w < 4; w++)
    {
        float4 er = shellElevRect(L, w);
        float2 span = shellWallSpan(L, w);
        float len = span.y - span.x;
        float nw = ilLabelW(LB_WALL0 + (uint)w, IL_T_TITLE * ui) + 10.0 * ui + ilNumW(ilFormat(len, 2, 1, false).n, IL_T_VALUE * ui) + 3.0 * ui + ilLabelW(LB_M, IL_T_CAP * ui);
        float y = (w == WALL_S) ? er.w + 13.0 * ui : er.y - 13.0 * ui;
        float nx = 0.5 * (er.x + er.z) - 0.5 * nw;
        nx += dlLabel(LB_WALL0 + (uint)w, nx, y, IL_T_TITLE * ui, wallTint(w), IL_LEFT) + 10.0 * ui;
        nx += dlNum(len, 2, nx, y, IL_T_VALUE * ui, IL_DIM, IL_LEFT) + 3.0 * ui;
        dlLabel(LB_M, nx, y, IL_T_CAP * ui, IL_DIM, IL_LEFT);
    }

    // ---- the room in the plan: name, floor area, ceiling
    {
        float2 ctr = shellPlanPx(L, float2((r.x0 + r.x1) * 0.5, (r.z0 + r.z1) * 0.5));
        float area = (r.x1 - r.x0) * (r.z1 - r.z0);
        dlLabel(LB_ROOMNAME, ctr.x, ctr.y - 17.0 * ui, IL_T_TITLE * ui, IL_INK, IL_CENTER);
        float wa = ilNumW(ilFormat(area, 1, 1, false).n, IL_T_VALUE * ui) + 4.0 * ui + ilLabelW(LB_SQM, IL_T_CAP * ui);
        float ax = ctr.x - 0.5 * wa;
        ax += dlNum(area, 1, ax, ctr.y, IL_T_VALUE * ui, IL_MID, IL_LEFT) + 4.0 * ui;
        dlLabel(LB_SQM, ax, ctr.y, IL_T_CAP * ui, IL_DIM, IL_LEFT);
        float wc = ilLabelW(LB_CLG, IL_T_CAP * ui) + 5.0 * ui + ilNumW(ilFormat(r.H, 2, 1, false).n, IL_T_VALUE * ui) + 3.0 * ui + ilLabelW(LB_M, IL_T_CAP * ui);
        float cx = ctr.x - 0.5 * wc;
        cx += dlLabel(LB_CLG, cx, ctr.y + 17.0 * ui, IL_T_CAP * ui, IL_DIM, IL_LEFT) + 5.0 * ui;
        cx += dlNum(r.H, 2, cx, ctr.y + 17.0 * ui, IL_T_VALUE * ui, IL_DIM, IL_LEFT) + 3.0 * ui;
        dlLabel(LB_M, cx, ctr.y + 17.0 * ui, IL_T_CAP * ui, IL_DIM, IL_LEFT);
    }

    // ---- hand-edited openings: a small diamond in the corner of their elevation
    [loop] for (int e = 0; e < SHELL_OPEN_MAX; e++)
    {
        BROpening o = opening(e);
        if (o.active && o.edited)
        {
            float2 mk = shellElevPx(L, o.wall, o.a + o.width * 0.5 - 0.06, o.sill + o.height - 0.06);
            dlDiamond(mk, max(0.035 * L.s, 3.0 * ui), 0.0, (selOpen && selIndex == e) ? IL_ACCENT : IL_INK, 1.0);
        }
    }

    // ---- the selected opening: dimensions in its elevation, its chain in the plan, edge handles
    if (selOpen && so.active)
    {
        BROpening o = so;
        int w = o.wall;
        float hw = o.width * 0.5;
        bool horiz = (w == WALL_N || w == WALL_S);
        float vs = IL_T_VALUE * ui;
        // width, above the opening (beyond its curtain rod)
        float dimY = o.sill + o.height + (o.curtains ? 0.34 : 0.22);
        float2 pa = shellElevPx(L, w, o.a - hw, dimY), pb = shellElevPx(L, w, o.a + hw, dimY);
        dimLine(pa, pb, IL_INK);
        float2 tOff = horiz ? float2(0, (w == WALL_N) ? -11.0 * ui : 11.0 * ui) : float2((w == WALL_W) ? -24.0 * ui : 24.0 * ui, 0);
        float2 mid = 0.5 * (pa + pb) + tOff;
        dlNum(o.width, 2, mid.x, mid.y, vs, IL_INK, IL_CENTER);
        // sill and height, on its low-a side
        float dimA = o.a - hw - 0.22;
        float2 v0 = shellElevPx(L, w, dimA, 0.0), v1 = shellElevPx(L, w, dimA, o.sill), v2 = shellElevPx(L, w, dimA, o.sill + o.height);
        float2 sOff = horiz ? float2(-24.0 * ui, 0) : float2(0, 11.0 * ui);
        if (o.sill > 0.01)
        {
            dimLine(v0, v1, IL_DIM);
            float2 m1 = 0.5 * (v0 + v1) + sOff;
            dlNum(o.sill, 2, m1.x, m1.y, vs, IL_DIM, IL_CENTER);
        }
        dimLine(v1, v2, IL_INK);
        float2 m2 = 0.5 * (v1 + v2) + sOff;
        dlNum(o.height, 2, m2.x, m2.y, vs, IL_INK, IL_CENTER);

        // the chain along its wall in the plan: corner -> opening -> corner, the opening in accent
        float2 ext = brWallExtent(r, w);
        float off = 0.62;
        float stops[4] = { ext.x, o.a - hw, o.a + hw, ext.y };
        [loop] for (int c = 0; c < 3; c++)
        {
            float s0 = stops[c], s1 = stops[c + 1];
            if (s1 - s0 >= 0.02)
            {
                float3 cc = (c == 1) ? IL_ACCENT : IL_INK;
                dimLine(shellPlanPx(L, brWallPoint(r, w, s0, off)), shellPlanPx(L, brWallPoint(r, w, s1, off)), cc);
                float2 mp = shellPlanPx(L, brWallPoint(r, w, 0.5 * (s0 + s1), off + 0.18));
                dlNum(s1 - s0, 2, mp.x, mp.y, vs, cc, IL_CENTER);
            }
        }

        // edge handles (the reducer grabs within 7 px of these edges)
        float2 hp[4] = { float2(o.a - hw, o.sill + o.height * 0.5), float2(o.a + hw, o.sill + o.height * 0.5),
                         float2(o.a, o.sill + o.height), float2(o.a, o.sill) };
        int nh = (brOpenToFloor(o.kind) || o.kind == OPEN_FIREPLACE) ? 3 : 4;
        float hs = 4.0 * ui;
        [loop] for (int h = 0; h < nh; h++)
        {
            float2 q = shellElevPx(L, w, hp[h].x, hp[h].y);
            dlRectEdged(float4(q - hs, q + hs), IL_FIELD, 1.0, 0.0, IL_ACCENT, 1.2);
        }
    }

    // ---- TL: the inspector
    float4 card = shellInspectorRect(L);
    dlRectEdged(card, IL_PANEL, 0.96, IL_RADIUS * ui, IL_EDGE, 1.0);
    if (selOpen)
    {
        BROpening o = so;
        float4 r0 = shellInspectorRow(L, 0);
        dlLabelFit(LB_K0 + (uint)clamp(o.kind, 0, 7), r0.x, ilMid(r0).y, IL_T_TITLE * ui, IL_ACCENT, IL_LEFT, r0.z - r0.x);
        float4 r1 = shellInspectorRow(L, 1);
        float y1 = ilMid(r1).y;
        float wx = r1.x + dlLabel(LB_WALL0 + (uint)clamp(o.wall, 0, 3), r1.x, y1, IL_T_TITLE * ui, wallTint(o.wall), IL_LEFT) + 5.0 * ui;
        dlLabel(LB_WALLWORD, wx, y1, IL_T_BODY * ui, IL_DIM, IL_LEFT);
        dlLabel(o.edited ? LB_EDITED : LB_GENERATED, r1.z, y1, IL_T_BODY * ui, o.edited ? IL_INK : IL_DIM, IL_RIGHT);
        float2 ext = brWallExtent(r, o.wall);
        float fromC = min(o.a - o.width * 0.5 - ext.x, ext.y - o.a - o.width * 0.5);
        [loop] for (int m = 0; m < 4; m++)
        {
            uint cap = (m == 0) ? LB_W : (m == 1) ? ((o.kind == OPEN_FIREPLACE) ? LB_MANTEL : LB_H) : (m == 2) ? LB_SILL : LB_FROM;
            float v = (m == 0) ? o.width : (m == 1) ? o.height : (m == 2) ? o.sill : fromC;
            valueRow(shellInspectorRow(L, 2 + m), cap, v, 2, LB_M, IL_INK);
        }
        if (brOpenIsGlazed(o.kind))
        {
            float4 r6 = shellInspectorRow(L, 6);
            dlLabel(LB_CURT, r6.x, ilMid(r6).y, IL_T_BODY * ui, IL_DIM, IL_LEFT);
            dlLabel(o.curtains ? LB_ON : LB_OFF, r6.z, ilMid(r6).y, IL_T_BODY * ui, o.curtains ? IL_INK : IL_DIM, IL_RIGHT);
        }
    }
    else if (selType == 2 || selType == 3)
    {
        int w = clamp(selIndex, 0, 3);
        float4 r0 = shellInspectorRow(L, 0);
        dlLabel((selType == 2) ? LB_WALLSEL : LB_CEILING, r0.x, ilMid(r0).y, IL_T_TITLE * ui, IL_ACCENT, IL_LEFT);
        float4 r1 = shellInspectorRow(L, 1);
        float wx = r1.x + dlLabel(LB_WALL0 + (uint)w, r1.x, ilMid(r1).y, IL_T_TITLE * ui, wallTint(w), IL_LEFT) + 5.0 * ui;
        dlLabel(LB_WALLWORD, wx, ilMid(r1).y, IL_T_BODY * ui, IL_DIM, IL_LEFT);
        if (selType == 2) valueRow(shellInspectorRow(L, 2), LB_LENGTH, brWallLength(r, w), 2, LB_M, IL_INK);
        else valueRow(shellInspectorRow(L, 2), LB_CEIL_H, r.H, 2, LB_M, IL_INK);
        float4 r4 = shellInspectorRow(L, 4);
        dlLabelFit((selType == 2) ? LB_DRAG_WALL : LB_DRAG_CEIL, r4.x, ilMid(r4).y, IL_T_CAP * ui, IL_DIM, IL_LEFT, r4.z - r4.x);
    }
    else
    {
        float4 r0 = shellInspectorRow(L, 0);
        dlLabel(LB_NOSEL, r0.x, ilMid(r0).y, IL_T_TITLE * ui, IL_DIM, IL_LEFT);
        float4 r1 = shellInspectorRow(L, 1);
        dlLabelFit(LB_NOSEL_HINT, r1.x, ilMid(r1).y, IL_T_CAP * ui, IL_DIM, IL_LEFT, r1.z - r1.x);
    }
    // its chips: the mouse path to every key verb, from the rects shell.hlsl hit-tests
    int hotChip = shellChipAt(L, ptr);
    // (shell.hlsl's chipVerb is the same table; every label id stays in range, FXC folds selects)
    [unroll] for (int ck = 0; ck < 4; ck++)
    {
        bool show = (selType == 1) ? (ck != 2 || (selOpen && brOpenIsGlazed(so.kind)))
                  : (selType == 2) ? (ck == 0 || ck == 3)
                  : (ck == 3);
        uint verb = (selType == 1) ? ((ck == 0) ? LB_CH_KIND : (ck == 1) ? LB_CH_TOGGLE : (ck == 2) ? LB_CH_CURT : LB_CH_RESET)
                  : (selType == 2) ? ((ck == 0) ? LB_CH_ADD : LB_CH_RROOM)
                  : (selType == 3) ? LB_CH_RROOM : LB_CH_RALL;
        uint key = (selType == 1) ? ((ck == 0) ? LB_KEY_K : (ck == 1) ? LB_KEY_X : (ck == 2) ? LB_KEY_C : LB_KEY_R)
                 : (selType == 2) ? ((ck == 0) ? LB_KEY_A : LB_KEY_R)
                 : (selType == 3) ? LB_KEY_R : LB_KEY_0;
        if (show) chip(shellChipRect(L, ck), verb, key, hotChip == ck, hotChip == ck && down);
    }

    // ---- TR: the room's measures and its alarms
    {
        int nOpen = 0, nAl = 0;
        [loop] for (int c = 0; c < SHELL_OPEN_MAX; c++) { BROpening oc = opening(c); nOpen += oc.active ? 1 : 0; nAl += (oc.active && oc.alarms != 0) ? 1 : 0; }
        int shown = min(nAl, 5);
        float rh = SHELL_ROW_H * ui, pad = 10.0 * ui;
        float2 mx = shellMeasuresX(L);
        float top = L.header + SHELL_PAD * ui;
        float4 mc = float4(mx.x, top, mx.y, top + 8.0 * ui + (6.0 + (float)shown) * rh + 6.0 * ui + 8.0 * ui);
        dlRectEdged(mc, IL_PANEL, 0.96, IL_RADIUS * ui, IL_EDGE, 1.0);
        float area = (r.x1 - r.x0) * (r.z1 - r.z0);
        float perim = 2.0 * ((r.x1 - r.x0) + (r.z1 - r.z0));
        float4 row = float4(mc.x + pad, mc.y + 8.0 * ui, mc.z - pad, mc.y + 8.0 * ui + rh);
        dlLabel(LB_ROOM, row.x, ilMid(row).y, IL_T_TITLE * ui, IL_DIM, IL_LEFT);
        [loop] for (int m = 0; m < 3; m++)
        {
            row += float4(0, rh, 0, rh);
            uint cap = (m == 0) ? LB_AREA : (m == 1) ? LB_PERIM : LB_VOLUME;
            uint unit = (m == 0) ? LB_SQM : (m == 1) ? LB_M : LB_CUM;
            float v = (m == 0) ? area : (m == 1) ? perim : area * r.H;
            valueRow(row, cap, v, (m == 1) ? 2 : 1, unit, IL_INK);
        }
        row += float4(0, rh, 0, rh);
        dlLabel(LB_OPENINGS, row.x, ilMid(row).y, IL_T_BODY * ui, IL_DIM, IL_LEFT);
        dlInt(nOpen, 1, row.z, ilMid(row).y, IL_T_VALUE * ui, IL_INK, IL_RIGHT);
        row += float4(0, rh + 6.0 * ui, 0, rh + 6.0 * ui);
        dlHLine(row.y - 3.0 * ui, row.x, row.z, IL_GRID);
        dlLabel(LB_ALARMS, row.x, ilMid(row).y, IL_T_TITLE * ui, (nAl > 0) ? IL_ALARM : IL_DIM, IL_LEFT);
        if (nAl == 0) dlLabel(LB_CLEAR, row.z, ilMid(row).y, IL_T_BODY * ui, IL_DIM, IL_RIGHT);
        else dlInt(nAl, 1, row.z, ilMid(row).y, IL_T_VALUE * ui, IL_ALARM, IL_RIGHT);
        int listed = 0;
        [loop] for (int s = 0; s < SHELL_OPEN_MAX; s++)
        {
            BROpening o = opening(s);
            if (o.active && o.alarms != 0 && listed < 5)
            {
                float4 ar = row + float4(0, rh * (1.0 + listed), 0, rh * (1.0 + listed));
                uint why = ((o.alarms & ALARM_OVERLAP) != 0) ? LB_A_OVERLAP : ((o.alarms & ALARM_HEAD) != 0) ? LB_A_HEAD : ((o.alarms & ALARM_TOO_WIDE) != 0) ? LB_A_WIDE : LB_A_CORNER;
                dlLabel(LB_WALL0 + (uint)clamp(o.wall, 0, 3), ar.x, ilMid(ar).y, IL_T_TITLE * ui, IL_ALARM, IL_LEFT);
                dlLabel(why, ar.z, ilMid(ar).y, IL_T_BODY * ui, IL_ALARM, IL_RIGHT);
                listed++;
            }
        }
    }

    // ---- BL: the scale (two metres) and north
    {
        float pad = SHELL_PAD * ui;
        float2 bl = float2(max(shellPX(L, L.x0) - shellCornerW(L) + pad, pad), res.y - pad - 12.0 * ui);
        float th = 3.0 * ui;
        dlRect(float4(bl.x, bl.y - th, bl.x + L.s, bl.y + th), IL_INK, 1.0, 0.0);
        dlRect(float4(bl.x + L.s, bl.y - th, bl.x + 2.0 * L.s, bl.y + th), IL_RULE, 1.0, 0.0);
        dlBorderRect(float4(bl.x, bl.y - th, bl.x + 2.0 * L.s, bl.y + th), 0.0, IL_MID, 1.0);
        dlLabel(LB_SCALE, bl.x, bl.y - 13.0 * ui, IL_T_CAP * ui, IL_DIM, IL_LEFT);
        float2 na = bl + float2(2.0 * L.s + 30.0 * ui, -6.0 * ui);
        dlTri(na + float2(0, -18.0 * ui), 5.5 * ui, 12.0 * ui, 1u, IL_INK, 1.0);
        dlLine(na + float2(0, -6.0 * ui), na + float2(0, 8.0 * ui), 1.5, IL_MID, 1.0);
        dlLabel(LB_NORTH, na.x, na.y + 17.0 * ui, IL_T_TITLE * ui, IL_INK, IL_CENTER);
    }

    // ---- BR: the key map
    {
        float pad = SHELL_PAD * ui, ph = 19.0 * ui;
        float xr = min(shellPX(L, L.x1) + shellCornerW(L), res.x) - pad;
        [loop] for (int row = 0; row < 7; row++)
        {
            float y = res.y - pad - (6.5 - (float)row) * ph;
            bool two = row >= 3 && row <= 5;
            float x = xr + 14.0 * ui - hintW(mapKey(row, 0), mapDoes(row, 0)) - (two ? hintW(mapKey(row, 1), mapDoes(row, 1)) : 0.0);
            [loop] for (int j = 0; j < (two ? 2 : 1); j++) x += hint(x, y, mapKey(row, j), mapDoes(row, j));
        }
    }

    dlFinish();
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    if (gi == 0u) layout();
    dlEnd(gi);
}
