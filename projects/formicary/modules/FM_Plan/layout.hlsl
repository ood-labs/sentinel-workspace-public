// FM_Plan / layout - the plan canvas's type and chrome, recorded for the shared UI kit (ui.hlsl draws
// it over canvas.hlsl's plan strip and flow strip):
//
//   - the title row: the instrument, the arrangement, which way round the page faces;
//   - the plan plate: border, caption, the arena's size, the scale bar's caption, a legend for the
//     one identity hue on the drawing (food kind);
//   - the flow plate: border, caption, a legend for its marks, the ruler's hundreds, lane tags;
//   - the readout column: the records, the routes' cost, the live readings fed back from FM_Colony
//     (grey and labelled when nothing is wired, because a number that was not measured must not
//     look like one that was), and the selection with the verbs that act on it;
//   - the inspector: the record under the pointer in the plan - exactly the one a click there
//     would select - or the route of the lane under it in the flow strip;
//   - the footer: the global verbs, and the routes' status in alarm red when any is blocked.
//
// Every figure is read from the plan buffer or a live input; nothing here decides anything. Hover
// is read from the pointer snapshot and never stored. One thread records everything: the record
// set is 52 slots, so nothing here is worth batching.
//
// Rows are gathered into a small table and drawn by ONE loop (drawRows), and the selection pane and
// the hover card share one copy of the record code: FXC inlines every call, so a readout written as
// forty direct calls is forty copies of the text and number code and a compile measured in minutes.
#include "../_shared/formic.hlsli"
#include "layout.hlsli"
StructuredBuffer<FmRec> Plan : register(t0);
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"
#include "plan_view.hlsli"

#define NONE 0xFFFFu

static float  g_s;
static float2 g_R;
static FmRec  g_arena;

// ---------------------------------------------------------------- the row table
// kind: what the right-hand side is. v.x (and v.y) the figures, word a label id.
#define ROW_NUM    0u   // number, then unit
#define ROW_WORD   1u   // a word
#define ROW_PAIR   2u   // two signed numbers (x, z), then unit
#define ROW_SWATCH 3u   // a food kind: its identity swatch, then its word
#define ROW_ENDS   4u   // a route's ends: v = (from slot, to slot)
#define ROWS_MAX   10u

static uint   gN;
static uint   gCap[ROWS_MAX];
static uint   gKind[ROWS_MAX];
static float2 gV[ROWS_MAX];
static int    gDec[ROWS_MAX];
static uint   gWord[ROWS_MAX];
static float3 gInk[ROWS_MAX];

void rowAdd(uint cap, uint kind, float2 v, int dec, uint word, float3 ink)
{
    if (gN >= ROWS_MAX) return;
    gCap[gN] = cap; gKind[gN] = kind; gV[gN] = v; gDec[gN] = dec; gWord[gN] = word; gInk[gN] = ink;
    gN++;
}
void rowNum(uint cap, float v, int dec, uint unit, float3 ink) { rowAdd(cap, ROW_NUM, float2(v, 0.0), dec, unit, ink); }
void rowWord(uint cap, uint word, float3 ink) { rowAdd(cap, ROW_WORD, 0.0, 0, word, ink); }

// 0 nest, 1 food, 2 obstacle, 3 route, 4 station, 5 not a pickable record
uint recRole(uint slot)
{
    if (slot == FM_NEST) return 0u;
    if (slot >= FM_CACHE_0 && slot < FM_CACHE_0 + FM_CACHES) return 1u;
    if (slot >= FM_OBST_0 && slot < FM_OBST_0 + FM_OBSTS) return 2u;
    if (slot >= FM_EDGE_0 && slot < FM_EDGE_0 + FM_EDGES) return 3u;
    if (slot >= FM_STA_0 && slot < FM_STA_0 + FM_STAS) return 4u;
    return 5u;
}

