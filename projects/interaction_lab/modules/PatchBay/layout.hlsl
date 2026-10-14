// Patch Bay / layout - the sources, the outputs, the cables hung between them, the matrix (the same
// patch as a table) and the selected cable's inspector.
//
// Grey carries everything but the selection: amber marks the selected cable and whatever is held (a
// plug in the air, a knob, a base). A cable's brightness IS its live push, |depth x (2 source - 1)|,
// so a patch reads as signal moving through it; a cable with a negative depth inverts its source
// and is drawn dashed. Hover comes from the pointer here and is never stored.
//
// 64 threads. Thread 0 records the chrome and reserves two batches: the traces (each source's scope
// worked out from its phase and rate - the input's from its ring - the outputs' traces from theirs,
// and the selected cable's push) and the cables (casing, core and both plugs, newest on top, so a
// crossing reads over-and-under). Then every thread fills both.
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"
#include "bay.hlsli"

#define SC_SEGS   48u                                  // a source scope: 48 segments and its live dot
#define SC_SLOTS  49u
#define TR_SEGS   95u                                  // a ring trace: 96 samples and its live dot
#define TR_SLOTS  96u
#define CB_SEGS   24u                                  // a cable: 24 casing, 24 core, two plugs
#define CB_SLOTS  50u
#define TRACE_ITEMS (PB_SRC * SC_SLOTS + PB_OUT * TR_SLOTS + TR_SLOTS)
#define CABLE_ITEMS ((PB_CABLES + 1u) * CB_SLOTS)      // the last one is the cable in the air
#define WINDOW    1.92                                 // what every trace spans (96 x 1/50 s)
#define CASING    (IL_FIELD * 0.14 + IL_PANEL * 0.86)  // the block plate the cables hang over

groupshared uint gsHot;                                // the cable under the pointer, or 0xFFFF

static PbLayout g_L;
static float g_s;
static float2 g_res;
static float2 g_ptr;
static uint g_mode, g_target;
static int g_sel;
static bool g_muted;

void plate(float4 r) { dlRect(r, IL_PANEL, 0.86, IL_RADIUS * g_s); }
float rateOf(uint i) { return i == 0u ? rate_1 : (i == 1u ? rate_2 : (i == 2u ? rate_3 : (i == 3u ? rate_4 : rate_5))); }
float plotX(float4 r, float u) { return lerp(r.x + 3.0 * g_s, r.z - 3.0 * g_s, u); }
float plotY(float4 r, float v) { return lerp(r.w - 3.0 * g_s, r.y + 3.0 * g_s, saturate(v)); }
float4 pushFrame() { float s = g_s; float4 ip = g_L.inspect; return float4(ip.x + 290.0 * s, ip.y + 30.0 * s, ip.z, ip.w - 34.0 * s); }
float pushY(float4 r, float c) { return lerp(r.w - 4.0 * g_s, r.y + 4.0 * g_s, saturate(0.5 + c)); }
float pushOf(uint k, float src) { return g_muted ? 0.0 : pbDepth(k) * (2.0 * src - 1.0) * 0.5; }

// source i as it was tau seconds ago: an oscillator from its phase and rate, the input from its ring
float srcAgo(uint i, float tau)
{
    float a = clamp(tau / PB_HIST_DT, 0.0, (float)(PB_HIST_N - 1u));
    uint a0 = (uint)a;
    float ring = lerp(pbHist(0u, a0), pbHist(0u, a0 + 1u), a - (float)a0);
    return i < 5u ? pbWave(i, pbPhase(i) - rateOf(i) * tau) : ring;
}

// a jack: a socket ring round a dark hole; while a cable is in the air the jacks it can reach light
void jack(float2 c, bool hot, bool target)
{
    float s = g_s;
    dlCircle(c, 10.0 * s, IL_PANEL, 1.0);
    dlCircle(c, 6.5 * s, IL_FIELD, 1.0);
    dlRing(c, 8.5 * s, (hot ? 2.0 : 1.25) * s, hot ? IL_INK : (target ? IL_MID : IL_RULE), 1.0);
}

