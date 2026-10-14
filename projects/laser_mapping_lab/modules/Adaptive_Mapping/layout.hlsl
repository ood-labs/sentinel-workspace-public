// Adaptive_Mapping / layout - the Mapped Path canvas's words, readouts, the records-out trace, the
// hover inspector and the verb, recorded for the shared UI kit (ui.hlsl draws them over preview).
//
// Every figure is the compiler's own: the stats record (stats.hlsl), the Mapped Scan itself, and
// the history ring (history.hlsl). The inspected record is the lit one nearest the pointer within
// reach, found by all 64 threads at once; hover is a read of the pointer snapshot and is never
// stored. The rects come from am_view.hlsli, the mapping draw.hlsl lands the path with.
//
// Threads: (1) all 64 search the records for the one under the pointer; (2) thread 0 records the
// chrome and reserves batch 0 for the trace's segments; (3) all 64 fill the batch.
#include "../_shared/scan.hlsli"
StructuredBuffer<Scan> A : register(t0);           // the Mapped Scan (out0)
StructuredBuffer<float4> St : register(t1);        // Compiler Stats
StructuredBuffer<float4> Hi : register(t2);        // the records-out ring
#include "am_view.hlsli"
#include "am_hist.hlsli"
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"

groupshared uint gsNear;                  // the nearest lit record: (distance in 1/16 px << 10) | index
groupshared float4 gsPlot;                // the trace's plot rect
groupshared float4 gsTrace;               // (newest slot, scale top, samples held, -)

static AMLayout g_L;
static float g_s;
static float2 g_res;

uint recCount() { return min((uint)max(A[0].endpoints.x, 0.0), 1023u); }

// ---------------------------------------------------------------- header: title, mode, status
void header(uint status, uint mode)
{
    float s = g_s;
    float hy = 0.5 * g_L.head.w;
    float cap = IL_T_TITLE * s;
    float x = 14.0 * s;
    x += dlLabel(LB_TITLE, x, hy, 14.0 * s, IL_INK, IL_LEFT) + 10.0 * s;
    float subEnd = x + ilLabelW(LB_SUBTITLE, 12.0 * s);
    // the status as a chip at the right; red edge and word only when the compile is broken
    uint stl = LB_ST_0 + min(status, 3u);
    bool bad = status >= 2u;
    float cw = ilLabelW(stl, cap) + 20.0 * s;
    float4 chip = float4(g_L.head.z - 14.0 * s - cw, hy - 11.0 * s, g_L.head.z - 14.0 * s, hy + 11.0 * s);
    dlRectEdged(chip, IL_RAISE, 1.0, IL_RADIUS * s, bad ? IL_ALARM : IL_EDGE, 1.0);
    dlLabel(stl, ilMid(chip).x, hy, cap, bad ? IL_ALARM : IL_INK, IL_CENTER);
    // the mapping mode left of it, then the subtitle, each only where it fits
    uint ml = mode == 1u ? LB_MODE_1 : LB_MODE_0;
    float mw = ilLabelW(ml, IL_T_BODY * s) + 6.0 * s + ilLabelW(LB_MODE, cap);
    float rx = chip.x - 18.0 * s;
    bool modeFits = rx - mw > x + 16.0 * s;
    if (modeFits)
    {
        rx -= dlLabel(ml, rx, hy, IL_T_BODY * s, IL_INK, IL_RIGHT) + 6.0 * s;
        rx -= dlLabel(LB_MODE, rx, hy, cap, IL_DIM, IL_RIGHT);
    }
    if ((modeFits ? rx - 16.0 * s : chip.x - 16.0 * s) > subEnd) dlLabel(LB_SUBTITLE, x, hy, 12.0 * s, IL_DIM, IL_LEFT);
}

// ---------------------------------------------------------------- the field's frame and caption
void field(uint status, uint n)
{
    float s = g_s;
    float4 f = g_L.field;
    dlBorderRect(f, IL_RADIUS * s, status >= 2u ? IL_ALARM : IL_EDGE, 1.0);
    float cy = f.y + 14.0 * s;
    float w = dlLabel(LB_FIELD, f.x + 10.0 * s, cy, IL_T_TITLE * s, IL_DIM, IL_LEFT);
    dlLabelFit(LB_FIELD_D, f.x + 18.0 * s + w, cy, IL_T_CAP * s, IL_DIM, IL_LEFT, f.z - f.x - 28.0 * s - w);
    if (n == 0u && status < 3u) dlLabel(LB_NO_PATHS, ilMid(f).x, ilMid(f).y, IL_T_BODY * s, IL_DIM, IL_CENTER);
}

