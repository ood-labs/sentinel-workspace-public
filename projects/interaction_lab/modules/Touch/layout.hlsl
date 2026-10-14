// Touch / layout - records the surface, the event log and the hint bar into the draw list.
//
// Everything drawn is read back from the two reducers' buffers: the strokes from the durable ink
// ring, the log rows and counters from the observe buffer. Nothing here interprets an event.
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"
#include "../_shared/ui/il_events.hlsli"
#include "touch.hlsli"

StructuredBuffer<uint4> InkB : register(t0);
StructuredBuffer<uint4> ObB : register(t1);

float  fb(uint u) { return asfloat(u); }
uint   ptCode(uint4 p) { return (uint)asfloat(p.z); }
float2 ptUv(uint4 p) { return float2(asfloat(p.x), asfloat(p.y)); }

void drawHead(TouchLayout L, float s)
{
    float y = ilMid(L.head).y;
    float w = dlLabel(LB_TITLE, L.head.x, y, 15.0 * s, IL_INK, IL_LEFT);
    dlLabelFit(LB_SUBTITLE, L.head.x + w + 14.0 * s, y, 12.0 * s, IL_DIM, IL_LEFT, L.head.z - L.head.x - w - 20.0 * s);
    dlHLine(L.head.w, L.head.x, L.head.z, IL_EDGE);
}

void drawSurface(TouchLayout L, float s, float2 res)
{
    dlPane(L.surface, s, LB_P_SURFACE, false);
    uint4 h0 = InkB[0];
    uint4 h1 = InkB[1];
    float brush = fb(h1.x);
    if (!(brush >= 1.0 && brush <= 48.0)) brush = 6.0;
    uint inkSel = h1.y & 3u;
    bool fade = (h1.z & 1u) != 0u;
    float clock = fb(h1.w);
    uint written = h0.w;

    // header tools, right to left: fade state, brush, the four inks
    float4 head = ilPaneHead(L.surface, s);
    float y = ilMid(head).y;
    float x = head.z - 10.0 * s;
    x -= dlLabel(fade ? LB_C_FADE_ON : LB_C_FADE_OFF, x, y, IL_T_CAP * s, fade ? IL_INK : IL_DIM, IL_RIGHT) + 16.0 * s;
    x -= dlNum(brush, 0, x, y, IL_T_VALUE * s, IL_INK, IL_RIGHT) + 5.0 * s;
    x -= dlLabel(LB_C_BRUSH, x, y, IL_T_CAP * s, IL_DIM, IL_RIGHT) + 16.0 * s;
    [loop] for (int k = 3; k >= 0; k--)
    {
        float4 chip = float4(x - 13.0 * s, y - 6.5 * s, x, y + 6.5 * s);
        dlRect(chip, ptId(k), 1.0, 2.0 * s);
        if ((uint)k == inkSel) dlBorderRect(ilInset(chip, -3.0 * s), 3.5 * s, IL_ACCENT, 1.5 * s);
        x -= 21.0 * s;
    }

    dlClip(L.ink);
    // quiet construction grid, centred
    float sp = 40.0 * s;
    float2 c = ilMid(L.ink);
    float2 sz = ilSize(L.ink);
    int nx = (int)(sz.x / sp * 0.5) + 1, ny = (int)(sz.y / sp * 0.5) + 1;
    [loop] for (int gx = -nx; gx <= nx; gx++) dlVLine(c.x + gx * sp, L.ink.y, L.ink.w, gx == 0 ? IL_EDGE : IL_GRID);
    [loop] for (int gy = -ny; gy <= ny; gy++) dlHLine(c.y + gy * sp, L.ink.x, L.ink.z, gy == 0 ? IL_EDGE : IL_GRID);

    // strokes: one batch slot per live point, filled by all 64 threads (inkPoint, below)
    uint oldest = written > T_INK_N ? written - T_INK_N : 0u;
    dlBatch(written - oldest, oldest);

    // ripples: a click is a small ring, a clear is a wide one
    [loop] for (uint r = 0u; r < T_RIPPLE_N; r++)
    {
        uint4 rp = ObB[O_RIP + r];
        float age = fb(rp.z);
        float life = (rp.w == 2u) ? 1.1 : 0.8;
        if (rp.w == 0u || !(age < life)) continue;
        float t = age / life;
        float rad = ((rp.w == 2u) ? 260.0 : 48.0) * s * (1.0 - pow(1.0 - t, 3.0)) + 4.0 * s;
        dlRing(inkToPx(L, float2(fb(rp.x), fb(rp.y))), rad, 1.5 * s, IL_INK, 1.0 - t);
    }

    // brush cursor where the pointer is (a cosmetic snapshot read, never state)
    float2 ptr = _ViewportPointerPosition * res;
    if (ilIn(ptr, L.ink)) dlRing(ptr, 0.5 * brush * s + 1.0, 1.0, IL_MID, 0.9);

    if (written == 0u)
    {
        float ew = min(ilLabelW(LB_EMPTY, IL_T_BODY * s), sz.x - 40.0 * s);
        dlRect(float4(c.x - 0.5 * ew - 12.0 * s, c.y - 12.0 * s, c.x + 0.5 * ew + 12.0 * s, c.y + 12.0 * s), IL_PANEL, 1.0, IL_RADIUS * s);
        dlLabelFit(LB_EMPTY, c.x, c.y, IL_T_BODY * s, IL_DIM, IL_CENTER, sz.x - 40.0 * s);
    }
    dlClipReset();
}

