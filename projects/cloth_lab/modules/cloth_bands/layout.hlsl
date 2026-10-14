// Audio Bands / layout - the panel's type and chrome, recorded for the shared UI kit (ui.hlsl draws
// it over render.hlsl's spectrum and strips):
//
//   - the title row, with what every threshold is measured against (rolling level, or the fixed
//     reference in dB);
//   - the plate borders and the octave ruler;
//   - per band, its name, its measured span and its level (greyed and marked GATED under the
//     signal gate, which is why a lane can be dead), and the threshold value beside its fader;
//   - per strip, its name (flashing the accent on a hit), its current full scale, its hit count
//     and its detection lamp;
//   - the inspector: the band under the pointer (or in hand) with every live figure that decides
//     whether it fires, the hop under the pointer in a strip, and a frequency cursor;
//   - the keycap footer, the module's three real gestures.
//
// Hover is read from the pointer snapshot here and never stored. Everything is placed through
// bands_view.hlsli and bands.hlsli, the functions the drawing and the event pass use.
#include "bands.hlsli"
StructuredBuffer<float4> Cols  : register(t0);
StructuredBuffer<float4> Bands : register(t1);
StructuredBuffer<float4> Det   : register(t2);
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"
#include "bands_view.hlsli"

static float  g_s;
static float2 g_R;

// A key and what it does, for the footer; returns the width used.
float hintW(uint key, uint does)
{
    float s = g_s;
    return ilLabelW(key, IL_T_CAP * s) + 12.0 * s + 6.0 * s + ilLabelW(does, IL_T_CAP * s) + 16.0 * s;
}
float hint(float x, float y, uint key, uint does)
{
    float s = g_s;
    float kw = ilLabelW(key, IL_T_CAP * s) + 12.0 * s, kh = 18.0 * s;
    dlKeycap(float4(x, y - 0.5 * kh, x + kw, y + 0.5 * kh), s, key);
    return kw + 6.0 * s + dlLabel(does, x + kw + 6.0 * s, y, IL_T_CAP * s, IL_DIM, IL_LEFT) + 16.0 * s;
}

// A card of size sz beside the pointer, flipped away from any edge it would cross.
float4 card(float2 at, float2 sz)
{
    float s = g_s;
    float2 o = at + 16.0 * s;
    if (o.x + sz.x > g_R.x - 6.0 * s) o.x = at.x - 16.0 * s - sz.x;
    if (o.y + sz.y > g_R.y - 6.0 * s) o.y = at.y - 16.0 * s - sz.y;
    o = clamp(o, 6.0 * s, max(g_R - sz - 6.0 * s, 6.0 * s));
    float4 r = float4(o, o + sz);
    dlRectEdged(r, IL_RAISE, 1.0, IL_RADIUS * s, IL_EDGE, 1.0);
    return r;
}

// One card row: caption left, value and unit right.
void row(float4 c, float y, uint cap, float v, int dec, uint unit, float3 ink)
{
    float s = g_s;
    dlLabel(cap, c.x + 10.0 * s, y, IL_T_CAP * s, IL_DIM, IL_LEFT);
    float uw = dlLabel(unit, c.z - 10.0 * s, y, IL_T_CAP * s, IL_DIM, IL_RIGHT);
    dlNum(v, dec, c.z - 13.0 * s - uw, y, IL_T_VALUE * s, ink, IL_RIGHT);
}

// A frequency, as Hz under 1 kHz and kHz above; returns the width.
float freq(float hz, float x, float y, float3 ink)
{
    float s = g_s;
    bool k = hz >= 1000.0;
    float w = dlNum(k ? hz / 1000.0 : hz, k ? 2 : 0, x, y, IL_T_VALUE * s, ink, IL_LEFT) + 3.0 * s;
    return w + dlLabel(k ? LB_U_KHZ : LB_U_HZ, x + w, y, IL_T_CAP * s, IL_DIM, IL_LEFT);
}

