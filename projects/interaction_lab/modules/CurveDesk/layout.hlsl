// Curve Desk / layout - the channel list, the graph, the spacing chart and the chrome.
//
// Three steps in one group of 64 threads:
//   1. one thread per channel plans its curve as line pieces: a hold before the first key and
//      after the last, then per segment 2 for a step, 1 for a linear, and one per ~6 px of the
//      control polygon for a bezier (segments outside the view get none);
//   2. thread 0 records everything else, reserving one batch for the pieces at its place in
//      painter's order (above the grid, under the loop veil and the keys);
//   3. every thread draws pieces. A bezier piece is a chord of the curve in its own parameter,
//      so steep segments stay smooth without solving for time.
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"
#include "../_shared/ui/il_pane.hlsli"
#include "curve.hlsli"

StructuredBuffer<float4> C : register(t1);

#define CV_PIECES 720u
#define DM_KEY    1u
#define DM_HANDLE 2u
#define DM_BOX    3u

groupshared uint gsOff[CV_CH][CV_KMAX + 2u];
groupshared uint gsN[CV_CH];
groupshared uint gsTot[CV_CH];

static CvLayout g_L;
static float2 g_tw, g_vw;
static uint g_packed;
static float g_len, g_fps, g_s;

void plate(float4 r) { dlRect(r, IL_PANEL, 0.86, IL_RADIUS * g_s); }
float3 chCol(uint c) { return ptId((int)c); }
float2 toS(float2 w) { return cvP(g_L, g_tw, g_vw, w); }
float pxT() { return (g_L.graph.z - g_L.graph.x) / max(g_tw.y - g_tw.x, 1e-6); }
float pxV() { return (g_L.graph.w - g_L.graph.y) / max(g_vw.y - g_vw.x, 1e-6); }

// ---------------------------------------------------------------- curve pieces
// entry 0 = the hold before the first key, entry n = the hold after the last, entry e = the
// segment from key e-1 to key e
uint piecesFor(uint c, uint n, uint e)
{
    if (e == 0u) return cvKey(c, 0u).a.x > g_tw.x ? 1u : 0u;
    if (e == n) return cvKey(c, n - 1u).a.x < g_tw.y ? 1u : 0u;
    CvRec k0 = cvKey(c, e - 1u), k1 = cvKey(c, e);
    if (k1.a.x < g_tw.x || k0.a.x > g_tw.y) return 0u;
    uint m = cvInterp(k0.e);
    if (m == CV_STEP) return 2u;
    if (m == CV_LINEAR) return 1u;
    float2 p0 = 0.0, p1 = 0.0, p2 = 0.0, p3 = 0.0;
    cvSegCtl(k0, k1, p0, p1, p2, p3);
    float len = length(toS(p1) - toS(p0)) + length(toS(p2) - toS(p1)) + length(toS(p3) - toS(p2));
    return clamp((uint)ceil(len / (6.0 * g_s)), 2u, 40u);
}

void piece(uint c, uint n, uint e, uint i, uint m)
{
    float2 a, b;
    if (e == 0u)
    {
        CvRec k = cvKey(c, 0u);
        a = float2(g_tw.x, k.a.y);
        b = k.a;
    }
    else if (e == n)
    {
        CvRec k = cvKey(c, n - 1u);
        a = k.a;
        b = float2(g_tw.y, k.a.y);
    }
    else
    {
        CvRec k0 = cvKey(c, e - 1u), k1 = cvKey(c, e);
        uint mode = cvInterp(k0.e);
        if (mode == CV_STEP)
        {
            float2 corner = float2(k1.a.x, k0.a.y);
            a = (i == 0u) ? k0.a : corner;
            b = (i == 0u) ? corner : k1.a;
        }
        else if (mode == CV_LINEAR)
        {
            a = k0.a;
            b = k1.a;
        }
        else
        {
            float2 p0 = 0.0, p1 = 0.0, p2 = 0.0, p3 = 0.0;
            cvSegCtl(k0, k1, p0, p1, p2, p3);
            a = cvBez(p0, p1, p2, p3, (float)i / (float)m);
            b = cvBez(p0, p1, p2, p3, (float)(i + 1u) / (float)m);
        }
    }
    dlLine(toS(a), toS(b), 1.5 * g_s, chCol(c), 1.0);
}