// the depth knob: bipolar, zero at twelve o'clock, +-1 at +-135 degrees
void knob(float2 c, float r, float v, bool live, bool held, bool hot)
{
    float s = g_s;
    float sweep = 0.75 * IL_PI;
    dlArc(c, r, 3.0 * s, -sweep, sweep, hot ? IL_RULE : IL_EDGE * 1.3, 1.0);
    dlRect(float4(c.x - 0.75 * s, c.y - r - 7.0 * s, c.x + 0.75 * s, c.y - r - 3.0 * s), IL_DIM, 1.0, 0.0);
    float a = clamp(v, -1.0, 1.0) * sweep;
    if (live && abs(v) > 0.002) dlArc(c, r, 3.0 * s, min(0.0, a), max(0.0, a), held ? IL_ACCENT : IL_INK, 1.0);
    dlCircle(c, r - 7.0 * s, IL_RAISE * 1.6, 1.0);
    if (live)
    {
        float2 dir = float2(sin(a), -cos(a));
        dlLine(c + dir * (r * 0.2), c + dir * (r - 11.0 * s), 2.0 * s, held ? IL_ACCENT : IL_INK, 1.0);
    }
}

// ---------------------------------------------------------------- the header
void header(uint n)
{
    float s = g_s;
    float4 hd = g_L.head;
    float hy = ilMid(hd).y;
    float tw = ilLabelW(LB_TITLE, 15.0 * s), sw = ilLabelW(LB_SUBTITLE, 12.0 * s);
    float4 hp = float4(hd.x, hd.y, hd.x + tw + sw + 40.0 * s, hd.w);
    plate(hp);
    dlLabel(LB_TITLE, hp.x + 12.0 * s, hy, 15.0 * s, IL_INK, IL_LEFT);
    dlLabel(LB_SUBTITLE, hp.x + 12.0 * s + tw + 14.0 * s, hy, 12.0 * s, IL_DIM, IL_LEFT);

    float cap = IL_T_CAP * s, val = IL_T_VALUE * s;
    float ww = ilNumW(4u, val) + ilLabelW(LB_SLASH, val) + 6.0 * s + ilLabelW(LB_CABLES, cap) + 24.0 * s;
    float4 cp = float4(hd.z - ww, hd.y, hd.z, hd.w);
    plate(cp);
    float x = cp.x + 12.0 * s;
    x += dlInt((int)n, 1, x, hy, val, IL_INK, IL_LEFT);
    x += dlLabel(LB_SLASH, x, hy, val, IL_DIM, IL_LEFT);
    x += dlInt((int)PB_CABLES, 1, x, hy, val, IL_DIM, IL_LEFT) + 6.0 * s;
    dlLabel(LB_CABLES, x, hy, cap, IL_DIM, IL_LEFT);
    if (g_muted)
    {
        float mw = ilLabelW(LB_MUTED, IL_T_BODY * s) + 26.0 * s;
        dlChip(float4(cp.x - 8.0 * s - mw, hd.y + 3.0 * s, cp.x - 8.0 * s, hd.w - 3.0 * s), s, LB_MUTED, true, false, false);
    }
}

// ---------------------------------------------------------------- the sources
void sources()
{
    float s = g_s;
    float cap = IL_T_CAP * s, val = IL_T_VALUE * s, body = IL_T_BODY * s;
    dlLabel(LB_SOURCES, g_L.srcCol.x + 2.0 * s, g_L.rows.y - 14.0 * s, IL_T_TITLE * s, IL_DIM, IL_LEFT);
    bool toSrc = g_mode == DM_FROM_DST;
    uint hot = (g_mode == DM_NONE || toSrc) ? pbHitSrcJack(g_L, g_ptr, s) : 0xFFFFu;
    int selSrc = g_sel >= 0 ? (int)pbCSrc((uint)g_sel) : -1;
    [loop] for (uint i = 0u; i < PB_SRC; i++)
    {
        float4 r = pbSrcRow(g_L, i);
        float y = ilMid(r).y;
        dlRect(r, IL_WELL, 1.0, IL_RADIUS * s);
        if ((int)i == selSrc) dlRect(float4(r.x, r.y + 4.0 * s, r.x + 2.0 * s, r.w - 4.0 * s), IL_ACCENT, 1.0, 0.0);
        dlLabel(LB_SRC_0 + i, r.x + 12.0 * s, y - 8.0 * s, body, IL_INK, IL_LEFT);
        dlLabel(LB_KIND_0 + i, r.x + 12.0 * s, y + 9.0 * s, cap, IL_DIM, IL_LEFT);
        float4 sc = pbScope(g_L, i, s);
        dlRect(sc, IL_FIELD, 1.0, 2.0 * s);
        dlHLine(ilMid(sc).y, sc.x, sc.z, IL_GRID);
        float xr = r.z - 34.0 * s;
        dlNum(pbSrcNow(i), 2, xr, y - 8.0 * s, val, IL_INK, IL_RIGHT);
        if (i < 5u)
        {
            float hw = dlLabel(LB_HZ, xr, y + 9.0 * s, cap, IL_DIM, IL_RIGHT);
            dlNum(rateOf(i), 2, xr - hw - 3.0 * s, y + 9.0 * s, cap, IL_DIM, IL_RIGHT);
        }
        jack(pbSrcJack(g_L, i, s), hot == i, toSrc);
    }
}

