// FM_Colony / layout - the colony canvas's type and chrome, recorded for the shared UI kit (ui.hlsl
// draws it over canvas.hlsl's arena and gait chart):
//
//   - the title row, with where the population comes from (a steady trail, or a dormant pool that
//     only fills as emitters release);
//   - the arena plate's caption and its legend: the two scents are the plate's one hue, so they
//     are named, with the marks for the focus ant, planted and lifted feet, and slip;
//   - the gait plate's caption (which ant), the tripod blocks and the lane names;
//   - the readout column: what the colony is measured to be doing, with the two values that move
//     traced over the last four seconds (mean speed, which the beat drives, against its base;
//     mean slip against its alarm), the lane shares as bars, and the release pool;
//   - the inspector: the ant under the pointer, with everything its record says, or the moment of
//     the gait chart under the pointer;
//   - the footer.
//
// Every figure is a measurement read from a buffer the colony wrote, never a restatement of a
// parameter (except where a parameter is the reference a measurement is read against: the base
// speed, the slip alarm). Hover is read from the pointer snapshot and never stored.
//
// 64 threads. All of them search the population for the ant nearest the pointer (each a
// sixteenth of it); thread 0 records the chrome and reserves one batch for the two history
// traces; then every thread fills the batch.
#include "../_shared/formic.hlsli"
#include "colony.hlsli"
StructuredBuffer<FmAnt>  Ants  : register(t0);
StructuredBuffer<FmFoot> Feet  : register(t1);
StructuredBuffer<FmMeas> Meas  : register(t2);
StructuredBuffer<FmRec>  PlanB : register(t3);
StructuredBuffer<FmGait> Hist  : register(t4);
StructuredBuffer<float4> Trace : register(t5);
StructuredBuffer<FmSta>  Sta   : register(t6);
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"
#include "colony_view.hlsli"

#define TRACE_SEGS  (FC_TRACE_N - 1u)
#define TRACE_ITEMS (2u * (TRACE_SEGS + 1u))       // two traces: their segments and a live dot each

groupshared uint gsNear;                         // (distance * 16) << 16 | ant, or none

static FcView g_V;
static float  g_s;
static float2 g_R;

// ---------------------------------------------------------------- the readout column
struct ColL { float4 colony, footing, lanes, pool; float4 spd, slip; bool showPool; };

float colRowH() { return ilSnap(22.0 * g_s); }

ColL colLayout()
{
    ColL c;
    float s = g_s;
    float rh = colRowH(), hh = ilSnap(IL_HEADER * s), g = ilSnap(8.0 * s);
    float4 r = g_V.col;
    float fixedH = 4.0 * hh + 14.0 * rh + 44.0 * s + 3.0 * g;
    float th = clamp(floor((r.w - r.y - fixedH) * 0.5), 40.0 * s, 110.0 * s);
    c.colony  = ilCutTop(r, hh + 4.0 * rh + th + 14.0 * s); r.y += g;
    c.footing = ilCutTop(r, hh + 2.0 * rh + th + 14.0 * s); r.y += g;
    c.lanes   = ilCutTop(r, hh + 5.0 * rh + 8.0 * s);       r.y += g;
    c.showPool = r.w - r.y >= hh + 3.0 * rh + 8.0 * s;
    c.pool    = ilCutTop(r, hh + 3.0 * rh + 8.0 * s);
    c.spd  = float4(c.colony.x + 10.0 * s,  c.colony.y + hh + 4.0 * rh + 4.0 * s,  c.colony.z - 10.0 * s,  c.colony.w - 10.0 * s);
    c.slip = float4(c.footing.x + 10.0 * s, c.footing.y + hh + 2.0 * rh + 4.0 * s, c.footing.z - 10.0 * s, c.footing.w - 10.0 * s);
    return c;
}