// ---------------------------------------------------------------- the header
float numW(uint cells, float size) { return ilNumW(cells, size); }

void header(CvRec h0, CvRec h1, uint nsel, uint selKey)
{
    float s = g_s;
    float4 hd = g_L.head;
    float hy = ilMid(hd).y;
    float tw = ilLabelW(LB_TITLE, 15.0 * s), sw = ilLabelW(LB_SUBTITLE, 12.0 * s);
    float4 hp = float4(hd.x, hd.y, hd.x + tw + sw + 40.0 * s, hd.w);
    plate(hp);
    dlLabel(LB_TITLE, hp.x + 12.0 * s, hy, 15.0 * s, IL_INK, IL_LEFT);
    dlLabel(LB_SUBTITLE, hp.x + 12.0 * s + tw + 14.0 * s, hy, 12.0 * s, IL_DIM, IL_LEFT);

    // transport: playing / paused, the frame and the time
    bool playing = (h1.e & CV_PLAYING) != 0u;
    uint state = playing ? LB_PLAYING : LB_PAUSED;
    float frames = round(g_len * g_fps);
    float frame = floor(h0.c * g_fps + 1e-4);
    float cap = IL_T_CAP * s, val = IL_T_VALUE * s;
    float w = 22.0 * s + ilLabelW(state, cap) + 18.0 * s + ilLabelW(LB_F, cap) + 6.0 * s + numW(2u, val)
            + ilLabelW(LB_SLASH, cap) + numW(2u, val) + 16.0 * s + numW(4u, val) + ilLabelW(LB_UNIT_S, cap) + 18.0 * s;
    float4 tp = float4(hd.z - w, hd.y, hd.z, hd.w);
    plate(tp);
    float x = tp.x + 12.0 * s;
    if (playing) dlTri(float2(x + 7.0 * s, hy), 4.0 * s, 7.0 * s, 3u, IL_INK, 1.0);
    else
    {
        dlRect(float4(x, hy - 4.0 * s, x + 2.5 * s, hy + 4.0 * s), IL_INK, 1.0, 0.0);
        dlRect(float4(x + 4.5 * s, hy - 4.0 * s, x + 7.0 * s, hy + 4.0 * s), IL_INK, 1.0, 0.0);
    }
    x += 14.0 * s;
    x += dlLabel(state, x, hy, cap, IL_INK, IL_LEFT) + 18.0 * s;
    x += dlLabel(LB_F, x, hy, cap, IL_DIM, IL_LEFT) + 6.0 * s;
    x += dlInt((int)frame, 2, x, hy, val, IL_INK, IL_LEFT);
    x += dlLabel(LB_SLASH, x, hy, cap, IL_DIM, IL_LEFT);
    x += dlInt((int)frames, 2, x, hy, val, IL_DIM, IL_LEFT) + 16.0 * s;
    x += dlNum(h0.c, 2, x, hy, val, IL_INK, IL_LEFT);
    dlLabel(LB_UNIT_S, x + 2.0 * s, hy, cap, IL_DIM, IL_LEFT);

    // the selection, left of the transport
    if (nsel == 0u) return;
    float right = tp.x - 8.0 * s;
    if (nsel > 1u)
    {
        float ww = numW(2u, val) + 8.0 * s + ilLabelW(LB_SELECTED, cap) + 24.0 * s;
        float4 sp = float4(right - ww, hd.y, right, hd.w);
        plate(sp);
        float sx = sp.x + 12.0 * s;
        sx += dlInt((int)nsel, 1, sx, hy, val, IL_ACCENT, IL_LEFT) + 8.0 * s;
        dlLabel(LB_SELECTED, sx, hy, cap, IL_DIM, IL_LEFT);
        return;
    }
    uint ch = selKey / CV_KMAX, i = selKey % CV_KMAX;
    CvRec k = cvKey(ch, i);
    uint im = cvInterp(k.e), hm = cvHandles(k.e);
    float ww = ilLabelW(LB_CH_0 + ch, cap) + 14.0 * s + ilLabelW(LB_KEY, cap) + 5.0 * s + numW(2u, val) + 14.0 * s
             + ilLabelW(LB_T, cap) + 5.0 * s + numW(5u, val) + ilLabelW(LB_UNIT_S, cap) + 14.0 * s
             + ilLabelW(LB_F, cap) + 5.0 * s + numW(2u, val) + 14.0 * s
             + ilLabelW(LB_V, cap) + 5.0 * s + numW(6u, val) + 14.0 * s
             + ilLabelW(LB_I_0 + im, cap) + 10.0 * s + ilLabelW(LB_H_0 + hm, cap) + 24.0 * s;
    float4 sp = float4(right - ww, hd.y, right, hd.w);
    plate(sp);
    float sx = sp.x + 12.0 * s;
    dlRect(float4(sx, hy - 5.0 * s, sx + 3.0 * s, hy + 5.0 * s), chCol(ch), 1.0, 0.0);
    sx += 8.0 * s;
    sx += dlLabel(LB_CH_0 + ch, sx, hy, cap, IL_INK, IL_LEFT) + 14.0 * s;
    sx += dlLabel(LB_KEY, sx, hy, cap, IL_DIM, IL_LEFT) + 5.0 * s;
    sx += dlInt((int)i + 1, 1, sx, hy, val, IL_ACCENT, IL_LEFT) + 14.0 * s;
    sx += dlLabel(LB_T, sx, hy, cap, IL_DIM, IL_LEFT) + 5.0 * s;
    sx += dlNum(k.a.x, 3, sx, hy, val, IL_INK, IL_LEFT);
    sx += dlLabel(LB_UNIT_S, sx + 1.0 * s, hy, cap, IL_DIM, IL_LEFT) + 14.0 * s;
    sx += dlLabel(LB_F, sx, hy, cap, IL_DIM, IL_LEFT) + 5.0 * s;
    sx += dlNum(k.a.x * g_fps, (abs(k.a.x * g_fps - round(k.a.x * g_fps)) < 1e-3) ? 0 : 1, sx, hy, val, IL_INK, IL_LEFT) + 14.0 * s;
    sx += dlLabel(LB_V, sx, hy, cap, IL_DIM, IL_LEFT) + 5.0 * s;
    sx += dlNumSigned(k.a.y, 3, sx, hy, val, IL_INK, IL_LEFT) + 14.0 * s;
    sx += dlLabel(LB_I_0 + im, sx, hy, cap, IL_MID, IL_LEFT) + 10.0 * s;
    dlLabel(LB_H_0 + hm, sx, hy, cap, IL_MID, IL_LEFT);
}

