// BR_Trip / layout.hlsl -- the trip authority's anchors, chrome and type, recorded into the shared
// UI kit's draw list (ui.hlsl draws it over plate.hlsl's net and scope). Every rect and every pick
// comes from trip_layout.hlsli, the same functions trip.hlsl hit-tests with.
//
// NET: each anchor's reach ring (drag it to change the reach), an inner ring breathing with the
// anchor's own pulse, and its kind as an icon on a dark puck (square for an anchor riding a piece
// of furniture). The anchor under the pointer takes a value step and names its kind; the selected
// one takes the accent. SCOPE: the playhead (the trip clock, now) and the time axis. INSPECTOR: the
// selected anchor (kind, host, state, strength, reach, rate and its pulse now) or, with nothing
// selected, the trip (dose and overdrive, envelope, motif, tempo, the six channels and the stretch
// the furniture warps put on the march, red past its limit); the eight chips under it.
#include "../_shared/br_records.hlsli"
#include "../_shared/br_furn_defs.hlsli"
StructuredBuffer<BRRec> TripBuf : register(t0);
#define TRIP_REC(i) TripBuf[i]
#include "../_shared/br_shade.hlsli"
#include "../_shared/br_trip.hlsli"
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"
#include "trip_layout.hlsli"

BRRec sh(uint i) { BRRec r; r.head = _Data0[i].head; r.dims = _Data0[i].dims; r.look = _Data0[i].look; r.meta = _Data0[i].meta; return r; }

uint kindLabel(int k) { return LB_K_BREATHE + (uint)(clamp(k, TK_BREATHE, TK_FLOW) - TK_BREATHE); }
uint hostLabel(int host, bool haveFurn)
{
    if (host >= TH_FLOOR && host < TH_WALL0 + 4) return LB_V_FLOOR + (uint)host;   // floor, ceiling, walls S E N W
    int fk = haveFurn ? (int)round(_Data1[clamp(host - TH_OBJ0, 0, FURN_MAX - 1)].head.y) : 1;
    return LB_O1 + (uint)(clamp(fk, 1, 16) - 1);
}

// A key and what it does; returns the width used.
float hintW(float s, uint key, uint does) { return ilLabelW(key, IL_T_CAP * s) + 34.0 * s + ilLabelW(does, IL_T_CAP * s); }
float hint(float x, float y, float s, uint key, uint does)
{
    float kw = ilLabelW(key, IL_T_CAP * s) + 12.0 * s, kh = 18.0 * s;
    dlKeycap(float4(x, y - 0.5 * kh, x + kw, y + 0.5 * kh), s, key);
    return kw + 6.0 * s + dlLabel(does, x + kw + 6.0 * s, y, IL_T_CAP * s, IL_DIM, IL_LEFT) + 16.0 * s;
}

// A pane drawn over plate.hlsl's card: edge, header rule and title. Returns the header strip.
float4 paneChrome(float4 r, float s, uint title)
{
    dlBorderRect(r, IL_RADIUS * s, IL_EDGE, 1.0);
    float4 ph = ilPaneHead(r, s);
    dlHLine(ph.w, ph.x + 1.0, ph.z - 1.0, IL_EDGE);
    dlLabel(title, ph.x + 10.0 * s, ilMid(ph).y, IL_T_TITLE * s, IL_DIM, IL_LEFT);
    return ph;
}