// ---------------------------------------------------------------- the readout panes
// Ten rows over three panes, one loop so the number formatter compiles once. Captions R_IN ..
// R_DWELL run in this order in labels.txt.
void panes(float4 s0, float4 s1, float4 s2)
{
    float s = g_s;
    [loop] for (uint k = 0u; k < 3u; k++)
    {
        float4 p = amPane(g_L, k);
        if (p.w > p.y) dlPane(p, s, LB_P_RECORDS + k, false);
    }
    [loop] for (uint r = 0u; r < 10u; r++)
    {
        uint k = r < 3u ? 0u : (r < 6u ? 1u : 2u);
        uint j = r - (k == 0u ? 0u : (k == 1u ? 3u : 6u));
        float4 p = amPane(g_L, k);
        if (p.w <= p.y) continue;
        float v = s0.x;
        int dec = 0;
        uint unit = LB_U_REC;
        float3 col = IL_INK;
        if (r == 1u) v = s0.y;
        else if (r == 2u) { v = s1.w; col = IL_MID; }
        else if (r == 3u) { v = s1.x; dec = 5; unit = LB_U_FIELD; }
        else if (r == 4u) { v = s1.y; dec = 5; unit = LB_U_FIELD; }
        else if (r == 5u) { v = s1.z; unit = 0xFFFFu; }
        else if (r == 6u) { v = s2.y * 1000.0; dec = 2; unit = LB_U_MS; }
        else if (r == 7u) { v = s2.x; dec = 3; unit = LB_U_FIELD; }
        else if (r == 8u) { v = s2.z * 1000.0; dec = 2; unit = LB_U_MS; }
        else if (r == 9u) { v = s2.w * 1000.0; dec = 2; unit = LB_U_MS; }
        float y = amRowY(g_L, p, j);
        float x1 = p.z - 10.0 * s;
        float uw = 0.0;                     // (an if, not ?: - HLSL evaluates both sides of ?:)
        if (unit != 0xFFFFu) uw = dlLabel(unit, x1, y, IL_T_CAP * s, IL_DIM, IL_RIGHT) + 4.0 * s;
        float nw = dlNum(v, dec, x1 - uw, y, IL_T_VALUE * s, col, IL_RIGHT);
        dlLabelFit(LB_R_IN + r, p.x + 10.0 * s, y, IL_T_BODY * s, IL_DIM, IL_LEFT, p.z - p.x - 26.0 * s - uw - nw);
    }
}

// ---------------------------------------------------------------- the records-out trace
// The pane, its scale and the budget line here; the segments are batch 0, filled by every thread.
// Batch 0 is ALWAYS reserved (with 0 segments when there is nothing to plot): main() reads it.
void trace(float budget)
{
    float s = g_s;
    gsPlot = float4(0.0, 0.0, 0.0, 0.0);
    gsTrace = float4(0.0, 64.0, 0.0, 0.0);
    float4 p = amPane(g_L, 3u);
    float4 h = Hi[0];
    bool ours = h.w == AM_HIST_MAGIC;
    uint held = ours ? (uint)clamp(h.z, 0.0, (float)AM_HIST_N) : 0u;
    uint head = ours ? (uint)h.x % AM_HIST_N : 0u;
    float4 pl = float4(0.0, 0.0, 0.0, 0.0);
    if (p.w > p.y)
    {
        float4 body = dlPane(p, s, LB_P_TRACE, false);
        float4 hd = ilPaneHead(p, s);
        float tw = ilLabelW(LB_P_TRACE, IL_T_TITLE * s);
        dlLabelFit(LB_TRACE_D, hd.x + 18.0 * s + tw, ilMid(hd).y, IL_T_CAP * s, IL_DIM, IL_LEFT, hd.z - hd.x - 28.0 * s - tw);
        pl = float4(body.x + 38.0 * s, body.y + 10.0 * s, body.z - 12.0 * s, body.w - 10.0 * s);
    }
    bool plot = pl.w - pl.y >= 24.0 * s && pl.z - pl.x >= 60.0 * s;
    if (plot)
    {
        // the scale: the larger of the budget and the tallest sample, with headroom, in steps of 64
        float top = max(64.0, budget);
        [loop] for (uint a = 0u; a < held; a++)
        {
            float4 v = Hi[1u + (head + AM_HIST_N - a) % AM_HIST_N];
            top = max(top, max(v.x, v.y));
        }
        top = ceil(top * 1.1 / 64.0) * 64.0;
        dlRect(pl, IL_WELL, 1.0, 2.0 * s);
        // Each number sits ON the level it names: zero on the floor of the plot, the budget on its
        // dashed line. Labels nudged inside the plot read a trace of 46 records as zero and the
        // budget line as the top of the scale.
        float yb = lerp(pl.w, pl.y, saturate(budget / top));
        if (pl.w - yb > 10.0 * s) dlInt(0, 1, pl.x - 6.0 * s, pl.w, IL_T_CAP * s, IL_DIM, IL_RIGHT);
        dlInt((int)round(budget), 1, pl.x - 6.0 * s, yb, IL_T_CAP * s, IL_DIM, IL_RIGHT);
        dlDashed(float2(pl.x, yb), float2(pl.z, yb), 1.0, IL_RULE, 1.0, 4.0 * s, 3.0 * s);
        gsPlot = pl;
        gsTrace = float4((float)head, top, (float)held, 0.0);
    }
    dlClip(plot ? pl : float4(0.0, 0.0, 0.0, 0.0));
    dlBatch(plot && held >= 2u ? held - 1u : 0u, 0u);          // batch 0: the segments, newest first
    dlClipReset();
    if (plot && held >= 1u)
    {
        // the newest sample is the live reading
        float4 v = Hi[1u + head];
        dlCircle(float2(pl.z, lerp(pl.w, pl.y, saturate(v.x / gsTrace.y))), 3.0 * s, IL_ACCENT, 1.0);
    }
}