// ---------------------------------------------------------------- channel list
void channels(float2 pointer)
{
    float s = g_s;
    float4 l = g_L.list;
    dlLabel(LB_CHANNELS, l.x + 2.0 * s, l.y + 10.0 * s, IL_T_TITLE * s, IL_DIM, IL_LEFT);
    float4 live = C[1];
    [loop] for (uint c = 0u; c < CV_CH; c++)
    {
        float4 r = g_L.row[c];
        bool hidden = cvHidden(g_packed, c);
        bool hot = ilIn(pointer, r);
        dlRect(r, hot ? IL_RAISE : IL_WELL, 1.0, IL_RADIUS * s);
        float4 sw = float4(r.x + 10.0 * s, r.y + 11.0 * s, r.x + 13.0 * s, r.w - 11.0 * s);
        if (hidden) dlBorderRect(sw, 0.0, IL_RULE, 1.0 * s);
        else dlRect(sw, chCol(c), 1.0, 0.0);
        float y0 = r.y + 17.0 * s, y1 = r.y + 35.0 * s;
        dlLabel(LB_CH_0 + c, r.x + 22.0 * s, y0, IL_T_TITLE * s, hidden ? IL_DIM : IL_INK, IL_LEFT);
        dlLabel(LB_CH_0_D + c, r.x + 22.0 * s, y1, IL_T_CAP * s, IL_DIM, IL_LEFT);
        if (hidden) dlLabel(LB_HIDDEN, r.z - 10.0 * s, y0, IL_T_CAP * s, IL_DIM, IL_RIGHT);
        else dlNumSigned(live[c], 2, r.z - 10.0 * s, y0, IL_T_VALUE * s, IL_INK, IL_RIGHT);
        float kx = r.z - 10.0 * s;
        kx -= dlLabel(LB_KEYS, kx, y1, IL_T_CAP * s, IL_DIM, IL_RIGHT) + 4.0 * s;
        dlInt((int)cvCount(g_packed, c), 1, kx, y1, IL_T_CAP * s, IL_DIM, IL_RIGHT);
    }
}

