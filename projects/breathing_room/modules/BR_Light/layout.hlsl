// BR_Light / layout.hlsl -- the lighting authority's chrome, paths, handles, rings and type,
// recorded into the shared UI kit's draw list (ui.hlsl draws it over plate.hlsl's sky and plan).
// Every rect and every hit test comes from light_layout.hlsli, the functions light.hlsl uses.
//
// SUN PATH: today's path (the golden part in the sun's own colour) with its hours, the sun as the
// live reading (accent ring), and, under the pointer, the time a press there would jump the sun to.
// DAY: night, day, the golden hours and the blue hour on 0-24 h; the playhead is the time.
// LIGHTS: the sun's or the selected light's readout, the chips, and the rack of every light with
// its switch. PLAN: every light's middle pool (the ring you drag) in its own colour, the selected
// one's bright core and faint fringe, and the sun's bearing into the room.
//
// Mostly monochrome (plan_theme): amber is the selection and the live sun; a light's rings and
// swatches carry its own colour through ptSampleColour, the golden hours the sun's through
// ptSampleFill. Hover is a value step.
#include "../_shared/br_records.hlsli"
#include "../_shared/br_furn_defs.hlsli"
#include "../_shared/br_light_defs.hlsli"
#include "../_shared/br_shade.hlsli"          // brVN3, which br_sky needs
#include "../_shared/br_sky.hlsli"
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"
#include "light_layout.hlsli"

StructuredBuffer<BRRec> LightBuf : register(t0);

BRRec sh(uint i) { BRRec r; r.head = _Data0[i].head; r.dims = _Data0[i].dims; r.look = _Data0[i].look; r.meta = _Data0[i].meta; return r; }
int lightRec(int k) { return (k == 5) ? LIGHT_FIRE : LIGHT_LAMP0 + k; }

// A key and what it does; returns the width used.
float hintW(float s, uint key, uint does) { return ilLabelW(key, IL_T_CAP * s) + 34.0 * s + ilLabelW(does, IL_T_CAP * s); }
float hint(float x, float y, float s, uint key, uint does)
{
    float kw = ilLabelW(key, IL_T_CAP * s) + 12.0 * s, kh = 18.0 * s;
    dlKeycap(float4(x, y - 0.5 * kh, x + kw, y + 0.5 * kh), s, key);
    return kw + 6.0 * s + dlLabel(does, x + kw + 6.0 * s, y, IL_T_CAP * s, IL_DIM, IL_LEFT) + 16.0 * s;
}

// hh:mm in the mono face; returns its width
float clockW(float size) { return 2.0 * ilNumW(2u, size) + ilLabelW(LB_COLON, size); }
float dlClock(float h, float x, float y, float size, float3 c, uint align)
{
    float hh = floor(h), mm = floor(frac(h) * 60.0 + 0.5);
    if (mm >= 60.0) { mm = 0.0; hh += 1.0; }
    float w = clockW(size);
    float x0 = ilAlignX(x, w, align);
    x0 += dlNumEx(hh, 0, 2, false, x0, y, size, c, IL_LEFT);
    x0 += dlLabel(LB_COLON, x0, y, size, c, IL_LEFT);
    dlNumEx(mm, 0, 2, false, x0, y, size, c, IL_LEFT);
    return w;
}
// a small raised card holding a clock, centred on c (a preview of what a press would set)
void clockCard(float2 c, float h, float s)
{
    float w = clockW(IL_T_VALUE * s) + 12.0 * s;
    float4 r = float4(c.x - 0.5 * w, c.y - 9.0 * s, c.x + 0.5 * w, c.y + 9.0 * s);
    dlRectEdged(r, IL_RAISE, 0.96, IL_RADIUS * s, IL_EDGE, 1.0);
    dlClock(h, c.x, c.y, IL_T_VALUE * s, IL_INK, IL_CENTER);
}
// a pane drawn by plate.hlsl (card) gets its edge, header rule and title here; returns the title's end
float paneChrome(float4 r, float s, uint title)
{
    dlBorderRect(r, IL_RADIUS * s, IL_EDGE, 1.0);
    float4 h = ilPaneHead(r, s);
    dlHLine(h.w, h.x + 1.0, h.z - 1.0, IL_EDGE);
    return h.x + 10.0 * s + dlLabel(title, h.x + 10.0 * s, ilMid(h).y, IL_T_TITLE * s, IL_DIM, IL_LEFT) + 16.0 * s;
}
// caption at x, value laid out by the caller at x + 70 ui px
void caption(uint id, float x, float y, float s) { dlLabel(id, x, y, IL_T_CAP * s, IL_DIM, IL_LEFT); }