// The event log's geometry - computed identically by thread 0 (which draws the frame and
// reserves the rows) and by the batch threads (which draw the rows).
#define T_ROW_CMDS 11u      // highlight, seq, type, phase, code, 3 mods, x, y, value
struct RailGeom
{
    float4 r;               // inner rect
    float  cx[7];           // column starts: seq | type | phase | code | mods | position | value
    float  ms, adv, rowH, headY, logTop, logBottom;
    bool   showValue, showRules;
    uint   logHead, rows;
};

RailGeom railGeom(TouchLayout L, float s)
{
    RailGeom G;
    float4 body = L.rail;
    body.y += ilSnap(IL_HEADER * s);
    G.r = ilInset2(body, float2(12.0 * s, 8.0 * s));
    G.ms = 11.0 * s;
    G.adv = IL_MONO_ADV * G.ms / IL_TYPE_EM;
    // in mono cells: seq 6 | type 9 | phase 9 | code 5 | mods 5 | position 12 | value 6
    G.cx[0] = G.r.x; G.cx[1] = G.cx[0] + 6.0 * G.adv; G.cx[2] = G.cx[1] + 9.0 * G.adv; G.cx[3] = G.cx[2] + 9.0 * G.adv;
    G.cx[4] = G.cx[3] + 5.0 * G.adv; G.cx[5] = G.cx[4] + 5.0 * G.adv; G.cx[6] = G.cx[5] + 12.0 * G.adv;
    G.showValue = G.cx[6] + 6.0 * G.adv <= G.r.z;
    G.headY = G.r.y + 10.0 * s;
    G.rowH = 17.0 * s;
    G.logTop = G.headY + 20.0 * s;
    float countersH = 4.0 * G.rowH + 18.0 * s;
    float rulesH = 4.0 * 15.0 * s + 30.0 * s;
    // the rules show when the log still keeps at least eight rows; the log takes whatever is left
    G.showRules = (G.r.w - G.logTop - countersH - rulesH) >= 8.0 * G.rowH;
    G.logBottom = G.r.w - countersH - (G.showRules ? rulesH : 0.0);
    uint fit = (uint)max(floor((G.logBottom - G.logTop) / G.rowH + 0.5), 0.0);
    G.logHead = ObB[O_CNT].y;
    G.rows = L.hasRail ? min(min(G.logHead, T_LOG_N), fit) : 0u;
    return G;
}