// ---------------------------------------------------------------- the outputs
void outputs()
{
    float s = g_s;
    float cap = IL_T_CAP * s, val = IL_T_VALUE * s, body = IL_T_BODY * s;
    float tx = g_L.dstCol.x + 2.0 * s, ty = g_L.rows.y - 14.0 * s;
    tx += dlLabel(LB_OUTPUTS, tx, ty, IL_T_TITLE * s, IL_DIM, IL_LEFT) + 10.0 * s;
    dlLabelFit(LB_TO, tx, ty, cap, IL_DIM, IL_LEFT, g_L.dstCol.z - tx);
    bool toDst = g_mode == DM_FROM_SRC || g_mode == DM_REPLUG;
    uint hotJack = (g_mode == DM_NONE || toDst) ? pbHitDstJack(g_L, g_ptr, s) : 0xFFFFu;
    uint hotMeter = (g_mode == DM_NONE && hotJack == 0xFFFFu) ? pbHitMeter(g_L, g_ptr, s) : 0xFFFFu;
    int selDst = g_sel >= 0 ? (int)pbCDst((uint)g_sel) : -1;
    [loop] for (uint d = 0u; d < PB_OUT; d++)
    {
        float4 r = pbDstRow(g_L, d);
        float y = ilMid(r).y, yt = y - 8.0 * s;
        dlRect(r, IL_WELL, 1.0, IL_RADIUS * s);
        if ((int)d == selDst) dlRect(float4(r.x, r.y + 4.0 * s, r.x + 2.0 * s, r.w - 4.0 * s), IL_ACCENT, 1.0, 0.0);
        float base = pbBase(d), reach;
        pbModulate(d, base, reach);
        if (g_muted) reach = 0.0;
        float live = pbOutNow(d);
        float4 m = pbMeter(g_L, d, s);
        float x = m.x;
        x += dlLabel(LB_OUT, x, yt, body, IL_INK, IL_LEFT) + 4.0 * s;
        x += dlInt((int)d + 1, 1, x, yt, body, IL_INK, IL_LEFT) + 8.0 * s;
        dlLabel(LB_DST_0 + d, x, yt, cap, IL_DIM, IL_LEFT);
        dlNum(live, 2, m.z, yt, val, IL_INK, IL_RIGHT);

        // the meter: the swing the cables can reach, the push from the base to the live value, the
        // needle, and the base underneath
        bool dragBase = g_mode == DM_BASE && g_target == d;
        dlRectEdged(m, IL_FIELD, 1.0, 2.0 * s, (hotMeter == d || dragBase) ? IL_RULE : IL_EDGE, 1.0);
        float xa = lerp(m.x, m.z, saturate(base - reach)), xb = lerp(m.x, m.z, saturate(base + reach));
        if (xb > xa + 0.5) dlRect(float4(xa, m.y + 1.0, xb, m.w - 1.0), IL_EDGE * 1.3, 1.0, 0.0);
        float xBase = lerp(m.x, m.z, base), xLive = lerp(m.x, m.z, live);
        if (abs(xLive - xBase) > 0.5) dlRect(float4(min(xBase, xLive), m.y + 2.5 * s, max(xBase, xLive), m.w - 2.5 * s), IL_MID, 1.0, 0.0);
        dlRect(float4(xLive - 1.0 * s, m.y - 3.0 * s, xLive + 1.0 * s, m.w + 3.0 * s), IL_INK, 1.0, 0.0);
        dlTri(float2(xBase, m.w + 1.5 * s), 4.0 * s, 5.0 * s, 1u, dragBase ? IL_ACCENT : (hotMeter == d ? IL_INK : IL_DIM), 1.0);

        // the trace's ground: the swing band and the base behind the last 1.92 s (the line is batched)
        float4 tr = pbTrace(g_L, d, s);
        dlRect(tr, IL_FIELD, 1.0, 2.0 * s);
        float ya = plotY(tr, base + reach), yb = plotY(tr, base - reach);
        if (yb > ya + 0.5) dlRect(float4(tr.x, ya, tr.z, yb), IL_GRID, 1.0, 0.0);
        float yBase = plotY(tr, base);
        dlDashed(float2(tr.x, yBase), float2(tr.z, yBase), 1.0 * s, IL_RULE, 1.0, 3.0 * s, 3.0 * s);
        jack(pbDstJack(g_L, d, s), hotJack == d, toDst);
    }
}