// ---------------------------------------------------------------- graph: under the curves
void graphBack()
{
    float s = g_s;
    float4 g = g_L.graph, ru = g_L.ruler;
    dlRect(ru, IL_WELL, 1.0, 2.0 * s);
    dlRect(g, IL_WELL, 1.0, 2.0 * s);
    dlClip(float4(g.x, ru.y, g.z, g.w));

    // value grid, the zero line a step brighter
    float vstep = ilNiceStep(pxV(), 34.0 * s);
    int vdec = vstep < 0.1 ? 2 : 1;
    float v0 = ceil(g_vw.x / vstep) * vstep;
    [loop] for (int k = 0; k < 40; k++)
    {
        float v = v0 + k * vstep;
        if (v > g_vw.y) break;
        float y = cvY(g_L, g_vw, v);
        dlHLine(y, g.x, g.z, abs(v) < vstep * 0.25 ? IL_EDGE : IL_GRID);
        dlNumSigned(abs(v) < vstep * 0.25 ? 0.0 : v, vdec, g.x + 6.0 * s, y - 7.0 * s, IL_T_CAP * s, IL_DIM, IL_LEFT);
    }

    // time grid and ruler labels; frame ticks once frames are far enough apart
    float tstep = ilNiceStep(pxT(), 72.0 * s);
    int tdec = tstep < 0.1 ? 2 : (tstep < 1.0 ? 1 : 0);
    float t0 = ceil(g_tw.x / tstep) * tstep;
    float ry = ilMid(ru).y;
    [loop] for (int k2 = 0; k2 < 40; k2++)
    {
        float t = t0 + k2 * tstep;
        if (t > g_tw.y) break;
        float x = cvX(g_L, g_tw, t);
        dlVLine(x, g.y, g.w, IL_GRID);
        dlVLine(x, ru.w - 6.0 * s, ru.w, IL_RULE);
        if (x + 4.0 * s + numW(5u, IL_T_CAP * s) < ru.z)     // no label cut off at the edge
            dlNum(t, tdec, x + 4.0 * s, ry - 2.0 * s, IL_T_CAP * s, IL_DIM, IL_LEFT);
    }
    float frameStep = 1.0 / g_fps;
    if (frameStep * pxT() >= 5.0 * s)
    {
        float f0 = ceil(g_tw.x * g_fps);
        [loop] for (int k3 = 0; k3 < 400; k3++)
        {
            float t = (f0 + k3) / g_fps;
            if (t > g_tw.y) break;
            dlVLine(cvX(g_L, g_tw, t), ru.w - 3.0 * s, ru.w, IL_EDGE);
        }
    }

    // the loop's ends
    float xa = cvX(g_L, g_tw, 0.0), xb = cvX(g_L, g_tw, g_len);
    dlVLine(xa, ru.y, g.w, IL_RULE);
    dlVLine(xb, ru.y, g.w, IL_RULE);
    dlClip(float4(0.0, 0.0, _Resolution.xy));
}

// ---------------------------------------------------------------- graph: over the curves
void keyGlyph(float2 p, uint e, float3 col, bool hot)
{
    float s = g_s;
    uint m = cvInterp(e);
    float r = 4.5 * s;
    if (m == CV_BEZIER) dlDiamond(p, r + 1.0 * s, 0.0, col, 1.0);
    else if (m == CV_LINEAR) dlRect(float4(p - r * 0.8, p + r * 0.8), col, 1.0, 0.0);
    else dlBorderRect(float4(p - r * 0.8, p + r * 0.8), 0.0, col, 1.5 * s);
    if (hot) dlRing(p, r + 4.0 * s, 1.0 * s, IL_INK, 1.0);
}