void layout()
{
    float2 res = _Resolution.xy;
    bool haveShell = _Data0_Count >= 13u && abs(_Data0[0].head.x - ROLE_ROOM) < 0.5;
    BRRoom rm = brDefaultRoom();
    if (haveShell) rm = brRoomFromRec(sh(0));
    bool haveFurn = _Data1_Count >= 30u;
    LLayout L = lLayout(res, rm);
    float s = L.s;
    float cap = IL_T_CAP * s, val = IL_T_VALUE * s;

    BRRec sun = LightBuf[LIGHT_SUN];
    float3 sd = normalize(sun.dims.xyz + 1e-6);
    float tod = sun.meta.x, doy = sun.meta.y, lat = sun.meta.z, compassDeg = sun.meta.w;
    BRRec rules = LightBuf[LIGHT_RULES];
    float rise = rules.dims.x, set = rules.dims.y, g0 = rules.dims.z, g1 = rules.dims.w;
    float sunElDeg = rules.look.x, sunAzDeg = rules.look.y;
    BRRec ed = LightBuf[LIGHT_EDITOR];
    int sel = (int)round(ed.head.y);
    int handle = (int)round(ed.dims.x);
    bool dragging = ed.dims.y > 0.5;
    float3 sunCol = brSunColour(sd);
    float3 sunN = sunCol / max(max(sunCol.r, max(sunCol.g, sunCol.b)), 1e-4);
    float3 sunInk = ptSampleColour(sunN);
    bool golden = (tod > rise && tod < g0) || (tod > g1 && tod < set);

    // the lights as published
    float3 bulb[LIGHT_ROLES];
    float pw[LIGHT_ROLES];
    bool ex[LIGHT_ROLES];
    int nOn = 0;
    [unroll] for (int k0 = 0; k0 < LIGHT_ROLES; k0++)
    {
        BRRec lr = LightBuf[lightRec(k0)];
        bulb[k0] = lr.meta.xyz;
        pw[k0] = lr.dims.x;
        ex[k0] = lr.dims.w > 0.5;
        nOn += (ex[k0] && lr.head.z > 0.5) ? 1 : 0;
    }

    // what the pointer is over (the same questions light.hlsl asks on a press)
    float2 ptr = _ViewportPointerPosition * res;
    bool down = (_ViewportButtons & 1u) != 0u;
    int hotChip = lChipAt(L, ptr);
    bool hotSw = false;
    int hotRow = (hotChip < 0) ? lRowAt(L, ptr, hotSw) : -1;
    bool hotRing = false;
    int hotLight = (!dragging && lInRect(ptr, L.planBody, 0.0)) ? lLightAt(L, ptr, bulb, pw, ex, hotRing) : -1;
    bool hotChart = !dragging && lInRect(ptr, L.chartBody, 0.0);
    bool hotDay = !dragging && lInRect(ptr, L.dayBody, 0.0);

    dlBegin(res);

    // =========================================================================================
    // TITLE STRIP: the time, the sun's elevation, how many lights are on
    {
        float hy = ilMid(L.head).y;
        float x = 14.0 * s;
        x += dlLabel(LB_TITLE, x, hy, 15.0 * s, IL_INK, IL_LEFT) + 14.0 * s;
        dlLabel(LB_SUBTITLE, x, hy, IL_T_BODY * s, IL_DIM, IL_LEFT);
        float xr = res.x - 14.0 * s;
        xr -= dlLabel(LB_LIGHTSON, xr, hy, cap, IL_DIM, IL_RIGHT) + 5.0 * s;
        xr -= dlInt(nOn, 1, xr, hy, val, IL_INK, IL_RIGHT) + 18.0 * s;
        xr -= dlLabel(LB_DEG, xr, hy, cap, IL_DIM, IL_RIGHT) + 3.0 * s;
        xr -= dlNum(sunElDeg, 1, xr, hy, val, IL_INK, IL_RIGHT) + 5.0 * s;
        xr -= dlLabel(LB_C_SUN, xr, hy, cap, IL_DIM, IL_RIGHT) + 18.0 * s;
        dlClock(tod, xr, hy, val, IL_INK, IL_RIGHT);
    }

    // =========================================================================================
    // SUN PATH
    {
        float tx = paneChrome(L.chartR, s, LB_SUNPATH);
        float4 ch = ilPaneHead(L.chartR, s);
        float cy = ilMid(ch).y;
        // what the path is drawn for: the day of the year and the latitude
        float xr = ch.z - 10.0 * s;
        xr -= dlLabel(LB_DEG, xr, cy, cap, IL_DIM, IL_RIGHT) + 3.0 * s;
        xr -= dlNum(lat, 1, xr, cy, val, IL_MID, IL_RIGHT) + 5.0 * s;
        xr -= dlLabel(LB_C_LAT, xr, cy, cap, IL_DIM, IL_RIGHT) + 14.0 * s;
        xr -= dlInt((int)round(doy), 1, xr, cy, val, IL_MID, IL_RIGHT) + 5.0 * s;
        xr -= dlLabel(LB_C_DAYN, xr, cy, cap, IL_DIM, IL_RIGHT) + 18.0 * s;
        float hw = hintW(s, LB_K_DRAG, LB_D_SUN);
        if (xr - hw > tx) hint(xr - hw, cy, s, LB_K_DRAG, LB_D_SUN);

        dlClip(L.chartBody);
        float4 pl = lChartPlot(L);
        // compass along the horizon, elevation up the side
        [loop] for (int k3 = 0; k3 <= 8; k3++)
        {
            float2 lp = lChartPx(L, (float)k3 * 0.7853982, 0.0);
            dlLabel(LB_AZN + (uint)(k3 % 8), lp.x, lp.y + 11.0 * s, cap, IL_DIM, IL_CENTER);
        }
        [loop] for (int k4 = 1; k4 <= 7; k4++)
        {
            float2 lp = lChartPx(L, 0.0, (float)k4 * 0.1745329);
            dlInt(k4 * 10, 1, lp.x - 5.0 * s, lp.y, cap, IL_RULE * 1.8, IL_RIGHT);
        }
        // today's path, the golden part (sun under 6 degrees) in the sun's colour
        float2 prev = 0;
        [loop] for (int i = 0; i <= 64; i++)
        {
            float t = lerp(max(rise - 0.5, 0.0), min(set + 0.5, 24.0), (float)i / 64.0);
            float2 ea = brSolarPosition(t, doy, lat);
            float az = ea.y - 6.2831853 * floor(ea.y / 6.2831853);
            float2 cur = lChartPx(L, az, max(ea.x, -0.06));
            if (i > 0 && abs(cur.x - prev.x) < (pl.z - pl.x) * 0.5)
            {
                bool gold = degrees(ea.x) < 6.0;
                dlLine(prev, cur, gold ? 2.2 : 1.4, gold ? sunInk : IL_MID, 1.0);
            }
            prev = cur;
        }
        // its hours
        [loop] for (int hr = 5; hr <= 21; hr++)
        {
            float2 ea = brSolarPosition((float)hr, doy, lat);
            if (ea.x >= -0.02)
            {
                float az = ea.y - 6.2831853 * floor(ea.y / 6.2831853);
                float2 hp = lChartPx(L, az, ea.x);
                dlCircle(hp, 2.2 * s, IL_DIM, 1.0);
                dlInt(hr, 1, hp.x, hp.y - 10.0 * s, cap, IL_DIM, IL_CENTER);
            }
        }
        // under the pointer: where a press would put the sun, and at what time
        if (hotChart)
        {
            float tg = lSunTimeAt(L, ptr, doy, lat, float2(rise, set), tod);
            float2 ea = brSolarPosition(tg, doy, lat);
            float2 gp = lChartPx(L, fmod(ea.y + 6.2831853 * 2.0, 6.2831853), max(ea.x, -0.02));
            dlRing(gp, 9.0 * s, 1.2, IL_INK, 0.8);
            if (tooltips != 0) clockCard(gp + float2(0.0, 22.0 * s), tg, s);     // the time card (Tooltips)
        }
        // the sun: the live reading
        float2 sa = dirAzEl(sd, compassDeg);
        float2 sp = lChartPx(L, sa.x, max(sa.y, -0.06));
        dlCircle(sp, 6.0 * s, sunInk, 1.0);
        dlRing(sp, 9.0 * s, (dragging && handle == H_SUN) ? 2.4 : 1.6, IL_ACCENT, 1.0);
        dlClipReset();
    }

    // =========================================================================================
    // DAY
    {
        dlPane(L.dayR, s, LB_DAY, false);
        float4 dh = ilPaneHead(L.dayR, s);
        float dy = ilMid(dh).y;
        float xr = dh.z - 10.0 * s;
        xr -= dlClock(set, xr, dy, val, IL_MID, IL_RIGHT) + 5.0 * s;
        xr -= dlLabel(LB_C_SET, xr, dy, cap, IL_DIM, IL_RIGHT) + 16.0 * s;
        xr -= dlClock(rise, xr, dy, val, IL_MID, IL_RIGHT) + 5.0 * s;
        dlLabel(LB_C_RISE, xr, dy, cap, IL_DIM, IL_RIGHT);

        float4 tr = lDayTrack(L);
        float xRise = lDayX(L, rise), xSet = lDayX(L, set);
        dlRect(tr, IL_WELL * 1.4, 1.0, 0.0);                                         // night
        if (xSet > xRise) dlRect(float4(xRise, tr.y, xSet, tr.w), IL_RULE * 0.9, 1.0, 0.0);   // day
        float3 gf = ptSampleFill(sunN) * 1.2;                                        // the golden hours
        if (g0 > rise) dlRect(float4(xRise, tr.y, lDayX(L, g0), tr.w), gf, 0.85, 0.0);
        if (set > g1) dlRect(float4(lDayX(L, g1), tr.y, xSet, tr.w), gf, 0.85, 0.0);
        float xb0 = lDayX(L, max(rise - 0.5, 0.0)), xb1 = lDayX(L, min(set + 0.5, 24.0));  // the blue hour
        if (xRise > xb0) dlRect(float4(xb0, tr.y, xRise, tr.w), PT_ID_A * 0.6, 0.8, 0.0);
        if (xb1 > xSet) dlRect(float4(xSet, tr.y, xb1, tr.w), PT_ID_A * 0.6, 0.8, 0.0);
        [loop] for (int h1 = 1; h1 < 24; h1++)
        {
            float x = lDayX(L, (float)h1);
            dlRect(float4(x - 0.5, tr.y, x + 0.5, tr.w), IL_FIELD, 0.6, 0.0);
        }
        [loop] for (int hk = 0; hk <= 24; hk += 3)
            dlInt(hk, 1, lDayX(L, (float)hk), tr.y - 9.0 * s, cap, IL_DIM, IL_CENTER);
        // under the pointer: the time a press would set
        if (hotDay)
        {
            float gx = clamp(ptr.x, tr.x, tr.z);
            dlRect(float4(gx - 0.5, tr.y - 2.0 * s, gx + 0.5, tr.w + 2.0 * s), IL_INK, 0.7, 0.0);
            if (tooltips != 0) clockCard(float2(gx, tr.y - 9.0 * s), clamp(lDayH(L, gx), 0.0, 24.0), s);   // (Tooltips)
        }
        // the playhead: the time
        float px = lDayX(L, tod);
        dlRect(float4(px - 1.1, tr.y - 2.0 * s, px + 1.1, tr.w + 2.0 * s), IL_ACCENT, 1.0, 0.0);
        dlTri(float2(px, tr.y - 1.0), 5.0 * s, 6.0 * s, 0u, IL_ACCENT, 1.0);
    }

    // =========================================================================================
    // LIGHTS: the readout and the chips on the left, the rack on the right
    {
        dlPane(L.inspR, s, LB_LIGHTS, false);
        float4 info = lInfoRect(L);
        float colW = 0.5 * (info.z - info.x), vx = 70.0 * s, lh = ilSnap(17.0 * s);
        float y = info.y + 8.0 * s;
        float x1 = info.x + colW;
        if (sel >= 0 && sel < LIGHT_ROLES)
        {
            BRRec lr = LightBuf[lightRec(sel)];
            bool isOn = lr.head.z > 0.5;
            dlLabel(LB_R0 + (uint)sel, info.x, y, IL_T_TITLE * s, IL_ACCENT, IL_LEFT);     // the selection
            float yr = y + 1.4 * lh;
            caption(LB_C_STATE, info.x, yr, s);
            dlLabel(isOn ? LB_ON : LB_OFF, info.x + vx, yr, IL_T_BODY * s, isOn ? IL_INK : IL_DIM, IL_LEFT);
            caption(LB_C_POWER, info.x, yr + lh, s);
            dlNum(lr.dims.x, 2, info.x + vx, yr + lh, val, IL_INK, IL_LEFT);
            caption(LB_C_TEMP, info.x, yr + 2.0 * lh, s);
            float w = dlInt((int)round(lr.dims.y), 1, info.x + vx, yr + 2.0 * lh, val, IL_INK, IL_LEFT) + 3.0 * s;
            w += dlLabel(LB_K, info.x + vx + w, yr + 2.0 * lh, cap, IL_DIM, IL_LEFT) + 8.0 * s;
            float4 sw = float4(info.x + vx + w, yr + 2.0 * lh - 6.0 * s, info.x + vx + w + 34.0 * s, yr + 2.0 * lh + 6.0 * s);
            dlRectEdged(sw, ptSampleColour(lr.look.rgb), isOn ? 1.0 : 0.3, 2.0 * s, IL_EDGE, 1.0);   // the light's own colour
            // the reach: the middle pool's radius on the floor, what dragging its ring sets
            bool ringHeld = dragging && handle == H_RING;
            caption(LB_C_REACH, x1, yr, s);
            float rw = dlNum(lRingRadius(lr.dims.x, max(lr.meta.y, 0.1), LIGHT_RING_E), 2, x1 + vx, yr, val, ringHeld ? IL_ACCENT : IL_INK, IL_LEFT) + 3.0 * s;
            dlLabel(LB_M, x1 + vx + rw, yr, cap, IL_DIM, IL_LEFT);
        }
        else
        {
            dlLabel(LB_SUN, info.x, y, IL_T_TITLE * s, IL_INK, IL_LEFT);
            float yr = y + 1.4 * lh;
            caption(LB_C_TIME, info.x, yr, s);
            dlClock(tod, info.x + vx, yr, val, IL_INK, IL_LEFT);
            caption(LB_C_ELEV, info.x, yr + lh, s);
            float w = dlNum(sunElDeg, 1, info.x + vx, yr + lh, val, IL_INK, IL_LEFT) + 3.0 * s;
            dlLabel(LB_DEG, info.x + vx + w, yr + lh, cap, IL_DIM, IL_LEFT);
            caption(LB_C_AZIM, info.x, yr + 2.0 * lh, s);
            w = dlInt((int)round(sunAzDeg), 1, info.x + vx, yr + 2.0 * lh, val, IL_INK, IL_LEFT) + 3.0 * s;
            dlLabel(LB_DEG, info.x + vx + w, yr + 2.0 * lh, cap, IL_DIM, IL_LEFT);
            caption(LB_C_RISE, x1, yr, s);
            dlClock(rise, x1 + vx, yr, val, IL_MID, IL_LEFT);
            caption(LB_C_SET, x1, yr + lh, s);
            dlClock(set, x1 + vx, yr + lh, val, IL_MID, IL_LEFT);
            if (golden) dlLabel(LB_GOLDEN, x1, yr + 2.0 * lh, IL_T_BODY * s, sunInk, IL_LEFT);
        }
        // chips: a selected light's, or the sun's
        bool selOn = false;
        if (sel >= 0 && sel < LIGHT_ROLES) selOn = LightBuf[lightRec(sel)].head.z > 0.5;
        uint chip0 = (sel >= 0) ? LB_CH_ONOFF : LB_CH_GOLD;
        [loop] for (int c = 0; c < 4; c++)
            dlChip(lChipRect(L, c), s, chip0 + (uint)c, sel >= 0 && c == 0 && selOn, hotChip == c, hotChip == c && down);

        // the rack: every light at a glance, in its own colour, with its switch
        [loop] for (int rk = 0; rk < RACK_ROWS; rk++)
        {
            float4 rr = lRowRect(L, rk);
            BRRec lr = LightBuf[lightRec(rk)];
            bool e = lr.dims.w > 0.5;
            bool isOn = e && lr.head.z > 0.5;
            bool isSel = rk == sel;
            bool hot = rk == hotRow;
            float3 face = isSel ? IL_RAISE * 1.9 : (hot && e ? IL_RAISE * 1.45 : IL_RAISE);
            dlRectEdged(rr, face, 1.0, IL_RADIUS * s, isSel ? IL_RULE : IL_EDGE, 1.0);
            if (isSel) dlRect(float4(rr.x + 1.0, rr.y + 5.0 * s, rr.x + 1.0 + 2.0 * s, rr.w - 5.0 * s), IL_ACCENT, 1.0, 1.0);
            float cy = ilMid(rr).y;
            float4 swr = float4(rr.x + 9.0 * s, cy - 5.0 * s, rr.x + 19.0 * s, cy + 5.0 * s);
            dlRect(swr, e ? ptSampleColour(lr.look.rgb) : IL_DIM, isOn ? 1.0 : 0.25, 1.5 * s);
            dlLabel(LB_R0 + (uint)rk, rr.x + 27.0 * s, cy, IL_T_TITLE * s, e ? (isSel ? IL_ACCENT : IL_INK) : IL_DIM, IL_LEFT);
            if (e)
            {
                dlNum(lr.dims.x, 2, rr.x + 118.0 * s, cy, val, isOn ? IL_INK : IL_DIM, IL_LEFT);
                float kw = dlInt((int)round(lr.dims.y), 1, rr.x + 156.0 * s, cy, val, IL_DIM, IL_LEFT) + 2.0 * s;
                dlLabel(LB_K, rr.x + 156.0 * s + kw, cy, cap, IL_DIM, IL_LEFT);
                dlToggle(lRowSwitch(L, rk), s, isOn, hot && hotSw);
            }
        }
    }

    // =========================================================================================
    // PLAN: where the light lands
    {
        float tx = paneChrome(L.planR, s, LB_PLAN);
        float4 ph = ilPaneHead(L.planR, s);
        float py = ilMid(ph).y;
        float hw = hintW(s, LB_K_CLICK, LB_D_LIGHT) + hintW(s, LB_K_DRAG, LB_D_RING);
        if (ph.z - 10.0 * s - hw > tx)
        {
            float hx = ph.z - 10.0 * s - hw;
            hx += hint(hx, py, s, LB_K_CLICK, LB_D_LIGHT);
            hint(hx, py, s, LB_K_DRAG, LB_D_RING);
        }
        dlClip(L.planBody);
        float ny = L.planBody.y + 14.0 * s;
        if (!haveShell) { dlLabel(LB_NOSHELL, L.planBody.x + 10.0 * s, ny, cap, IL_INK, IL_LEFT); ny += 16.0 * s; }
        if (!haveFurn) dlLabel(LB_NOFURN, L.planBody.x + 10.0 * s, ny, cap, IL_INK, IL_LEFT);

        // the sun's bearing into the room
        if (sd.y > 0.0)
        {
            float2 sh2 = -normalize(sd.xz + 1e-5);
            float2 cen = float2((rm.x0 + rm.x1) * 0.5, (rm.z0 + rm.z1) * 0.5);
            float2 Pa = lPlanPx(L, cen - sh2 * 0.9), Pb = lPlanPx(L, cen + sh2 * 0.9);
            dlDashed(Pa, Pb, 1.2, sunInk, 1.0, 5.4 * s, 3.6 * s);
            float2 dv = normalize(Pb - Pa + 1e-5), sv = float2(-dv.y, dv.x);
            dlLine(Pb, Pb - dv * 8.0 * s + sv * 4.0 * s, 1.4, sunInk, 1.0);
            dlLine(Pb, Pb - dv * 8.0 * s - sv * 4.0 * s, 1.4, sunInk, 1.0);
        }

        // lamps and the fire: rings of equal floor illuminance in their own colour. Every light shows
        // its middle pool (the ring you drag); the selected one shows the bright core and the faint
        // fringe as well
        [loop] for (int k = 0; k < LIGHT_ROLES; k++)
        {
            if (ex[k])
            {
                BRRec lr = LightBuf[lightRec(k)];
                bool isOn = lr.head.z > 0.5;
                float h = max(bulb[k].y, 0.1);
                float3 lc = isOn ? ptSampleColour(lr.look.rgb) : IL_DIM;
                bool isSel = k == sel;
                bool ringHot = k == hotLight && hotRing;
                bool dotHot = k == hotLight && !hotRing;
                bool ringHeld = isSel && dragging && handle == H_RING;
                float2 bp = lPlanPx(L, bulb[k].xz);
                float a = isOn ? 1.0 : 0.5;
                float rMid = lRingRadius(pw[k], h, LIGHT_RING_E) * L.scale;
                if (isSel)
                {
                    float rCore = lRingRadius(pw[k], h, 1.0) * L.scale, rFringe = lRingRadius(pw[k], h, 0.12) * L.scale;
                    if (rCore > 0.0) dlEllipse(bp, float2(rCore, rCore), 0.9, IL_ACCENT, a, 3.14159 * rCore / 40.0, 3.14159 * rCore / 40.0);
                    if (rFringe > 0.0) dlEllipse(bp, float2(rFringe, rFringe), 0.9, IL_ACCENT, a, 3.14159 * rFringe / 40.0, 3.14159 * rFringe / 40.0);
                }
                if (rMid > 0.0)
                    dlRing(bp, rMid, isSel ? 2.2 : (ringHot ? 2.0 : 1.5), isSel ? IL_ACCENT : (ringHot ? IL_INK : lc), (ringHot || isSel) ? 1.0 : a);
                // the bulb: filled when on, ringed always
                float rb = max(0.06 * L.scale, 3.0 * s);
                if (isOn) dlCircle(bp, rb, lc, 1.0);
                dlRing(bp, rb, dotHot ? 2.0 : 1.2, isSel ? IL_ACCENT : (dotHot ? IL_INK : lc), 1.0);
                // its name (and, while its ring is held or under the pointer, its reach), left of the
                // light when the right would run off the plan
                bool showReach = tooltips != 0 && (ringHeld || ringHot);     // the reach tag (Tooltips; the readout keeps it)
                float reach = rMid / L.scale;
                float nameW = ilLabelW(LB_R0 + (uint)k, cap);
                float reachW = showReach ? 8.0 * s + ilNumW(ilFormat(reach, 2, 1, false).n, val) + 3.0 * s + ilLabelW(LB_M, cap) : 0.0;
                float lw = nameW + reachW;
                float lx = (bp.x + 8.0 * s + lw > L.planBody.z - 6.0 * s) ? bp.x - 8.0 * s - lw : bp.x + 8.0 * s;
                float ly = bp.y - 12.0 * s;
                lx += dlLabel(LB_R0 + (uint)k, lx, ly, cap, isSel ? IL_ACCENT : IL_DIM, IL_LEFT) + 8.0 * s;
                if (showReach)
                {
                    lx += dlNum(reach, 2, lx, ly, val, ringHeld ? IL_ACCENT : IL_INK, IL_LEFT) + 3.0 * s;
                    dlLabel(LB_M, lx, ly, cap, IL_DIM, IL_LEFT);
                }
            }
        }
        dlClipReset();
    }

    dlFinish();
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    if (gi == 0u) layout();
    dlEnd(gi);
}
