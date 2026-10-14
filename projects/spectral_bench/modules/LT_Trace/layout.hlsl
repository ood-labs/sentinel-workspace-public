// LT_Trace / layout.hlsl - the scope canvas's type, frame, legend and inspector, recorded for the
// shared UI kit (ui.hlsl rasterizes it and places scope.hlsl's image over the bench).
//
// Every rect comes from tvLayout() - the function the art draws with - so the frame, the legend
// and the segment the pointer picks sit on the same pixels as the lines. Every number is read this
// cook from the paths header and the paths themselves. Hover is read from the pointer snapshot and
// never stored; this node writes nothing but its draw list.
//
// One group of 64 threads. They scan the drawn lanes together - how many are trapped, and which
// segment is nearest the pointer - then thread 0 records the frame. The multi-part lines are built
// as DATA (`Item`, rows from one template table) and recorded by one loop through one emit(),
// because FXC inlines every call and its compile time grows with one inlined body.
#include "../_shared/bench.hlsli"
#include "../_shared/optics.hlsli"
StructuredBuffer<BenchRec> Bench : register(t0);
StructuredBuffer<PathSeg>  Paths : register(t1);
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"
#include "trace_view.hlsli"

static TvLayout g_L;
static float    g_s;
static float2   g_res;
static PathSeg  g_H;
static uint     g_nLane;
static uint     g_stride;
static uint     g_trapped;
static float    g_titleEnd;
static bool     g_compact;     // header readouts without SOURCES (a narrow canvas)
static float    g_capEnd;      // where the plate caption ends: the quality line yields to it
static uint     g_hot;         // the hovered segment's slot, or NO_SLOT
static bool     g_tip;         // the card is drawn: a hovered segment and Tooltips on
static float4   g_cardRect;

#define NO_SLOT 0xFFFFFFFFu

// ---------------------------------------------------------------- runs of type, as data
// An Item is two scalars - a packed code and a value; size and colour come from a style.
//   code: kind 2b | style 4b << 2 | gap (px at scale 1) 6b << 6 | decimals 3b << 12 | min digits 2b << 15 | label id << 17
#define IT_NONE  0u
#define IT_LABEL 1u
#define IT_NUM   2u
#define ST_CAP_DIM     0u     // bold captions (IL_T_TITLE)
#define ST_CAP_INK     1u
#define ST_CAP_ALARM   2u
#define ST_SMALL_DIM   3u     // small sans: units, captions in a card (IL_T_CAP)
#define ST_BODY_INK    4u     // names and phrases (IL_T_BODY)
#define ST_BODY_ACCENT 5u
#define ST_BODY_ALARM  6u
#define ST_VAL_INK     7u     // numbers (IL_T_VALUE)
#define ST_VAL_ALARM   8u
struct Item { uint code; float v; };

// every multi-part line, and the most items one holds
#define LN_READOUTS 0u
#define LN_QUALITY  1u
#define LN_CARD0    2u        // the inspector's rows, LN_CARD0 .. LN_CARD0 + 5
#define LN_ROWS     6u
#define LN_COUNT    8u
#define LN_ITEMS    9u

