// Scope / layout - four probe lanes and the gate strip, the cursors, the time axis.
//
// Three steps in one group of 64 threads:
//   1. every thread scans a slice of the ring for each lane's visible range (a lane grows past
//      0..1 only when its probe does);
//   2. thread 0 records the chrome, the cursors and the readouts;
//   3. every thread draws two trace columns in parallel: per lane, a connector from the last
//      sample before the column, then the column's first sample to its last - routed through
//      the most extreme sample between them when that one goes further, at its own time, so a
//      peak is never lost when the window holds more samples than columns - plus the gate.
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"
#include "scope.hlsli"

StructuredBuffer<ScRec> R : register(t0);

groupshared uint gsLo[SC_LANES];
groupshared uint gsHi[SC_LANES];
static float g_lo[SC_LANES];
static float g_hi[SC_LANES];
static uint g_written = 0u;
static uint g_M = 0u;

uint ordF(float f) { uint u = asuint(f); return (u & 0x80000000u) != 0u ? ~u : (u | 0x80000000u); }
float unordF(uint u) { return asfloat((u & 0x80000000u) != 0u ? (u & 0x7FFFFFFFu) : ~u); }

// the ring as a time-ordered array: j = 0 (oldest) .. g_M - 1 (newest)
ScRec at(uint j) { return R[SC_RING0 + (g_written - g_M + j) % SC_N]; }
uint lowerBound(float t)
{
    uint lo = 0u, hi = g_M;
    [loop] while (lo < hi)
    {
        uint mid = (lo + hi) >> 1;
        if (at(mid).a.x < t) lo = mid + 1u; else hi = mid;
    }
    return lo;
}
float4 valueAt(float t)
{
    uint j = lowerBound(t);
    if (j >= g_M) return scProbes(at(g_M - 1u));
    if (j > 0u && abs(at(j - 1u).a.x - t) < abs(at(j).a.x - t)) j--;
    return scProbes(at(j));
}

float laneY(ScLayout L, uint l, float v, float s)
{
    float4 r = L.lane[l];
    float k = saturate((v - g_lo[l]) / max(g_hi[l] - g_lo[l], 1e-6));
    return lerp(r.w - 8.0 * s, r.y + 8.0 * s, k);
}

void plate(float4 r, float s) { dlRect(r, IL_PANEL, 0.86, IL_RADIUS * s); }

// a value tag beside a cursor, flipped left near the right edge
void valueTag(ScLayout L, float s, float x, float y, float v, float3 col)
{
    float w = ilNumW(5u, IL_T_CAP * s) + 10.0 * s;
    bool left = x + 10.0 * s + w > L.plot.z;
    float x0 = left ? x - 10.0 * s - w : x + 10.0 * s;
    float4 r = float4(x0, y - 8.0 * s, x0 + w, y + 8.0 * s);
    dlRect(r, IL_FIELD, 0.92, 2.0 * s);
    dlNum(v, 2, ilMid(r).x, y, IL_T_CAP * s, col, IL_CENTER);
}

void cursor(ScLayout L, float s, float t, float now, float window, float3 col)
{
    float x = scX(L, t, now, window);
    dlLine(float2(x, L.plot.y - 4.0 * s), float2(x, L.plot.w + 2.0 * s), 1.25 * s, col, 1.0);
    float4 v = valueAt(t);
    [loop] for (uint l = 0u; l < SC_LANES; l++)
    {
        float y = laneY(L, l, v[l], s);
        dlCircle(float2(x, y), 3.5 * s, col, 1.0);
        valueTag(L, s, x, y, v[l], col);
    }
    // its moment, on the axis
    float w = ilNumW(5u, IL_T_CAP * s) + ilLabelW(LB_UNIT_S, IL_T_CAP * s) + 16.0 * s;
    float4 r = float4(x - 0.5 * w, L.axis.y, x + 0.5 * w, L.axis.w);
    r.xz += clamp(0.0, L.plot.x - r.x, L.plot.z - r.z);
    dlRect(r, IL_FIELD, 1.0, 2.0 * s);
    float y = ilMid(r).y;
    float uw = ilLabelW(LB_UNIT_S, IL_T_CAP * s);
    dlLabel(LB_UNIT_S, r.z - 6.0 * s, y, IL_T_CAP * s, col, IL_RIGHT);
    dlNum(t - now, 2, r.z - 9.0 * s - uw, y, IL_T_CAP * s, col, IL_RIGHT);
}