// ---------------------------------------------------------------- the matrix
void matrixView()
{
    float s = g_s;
    float cap = IL_T_CAP * s;
    float4 mx = g_L.grid;
    float ty = mx.y - 40.0 * s;
    float x = g_L.srcCol.x + 2.0 * s;
    x += dlLabel(LB_MATRIX, x, ty, IL_T_TITLE * s, IL_DIM, IL_LEFT) + 10.0 * s;
    dlLabelFit(LB_MATRIX_D, x, ty, cap, IL_DIM, IL_LEFT, g_L.inspect.x - x - 12.0 * s);
    int selSrc = -1, selDst = -1;
    if (g_sel >= 0) { selSrc = (int)pbCSrc((uint)g_sel); selDst = (int)pbCDst((uint)g_sel); }
    uint hot = (g_mode == DM_NONE) ? pbHitCell(g_L, g_ptr) : 0xFFFFu;
    [loop] for (uint c = 0u; c < PB_OUT; c++)
        dlLabel(LB_DST_0 + c, ilMid(pbCell(g_L, 0u, c)).x, mx.y - 12.0 * s, cap, (int)c == selDst ? IL_INK : IL_DIM, IL_CENTER);
    [loop] for (uint i = 0u; i < PB_SRC; i++)
    {
        dlLabel(LB_SRC_0 + i, mx.x - 8.0 * s, ilMid(pbCell(g_L, i, 0u)).y, cap, (int)i == selSrc ? IL_INK : IL_DIM, IL_RIGHT);
        [loop] for (uint d = 0u; d < PB_OUT; d++)
        {
            float4 cl = ilInset(pbCell(g_L, i, d), 1.0 * s);
            dlRect(cl, hot == i * PB_OUT + d ? IL_RAISE : IL_WELL, 1.0, 2.0 * s);
            uint k = pbFind(i, d);
            if (k == 0xFFFFu) continue;
            // patched: the depth, and under it a bipolar bar from a zero tick, right (+) or left (-)
            float2 cm = ilMid(cl);
            float dep = pbDepth(k), by = cl.w - 8.0 * s;
            float x1 = cm.x + dep * ((cl.z - cl.x) * 0.5 - 6.0 * s);
            dlNumSigned(dep, 2, cm.x, cl.y + 10.0 * s, cap, (int)k == g_sel ? IL_INK : IL_MID, IL_CENTER);
            dlRect(float4(cl.x + 6.0 * s, by - 0.5, cl.z - 6.0 * s, by + 0.5), IL_EDGE, 1.0, 0.0);
            dlVLine(cm.x, by - 4.0 * s, by + 4.0 * s, IL_RULE);
            if (abs(x1 - cm.x) > 0.5) dlRect(float4(min(cm.x, x1), by - 2.5 * s, max(cm.x, x1), by + 2.5 * s), g_muted ? IL_RULE : IL_MID, 1.0, 0.0);
            if ((int)k == g_sel) dlBorderRect(cl, 2.0 * s, IL_ACCENT, 1.5 * s);
        }
    }
}