// Draws the table in r, one row every rh from y: caption at the left, figure at the right.
// One if / else chain and no `continue`: with an early `continue` out of this [loop], FXC dropped
// the draw list's slot advances made inside the skipped-to branch, so the next row overwrote the
// food kind's word and swatch (seen live: the row's caption drew, its figure never did).
void drawRows(float4 r, float y, float rh)
{
    float s = g_s, cs = IL_T_CAP * s, vs = IL_T_VALUE * s;
    [loop] for (uint i = 0u; i < gN; i++)
    {
        float yy = y + (float)i * rh;
        uint k = gKind[i], w = gWord[i];
        float3 ink = gInk[i];
        dlLabel(gCap[i], r.x + 10.0 * s, yy, cs, IL_DIM, IL_LEFT);
        float xr = r.z - 10.0 * s;
        if (k == ROW_WORD) dlLabel(w, xr, yy, cs, ink, IL_RIGHT);
        else if (k == ROW_SWATCH)
        {
            xr -= dlLabel(w, xr, yy, cs, ink, IL_RIGHT) + 4.0 * s;
            dlRect(float4(xr - 8.0 * s, yy - 4.0 * s, xr, yy + 4.0 * s), ptSampleColour(ptId((int)gV[i].x)), 1.0, 1.5 * s);
        }
        else if (k == ROW_ENDS)
        {
            // FROM to TO, right-aligned: each end is NEST, or FOOD and its number
            [loop] for (uint e = 0u; e < 2u; e++)
            {
                uint node = (uint)((e == 0u) ? gV[i].y : gV[i].x);
                if (recRole(node) == 1u)
                {
                    xr -= dlInt((int)(node - FM_CACHE_0) + 1, 1, xr, yy, vs, IL_INK, IL_RIGHT) + 4.0 * s;
                    xr -= dlLabel(LB_K_FOOD, xr, yy, cs, IL_INK, IL_RIGHT);
                }
                else xr -= dlLabel(LB_K_NEST, xr, yy, cs, IL_INK, IL_RIGHT);
                if (e == 0u) xr -= 5.0 * s + dlLabel(LB_ARROW, xr - 5.0 * s, yy, cs, IL_DIM, IL_RIGHT) + 5.0 * s;
            }
        }
        else
        {
            if (w != NONE) xr -= dlLabel(w, xr, yy, cs, IL_DIM, IL_RIGHT) + 3.0 * s;
            if (k == ROW_PAIR)
            {
                xr -= dlNumEx(gV[i].y, gDec[i], 1, true, xr, yy, vs, ink, IL_RIGHT) + 8.0 * s;
                dlNumEx(gV[i].x, gDec[i], 1, true, xr, yy, vs, ink, IL_RIGHT);
            }
            else dlNum(gV[i].x, gDec[i], xr, yy, vs, ink, IL_RIGHT);
        }
    }
}

// ---------------------------------------------------------------- keycaps
float keyW(uint k) { return ilLabelW(k, IL_T_CAP * g_s) + 12.0 * g_s; }
// One verb: its key (or a more / less pair) and what it does. Returns the width used.
float verbW(uint3 v)
{
    float s = g_s;
    float w = keyW(v.x) + 6.0 * s + ilLabelW(v.z, IL_T_CAP * s) + 14.0 * s;
    if (v.y != NONE) w += keyW(v.y) + 3.0 * s;
    return w;
}
float verb(float x, float y, uint3 v)
{
    float s = g_s, kh = 18.0 * s, x0 = x;
    [loop] for (uint i = 0u; i < 2u; i++)
    {
        uint k = (i == 0u) ? v.x : v.y;
        if (k == NONE) break;
        float kw = keyW(k);
        dlKeycap(float4(x, y - 0.5 * kh, x + kw, y + 0.5 * kh), s, k);
        x += kw + 3.0 * s;
    }
    x += 3.0 * s;
    return (x - x0) + dlLabel(v.z, x, y, IL_T_CAP * s, IL_DIM, IL_LEFT) + 14.0 * s;
}

// The plan's real verbs (plan.hlsl and the manifest's bindings), as (key, second key or NONE, what
// it does): 0..6 the footer's global ones, then each record kind's, shown in the selection pane
// where they act on the selected record.
static const uint3 VERBS[27] = {
    uint3(LB_KEY_CLICK, NONE, LB_D_SELECT), uint3(LB_KEY_DRAG, NONE, LB_D_MOVE), uint3(LB_KEY_A, NONE, LB_D_ADD),
    uint3(LB_KEY_B, NONE, LB_D_ROUTE), uint3(LB_KEY_R, NONE, LB_D_RESEED), uint3(LB_KEY_P, NONE, LB_D_PALETTE),
    uint3(LB_KEY_C, NONE, LB_D_CLEAR),
    // nest
    uint3(LB_KEY_X, NONE, LB_V_ONOFF),
    // food
    uint3(LB_KEY_F, LB_KEY_V, LB_V_PAYLOAD), uint3(LB_KEY_N, NONE, LB_V_REROLL), uint3(LB_KEY_X, NONE, LB_V_ONOFF),
    // obstacle
    uint3(LB_KEY_M, NONE, LB_V_KIND), uint3(LB_KEY_F, LB_KEY_V, LB_V_SIZE), uint3(LB_KEY_N, NONE, LB_V_REROLL), uint3(LB_KEY_X, NONE, LB_V_ONOFF),
    // route
    uint3(LB_KEY_G, LB_KEY_H, LB_V_RECRUIT), uint3(LB_KEY_B, NONE, LB_V_ROUTE), uint3(LB_KEY_N, NONE, LB_V_REROLL), uint3(LB_KEY_X, NONE, LB_V_ONOFF),
    // station
    uint3(LB_KEY_M, NONE, LB_V_KIND), uint3(LB_KEY_E, NONE, LB_V_MODE), uint3(LB_KEY_T, NONE, LB_V_FIRE), uint3(LB_KEY_F, LB_KEY_V, LB_V_STRENGTH),
    uint3(LB_KEY_G, LB_KEY_H, LB_V_REACH), uint3(LB_KEY_N, NONE, LB_V_REROLL), uint3(LB_KEY_X, NONE, LB_V_ONOFF), uint3(LB_KEY_D, NONE, LB_V_DELETE) };