void layout(ScLayout L, float s, ScRec h, float now, float window)
{
    float2 res = _Resolution.xy;
    dlBegin(res);
    bool hold = ((uint)h.d & SC_HOLD) != 0u;

    // header: title, then the window and the hold state on the right
    float tw = ilLabelW(LB_TITLE, 15.0 * s), sw = ilLabelW(LB_SUBTITLE, 12.0 * s);
    float4 hp = float4(L.head.x, L.head.y, L.head.x + tw + sw + 40.0 * s, L.head.w);
    plate(hp, s);
    float hy = ilMid(hp).y;
    dlLabel(LB_TITLE, hp.x + 12.0 * s, hy, 15.0 * s, IL_INK, IL_LEFT);
    dlLabel(LB_SUBTITLE, hp.x + 12.0 * s + tw + 14.0 * s, hy, 12.0 * s, IL_DIM, IL_LEFT);
    float ww = ilLabelW(LB_WIN, IL_T_CAP * s), nw = ilNumW(4u, IL_T_VALUE * s), uw = ilLabelW(LB_UNIT_S, IL_T_CAP * s);
    float4 wp = float4(L.head.z - (ww + nw + uw + 40.0 * s), L.head.y, L.head.z, L.head.w);
    plate(wp, s);
    float x = wp.z - 12.0 * s;
    x -= dlLabel(LB_UNIT_S, x, hy, IL_T_CAP * s, IL_DIM, IL_RIGHT) + 4.0 * s;
    x -= dlNum(window, 1, x, hy, IL_T_VALUE * s, IL_INK, IL_RIGHT) + 8.0 * s;
    dlLabel(LB_WIN, x, hy, IL_T_CAP * s, IL_DIM, IL_RIGHT);
    if (hold)
    {
        float aw = ilLabelW(LB_HOLD, IL_T_CAP * s) + 30.0 * s;
        float4 ar = float4(wp.x - 8.0 * s - aw, L.head.y, wp.x - 8.0 * s, L.head.w);
        plate(ar, s);
        dlRect(float4(ar.x + 9.0 * s, hy - 4.0 * s, ar.x + 11.5 * s, hy + 4.0 * s), IL_INK, 1.0, 0.0);
        dlRect(float4(ar.x + 13.5 * s, hy - 4.0 * s, ar.x + 16.0 * s, hy + 4.0 * s), IL_INK, 1.0, 0.0);
        dlLabel(LB_HOLD, ar.x + 22.0 * s, hy, IL_T_CAP * s, IL_INK, IL_LEFT);
    }

    // the block: lanes, gate strip, time grid and axis
    plate(L.block, s);
    float step = window <= 1.01 ? 0.25 : (window <= 2.01 ? 0.5 : (window <= 8.01 ? 1.0 : 2.0));
    int ticks = (int)floor(window / step + 1e-3);
    [loop] for (int k = 0; k <= ticks; k++)
    {
        float ago = k * step;
        float gx = lerp(L.plot.z, L.plot.x, ago / window);
        dlVLine(gx, L.plot.y, L.plot.w, IL_GRID);
        float ay = ilMid(L.axis).y;
        if (k == 0) dlLabel(LB_NOW, gx, ay, IL_T_CAP * s, IL_DIM, IL_RIGHT);
        else dlNum(-ago, step < 1.0 ? 2 : 0, gx, ay, IL_T_CAP * s, IL_DIM, IL_CENTER);
    }

    ScRec newest = at(max(g_M, 1u) - 1u);
    float4 live = scProbes(newest);
    [loop] for (uint l = 0u; l < SC_LANES; l++)
    {
        float4 r = L.lane[l];
        dlRect(r, IL_WELL, 1.0, 2.0 * s);
        dlHLine(laneY(L, l, 0.0, s), r.x, r.z, IL_EDGE);
        dlHLine(laneY(L, l, 1.0, s), r.x, r.z, IL_EDGE);
        dlHLine(laneY(L, l, 0.5, s), r.x, r.z, IL_GRID);
        float ny = r.y + 12.0 * s;
        dlLabel(LB_L_A + l, L.gutter.x, ny, IL_T_TITLE * s, IL_INK, IL_LEFT);
        dlLabel(LB_L_A_D + l, L.gutter.x, ny + 15.0 * s, IL_T_CAP * s, IL_DIM, IL_LEFT);
        if (g_M > 0u) dlNum(live[l], 2, L.gutter.z, ny + 2.0 * s, IL_T_VALUE * 1.5 * s, IL_INK, IL_RIGHT);
        // the lane's range (it widens past 0..1 only when the probe does)
        float ry = r.w - 9.0 * s;
        float rx = L.gutter.z;
        rx -= dlNum(g_hi[l], 2, rx, ry, IL_T_CAP * s, IL_DIM, IL_RIGHT) + 4.0 * s;
        rx -= dlLabel(LB_DASH, rx, ry, IL_T_CAP * s, IL_DIM, IL_RIGHT) + 4.0 * s;
        dlNum(g_lo[l], 2, rx, ry, IL_T_CAP * s, IL_DIM, IL_RIGHT);
    }
    dlRect(L.gate, IL_WELL, 1.0, 2.0 * s);
    float gy = ilMid(L.gate).y;
    dlLabel(LB_L_GATE, L.gutter.x, gy, IL_T_TITLE * s, IL_INK, IL_LEFT);
    dlLabel(LB_L_GATE_D, L.gutter.x + 44.0 * s, gy, IL_T_CAP * s, IL_DIM, IL_LEFT);
    if (g_M > 0u && newest.a.y > 0.5) dlCircle(float2(L.gutter.z - 5.0 * s, gy), 4.5 * s, IL_INK, 1.0);
    else dlRing(float2(L.gutter.z - 5.0 * s, gy), 4.5 * s, 1.25 * s, IL_DIM, 1.0);

    // batch 0: the traces, clipped to the plot
    dlClip(L.plot);
    dlBatch(SC_COLS * SC_SLOTS, 0u);
    dlClip(float4(0.0, 0.0, res));

    // the live heads: where each probe is now
    if (!hold && g_M > 0u)
        [loop] for (uint l2 = 0u; l2 < SC_LANES; l2++)
            dlCircle(float2(scX(L, newest.a.x, now, window), laneY(L, l2, live[l2], s)), 3.0 * s, IL_ACCENT, 1.0);

    // cursors: the active one is the selection (amber), the other the reference; active on top
    bool activeB = ((uint)h.d & SC_ACTIVE_B) != 0u;
    if (activeB)
    {
        if (h.b.x > 0.0) cursor(L, s, h.b.x, now, window, IL_INK);
        if (h.b.y > 0.0) cursor(L, s, h.b.y, now, window, IL_ACCENT);
    }
    else
    {
        if (h.b.y > 0.0) cursor(L, s, h.b.y, now, window, IL_INK);
        if (h.b.x > 0.0) cursor(L, s, h.b.x, now, window, IL_ACCENT);
    }
    if (h.b.x > 0.0 && h.b.y > 0.0)
    {
        // how far apart, and each lane's difference, in the gutter
        float4 va = valueAt(h.b.x), vb = valueAt(h.b.y);
        [loop] for (uint l3 = 0u; l3 < SC_LANES; l3++)
        {
            float4 r = L.lane[l3];
            float y = r.y + 46.0 * s;
            if (y > r.w - 18.0 * s) continue;
            float bx = L.gutter.z;
            dlNumSigned(vb[l3] - va[l3], 2, bx, y, IL_T_CAP * s, IL_INK, IL_RIGHT);
            dlLabel(LB_BA, bx - ilNumW(6u, IL_T_CAP * s), y, IL_T_CAP * s, IL_DIM, IL_RIGHT);
        }
        float xa = scX(L, h.b.x, now, window), xb = scX(L, h.b.y, now, window);
        float my = L.plot.y - 4.0 * s;
        dlLine(float2(min(xa, xb), my), float2(max(xa, xb), my), 1.0 * s, IL_INK, 0.8);
        float aw = ilLabelW(LB_APART, IL_T_CAP * s) + ilNumW(5u, IL_T_CAP * s) + ilLabelW(LB_UNIT_S, IL_T_CAP * s) + 26.0 * s;
        float cx = 0.5 * (xa + xb);
        float4 ar = float4(cx - 0.5 * aw, my - 18.0 * s, cx + 0.5 * aw, my - 3.0 * s);
        ar.xz += clamp(0.0, L.plot.x - ar.x, L.plot.z - ar.z);
        dlRect(ar, IL_FIELD, 1.0, 2.0 * s);
        float ay = ilMid(ar).y;
        float px = ar.x + 8.0 * s;
        px += dlNum(abs(h.b.x - h.b.y), 2, px, ay, IL_T_CAP * s, IL_INK, IL_LEFT) + 3.0 * s;
        px += dlLabel(LB_UNIT_S, px, ay, IL_T_CAP * s, IL_INK, IL_LEFT) + 6.0 * s;
        dlLabel(LB_APART, px, ay, IL_T_CAP * s, IL_DIM, IL_LEFT);
    }

    // hint bar
    float kh = 18.0 * s;
    float bx = 16.0 * s, by = res.y - 26.0 * s;
    float total = 0.0;
    [loop] for (uint k1 = 0u; k1 < 6u; k1++)
        total += ilLabelW(LB_K_DRAG + k1, IL_T_CAP * s) + 12.0 * s + 6.0 * s + ilLabelW(LB_D_DRAG + k1, IL_T_CAP * s) + 16.0 * s;
    plate(float4(bx, by - 15.0 * s, bx + total + 8.0 * s, by + 15.0 * s), s);
    bx += 10.0 * s;
    [loop] for (uint k2 = 0u; k2 < 6u; k2++)
    {
        float kw = ilLabelW(LB_K_DRAG + k2, IL_T_CAP * s) + 12.0 * s;
        float dw = ilLabelW(LB_D_DRAG + k2, IL_T_CAP * s);
        dlKeycap(float4(bx, by - kh * 0.5, bx + kw, by + kh * 0.5), s, LB_K_DRAG + k2);
        dlLabel(LB_D_DRAG + k2, bx + kw + 6.0 * s, by, IL_T_CAP * s, IL_DIM, IL_LEFT);
        bx += kw + 6.0 * s + dw + 16.0 * s;
    }
    dlFinish();
}