Item itNone() { Item it; it.code = IT_NONE; it.v = 0.0; return it; }
Item itLabel(uint id, uint style, uint gap)
{
    Item it; it.code = IT_LABEL | (style << 2) | (gap << 6) | (id << 17); it.v = 0.0;
    return it;
}
Item itNum(float v, uint dec, uint minInt, uint style, uint gap)
{
    Item it; it.code = IT_NUM | (style << 2) | (gap << 6) | (dec << 12) | (minInt << 15); it.v = v;
    return it;
}
float styleSize(uint st)
{
    return (st <= 2u) ? IL_T_TITLE : ((st == 3u) ? IL_T_CAP : ((st <= 6u) ? IL_T_BODY : IL_T_VALUE));
}
float3 styleCol(uint st)
{
    bool alarm = st == ST_CAP_ALARM || st == ST_BODY_ALARM || st == ST_VAL_ALARM;
    bool ink = st == ST_CAP_INK || st == ST_BODY_INK || st == ST_VAL_INK;
    return (st == ST_BODY_ACCENT) ? IL_ACCENT : (alarm ? IL_ALARM : (ink ? IL_INK : IL_DIM));
}
// Width plus the gap after it.
float itemAdvance(Item it)
{
    uint kind = it.code & 3u;
    float size = styleSize((it.code >> 2) & 15u) * g_s;
    float lw = ilLabelW(it.code >> 17, size);
    float nw = ilNumW(ilFormat(it.v, (int)((it.code >> 12) & 7u), (int)((it.code >> 15) & 3u), false).n, size);
    return (kind == IT_NONE) ? 0.0 : ((kind == IT_LABEL) ? lw : nw) + (float)((it.code >> 6) & 63u) * g_s;
}
// Record one item with its capitals sitting on the baseline yb; returns its advance. A label that
// would run past xMax is dropped, never squeezed into its neighbour.
float emit(Item it, float x, float yb, float xMax)
{
    uint kind = it.code & 3u, st = (it.code >> 2) & 15u, id = it.code >> 17;
    float size = styleSize(st) * g_s;
    float3 col = styleCol(st);
    float y = yb - 0.5 * ilCapH(size);
    float w = 0.0;
    if (kind == IT_LABEL)
    {
        w = ilLabelW(id, size);
        if (x + w <= xMax) dlLabel(id, x, y, size, col, IL_LEFT);
    }
    else if (kind == IT_NUM) w = dlNumEx(it.v, (int)((it.code >> 12) & 7u), (int)((it.code >> 15) & 3u), false, x, y, size, col, IL_LEFT);
    return (kind == IT_NONE) ? 0.0 : w + (float)((it.code >> 6) & 63u) * g_s;
}

// ---------------------------------------------------------------- the header's readouts
// The broken state first (only when there is one), then what is traced and how much of it the
// scope draws: LANES is every (ray, wavelength, path), DRAWN the decimated share on screen.
Item readoutItem(uint i)
{
    bool al = g_trapped > 0u, src = !g_compact;
    Item it = itNone();
    if (i == 0u && al) it = itLabel(LB_TRAPPED, ST_CAP_ALARM, 6u);
    else if (i == 1u && al) it = itNum((float)g_trapped, 0u, 1u, ST_VAL_ALARM, 18u);
    else if (i == 2u && src) it = itLabel(LB_SOURCES, ST_CAP_DIM, 6u);
    else if (i == 3u && src) it = itNum(g_H.lane, 0u, 1u, ST_VAL_INK, 18u);
    else if (i == 4u) it = itLabel(LB_LANES, ST_CAP_DIM, 6u);
    else if (i == 5u) it = itNum((float)g_nLane, 0u, 1u, ST_VAL_INK, 18u);
    else if (i == 6u) it = itLabel(LB_DRAWN, ST_CAP_DIM, 6u);
    else if (i == 7u) it = itNum((float)tvDrawn(g_nLane), 0u, 1u, ST_VAL_INK, 0u);
    return it;
}

// ---------------------------------------------------------------- what the quality rung buys
// The four factors of LANES, as the trace actually ran them (the header, not the parameters:
// rays per source give way when many sources share the ray budget).
Item qualityItem(uint i)
{
    float v = (i == 0u) ? g_H.evt : ((i == 2u) ? g_H.b.y : ((i == 4u) ? g_H.wl : (float)g_stride));
    uint word = (i == 1u) ? LB_Q_RAYS : ((i == 3u) ? LB_Q_WAVES : ((i == 5u) ? LB_Q_PATHS : LB_Q_BOUNCES));
    Item it = itNone();
    if (i < 8u && (i & 1u) == 0u) it = itNum(v, 0u, 1u, ST_VAL_INK, 4u);
    else if (i < 8u) it = itLabel(word, ST_SMALL_DIM, (i == 7u) ? 0u : 14u);
    return it;
}