void graphFront(CvRec h0, CvRec h1, CvRec h2, float2 pointer)
{
    float s = g_s;
    float4 g = g_L.graph, ru = g_L.ruler;
    dlClip(g);
    // outside the loop the curve holds; veil it
    float xa = cvX(g_L, g_tw, 0.0), xb = cvX(g_L, g_tw, g_len);
    if (xa > g.x) dlRect(float4(g.x, g.y, min(xa, g.z), g.w), IL_FIELD, 0.55, 0.0);
    if (xb < g.z) dlRect(float4(max(xb, g.x), g.y, g.z, g.w), IL_FIELD, 0.55, 0.0);

    uint mode = (uint)h1.c, target = (uint)h1.d;
    bool inGraph = ilIn(pointer, g) && mode == 0u;
    uint hotKey = inGraph ? cvHitKey(g_L, g_tw, g_vw, g_packed, pointer, 8.0 * s) : 0xFFFFu;
    uint hotHandle = inGraph ? cvHitHandle(g_L, g_tw, g_vw, g_packed, pointer, 8.0 * s) : 0xFFFFu;

    // handles of the selected keys, under the keys
    [loop] for (uint c = 0u; c < CV_CH; c++)
    {
        if (cvHidden(g_packed, c)) continue;
        uint n = cvCount(g_packed, c);
        [loop] for (uint i = 0u; i < n; i++)
        {
            CvRec k = cvKey(c, i);
            if (!cvSel(k.e)) continue;
            float2 p = toS(k.a);
            [loop] for (uint side = 0u; side < 2u; side++)
            {
                bool shown = side == 0u ? cvShowsIn(c, n, i) : cvShowsOut(c, n, i);
                if (!shown) continue;
                float2 q = toS(side == 0u ? cvTipIn(c, i) : cvTipOut(c, i));
                uint id = (c * CV_KMAX + i) * 2u + side;
                bool dragged = mode == DM_HANDLE && target == id;
                dlLine(p, q, 1.0 * s, IL_MID, 1.0);
                dlCircle(q, 3.5 * s, dragged ? IL_ACCENT : IL_INK, 1.0);
                if (hotHandle == id) dlRing(q, 7.0 * s, 1.0 * s, IL_INK, 1.0);
            }
        }
    }
    // keys: diamond = bezier, square = linear, open square = step; selected in amber
    [loop] for (uint c2 = 0u; c2 < CV_CH; c2++)
    {
        if (cvHidden(g_packed, c2)) continue;
        uint n = cvCount(g_packed, c2);
        [loop] for (uint i = 0u; i < n; i++)
        {
            CvRec k = cvKey(c2, i);
            keyGlyph(toS(k.a), k.e, cvSel(k.e) ? IL_ACCENT : chCol(c2), hotKey == c2 * CV_KMAX + i && hotHandle == 0xFFFFu);
        }
    }

    // the playhead: a live reading on every shown curve
    float px = cvX(g_L, g_tw, h0.c);
    float4 live = C[1];
    if (px >= g.x && px <= g.z)
    {
        dlLine(float2(px, g.y), float2(px, g.w), 1.25 * s, IL_ACCENT, 0.9);
        [loop] for (uint c3 = 0u; c3 < CV_CH; c3++)
            if (!cvHidden(g_packed, c3)) dlCircle(float2(px, cvY(g_L, g_vw, live[c3])), 3.0 * s, IL_ACCENT, 1.0);
    }
    // box select in progress
    if (mode == DM_BOX)
    {
        float4 box = float4(min(h1.a, h2.b), max(h1.a, h2.b));
        dlRectEdged(box, IL_INK, 0.06, 0.0, IL_INK, 1.0 * s);
    }
    dlClip(float4(0.0, 0.0, _Resolution.xy));

    // the playhead's flag on the ruler: its frame
    if (px >= ru.x && px <= ru.z)
    {
        float fw = numW(2u, IL_T_CAP * s) + 10.0 * s;
        float4 fr = float4(px - 0.5 * fw, ru.y + 2.0 * s, px + 0.5 * fw, ru.w - 2.0 * s);
        fr.xz += clamp(0.0, ru.x - fr.x, ru.z - fr.z);
        dlRect(fr, IL_ACCENT, 1.0, 2.0 * s);
        dlInt((int)floor(h0.c * g_fps + 1e-4), 2, ilMid(fr).x, ilMid(fr).y, IL_T_CAP * s, IL_FIELD, IL_CENTER);
    }
}