// ---------------------------------------------------------------- the inspector
void inspector()
{
    float s = g_s;
    float cap = IL_T_CAP * s, val = IL_T_VALUE * s, body = IL_T_BODY * s;
    float4 ip = g_L.inspect;
    float ty = ip.y + 12.0 * s;
    float x = ip.x + 2.0 * s;
    x += dlLabel(LB_CABLE, x, ty, IL_T_TITLE * s, IL_DIM, IL_LEFT) + 12.0 * s;
    float2 kc = pbKnob(g_L, s);
    float kr = PB_KNOB_R * s;
    float rx = ip.x + 130.0 * s;
    if (g_sel < 0)
    {
        knob(kc, kr, 0.0, false, false, false);
        dlLabel(LB_PICK, rx, kc.y - 10.0 * s, body, IL_MID, IL_LEFT);
        dlLabelFit(LB_DEPTH_D, rx, kc.y + 10.0 * s, cap, IL_DIM, IL_LEFT, ip.z - rx);
        return;
    }
    uint k = (uint)g_sel, src = pbCSrc(k), dst = pbCDst(k);
    float dep = pbDepth(k);
    x += dlLabel(LB_SRC_0 + src, x, ty, body, IL_INK, IL_LEFT) + 6.0 * s;
    x += dlLabel(LB_ARROW, x, ty, body, IL_DIM, IL_LEFT) + 6.0 * s;
    x += dlLabel(LB_OUT, x, ty, body, IL_INK, IL_LEFT) + 4.0 * s;
    x += dlInt((int)dst + 1, 1, x, ty, body, IL_INK, IL_LEFT) + 8.0 * s;
    dlLabel(LB_DST_0 + dst, x, ty, cap, IL_DIM, IL_LEFT);

    bool held = g_mode == DM_DEPTH || g_mode == DM_CELL;
    knob(kc, kr, dep, true, held, g_mode == DM_NONE && length(g_ptr - kc) < kr);
    dlNumSigned(dep, 2, kc.x, kc.y + kr + 16.0 * s, 15.0 * s, held ? IL_ACCENT : IL_INK, IL_CENTER);

    // depth, the swing it can give, and what it pushes right now
    float push = pushOf(k, pbSrcNow(src));
    float vx = ip.x + 268.0 * s;
    float y0 = kc.y - 30.0 * s, y1 = kc.y - 6.0 * s, y2 = kc.y + 18.0 * s;
    dlLabel(LB_DEPTH, rx, y0, body, IL_DIM, IL_LEFT);
    dlNumSigned(dep, 2, vx, y0, val, IL_INK, IL_RIGHT);
    dlLabel(LB_SWING, rx, y1, body, IL_DIM, IL_LEFT);
    float nw = dlNum(abs(dep) * 0.5, 2, vx, y1, val, IL_INK, IL_RIGHT);
    dlLabel(LB_PLUSMINUS, vx - nw - 2.0 * s, y1, val, IL_DIM, IL_RIGHT);
    dlLabel(LB_NOW, rx, y2, body, IL_DIM, IL_LEFT);
    dlNumSigned(push, 2, vx, y2, val, IL_INK, IL_RIGHT);
    if (dep < 0.0) dlLabel(LB_INVERTED, rx, y2 + 24.0 * s, cap, IL_DIM, IL_LEFT);

    // the sum the output is: base + this cable + the others, clamped
    float base = pbBase(dst), others = 0.0;
    uint n = pbCables();
    [loop] for (uint j = 0u; j < n; j++)
        if (j != k && pbCDst(j) == dst) others += pushOf(j, pbSrcNow(pbCSrc(j)));
    float sum = base + push + others;
    float yb = ip.w - 12.0 * s;
    float sx = rx;
    sx += dlLabel(LB_BASE, sx, yb, cap, IL_DIM, IL_LEFT) + 4.0 * s;
    sx += dlNum(base, 2, sx, yb, val, IL_INK, IL_LEFT) + 8.0 * s;
    sx += dlLabel(LB_PLUS, sx, yb, val, IL_DIM, IL_LEFT) + 8.0 * s;
    sx += dlLabel(LB_THIS, sx, yb, cap, IL_DIM, IL_LEFT) + 4.0 * s;
    sx += dlNumSigned(push, 2, sx, yb, val, IL_INK, IL_LEFT) + 8.0 * s;
    sx += dlLabel(LB_PLUS, sx, yb, val, IL_DIM, IL_LEFT) + 8.0 * s;
    sx += dlLabel(LB_OTHERS, sx, yb, cap, IL_DIM, IL_LEFT) + 4.0 * s;
    sx += dlNumSigned(others, 2, sx, yb, val, IL_INK, IL_LEFT) + 8.0 * s;
    sx += dlLabel(LB_EQ, sx, yb, val, IL_DIM, IL_LEFT) + 8.0 * s;
    sx += dlNum(pbOutNow(dst), 2, sx, yb, val, IL_INK, IL_LEFT) + 12.0 * s;
    if (sum < 0.0 || sum > 1.0) dlLabel(LB_CLAMPED, sx, yb, cap, IL_DIM, IL_LEFT);

    // the push over the last 1.92 s, between the bounds of its swing (the line is batched)
    float4 fr = pushFrame();
    dlRect(fr, IL_FIELD, 1.0, 2.0 * s);
    dlHLine(pushY(fr, 0.0), fr.x, fr.z, IL_EDGE);
    float bnd = abs(dep) * 0.5;
    if (bnd > 0.004)
    {
        dlDashed(float2(fr.x, pushY(fr, bnd)), float2(fr.z, pushY(fr, bnd)), 1.0 * s, IL_RULE, 1.0, 3.0 * s, 3.0 * s);
        dlDashed(float2(fr.x, pushY(fr, -bnd)), float2(fr.z, pushY(fr, -bnd)), 1.0 * s, IL_RULE, 1.0, 3.0 * s, 3.0 * s);
    }
    dlLabel(LB_PUSH_T, fr.x + 8.0 * s, fr.y + 10.0 * s, cap, IL_DIM, IL_LEFT);
}