// ---------------------------------------------------------------- the inspector's rows
// A hovered segment's card: its lane's identity, then what happened where it ends. Each row is a
// template from one immediate table plus up to three numbers and one name, chosen by rowSpec().
// TL a fixed label, TD the row's name, TN one of its numbers (the slot sits where a label keeps
// its id).
#define TD_BASE 0x7FF0u
#define TL(id, st, gap)            (IT_LABEL | ((st) << 2) | ((gap) << 6) | ((id) << 17))
#define TD(st, gap)                TL(TD_BASE, st, gap)
#define TN(slot, dec, mn, st, gap) (IT_NUM | ((st) << 2) | ((gap) << 6) | ((dec) << 12) | ((mn) << 15) | ((slot) << 17))
#define SD ST_SMALL_DIM
#define VI ST_VAL_INK
#define TV_NONE         0u
#define TV_MAIN         1u
#define TV_ONE          2u
#define TV_TWO          3u
#define TV_FROM         4u
#define TV_WAVE         5u
#define TV_EVENT        6u
#define TV_EVENT_EXIT   7u
#define TV_EVENT_ALARM  8u
#define TV_CARRY        9u
#define TV_AIR         10u
#define TV_AIR_AT      11u
#define TV_GLASS       12u
#define TV_GLASS_AT    13u
#define TV_COUNT       14u

static const uint CARD_TPL[TV_COUNT * LN_ITEMS] =
{
    0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u,
    // which of the lane's paths: the branch and what it means
    TL(LB_B_MAIN, ST_CAP_INK, 6u), TL(LB_BM_MAIN, SD, 0u), 0u, 0u, 0u, 0u, 0u, 0u, 0u,
    TL(LB_B_ONE, ST_CAP_INK, 6u), TL(LB_BM_ONE, SD, 0u), 0u, 0u, 0u, 0u, 0u, 0u, 0u,
    TL(LB_B_TWO, ST_CAP_INK, 6u), TL(LB_BM_TWO, SD, 0u), 0u, 0u, 0u, 0u, 0u, 0u, 0u,
    // whose ray: the source's slot (as the bench plan numbers it), and which ray of its aperture
    TL(LB_C_SOURCE, SD, 4u), TN(0u, 0u, 2u, VI, 14u), TL(LB_C_RAY, SD, 4u), TN(1u, 0u, 1u, VI, 3u), TL(LB_C_OF, SD, 3u), TN(2u, 0u, 1u, VI, 0u), 0u, 0u, 0u,
    // its wavelength, at which interaction
    TN(0u, 0u, 1u, VI, 3u), TL(LB_NM, SD, 14u), TL(LB_C_STEP, SD, 4u), TN(1u, 0u, 1u, VI, 0u), 0u, 0u, 0u, 0u, 0u,
    // what happened where the segment ends: exits in the accent (that is where it disperses),
    // a trapped beam in the alarm - the colours the scope and the bench's ladder use
    TD(ST_BODY_INK, 0u), 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u,
    TD(ST_BODY_ACCENT, 0u), 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u,
    TD(ST_BODY_ALARM, 0u), 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u,
    // the power it carries, and how far it has turned from where it was emitted
    TL(LB_C_POWER, SD, 4u), TN(0u, 0u, 1u, VI, 3u), TL(LB_PCT, SD, 12u), TL(LB_C_DEVIATION, SD, 4u), TN(1u, 1u, 1u, VI, 3u), TL(LB_DEG, SD, 0u), 0u, 0u, 0u,
    // what it travelled through, and what it reached
    TL(LB_C_AIR, SD, 12u), 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u,
    TL(LB_C_AIR, SD, 12u), 0u, TL(LB_C_AT, SD, 4u), TD(ST_CAP_INK, 5u), TN(1u, 0u, 2u, SD, 0u), 0u, 0u, 0u, 0u,
    TL(LB_C_GLASS, SD, 4u), TN(0u, 3u, 1u, VI, 12u), 0u, 0u, 0u, 0u, 0u, 0u, 0u,
    TL(LB_C_GLASS, SD, 4u), TN(0u, 3u, 1u, VI, 12u), TL(LB_C_AT, SD, 4u), TD(ST_CAP_INK, 5u), TN(1u, 0u, 2u, SD, 0u), 0u, 0u, 0u, 0u,
};

// the current row: its template, numbers and name
static uint   g_tv;
static float3 g_tvV;
static uint   g_tvD;