// A 0..1 amount as a bar (or -1..1 about the centre).
void bar(float4 r, float s, float v, bool centred, float3 c)
{
    dlRectEdged(r, IL_WELL, 1.0, 1.5 * s, IL_EDGE, 1.0);
    float x0 = centred ? ilMid(r).x : r.x;
    float x1 = centred ? x0 + clamp(v, -1.0, 1.0) * (r.z - r.x) * 0.5 : lerp(r.x, r.z, saturate(v));
    float4 f = float4(min(x0, x1), r.y + 1.0, max(x0, x1), r.w - 1.0);
    if (f.z - f.x > 0.5) dlRect(f, c, 1.0, 1.0 * s);
    if (centred) dlVLine(x0, r.y - 2.0 * s, r.w + 2.0 * s, IL_RULE);
}
// An inspector row: caption left, the rest of the row from vx on; returns the value area.
float4 row(float4 r, float s, uint caption)
{
    dlLabel(caption, r.x, ilMid(r).y, IL_T_BODY * s, IL_DIM, IL_LEFT);
    dlHLine(r.w - 0.5, r.x, r.z, IL_GRID);
    return float4(r.x + 104.0 * s, r.y, r.z, r.w);
}
// A bar with its number at the right end.
void barRow(float4 v, float s, float amount, float shown, int dec, bool centred, float3 c)
{
    float y = ilMid(v).y;
    float nw = ilNumW(ilFormat(shown, dec, 1, centred).n, IL_T_VALUE * s);
    dlNumEx(shown, dec, 1, centred, v.z, y, IL_T_VALUE * s, IL_INK, IL_RIGHT);
    bar(float4(v.x, y - 3.0 * s, v.z - nw - 10.0 * s, y + 3.0 * s), s, amount, centred, c);
}
// number, a gap, unit; right-aligned at x. Returns the width.
float numUnitR(float v, int dec, uint unit, float x, float y, float s, float3 ink)
{
    float w = dlLabel(unit, x, y, IL_T_CAP * s, IL_DIM, IL_RIGHT) + 4.0 * s;
    return w + dlNum(v, dec, x - w, y, IL_T_VALUE * s, ink, IL_RIGHT);
}

// A kind's icon, radius r px: breathe = ring and dot, melt = a drip, swirl = a spiral, bloom = an
// asterisk, flow = a double chevron. Icons, not captions: anchors that share a spot stay readable.
void kindIcon(float2 c, int kind, float r, float3 ink, float a)
{
    float w = 1.3;
    if (kind == TK_BREATHE) { dlRing(c, r, w, ink, a); dlCircle(c, r * 0.32, ink, a); }
    else if (kind == TK_MELT)
    {
        dlCircle(c + float2(0.0, r * 0.35), r * 0.55, ink, a);
        dlLine(c + float2(0.0, -r), c + float2(0.0, r * 0.1), w, ink, a);
    }
    else if (kind == TK_SWIRL) { dlArc(c, r, w, 0.0, 4.4, ink, a); dlArc(c, r * 0.5, w, 2.2, 6.2, ink, a); }
    else if (kind == TK_BLOOM)
    {
        [loop] for (int i = 0; i < 3; i++)
        {
            float ang = (float)i * 1.0471976;
            float2 e = float2(cos(ang), sin(ang)) * r;
            dlLine(c - e, c + e, w, ink, a);
        }
    }
    else
    {
        [loop] for (int j = 0; j < 2; j++)
        {
            float2 o = c + float2((j == 0) ? -r * 0.55 : r * 0.25, 0.0);
            dlLine(o + float2(-r * 0.3, -r * 0.6), o + float2(r * 0.3, 0.0), w, ink, a);
            dlLine(o + float2(r * 0.3, 0.0), o + float2(-r * 0.3, r * 0.6), w, ink, a);
        }
    }
}

