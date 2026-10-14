// BR_Furnish / layout.hlsl -- the furnishing plan's chrome, readouts, handles and type, recorded
// into the shared UI kit's draw list (ui.hlsl draws it over plate.hlsl's plan and section). Every
// rect and transform comes from furnish_layout.hlsli, the same functions furnish.hlsl picks with.
//
// PLAN overlays: the section cut A-A with its arrows at the wall being drawn; the route from the
// door to the windows with its narrowest point dimensioned; the conversation circle; the
// coffee-table gap; the north arrow and a 1 m bar; and on top, the selection's family (dotted to
// its parent and to everything hanging off it) and its handles (turn knob, width and depth grips),
// in the accent because they are the selection's, heavier while held.
// SECTION: the wall it looks at and the cut depth. INSPECTOR: the selected piece's kind, variant,
// size, place, turn, host, materials and tags, the keys, and the four chips. RULES: each design
// rule's live reading against its target band, red when broken.
#include "../_shared/br_records.hlsli"
#include "../_shared/br_furn_defs.hlsli"
#include "furnish_defs.hlsli"
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"
#include "furnish_layout.hlsli"

StructuredBuffer<BRRec> FurnBuf : register(t0);

// the reducer's handle ids (furnish.hlsl H_*)
#define FH_ROT   2
#define FH_WIDTH 3
#define FH_DEPTH 4

BRRec sh(uint i) { BRRec r; r.head = _Data0[i].head; r.dims = _Data0[i].dims; r.look = _Data0[i].look; r.meta = _Data0[i].meta; return r; }

uint kindLabel(int k) { return LB_K0 + (uint)clamp(k, 0, 16); }
uint matLabel(int m) { return LB_M0 + (uint)clamp(m, 0, 23); }
uint wallLabel(int w) { return LB_WALL0 + (uint)clamp(w, 0, 3); }
uint variantLabel(int k, int v)
{
    uint first = (k == 1) ? LB_V1_0 : (k == 2) ? LB_V2_0 : (k == 3) ? LB_V3_0 : (k == 4) ? LB_V4_0 : (k == 5) ? LB_V5_0
               : (k == 6) ? LB_V6_0 : (k == 7) ? LB_V7_0 : (k == 8) ? LB_V8_0 : (k == 9) ? LB_V9_0 : (k == 10) ? LB_V10_0
               : (k == 11) ? LB_V11_0 : (k == 12) ? LB_V12_0 : (k == 13) ? LB_V13_0 : (k == 14) ? LB_V14_0 : (k == 15) ? LB_V15_0 : LB_V16_0;
    int n = (k == 7 || k == 9 || k == 13) ? 2 : ((k == 10 || k >= 14) ? 1 : 3);
    return first + (uint)clamp(v, 0, n - 1);
}

float2 halfWDf(FPiece p)
{
    if (p.kind == FK_FLOORLAMP && p.variant == 0) return float2(0.17, 0.17);
    float2 h = p.size.xz * 0.5;
    if (p.kind == FK_COFFEE && p.variant != 0) h = float2(p.size.x, p.size.x) * 0.5;
    return h;
}

// A key and what it does; returns the width used. hintW measures it without drawing.
float hintW(float s, uint key, uint does) { return ilLabelW(key, IL_T_CAP * s) + 34.0 * s + ilLabelW(does, IL_T_CAP * s); }
float hint(float x, float y, float s, uint key, uint does)
{
    float kw = ilLabelW(key, IL_T_CAP * s) + 12.0 * s, kh = 18.0 * s;
    dlKeycap(float4(x, y - 0.5 * kh, x + kw, y + 0.5 * kh), s, key);
    return kw + 6.0 * s + dlLabel(does, x + kw + 6.0 * s, y, IL_T_CAP * s, IL_DIM, IL_LEFT) + 16.0 * s;
}
// A number and its unit (unit in the caption size); returns the width.
float numUnit(float v, int dec, uint unit, float x, float y, float s, float3 ink)
{
    float w = dlNum(v, dec, x, y, IL_T_VALUE * s, ink, IL_LEFT) + 3.0 * s;
    return w + dlLabel(unit, x + w, y, IL_T_CAP * s, IL_DIM, IL_LEFT);
}
// The edge and header rule of a pane whose card the plate drew; returns its header strip.
float4 paneEdge(float4 r, float s)
{
    dlBorderRect(r, IL_RADIUS * s, IL_EDGE, 1.0);
    float4 h = ilPaneHead(r, s);
    dlHLine(h.w, h.x + 1.0, h.z - 1.0, IL_EDGE);
    return h;
}
// The triangle direction (il_draw: 0 down, 1 up, 2 left, 3 right) nearest a screen direction.
uint triDir(float2 d) { return (abs(d.x) > abs(d.y)) ? ((d.x > 0.0) ? 3u : 2u) : ((d.y > 0.0) ? 0u : 1u); }

