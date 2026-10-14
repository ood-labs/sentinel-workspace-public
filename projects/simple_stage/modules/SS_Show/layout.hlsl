// SS_Show / layout - the show monitor, drawn entirely by the shared UI kit (ui.hlsl), laid out from
// the live panel extent. Five lanes, each as a 48-cell chase strip (what a chase with width .5 /
// spread .45 on that lane would do across the rig right now) with its phase cursor, a tape of the hits
// it actually played over the last 8 beats (history.hlsl), and its trigger count; the build ramp, the
// palettes in their own colour, the strobe gate, and which source is driving the rig. Point at a
// lane for its card: its timing (cycle, rest, offset, or the build / phrase length) and its last hit.
// The 240 chase cells and the 320 tape ticks are recorded in parallel (two batches).
#include "../_shared/ss_show.hlsli"
StructuredBuffer<float4> S : register(t0);
StructuredBuffer<float4> Hist : register(t1);
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"

#define CELLS 48u
#define HIST_N 64u
#define TAPE_BEATS 8.0

struct ShowView
{
    float  s;
    float4 head, lanes, pal, strobe, source;
    float4 rows;                                  // the lanes pane under its header
    float  rowH, stripX0, stripX1, tapeX0, tapeX1, countX;
};

ShowView showView(float2 R)
{
    ShowView g;
    g.s = max(ilCtx(R).s, 0.85);
    float s = g.s;
    float4 r = float4(10.0, 0.0, R.x - 10.0, R.y - 10.0);
    g.head = ilCutTop(r, 40.0 * s);
    float4 bottom = ilCutBottom(r, clamp(0.32 * (r.w - r.y), 150.0 * s, 210.0 * s));
    r.w -= 10.0 * s;
    g.lanes = r;
    float gap = 10.0 * s, w = bottom.z - bottom.x - 2.0 * gap;
    g.pal = float4(bottom.x, bottom.y, bottom.x + 0.30 * w, bottom.w);
    g.strobe = float4(g.pal.z + gap, bottom.y, g.pal.z + gap + 0.34 * w, bottom.w);
    g.source = float4(g.strobe.z + gap, bottom.y, bottom.z, bottom.w);
    g.rows = float4(g.lanes.x, g.lanes.y + IL_HEADER * s, g.lanes.z, g.lanes.w - 4.0 * s);
    g.rowH = (g.rows.w - g.rows.y) / 5.0;
    g.countX = g.lanes.z - 14.0 * s;
    g.tapeX1 = g.countX - 64.0 * s;
    g.stripX0 = g.lanes.x + 118.0 * s;
    g.tapeX0 = g.tapeX1 - 0.30 * (g.tapeX1 - g.stripX0);
    g.stripX1 = g.tapeX0 - 18.0 * s;
    return g;
}
float laneMid(ShowView g, uint lane) { return g.rows.y + (lane + 0.5) * g.rowH; }
float cellH(ShowView g) { return min(0.5 * g.rowH, 30.0 * g.s); }
float laneLevel(uint lane, float4 l) { return lane == 3u ? l.w : 1.0; }   // BUILD scales by its ramp

static ShowView gV;
static bool gOk;

// a caption and a number with an optional unit; returns the width
float capNum(uint caption, float v, int decimals, uint unit, float x, float y, float s)
{
    float w = dlLabel(caption, x, y, IL_T_CAP * s, IL_DIM, IL_LEFT) + 5.0 * s;
    w += dlNum(v, decimals, x + w, y, IL_T_VALUE * s, IL_INK, IL_LEFT);
    if (unit != 0xffffffffu) w += 4.0 * s + dlLabel(unit, x + w + 4.0 * s, y, IL_T_CAP * s, IL_DIM, IL_LEFT);
    return w + 14.0 * s;
}