// The hovered lane's identity, decoded exactly as trace.hlsl encodes a lane:
// lane = ((ray * waves) + wave) * paths + branch, ray = source ordinal * raysPer + sub-ray.
void rowSpec(uint row)
{
    PathSeg g = Paths[min(g_hot, (uint)LT_PATH_TOTAL - 1u)];
    uint lane = g_hot / g_stride;
    uint nBranch = (uint)clamp(g_H.wl, 1.0, (float)LT_BRANCH);
    uint nWave = (uint)clamp(g_H.b.y, 1.0, (float)LT_MAX_WAVE);
    uint raysPer = (uint)clamp(g_H.evt, 1.0, (float)LT_MAX_RAY);
    uint br = lane % nBranch;
    uint ry = lane / (nBranch * nWave);
    uint tv = TV_NONE;
    float3 v = float3(0.0, 0.0, 0.0);
    uint d = 0u;
    if (row == 0u) tv = TV_MAIN + min(br, 2u);
    else if (row == 1u)
    {
        // the emitter ordinal mapped onto its record, as the trace does: live slots are not
        // contiguous once records have been deleted or switched off
        uint emIdx = ry / raysPer, seen = 0u, slot = 0u;
        [loop] for (uint fi = 0u; fi < (uint)LT_MAX_EMIT; ++fi)
        {
            BenchRec E = Bench[LT_EMIT_BASE + fi];
            if (E.role == ROLE_EMITTER && E.active > 0.5 && !LtFlagF(E.flags, F_OFF))
            {
                if (seen == emIdx) { slot = fi; break; }
                seen++;
            }
        }
        tv = TV_FROM;
        v = float3((float)slot, (float)(ry % raysPer + 1u), (float)raysPer);
    }
    else if (row == 2u)
    {
        tv = TV_WAVE;
        v = float3(round(g.wl), g.depth, 0.0);
    }
    else if (row == 3u)
    {
        int ev = (int)clamp(g.evtEnd, 0.0, (float)(EV_COUNT - 1));
        tv = (ev == EV_TIR || ev == EV_EXHAUST) ? TV_EVENT_ALARM : ((ev == EV_EXIT) ? TV_EVENT_EXIT : TV_EVENT);
        d = LB_W_EMIT + (uint)ev;
    }
    else if (row == 4u)
    {
        tv = TV_CARRY;
        v = float3(round(saturate(g.power) * 100.0), degrees(g.dev), 0.0);
    }
    else if (row == 5u)
    {
        int e = (int)g.elem;
        bool glass = g.ior > 1.001, at = e >= LT_ELEM_BASE && e < LT_TOTAL;
        tv = glass ? (at ? TV_GLASS_AT : TV_GLASS) : (at ? TV_AIR_AT : TV_AIR);
        d = LB_K_PRISM + (uint)clamp(Bench[(uint)clamp(e, 0, LT_TOTAL - 1)].kind, 0.0, (float)(EK_COUNT - 1));
        v = float3(g.ior, (float)(e - LT_ELEM_BASE), 0.0);
    }
    g_tv = tv; g_tvV = v; g_tvD = d;
}

// Item i of the current row: the template's, with its name or number filled in.
Item rowItem(uint i)
{
    uint c = CARD_TPL[g_tv * LN_ITEMS + i];
    uint f = c >> 17;
    Item it;
    it.v = (f == 0u) ? g_tvV.x : ((f == 1u) ? g_tvV.y : g_tvV.z);
    if ((c & 3u) == IT_NUM) c &= 0x1FFFFu;
    else
    {
        it.v = 0.0;
        if (f == TD_BASE) c = (c & 0x1FFFFu) | (g_tvD << 17);
    }
    it.code = c;
    return it;
}

// ---------------------------------------------------------------- every multi-part line
Item lineItem(uint ln, uint i)
{
    Item it = itNone();
    if (ln == LN_READOUTS) it = readoutItem(i);
    else if (ln == LN_QUALITY) it = qualityItem(i);
    else it = rowItem(i);
    return it;
}

struct LineGeom { bool show; float x; float yb; float xMax; };

// Where line `ln`, `w` wide, goes - or that it does not show this cook.
LineGeom lineGeom(uint ln, float w)
{
    float s = g_s;
    LineGeom gm;
    gm.show = true; gm.x = 0.0; gm.yb = 0.0; gm.xMax = g_res.x;
    if (ln == LN_READOUTS)
    {
        // right-aligned, on the title's baseline
        gm.x = g_L.head.z - 4.0 * s - w;
        gm.yb = g_L.head.y + 10.0 * s + 0.5 * ilCapH(14.0 * s);
    }
    else if (ln == LN_QUALITY)
    {
        // right-aligned in the plate's caption row, only where it clears the caption
        gm.x = g_L.plate.z - 10.0 * s - w;
        gm.yb = g_L.plate.y + 12.0 * s + 0.5 * ilCapH(IL_T_TITLE * s);
        gm.show = g_nLane > 0u && gm.x > g_capEnd + 16.0 * s;
    }
    else
    {
        uint row = ln - LN_CARD0;
        gm.show = g_tip;
        gm.x = g_cardRect.x + 10.0 * s;
        gm.yb = g_cardRect.y + 14.0 * s + ((row > 0u) ? 2.0 * s + (float)row * 17.0 * s : 0.0) + 0.5 * ilCapH(IL_T_VALUE * s);
        gm.xMax = g_cardRect.z - 10.0 * s;
    }
    return gm;
}