// segment a of the trace: from sample a (age a) back to sample a + 1, red where the compile broke
void traceSeg(uint a)
{
    float s = g_s;
    float4 pl = gsPlot;
    float4 t = gsTrace;
    uint head = (uint)t.x;
    float dx = (pl.z - pl.x) / (float)(AM_HIST_N - 1u);
    float4 v0 = Hi[1u + (head + AM_HIST_N - a) % AM_HIST_N];
    float4 v1 = Hi[1u + (head + 2u * AM_HIST_N - a - 1u) % AM_HIST_N];
    float2 p0 = float2(pl.z - (float)a * dx, lerp(pl.w, pl.y, saturate(v0.x / t.y)));
    float2 p1 = float2(pl.z - (float)(a + 1u) * dx, lerp(pl.w, pl.y, saturate(v1.x / t.y)));
    dlLine(p1, p0, 1.25 * s, (v0.z >= 2.0 || v1.z >= 2.0) ? IL_ALARM : IL_MID, 1.0);
}

// ---------------------------------------------------------------- the inspector
// The record lifts to ink with its start dotted and its end ringed; the card gives its identity,
// ends (field units, +y up), length, time in the cycle and the joint flag at its start.
void inspect(uint idx, uint n, float2 at)
{
    float s = g_s;
    float2 R = g_res;
    Scan r = A[idx];
    float2 a = amFieldPx(g_L, r.endpoints.xy), b = amFieldPx(g_L, r.endpoints.zw);
    dlClip(g_L.field);
    dlLine(a, b, 2.5 * s, IL_INK, 1.0);
    dlCircle(a, 3.0 * s, IL_INK, 1.0);
    dlRing(b, 3.5 * s, 1.25 * s, IL_INK, 1.0);
    dlClipReset();
    if (tooltips == 0) return;                   // Tooltips off: the record still lifts, no card

    uint rows = 6u;
    float w = 236.0 * s, hgt = (36.0 + 18.0 * (float)rows) * s;
    float x0 = at.x + 18.0 * s;
    if (x0 + w > R.x - 8.0 * s) x0 = at.x - 18.0 * s - w;
    float y0 = at.y + 18.0 * s;
    if (y0 + hgt > R.y - 8.0 * s) y0 = at.y - 18.0 * s - hgt;
    x0 = max(x0, 8.0 * s);
    y0 = max(y0, 8.0 * s);
    dlRectEdged(float4(x0, y0, x0 + w, y0 + hgt), IL_RAISE, 1.0, IL_RADIUS * s, IL_EDGE, 1.0);
    float ty = y0 + 15.0 * s, tx = x0 + 10.0 * s;
    tx += dlLabel(LB_I_RECORD, tx, ty, IL_T_TITLE * s, IL_INK, IL_LEFT) + 5.0 * s;
    tx += dlInt((int)idx, 1, tx, ty, IL_T_VALUE * s, IL_INK, IL_LEFT) + 5.0 * s;
    tx += dlLabel(LB_OF, tx, ty, IL_T_CAP * s, IL_DIM, IL_LEFT) + 5.0 * s;
    dlInt((int)n, 1, tx, ty, IL_T_VALUE * s, IL_MID, IL_LEFT);
    // its colour at the start and at the end (its own colours, pulled toward the instrument)
    float rx = x0 + w - 10.0 * s;
    dlRect(float4(rx - 10.0 * s, ty - 6.0 * s, rx, ty + 6.0 * s), ptSampleColour(r.color1.rgb), 1.0, 2.0 * s);
    dlRect(float4(rx - 22.0 * s, ty - 6.0 * s, rx - 12.0 * s, ty + 6.0 * s), ptSampleColour(r.color0.rgb), 1.0, 2.0 * s);
    dlHLine(y0 + 29.0 * s, x0 + 1.0, x0 + w - 1.0, IL_EDGE);

    float cx = x0 + 10.0 * s, vx = x0 + w - 10.0 * s;
    float y = y0 + 29.0 * s + 15.0 * s;
    uint joint = (uint)clamp(round(r.timing.z), 0.0, 2.0);
    [loop] for (uint k = 0u; k < rows; k++)
    {
        uint capL = LB_I_FROM, unit = LB_U_FIELD;
        uint nums = 2u;
        float v0 = r.endpoints.x, v1 = r.endpoints.y;
        int dec = 3;
        if (k == 1u) { capL = LB_I_TO; v0 = r.endpoints.z; v1 = r.endpoints.w; }
        else if (k == 2u) { capL = LB_I_LENGTH; nums = 1u; v0 = length(r.endpoints.zw - r.endpoints.xy); }
        else if (k == 3u) { capL = LB_I_START; nums = 1u; v0 = r.timing.x * 1000.0; dec = 2; unit = LB_U_MS; }
        else if (k == 4u) { capL = LB_I_LASTS; nums = 1u; v0 = r.timing.y * 1000.0; unit = LB_U_MS; }
        else if (k == 5u) { capL = LB_I_JOINT; nums = 0u; }
        dlLabel(capL, cx, y, IL_T_CAP * s, IL_DIM, IL_LEFT);
        if (nums == 0u)
            dlLabel(LB_J_0 + joint, vx, y, IL_T_BODY * s, IL_INK, IL_RIGHT);
        else
        {
            float xr = vx - dlLabel(unit, vx, y, IL_T_CAP * s, IL_DIM, IL_RIGHT) - 4.0 * s;
            xr -= dlNum(nums == 2u ? v1 : v0, dec, xr, y, IL_T_VALUE * s, IL_INK, IL_RIGHT);
            if (nums == 2u)
            {
                xr -= 4.0 * s;
                xr -= dlLabel(LB_U_COMMA, xr, y, IL_T_CAP * s, IL_DIM, IL_RIGHT) + 4.0 * s;
                dlNum(v0, dec, xr, y, IL_T_VALUE * s, IL_INK, IL_RIGHT);
            }
        }
        y += 18.0 * s;
    }
}