// The card for the lane under the pointer: where its timing comes from, the timing, its last hit.
void laneCard(uint lane, float2 p, float2 R, float s)
{
    float4 l = S[3 + lane];
    bool surface = lane < 3u && S[1].w > 0.5;
    float2 size = float2(318.0, 84.0) * s;
    float2 o = p + 16.0 * s;
    if (o.x + size.x > R.x - 6.0) o.x = p.x - 16.0 * s - size.x;
    if (o.y + size.y > R.y - 6.0) o.y = p.y - 16.0 * s - size.y;
    float4 r = float4(o, o + size);
    dlRectEdged(r, IL_RAISE, 0.96, IL_RADIUS * s, IL_EDGE, 1.0);
    float x0 = r.x + 10.0 * s, y1 = r.y + 17.0 * s, y2 = r.y + 42.0 * s, y3 = r.y + 66.0 * s;
    dlLabel(LB_L_KICK + lane, x0, y1, IL_T_TITLE * s, IL_INK, IL_LEFT);
    if (lane < 3u) dlLabel(surface ? LB_SURFACE : LB_INTERNAL, r.z - 10.0 * s, y1, IL_T_CAP * s, IL_DIM, IL_RIGHT);
    float x = x0;
    if (surface) dlLabel(LB_STEPS, x, y2, IL_T_BODY * s, IL_DIM, IL_LEFT);
    else if (lane < 3u)
    {
        float cyc = lane == 0u ? lane1_cycle : (lane == 1u ? lane2_cycle : lane3_cycle);
        float rst = lane == 0u ? lane1_rest : (lane == 1u ? lane2_rest : lane3_rest);
        float off = lane == 0u ? lane1_offset : (lane == 1u ? lane2_offset : lane3_offset);
        x += capNum(LB_CYCLE, cyc, 2, LB_BEATS, x, y2, s);
        x += capNum(LB_REST, rst, 2, 0xffffffffu, x, y2, s);
        capNum(LB_OFFSET, off, 2, 0xffffffffu, x, y2, s);
    }
    else if (lane == 3u)
    {
        // BUILD ramps over its length while its pulses double every quarter (state.hlsl)
        x += capNum(LB_LENGTH, build_beats, 0, LB_BEATS, x, y2, s);
        x += capNum(LB_RAMP, l.y * 100.0, 0, LB_U_PCT, x, y2, s);
        capNum(LB_PULSES, exp2(min(3.0, floor(l.y * 4.0))), 0, LB_PER_BEAT, x, y2, s);
    }
    else
    {
        x += capNum(LB_LENGTH, phrase_beats, 0, LB_BEATS, x, y2, s);
        capNum(LB_THROUGH, l.x * 100.0, 0, LB_U_PCT, x, y2, s);
    }
    // the newest hit in the history ring
    uint h = lane * (HIST_N + 1u);
    uint w = (uint)Hist[h].y % HIST_N;
    float ago = S[2].y - Hist[h + 1u + (w + HIST_N - 1u) % HIST_N].x;
    x = x0;
    if (Hist[h].z == 260936.0 && ago >= 0.0 && ago < 1e6) x += capNum(LB_LAST_HIT, ago, 2, LB_BEATS_AGO, x, y3, s);
    capNum(LB_COUNT, fmod(l.z, 100000.0), 0, 0xffffffffu, x, y3, s);
}