// The card: IL_RAISE, IL_EDGE, beside the point it describes and flipped away from the canvas edges.
float4 cardFrame(float2 at, float2 size)
{
    float s = g_s;
    float2 o = float2(16.0 * s, 14.0 * s);
    float2 p = at + o;
    if (p.x + size.x > g_res.x - 6.0 * s) p.x = at.x - o.x - size.x;
    if (p.y + size.y > g_res.y - 6.0 * s) p.y = at.y - o.y - size.y;
    p = clamp(p, 6.0 * s, max(g_res - size - 6.0 * s, 6.0 * s));
    float4 r = float4(p, p + size);
    dlRectEdged(r, IL_RAISE, 1.0, IL_RADIUS * s, IL_EDGE, 1.0);
    return r;
}

void lines(float2 ptr)
{
    float s = g_s;
    Item items[LN_ITEMS];          // one line's items, built once, then measured and recorded
    [loop] for (uint ln = 0u; ln < LN_COUNT; ln++)
    {
        // the card goes down after every other piece of type, so nothing draws over it
        if (ln == LN_CARD0 && g_tip)
            g_cardRect = cardFrame(ptr, float2(226.0 * s, 30.0 * s + (float)(LN_ROWS - 1u) * 17.0 * s));
        if (ln >= LN_CARD0) rowSpec(g_tip ? ln - LN_CARD0 : 99u);
        float w = 0.0;
        [loop] for (uint i = 0u; i < LN_ITEMS; i++) { items[i] = lineItem(ln, i); w += itemAdvance(items[i]); }
        LineGeom gm = lineGeom(ln, w);
        if (!gm.show) continue;
        float x = gm.x;
        [loop] for (uint j = 0u; j < LN_ITEMS; j++) x += emit(items[j], x, gm.yb, gm.xMax);
    }
}

// ---------------------------------------------------------------- the title, the plate, the legend
void title()
{
    float s = g_s;
    float hy = g_L.head.y + 10.0 * s, x0 = g_L.head.x + 4.0 * s;
    float tw = dlLabel(LB_TITLE, x0, hy, 14.0 * s, IL_INK, IL_LEFT);
    g_titleEnd = x0 + tw + 10.0 * s + dlLabel(LB_SUBTITLE, x0 + tw + 10.0 * s, hy, 12.0 * s, IL_DIM, IL_LEFT);
    // SOURCES gives way first when the readouts would run into the title
    g_compact = false;
    float fw = 0.0;
    [loop] for (uint i = 0u; i < LN_ITEMS; i++) fw += itemAdvance(readoutItem(i));
    g_compact = g_L.head.z - 4.0 * s - fw < g_titleEnd + 16.0 * s;
}

void plate()
{
    float s = g_s;
    float4 pl = g_L.plate, b = g_L.plot;
    dlRectEdged(pl, IL_PANEL, 1.0, IL_RADIUS * s, IL_EDGE, 1.0);
    float cy = pl.y + 12.0 * s;
    g_capEnd = pl.x + 10.0 * s + dlLabel(LB_PATHS, pl.x + 10.0 * s, cy, IL_T_TITLE * s, IL_DIM, IL_LEFT);

    // The traced lines, drawn by scope.hlsl at its own budget into its texture's corner and
    // placed here over the bench - 1:1 on a small canvas, upscaled on a big one.
    dlImage(b, float4(0.0, 0.0, g_L.art.x / g_res.x, g_L.art.y / g_res.y), float3(1.0, 1.0, 1.0), 1.0);
    // the bench's edge, so an escaping ray is legibly leaving something
    dlBorderRect(b, 0.0, IL_RULE, 1.0);
    if (g_nLane == 0u) dlLabel(LB_NONE, ilMid(b).x, ilMid(b).y, IL_T_BODY * s, IL_DIM, IL_CENTER);
}