// ---------------------------------------------------------------- the spacing chart
float3 valuesAt(float t)
{
    return float3(cvValue(0u, cvCount(g_packed, 0u), t), cvValue(1u, cvCount(g_packed, 1u), t), cvValue(2u, cvCount(g_packed, 2u), t));
}

// the sample pass's 256 samples across the loop, read back instead of solving each ghost again
float3 sampledAt(float t)
{
    float u = saturate(t / g_len) * (float)(CV_SAMPLES - 1u);
    uint i = min((uint)u, CV_SAMPLES - 2u);
    return lerp(C[2u + i].xyz, C[3u + i].xyz, u - (float)i);
}

void chart(float play)
{
    float s = g_s;
    float4 c = g_L.chart, st = g_L.stage;
    dlRect(c, IL_WELL, 1.0, IL_RADIUS * s);
    dlLabel(LB_SPACING, c.x + 12.0 * s, c.y + 16.0 * s, IL_T_TITLE * s, IL_INK, IL_LEFT);
    dlLabel(LB_ON_TWOS, c.x + 12.0 * s, c.y + 34.0 * s, IL_T_CAP * s, IL_DIM, IL_LEFT);
    float fx = c.x + 12.0 * s;
    fx += dlNum(g_fps, 0, fx, c.y + 50.0 * s, IL_T_CAP * s, IL_DIM, IL_LEFT) + 4.0 * s;
    dlLabel(LB_FPS, fx, c.y + 50.0 * s, IL_T_CAP * s, IL_DIM, IL_LEFT);

    float ground = st.w - 4.0 * s;
    dlHLine(ground, st.x, st.z, IL_RULE);
    // ghosts on twos over the path through them (each filled with the well, so the path shows only
    // between ghosts); every half second a step brighter
    uint ng = cvGhosts(g_len, g_fps);
    float4 gb[49];
    [loop] for (uint k = 0u; k < ng; k++)
    {
        float3 v = sampledAt(min(cvGhostT(k, g_fps), g_len));
        float2 r;
        float2 p = cvBall(g_L, s, v.x, v.y, v.z, r);
        gb[k] = float4(p, r);
        if (k > 0u) dlLine(gb[k - 1u].xy, p, 1.0 * s, IL_EDGE, 1.0);
    }
    [loop] for (uint k2 = 0u; k2 < ng; k2++)
    {
        dlEllipse(gb[k2].xy, gb[k2].zw, 0.0, IL_WELL, 1.0, 0.0, 0.0);
        dlEllipse(gb[k2].xy, gb[k2].zw, 1.0 * s, (k2 % 6u == 0u) ? IL_MID : IL_DIM, 1.0, 0.0, 0.0);
    }
    // the selected keys' moments, attached to where the ball is then
    [loop] for (uint ch = 0u; ch < CV_CH; ch++)
    {
        uint n = cvCount(g_packed, ch);
        [loop] for (uint i = 0u; i < n; i++)
        {
            CvRec key = cvKey(ch, i);
            if (!cvSel(key.e) || cvHidden(g_packed, ch)) continue;
            float3 v = valuesAt(clamp(key.a.x, 0.0, g_len));
            float2 r;
            float2 p = cvBall(g_L, s, v.x, v.y, v.z, r);
            dlEllipse(p, r + 4.0 * s, 1.25 * s, IL_ACCENT, 1.0, 0.0, 0.0);
        }
    }
    // the ball now: the playhead's own values
    float3 v = C[1].xyz;
    float2 r;
    float2 p = cvBall(g_L, s, v.x, v.y, v.z, r);
    dlEllipse(p, r, 0.0, IL_INK, 1.0, 0.0, 0.0);
    dlEllipse(p, r + 2.0 * s, 1.25 * s, IL_ACCENT, 1.0, 0.0, 0.0);
}