// ---------------------------------------------------------------- the band under the pointer
void bandCard(uint L, float2 at, float hzMax)
{
    float s = g_s;
    float4 b = Bands[L];
    float4 A = Det[abStateA(L)];
    float4 B = Det[abStateB(L)];
    float4 C = Det[abStateC(L)];
    bool gated = C.y > 0.5;
    // the absolute level a hop must clear right now: the reference (the fixed one, or the band's
    // own rolling level) plus the lane's threshold - the very comparison detect.hlsl makes
    float trigger = ((adapt_mode == 1) ? fixed_ref_db : A.x) + b.w;
    float rh = 15.0 * s;
    float4 c = card(at, float2(184.0 * s, 9.0 * s + 7.0 * rh));
    float y = c.y + 4.0 * s + 0.5 * rh;
    dlCircle(float2(c.x + 13.0 * s, y), 3.0 * s, ptId((int)L), 1.0);
    dlLabel(LB_L_KICK + L, c.x + 21.0 * s, y, IL_T_TITLE * s, IL_INK, IL_LEFT);
    float ow = dlLabel(LB_U_OCT, c.z - 10.0 * s, y, IL_T_CAP * s, IL_DIM, IL_RIGHT);
    dlNum(log2(max(b.y, 1.0) / max(b.x, 1.0)), 2, c.z - 13.0 * s - ow, y, IL_T_VALUE * s, IL_MID, IL_RIGHT);
    y += rh;
    // the span, lo - hi
    dlLabel(LB_C_SPAN, c.x + 10.0 * s, y, IL_T_CAP * s, IL_DIM, IL_LEFT);
    float x = c.z - 10.0 * s;
    x -= dlLabel(LB_U_HZ, x, y, IL_T_CAP * s, IL_DIM, IL_RIGHT) + 3.0 * s;
    x -= dlNum(b.y, 0, x, y, IL_T_VALUE * s, IL_INK, IL_RIGHT) + 3.0 * s;
    x -= dlLabel(LB_DASH, x, y, IL_T_VALUE * s, IL_DIM, IL_RIGHT) + 3.0 * s;
    dlNum(b.x, 0, x, y, IL_T_VALUE * s, IL_INK, IL_RIGHT);
    y += rh;
    row(c, y, LB_C_THRESH, b.w, 1, LB_U_DB, IL_INK);
    y += rh;
    row(c, y, LB_C_FIRES, trigger, 1, LB_U_DB, IL_INK);
    y += rh;
    row(c, y, LB_C_LEVEL, C.x, 1, LB_U_DB, gated ? IL_DIM : IL_INK);
    if (gated) dlLabel(LB_GATED, c.x + 44.0 * s, y, IL_T_CAP * s, IL_DIM, IL_LEFT);
    y += rh;
    row(c, y, LB_C_PEAK, B.w, 1, LB_U_DB, IL_INK);
    y += rh;
    dlLabel(LB_HITS, c.x + 10.0 * s, y, IL_T_CAP * s, IL_DIM, IL_LEFT);
    dlInt((int)B.x, 1, c.z - 10.0 * s, y, IL_T_VALUE * s, IL_INK, IL_RIGHT);
}