// How to read the lines: hue is the wavelength, the alarm is a trapped beam, brightness is power.
// Dropped from the end rather than squeezed when the row runs out of room.
void legend()
{
    float s = g_s, small = IL_T_CAP * s;
    float y = g_L.plate.w - 11.0 * s, x = g_L.plate.x + 10.0 * s, xMax = g_L.plate.z - 10.0 * s;
    float h = 3.5 * s;

    // the spectrum, 400 to 700 nm, in the colours the art gives each wavelength
    float rw = 66.0 * s;
    float need = ilNumW(3u, small) * 2.0 + rw + 12.0 * s + ilLabelW(LB_NM, small);
    if (x + need > xMax) return;
    x += dlInt(400, 3, x, y, small, IL_DIM, IL_LEFT) + 5.0 * s;
    // k0 is 0, but not a constant FXC can see: without it the compiler folds the colour maths at
    // fixed wavelengths and warns about double-precision sums it cannot represent
    uint k0 = (uint)min(g_res.x, 0.0);
    [loop] for (uint k = k0; k < 6u; k++)
    {
        float wl0 = 400.0 + 50.0 * (float)k;
        float4 r = float4(x + rw * (float)k / 6.0, y - h, x + rw * (float)(k + 1u) / 6.0, y + h);
        dlHGrad(r, tvSegColour(wl0, EV_ESCAPE), tvSegColour(wl0 + 50.0, EV_ESCAPE), 0.0);
    }
    x += rw + 5.0 * s;
    x += dlInt(700, 3, x, y, small, IL_DIM, IL_LEFT) + 3.0 * s;
    x += dlLabel(LB_NM, x, y, small, IL_DIM, IL_LEFT) + 18.0 * s;

    // the alarm: a beam trapped by total internal reflection or out of interactions
    float aw = 11.0 * s + ilLabelW(LB_ALARM_KEY, small);
    if (x + aw > xMax) return;
    dlRect(float4(x, y - h, x + 7.0 * s, y + h), IL_ALARM, 1.0, 1.0 * s);
    x += 11.0 * s + dlLabel(LB_ALARM_KEY, x + 11.0 * s, y, small, IL_DIM, IL_LEFT) + 18.0 * s;

    // brightness: the power a segment carries
    float pw = 26.0 * s + ilLabelW(LB_POWER_KEY, small);
    if (x + pw > xMax) return;
    dlHGrad(float4(x, y - h, x + 22.0 * s, y + h), IL_WELL, IL_INK, 1.0 * s);
    dlLabel(LB_POWER_KEY, x + 26.0 * s, y, small, IL_DIM, IL_LEFT);
}

// The one gesture this canvas has.
void footer()
{
    float s = g_s;
    float4 ft = g_L.foot;
    float y = ilMid(ft).y, x = ft.x + 4.0 * s;
    float kh = 18.0 * s, cap = IL_T_CAP * s;
    float kw = ilLabelW(LB_KEY_HOVER, cap) + 10.0 * s;
    dlKeycap(float4(x, y - 0.5 * kh, x + kw, y + 0.5 * kh), s, LB_KEY_HOVER);
    dlLabel(LB_DO_HOVER, x + kw + 6.0 * s, y, cap, IL_DIM, IL_LEFT);
}

// ---------------------------------------------------------------- hover
// The hovered segment's whole lane on the bench, lifted over the other lines; the segment itself
// heavier, ringed where it ends - which is where the card's event happened.
void lanePath()
{
    float s = g_s;
    uint lane = g_hot / g_stride, base = lane * g_stride;
    uint live = (uint)clamp(g_H.a.x, 0.0, (float)LT_PATH_TOTAL);
    dlClip(g_L.plot);
    float2 hotEnd = float2(-1e4, -1e4);
    [loop] for (uint j = 0u; j < g_stride; ++j)
    {
        uint slot = base + j;
        if (slot >= live) break;
        PathSeg g = Paths[slot];
        if (!ltSegLive(g)) break;
        float2 a = tvBenchToPix(g_L, g.a), b = tvBenchToPix(g_L, g.b);
        bool hot = slot == g_hot;
        float wgt = (hot ? 2.2 : 1.4) * s;
        // a dark halo keeps it legible where it crosses the other lanes
        dlLine(a, b, wgt + 2.5, IL_FIELD, 0.55);
        dlLine(a, b, wgt, IL_INK, hot ? 1.0 : 0.85);
        if (hot) hotEnd = b;
    }
    if (hotEnd.x > -1e3) dlRing(hotEnd, 4.0 * s, 1.25 * s, IL_INK, 1.0);
    dlClipReset();
}