// Log row i (newest first), in its own span of the row batch.
void logRow(RailGeom G, uint i, float s)
{
    float ry = G.logTop + i * G.rowH;
    uint slot = O_LOG + 2u * ((G.logHead - 1u - i) % T_LOG_N);
    uint4 a = ObB[slot];
    uint4 b = ObB[slot + 1u];
    uint type = a.y & 0xFFu, phase = (a.y >> 8) & 0xFFu, code = a.y >> 16;
    float3 ink = (i == 0u) ? IL_INK : lerp(IL_MID, IL_DIM, saturate((float)i / max((float)G.rows, 8.0)));
    if (i == 0u) dlRect(float4(G.r.x - 6.0 * s, ry - G.rowH * 0.5, G.r.z + 6.0 * s, ry + G.rowH * 0.5), IL_RAISE, 1.0, 2.0 * s);
    dlInt((int)(a.x % 100000u), 1, G.cx[0], ry, G.ms, ink, IL_LEFT);
    dlLabel(LB_T_NONE + min(type, 6u), G.cx[1], ry, G.ms, ink, IL_LEFT);
    dlLabel(LB_PH_NONE + min(phase, 8u), G.cx[2], ry, G.ms, ink, IL_LEFT);
    dlInt((int)code, 1, G.cx[3], ry, G.ms, ink, IL_LEFT);
    float mx = G.cx[4];
    if ((a.z & VIEWPORT_MODIFIER_SHIFT) != 0u)   mx += dlLabel(LB_M_SHIFT, mx, ry, G.ms, ink, IL_LEFT);
    if ((a.z & VIEWPORT_MODIFIER_CONTROL) != 0u) mx += dlLabel(LB_M_CTRL, mx, ry, G.ms, ink, IL_LEFT);
    if ((a.z & VIEWPORT_MODIFIER_ALT) != 0u)     mx += dlLabel(LB_M_ALT, mx, ry, G.ms, ink, IL_LEFT);
    // a key has no position, and most events carry no value: say so rather than print zeros
    if (type == IL_EV_KEY) dlLabel(LB_T_NONE, G.cx[5], ry, G.ms, IL_DIM, IL_LEFT);
    else
    {
        float px = dlNum(fb(b.x), 2, G.cx[5], ry, G.ms, ink, IL_LEFT);
        dlNum(fb(b.y), 2, G.cx[5] + px + G.adv, ry, G.ms, ink, IL_LEFT);
    }
    if (G.showValue)
    {
        if (abs(fb(a.w)) > 1e-4) dlNumSigned(fb(a.w), 2, G.cx[6], ry, G.ms, ink, IL_LEFT);
        else dlLabel(LB_T_NONE, G.cx[6], ry, G.ms, IL_DIM, IL_LEFT);
    }
}

void drawRail(TouchLayout L, float s)
{
    dlPane(L.rail, s, LB_P_LOG, false);
    RailGeom G = railGeom(L, s);
    float4 r = G.r;
    float y = G.headY;
    uint hdr[7] = { LB_H_SEQ, LB_H_TYPE, LB_H_PHASE, LB_H_CODE, LB_H_MODS, LB_H_POS, LB_H_VAL };
    [loop] for (int h = 0; h < 7; h++)
        if (h < 6 || G.showValue) dlLabel(hdr[h], G.cx[h], y, IL_T_CAP * s, IL_DIM, IL_LEFT);
    dlHLine(y + 9.0 * s, r.x, r.z, IL_EDGE);

    // the rows: reserved here in painter's order, drawn by every thread (logRow, in main)
    dlBatch(G.rows * T_ROW_CMDS, 0u);

    uint4 sq = ObB[O_SEQ];
    uint4 cn = ObB[O_CNT];
    float rowH = G.rowH;
    bool showRules = G.showRules;
    float logBottom = G.logBottom;

    // counters: the rules made visible
    float cy = logBottom + 10.0 * s;
    dlHLine(cy - 2.0 * s, r.x, r.z, IL_EDGE);
    float half = (r.z - r.x - 16.0 * s) * 0.5;
    float4 c0 = float4(r.x, cy, r.x + half, cy + rowH);
    float4 c1 = float4(r.z - half, cy, r.z, cy + rowH);
    uint4 h0 = InkB[0];
    dlValueRow(c0, s, LB_C_CONSUMED, (float)sq.y, 0, false);
    dlValueRow(c1, s, LB_C_STALE, (float)sq.z, 0, false);
    c0.yw += rowH; c1.yw += rowH;
    dlValueRow(c0, s, LB_C_RESETS, (float)sq.w, 0, false);
    dlValueRow(c1, s, LB_C_MOVES, (float)cn.x, 0, false);
    c0.yw += rowH; c1.yw += rowH;
    dlValueRow(c0, s, LB_C_WHEEL, fb(cn.w), 2, false);
    dlValueRow(c1, s, LB_C_STROKES, (float)h0.z, 0, false);
    c0.yw += rowH; c1.yw += rowH;
    dlValueRow(c0, s, LB_C_POINTS, (float)min(h0.w, T_INK_N), 0, false);

    if (showRules)
    {
        float ry0 = c0.w + 22.0 * s;
        dlLabel(LB_P_RULES, r.x, ry0, IL_T_TITLE * s, IL_DIM, IL_LEFT);
        [loop] for (uint k = 0u; k < 4u; k++)
            dlLabelFit(LB_R1 + k, r.x, ry0 + 18.0 * s + k * 15.0 * s, IL_T_CAP * s, IL_MID, IL_LEFT, r.z - r.x);
    }
}