void layout()
{
    float2 res = _Resolution.xy;
    bool haveShell = _Data0_Count >= 13u && abs(_Data0[0].head.x - ROLE_ROOM) < 0.5;
    BRRoom R = brDefaultRoom();
    if (haveShell) R = brRoomFromRec(sh(0));
    bool haveFurn = _Data1_Count >= 30u && abs(_Data1[0].head.x - ROLE_FURN) < 0.5;
    TLayout L = tLayout(res, R);
    float s = L.s;

    BRTrip T = tripHeader();
    BRRec ed = TripBuf[TRIP_EDITOR];
    BRRec dg = TripBuf[TRIP_DIAG];
    int sel = (int)round(ed.head.y);
    if (sel < -1 || sel >= TRIP_ANCH_MAX) sel = -1;
    bool addArmed = dg.look.z > 0.5;
    bool holding = dg.look.w > 0.5;
    bool alarm = dg.look.y > 0.5;

    // what the pointer is over: a chip, or an anchor (the press's own pick)
    float2 ptr = _ViewportPointerPosition * res;
    bool down = (_ViewportButtons & 1u) != 0u;
    int hotChip = tChipAt(L, ptr);
    int hotA = -1; bool hotRing = false;
    if (tInRect(ptr, L.netR, 0.0) && !addArmed)
    {
        float best = TRIP_GRAB * s;
        [loop] for (int kp = 0; kp < TRIP_ANCH_MAX; kp++)
        {
            BRAnchor A = tripAnchor(kp);
            if (A.on) tPickTest(L, ptr, tAnchorPx(L, A), A.radius * L.scale, kp, best, hotA, hotRing);
        }
    }

    dlBegin(res);

    // ---- title strip: the dose as set (overdrive included), motif, the trip clock, anchors running
    float hy = ilMid(L.head).y;
    float x = res.x - 14.0 * s;
    float nOn = dg.dims.x + dg.dims.y + dg.dims.z + dg.dims.w + dg.look.x;
    x -= dlLabel(LB_ANCHORS, x, hy, IL_T_CAP * s, IL_DIM, IL_RIGHT) + 5.0 * s;
    x -= dlInt((int)round(nOn), 1, x, hy, IL_T_VALUE * s, IL_INK, IL_RIGHT) + 20.0 * s;
    float mins = floor(T.time / 60.0), secs = floor(T.time - mins * 60.0);
    x -= dlInt((int)secs, 2, x, hy, IL_T_VALUE * s, IL_INK, IL_RIGHT);
    x -= dlLabel(LB_COLON, x, hy, IL_T_VALUE * s, IL_INK, IL_RIGHT);
    x -= dlInt((int)mins, 1, x, hy, IL_T_VALUE * s, IL_INK, IL_RIGHT) + 5.0 * s;
    x -= dlLabel(LB_TIME, x, hy, IL_T_CAP * s, IL_DIM, IL_RIGHT) + 20.0 * s;
    int motifK = (((int)round(T.motif)) % 4 + 4) % 4;
    x -= dlLabel(LB_M_GIRIH + (uint)motifK, x, hy, IL_T_BODY * s, IL_INK, IL_RIGHT) + 20.0 * s;
    x -= dlNum(T.dose + T.push, 2, x, hy, IL_T_VALUE * s, IL_INK, IL_RIGHT) + 5.0 * s;
    x -= dlLabel(LB_DOSE, x, hy, IL_T_CAP * s, IL_DIM, IL_RIGHT) + 24.0 * s;
    float tx = 14.0 * s;
    tx += dlLabel(LB_TITLE, tx, hy, 15.0 * s, IL_INK, IL_LEFT) + 14.0 * s;
    dlLabelFit(LB_SUBTITLE, tx, hy, IL_T_BODY * s, IL_DIM, IL_LEFT, x - tx);

    // ---- the net: chrome, surface captions, anchors
    float4 nh = paneChrome(L.netPane, s, LB_NET);
    {
        float ty = ilMid(nh).y, x0 = nh.x + 20.0 * s + ilLabelW(LB_NET, IL_T_TITLE * s);
        if (addArmed) dlLabelFit(LB_ADDHINT, nh.z - 10.0 * s, ty, IL_T_CAP * s, IL_INK, IL_RIGHT, nh.z - 10.0 * s - x0);
        else
        {
            float hw = hintW(s, LB_K_DRAG, LB_D_DRAG) + hintW(s, LB_K_RING, LB_D_RING) + hintW(s, LB_K_CLICK, LB_D_CLICK);
            if (nh.z - 10.0 * s - hw > x0)
            {
                float hx = nh.z - 10.0 * s - hw;
                hx += hint(hx, ty, s, LB_K_DRAG, LB_D_DRAG);
                hx += hint(hx, ty, s, LB_K_RING, LB_D_RING);
                hint(hx, ty, s, LB_K_CLICK, LB_D_CLICK);
            }
        }
    }
    dlClip(L.netR);
    [loop] for (int hp = 0; hp < 6; hp++)
    {
        float2 at = tNetPx(L, tPanel(L, hp).xy) + float2(6.0, 9.0) * s;
        dlLabel(LB_H_FLOOR + (uint)hp, at.x, at.y, IL_T_CAP * s, IL_DIM, IL_LEFT);
    }
    [loop] for (int i = 0; i < TRIP_ANCH_MAX; i++)
    {
        BRAnchor A = tripAnchor(i);
        bool isSel = i == sel;
        if (A.on || isSel)
        {
            bool hot = i == hotA;
            float2 ap = tAnchorPx(L, A);
            float rr = A.radius * L.scale;
            float pulse = tripPulse(A, T.time);
            float3 c = isSel ? IL_ACCENT : (hot ? IL_INK : IL_INK * 0.78);
            float a = A.on ? 1.0 : 0.45;
            // the reach ring (drag it), and an inner ring breathing with the anchor's cycle
            dlRing(ap, rr, (isSel || (hot && hotRing)) ? 2.0 : 1.2, c, a);
            dlRing(ap, rr * (0.55 + 0.25 * pulse), 0.9, c, 0.55 * a);
            // the kind's icon on a dark puck (square: the anchor rides a piece of furniture)
            float pk = 9.0 * s;
            if (A.host >= TH_OBJ0) dlRect(float4(ap - pk, ap + pk), IL_FIELD, 0.85, 2.0 * s);
            else dlCircle(ap, pk, IL_FIELD, 0.85);
            kindIcon(ap, A.kind, 5.5 * s, c, a);
            // its kind: always on the selection, on the hovered anchor only with Tooltips
            if (isSel || (tooltips != 0 && hot)) dlLabel(kindLabel(A.kind), ap.x + 14.0 * s, ap.y, IL_T_TITLE * s, c, IL_LEFT);
        }
    }
    dlClipReset();

    // ---- the scope: plot frame, the playhead (now) and the time axis
    paneChrome(L.scopePane, s, LB_SCOPE);
    float4 sp = tScopePlot(L);
    dlBorderRect(sp, 0.0, IL_EDGE, 1.0);
    float xNow = tScopeX(L, 0.0);
    dlLine(float2(xNow, sp.y), float2(xNow, sp.w), 1.8, IL_ACCENT, 1.0);
    float ay = sp.w + 11.0 * s;
    dlLabel(LB_NOW, xNow, ay, IL_T_CAP * s, IL_ACCENT, IL_CENTER);
    dlLabel(LB_AGO, sp.x, ay, IL_T_CAP * s, IL_DIM, IL_LEFT);
    dlLabel(LB_AHEAD, sp.z, ay, IL_T_CAP * s, IL_DIM, IL_RIGHT);

    // ---- the inspector
    dlPane(L.sidePane, s, (sel >= 0) ? LB_ANCHOR : LB_TRIP, sel >= 0);
    if (sel >= 0)
    {
        BRAnchor A = tripAnchor(sel);
        float4 r0 = tRowRect(L, 0.0);
        dlLabel(kindLabel(A.kind), r0.x, ilMid(r0).y, IL_T_TITLE * s, IL_ACCENT, IL_LEFT);
        dlLabel(A.on ? LB_ON : LB_OFF, r0.z, ilMid(r0).y, IL_T_BODY * s, A.on ? IL_INK : IL_DIM, IL_RIGHT);
        dlHLine(r0.w - 0.5, r0.x, r0.z, IL_GRID);
        float4 v1 = row(tRowRect(L, 1.0), s, LB_C_HOST);
        dlLabel(hostLabel(A.host, haveFurn), v1.z, ilMid(v1).y, IL_T_BODY * s, IL_INK, IL_RIGHT);
        float4 v2 = row(tRowRect(L, 2.0), s, LB_C_STRENGTH);
        barRow(v2, s, A.strength, A.strength, 2, false, IL_MID);
        float4 v3 = row(tRowRect(L, 3.0), s, LB_C_RADIUS);
        numUnitR(A.radius, 2, LB_M, v3.z, ilMid(v3).y, s, IL_INK);
        float4 v4 = row(tRowRect(L, 4.0), s, LB_C_RATE);
        numUnitR(A.rate * 60.0, 1, LB_PERMIN, v4.z, ilMid(v4).y, s, IL_INK);
        float4 v5 = row(tRowRect(L, 5.0), s, LB_C_PULSE);
        float pv = tripPulse(A, T.time) * A.strength;
        barRow(v5, s, pv, pv, 2, true, IL_ACCENT);
    }
    else
    {
        float4 v0 = row(tRowRect(L, 0.0), s, LB_C_DOSE);
        barRow(v0, s, T.dose, T.dose, 2, false, IL_INK);
        float4 v1 = row(tRowRect(L, 1.0), s, LB_C_PUSH);
        barRow(v1, s, T.push * 0.5, T.push, 2, false, IL_MID);
        float4 v2 = row(tRowRect(L, 2.0), s, LB_C_ENV);
        dlLabel(LB_A_STEADY + (uint)clamp((int)round(arc), 0, 2), v2.z, ilMid(v2).y, IL_T_BODY * s, IL_INK, IL_RIGHT);
        float4 v3 = row(tRowRect(L, 3.0), s, LB_C_MOTIF);
        dlLabel(LB_M_GIRIH + (uint)motifK, v3.z, ilMid(v3).y, IL_T_BODY * s, IL_INK, IL_RIGHT);
        float4 v4 = row(tRowRect(L, 4.0), s, LB_C_TEMPO);
        float tw = dlNum(T.tempo, 2, v4.z, ilMid(v4).y, IL_T_VALUE * s, holding ? IL_DIM : IL_INK, IL_RIGHT);
        if (holding) dlLabel(LB_HOLDING, v4.z - tw - 8.0 * s, ilMid(v4).y, IL_T_BODY * s, IL_INK, IL_RIGHT);
        float4 rc = tRowRect(L, 5.0);
        dlLabel(LB_CHANNELS, rc.x, ilMid(rc).y + 4.0 * s, IL_T_TITLE * s, IL_DIM, IL_LEFT);
        float chV[6] = { T.breathe, T.drift, T.melt, T.geometry, T.colour, T.objects };
        [loop] for (int c6 = 0; c6 < 6; c6++)
        {
            float4 vc = row(tRowRect(L, 6.0 + (float)c6), s, LB_CH_BREATHE + (uint)c6);
            barRow(vc, s, chV[c6], chV[c6], 2, false, IL_MID);
        }
        float4 vs = row(tRowRect(L, 12.0), s, LB_C_STRETCH);
        numUnitR(T.lip, 2, LB_X, vs.z, ilMid(vs).y, s, alarm ? IL_ALARM : IL_INK);
        if (alarm)
        {
            float4 ra = tRowRect(L, 13.0);
            dlLabel(LB_ALARM, ra.z, ilMid(ra).y, IL_T_BODY * s, IL_ALARM, IL_RIGHT);
        }
    }
    [loop] for (int ck = 0; ck < TRIP_CHIPS; ck++)
    {
        uint lab = (sel >= 0) ? LB_CA_KIND + (uint)ck : ((ck == 7) ? (holding ? LB_CG_RUN : LB_CG_HOLD) : LB_CG_REROLL + (uint)ck);
        bool on = sel < 0 && ((ck == 4 && addArmed) || (ck == 7 && holding));
        dlChip(tChipRect(L, ck), s, lab, on, hotChip == ck, hotChip == ck && down);
    }

    dlFinish();
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    if (gi == 0u) layout();
    dlEnd(gi);
}