// ---------------------------------------------------------------- the verb
void footer()
{
    float s = g_s;
    float fy = ilMid(g_L.foot).y;
    float x = 14.0 * s;
    float kw = ilLabelW(LB_K_HOVER, IL_T_CAP * s) + 12.0 * s, kh = 18.0 * s;
    dlKeycap(float4(x, fy - 0.5 * kh, x + kw, fy + 0.5 * kh), s, LB_K_HOVER);
    dlLabel(LB_D_HOVER, x + kw + 6.0 * s, fy, IL_T_CAP * s, IL_DIM, IL_LEFT);
}

// ---------------------------------------------------------------- thread 0
void layout(uint near, float2 ptr)
{
    dlBegin(g_res);
    float4 s0 = St[0], s1 = St[1], s2 = St[2], s3 = St[3];
    uint status = (uint)clamp(s0.z, 0.0, 3.0);
    uint n = recCount();
    header(status, (uint)clamp(s3.y, 0.0, 1.0));
    field(status, n);
    panes(s0, s1, s2);
    trace(s1.w);
    if (near != 0xFFFFFFFFu) inspect(near & 1023u, n, ptr);
    footer();
    dlFinish();
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    g_res = _Resolution.xy;
    g_L = amLayout(g_res);
    g_s = g_L.s;

    // 1. every thread: the lit record nearest the pointer, while the pointer is over the field
    if (gi == 0u) gsNear = 0xFFFFFFFFu;
    GroupMemoryBarrierWithGroupSync();
    float2 pn = _ViewportPointerPosition;
    float2 ptr = pn * g_res;
    bool over = all(pn >= 0.0) && all(pn <= 1.0) && ilIn(ptr, g_L.field);
    uint n = recCount();
    float reach = 10.0 * g_s;
    if (over)
    {
        [loop] for (uint i = 1u + gi; i <= n; i += IL_LAYOUT_THREADS)
        {
            Scan r = A[i];
            if (r.timing.w > 0.5) continue;
            float d = ilSdSeg(ptr, amFieldPx(g_L, r.endpoints.xy), amFieldPx(g_L, r.endpoints.zw));
            if (d < reach) InterlockedMin(gsNear, (min((uint)(d * 16.0), 0x3FFFFFu) << 10) | i);
        }
    }
    GroupMemoryBarrierWithGroupSync();

    // 2. thread 0: the chrome, and the trace's batch
    if (gi == 0u) layout(gsNear, ptr);
    dlSync();

    // 3. every thread: the trace's segments
    ILBatch b = dlGetBatch(0u);
    [loop] for (uint k = gi; k < b.count; k += IL_LAYOUT_THREADS) { dlAt(b, k); traceSeg(k); }
    dlEnd(gi);
}