// one trace column: per lane a connector and first-(extreme-)last (3 slots), then the gate
void column(ScLayout L, float s, uint k, float now, float window)
{
    if (g_M == 0u) return;
    float t0 = now - window;
    float tk0 = t0 + window * (float)k / SC_COLS;
    float tk1 = (k + 1u == SC_COLS) ? now + 1e-3 : t0 + window * (float)(k + 1u) / SC_COLS;
    uint j0 = lowerBound(tk0), j1 = lowerBound(tk1);
    uint inCol = j1 - j0;
    ScRec prev = at(max(j0, 1u) - 1u);
    ScRec first = at(min(j0, g_M - 1u));
    ScRec last = at(min(max(j1, 1u) - 1u, g_M - 1u));
    float4 vp = scProbes(prev), vf = scProbes(first);
    float4 lo = vf, hi = vf;
    uint4 jlo = j0, jhi = j0;
    bool gate = inCol == 0u ? (j0 > 0u && prev.a.y > 0.5) : false;
    [loop] for (uint j = j0; j < j1 && j < j0 + 8u; j++)
    {
        ScRec r = at(j);
        float4 v = scProbes(r);
        bool4 below = v < lo, above = v > hi;
        lo = below ? v : lo;
        jlo = below ? j : jlo;
        hi = above ? v : hi;
        jhi = above ? j : jhi;
        gate = gate || r.a.y > 0.5;
    }
    float xp = scX(L, prev.a.x, now, window), xf = scX(L, first.a.x, now, window), xl = scX(L, last.a.x, now, window);
    float4 vl = scProbes(last);
    [loop] for (uint l = 0u; l < SC_LANES; l++)
    {
        float yf = laneY(L, l, vf[l], s), yl = laneY(L, l, vl[l], s);
        if (inCol > 0u && j0 > 0u)
            dlLine(float2(xp, laneY(L, l, vp[l], s)), float2(xf, yf), 1.5 * s, IL_INK, 1.0);
        // the extreme that goes furthest past first and last (y grows downward)
        float ylo = laneY(L, l, lo[l], s), yhi = laneY(L, l, hi[l], s);
        float up = min(yf, yl) - yhi, down = ylo - max(yf, yl);
        if (inCol > 2u && max(up, down) > 1.0)
        {
            ScRec re = at(up >= down ? jhi[l] : jlo[l]);
            float2 pe = float2(scX(L, re.a.x, now, window), up >= down ? yhi : ylo);
            dlLine(float2(xf, yf), pe, 1.5 * s, IL_INK, 1.0);
            dlLine(pe, float2(xl, yl), 1.5 * s, IL_INK, 1.0);
        }
        else if (inCol > 1u)
            dlLine(float2(xf, yf), float2(xl, yl), 1.5 * s, IL_INK, 1.0);
    }
    if (gate)
    {
        float x0 = lerp(L.plot.x, L.plot.z, (float)k / SC_COLS), x1 = lerp(L.plot.x, L.plot.z, (float)(k + 1u) / SC_COLS);
        dlRect(float4(x0, L.gate.y + 5.0 * s, x1 + 0.5, L.gate.w - 5.0 * s), IL_MID, 1.0, 0.0);
    }
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    float2 res = _Resolution.xy;
    float s = ilCtx(res).s;
    ScLayout L = scLayout(res, s);
    ScRec h = R[SC_HEAD];
    float now = h.a.x;
    float window = clamp(h.a.y, SC_WIN_MIN, SC_WIN_MAX);
    g_written = h.f;
    g_M = min(h.f, SC_N);

    // 1. each lane's visible range
    if (gi < SC_LANES)
    {
        gsLo[gi] = ordF(1e30);
        gsHi[gi] = ordF(-1e30);
    }
    GroupMemoryBarrierWithGroupSync();
    [loop] for (uint j = gi; j < g_M; j += IL_LAYOUT_THREADS)
    {
        ScRec r = at(j);
        if (r.a.x < now - window || r.a.x > now) continue;
        float4 v = scProbes(r);
        [unroll] for (uint l = 0u; l < SC_LANES; l++)
        {
            InterlockedMin(gsLo[l], ordF(v[l]));
            InterlockedMax(gsHi[l], ordF(v[l]));
        }
    }
    GroupMemoryBarrierWithGroupSync();
    [unroll] for (uint l = 0u; l < SC_LANES; l++)
    {
        float lo = unordF(gsLo[l]), hi = unordF(gsHi[l]);
        if (!(lo <= hi)) { lo = 0.0; hi = 1.0; }
        g_lo[l] = min(lo, 0.0);
        g_hi[l] = max(hi, 1.0);
    }

    // 2. chrome, cursors, readouts
    if (gi == 0u) layout(L, s, h, now, window);
    dlSync();

    // 3. the traces
    ILBatch b = dlGetBatch(0u);
    [loop] for (uint k = gi; k < SC_COLS; k += IL_LAYOUT_THREADS)
    {
        dlAtSpan(b, k, SC_SLOTS);
        column(L, s, k, now, window);
    }
    dlEnd(gi);
}