// ---------------------------------------------------------------- the hop under the pointer
void laneCard(uint lane, float2 at, float hopDt)
{
    float s = g_s;
    float4 pr = abLanePlot(lane, g_R);
    float nShow = abTraceShow(hopDt);
    float plotW = pr.z - pr.x;
    float u0 = (at.x - pr.x) / plotW, u1 = (at.x + 1.0 - pr.x) / plotW;
    int kA = (int)floor(u0 * nShow);
    int kB = min((int)floor(u1 * nShow), kA + 8);
    uint wIdx = (uint)max(Det[abStateB(lane)].z, 0.0);
    // the same reduction the strip draws: the most of each over the hops this pixel covers
    float flux = 0.0, thr = 0.0, fired = 0.0, lvl = -120.0, newest = -1.0;
    [loop] for (int k = kA; k <= kB; ++k)
    {
        float fk = (float)wIdx - nShow + (float)k;
        if (fk >= 0.0)                                // one exit per iteration, no `continue`
        {
            float4 tv = Det[abTraceAt(lane, (uint)fk)];
            flux = max(flux, tv.x); thr = max(thr, tv.y); fired = max(fired, tv.z); lvl = max(lvl, tv.w);
            newest = max(newest, fk);
        }
    }
    if (newest < 0.0) return;                         // before the ring has filled this far back
    float fs = abFullScale(lane);
    float gTop = pr.y + 1.0, gBot = pr.w - 1.0;
    dlVLine(at.x, pr.y, pr.w, IL_MID);
    dlCircle(float2(at.x, gBot - saturate(flux / fs) * (gBot - gTop)), 2.5 * s, fired > 0.5 ? IL_ACCENT : IL_INK, 1.0);

    float rh = 15.0 * s;
    float4 c = card(at, float2(168.0 * s, 9.0 * s + (fired > 0.5 ? 5.0 : 4.0) * rh));
    float y = c.y + 4.0 * s + 0.5 * rh;
    dlCircle(float2(c.x + 13.0 * s, y), 3.0 * s, ptId((int)lane), 1.0);
    dlLabel(LB_L_KICK + lane, c.x + 21.0 * s, y, IL_T_TITLE * s, IL_INK, IL_LEFT);
    float aw = dlLabel(LB_C_AGO, c.z - 10.0 * s, y, IL_T_CAP * s, IL_DIM, IL_RIGHT);
    dlNum(max((float)wIdx - 1.0 - newest, 0.0) * hopDt, 2, c.z - 13.0 * s - aw, y, IL_T_VALUE * s, IL_MID, IL_RIGHT);
    y += rh;
    row(c, y, LB_C_FLUX, flux, 1, LB_U_DB, fired > 0.5 || flux > thr ? IL_ACCENT : IL_INK);
    y += rh;
    row(c, y, LB_C_THRESH, thr, 1, LB_U_DB, IL_INK);
    y += rh;
    row(c, y, LB_C_LEVEL, lvl, 1, LB_U_DB, lvl <= AB_SILENCE_DB ? IL_DIM : IL_INK);
    if (fired > 0.5) dlLabel(LB_HIT, c.x + 10.0 * s, y + rh, IL_T_TITLE * s, IL_ACCENT, IL_LEFT);
}