void layout()
{
    float2 R = _Resolution.xy;
    ShowView g = gV;
    float s = g.s;
    dlBegin(R);
    float4 s2 = S[2], s11 = S[11], s12 = S[12];
    bool prog = s2.x > 0.5, running = s12.w > 0.5;

    // header: title, then BPM and the four beat lamps (the current beat is the live reading)
    float hy = ilMid(g.head).y;
    float tw = dlLabel(LB_TITLE, g.head.x + 6.0 * s, hy, 14.0 * s, IL_INK, IL_LEFT);
    dlLabel(LB_SUBTITLE, g.head.x + 6.0 * s + tw + 10.0 * s, hy, 12.0 * s, IL_DIM, IL_LEFT);
    uint cur = (uint)floor(s2.y) % 4u;
    float lx = g.head.z - 6.0 * s - 4.0 * 24.0 * s;
    [unroll] for (uint k = 0u; k < 4u; k++)
    {
        float4 r = float4(lx + k * 24.0 * s, hy - 5.0 * s, lx + k * 24.0 * s + 18.0 * s, hy + 5.0 * s);
        bool lit = gOk && running && k == cur;
        dlRectEdged(r, lit ? IL_ACCENT : IL_RAISE, 1.0, 2.0 * s, lit ? IL_ACCENT : IL_EDGE, 1.0);
    }
    float x = lx - 10.0 * s;
    x -= dlLabel(running ? LB_BEAT : LB_STOPPED, x, hy, IL_T_TITLE * s, running ? IL_DIM : IL_MID, IL_RIGHT) + 22.0 * s;
    x -= dlNum(s2.z, 1, x, hy, 16.0 * s, IL_INK, IL_RIGHT) + 7.0 * s;
    dlLabel(LB_BPM, x, hy, IL_T_TITLE * s, IL_DIM, IL_RIGHT);

    // lanes: the pane, its column captions, then the cells (a batch) under everything else
    dlPane(g.lanes, s, LB_LANES, false);
    float cy = g.lanes.y + 0.5 * IL_HEADER * s;
    dlLabel(LB_H_CHASE, g.stripX0, cy, IL_T_CAP * s, IL_DIM, IL_LEFT);
    dlLabel(LB_H_TAPE, g.tapeX0, cy, IL_T_CAP * s, IL_DIM, IL_LEFT);
    dlLabel(LB_COUNT, g.countX, cy, IL_T_CAP * s, IL_DIM, IL_RIGHT);
    if (!gOk) dlLabel(LB_WAITING, ilMid(g.rows).x, ilMid(g.rows).y, IL_T_BODY * s, IL_DIM, IL_CENTER);
    dlBatch(gOk ? 5u * CELLS : 0u, 0u);

    // hover: the lane under the pointer (never stored)
    float2 uv = _ViewportPointerPosition, p = uv * R;
    int hl = (gOk && all(uv >= 0.0) && all(uv <= 1.0) && ilIn(p, g.rows)) ? (int)floor((p.y - g.rows.y) / g.rowH) : -1;
    hl = hl > 4 ? -1 : hl;

    float bw = (g.tapeX1 - g.tapeX0) / TAPE_BEATS;
    float now = s2.y;
    [loop] for (uint lane = 0u; gOk && lane < 5u; lane++)
    {
        float4 l = S[3 + lane];
        bool on = l.y > 0.001;
        float ym = laneMid(g, lane), ch = cellH(g);
        if (lane > 0u) dlHLine(ym - 0.5 * g.rowH, g.lanes.x + 1.0, g.lanes.z - 1.0, IL_GRID);
        if ((int)lane == hl) dlRect(float4(g.lanes.x + 1.0, ym - 0.5 * g.rowH, g.lanes.z - 1.0, ym + 0.5 * g.rowH), IL_INK, 0.05, 0.0);
        dlCircle(float2(g.lanes.x + 16.0 * s, ym), 4.0 * s, on ? IL_INK : IL_RULE, on ? max(0.35, laneLevel(lane, l)) : 1.0);
        dlLabel(LB_L_KICK + lane, g.lanes.x + 30.0 * s, ym, IL_T_TITLE * s, on || (int)lane == hl ? IL_INK : IL_DIM, IL_LEFT);
        // the phase cursor over the strip: the lane's playhead
        float px = lerp(g.stripX0, g.stripX1, saturate(l.x));
        dlLine(float2(px, ym - 0.5 * ch - 4.0 * s), float2(px, ym + 0.5 * ch + 4.0 * s), 1.5 * s, IL_ACCENT, on ? 1.0 : 0.3);
        if (lane == 3u)
        {
            float4 track = float4(g.stripX0, ym + 0.5 * ch + 3.0 * s, g.stripX1, ym + 0.5 * ch + 6.0 * s);
            dlRect(track, IL_WELL, 1.0, 1.0);
            dlRect(float4(track.xy, lerp(track.x, track.z, saturate(l.y)), track.w), IL_MID, 1.0, 1.0);
        }
        // the tape: a well with beat lines (every fourth one brighter); the hits are a batch below
        float4 tape = float4(g.tapeX0, ym - 0.5 * ch, g.tapeX1, ym + 0.5 * ch);
        dlRect(tape, IL_WELL, 1.0, 1.5 * s);
        float first = ceil(now - TAPE_BEATS);
        [loop] for (float b = first; b <= now; b += 1.0)
        {
            float bx = g.tapeX1 - (now - b) * bw;
            dlVLine(bx, tape.y + 1.0, tape.w - 1.0, fmod(b, 4.0) < 0.5 ? IL_EDGE : IL_GRID);
        }
        dlInt((int)fmod(l.z, 100000.0), 1, g.countX, ym, IL_T_VALUE * s, IL_MID, IL_RIGHT);
    }
    dlBatch(gOk ? 5u * HIST_N : 0u, 0u);

    // palettes, in their own colour (pulled toward grey so a loud palette cannot outrank a reading)
    float4 pb = dlPane(g.pal, s, LB_PALETTES, false);
    float pad = 12.0 * s;
    float sw = min((pb.z - pb.x - 4.0 * pad) / 3.0, pb.w - pb.y - 2.0 * pad - 20.0 * s);
    [unroll] for (uint pi = 0u; pi < 3u; pi++)
    {
        float4 r = float4(pb.x + pad + pi * (sw + pad), pb.y + pad, pb.x + pad + pi * (sw + pad) + sw, pb.y + pad + sw);
        dlRectEdged(r, ptSampleFill(S[8 + pi].rgb), 1.0, IL_RADIUS * s, IL_RULE, 1.0);
        dlLabel(LB_PAL_A + pi, r.x, r.w + 12.0 * s, IL_T_TITLE * s, IL_DIM, IL_LEFT);
    }

    // strobe: rate and duty, the gate as it flashes, held and blackout states
    float4 sb = dlPane(g.strobe, s, LB_STROBE, false);
    float sx = sb.x + pad, row1 = sb.y + 0.22 * (sb.w - sb.y), row2 = sb.y + 0.52 * (sb.w - sb.y), row3 = sb.y + 0.80 * (sb.w - sb.y);
    float rw = dlNum(s12.x, 1, sx, row1, 24.0 * s, IL_INK, IL_LEFT);
    dlLabel(LB_PER_BEAT, sx + rw + 8.0 * s, row1 + 3.0 * s, IL_T_BODY * s, IL_DIM, IL_LEFT);
    float dw = dlLabel(LB_DUTY, sx, row2, IL_T_TITLE * s, IL_DIM, IL_LEFT) + 8.0 * s;
    dlNum(s12.y, 2, sx + dw, row2, IL_T_VALUE * s, IL_INK, IL_LEFT);
    bool gate = s11.y > 0.5 && s11.z < 0.5;
    float lw = min(104.0 * s, 0.38 * (sb.z - sb.x));
    float4 lamp = float4(sb.z - pad - lw, row1 - 16.0 * s, sb.z - pad, row1 + 16.0 * s);
    dlRectEdged(lamp, gate ? IL_INK : IL_WELL, 1.0, IL_RADIUS * s, gate ? IL_INK : IL_EDGE, 1.0);
    dlLabel(LB_GATE, ilMid(lamp).x, ilMid(lamp).y, IL_T_CAP * s, gate ? IL_FIELD : IL_DIM, IL_CENTER);
    dlChip(float4(sx, row3 - 12.0 * s, sx + 84.0 * s, row3 + 12.0 * s), s, LB_HELD, s11.x > 0.5, false, false);
    float4 bo = float4(sb.z - pad - lw, row3 - 12.0 * s, sb.z - pad, row3 + 12.0 * s);
    bool black = s11.z > 0.5;
    if (black) dlRect(bo, IL_ALARM, 1.0, IL_RADIUS * s);
    else dlRectEdged(bo, IL_RAISE, 1.0, IL_RADIUS * s, IL_EDGE, 1.0);
    dlLabel(LB_BLACKOUT, ilMid(bo).x, ilMid(bo).y, IL_T_BODY * s, black ? IL_FIELD : IL_DIM, IL_CENTER);

    // source: who is driving the rig (amber while the live programmer drives), lanes 1-3
    float4 so = dlPane(g.source, s, LB_SOURCE, false);
    float ox = so.x + pad, oz = so.z - pad;
    uint drive = prog ? LB_PROGRAMMER : (S[0].y > 0.5 ? LB_REFERENCE : LB_HOLD);
    float r1 = so.y + 0.3 * (so.w - so.y), r3 = so.y + 0.74 * (so.w - so.y);
    dlLabel(drive, ox, r1, 20.0 * s, prog ? IL_ACCENT : (drive == LB_HOLD ? IL_DIM : IL_INK), IL_LEFT);
    dlHLine(0.5 * (r1 + r3), ox, oz, IL_GRID);
    dlLabel(LB_LANES13, ox, r3, IL_T_TITLE * s, IL_DIM, IL_LEFT);
    dlLabel(S[1].w > 0.5 ? LB_SURFACE : LB_INTERNAL, oz, r3, IL_T_TITLE * s, IL_INK, IL_RIGHT);

    if (tooltips != 0 && hl >= 0) laneCard((uint)hl, p, R, s);   // the card (Tooltips); the row lift stays
    dlFinish();
}