// ---------------------------------------------------------------- the group's shared scan
groupshared uint  gsTrapped[IL_LAYOUT_THREADS];
groupshared float gsBestD[IL_LAYOUT_THREADS];
groupshared uint  gsBestSlot[IL_LAYOUT_THREADS];

// Every thread, outside any branch: its share of the lanes the scope draws (the same decimation),
// counting the ones carrying a broken event and, while the pointer is over the bench, finding the
// segment nearest it.
void scan(uint gi, TvLayout L, float2 ptr, bool hover)
{
    PathSeg H = Paths[LT_PATH_HDR];
    uint live = (uint)clamp(H.a.x, 0.0, (float)LT_PATH_TOTAL);
    uint stride = (uint)clamp(H.depth, 1.0, (float)LT_MAX_SEG);
    uint nLane = (uint)clamp(H.a.y, 0.0, (float)(LT_MAX_RAY * LT_MAX_WAVE * LT_BRANCH));
    uint step = tvStep(nLane);
    uint trapped = 0u, bestSlot = NO_SLOT;
    float bestD = 9.0 * L.s;              // the reach: nothing farther than this is hovered
    [loop] for (uint li = gi * step; li < nLane; li += IL_LAYOUT_THREADS * step)
    {
        bool broken = false;
        [loop] for (uint sj = 0u; sj < stride; ++sj)
        {
            uint slot = li * stride + sj;
            if (slot >= live) break;
            PathSeg g = Paths[slot];
            if (!ltSegLive(g)) break;
            int ev = (int)g.evtEnd;
            if (ev == EV_TIR || ev == EV_EXHAUST) broken = true;
            float d = hover ? ilSdSeg(ptr, tvBenchToPix(L, g.a), tvBenchToPix(L, g.b)) : 1e9;
            if (d < bestD) { bestD = d; bestSlot = slot; }
        }
        if (broken) trapped++;
    }
    gsTrapped[gi] = trapped;
    gsBestD[gi] = bestD;
    gsBestSlot[gi] = bestSlot;
}

// ---------------------------------------------------------------- thread 0
void layout(float2 ptr)
{
    dlBegin(g_res);
    g_H = Paths[LT_PATH_HDR];
    g_nLane = (uint)clamp(g_H.a.y, 0.0, (float)(LT_MAX_RAY * LT_MAX_WAVE * LT_BRANCH));
    g_stride = (uint)clamp(g_H.depth, 1.0, (float)LT_MAX_SEG);

    // the scan's results: the trapped lanes, and the nearest segment in reach
    g_trapped = 0u; g_hot = NO_SLOT;
    float bd = 1e9;
    [loop] for (uint t = 0u; t < IL_LAYOUT_THREADS; t++)
    {
        g_trapped += gsTrapped[t];
        if (gsBestSlot[t] != NO_SLOT && gsBestD[t] < bd) { bd = gsBestD[t]; g_hot = gsBestSlot[t]; }
    }

    title();
    plate();
    legend();
    footer();
    if (g_hot != NO_SLOT) lanePath();
    g_tip = tooltips != 0 && g_hot != NO_SLOT;   // Tooltips off: the lane still lifts, the card goes
    lines(ptr);                  // readouts, the quality line, and last the card
    dlFinish();
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    g_res = _Resolution.xy;
    g_L = tvLayout(g_res);
    g_s = g_L.s;
    // the pointer, only over the bench (outside the canvas it is ignored)
    float2 n = _ViewportPointerPosition;
    float2 ptr = n * g_res;
    bool hover = all(n >= 0.0) && all(n <= 1.0) && tvIn(g_L.plot, ptr);
    scan(gi, g_L, ptr, hover);
    GroupMemoryBarrierWithGroupSync();
    if (gi == 0u) layout(ptr);
    dlEnd(gi);
}