void layout()
{
    float2 res = _Resolution.xy;
    bool haveShell = _Data0_Count >= 13u && abs(_Data0[0].head.x - ROLE_ROOM) < 0.5;
    BRRoom r = brDefaultRoom();
    if (haveShell) r = brRoomFromRec(sh(0));
    FLayout L = fLayout(res, r);
    float s = L.ui;
    float cap = IL_T_CAP * s, body = IL_T_BODY * s, val = IL_T_VALUE * s, ttl = IL_T_TITLE * s;
    float2 ptr = _ViewportPointerPosition * res;
    bool down = (_ViewportButtons & 1u) != 0u;

    BRRec ed = FurnBuf[FURN_EDITOR];
    int sel = (int)round(ed.head.y);
    if (sel < -1 || sel >= FS_COUNT) sel = -1;
    int secWall = clamp((int)round(ed.head.z), 0, 3);
    float cutD = ed.meta.w;
    bool dragging = ed.dims.x > 0.5;
    int handle = (int)round(ed.dims.y);
    BRRec rules = FurnBuf[FURN_RULES];
    int ruleBits = (int)round(rules.head.w);
    int routeN = clamp((int)round(rules.head.z), 0, FURN_ROUTE_N);

    int nPieces = 0, nEdited = 0, nAlarm = 0;
    [loop] for (int ci = 0; ci < FS_COUNT; ci++)
    {
        FPiece c = fpFromRec(FurnBuf[ci]);
        if (!fpVisible(c)) continue;
        nPieces++;
        if ((c.flags & FF_EDITED) != 0) nEdited++;
        if ((c.flags & FF_ALARM) != 0) nAlarm++;
    }

    dlBegin(res);

    // ---- title strip: the arrangement and the counts
    {
        float hy = 0.5 * L.header;
        float x = 14.0 * s;
        x += dlLabel(LB_TITLE, x, hy, 15.0 * s, IL_INK, IL_LEFT) + 14.0 * s;
        x += dlLabel(LB_SUB, x, hy, body, IL_DIM, IL_LEFT) + 22.0 * s;
        x += dlLabel(LB_ARR0 + (uint)clamp(arrangement, 0, 3), x, hy, ttl, IL_INK, IL_LEFT) + 8.0 * s;
        dlLabel(LB_LAY0 + (uint)clamp(layering, 0, 2), x, hy, body, IL_MID, IL_LEFT);
        float xr = res.x - 14.0 * s;
        bool alarms = nAlarm > 0;
        xr -= dlLabel(LB_ALARMS, xr, hy, cap, alarms ? IL_ALARM : IL_DIM, IL_RIGHT) + 4.0 * s;
        xr -= dlInt(nAlarm, 1, xr, hy, val, alarms ? IL_ALARM : IL_INK, IL_RIGHT) + 16.0 * s;
        xr -= dlLabel(LB_EDITED, xr, hy, cap, IL_DIM, IL_RIGHT) + 4.0 * s;
        xr -= dlInt(nEdited, 1, xr, hy, val, IL_INK, IL_RIGHT) + 16.0 * s;
        xr -= dlLabel(LB_PIECES, xr, hy, cap, IL_DIM, IL_RIGHT) + 4.0 * s;
        dlInt(nPieces, 1, xr, hy, val, IL_INK, IL_RIGHT);
    }

    // =========================================================================================
    // PLAN pane: edge, title and the gestures, then the overlays clipped to its body
    {
        float4 h = paneEdge(L.planPane, s);
        float hy = ilMid(h).y, xEnd = h.z - 10.0 * s;
        float x = h.x + 10.0 * s;
        x += dlLabel(LB_PLAN, x, hy, ttl, IL_DIM, IL_LEFT) + 18.0 * s;
        if (x + hintW(s, LB_K_CLICK, LB_D_CLICK) <= xEnd) x += hint(x, hy, s, LB_K_CLICK, LB_D_CLICK);
        if (x + hintW(s, LB_K_DRAG, LB_D_DRAG) <= xEnd) x += hint(x, hy, s, LB_K_DRAG, LB_D_DRAG);
        if (x + ilLabelW(LB_D_REHOST, cap) <= xEnd) dlLabel(LB_D_REHOST, x, hy, cap, IL_DIM, IL_LEFT);
    }
    dlClip(L.planR);

    // section cut A-A, arrows pointing at the wall being drawn
    {
        float2 e = brWallExtent(r, secWall);
        float2 a0 = brWallPoint(r, secWall, e.x, cutD), a1 = brWallPoint(r, secWall, e.y, cutD);
        float2 Pa = fPlanPx(L, a0), Pb = fPlanPx(L, a1);
        float2 dir = normalize(Pb - Pa + 1e-6);
        dlDashed(Pa, Pb, 1.0, IL_DIM, 0.9, 8.7 * s, 5.3 * s);
        float2 nP = normalize(fPlanPx(L, a0 - brWallNormal(secWall)) - Pa + 1e-6);
        [unroll] for (int e2 = 0; e2 < 2; e2++)
        {
            float2 c = (e2 == 0) ? Pa - dir * 10.0 * s : Pb + dir * 10.0 * s;
            dlLine(c, c + nP * 4.0 * s, 1.3, IL_INK, 1.0);
            dlTri(c + nP * 9.0 * s, 3.2 * s, 7.0 * s, triDir(nP), IL_INK, 1.0);
            float2 t = c - nP * 9.0 * s;
            dlLabel(LB_CUT, t.x, t.y, cap, IL_DIM, IL_CENTER);
        }
    }
    // the route from the door to the windows, its narrowest point dimensioned
    if (routeN >= 2)
    {
        bool bad = (ruleBits & (RULE_WALKWAY | RULE_BLOCKED)) != 0;
        float3 rc = bad ? IL_ALARM : IL_INK;
        [loop] for (int ri = 0; ri + 1 < routeN; ri++)
        {
            BRRec ra = FurnBuf[FURN_ROUTE0 + ri / 2], rb = FurnBuf[FURN_ROUTE0 + (ri + 1) / 2];
            float2 a = ((ri % 2) == 0) ? ra.dims.xy : ra.dims.zw;
            float2 b = (((ri + 1) % 2) == 0) ? rb.dims.xy : rb.dims.zw;
            dlDashed(fPlanPx(L, a), fPlanPx(L, b), 1.4 * s, rc, bad ? 1.0 : 0.75, 5.5 * s, 4.5 * s);
        }
        float wv = rules.dims.z;
        if (wv > 0.0)
        {
            float2 Pn = fPlanPx(L, rules.look.zw);
            dlRing(Pn, 4.0 * s, 1.4, rc, 1.0);
            numUnit(wv, 2, LB_M, Pn.x + 8.0 * s, Pn.y - 9.0 * s, s, rc);
        }
    }
    // the conversation circle
    if (rules.dims.y > 0.1)
    {
        bool bad = (ruleBits & RULE_CONVERSE) != 0;
        float2 Pc = fPlanPx(L, rules.look.xy);
        float rad = rules.dims.y * 0.5 * L.s;
        float dash = 3.14159 * rad / 48.0;
        dlEllipse(Pc, float2(rad, rad), 1.0, bad ? IL_ALARM : PT_RULE * 1.9, 1.0, dash, dash);
        dlLabel(LB_R_CONV, Pc.x - rad * 0.74 - 4.0 * s, Pc.y - rad * 0.74 - 7.0 * s, cap, bad ? IL_ALARM : IL_DIM, IL_RIGHT);
    }
    // the coffee-table gap, dimensioned from the sofa's front
    {
        FPiece sofa = fpFromRec(FurnBuf[FS_SOFA]);
        if (fpVisible(sofa) && rules.dims.x > -0.5)
        {
            bool bad = (ruleBits & RULE_COFFEE) != 0;
            float3 gc = bad ? IL_ALARM : IL_INK * 0.8;
            float2 a = sofa.pos + fwd2(sofa.yaw) * sofa.size.z * 0.5 + right2(sofa.yaw) * (sofa.size.x * 0.5 - 0.30);
            float2 b = a + fwd2(sofa.yaw) * max(rules.dims.x, 0.0);
            float2 Pa = fPlanPx(L, a), Pb = fPlanPx(L, b);
            float2 dir = normalize(Pb - Pa + 1e-6), side = float2(-dir.y, dir.x);
            float2 sl = (dir + side) * 0.7071 * 4.0 * s;
            dlLine(Pa, Pb, 1.0, gc, 1.0);
            dlLine(Pa - sl, Pa + sl, 1.4, gc, 1.0);
            dlLine(Pb - sl, Pb + sl, 1.4, gc, 1.0);
            float2 m = (Pa + Pb) * 0.5;
            numUnit(rules.dims.x, 2, LB_M, m.x + 6.0 * s, m.y, s, bad ? IL_ALARM : IL_INK);
        }
    }
    // the north arrow and a 1 m bar
    {
        float2 na = float2(L.planR.z - 22.0 * s, L.planR.y + 30.0 * s);
        dlRing(na, 11.0 * s, 1.0, IL_DIM, 1.0);
        dlTri(na - float2(0.0, 9.0 * s), 3.6 * s, 8.0 * s, 1u, IL_INK, 1.0);
        dlLabel(LB_N, na.x, na.y + 4.0 * s, cap, IL_INK, IL_CENTER);
        float2 sb = float2(L.planR.x + 14.0 * s, L.planR.w - 14.0 * s);
        float2 se = sb + float2(L.s, 0.0);
        float2 sl = float2(0.7071, -0.7071) * 4.0 * s;
        dlLine(sb, se, 1.0, IL_DIM, 1.0);
        dlLine(sb - sl, sb + sl, 1.4, IL_DIM, 1.0);
        dlLine(se - sl, se + sl, 1.4, IL_DIM, 1.0);
        float x = se.x + 6.0 * s;
        x += dlInt(1, 1, x, sb.y, val, IL_DIM, IL_LEFT) + 3.0 * s;
        dlLabel(LB_M, x, sb.y, cap, IL_DIM, IL_LEFT);
    }
    // the selection: its family, then its handles on top
    if (sel >= 0)
    {
        FPiece p = fpFromRec(FurnBuf[sel]);
        if ((p.flags & FF_HIDDEN) == 0)
        {
            float2 Pc = fPlanPx(L, p.pos);
            if (p.parent >= 0 && p.parent < FS_COUNT)
            {
                float2 Pq = fPlanPx(L, fpFromRec(FurnBuf[p.parent]).pos);
                dlDashed(Pc, Pq, 1.2, IL_INK, 1.0, 3.2 * s, 3.8 * s);
                dlRing(Pq, 4.0 * s, 1.2, IL_INK, 1.0);
            }
            [loop] for (int c = 0; c < FS_COUNT; c++)
            {
                FPiece q = fpFromRec(FurnBuf[c]);
                if (q.parent != sel || (q.flags & FF_HIDDEN) != 0) continue;
                float2 Pq = fPlanPx(L, q.pos);
                dlDashed(Pc, Pq, 1.0, IL_DIM, 1.0, 3.2 * s, 3.8 * s);
                dlCircle(Pq, 2.5 * s, IL_DIM, 1.0);
            }
            float2 h = halfWDf(p);
            float2 Pk = fPlanPx(L, p.pos + fwd2(p.yaw) * (h.y + fKnobPx(L) / L.s));
            float2 Pf = fPlanPx(L, p.pos + fwd2(p.yaw) * h.y);
            bool heldRot = dragging && handle == FH_ROT;
            dlLine(Pf, Pk, 1.2, IL_ACCENT, 0.85);
            dlCircle(Pk, 7.5 * s, IL_FIELD, 0.6);
            dlRing(Pk, 6.0 * s, heldRot ? 2.4 : 1.6, IL_ACCENT, 1.0);
            dlCircle(Pk, 3.0 * s, IL_ACCENT, heldRot ? 1.0 : 0.6);
            bool rw = p.kind == FK_RUG || p.kind == FK_SOFA || p.kind == FK_COFFEE || p.kind == FK_CONSOLE || p.kind == FK_SHELF || p.kind == FK_ART;
            bool rd = p.kind == FK_RUG || p.kind == FK_COFFEE || p.kind == FK_SOFA;
            if (rw)
            {
                float2 Ph = fPlanPx(L, p.pos + right2(p.yaw) * h.x);
                float g = (dragging && handle == FH_WIDTH) ? 5.0 * s : 4.0 * s;
                dlRectEdged(float4(Ph - g, Ph + g), IL_ACCENT, 1.0, 0.0, IL_FIELD, 1.0);
            }
            if (rd)
            {
                float2 Ph = fPlanPx(L, p.pos - fwd2(p.yaw) * h.y);
                float g = (dragging && handle == FH_DEPTH) ? 5.0 * s : 4.0 * s;
                dlRectEdged(float4(Ph - g, Ph + g), IL_ACCENT, 1.0, 0.0, IL_FIELD, 1.0);
            }
        }
    }
    dlClipReset();

    // =========================================================================================
    // SECTION pane: the wall it looks at and the cut depth
    {
        float4 h = paneEdge(L.secPane, s);
        float hy = ilMid(h).y;
        float x = h.x + 10.0 * s;
        x += dlLabel(LB_SECTION, x, hy, ttl, IL_DIM, IL_LEFT) + 10.0 * s;
        x += dlLabel(LB_LOOKING, x, hy, body, IL_DIM, IL_LEFT) + 5.0 * s;
        dlLabel(wallLabel(secWall), x, hy, body, IL_INK, IL_LEFT);
        float xr = h.z - 10.0 * s;
        xr -= dlLabel(LB_M, xr, hy, cap, IL_DIM, IL_RIGHT) + 3.0 * s;
        xr -= dlNum(cutD, 2, xr, hy, val, IL_INK, IL_RIGHT) + 6.0 * s;
        dlLabel(LB_CUT, xr, hy, cap, IL_DIM, IL_RIGHT);
        dlLabelFit(LB_SEC_HINT, L.secR.x + 10.0 * s, L.secR.y + 10.0 * s, cap, IL_DIM, IL_LEFT, L.secR.z - L.secR.x - 20.0 * s);
    }

    // =========================================================================================
    // INSPECTOR pane
    {
        float4 ir = L.inspR;
        dlRectEdged(ir, IL_PANEL, 1.0, IL_RADIUS * s, IL_EDGE, 1.0);
        float4 h = ilPaneHead(ir, s);
        dlHLine(h.w, h.x + 1.0, h.z - 1.0, IL_EDGE);
        float pad = 10.0 * s, rh = ilSnap(20.0 * s);
        float x0 = ir.x + pad, x1 = ir.z - pad, vx = x0 + 58.0 * s;
        float y = h.w + 6.0 * s + 0.5 * rh;
        if (sel >= 0)
        {
            FPiece p = fpFromRec(FurnBuf[sel]);
            dlLabel(kindLabel(p.kind), h.x + 10.0 * s, ilMid(h).y, ttl, IL_ACCENT, IL_LEFT);
            dlLabel(variantLabel(p.kind, p.variant), x0, y, body, IL_INK, IL_LEFT);
            y += rh;
            // size: width x depth x height
            dlLabel(LB_SIZE, x0, y, body, IL_DIM, IL_LEFT);
            float x = vx;
            x += dlNum(p.size.x, 2, x, y, val, IL_INK, IL_LEFT) + 4.0 * s;
            x += dlLabel(LB_X, x, y, cap, IL_DIM, IL_LEFT) + 4.0 * s;
            x += dlNum(p.size.z, 2, x, y, val, IL_INK, IL_LEFT) + 4.0 * s;
            x += dlLabel(LB_X, x, y, cap, IL_DIM, IL_LEFT) + 4.0 * s;
            numUnit(p.size.y, 2, LB_M, x, y, s, IL_INK);
            y += rh;
            // where it stands, and its turn
            dlLabel(LB_POS, x0, y, body, IL_DIM, IL_LEFT);
            x = vx;
            x += dlNum(p.pos.x, 2, x, y, val, IL_INK, IL_LEFT) + 1.0 * s;
            x += dlLabel(LB_COMMA, x, y, cap, IL_DIM, IL_LEFT) + 5.0 * s;
            numUnit(p.pos.y, 2, LB_M, x, y, s, IL_INK);
            y += rh;
            dlLabel(LB_ROT, x0, y, body, IL_DIM, IL_LEFT);
            numUnit(round(degrees(p.yaw)), 0, LB_DEG, vx, y, s, IL_INK);
            y += rh;
            // what it stands on or hangs off
            int pr = p.parent;
            bool onTop = p.kind == FK_TABLELAMP || p.kind == FK_CUSHION || p.kind == FK_BOOKS || p.kind == FK_VASE;
            if (pr >= 0 && pr < FS_COUNT)
            {
                dlLabel(onTop ? LB_ON : LB_HANGS, x0, y, body, IL_DIM, IL_LEFT);
                dlLabel(kindLabel(fpFromRec(FurnBuf[pr]).kind), vx, y, body, IL_INK, IL_LEFT);
            }
            else if (pr <= FP_WALL0 && pr >= FP_WALL0 - 3)
            {
                dlLabel(LB_WALLON, x0, y, body, IL_DIM, IL_LEFT);
                dlLabel(wallLabel(FP_WALL0 - pr), vx, y, body, IL_INK, IL_LEFT);
            }
            else
            {
                dlLabel(LB_HOST, x0, y, body, IL_DIM, IL_LEFT);
                dlLabel((pr == FP_MANTEL) ? LB_MANTEL : (pr == FP_FIREBOX) ? LB_FIREBOX : LB_FREE, vx, y, body, IL_INK, IL_LEFT);
            }
            y += rh;
            // materials
            dlLabel(LB_MAT, x0, y, body, IL_DIM, IL_LEFT);
            dlLabel(matLabel(p.matA), vx, y, body, IL_INK, IL_LEFT);
            if (p.matB != p.matA) { y += rh; dlLabel(matLabel(p.matB), vx, y, body, IL_MID, IL_LEFT); }
            y += rh;
            // tags
            x = x0;
            if ((p.flags & FF_EDITED) != 0) x += dlLabel(LB_EDITEDTAG, x, y, body, IL_INK, IL_LEFT) + 12.0 * s;
            if ((p.flags & FF_HIDDEN) != 0) x += dlLabel(LB_HIDDEN, x, y, body, IL_DIM, IL_LEFT) + 12.0 * s;
            if ((p.flags & FF_ALARM) != 0) dlLabel(LB_ALARMTAG, x, y, body, IL_ALARM, IL_LEFT);
        }
        else
        {
            dlLabel(LB_INSPECTOR, h.x + 10.0 * s, ilMid(h).y, ttl, IL_DIM, IL_LEFT);
            dlLabel(LB_NOSEL, x0, y, body, IL_INK, IL_LEFT);
            y += rh;
            dlLabelFit(LB_NOSEL2, x0, y, cap, IL_DIM, IL_LEFT, x1 - x0);
        }
        // the keys, bottom-up above the chips, as many rows as fit under the content
        float yLimit = y + 0.5 * rh + 4.0 * s;
        float ky = fChipRect(L, 0).y - 8.0 * s - 0.5 * rh;
        float colX = x0 + 0.5 * (x1 - x0);
        if (ky - 0.5 * rh >= yLimit) hint(x0, ky, s, LB_K_ESC, LB_D_ESC);
        ky -= rh;
        if (ky - 0.5 * rh >= yLimit) { hint(x0, ky, s, LB_K_N, LB_D_N); hint(colX, ky, s, LB_K_0, LB_D_0); }
        ky -= rh;
        if (ky - 0.5 * rh >= yLimit) { hint(x0, ky, s, LB_K_H, LB_D_H); hint(colX, ky, s, LB_K_R, LB_D_R); }
        ky -= rh;
        if (ky - 0.5 * rh >= yLimit) { hint(x0, ky, s, LB_K_V, LB_D_V); hint(colX, ky, s, LB_K_M, LB_D_M); }
        // the chips: the selected piece's verbs, or the room's (the empty slot has no verb)
        int hotChip = fChipAt(L, ptr);
        bool hidden = sel >= 0 && (fpFromRec(FurnBuf[sel]).flags & FF_HIDDEN) != 0;
        [unroll] for (int ck = 0; ck < 4; ck++)
        {
            uint lab = (sel >= 0) ? ((ck == 0) ? LB_CH_VAR : (ck == 1) ? LB_CH_MAT : (ck == 2) ? (hidden ? LB_CH_SHOW : LB_CH_HIDE) : LB_CH_RESET)
                                  : ((ck == 0) ? LB_CH_REROLL : (ck == 1) ? LB_CH_UNHIDE : LB_CH_RESETALL);
            if (sel >= 0 || ck != 2) dlChip(fChipRect(L, ck), s, lab, false, hotChip == ck, hotChip == ck && down);
        }
    }

    // =========================================================================================
    // RULES pane: each rule's reading against its target band
    {
        float4 b = dlPane(L.rulesR, s, LB_RULES, false);
        float pad = 10.0 * s;
        float x0 = b.x + pad, x1 = b.z - pad, wPanel = x1 - x0;
        float rowH = max((b.w - b.y - 2.0 * pad) / 7.0, 30.0 * s);
        [loop] for (int k = 0; k < 7; k++)
        {
            float y = b.y + pad + rowH * (float)k + 8.0 * s;
            int bit = (k == 0) ? RULE_COFFEE : (k == 1) ? RULE_CONVERSE : (k == 2) ? (RULE_WALKWAY | RULE_BLOCKED) : (k == 3) ? RULE_HEARTH : (k == 4) ? RULE_DOOR : (k == 5) ? RULE_OVERLAP : 0;
            bool bad = (ruleBits & bit) != 0;
            float3 vc = bad ? IL_ALARM : IL_INK;
            dlLabel(LB_R_COFFEE + (uint)k, x0, y, body, IL_DIM, IL_LEFT);
            float val0 = 0.0, lo = 0.0, hi = 1.0, vmax = 1.0;
            bool gauge = true;
            if (k == 0) { val0 = rules.dims.x; lo = 0.40; hi = 0.50; vmax = 1.0; }
            else if (k == 1) { val0 = rules.dims.y; lo = 1.8; hi = 3.0; vmax = 4.5; }
            else if (k == 2) { val0 = rules.dims.z; lo = walkway; hi = 1.5; vmax = 2.0; }
            else if (k == 3) { val0 = rules.dims.w; lo = 0.9; hi = 3.0; vmax = 3.0; }
            else gauge = false;
            if (gauge)
            {
                if (val0 < 0.0) dlLabel((k == 2 && (ruleBits & RULE_BLOCKED) != 0) ? LB_BLOCKED : LB_NONE, x1, y, body, vc, IL_RIGHT);
                else
                {
                    float xr = x1 - dlLabel(LB_M, x1, y, cap, IL_DIM, IL_RIGHT) - 3.0 * s;
                    dlNum(val0, 2, xr, y, val, vc, IL_RIGHT);
                    // track, target band, reading
                    float gy = y + 10.0 * s, th = 3.0 * s;
                    dlRect(float4(x0, gy, x1, gy + th), IL_EDGE, 1.0, 1.0);
                    dlRect(float4(x0 + wPanel * saturate(lo / vmax), gy, x0 + wPanel * saturate(hi / vmax), gy + th), IL_DIM * 0.8, 1.0, 1.0);
                    float vx = x0 + wPanel * saturate(val0 / vmax);
                    dlRect(float4(vx - 1.5 * s, gy - 3.0 * s, vx + 1.5 * s, gy + th + 3.0 * s), vc, 1.0, 0.0);
                }
            }
            else if (k == 4) dlLabel(bad ? LB_BLOCKED : LB_CLEAR, x1, y, body, vc, IL_RIGHT);
            else if (k == 5) dlInt((int)round(rules.meta.w), 1, x1, y, val, vc, IL_RIGHT);
            else
            {
                // legs on the rug: how many of the group's legs stand on it
                float xr = x1 - dlInt((int)round(rules.meta.y), 1, x1, y, val, IL_DIM, IL_RIGHT) - 5.0 * s;
                xr -= dlLabel(LB_OF, xr, y, cap, IL_DIM, IL_RIGHT) + 5.0 * s;
                dlInt((int)round(rules.meta.x), 1, xr, y, val, (rules.meta.x < rules.meta.y) ? IL_MID : IL_INK, IL_RIGHT);
            }
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