// per record kind (nest, food, obstacle, route, station): first verb and count
static const uint2 ROLE_VERBS[5] = { uint2(7u, 1u), uint2(8u, 3u), uint2(11u, 4u), uint2(15u, 4u), uint2(19u, 8u) };

// ---------------------------------------------------------------- records
// A route's lane: the active-edge ordinal the flow strip stacks it at (and FM_Colony measures in).
uint laneOf(uint e)
{
    uint k = 0u;
    for (uint j = 0u; j < e && j < FM_EDGES; j++) if (Plan[FM_EDGE_0 + j].active > 0.5) k++;
    return k;
}
// The measured share of a lane, or -1: only the first four lanes have a feedback channel.
float laneMeas(uint lane)
{
    if (lane == 0u) return live_e0;
    if (lane == 1u) return live_e1;
    if (lane == 2u) return live_e2;
    if (lane == 3u) return live_e3;
    return -1.0;
}

// A record's defining rows, into the table. dims for an obstacle = (half length, height, half width).
void gatherRecord(uint slot)
{
    uint role = recRole(slot);
    FmRec r = Plan[slot];
    int k = (int)(r.kind + 0.5), md = (int)(r.p1 + 0.5);
    gN = 0u;
    if (role == 0u)
    {
        rowNum(LB_C_RADIUS, r.dims.x, 1, LB_U_MM, IL_INK);
        rowAdd(LB_C_AT, ROW_PAIR, fmRecWorld(r, g_arena), 1, LB_U_MM, IL_INK);
    }
    else if (role == 1u)
    {
        // food kind is an identity: its swatch is the colour the plan draws the pile in
        rowAdd(LB_C_KIND, ROW_SWATCH, float2((float)clamp(k, 0, 2), 0.0), 0, LB_FK_0 + (uint)clamp(k, 0, 2), IL_INK);
        rowNum(LB_C_PAYLOAD, r.p0, 2, NONE, IL_INK);
        rowNum(LB_C_RADIUS, r.dims.x, 1, LB_U_MM, IL_INK);
    }
    else if (role == 2u)
    {
        rowWord(LB_C_KIND, LB_OB_0 + (uint)clamp(k, 0, 2), IL_INK);
        rowNum(LB_C_LENGTH, r.dims.x * 2.0, 1, LB_U_MM, IL_INK);
        rowNum(LB_C_WIDTH, r.dims.z * 2.0, 1, LB_U_MM, IL_INK);
        rowNum(LB_C_HEIGHT, r.dims.y, 1, LB_U_MM, IL_INK);
        rowNum(LB_C_YAW, frac(r.p0 / 6.2831853) * 360.0, 0, LB_U_DEG, IL_INK);
    }
    else if (role == 3u)
    {
        float straight = length(fmRecWorld(Plan[(uint)r.p1], g_arena) - fmRecWorld(Plan[(uint)r.p0], g_arena));
        rowAdd(LB_C_FROM, ROW_ENDS, float2(r.p0, r.p1), 0, NONE, IL_INK);
        rowNum(LB_C_WALKED, r.p3, 1, LB_U_MM, IL_INK);
        rowNum(LB_C_STRAIGHT, straight, 1, LB_U_MM, IL_INK);
        // the cost of the detour: the gap between the lane's end and its ghost tick
        rowNum(LB_C_DETOUR, max(r.p3 / max(straight, 1e-3) - 1.0, 0.0) * 100.0, 0, LB_U_PCT, IL_INK);
        rowNum(LB_C_RECRUIT, r.p2, 2, NONE, IL_INK);
        // measured clearance: negative means the route runs through something
        if (abs(r.pad1) < 1e5) rowNum(LB_C_CLEAR, r.pad1, 1, LB_U_MM, r.pad1 < 0.0 ? IL_ALARM : IL_INK);
        else rowWord(LB_C_CLEAR, LB_NONE_NEAR, IL_MID);
        // the traffic FM_Colony measured on this lane - a live reading, so the accent, when there is one
        float m = (r.active > 0.5) ? laneMeas(laneOf(slot - FM_EDGE_0)) : -1.0;
        if (m >= 0.0) rowNum(LB_LG_MEASURED, saturate(m) * 100.0, 0, LB_U_PCT, IL_ACCENT);
        else rowWord(LB_LG_MEASURED, LB_LG_NONE, IL_MID);
    }
    else if (role == 4u)
    {
        rowWord(LB_C_KIND, LB_SK_0 + (uint)clamp(k, 0, 3), IL_INK);
        rowWord(LB_C_MODE, (k == 0) ? LB_EM_0 + (uint)clamp(md, 0, 2) : ((k == 3) ? LB_SM_0 + (uint)clamp(md, 0, 1) : LB_AM_0 + (uint)clamp(md, 0, 1)), IL_INK);
        // strength means a different thing per kind: ants released, a steering gain, ants swallowed
        if (k == 0) rowNum(LB_C_STRENGTH, r.p0, 1, LB_U_PER_S, IL_INK);
        else if (k == 3) rowNum(LB_DRAIN, r.p0, 1, LB_U_PER_S, IL_INK);
        else rowNum(LB_GAIN, r.p0, 2, NONE, IL_INK);
        rowNum(LB_C_REACH, fmStaRadius(r), 1, LB_U_MM, IL_INK);
        if (k == 0)
        {
            rowNum(LB_C_BURST, r.p3, 0, LB_U_ANTS, IL_INK);
            if (r.p2 > 0.5) rowNum(LB_C_BUDGET, r.p2, 0, LB_U_ANTS, IL_INK);
            else rowWord(LB_C_BUDGET, LB_UNLIMITED, IL_MID);
            rowNum(LB_C_SPREAD, r.dims.z * 57.29578, 0, LB_U_DEG, IL_INK);
            rowNum(LB_C_FIRED, r.pad0, 0, NONE, IL_INK);
        }
        else if ((k == 1 || k == 2) && md == 1) rowNum(LB_C_PULSE, r.p3, 2, LB_U_HZ, IL_INK);
    }
}