// ---------------------------------------------------------------- over the cables
// the selected cable's own knob, at its middle: drag it up and down for depth
void midKnob()
{
    if (g_sel < 0 || g_mode == DM_REPLUG) return;
    float s = g_s;
    float2 c = pbCableMid(g_L, (uint)g_sel, s);
    float dep = pbDepth((uint)g_sel);
    bool held = g_mode == DM_DEPTH || g_mode == DM_CELL;
    bool hot = g_mode == DM_NONE && length(g_ptr - c) < 11.0 * s;
    float sweep = 0.75 * IL_PI;
    float a = clamp(dep, -1.0, 1.0) * sweep;
    dlCircle(c, 12.0 * s, CASING, 1.0);
    dlCircle(c, 8.0 * s, IL_RAISE * 1.6, 1.0);
    dlArc(c, 9.0 * s, 2.0 * s, -sweep, sweep, hot ? IL_MID : IL_RULE, 1.0);
    if (abs(dep) > 0.002) dlArc(c, 9.0 * s, 2.0 * s, min(0.0, a), max(0.0, a), IL_ACCENT, 1.0);
    dlLine(c, c + float2(sin(a), -cos(a)) * 6.0 * s, 1.5 * s, held ? IL_ACCENT : IL_INK, 1.0);
}

// a plug held over nothing is unplugged when it is let go: say so at the pointer
void dropHint()
{
    if (g_mode != DM_REPLUG || pbHitDstJack(g_L, g_ptr, g_s) != 0xFFFFu) return;
    float s = g_s;
    float w = ilLabelW(LB_UNPLUG, IL_T_CAP * s) + 16.0 * s;
    float4 hp = float4(g_ptr.x + 14.0 * s, g_ptr.y - 28.0 * s, g_ptr.x + 14.0 * s + w, g_ptr.y - 10.0 * s);
    dlRectEdged(hp, IL_RAISE, 1.0, IL_RADIUS * s, IL_RULE, 1.0);
    dlLabel(LB_UNPLUG, hp.x + 8.0 * s, ilMid(hp).y, IL_T_CAP * s, IL_INK, IL_LEFT);
}