// ---------------------------------------------------------------- hint bar: the verbs that apply now
void hints(bool selected)
{
    float s = g_s;
    uint k0 = selected ? LB_K_B0 : LB_K_A0;
    uint d0 = selected ? LB_D_B0 : LB_D_A0;
    float kh = 18.0 * s;
    float bx = g_L.hint.x, by = ilMid(g_L.hint).y;
    float total = 0.0;
    [loop] for (uint a = 0u; a < 6u; a++)
        total += ilLabelW(k0 + a, IL_T_CAP * s) + 12.0 * s + 6.0 * s + ilLabelW(d0 + a, IL_T_CAP * s) + 16.0 * s;
    plate(float4(bx, by - 15.0 * s, bx + total + 8.0 * s, by + 15.0 * s));
    bx += 10.0 * s;
    [loop] for (uint b = 0u; b < 6u; b++)
    {
        float kw = ilLabelW(k0 + b, IL_T_CAP * s) + 12.0 * s;
        float dw = ilLabelW(d0 + b, IL_T_CAP * s);
        dlKeycap(float4(bx, by - kh * 0.5, bx + kw, by + kh * 0.5), s, k0 + b);
        dlLabel(d0 + b, bx + kw + 6.0 * s, by, IL_T_CAP * s, IL_DIM, IL_LEFT);
        bx += kw + 6.0 * s + dw + 16.0 * s;
    }
}

// ---------------------------------------------------------------- thread 0
void layout(uint pieces)
{
    float2 res = _Resolution.xy;
    float s = g_s;
    dlBegin(res);
    CvRec h0 = S[CV_V0], h1 = S[CV_V1], h2 = S[CV_V2];
    float2 pointer = h1.b;

    uint nsel = 0u, selKey = 0u;
    [loop] for (uint c = 0u; c < CV_CH; c++)
    {
        uint n = cvCount(g_packed, c);
        [loop] for (uint i = 0u; i < n; i++)
            if (cvSel(cvKey(c, i).e)) { nsel++; selKey = c * CV_KMAX + i; }
    }

    header(h0, h1, nsel, selKey);
    plate(g_L.block);
    channels(pointer);
    graphBack();
    dlClip(g_L.graph);
    dlBatch(pieces, 0u);
    dlClip(float4(0.0, 0.0, res));
    graphFront(h0, h1, h2, pointer);

    // the splitter: a short grip mark, brighter while it is under the pointer
    bool hotGrip = ilIn(pointer, g_L.grip) || (uint)h1.c == 6u;
    float gx = ilMid(g_L.inner).x;
    dlRect(float4(gx - 18.0 * s, g_L.splitAt - 1.0 * s, gx + 18.0 * s, g_L.splitAt + 1.0 * s), hotGrip ? IL_INK : IL_RULE, 1.0, 1.0 * s);

    chart(h0.c);
    hints(nsel > 0u);
    dlFinish();
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    float2 res = _Resolution.xy;
    g_s = ilCtx(res).s;
    CvRec h0 = S[CV_V0], h1 = S[CV_V1];
    g_tw = h0.a;
    g_vw = h0.b;
    g_packed = S[CV_P0].e;
    g_len = clamp(length_s, 0.5, 8.0);
    g_fps = clamp((float)fps, 6.0, 60.0);
    g_L = cvLayout(res, g_s, clamp(h0.d, 0.15, 0.92));

    // 1. each channel's pieces
    if (gi < CV_CH)
    {
        uint n = cvHidden(g_packed, gi) ? 0u : cvCount(g_packed, gi);
        uint acc = 0u;
        gsOff[gi][0] = 0u;
        [loop] for (uint e = 0u; e <= n && n > 0u; e++)
        {
            acc += piecesFor(gi, n, e);
            gsOff[gi][e + 1u] = acc;
        }
        gsN[gi] = n;
        gsTot[gi] = acc;
    }
    GroupMemoryBarrierWithGroupSync();
    uint base1 = gsTot[0], base2 = gsTot[0] + gsTot[1];
    uint total = min(base2 + gsTot[2], CV_PIECES);

    // 2. everything else
    if (gi == 0u) layout(total);
    dlSync();

    // 3. the curves
    ILBatch b = dlGetBatch(0u);
    [loop] for (uint g = gi; g < total; g += IL_LAYOUT_THREADS)
    {
        uint c = g < base1 ? 0u : (g < base2 ? 1u : 2u);
        uint local = g - (c == 0u ? 0u : (c == 1u ? base1 : base2));
        uint n = gsN[c];
        uint e = 0u;
        [loop] while (e < n && gsOff[c][e + 1u] <= local) e++;
        dlAt(b, g);
        piece(c, n, e, local - gsOff[c][e], gsOff[c][e + 1u] - gsOff[c][e]);
    }
    dlEnd(gi);
}