// A record's name row: kind and number (accent when it is the selection), state at the right.
// Food, obstacles and stations are numbered from 1 in slot order (FM_Stage numbers stations the
// same way), a route by its lane.
void nameRow(uint slot, float4 r, float y)
{
    float s = g_s;
    uint role = recRole(slot);
    FmRec rec = Plan[slot];
    uint fl = (uint)rec.flags;
    float3 ink = ((fl & F_SELECTED) != 0u) ? IL_ACCENT : IL_INK;
    float x = r.x + 10.0 * s;
    x += dlLabel(LB_K_NEST + role, x, y, IL_T_TITLE * s, ink, IL_LEFT) + 5.0 * s;
    int num = -1;
    if (role == 1u) num = (int)(slot - FM_CACHE_0) + 1;
    else if (role == 2u) num = (int)(slot - FM_OBST_0) + 1;
    else if (role == 3u) num = (int)laneOf(slot - FM_EDGE_0);
    else if (role == 4u) num = (int)(slot - FM_STA_0) + 1;
    if (num >= 0) dlInt(num, (role == 3u) ? 2 : 1, x, y, IL_T_VALUE * s, ink, IL_LEFT);
    uint st = NONE;
    float3 sink = IL_DIM;
    if (rec.active < 0.5) st = LB_ST_OFF;
    else if (role == 3u && (fl & F_BLOCKED) != 0u) { st = LB_ST_BLOCKED; sink = IL_ALARM; }
    else if ((fl & F_EDITED) != 0u) st = LB_ST_EDITED;
    if (st != NONE) dlLabel(st, r.z - 10.0 * s, y, IL_T_CAP * s, sink, IL_RIGHT);
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

// The hovered record's hot state: one value step - an ink ring (an obstacle's outline) just outside
// everything the canvas draws for it, so it never covers a mark. Never a hue: the accent stays the
// selection's.
void hoverMark(uint slot, FmLayout L, float hair)
{
    float s = g_s, w = 1.5 * s;
    uint role = recRole(slot);
    FmRec r = Plan[slot];
    float2 c = fmPlanToPx(L, fmRecWorld(r, g_arena));
    if (role == 2u)
    {
        // the obstacle's own frame (formic.hlsli fmObstDist): local x along its yaw
        float m = 4.0 * s / max(L.scale, 1e-4);
        float ca = cos(r.p0), sa = sin(r.p0);
        float2 ex = float2(ca, sa) * (r.dims.x + m), ez = float2(-sa, ca) * (r.dims.z + m);
        float2 w0 = fmRecWorld(r, g_arena);
        [loop] for (uint q = 0u; q < 4u; q++)
        {
            float2 u0 = float2((q == 1u || q == 2u) ? 1.0 : -1.0, (q >= 2u) ? 1.0 : -1.0);
            float2 u1 = float2((q == 0u || q == 1u) ? 1.0 : -1.0, (q == 1u || q == 2u) ? 1.0 : -1.0);
            dlLine(fmPlanToPx(L, w0 + ex * u0.x + ez * u0.y), fmPlanToPx(L, w0 + ex * u1.x + ez * u1.y), w, IL_INK, 0.9);
        }
        return;
    }
    float rad;
    if (role == 0u) rad = max(max(r.dims.x, 0.5) * L.scale, 5.0 * hair) * 1.6 + 3.0 * s;
    else if (role == 1u) rad = max(max(r.dims.x, 0.4) * L.scale, 3.0 * hair) + (6.5 + 5.0 * saturate(r.p0)) * hair + 4.0 * s;
    else if (role == 4u) rad = 7.0 * hair * 2.9 + 4.0 * s;
    else
    {
        // a route: its mid handle, and its lane in the flow strip, so the two views name one route
        c = fmPlanToPx(L, fmEdgeHandle(fmRecWorld(Plan[(uint)r.p0], g_arena), fmRecWorld(Plan[(uint)r.p1], g_arena), float2(r.dims.x, r.dims.z)));
        rad = 4.5 * hair + 5.0 * s;
        float2 lp = fmFlowToPx(L, 0.0, laneOf(slot - FM_EDGE_0));
        dlBorderRect(float4(lp.x - 40.0 * s, lp.y - 0.5 * L.laneH, FM_DRAW_R * g_R.x - 6.0 * s, lp.y + 0.5 * L.laneH), 2.0 * s, IL_RULE, 1.0);
    }
    dlRing(c, rad, w, IL_INK, 0.9);
}

void layout()
{
    float2 R = g_R;
    float  s = g_s;
    dlBegin(R);
    FmRec hdr = Plan[FM_HEADER];
    g_arena = Plan[FM_ARENA];
    uint lanes = max((uint)hdr.kind, 1u);
    float maxRoute = max(hdr.p3, 1.0);
    uint selSlot = (hdr.pos.y > 0.5) ? (uint)(hdr.pos.y - 1.0) : NONE;
    FmLayout L = fmLayout(R, g_arena, maxRoute, lanes);
    float hair = max(R.x / 1200.0, 0.75);        // the canvas's hairline unit (canvas.hlsl)
    float cs = IL_T_CAP * s, vs = IL_T_VALUE * s, ts = IL_T_TITLE * s;
    bool measured = (live_e0 >= 0.0);

    // ---- title row
    float4 hd = fmHeadRect(R);
    float hy = 0.5 * hd.w;
    float tw = dlLabel(LB_TITLE, hd.x, hy, 14.0 * s, IL_INK, IL_LEFT);
    dlLabel(LB_SUBTITLE, hd.x + tw + 10.0 * s, hy, 12.0 * s, IL_DIM, IL_LEFT);
    // each enum value sits in a slot as wide as its widest option, so switching one never moves
    // the captions (a header that reflows is a header you stop reading)
    float wArr = 0.0;
    [loop] for (uint a = 0u; a < 4u; a++) wArr = max(wArr, ilLabelW(LB_AR_0 + a, ts));
    float x = hd.z - max(ilLabelW(LB_FACE_0, ts), ilLabelW(LB_FACE_1, ts));
    dlLabel(LB_FACE_0 + (uint)clamp((int)plan_facing, 0, 1), x, hy, ts, IL_INK, IL_LEFT);
    x -= 7.0 * s;
    x -= dlLabel(LB_FACES, x, hy, ts, IL_DIM, IL_RIGHT) + 22.0 * s + wArr;
    dlLabel(LB_AR_0 + (uint)clamp((int)arrangement, 0, 3), x, hy, ts, IL_INK, IL_LEFT);
    dlLabel(LB_ARRANGEMENT, x - 7.0 * s, hy, ts, IL_DIM, IL_RIGHT);

    // ---- the plan plate: caption, the arena's size, the scale bar's caption, the food-kind legend
    float4 pr = fmPlanRect(R);
    dlBorderRect(pr, IL_RADIUS * s, IL_EDGE, 1.0);
    float cy = pr.y + 13.0 * s;
    dlLabel(LB_PLAN, pr.x + 10.0 * s, cy, ts, IL_DIM, IL_LEFT);
    float2 ah = fmArenaHalf(g_arena);
    x = pr.z - 10.0 * s;
    x -= dlLabel(LB_U_MM, x, cy, cs, IL_DIM, IL_RIGHT) + 3.0 * s;
    [loop] for (uint ax = 0u; ax < 2u; ax++)
    {
        x -= dlNum(((ax == 0u) ? ah.y : ah.x) * 2.0, 0, x, cy, vs, IL_MID, IL_RIGHT) + 4.0 * s;
        if (ax == 0u) x -= dlLabel(LB_U_X, x, cy, cs, IL_DIM, IL_RIGHT) + 4.0 * s;
    }
    dlLabel(LB_ARENA, x - 3.0 * s, cy, ts, IL_DIM, IL_RIGHT);
    float2 sb = float2(pr.x + 16.0 * hair, pr.w - 16.0 * hair);          // canvas.hlsl's scale bar
    dlLabel(LB_TEN_MM, sb.x, sb.y - 13.0 * hair, cs, IL_DIM, IL_LEFT);
    float ly = pr.w - 13.0 * s;
    x = pr.z - 10.0 * s;
    [loop] for (int fk = 2; fk >= 0; fk--)
    {
        x -= dlLabel(LB_KEY_A + (uint)fk, x, ly, cs, IL_DIM, IL_RIGHT) + 4.0 * s;
        dlRect(float4(x - 8.0 * s, ly - 4.0 * s, x, ly + 4.0 * s), ptSampleColour(ptId(fk)), 1.0, 1.5 * s);
        x -= 18.0 * s;
    }
    dlLabel(LB_LG_KIND, x + 4.0 * s, ly, cs, IL_DIM, IL_RIGHT);

    // ---- the flow plate: caption, legend, the ruler's hundreds, lane tags
    float4 fr = fmFlowRect(R);
    dlBorderRect(fr, IL_RADIUS * s, IL_EDGE, 1.0);
    float2 blk = fmFlowBlockY(L, lanes);
    float fy = fr.y + 13.0 * s;
    if (blk.x - 5.0 * hair - fr.y >= 20.0 * s)          // many lanes fill the strip: then the lanes win
    {
        dlLabel(LB_FLOW, fr.x + 10.0 * s, fy, ts, IL_DIM, IL_LEFT);
        x = fr.z - 10.0 * s;
        x -= dlLabel(LB_LG_NONE, x, fy, cs, IL_DIM, IL_RIGHT) + 5.0 * s;
        dlDashed(float2(x - 14.0 * s, fy), float2(x, fy), 1.5 * s, IL_RULE, 1.0, 3.0 * s, 2.5 * s);
        x -= 28.0 * s;
        x -= dlLabel(LB_LG_MEASURED, x, fy, cs, IL_DIM, IL_RIGHT) + 5.0 * s;
        dlRect(float4(x - 14.0 * s, fy - 2.5 * s, x, fy + 2.5 * s), IL_ACCENT, 1.0, 1.0);
        x -= 28.0 * s;
        x -= dlLabel(LB_LG_STRAIGHT, x, fy, cs, IL_DIM, IL_RIGHT) + 6.0 * s;
        dlVLine(x, fy - 5.0 * s, fy + 5.0 * s, IL_DIM);
    }
    float ry = min(blk.y + 5.0 * hair + 9.0 * s, fr.w - 7.0 * s);
    dlClip(fr);
    dlLabel(LB_U_MM, L.flowO.x, ry, cs, IL_DIM, IL_CENTER);
    // the ruler's hundreds, then one tag per lane: one number call between them
    uint lane = 0u, t = 4u;
    [loop] for (uint e = 0u; e < FM_EDGES + 4u; e++)
    {
        float2 at = 0.0;
        float3 ink = IL_DIM;
        int n = 0;
        uint al = IL_RIGHT;
        if (e < 4u)
        {
            float dmm = (float)(t + 4u * e) * 25.0;
            if (dmm > maxRoute * 1.08) continue;
            at = float2(L.flowO.x + dmm * L.flowScale, ry); n = (int)dmm; al = IL_CENTER;
        }
        else
        {
            uint ei = e - 4u;
            if (Plan[FM_EDGE_0 + ei].active < 0.5) continue;
            at = fmFlowToPx(L, 0.0, lane) - float2(6.0 * hair, 0.0); n = (int)lane;
            if ((FM_EDGE_0 + ei) == selSlot) ink = IL_ACCENT;
            lane++;
        }
        dlInt(n, (e < 4u) ? 1 : 2, at.x, at.y, cs, ink, al);
    }
    dlClipReset();

    // ---- the readout column: three readout panes from one row table, then the selection pane
    float4 col = fmColRect(R);
    float rh = ilSnap(20.0 * s), hh = ilSnap(IL_HEADER * s), g = ilSnap(8.0 * s);
    float4 cr = col;
    uint nOn[3] = { 0u, 0u, 0u };                      // active trails, stations, obstacles
    for (uint k1 = 0u; k1 < FM_EDGES; k1++) if (Plan[FM_EDGE_0 + k1].active > 0.5) nOn[0]++;
    for (uint k2 = 0u; k2 < FM_STAS; k2++) if (Plan[FM_STA_0 + k2].active > 0.5) nOn[1]++;
    for (uint k3 = 0u; k3 < FM_OBSTS; k3++) if (Plan[FM_OBST_0 + k3].active > 0.5) nOn[2]++;
    [loop] for (uint pane = 0u; pane < 3u; pane++)
    {
        gN = 0u;
        uint title = LB_P_ARR;
        if (pane == 0u)
        {
            rowNum(LB_R_FOOD, hdr.tint.y, 0, NONE, IL_INK);
            rowNum(LB_R_TRAILS, (float)nOn[0], 0, NONE, IL_INK);
            rowNum(LB_R_STATIONS, (float)nOn[1], 0, NONE, nOn[1] > 0u ? IL_INK : IL_DIM);
            rowNum(LB_R_OBST, (float)nOn[2], 0, NONE, nOn[2] > 0u ? IL_INK : IL_DIM);
        }
        else if (pane == 1u)
        {
            title = LB_P_ROUTES;
            // the plan floors its longest route at 1 mm so the flow strip always has a scale;
            // with no trail on, that floor is not a walk, so the row says so instead
            if (nOn[0] > 0u) rowNum(LB_R_LONGEST, maxRoute, 1, LB_U_MM, IL_INK);
            else             rowWord(LB_R_LONGEST, LB_NO_TRAIL, IL_DIM);
            rowNum(LB_R_RECRUIT, hdr.p2, 2, NONE, nOn[0] > 0u ? IL_INK : IL_DIM);
        }
        else
        {
            // LIVE: the only numbers on the canvas that were MEASURED rather than authored, so the
            // accent is spent here - but only when there IS a measurement. Before FM_Colony's
            // control outputs are wired every one reads a hard zero, and a zero in the live colour
            // would claim a reading that was never taken; the lane shares default to -1 precisely
            // so "not measured" can be told apart.
            title = LB_P_LIVE;
            float3 li = measured ? IL_ACCENT : IL_RULE;
            rowNum(LB_R_WALKING, max(live_traffic, 0.0), 0, LB_U_ANTS, li);
            rowNum(LB_R_LADEN, saturate(live_laden) * 100.0, 0, LB_U_PCT, li);
            rowNum(LB_R_SPEED, max(live_speed, 0.0), 1, LB_U_MMS, li);
            // foot slip is a CORRECTNESS reading: past about a third of a millimetre per step the
            // ants are skating rather than walking, so it turns alarm red there (the canvas's own
            // threshold, unchanged from before the kit)
            rowNum(LB_R_SLIP, max(live_slip, 0.0), 2, LB_U_MM, (measured && live_slip > 0.35) ? IL_ALARM : li);
        }
        float4 pn = ilCutTop(cr, hh + (float)gN * rh + 8.0 * s);
        cr.y += g;
        float4 b = dlPane(pn, s, title, false);
        if (pane == 2u && !measured) dlLabel(LB_NO_READING, pn.z - 10.0 * s, ilMid(ilPaneHead(pn, s)).y, cs, IL_DIM, IL_RIGHT);
        drawRows(b, b.y + 0.5 * rh + 3.0 * s, rh);
    }
    // the selection pane takes what is left of the column, when there is room for one
    bool selRoom = (cr.w - cr.y) >= hh + 2.0 * rh;
    float4 selBody = float4(0.0, 0.0, 0.0, 0.0);
    if (selRoom) selBody = dlPane(cr, s, LB_P_SEL, false);      // (not ?: - FXC evaluates both sides)

    // ---- footer: the routes' status at the right, the global verbs from the left up to it
    float4 ft = fmFootRect(R);
    float fyy = ilMid(ft).y;
    uint blocked = (uint)hdr.tint.z;
    float statusL;
    if (blocked > 0u)
    {
        float cw = ilNumW(ilFormat((float)blocked, 0, 1, false).n, vs) + 6.0 * s + ilLabelW(LB_S_BLOCKED, ts) + 20.0 * s;
        float4 chip = float4(ft.z - cw, fyy - 10.0 * s, ft.z, fyy + 10.0 * s);
        dlRectEdged(chip, IL_PANEL, 1.0, IL_RADIUS * s, IL_ALARM, 1.0);
        float cx = chip.x + 10.0 * s;
        cx += dlInt((int)blocked, 1, cx, fyy, vs, IL_ALARM, IL_LEFT) + 6.0 * s;
        dlLabel(LB_S_BLOCKED, cx, fyy, ts, IL_ALARM, IL_LEFT);
        statusL = chip.x;
    }
    else statusL = ft.z - dlLabel(LB_S_CLEAR, ft.z, fyy, ts, IL_DIM, IL_RIGHT);
    float hx = ft.x;
    [loop] for (uint f = 0u; f < 7u; f++)
    {
        if (hx + verbW(VERBS[f]) > statusL - 16.0 * s) break;
        hx += verb(hx, fyy, VERBS[f]);
    }
    // what "blocked" means, where there is room for it
    if (blocked > 0u) dlLabelFit(LB_S_ROUTES, statusL - 10.0 * s, fyy, cs, IL_DIM, IL_RIGHT, statusL - 20.0 * s - hx);

    // ---- the hovered record: what a click here would select in the plan, or the route of the
    // lane under the pointer in the flow strip (a readout: pointing at a lane selects nothing)
    float2 ptr = fmPointer(R);
    uint hov = NONE;
    if (ptr.x >= 0.0 && fmInPlanStrip(L, ptr))
    {
        uint p = fmHoverPick(fmPxToPlan(L, ptr), L, g_arena);
        if (p > 0u) hov = p - 1u;
    }
    else if (ptr.x >= 0.0)
    {
        uint slot;
        if (fmFlowLaneAt(L, ptr, lanes, slot) != 0xFFFFu) hov = FM_EDGE_0 + slot;
    }

    // ---- the selection pane's record and verbs (use 0), then the inspector card on top (use 1):
    // one copy of the record code between them
    // (No `continue` here: see drawRows.)
    [loop] for (uint use = 0u; use < 2u; use++)
    {
        uint slot = (use == 0u) ? selSlot : hov;
        if (use == 0u) dlClip(ilInset(selBody, 1.0)); else dlClipReset();   // a short pane clips its rows
        bool shown = use == 1u || selRoom;
        bool none = slot == NONE || recRole(slot) >= 5u;
        bool rows = use == 0u || tooltips != 0;      // the card beside the pointer (Tooltips); the hover mark stays
        if (shown && none && use == 0u)
            dlLabelFit(LB_NOTHING, selBody.x + 10.0 * s, selBody.y + 0.5 * rh + 3.0 * s, IL_T_BODY * s, IL_DIM, IL_LEFT, selBody.z - selBody.x - 20.0 * s);
        if (shown && !none && use == 1u) hoverMark(slot, L, hair);
        if (shown && !none && rows)
        {
            gatherRecord(slot);
            float4 box = selBody;
            float pitch = rh;
            if (use == 1u)
            {
                pitch = ilSnap(15.0 * s);
                box = card(ptr, float2(ilSnap(200.0 * s), ilSnap(10.0 * s) + (1.0 + (float)gN) * pitch));
            }
            float y0 = box.y + 0.5 * pitch + ((use == 0u) ? 3.0 * s : 5.0 * s);
            nameRow(slot, box, y0);
            drawRows(box, y0 + pitch, pitch);

            // the verbs that act on the selection, wrapped to the pane
            if (use == 0u)
            {
                float vy = y0 + (1.0 + (float)gN) * pitch;
                dlHLine(vy - 0.5 * pitch + 4.0 * s, box.x + 1.0, box.z - 1.0, IL_EDGE);
                vy += 12.0 * s;
                uint2 rv = ROLE_VERBS[recRole(slot)];
                float vx = box.x + 10.0 * s;
                [loop] for (uint v = 0u; v < rv.y; v++)
                {
                    uint3 vb = VERBS[rv.x + v];
                    if (vx + verbW(vb) > box.z && vx > box.x + 10.0 * s) { vx = box.x + 10.0 * s; vy += 24.0 * s; }
                    if (vy > box.w - 10.0 * s) break;
                    vx += verb(vx, vy, vb);
                }
            }
        }
    }
    dlClipReset();
    dlFinish();
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    g_R = _Resolution.xy;
    g_s = fmS(g_R);
    if (gi == 0u) layout();
    dlEnd(gi);
}