// caption left, value and unit right, a row centred on y
void vrow(float4 b, float y, uint cap, float v, int dec, uint unit, float3 ink)
{
    float s = g_s;
    dlLabel(cap, b.x + 10.0 * s, y, IL_T_BODY * s, IL_DIM, IL_LEFT);
    float uw = dlLabel(unit, b.z - 10.0 * s, y, IL_T_CAP * s, IL_DIM, IL_RIGHT);
    dlNum(v, dec, b.z - 13.0 * s - uw, y, IL_T_VALUE * s, ink, IL_RIGHT);
}
void irow(float4 b, float y, uint cap, int v, float3 ink)
{
    float s = g_s;
    dlLabel(cap, b.x + 10.0 * s, y, IL_T_BODY * s, IL_DIM, IL_LEFT);
    dlInt(v, 1, b.z - 10.0 * s, y, IL_T_VALUE * s, ink, IL_RIGHT);
}

// The history ring: age 0 is the newest sample. (speed, slip, traffic, laden)
float4 traceAt(uint age)
{
    float4 h = Trace[0];
    uint i = ((uint)max(h.x, 0.0) + FC_TRACE_N - 1u - min(age, FC_TRACE_N - 1u)) % FC_TRACE_N;
    return Trace[1u + i];
}
bool  traceOk() { float4 h = Trace[0]; return h.w == FC_TRACE_MAGIC && h.y >= 2.0; }
uint  traceWritten() { return (uint)clamp(Trace[0].y, 0.0, (float)FC_TRACE_N); }
float spdMax() { return max(max(speed_base * (1.0 + speed_audio), walk_speed), 1.0) * 1.15; }
float slipMax() { return max(slip_alarm * 2.2, 1e-4); }
float plotY(float4 r, float v) { return lerp(r.w - 2.0 * g_s, r.y + 2.0 * g_s, saturate(v)); }
float plotX(float4 r, uint age) { return lerp(r.z, r.x, (float)age / (float)(FC_TRACE_N - 1u)); }