// Batch 0 record i: lane i / 48, cell i % 48 - how bright a chase at that rank would be right now.
void drawCell(uint i)
{
    uint lane = i / CELLS, cell = i % CELLS;
    float4 l = S[3 + lane];
    float cw = (gV.stripX1 - gV.stripX0) / CELLS, ym = laneMid(gV, lane), ch = cellH(gV);
    float v = laneLevel(lane, l) * ssPulse(l.x, (cell + 0.5) / CELLS, 0.5, 0.45) * (l.y > 0.001 ? 1.0 : 0.0);
    float4 r = float4(gV.stripX0 + cell * cw, ym - 0.5 * ch, gV.stripX0 + (cell + 1u) * cw, ym + 0.5 * ch);
    r.xz = floor(r.xz + 0.5) + float2(1.0, -1.0);            // whole-pixel cells, a 2 px gap
    dlRect(r, lerp(IL_WELL, IL_INK, v), 1.0, 1.5 * gV.s);
}

// Batch 1 record i: lane i / 32, history entry i % 32 - a tick where that hit landed on the tape.
void drawHit(uint i)
{
    uint lane = i / HIST_N, k = i % HIST_N;
    uint h = lane * (HIST_N + 1u);
    if (Hist[h].z != 260936.0) return;
    float4 e = Hist[h + 1u + k];
    float age = S[2].y - e.x;
    if (age < 0.0 || age > TAPE_BEATS) return;
    float ym = laneMid(gV, lane), ch = cellH(gV);
    float x = gV.tapeX1 - age * (gV.tapeX1 - gV.tapeX0) / TAPE_BEATS;
    float hh = 0.5 * ch * lerp(0.35, 1.0, saturate(e.y));
    dlRect(float4(x - 1.0 * gV.s, ym - hh, x + 1.0 * gV.s, ym + hh), IL_INK, 1.0, 0.5 * gV.s);
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    gV = showView(_Resolution.xy);
    gOk = S[2].w == 260934;
    if (gi == 0u) layout();
    dlSync();
    ILBatch b0 = dlGetBatch(0u);
    [loop] for (uint i = gi; i < b0.count; i += IL_LAYOUT_THREADS) { dlAt(b0, i); drawCell(b0.user + i); }
    ILBatch b1 = dlGetBatch(1u);
    [loop] for (uint j = gi; j < b1.count; j += IL_LAYOUT_THREADS) { dlAt(b1, j); drawHit(b1.user + j); }
    dlEnd(gi);
}