void drawHints(TouchLayout L, float s)
{
    float x = L.hint.x;
    float y = ilMid(L.hint).y;
    float kh = 18.0 * s;
    [loop] for (uint i = 0u; i < 8u; i++)
    {
        uint key = LB_K_CLICK + i, desc = LB_D_CLICK + i;
        float kw = ilLabelW(key, IL_T_CAP * s) + 12.0 * s;
        float dw = ilLabelW(desc, IL_T_CAP * s);
        if (x + kw + 6.0 * s + dw > L.hint.z) break;
        dlKeycap(float4(x, y - kh * 0.5, x + kw, y + kh * 0.5), s, key);
        dlLabel(desc, x + kw + 6.0 * s, y, IL_T_CAP * s, IL_DIM, IL_LEFT);
        x += kw + 6.0 * s + dw + 18.0 * s;
    }
}

void layout()
{
    float2 res = _Resolution.xy;
    ILCtx cx = ilCtx(res);
    float s = cx.s;
    TouchLayout L = touchLayout(res, s);
    dlBegin(res);
    drawHead(L, s);
    drawSurface(L, s, res);                // batch 0: ink points
    if (L.hasRail) drawRail(L, s);         // batch 1: log rows
    else dlBatch(0u, 0u);                  // (keep the batch ids stable)
    drawHints(L, s);
    dlFinish();
}

// Ink point i: a capsule back to the previous point of the same stroke, a dot when it is a
// stroke's only point, nothing when it starts a longer stroke (its successor draws the joint).
void inkPoint(TouchLayout L, float s, uint i, uint oldest, uint written)
{
    uint4 h1 = InkB[1];
    bool fade = (h1.z & 1u) != 0u;
    float clock = fb(h1.w);
    uint4 p = InkB[INK_SLOT(i)];
    uint code = ptCode(p);
    uint stroke = code >> 8;
    float wpx = max((float)(code & 63u), 1.0) * s;
    // fade toward the pane instead of with alpha: capsules overlap at every joint, and
    // translucent overlaps would bead there
    float fadeK = fade ? max(exp(-(clock - fb(p.w)) / 3.0), 0.10) : 1.0;
    float3 inkCol = lerp(IL_PANEL, ptId((int)((code >> 6) & 3u)), fadeK);
    uint4 prev = InkB[INK_SLOT(max(i, oldest + 1u) - 1u)];
    bool joined = (i > oldest) && ((ptCode(prev) >> 8) == stroke);
    float2 b = inkToPx(L, ptUv(p));
    if (joined) dlLine(inkToPx(L, ptUv(prev)), b, wpx, inkCol, 1.0);
    else
    {
        bool lone = (i + 1u >= written) || ((ptCode(InkB[INK_SLOT(i + 1u)]) >> 8) != stroke);
        if (lone) dlCircle(b, 0.5 * wpx, inkCol, 1.0);
    }
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    if (gi == 0u) layout();
    dlSync();
    float2 res = _Resolution.xy;
    float s = ilCtx(res).s;
    TouchLayout L = touchLayout(res, s);
    ILBatch ink = dlGetBatch(0u);
    uint written = InkB[0].w;
    [loop] for (uint i = gi; i < ink.count; i += IL_LAYOUT_THREADS)
    {
        dlAt(ink, i);
        inkPoint(L, s, ink.user + i, ink.user, written);
    }
    ILBatch rows = dlGetBatch(1u);
    RailGeom G = railGeom(L, s);
    [loop] for (uint r = gi; r < rows.count / T_ROW_CMDS; r += IL_LAYOUT_THREADS)
    {
        dlAtSpan(rows, r, T_ROW_CMDS);
        logRow(G, r, s);
    }
    dlEnd(gi);
}