void layout()
{
    float2 R = g_R;
    float  s = g_s;
    float  W = R.x, H = R.y;
    dlBegin(R);

    float4 hdr = Cols[AB_COL_HDR];
    float hzMax = hdr.y, hopDt = hdr.z;
    float plotTop = abPlotTop(H), plotBot = abPlotBot(H);
    float4 sp = abSpecPlate(R);

    int    held    = abHeldLane();
    bool   heldBar = held >= 0 && abHeldBar();
    float2 ptr     = abPointer(R);
    int    hot     = (held < 0) ? abBandAt(ptr, R, hzMax) : -1;
    bool   hotBar  = hot >= 0 && abOnBar(ptr, (uint)hot, H);
    int    hotLane = (held < 0 && hot < 0) ? abLaneAt(ptr, R) : -1;
    float  vs = IL_T_VALUE * s, cs = IL_T_CAP * s;

    // ---- title row: the instrument, then what every threshold is measured against
    float ty = 0.5 * sp.y;
    float tsz = min(14.0 * s, max(sp.y * 0.95, 10.0));
    float csz = min(IL_T_TITLE * s, tsz * 0.82);
    float x = W - 10.0 * s;
    if (adapt_mode == 1)
    {
        x -= dlLabel(LB_U_DB, x, ty, csz, IL_DIM, IL_RIGHT) + 3.0 * s;
        x -= dlNum(fixed_ref_db, 0, x, ty, csz * 1.1, IL_INK, IL_RIGHT) + 6.0 * s;
        x -= dlLabel(LB_FIXED, x, ty, csz, IL_INK, IL_RIGHT) + 7.0 * s;
    }
    else x -= dlLabel(LB_ROLLING, x, ty, csz, IL_INK, IL_RIGHT) + 7.0 * s;
    x -= dlLabel(LB_REFERENCE, x, ty, csz, IL_DIM, IL_RIGHT);
    float tw = dlLabel(LB_TITLE, 10.0 * s, ty, tsz, IL_INK, IL_LEFT);
    dlLabelFit(LB_SUBTITLE, 20.0 * s + tw, ty, tsz * 0.86, IL_DIM, IL_LEFT, x - 34.0 * s - tw);

    // ---- the spectrum plate and its octave ruler
    dlBorderRect(sp, IL_RADIUS * s, IL_EDGE, 1.0);
    float ry = 0.5 * (plotBot + sp.w) + 1.0 * s;
    float lastX = 0.0;
    [loop] for (int o = 0; o < 10; ++o)
    {
        float hz = abOctHz(o);
        if (hz > hzMax) break;
        float gx = abHzToX(hz, hzMax) * W + 3.0 * s;
        lastX = gx + dlLabel(LB_HZ_31 + (uint)o, gx, ry, cs, IL_DIM, IL_LEFT);
    }
    float hzw = ilLabelW(LB_U_HZ, cs);
    if (hzMax > 0.0 && lastX + 8.0 * s < W - 10.0 * s - hzw) dlLabel(LB_U_HZ, W - 10.0 * s, ry, cs, IL_DIM, IL_RIGHT);
    if (hzMax <= 0.0) dlLabel(LB_WAITING, 0.5 * W, 0.5 * (plotTop + plotBot), IL_T_BODY * s, IL_DIM, IL_CENTER);

    // ---- per band: name, span and level as a block clamped to the panel (not row by row, so
    // the rows stay left-aligned at exactly the sizes where the clamp matters), and the threshold
    // value beside its fader
    [loop] for (uint L = 0u; L < AB_LANES; ++L)
    {
        float4 b = Bands[L];
        // one exit per iteration, no `continue` (fxc can drop the draws of a [loop] that has one)
        if (b.z > 0.5 && b.y > b.x && hzMax > 0.0)
        {
            float x0 = abHzToX(b.x, hzMax) * W;
            float x1 = abHzToX(b.y, hzMax) * W;
            bool  isHeld = ((int)L == held), isHot = ((int)L == hot);
            bool  lifted = isHeld || isHot;
            float4 C = Det[abStateC(L)];
            bool  gated = C.y > 0.5;
            float3 val = lifted ? IL_INK : IL_MID;

            float dashW = ilLabelW(LB_DASH, vs);
            float spanW = ilNumW(ilFormat(b.x, 0, 1, false).n, vs) + dashW + ilNumW(ilFormat(b.y, 0, 1, false).n, vs) + 9.0 * s + ilLabelW(LB_U_HZ, cs);
            float lvlW = ilNumW(ilFormat(C.x, 0, 1, false).n, vs) + 3.0 * s + ilLabelW(LB_U_DB, cs) + (gated ? 6.0 * s + ilLabelW(LB_GATED, cs) : 0.0);
            float blockW = max(max(spanW, lvlW), 10.0 * s + ilLabelW(LB_L_KICK + L, IL_T_TITLE * s));
            float bx = clamp(x0 + 6.0 * s, 6.0 * s, max(W - blockW - 6.0 * s, 6.0 * s));
            float y1 = plotTop + 12.0 * s, y2 = y1 + 15.0 * s, y3 = y2 + 14.0 * s;
            // a band narrower than its words gets a plate under them, so its own edge does not run
            // through the figures (the edge still shows above and below the block)
            if (bx + blockW > x1 - 4.0 * s)
                dlRect(float4(bx - 4.0 * s, y1 - 8.0 * s, bx + blockW + 4.0 * s, y3 + 8.0 * s), IL_PANEL, 0.86, IL_RADIUS * s);

            dlCircle(float2(bx + 3.0 * s, y1), 3.0 * s, ptId((int)L), 1.0);
            dlLabel(LB_L_KICK + L, bx + 10.0 * s, y1, IL_T_TITLE * s, val, IL_LEFT);
            float sx = bx;
            sx += dlNum(b.x, 0, sx, y2, vs, val, IL_LEFT) + 3.0 * s;
            sx += dlLabel(LB_DASH, sx, y2, vs, IL_DIM, IL_LEFT) + 3.0 * s;
            sx += dlNum(b.y, 0, sx, y2, vs, val, IL_LEFT) + 3.0 * s;
            dlLabel(LB_U_HZ, sx, y2, cs, IL_DIM, IL_LEFT);
            // level, and a mark when it is under the signal gate: without it a gated lane is simply
            // dead with no visible reason, the worst failure for a detector you are trying to tune
            float lx = bx;
            lx += dlNum(C.x, 0, lx, y3, vs, gated ? IL_DIM : val, IL_LEFT) + 3.0 * s;
            lx += dlLabel(LB_U_DB, lx, y3, cs, IL_DIM, IL_LEFT) + 6.0 * s;
            if (gated) dlLabel(LB_GATED, lx, y3, cs, IL_DIM, IL_LEFT);

            // the threshold, printed beside its bar so the fader reads as a number and not only as a
            // height; above the bar, or under it when the bar is near the top
            float u = abUI(H);
            float barY = abThreshToY(b.w, H);
            bool  bHeld = isHeld && heldBar, bHot = isHot && hotBar;
            float tyb = (barY - 10.0 * s > plotTop + 6.0 * s) ? barY - 10.0 * s : barY + 10.0 * s;
            float tx = x1 - 6.5 * u - 4.0 * s;
            float tw = ilNumW(ilFormat(b.w, 1, 1, false).n, vs) + 3.0 * s + ilLabelW(LB_U_DB, cs);
            float3 tc = bHeld ? IL_ACCENT : (bHot || isHeld ? IL_INK : IL_MID);
            if (tx - tw < x0 + 4.0 * s && x1 + 4.0 * s + tw < W - 6.0 * s)
            {
                // no room left of the tab inside a narrow band: just right of the band, beside the tab
                float rx = x1 + 4.0 * s;
                rx += dlNum(b.w, 1, rx, tyb, vs, tc, IL_LEFT) + 3.0 * s;
                dlLabel(LB_U_DB, rx, tyb, cs, IL_DIM, IL_LEFT);
            }
            else
            {
                tx -= dlLabel(LB_U_DB, tx, tyb, cs, IL_DIM, IL_RIGHT) + 3.0 * s;
                dlNum(b.w, 1, tx, tyb, vs, tc, IL_RIGHT);
            }
        }
    }

    // ---- per strip: name (the accent flashes on a hit), full scale, hit count, lamp
    float capH = abCapH(R);
    [loop] for (uint l = 0u; l < AB_LANES; ++l)
    {
        float4 lr = abLaneRect(l, R);
        bool lifted = ((int)l == held) || ((int)l == hot) || ((int)l == hotLane);
        dlBorderRect(lr, IL_RADIUS * s, lifted ? IL_RULE : IL_EDGE, 1.0);
        float cy = lr.y + 0.5 * capH + 1.0 * s;
        float env = saturate(Det[abStateA(l)].w);
        dlCircle(float2(lr.x + 13.0 * s, cy), 3.0 * s, ptId((int)l), 1.0);
        dlLabel(LB_L_KICK + l, lr.x + 21.0 * s, cy, IL_T_TITLE * s, lerp(lifted ? IL_INK : IL_MID, IL_ACCENT, env), IL_LEFT);
        float fx = lr.x + 21.0 * s + 50.0 * s;
        fx += dlLabel(LB_SCALE, fx, cy, cs, IL_DIM, IL_LEFT) + 5.0 * s;
        fx += dlNum(abFullScale(l), 0, fx, cy, vs, IL_MID, IL_LEFT) + 3.0 * s;
        dlLabel(LB_U_DB, fx, cy, cs, IL_DIM, IL_LEFT);
        float hx = lr.z - 10.0 * s;
        hx -= dlLabel(LB_HITS, hx, cy, cs, IL_DIM, IL_RIGHT) + 4.0 * s;
        dlInt((int)Det[abStateB(l)].x, 1, hx, cy, vs, IL_INK, IL_RIGHT);
        dlRectEdged(abLamp(l, R), lerp(IL_WELL, IL_ACCENT, env), 1.0, 2.0 * s, lerp(IL_EDGE, IL_ACCENT, env), 1.0);
    }

    // ---- the inspector. A frequency cursor anywhere over the plot; the band under the pointer
    // (or in hand, as it is dragged); or the hop under the pointer in a strip.
    if (hzMax > 0.0 && ptr.x >= 0.0 && ptr.y > plotTop && ptr.y < plotBot)
    {
        dlVLine(ptr.x, plotTop, plotBot, IL_RULE);
        if (tooltips != 0)                       // Tooltips: the Hz / dB tag at the cursor
        {
            float hz = abXToHz(ptr.x / W, hzMax);
            float cwid = min(W, (float)AB_COLS_MAX);
            float lvl01 = Cols[(uint)clamp(floor(ptr.x / W * cwid), 0.0, cwid - 1.0)].x;
            float floorDb = min(db_floor, -6.0);
            float db = floorDb + lvl01 * (0.0 - floorDb);
            bool k = hz >= 1000.0;
            float tagW = ilNumW(ilFormat(k ? hz / 1000.0 : hz, k ? 2 : 0, 1, false).n, vs) + 3.0 * s + ilLabelW(k ? LB_U_KHZ : LB_U_HZ, cs)
                       + 10.0 * s + ilNumW(ilFormat(db, 0, 1, false).n, vs) + 3.0 * s + ilLabelW(LB_U_DB, cs) + 16.0 * s;
            float tx0 = clamp(ptr.x - 0.5 * tagW, sp.x + 2.0 * s, sp.z - tagW - 2.0 * s);
            float4 tag = float4(tx0, ry - 9.0 * s, tx0 + tagW, ry + 9.0 * s);
            dlRectEdged(tag, IL_RAISE, 1.0, IL_RADIUS * s, IL_RULE, 1.0);
            float tx = tag.x + 8.0 * s;
            tx += freq(hz, tx, ry, IL_INK) + 10.0 * s;
            tx += dlNum(db, 0, tx, ry, vs, IL_MID, IL_LEFT) + 3.0 * s;
            dlLabel(LB_U_DB, tx, ry, cs, IL_DIM, IL_LEFT);
        }
    }
    // Tooltips: the band card (hovered or held) and the hop card beside the pointer
    int insp = (held >= 0) ? held : hot;
    if (tooltips != 0 && insp >= 0 && ptr.x >= 0.0) bandCard((uint)insp, ptr, hzMax);
    else if (tooltips != 0 && hotLane >= 0 && hopDt > 0.0 && ilIn(ptr, abLanePlot((uint)hotLane, R))) laneCard((uint)hotLane, ptr, hopDt);

    // ---- footer: the gestures
    float fh = abFootH(R);
    if (fh > 0.0)
    {
        float fy = H - 0.5 * fh;
        float hx = 10.0 * s;
        hx += hint(hx, fy, LB_K_DRAG, LB_D_MOVE);
        hx += hint(hx, fy, LB_K_BAR, LB_D_THRESH);
        hx += hint(hx, fy, LB_K_RDRAG, LB_D_RESIZE);
        if (hx + hintW(LB_K_HOVER, LB_D_INSPECT) < W) hint(hx, fy, LB_K_HOVER, LB_D_INSPECT);
    }
    dlFinish();
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    g_R = _Resolution.xy;
    g_s = abS(g_R);
    if (gi == 0u) layout();
    dlEnd(gi);
}