// ---------------------------------------------------------------- hint bar
void hints()
{
    float s = g_s;
    float kh = 18.0 * s;
    float bx = g_L.hint.x, by = ilMid(g_L.hint).y;
    float total = 0.0;
    [loop] for (uint a = 0u; a < 7u; a++)
        total += ilLabelW(LB_K_A0 + a, IL_T_CAP * s) + 12.0 * s + 6.0 * s + ilLabelW(LB_D_A0 + a, IL_T_CAP * s) + 16.0 * s;
    plate(float4(bx, by - 15.0 * s, bx + total + 8.0 * s, by + 15.0 * s));
    bx += 10.0 * s;
    [loop] for (uint b = 0u; b < 7u; b++)
    {
        float kw = ilLabelW(LB_K_A0 + b, IL_T_CAP * s) + 12.0 * s;
        float dw = ilLabelW(LB_D_A0 + b, IL_T_CAP * s);
        dlKeycap(float4(bx, by - kh * 0.5, bx + kw, by + kh * 0.5), s, LB_K_A0 + b);
        dlLabel(LB_D_A0 + b, bx + kw + 6.0 * s, by, IL_T_CAP * s, IL_DIM, IL_LEFT);
        bx += kw + 6.0 * s + dw + 16.0 * s;
    }
}

// ---------------------------------------------------------------- the batches
void traceItem(uint g)
{
    float s = g_s;
    if (g < PB_SRC * SC_SLOTS)
    {
        uint i = g / SC_SLOTS, j = g % SC_SLOTS;
        float4 sc = pbScope(g_L, i, s);
        if (j == SC_SEGS) { dlCircle(float2(plotX(sc, 1.0), plotY(sc, pbSrcNow(i))), 2.5 * s, IL_INK, 1.0); return; }
        float u0 = (float)j / SC_SEGS, u1 = (float)(j + 1u) / SC_SEGS;
        dlLine(float2(plotX(sc, u0), plotY(sc, srcAgo(i, (1.0 - u0) * WINDOW))),
               float2(plotX(sc, u1), plotY(sc, srcAgo(i, (1.0 - u1) * WINDOW))), 1.25 * s, IL_MID, 1.0);
        return;
    }
    g -= PB_SRC * SC_SLOTS;
    if (g < PB_OUT * TR_SLOTS)
    {
        uint d = g / TR_SLOTS, j = g % TR_SLOTS;
        float4 tr = pbTrace(g_L, d, s);
        if (j == TR_SEGS) { dlCircle(float2(plotX(tr, 1.0), plotY(tr, pbHist(d + 1u, 0u))), 2.5 * s, IL_INK, 1.0); return; }
        float u0 = (float)j / TR_SEGS, u1 = (float)(j + 1u) / TR_SEGS;
        dlLine(float2(plotX(tr, u0), plotY(tr, pbHist(d + 1u, TR_SEGS - j))),
               float2(plotX(tr, u1), plotY(tr, pbHist(d + 1u, TR_SEGS - 1u - j))), 1.25 * s, IL_MID, 1.0);
        return;
    }
    g -= PB_OUT * TR_SLOTS;
    if (g_sel < 0) return;
    uint k = (uint)g_sel, src = pbCSrc(k);
    float4 fr = pushFrame();
    if (g == TR_SEGS) { dlCircle(float2(plotX(fr, 1.0), pushY(fr, pushOf(k, pbSrcNow(src)))), 3.0 * s, IL_INK, 1.0); return; }
    float u0 = (float)g / TR_SEGS, u1 = (float)(g + 1u) / TR_SEGS;
    dlLine(float2(plotX(fr, u0), pushY(fr, pushOf(k, srcAgo(src, (1.0 - u0) * WINDOW)))),
           float2(plotX(fr, u1), pushY(fr, pushOf(k, srcAgo(src, (1.0 - u1) * WINDOW)))), 1.5 * s, IL_INK, 1.0);
}

// the cable in the air: from its fixed jack to the pointer, snapping to a jack it can plug into
bool looseEnds(out float2 a, out float2 b)
{
    float s = g_s;
    bool fromSrc = g_mode == DM_FROM_SRC || g_mode == DM_REPLUG;
    uint hd = pbHitDstJack(g_L, g_ptr, s), hs = pbHitSrcJack(g_L, g_ptr, s);
    a = g_ptr;
    b = g_ptr;
    if (fromSrc)
    {
        a = pbSrcJack(g_L, g_mode == DM_FROM_SRC ? g_target : pbCSrc(g_target), s);
        if (hd != 0xFFFFu) b = pbDstJack(g_L, hd, s);
    }
    else if (g_mode == DM_FROM_DST)
    {
        b = pbDstJack(g_L, g_target, s);
        if (hs != 0xFFFFu) a = pbSrcJack(g_L, hs, s);
    }
    return fromSrc || g_mode == DM_FROM_DST;
}