// Batch item g: trace 0 is speed, trace 1 slip; per trace TRACE_SEGS segments (oldest first) and
// the live dot at the newest sample.
void traceItem(uint g, ColL c)
{
    float s = g_s;
    uint t = g / (TRACE_SEGS + 1u), j = g % (TRACE_SEGS + 1u);
    float4 r = (t == 0u) ? c.spd : c.slip;
    float full = (t == 0u) ? spdMax() : slipMax();
    uint written = traceWritten();
    if (!traceOk()) return;
    if (j == TRACE_SEGS)
    {
        float v = (t == 0u) ? traceAt(0u).x : traceAt(0u).y;
        bool bad = t == 1u && v > slip_alarm;
        dlCircle(float2(r.z, plotY(r, v / full)), 2.5 * s, bad ? IL_ALARM : IL_ACCENT, 1.0);
        return;
    }
    uint a0 = TRACE_SEGS - j, a1 = a0 - 1u;                // older and newer end of this segment
    if (a0 >= written) return;
    float v0 = (t == 0u) ? traceAt(a0).x : traceAt(a0).y;
    float v1 = (t == 0u) ? traceAt(a1).x : traceAt(a1).y;
    bool bad = t == 1u && max(v0, v1) > slip_alarm;      // a slip over its alarm is a broken gait
    dlLine(float2(plotX(r, a0), plotY(r, v0 / full)), float2(plotX(r, a1), plotY(r, v1 / full)), 1.25 * s, bad ? IL_ALARM : IL_MID, 1.0);
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
void crow(float4 c, float y, uint cap, float v, int dec, uint unit, float3 ink)
{
    float s = g_s;
    dlLabel(cap, c.x + 10.0 * s, y, IL_T_CAP * s, IL_DIM, IL_LEFT);
    float uw = dlLabel(unit, c.z - 10.0 * s, y, IL_T_CAP * s, IL_DIM, IL_RIGHT);
    dlNum(v, dec, c.z - 13.0 * s - uw, y, IL_T_VALUE * s, ink, IL_RIGHT);
}

// ---------------------------------------------------------------- the ant under the pointer
void antCard(uint i, float2 at, FmTop T, uint focus)
{
    float s = g_s;
    FmAnt a = Ants[i];
    float2 c = fmTopToPx(T, a.pos.xz);
    dlRing(c, max(a.size * T.scale * 0.75, 7.0 * s), 1.5 * s, IL_INK, 1.0);

    // the lane, as the ordinal the readouts and the plan's flow strip count in
    int lane = -1;
    uint slot = (uint)(a.edge + 0.5);
    if (slot > 0u)
    {
        lane = 0;
        [loop] for (uint e = 0u; e + 1u < slot && e < FM_EDGES; e++) if (PlanB[FM_EDGE_0 + e].active > 0.5) lane++;
    }
    float worst = 0.0;
    [loop] for (uint lg = 0u; lg < FM_LEGS; lg++) worst = max(worst, Feet[i * FM_LEGS + lg].slip);
    int task = clamp((int)(a.task + 0.5), 0, 4);

    float rh = 15.0 * s;
    float4 r = card(at, float2(186.0 * s, 9.0 * s + 8.0 * rh));
    float y = r.y + 4.0 * s + 0.5 * rh;
    float x = r.x + 10.0 * s;
    x += dlLabel(LB_ANT, x, y, IL_T_TITLE * s, IL_INK, IL_LEFT) + 5.0 * s;
    dlInt((int)i, 1, x, y, IL_T_VALUE * s, IL_INK, IL_LEFT);
    if (i == focus) dlLabel(LB_FOCUS, r.z - 10.0 * s, y, IL_T_CAP * s, IL_ACCENT, IL_RIGHT);
    y += rh;
    dlLabel(LB_C_TASK, r.x + 10.0 * s, y, IL_T_CAP * s, IL_DIM, IL_LEFT);
    dlLabel(LB_T_OUT + (uint)task, r.z - 10.0 * s, y, IL_T_CAP * s, IL_INK, IL_RIGHT);
    y += rh;
    crow(r, y, LB_C_SPEED, a.speed, 1, LB_U_MMS, IL_INK);
    y += rh;
    crow(r, y, LB_C_LOAD, saturate(a.load) * 100.0, 0, LB_U_PCT, IL_INK);
    y += rh;
    dlLabel(LB_LANE, r.x + 10.0 * s, y, IL_T_CAP * s, IL_DIM, IL_LEFT);
    if (lane >= 0) dlInt(lane, 2, r.z - 10.0 * s, y, IL_T_VALUE * s, IL_INK, IL_RIGHT);
    else dlLabel(LB_OFF_TRAIL, r.z - 10.0 * s, y, IL_T_CAP * s, IL_MID, IL_RIGHT);
    y += rh;
    crow(r, y, LB_C_BODY, a.size, 2, LB_U_MM, IL_INK);
    y += rh;
    dlLabel(LB_C_FROM, r.x + 10.0 * s, y, IL_T_CAP * s, IL_DIM, IL_LEFT);
    if (a.home > 0.5)
    {
        float hw = dlInt((int)(a.home + 0.5), 1, r.z - 10.0 * s, y, IL_T_VALUE * s, IL_INK, IL_RIGHT);
        dlLabel(LB_F_STATION, r.z - 14.0 * s - hw, y, IL_T_CAP * s, IL_INK, IL_RIGHT);
        float ox = r.x + 10.0 * s + ilLabelW(LB_C_FROM, IL_T_CAP * s) + 8.0 * s;
        float ow = dlNum(a.age, 1, ox, y, IL_T_VALUE * s, IL_MID, IL_LEFT);
        dlLabel(LB_U_S, ox + ow + 3.0 * s, y, IL_T_CAP * s, IL_DIM, IL_LEFT);
    }
    else dlLabel(LB_F_NEST, r.z - 10.0 * s, y, IL_T_CAP * s, IL_INK, IL_RIGHT);
    y += rh;
    crow(r, y, LB_WORST, worst, 2, LB_U_MM, worst > slip_alarm ? IL_ALARM : IL_INK);
}

// ---------------------------------------------------------------- the moment under the pointer
void gaitCard(float2 at)
{
    float s = g_s;
    float4 ch = g_V.chart;
    FmGait hdr = Hist[0];
    uint cursor = (uint)max(hdr.t, 0.0) % FM_GAIT_HIST;
    uint written = (uint)max(hdr.bits, 0.0);
    if (written == 0u) return;
    uint idx = fcGaitSample(g_V, at.x, cursor, written);
    FmGait smp = Hist[1u + idx];
    FmGait now = Hist[1u + (cursor + FM_GAIT_HIST - 1u) % FM_GAIT_HIST];
    uint bits = (uint)(smp.bits + 0.5);
    uint down = 0u;
    [unroll] for (uint lg = 0u; lg < 6u; lg++) down += (bits >> lg) & 1u;
    dlVLine(at.x, ch.y, ch.w, IL_INK);

    float rh = 15.0 * s;
    float4 r = card(at, float2(160.0 * s, 9.0 * s + 4.0 * rh));
    float y = r.y + 4.0 * s + 0.5 * rh;
    float aw = dlLabel(LB_C_AGO, r.z - 10.0 * s, y, IL_T_CAP * s, IL_DIM, IL_RIGHT);
    dlNum(max(now.t - smp.t, 0.0), 2, r.z - 13.0 * s - aw, y, IL_T_VALUE * s, IL_INK, IL_RIGHT);
    dlLabel(LB_GAIT, r.x + 10.0 * s, y, IL_T_TITLE * s, IL_DIM, IL_LEFT);
    y += rh;
    dlLabel(LB_C_DOWN, r.x + 10.0 * s, y, IL_T_CAP * s, IL_DIM, IL_LEFT);
    dlInt((int)down, 1, r.z - 10.0 * s, y, IL_T_VALUE * s, IL_INK, IL_RIGHT);
    y += rh;
    crow(r, y, LB_C_SPEED, smp.speed, 1, LB_U_MMS, IL_INK);
    y += rh;
    crow(r, y, LB_C_SLIP, smp.slip, 2, LB_U_MM, smp.slip > slip_alarm ? IL_ALARM : IL_INK);
}

// A legend entry: a mark drawn by the caller, then its name; returns the width used.
float legend(float x, float y, uint label)
{
    return 12.0 * g_s + dlLabel(label, x + 12.0 * g_s, y, IL_T_CAP * g_s, IL_DIM, IL_LEFT) + 14.0 * g_s;
}

void layout(uint nearAnt)
{
    float2 R = g_R;
    float  s = g_s;
    FcView V = g_V;
    dlBegin(R);
    FmRec arena = PlanB[FM_ARENA];
    FmMeas ms = Meas[0];
    uint focus = min((uint)focus_ant, FM_MAX_ANTS - 1u);
    uint n = min((uint)ant_count, FM_MAX_ANTS);
    float2 ptr = fcPointer(R);
    float cs = IL_T_CAP * s, vs = IL_T_VALUE * s;

    // ---- title row
    float hy = ilMid(V.head).y + 1.0 * s;
    float tw = dlLabel(LB_TITLE, V.head.x, hy, 14.0 * s, IL_INK, IL_LEFT);
    dlLabel(LB_SUBTITLE, V.head.x + tw + 10.0 * s, hy, 12.0 * s, IL_DIM, IL_LEFT);
    float x = V.head.z;
    bool dormant = ((int)seed_mode) == 1;
    x -= dlLabel(dormant ? LB_P_DORMANT : LB_P_STEADY, x, hy, IL_T_TITLE * s, IL_INK, IL_RIGHT) + 7.0 * s;
    dlLabel(LB_POPULATION, x, hy, IL_T_TITLE * s, IL_DIM, IL_RIGHT);

    // ---- the arena plate: border, caption, legend
    dlBorderRect(V.arena, IL_RADIUS * s, IL_EDGE, 1.0);
    dlLabel(LB_ARENA, V.arena.x + 10.0 * s, V.arena.y + 13.0 * s, IL_T_TITLE * s, IL_DIM, IL_LEFT);
    float ly = V.arena.w - 13.0 * s, lx = V.arena.x + 10.0 * s;
    float2 sw = float2(8.0, 8.0) * s;
    dlRect(float4(lx, ly - 0.5 * sw.y, lx + sw.x, ly + 0.5 * sw.y), ptRamp(0.85), 1.0, 1.5 * s);
    lx += legend(lx, ly, LB_LG_FOOD);
    dlRect(float4(lx, ly - 0.5 * sw.y, lx + sw.x, ly + 0.5 * sw.y), ptSampleFill(ptId(0)), 1.0, 1.5 * s);
    lx += legend(lx, ly, LB_LG_HOME) + 8.0 * s;
    dlLine(float2(lx, ly + 3.0 * s), float2(lx + 8.0 * s, ly - 3.0 * s), 2.0 * s, IL_ACCENT, 1.0);
    lx += legend(lx, ly, LB_LG_FOCUS);
    dlCircle(float2(lx + 4.0 * s, ly), 2.5 * s, IL_MID, 1.0);
    lx += legend(lx, ly, LB_LG_PLANTED);
    dlRing(float2(lx + 4.0 * s, ly), 2.5 * s, 1.0, IL_MID, 1.0);
    lx += legend(lx, ly, LB_LG_LIFTED);
    dlCircle(float2(lx + 4.0 * s, ly), 2.5 * s, IL_ALARM, 1.0);
    legend(lx, ly, LB_LG_SLIP);

    // ---- the gait plate: which ant, the two tripods, the lanes
    dlBorderRect(V.gait, IL_RADIUS * s, IL_EDGE, 1.0);
    float gy = V.gait.y + 13.0 * s;
    float gx = V.gait.x + 10.0 * s;
    gx += dlLabel(LB_GAIT, gx, gy, IL_T_TITLE * s, IL_DIM, IL_LEFT) + 10.0 * s;
    gx += dlLabel(LB_ANT, gx, gy, IL_T_TITLE * s, IL_DIM, IL_LEFT) + 5.0 * s;
    dlInt((int)focus, 1, gx, gy, vs, IL_ACCENT, IL_LEFT);
    float4 ch = V.chart;
    float laneH = fcLaneH(V);
    float rx = ch.z;
    rx -= dlLabel(LB_TRIPOD_B, rx, gy, cs, IL_DIM, IL_RIGHT) + 5.0 * s;
    dlRect(float4(rx - 8.0 * s, gy - 3.0 * s, rx, gy + 3.0 * s), IL_MID, 1.0, 1.0);
    rx -= 8.0 * s + 14.0 * s;
    rx -= dlLabel(LB_TRIPOD_A, rx, gy, cs, IL_DIM, IL_RIGHT) + 5.0 * s;
    dlRect(float4(rx - 8.0 * s, gy - 3.0 * s, rx, gy + 3.0 * s), IL_INK, 1.0, 1.0);
    [loop] for (uint row = 0u; row < 6u; row++)
        dlLabel(LB_ROW_0 + row, ch.x - 10.0 * s, ch.y + ((float)row + 0.5) * laneH, cs, IL_DIM, IL_RIGHT);
    dlLabel(LB_SPEED_LANE, ch.x - 10.0 * s, ch.y + 6.5 * laneH, cs, IL_DIM, IL_RIGHT);

    // ---- the readout column
    ColL c = colLayout();
    float rh = colRowH();
    float hh = ilSnap(IL_HEADER * s);

    float4 b = dlPane(c.colony, s, LB_COLONY, false);
    float y = b.y + 0.5 * rh + 2.0 * s;
    irow(b, y, LB_ANTS, (int)n, IL_INK);                                 y += rh;
    irow(b, y, LB_WALKING, (int)(ms.traffic + 0.5), IL_INK);             y += rh;
    vrow(b, y, LB_CARRYING, saturate(ms.laden) * 100.0, 0, LB_U_PCT, IL_INK); y += rh;
    vrow(b, y, LB_SPEED, ms.speed, 1, LB_U_MMS, IL_INK);
    // the speed trace: its base (the pace with no music) dashed under it, so a surge on the beat
    // reads as the distance above that line
    dlRect(c.spd, IL_WELL, 1.0, 2.0 * s);
    float by = plotY(c.spd, speed_base / spdMax());
    dlDashed(float2(c.spd.x, by), float2(c.spd.z, by), 1.0, IL_RULE, 1.0, 4.0 * s, 3.0 * s);
    dlLabel(LB_BASE, c.spd.x + 5.0 * s, by - 7.0 * s, cs, IL_DIM, IL_LEFT);

    b = dlPane(c.footing, s, LB_FOOTING, false);
    y = b.y + 0.5 * rh + 2.0 * s;
    // Slip is the correctness reading of the whole node. Red past the threshold, because a number
    // that only gets bigger does not tell you when it became a fault.
    vrow(b, y, LB_SLIP, ms.slip, 2, LB_U_MM, ms.slip > slip_alarm ? IL_ALARM : IL_INK);   y += rh;
    vrow(b, y, LB_WORST, ms.maxSlip, 2, LB_U_MM, ms.maxSlip > slip_alarm ? IL_ALARM : IL_INK);
    dlRect(c.slip, IL_WELL, 1.0, 2.0 * s);
    float ay = plotY(c.slip, slip_alarm / slipMax());
    dlDashed(float2(c.slip.x, ay), float2(c.slip.z, ay), 1.0, IL_DIM, 1.0, 4.0 * s, 3.0 * s);
    float ax = c.slip.x + 5.0 * s;
    ax += dlLabel(LB_ALARM, ax, ay - 7.0 * s, cs, IL_DIM, IL_LEFT) + 4.0 * s;
    ax += dlNum(slip_alarm, 2, ax, ay - 7.0 * s, cs, IL_DIM, IL_LEFT) + 2.0 * s;
    dlLabel(LB_U_MM, ax, ay - 7.0 * s, cs, IL_DIM, IL_LEFT);

    b = dlPane(c.lanes, s, LB_LANES, false);
    y = b.y + 0.5 * rh + 2.0 * s;
    [loop] for (uint l = 0u; l < 4u; l++)
    {
        float v = (l == 0u) ? ms.e0 : ((l == 1u) ? ms.e1 : ((l == 2u) ? ms.e2 : ms.e3));
        float lw = dlLabel(LB_LANE, b.x + 10.0 * s, y, IL_T_BODY * s, IL_DIM, IL_LEFT);
        dlInt((int)l, 2, b.x + 14.0 * s + lw, y, vs, IL_MID, IL_LEFT);
        float uw = dlLabel(LB_U_PCT, b.z - 10.0 * s, y, cs, IL_DIM, IL_RIGHT);
        float nw = dlNum(saturate(v) * 100.0, 0, b.z - 13.0 * s - uw, y, vs, IL_INK, IL_RIGHT);
        float4 bar = float4(b.x + 74.0 * s, y - 3.0 * s, b.z - 20.0 * s - uw - max(nw, ilNumW(3u, vs)), y + 3.0 * s);
        dlRectEdged(bar, IL_WELL, 1.0, 1.5 * s, IL_EDGE, 1.0);
        if (v > 0.001) dlRect(float4(bar.x, bar.y, lerp(bar.x, bar.z, saturate(v)), bar.w), IL_MID, 1.0, 1.5 * s);
        y += rh;
    }
    vrow(b, y, LB_OFF_TRAIL, saturate(ms.offTrail) * 100.0, 0, LB_U_PCT, IL_MID);

    if (c.showPool)
    {
        // The release pool. In a Dormant Pool this is why the arena is empty or full: ants come
        // onto the plate only as emitters release them, and the sinks put them back.
        FmSta sum = Sta[FM_STA_SUM];
        b = dlPane(c.pool, s, LB_POOL, false);
        y = b.y + 0.5 * rh + 2.0 * s;
        irow(b, y, LB_ON_PLATE, (int)(sum.accum + 0.5), IL_INK);   y += rh;
        irow(b, y, LB_DORMANT, (int)(sum.lastTrig + 0.5), IL_INK); y += rh;
        irow(b, y, LB_STATIONS, (int)(sum.live + 0.5), IL_INK);
    }

    // the two history traces: one batch, filled by every thread after this
    dlBatch(traceOk() ? TRACE_ITEMS : 0u, 0u);

    // ---- the inspector: the ant under the pointer, or the moment of the gait under it
    FmTop T = fcArenaTop(V, arena);
    if (tooltips != 0)      // the inspector card and the mark of what it describes (Tooltips)
    {
        if (nearAnt != 0xFFFFu) antCard(nearAnt, ptr, T, focus);
        else if (ptr.x >= ch.x && ptr.x <= ch.z && ptr.y >= ch.y && ptr.y <= ch.w) gaitCard(ptr);
    }

    // ---- footer
    float fy = ilMid(V.foot).y;
    float kw = ilLabelW(LB_K_HOVER, cs) + 12.0 * s, kh = 18.0 * s;
    if (tooltips != 0)      // the hint names the hover card, so it goes with it
    {
        dlKeycap(float4(V.foot.x, fy - 0.5 * kh, V.foot.x + kw, fy + 0.5 * kh), s, LB_K_HOVER);
        dlLabel(LB_D_INSPECT, V.foot.x + kw + 6.0 * s, fy, cs, IL_DIM, IL_LEFT);
    }
    dlFinish();
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    g_R = _Resolution.xy;
    g_V = fcView(g_R);
    g_s = g_V.s;

    // The ant under the pointer: every thread searches a sixteenth of the population, the nearest
    // body within reach wins. Only ants the drawing shows (active, inside the arena plate).
    if (gi == 0u) gsNear = 0xFFFFFFFFu;
    GroupMemoryBarrierWithGroupSync();
    float2 ptr = fcPointer(g_R);
    if (tooltips != 0 && ilIn(ptr, g_V.draw))     // only the hover card needs it (Tooltips)
    {
        FmTop T = fcArenaTop(g_V, PlanB[FM_ARENA]);
        uint n = min((uint)ant_count, FM_MAX_ANTS);
        float reach = FC_PICK_PX * g_s;
        [loop] for (uint i = gi; i < n; i += IL_LAYOUT_THREADS)
        {
            FmAnt a = Ants[i];
            if (a.active < 0.5) continue;
            float d = length(fmTopToPx(T, a.pos.xz) - ptr);
            if (d < reach) InterlockedMin(gsNear, (min((uint)(d * 16.0), 0xFFFFu) << 16) | i);
        }
    }
    GroupMemoryBarrierWithGroupSync();
    uint nearAnt = (gsNear == 0xFFFFFFFFu) ? 0xFFFFu : (gsNear & 0xFFFFu);

    if (gi == 0u) layout(nearAnt);
    dlSync();
    ColL c = colLayout();
    ILBatch bt = dlGetBatch(0u);
    [loop] for (uint g = gi; g < bt.count; g += IL_LAYOUT_THREADS) { dlAt(bt, g); traceItem(g, c); }
    dlEnd(gi);
}