void cableItem(uint g)
{
    float s = g_s;
    uint k = g / CB_SLOTS, j = g % CB_SLOTS;
    float2 a = 0.0, b = 0.0;
    float3 core = IL_ACCENT;
    float w = 2.5 * s;
    bool dashed = false;
    if (k < PB_CABLES)
    {
        if (k >= pbCables() || (g_mode == DM_REPLUG && k == g_target)) return;   // a held plug is drawn in the air
        float4 c = pbCable(k);
        a = pbSrcJack(g_L, (uint)c.x, s);
        b = pbDstJack(g_L, (uint)c.y, s);
        dashed = c.z < 0.0;
        w = 2.0 * s;
        if ((int)k != g_sel)
        {
            // brightness is the live push: a quiet source or a shallow cable stays dim (square root:
            // the eye needs the small pushes spread out more than the big ones)
            float push = g_muted ? 0.0 : abs(c.z * (2.0 * pbSrcNow((uint)c.x) - 1.0));
            core = (k == gsHot) ? IL_INK : lerp(IL_RULE * 1.35, IL_INK, saturate(sqrt(push / 0.6)));
        }
        if (k == gsHot) w = 2.75 * s;
    }
    else if (!looseEnds(a, b)) return;

    if (j < 2u * CB_SEGS)
    {
        uint q = j % CB_SEGS;
        float2 p0 = pbCableAt(a, b, (float)q / CB_SEGS, s), p1 = pbCableAt(a, b, (float)(q + 1u) / CB_SEGS, s);
        if (j < CB_SEGS) dlLine(p0, p1, w + 4.0 * s, CASING, 1.0);
        else if (dashed)
        {
            // a whole number of dashes a segment, so the pattern runs on unbroken across the joints
            float len = length(p1 - p0);
            float per = len / max(round(len / (9.0 * s)), 1.0);
            dlDashed(p0, p1, w, core, 1.0, 0.6 * per, 0.4 * per);
        }
        else dlLine(p0, p1, w, core, 1.0);
    }
    else dlCircle(j == 2u * CB_SEGS ? a : b, 5.0 * s, core, 1.0);       // the plugs
}

// ---------------------------------------------------------------- thread 0
void layout()
{
    dlBegin(g_res);
    header(pbCables());
    plate(g_L.block);
    sources();
    outputs();
    matrixView();
    inspector();
    dlBatch(TRACE_ITEMS, 0u);          // batch 0: the traces
    gsHot = (g_mode == DM_NONE && pbHitSrcJack(g_L, g_ptr, g_s) == 0xFFFFu && pbHitDstJack(g_L, g_ptr, g_s) == 0xFFFFu
             && pbHitCell(g_L, g_ptr) == 0xFFFFu && pbHitMeter(g_L, g_ptr, g_s) == 0xFFFFu) ? pbHitCable(g_L, g_ptr, g_s) : 0xFFFFu;
    dlBatch(CABLE_ITEMS, 0u);          // batch 1: the cables, over everything but what follows
    midKnob();
    dropHint();
    hints();
    dlFinish();
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    g_res = _Resolution.xy;
    g_s = ilCtx(g_res).s;
    g_L = pbLayout(g_res, g_s);
    float4 v1 = S[PB_V1];
    g_mode = (uint)v1.x;
    g_target = (uint)v1.y;
    g_sel = (int)v1.z;
    if (g_sel >= (int)pbCables()) g_sel = -1;
    if (g_mode == DM_REPLUG && g_target >= pbCables()) g_mode = DM_NONE;
    g_muted = pbMuted();
    // while something is held, the reducer's last drag position (what it will act on at release);
    // otherwise the pointer, for hover
    g_ptr = (g_mode != DM_NONE) ? S[PB_V2].zw : _ViewportPointerPosition * g_res;

    if (gi == 0u) layout();
    dlSync();

    ILBatch bt = dlGetBatch(0u);
    [loop] for (uint g = gi; g < bt.count; g += IL_LAYOUT_THREADS) { dlAt(bt, g); traceItem(g); }
    ILBatch bc = dlGetBatch(1u);
    [loop] for (uint h = gi; h < bc.count; h += IL_LAYOUT_THREADS) { dlAt(bc, h); cableItem(h); }
    dlEnd(gi);
}
