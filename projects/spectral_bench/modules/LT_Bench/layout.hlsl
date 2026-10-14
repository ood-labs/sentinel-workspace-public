// LT_Bench / layout.hlsl - the plan canvas's type, chrome and inspector, recorded for the shared UI
// kit (ui.hlsl draws it over canvas.hlsl's drawing).
//
// Every rect comes from ltLayout() - the function canvas.hlsl draws with and plan.hlsl picks with -
// so a caption, a hover outline and a click land on the same pixels. Every number is read this cook
// from the records (Bench) or from the rail's chief block (Chief, through rail.hlsli: the same
// computation the drawing uses, so the header's SPREAD and the curve cannot disagree). Hover is read
// from the pointer snapshot and never stored; the plan's edits stay entirely in plan.hlsl.
//
// FXC inlines every call and its compile time grows superlinearly with one inlined body, so the
// multi-part lines (the header's readouts, the selection line, the inspector's rows) are built as
// DATA - runs of type, `Item` - and recorded by one loop through one emit().
#include "../_shared/bench.hlsli"
#include "../_shared/optics.hlsli"
#include "layout.hlsli"
StructuredBuffer<BenchRec> Bench : register(t0);
StructuredBuffer<PathSeg>  Chief : register(t1);
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"
#include "rail.hlsli"

static LtLayout  g_L;
static float     g_s;
static float2    g_res;
static BenchRec  g_H;
static RailStats g_st;
static float     g_titleEnd;
static bool      g_compact;     // header readouts without the bench counts (a narrow canvas)
static int       g_sel;         // the selection's record, or -1
static BenchRec  g_selRec;
static bool      g_below;       // the plan plate has room under the bench for a line of type
static float     g_selEnd;      // where the selection line ended: the grid note yields to it

// the inspector: at most one card a cook
#define CARD_NONE   0u
#define CARD_RECORD 1u
#define CARD_RAY    2u
static uint      g_card;
static int       g_cardIdx;
static BenchRec  g_cardRec;
static PathSeg   g_cardSeg;
static float2    g_cardAt;
static uint      g_rows;        // the card's rows as 4-bit codes, first row lowest
static uint      g_nRows;
static float4    g_cardRect;

bool ltRecordValid(int idx) { return idx >= LT_EMIT_BASE && idx < LT_TOTAL; }
float hdgDeg(float hdg) { return (float)((uint)round(degrees(hdg) + 720.0) % 360u); }

// ---------------------------------------------------------------- runs of type, as data
// An Item is two scalars - a packed code and a value - so building one in a branch costs almost
// nothing; size and colour come from a style, decoded once in emit().
//   code: kind 2b | style 4b << 2 | gap (px at scale 1) 6b << 6 | decimals 3b << 12 | min digits 2b << 15 | label id << 17
#define IT_NONE  0u
#define IT_LABEL 1u
#define IT_NUM   2u
#define ST_CAP_DIM     0u     // bold captions (IL_T_TITLE)
#define ST_CAP_INK     1u
#define ST_CAP_ACCENT  2u
#define ST_CAP_ALARM   3u
#define ST_SMALL_DIM   4u     // small sans: units, captions in a card (IL_T_CAP)
#define ST_SMALL_MID   5u
#define ST_BODY_INK    6u     // names (IL_T_BODY)
#define ST_BODY_DIM    7u
#define ST_BODY_ACCENT 8u
#define ST_BODY_ALARM  9u
#define ST_VAL_INK    10u     // numbers (IL_T_VALUE)
#define ST_VAL_ALARM  11u
#define ST_HERO_ACCENT 12u    // the header's reading (16)
#define ST_HERO_DIM   13u
struct Item { uint code; float v; };

// every multi-part line, and the most items one holds
#define LN_READOUTS  0u
#define LN_SELECTION 1u
#define LN_GRID      2u
#define LN_CARD0     3u     // the inspector's rows, LN_CARD0 .. LN_CARD0 + 4
#define LN_COUNT     8u
#define LN_ITEMS     9u

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
    return (st <= 3u) ? IL_T_TITLE : ((st <= 5u) ? IL_T_CAP : ((st <= 9u) ? IL_T_BODY : ((st <= 11u) ? IL_T_VALUE : 16.0)));
}
float3 styleCol(uint st)
{
    bool accent = st == ST_CAP_ACCENT || st == ST_BODY_ACCENT || st == ST_HERO_ACCENT;
    bool alarm = st == ST_CAP_ALARM || st == ST_BODY_ALARM || st == ST_VAL_ALARM;
    bool ink = st == ST_CAP_INK || st == ST_BODY_INK || st == ST_VAL_INK;
    return accent ? IL_ACCENT : (alarm ? IL_ALARM : (ink ? IL_INK : ((st == ST_SMALL_MID) ? IL_MID : IL_DIM)));
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
// Left to right: the broken state (only when there is one), what is on the bench, then SPREAD -
// the reading this instrument exists to produce. SPREAD is the rail source's, so it wears the
// accent that also rings that source's housing in the plan and its number on the rail.
Item readoutItem(uint i)
{
    float alarms = g_H.z;
    bool al = alarms > 0.5, counts = !g_compact;
    Item it = itNone();
    if (i == 0u && al) it = itLabel(LB_ALARM, ST_CAP_ALARM, 6u);
    else if (i == 1u && al) it = itNum(alarms, 0u, 1u, ST_VAL_ALARM, 18u);
    else if (i == 2u && counts) it = itLabel(LB_SOURCES, ST_CAP_DIM, 6u);
    else if (i == 3u && counts) it = itNum(g_H.att, 0u, 1u, ST_VAL_INK, 18u);
    else if (i == 4u && counts) it = itLabel(LB_ELEMENTS, ST_CAP_DIM, 6u);
    else if (i == 5u && counts) it = itNum(g_H.r1, 0u, 1u, ST_VAL_INK, 22u);
    else if (i == 6u) it = itLabel(LB_SPREAD, ST_CAP_DIM, 8u);
    else if (i == 7u) it = itNum(min(degrees(g_st.devMax - g_st.devMin), 99.9), 1u, 1u, g_st.anyLive ? ST_HERO_ACCENT : ST_HERO_DIM, 4u);
    else if (i == 8u) it = itLabel(LB_DEG, ST_SMALL_DIM, 0u);
    return it;
}

// ---------------------------------------------------------------- the selection line
// What is selected, then its size and heading in real units, and for a prism whether its one-shot
// aim is still pending (AIM) or it is holding its angle (SET).
Item selItem(uint i)
{
    BenchRec R = g_selRec;
    bool elem = R.role == ROLE_ELEMENT;
    int k = (int)clamp(R.kind, 0.0, (float)(EK_COUNT - 1));
    bool prism = elem && k == EK_PRISM;
    bool aim = LtFlagF(R.flags, F_AIM);
    Item it = itNone();
    if (i == 0u) it = itLabel(elem ? LB_K_PRISM + (uint)k : LB_K_SOURCE, ST_CAP_ACCENT, 10u);
    else if (i == 1u && elem && ltIsGlass(k)) it = itLabel(LB_G_CROWN + (uint)clamp(R.tone, 0.0, (float)(GM_COUNT - 1)), ST_BODY_DIM, 14u);
    else if (i == 2u) it = itNum(round(ltToMM(elem ? R.p1.x * 2.0 : R.p1.x)), 0u, 1u, ST_VAL_INK, 3u);
    else if (i == 3u) it = itLabel(LB_MM, ST_SMALL_DIM, 14u);
    else if (i == 4u) it = itNum(hdgDeg(R.hdg), 0u, 3u, ST_VAL_INK, 3u);
    else if (i == 5u) it = itLabel(LB_DEG, ST_SMALL_DIM, prism ? 14u : 0u);
    else if (i == 6u && prism) it = itLabel(aim ? LB_S_AIM : LB_S_SET, aim ? ST_CAP_ACCENT : ST_CAP_DIM, 0u);
    return it;
}

// ---------------------------------------------------------------- the inspector's rows
// A card is up to five rows, chosen in inspect(). Each row resolves (rowSpec, once per row) to a
// template - a fixed run of items in one immediate table - plus what varies: up to three numbers
// and two names. Keeping the per-item work a table lookup keeps this pass quick to compile.
#define ROW_TITLE       1u    // a record: what it is and which slot
#define ROW_ELEM_MAT    2u    // what an element is made of (glass and index, reflectance, split)
#define ROW_ELEM_PLACE  3u    // its size and heading
#define ROW_ELEM_LIGHT  4u    // what the light did: off, unlit, TIR, or where the chief ray met it
#define ROW_PRISM_AIM   5u    // a prism's one-shot aim
#define ROW_SRC_LIGHT   6u    // a source's spectrum (and band)
#define ROW_SRC_BEAM    7u    // its beam, profile, and fan or waist
#define ROW_SRC_PLACE   8u    // its aperture and heading
#define ROW_SRC_OFF     9u
#define ROW_RAY_TITLE  10u    // a wavelength at an interaction
#define ROW_RAY_EVENT  11u    // what happened there
#define ROW_RAY_CARRY  12u    // the light left, and how far it has turned
#define ROW_RAY_MEDIUM 13u    // what it travelled through, and what it reached

// Template items: TL a fixed label, TD one of the row's two names, TN one of its three numbers
// (the slot sits where a label keeps its id). A caption, a number and its unit are TL TN TL.
#define TD_BASE 0x7FF0u
#define TL(id, st, gap)            (IT_LABEL | ((st) << 2) | ((gap) << 6) | ((id) << 17))
#define TD(slot, st, gap)          TL(TD_BASE + (slot), st, gap)
#define TN(slot, dec, mn, st, gap) (IT_NUM | ((st) << 2) | ((gap) << 6) | ((dec) << 12) | ((mn) << 15) | ((slot) << 17))
#define SD ST_SMALL_DIM
#define VI ST_VAL_INK
#define TV_NONE           0u
#define TV_TITLE          1u
#define TV_TITLE_SEL      2u
#define TV_MAT_PRISM      3u
#define TV_MAT_LENS       4u
#define TV_MAT_GLASS      5u
#define TV_MAT_MIRROR     6u
#define TV_MAT_SPLIT      7u
#define TV_ELEM_PLACE     8u
#define TV_SRC_PLACE      9u
#define TV_OFF           10u
#define TV_UNLIT         11u
#define TV_TIR           12u
#define TV_LIT           13u
#define TV_AIM           14u
#define TV_SET_MANUAL    15u
#define TV_SET           16u
#define TV_SPECTRUM      17u
#define TV_SPECTRUM_BAND 18u
#define TV_BEAM          19u
#define TV_BEAM_FAN      20u
#define TV_BEAM_CONV     21u
#define TV_RAY_TITLE     22u
#define TV_EVENT         23u
#define TV_EVENT_EXIT    24u
#define TV_EVENT_ALARM   25u
#define TV_RAY_CARRY     26u
#define TV_AIR           27u
#define TV_AIR_AT        28u
#define TV_GLASS         29u
#define TV_GLASS_AT      30u
#define TV_COUNT         31u

static const uint CARD_TPL[TV_COUNT * LN_ITEMS] =
{
    // none
    0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u,
    // title: the kind (the accent when it is the selection) and its slot
    TD(0u, ST_CAP_INK, 6u), TN(0u, 0u, 2u, SD, 0u), 0u, 0u, 0u, 0u, 0u, 0u, 0u,
    TD(0u, ST_CAP_ACCENT, 6u), TN(0u, 0u, 2u, SD, 0u), 0u, 0u, 0u, 0u, 0u, 0u, 0u,
    // glass, its index at the sodium d line, and a prism's apex or a lens's radius
    TD(0u, ST_BODY_INK, 10u), TL(LB_C_N, SD, 4u), TN(0u, 3u, 1u, VI, 12u), TL(LB_C_APEX, SD, 4u), TN(1u, 0u, 1u, VI, 3u), TL(LB_DEG, SD, 0u), 0u, 0u, 0u,
    TD(0u, ST_BODY_INK, 10u), TL(LB_C_N, SD, 4u), TN(0u, 3u, 1u, VI, 12u), TL(LB_C_RADIUS, SD, 4u), TN(1u, 0u, 1u, VI, 3u), TL(LB_MM, SD, 0u), 0u, 0u, 0u,
    TD(0u, ST_BODY_INK, 10u), TL(LB_C_N, SD, 4u), TN(0u, 3u, 1u, VI, 12u), 0u, 0u, 0u, 0u, 0u, 0u,
    // a mirror's reflectance; a splitter's r0 of the power one way, the rest the other
    TL(LB_C_REFLECT, SD, 4u), TN(0u, 0u, 1u, VI, 3u), TL(LB_PCT, SD, 0u), 0u, 0u, 0u, 0u, 0u, 0u,
    TL(LB_C_SPLIT, SD, 4u), TN(0u, 0u, 1u, VI, 3u), TL(LB_SLASH, SD, 3u), TN(1u, 0u, 1u, VI, 3u), TL(LB_PCT, SD, 0u), 0u, 0u, 0u, 0u,
    // size as the selection line reads it (an element across its full extent, a source's
    // aperture), then the heading
    TL(LB_C_SIZE, SD, 4u), TN(0u, 0u, 1u, VI, 3u), TL(LB_MM, SD, 12u), TL(LB_C_HEADING, SD, 4u), TN(1u, 0u, 3u, VI, 3u), TL(LB_DEG, SD, 0u), 0u, 0u, 0u,
    TL(LB_C_APERTURE, SD, 4u), TN(0u, 1u, 1u, VI, 3u), TL(LB_MM, SD, 12u), TL(LB_C_HEADING, SD, 4u), TN(1u, 0u, 3u, VI, 3u), TL(LB_DEG, SD, 0u), 0u, 0u, 0u,
    // what the light did: a state and what it means, or where the chief ray met it
    TL(LB_S_OFF, ST_CAP_DIM, 6u), TL(LB_D_OFF, SD, 0u), 0u, 0u, 0u, 0u, 0u, 0u, 0u,
    TL(LB_S_UNLIT, ST_CAP_ALARM, 6u), TL(LB_D_UNLIT, ST_SMALL_MID, 0u), 0u, 0u, 0u, 0u, 0u, 0u, 0u,
    TL(LB_S_TIR, ST_CAP_ALARM, 6u), TL(LB_D_TIR, ST_SMALL_MID, 0u), 0u, 0u, 0u, 0u, 0u, 0u, 0u,
    TL(LB_C_LIT, SD, 4u), TN(0u, 0u, 1u, VI, 3u), TL(LB_MM, SD, 12u), TL(LB_C_INCIDENCE, SD, 4u), TN(1u, 0u, 1u, VI, 3u), TL(LB_DEG, SD, 0u), 0u, 0u, 0u,
    // a prism's one-shot aim
    TL(LB_S_AIM, ST_CAP_ACCENT, 6u), TL(LB_D_AIM, SD, 0u), 0u, 0u, 0u, 0u, 0u, 0u, 0u,
    TL(LB_S_SET, ST_CAP_DIM, 6u), TL(LB_D_MANUAL, SD, 0u), 0u, 0u, 0u, 0u, 0u, 0u, 0u,
    TL(LB_S_SET, ST_CAP_DIM, 6u), TL(LB_D_SET, SD, 0u), 0u, 0u, 0u, 0u, 0u, 0u, 0u,
    // a source's spectrum, and a narrow band's centre and width
    TD(0u, ST_BODY_INK, 12u), 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u,
    TD(0u, ST_BODY_INK, 12u), TN(0u, 0u, 1u, VI, 3u), TL(LB_NM, SD, 10u), TN(1u, 0u, 1u, VI, 3u), TL(LB_NM, SD, 4u), TL(LB_C_WIDE, SD, 0u), 0u, 0u, 0u,
    // its beam and profile, and a fan's full angle or a converging beam's waist
    TD(0u, ST_BODY_INK, 8u), TD(1u, SD, 12u), 0u, 0u, 0u, 0u, 0u, 0u, 0u,
    TD(0u, ST_BODY_INK, 8u), TD(1u, SD, 12u), TL(LB_C_FAN, SD, 4u), TN(0u, 1u, 1u, VI, 3u), TL(LB_DEG, SD, 0u), 0u, 0u, 0u, 0u,
    TD(0u, ST_BODY_INK, 8u), TD(1u, SD, 12u), TL(LB_C_WAIST, SD, 4u), TN(0u, 0u, 1u, VI, 3u), TL(LB_MM, SD, 0u), 0u, 0u, 0u, 0u,
    // a wavelength at an interaction
    TN(0u, 0u, 1u, VI, 3u), TL(LB_NM, SD, 14u), TL(LB_C_STEP, SD, 4u), TN(1u, 0u, 1u, VI, 0u), 0u, 0u, 0u, 0u, 0u,
    // what happened there, in the colour the ladder gives it
    TD(0u, ST_BODY_INK, 0u), 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u,
    TD(0u, ST_BODY_ACCENT, 0u), 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u,
    TD(0u, ST_BODY_ALARM, 0u), 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u,
    // the power left, and how far the ray has turned
    TL(LB_C_POWER, SD, 4u), TN(0u, 0u, 1u, VI, 3u), TL(LB_PCT, SD, 12u), TL(LB_C_DEVIATION, SD, 4u), TN(1u, 1u, 1u, VI, 3u), TL(LB_DEG, SD, 0u), 0u, 0u, 0u,
    // what it travelled through, and what it reached
    TL(LB_C_AIR, SD, 12u), 0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u,
    TL(LB_C_AIR, SD, 12u), 0u, TL(LB_C_AT, SD, 4u), TD(0u, ST_CAP_INK, 5u), TN(1u, 0u, 2u, SD, 0u), 0u, 0u, 0u, 0u,
    TL(LB_C_GLASS, SD, 4u), TN(0u, 3u, 1u, VI, 12u), 0u, 0u, 0u, 0u, 0u, 0u, 0u,
    TL(LB_C_GLASS, SD, 4u), TN(0u, 3u, 1u, VI, 12u), TL(LB_C_AT, SD, 4u), TD(0u, ST_CAP_INK, 5u), TN(1u, 0u, 2u, SD, 0u), 0u, 0u, 0u, 0u,
};

// the current row: its template, numbers and names
static uint   g_tv;
static float3 g_tvV;
static uint2  g_tvD;

void rowSpec(uint code)
{
    BenchRec R = g_cardRec;
    PathSeg g = g_cardSeg;
    bool elem = g_cardIdx >= LT_ELEM_BASE;
    int k = (int)clamp(R.kind, 0.0, (float)(EK_COUNT - 1));
    uint tv = TV_NONE;
    float3 v = float3(0.0, 0.0, 0.0);
    uint2 d = uint2(0u, 0u);
    if (code == ROW_TITLE)
    {
        tv = (g_cardIdx == g_sel) ? TV_TITLE_SEL : TV_TITLE;
        d.x = elem ? LB_K_PRISM + (uint)k : LB_K_SOURCE;
        v.x = (float)(g_cardIdx - (elem ? LT_ELEM_BASE : LT_EMIT_BASE));
    }
    else if (code == ROW_ELEM_MAT)
    {
        int m = (int)clamp(R.tone, 0.0, (float)(GM_COUNT - 1));
        float pct = round(saturate(R.r0) * 100.0);
        bool glass = ltIsGlass(k);
        tv = glass ? ((k == EK_PRISM) ? TV_MAT_PRISM : ((k == EK_LENS) ? TV_MAT_LENS : TV_MAT_GLASS))
                   : ((k == EK_MIRROR) ? TV_MAT_MIRROR : ((k == EK_SPLITTER) ? TV_MAT_SPLIT : TV_NONE));
        d.x = LB_G_CROWN + (uint)m;
        if (glass) v = float3(ltIOR(m, 589.3), (k == EK_PRISM) ? round(degrees(R.r0)) : round(ltToMM(R.r0)), 0.0);
        else v = float3(pct, 100.0 - pct, 0.0);
    }
    else if (code == ROW_ELEM_PLACE)
    {
        tv = TV_ELEM_PLACE;
        v = float3(round(ltToMM(R.p1.x * 2.0)), hdgDeg(R.hdg), 0.0);
    }
    else if (code == ROW_SRC_PLACE)
    {
        tv = TV_SRC_PLACE;
        v = float3(ltToMM(R.p1.x), hdgDeg(R.hdg), 0.0);
    }
    else if (code == ROW_ELEM_LIGHT)
    {
        bool off = LtFlagF(R.flags, F_OFF), unlit = LtFlagF(R.flags, F_UNLIT), tir = LtFlagF(R.flags, F_ALARM);
        tv = off ? TV_OFF : (unlit ? TV_UNLIT : (tir ? TV_TIR : TV_LIT));
        v = float3(round(ltToMM(max(R.wl0, 0.0))), round(degrees(R.wl1)), 0.0);
    }
    else if (code == ROW_PRISM_AIM)
        tv = LtFlagF(R.flags, F_AIM) ? TV_AIM : (LtFlagF(R.flags, F_MANUAL) ? TV_SET_MANUAL : TV_SET);
    else if (code == ROW_SRC_LIGHT)
    {
        int sp = (int)clamp(R.tone, 0.0, (float)(SP_COUNT - 1));
        tv = (sp == SP_BAND) ? TV_SPECTRUM_BAND : TV_SPECTRUM;
        d.x = LB_SP_WHITE + (uint)sp;
        v = float3(round(R.wl0), round(R.wl1), 0.0);
    }
    else if (code == ROW_SRC_BEAM)
    {
        int bp = (int)clamp(R.kind, 0.0, (float)(BP_COUNT - 1));
        tv = (bp == BP_FAN) ? TV_BEAM_FAN : ((bp == BP_CONVERGE) ? TV_BEAM_CONV : TV_BEAM);
        d = uint2(LB_BP_COLL + (uint)bp, (R.gen > 0.5) ? LB_SH_GAUSS : LB_SH_FLAT);
        v.x = (bp == BP_FAN) ? degrees(2.0 * R.r1) : round(ltToMM(max(R.r1, 1e-3)));
    }
    else if (code == ROW_SRC_OFF) tv = TV_OFF;
    else if (code == ROW_RAY_TITLE)
    {
        tv = TV_RAY_TITLE;
        v = float3(round(g.wl), g.depth, 0.0);
    }
    else if (code == ROW_RAY_EVENT)
    {
        int ev = (int)clamp(g.evtEnd, 0.0, (float)(EV_COUNT - 1));
        tv = (ev == EV_TIR || ev == EV_EXHAUST) ? TV_EVENT_ALARM : ((ev == EV_EXIT) ? TV_EVENT_EXIT : TV_EVENT);
        d.x = LB_W_EMIT + (uint)ev;
    }
    else if (code == ROW_RAY_CARRY)
    {
        tv = TV_RAY_CARRY;
        v = float3(round(saturate(g.power) * 100.0), degrees(g.dev), 0.0);
    }
    else if (code == ROW_RAY_MEDIUM)
    {
        int e = (int)g.elem;
        bool glass = g.ior > 1.001, at = e >= LT_ELEM_BASE && e < LT_TOTAL;
        tv = glass ? (at ? TV_GLASS_AT : TV_GLASS) : (at ? TV_AIR_AT : TV_AIR);
        d.x = LB_K_PRISM + (uint)clamp(Bench[(uint)clamp(e, 0, LT_TOTAL - 1)].kind, 0.0, (float)(EK_COUNT - 1));
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
        if (f >= TD_BASE) c = (c & 0x1FFFFu) | (((f == TD_BASE) ? g_tvD.x : g_tvD.y) << 17);
    }
    it.code = c;
    return it;
}

// ---------------------------------------------------------------- every multi-part line

Item lineItem(uint ln, uint i)
{
    Item it = itNone();
    if (ln == LN_READOUTS) it = readoutItem(i);
    else if (ln == LN_SELECTION) it = selItem(i);
    else if (ln == LN_GRID) { if (i == 0u) it = itLabel(LB_GRID, ST_SMALL_DIM, 0u); }
    else it = rowItem(i);
    return it;
}

struct LineGeom { bool show; float x; float yb; float xMax; bool chip; float4 clip; };

// Where line `ln`, `w` wide, goes - or that it does not show this cook.
LineGeom lineGeom(uint ln, float w)
{
    float s = g_s;
    float4 pb = g_L.planBox, pl = g_L.plan;
    float vb = 0.5 * ilCapH(IL_T_VALUE * s);          // a row's baseline, below its midline
    LineGeom gm;
    gm.show = false; gm.x = 0.0; gm.yb = 0.0; gm.xMax = g_res.x; gm.chip = false;
    gm.clip = float4(0.0, 0.0, g_res);
    if (ln == LN_READOUTS)
    {
        // right-aligned, on the title's baseline
        gm.show = true;
        gm.x = g_L.head.z - 4.0 * s - w;
        gm.yb = g_L.head.y + 10.0 * s + 0.5 * ilCapH(14.0 * s);
    }
    else if (ln == LN_SELECTION)
    {
        // under the bench when the plate has room there, else on a chip in the bench's lower left
        // corner, where the readout has always been
        gm.show = g_sel >= 0;
        gm.x = g_below ? pl.x + 1.0 * s : pl.x + 10.0 * s;
        gm.yb = (g_below ? pl.w + min(pb.w - pl.w, 24.0 * s) * 0.5 : pl.w - 13.0 * s) + vb;
        gm.chip = !g_below;
        gm.clip = pb;
        gm.xMax = pb.z - 10.0 * s;
    }
    else if (ln == LN_GRID)
    {
        // the graticule's pitch, bottom right: under the bench, or in the side margin
        float side = pl.x - pb.x;
        gm.x = pb.z - 10.0 * s - w;
        gm.show = g_below ? (gm.x > g_selEnd + 16.0 * s) : (side >= w + 20.0 * s);
        gm.yb = (g_below ? pl.w + min(pb.w - pl.w, 24.0 * s) * 0.5 : pb.w - 14.0 * s) + 0.5 * ilCapH(IL_T_CAP * s);
    }
    else
    {
        uint row = ln - LN_CARD0;
        gm.show = g_card != CARD_NONE && row < g_nRows;
        gm.x = g_cardRect.x + 10.0 * s;
        gm.yb = g_cardRect.y + 14.0 * s + ((row > 0u) ? 2.0 * s + (float)row * 17.0 * s : 0.0) + vb;
        gm.xMax = g_cardRect.z - 10.0 * s;
    }
    return gm;
}

// Type that must sit over the drawing gets a chip under it.
void chip(float4 r) { dlRectEdged(r, IL_PANEL, 0.9, IL_RADIUS * g_s, IL_EDGE, 1.0); }

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

void lines()
{
    float s = g_s;
    Item items[LN_ITEMS];          // one line's items, built once, then measured and recorded
    [loop] for (uint ln = 0u; ln < LN_COUNT; ln++)
    {
        if (ln == LN_CARD0 && g_card != CARD_NONE)
        {
            // the card goes down after every other piece of type, so nothing draws over it
            g_cardRect = cardFrame(g_cardAt, float2(226.0 * s, 30.0 * s + (float)(g_nRows - 1u) * 17.0 * s));
            // the title's right-hand tag: the rail's own source, or a record placed by hand
            bool rail = g_card == CARD_RECORD && g_cardIdx < LT_ELEM_BASE && g_cardIdx - LT_EMIT_BASE == (int)clamp(g_H.dev, 0.0, (float)(LT_MAX_EMIT - 1));
            bool hand = g_card == CARD_RECORD && LtOwnedF(g_cardRec.flags);
            if (rail || hand)
                dlLabel(rail ? LB_S_RAIL : LB_C_HAND, g_cardRect.z - 10.0 * s, g_cardRect.y + 14.0 * s, rail ? IL_T_TITLE * s : IL_T_CAP * s, rail ? IL_ACCENT : IL_DIM, IL_RIGHT);
        }
        if (ln >= LN_CARD0) rowSpec((ln - LN_CARD0 < g_nRows) ? ((g_rows >> (4u * (ln - LN_CARD0))) & 15u) : 0u);
        float w = 0.0;
        [loop] for (uint i = 0u; i < LN_ITEMS; i++) { items[i] = lineItem(ln, i); w += itemAdvance(items[i]); }
        LineGeom gm = lineGeom(ln, w);
        if (!gm.show) continue;
        dlClip(gm.clip);
        if (gm.chip)
        {
            float hh = 9.0 * s, mid = gm.yb - 0.5 * ilCapH(IL_T_VALUE * s);
            chip(float4(gm.x - 6.0 * s, mid - hh, gm.x + w + 6.0 * s, mid + hh));
        }
        float x = gm.x;
        [loop] for (uint j = 0u; j < LN_ITEMS; j++) x += emit(items[j], x, gm.yb, gm.xMax);
        dlClipReset();
        if (ln == LN_SELECTION) g_selEnd = x;
    }
}

// ---------------------------------------------------------------- the header's title
void title()
{
    float s = g_s;
    float hy = g_L.head.y + 10.0 * s, x0 = g_L.head.x + 4.0 * s;
    float tw = dlLabel(LB_TITLE, x0, hy, 14.0 * s, IL_INK, IL_LEFT);
    g_titleEnd = x0 + tw + 10.0 * s + dlLabel(LB_SUBTITLE, x0 + tw + 10.0 * s, hy, 12.0 * s, IL_DIM, IL_LEFT);
    // the bench counts give way first when the readouts would run into the title
    g_compact = false;
    float fw = 0.0;
    [loop] for (uint i = 0u; i < LN_ITEMS; i++) fw += itemAdvance(readoutItem(i));
    g_compact = g_L.head.z - 4.0 * s - fw < g_titleEnd + 16.0 * s;
}

// ---------------------------------------------------------------- the plan plate
void planChrome()
{
    float s = g_s;
    float4 pb = g_L.planBox, pl = g_L.plan;
    float cap = IL_T_TITLE * s, small = IL_T_CAP * s;
    dlBorderRect(pb, IL_RADIUS * s, IL_EDGE, 1.0);
    // The bench itself: a draughtsman's frame with hard corners. It is also exactly the region
    // plan.hlsl picks in - nothing outside it can be seen or selected.
    dlBorderRect(pl, 0.0, IL_RULE, 1.0);

    // Bench space is fitted, never stretched, so the plate has spare room either above and below
    // the bench or beside it. The plate's words go in that room when there is enough of it.
    float topRoom = pl.y - pb.y, side = pl.x - pb.x;
    float capW = ilLabelW(LB_PLAN, cap);
    bool above = topRoom >= 20.0 * s;
    float2 cp = float2(pb.x + 10.0 * s, above ? pb.y + min(topRoom, 28.0 * s) * 0.5 : pb.y + 14.0 * s);
    if (!above && side < capW + 20.0 * s)
    {
        cp = float2(pl.x + 9.0 * s, pl.y + 12.0 * s);
        chip(float4(cp.x - 5.0 * s, cp.y - 8.0 * s, cp.x + capW + 5.0 * s, cp.y + 8.0 * s));
    }
    dlLabel(LB_PLAN, cp.x, cp.y, cap, IL_DIM, IL_LEFT);

    // which fans the plan is drawing (Plan Fans), top right, only where it has room of its own
    uint fans = (plan_fans < 0.5) ? LB_FANS_RAIL : LB_FANS_ALL;
    float fw = ilLabelW(fans, small);
    bool fanRoom = above ? (cp.x + capW + 24.0 * s < pb.z - 10.0 * s - fw) : (side >= fw + 20.0 * s);
    if (fanRoom) dlLabel(fans, pb.z - 10.0 * s, cp.y, small, IL_DIM, IL_RIGHT);

    // an empty bench says how to start one
    if (g_H.seed < 0.5) dlLabel(LB_EMPTY, ilMid(pl).x, ilMid(pl).y, IL_T_BODY * s, IL_DIM, IL_CENTER);
}

// Each prism's apex angle, inside the angle where a draughtsman puts it (canvas.hlsl draws the arc
// from the same vertices), far enough along the bisector to clear the arc. Clipped to the bench.
void apexLabels()
{
    float s = g_s, size = IL_T_CAP * s;
    dlClip(g_L.plan);
    [loop] for (uint ei = 0u; ei < (uint)LT_MAX_ELEM; ++ei)
    {
        BenchRec R = Bench[LT_ELEM_BASE + ei];
        if (R.role != ROLE_ELEMENT || R.active < 0.5 || (int)R.kind != EK_PRISM) continue;
        float2 va, vb, vc;
        ltPrismVerts(R.p0, R.hdg, max(R.p1.x, 1e-4), R.r0, va, vb, vc);
        float2 A = ltBenchToPix(g_L, va), B = ltBenchToPix(g_L, vb), C = ltBenchToPix(g_L, vc);
        float2 mid = (B + C) * 0.5;
        float h = length(mid - A);
        float2 toM = (mid - A) / max(h, 1e-3);
        float ar = h * 0.30;
        float v = round(degrees(R.r0));
        float nw = ilNumW(ilFormat(v, 0, 1, false).n, size);
        float tw = nw + 2.0 * s + ilLabelW(LB_DEG, size);
        float halfH = 0.5 * ilCapH(size);
        // the unit only when the whole call-out still lands inside the prism
        bool unit = ar + 4.0 * s + abs(toM.x) * tw + abs(toM.y) * 2.0 * halfH < h * 0.85;
        if (!unit) tw = nw;
        float2 at = A + toM * (ar + 4.0 * s + abs(toM.x) * 0.5 * tw + abs(toM.y) * halfH);
        float x = at.x - 0.5 * tw;
        dlNum(v, 0, x, at.y, size, IL_DIM, IL_LEFT);
        if (unit) dlLabel(LB_DEG, x + nw + 2.0 * s, at.y, size, IL_DIM, IL_LEFT);
    }
    dlClipReset();
}

// ---------------------------------------------------------------- the rail plate
// Event code for legend slot i: the accent and alarm events first, then the greys by value.
uint legendEvent(uint i)
{
    return (i == 0u) ? EV_EXIT : (i == 1u) ? EV_TIR : (i == 2u) ? EV_EXHAUST : (i == 3u) ? EV_SCREEN
         : (i == 4u) ? EV_MIRROR : (i == 5u) ? EV_ENTER : (i == 6u) ? EV_FRESNEL : (i == 7u) ? EV_EMIT
         : (i == 8u) ? EV_ESCAPE : EV_ABSORB;
}

// The ladder's colours for the events actually in it, then what the bar inside a cell means.
// Dropped from the end rather than squeezed when the caption row runs out of room.
void legend(uint events, float x, float xMax, float y)
{
    float s = g_s, small = IL_T_CAP * s;
    bool room = true;
    [loop] for (uint i = 0u; i < 11u; i++)
    {
        uint ev = legendEvent(min(i, 9u));
        bool bar = i == 10u;                           // the last slot: the power bar
        bool present = bar || (events & (1u << ev)) != 0u;
        uint id = bar ? LB_POWER : LB_E_EMIT + ev;
        float w = 11.0 * s + ilLabelW(id, small);
        room = room && (!present || x + w <= xMax);
        if (!present || !room) continue;
        if (bar) dlRect(float4(x + 2.5 * s, y - 4.5 * s, x + 4.5 * s, y + 4.5 * s), PT_INK, 0.55, 0.0);
        else dlRect(float4(x, y - 3.5 * s, x + 7.0 * s, y + 3.5 * s), eventColour((int)ev, 1.0), 1.0, 1.0 * s);
        x += 11.0 * s + dlLabel(id, x + 11.0 * s, y, small, IL_DIM, IL_LEFT) + 10.0 * s;
    }
}

void railChrome(int railEm)
{
    float s = g_s;
    float4 rb = g_L.railBox, ld = g_L.ladder, dp = g_L.devplot;
    float cap = IL_T_TITLE * s, small = IL_T_CAP * s;
    dlBorderRect(rb, IL_RADIUS * s, IL_EDGE, 1.0);
    dlBorderRect(ld, 1.5 * s, IL_EDGE, 1.0);
    dlBorderRect(dp, 1.5 * s, IL_EDGE, 1.0);
    float cy = rb.y + 9.0 * s;

    // the lane axis both plots share, red at the top, named by the wavelengths the rail source
    // emits (see ltRailAxis), and its unit above it
    dlLabel(LB_NM, rb.x + 6.0 * s, cy - 1.5 * s, small, IL_DIM, IL_LEFT);
    BenchRec E = Bench[LT_EMIT_BASE + (uint)railEm];
    float4 aw, ar;
    uint na = ltRailAxis((int)clamp(E.tone, 0.0, (float)(SP_COUNT - 1)), E.wl0, E.wl1, aw, ar);
    [loop] for (uint t = 0u; t < na; ++t)
        dlInt((int)round(aw[t]), 3, rb.x + 6.0 * s, ltRailRowY(ld, ar[t]), small, IL_DIM, IL_LEFT);

    // LEFT: the ladder's caption, the source it reads - in the accent that rings that source's
    // housing in the plan, one reading labelled in two places - and the legend between them
    float lx = ld.x + dlLabel(LB_LADDER, ld.x, cy, cap, IL_DIM, IL_LEFT) + 14.0 * s;
    float rx = ld.z - dlInt(railEm, 2, ld.z, cy, IL_T_VALUE * s, IL_ACCENT, IL_RIGHT) - 5.0 * s;
    rx -= dlLabel(LB_SRC, rx, cy, cap, IL_DIM, IL_RIGHT) + 14.0 * s;
    legend(g_st.events, lx, rx, cy);

    // RIGHT: the deviation profile's caption. With no live beam there is nothing to read below.
    dlLabel(LB_DEVIATION, dp.x, cy, cap, IL_DIM, IL_LEFT);
    if (!g_st.anyLive)
    {
        dlLabel(LB_NO_BEAM, ilMid(ld).x, ilMid(ld).y, IL_T_BODY * s, IL_DIM, IL_CENTER);
        return;
    }

    // the ladder's column captions: the interaction index
    float2 cell = ltLadderCell(ld, g_st.maxDepth);
    float by = ld.w + 7.0 * s;
    [loop] for (int c = 0; c < g_st.maxDepth && c < LT_MAX_SEG; ++c)
        dlInt(c, 1, ld.x + ((float)c + 0.5) * cell.x, by, small, IL_DIM, IL_CENTER);

    // the deviation axis, signed, in degrees; and the spread measured across the curve, so the
    // header's number has a visible length
    float lo, hi;
    ltDevRange(g_st, lo, hi);
    float loEnd = dp.x + dlInt((int)round(lo), 1, dp.x, by, small, IL_DIM, IL_LEFT);
    float ux = dp.z - dlLabel(LB_DEG, dp.z, by, small, IL_DIM, IL_RIGHT) - 3.0 * s;
    float hiStart = ux - dlInt((int)round(hi), 1, ux, by, small, IL_DIM, IL_RIGHT);

    float x0 = ltDevToX(dp, degrees(g_st.devMin), lo, hi), x1 = ltDevToX(dp, degrees(g_st.devMax), lo, hi);
    float spreadDeg = degrees(g_st.devMax - g_st.devMin);
    float nw = ilNumW(ilFormat(spreadDeg, 1, 1, false).n, small);
    float tw = nw + 2.0 * s + ilLabelW(LB_DEG, small), xm = 0.5 * (x0 + x1);
    if (x0 > loEnd + 6.0 * s && x1 < hiStart - 6.0 * s && x1 - x0 > tw + 16.0 * s)
    {
        float t0 = xm - 0.5 * tw - 4.0 * s, t1 = xm + 0.5 * tw + 4.0 * s;
        dlLine(float2(x0, by), float2(t0, by), 1.0, IL_DIM, 1.0);
        dlLine(float2(t1, by), float2(x1, by), 1.0, IL_DIM, 1.0);
        dlLine(float2(x0, by - 3.5 * s), float2(x0, by + 3.5 * s), 1.0, IL_DIM, 1.0);
        dlLine(float2(x1, by - 3.5 * s), float2(x1, by + 3.5 * s), 1.0, IL_DIM, 1.0);
        dlNum(spreadDeg, 1, xm - 0.5 * tw, by, small, IL_INK, IL_LEFT);
        dlLabel(LB_DEG, xm - 0.5 * tw + nw + 2.0 * s, by, small, IL_DIM, IL_LEFT);
    }
}

// ---------------------------------------------------------------- the verbs
// Key k of the footer and what it does now: on a selected SOURCE, K and M cycle its spectrum and
// beam rather than a kind and a glass.
#define LT_VERBS 17u
uint verbFor(uint i, bool srcSel)
{
    uint v = LB_DO_A + i;
    if (srcSel && i == 4u) v = LB_DO_KS;
    if (srcSel && i == 5u) v = LB_DO_MS;
    return v;
}

// The manifest's bindings as keycaps. As many as fit with their gaps closed to no less than half,
// spread evenly, the rest dropped from the end (the least needed are last).
void footer()
{
    float s = g_s;
    float4 ft = g_L.foot;
    float y = ilMid(ft).y, x = ft.x + 4.0 * s, room = ft.z - 4.0 * s - x;
    float kh = 18.0 * s, cap = IL_T_CAP * s, pad = 10.0 * s;
    bool srcSel = g_sel >= LT_EMIT_BASE && g_sel < LT_ELEM_BASE;
    uint n = 0u;
    float words = 0.0, fit = 0.0;
    [loop] for (uint i = 0u; i < LT_VERBS; i++)
    {
        words += ilLabelW(LB_KEY_A + i, cap) + pad + ilLabelW(verbFor(i, srcSel), cap);
        float gaps = (float)(i + 1u) * 6.0 * s + (float)i * 16.0 * s;
        if (words + 0.5 * gaps > room) break;
        n = i + 1u; fit = words;
    }
    float gapsN = (float)n * 6.0 * s + (float)max((int)n - 1, 0) * 16.0 * s;
    float k = min(1.0, (room - fit) / max(gapsN, 1e-3));
    [loop] for (uint j = 0u; j < n; j++)
    {
        uint key = LB_KEY_A + j;
        float kw = ilLabelW(key, cap) + pad;
        dlKeycap(float4(x, y - 0.5 * kh, x + kw, y + 0.5 * kh), s, key);
        x += kw + 6.0 * s * k;
        // ADD and SOURCE at full ink: they are the two that turn a generated bench into one you built
        x += dlLabel(verbFor(j, srcSel), x, y, cap, (j < 2u) ? IL_INK : IL_DIM, IL_LEFT) + 16.0 * s * k;
    }
}

// ---------------------------------------------------------------- hover
// plan.hlsl's pick, the same rule in the same space: gated on the bench, smallest hit wins.
int pickAt(float2 px)
{
    int hit = -1;
    if (ltInBox(g_L.plan, px))
    {
        float2 bp = ltPixToBench(g_L, px);
        float best = 1e9;
        [loop] for (uint i = 0u; i < (uint)LT_MAX_EMIT; ++i)
        {
            BenchRec R = Bench[LT_EMIT_BASE + i];
            if (R.active < 0.5) continue;
            float r = 0.030;
            if (length(bp - R.p0) < r && r < best) { best = r; hit = (int)(LT_EMIT_BASE + i); }
        }
        [loop] for (uint j = 0u; j < (uint)LT_MAX_ELEM; ++j)
        {
            BenchRec R = Bench[LT_ELEM_BASE + j];
            if (R.active < 0.5) continue;
            int k = (int)R.kind;
            float d, r;
            if (k == EK_PRISM || k == EK_SLAB || k == EK_LENS)
            {
                r = max(R.p1.x, 0.02) * ((k == EK_PRISM) ? 0.80 : 1.05);
                d = length(bp - R.p0);
            }
            else
            {
                float2 tg = ltPerp(ltDir(R.hdg));
                float2 rel = bp - R.p0;
                float u = clamp(dot(rel, tg), -R.p1.x, R.p1.x);
                d = length(rel - tg * u);
                r = max(R.p1.y, 0.012) + 0.012;
            }
            if (d < r && r < best) { best = r; hit = (int)(LT_ELEM_BASE + j); }
        }
    }
    return hit;
}

// The hovered record's grab footprint - exactly the shape the pick tests, a disc, or the face
// widened into a capsule - lifted one value step. What you see is what a click takes.
void grabOutline(int idx)
{
    float s = g_s;
    BenchRec R = Bench[idx];
    float2 c = ltBenchToPix(g_L, R.p0);
    int k = (int)R.kind;
    bool planar = idx >= LT_ELEM_BASE && !(k == EK_PRISM || k == EK_SLAB || k == EK_LENS);
    dlClip(g_L.plan);
    if (!planar)
    {
        float rb = (idx < LT_ELEM_BASE) ? 0.030 : max(R.p1.x, 0.02) * ((k == EK_PRISM) ? 0.80 : 1.05);
        float r = ltBenchToPixR(g_L, rb);
        dlCircle(c, r, IL_INK, 0.06);
        dlRing(c, r, 1.0, IL_MID, 0.9);
    }
    else
    {
        float2 tg = ltPerp(ltDir(R.hdg));
        float r = ltBenchToPixR(g_L, max(R.p1.y, 0.012) + 0.012);
        float2 e0 = ltBenchToPix(g_L, R.p0 - tg * R.p1.x), e1 = ltBenchToPix(g_L, R.p0 + tg * R.p1.x);
        float2 nn = ltPerp(tg) * r;
        dlLine(e0, e1, 2.0 * r, IL_INK, 0.06);
        dlLine(e0 + nn, e1 + nn, 1.0, IL_MID, 0.9);
        dlLine(e0 - nn, e1 - nn, 1.0, IL_MID, 0.9);
        float a = atan2(tg.x, -tg.y);                  // clockwise from 12 o'clock: the kit's arcs
        dlArc(e1, r, 1.0, a - 0.5 * IL_PI, a + 0.5 * IL_PI, IL_MID, 0.9);
        dlArc(e0, r, 1.0, a + 0.5 * IL_PI, a + 1.5 * IL_PI, IL_MID, 0.9);
    }
    dlClipReset();
}

// One wavelength's whole path on the bench, for a hovered ladder cell or deviation mark: the rail
// says what happened to this colour, the plan shows where. `seg` is the hovered interaction.
void lanePath(uint railBase, uint lane, int seg)
{
    float s = g_s;
    dlClip(g_L.plan);
    float2 hotEnd = float2(-1e4, -1e4);
    [loop] for (uint j = 0u; j < (uint)LT_MAX_SEG; ++j)
    {
        PathSeg g = Chief[railBase + lane * (uint)LT_MAX_SEG + j];
        if (!ltSegLive(g)) break;
        float2 a = ltBenchToPix(g_L, g.a), b = ltBenchToPix(g_L, g.b);
        bool hot = (int)j == seg;
        float wgt = (hot ? 2.2 : 1.4) * s;
        // a dark halo keeps it legible where it crosses the other 31 lanes
        dlLine(a, b, wgt + 2.5, IL_FIELD, 0.55);
        dlLine(a, b, wgt, IL_INK, hot ? 1.0 : 0.85);
        if (hot) hotEnd = b;
    }
    if (hotEnd.x > -1e3) dlRing(hotEnd, 4.0 * s, 1.25 * s, IL_INK, 1.0);
    dlClipReset();
}

// A lane's last live segment (its index) and where its mark sits in the deviation profile.
bool laneEnd(uint railBase, uint lane, out int lastIdx, out float2 mark)
{
    PathSeg last = (PathSeg)0;
    lastIdx = -1;
    [loop] for (uint j = 0u; j < (uint)LT_MAX_SEG; ++j)
    {
        PathSeg g = Chief[railBase + lane * (uint)LT_MAX_SEG + j];
        if (!ltSegLive(g)) break;
        last = g; lastIdx = (int)j;
    }
    float lo, hi;
    ltDevRange(g_st, lo, hi);
    mark = float2(ltDevToX(g_L.devplot, degrees(last.dev), lo, hi), ltRailRowY(g_L.devplot, (float)lane));
    return lastIdx >= 0;
}

// What the pointer is over: highlight it and choose the card. A record being dragged is inspected
// where it is, live, whatever the pointer snapshot says. The pointer outside the canvas is ignored.
void inspect(int drag, uint railBase)
{
    float s = g_s;
    g_card = CARD_NONE; g_rows = 0u; g_nRows = 0u;
    g_cardIdx = -1; g_cardRec = (BenchRec)0; g_cardSeg = (PathSeg)0; g_cardAt = float2(0.0, 0.0);
    int rec = -1, lane = -1, seg = -1;
    float2 at = float2(0.0, 0.0);
    if (ltRecordValid(drag))
    {
        BenchRec D = Bench[drag];
        if (D.active > 0.5) { rec = drag; at = ltBenchToPix(g_L, D.p0); }
    }
    float2 n = _ViewportPointerPosition;
    bool inside = all(n >= 0.0) && all(n <= 1.0);
    float2 ptr = n * g_res;
    float4 ld = g_L.ladder, dp = g_L.devplot;
    float2 cell = ltLadderCell(ld, g_st.maxDepth);
    if (rec < 0 && inside)
    {
        int hov = pickAt(ptr);
        if (hov >= 0)
        {
            rec = hov; at = ptr;
            grabOutline(hov);
        }
        else if (g_st.anyLive && ltInBox(ld, ptr))
        {
            // a ladder cell: one wavelength at one interaction
            int col = (int)clamp(floor((ptr.x - ld.x) / max(cell.x, 1e-3)), 0.0, (float)g_st.maxDepth - 1.0);
            int row = (int)clamp(floor((ld.w - ptr.y) / max(cell.y, 1e-3)), 0.0, (float)CHIEF_LANES - 1.0);
            if (ltSegLive(Chief[railBase + (uint)row * (uint)LT_MAX_SEG + (uint)col]))
            {
                lane = row; seg = col; at = ptr;
                dlBorderRect(float4(ld.x + (float)col * cell.x, ld.w - (float)(row + 1) * cell.y,
                                    ld.x + (float)(col + 1) * cell.x, ld.w - (float)row * cell.y), 1.0 * s, IL_INK, 1.0);
            }
        }
        else if (g_st.anyLive && ltInBox(float4(dp.x - 6.0 * s, dp.y - 6.0 * s, dp.z + 6.0 * s, dp.w + 6.0 * s), ptr))
        {
            // a deviation mark: the nearest lane, mostly by row
            float bd = 12.0 * s;
            float2 bm = float2(0.0, 0.0);
            [loop] for (uint li = 0u; li < (uint)CHIEF_LANES; ++li)
            {
                int ls; float2 m;
                if (!laneEnd(railBase, li, ls, m)) continue;
                float d = length((ptr - m) * float2(0.35, 1.0));
                if (d < bd) { bd = d; lane = (int)li; seg = ls; bm = m; }
            }
            if (lane >= 0)
            {
                at = ptr;
                dlLine(float2(dp.x, bm.y), float2(dp.z, bm.y), 1.0, IL_RULE, 0.8);
                dlBorderRect(float4(ld.x, ld.w - (float)(lane + 1) * cell.y, ld.z, ld.w - (float)lane * cell.y), 1.0 * s, IL_INK, 1.0);
            }
        }
    }

    if (lane >= 0)
    {
        // the lane's final deviation, ringed in the profile, and its path across the bench
        int ls; float2 m;
        if (laneEnd(railBase, (uint)lane, ls, m)) dlRing(m, 4.5 * s, 1.25 * s, IL_INK, 1.0);
        lanePath(railBase, (uint)lane, seg);
        g_card = CARD_RAY;
        g_cardSeg = Chief[railBase + (uint)lane * (uint)LT_MAX_SEG + (uint)max(seg, 0)];
        g_cardAt = at;
        g_rows = ROW_RAY_TITLE | (ROW_RAY_EVENT << 4) | (ROW_RAY_CARRY << 8) | (ROW_RAY_MEDIUM << 12);
        g_nRows = 4u;
    }
    else if (rec >= 0)
    {
        BenchRec R = Bench[rec];
        g_card = CARD_RECORD; g_cardIdx = rec; g_cardRec = R; g_cardAt = at;
        int k = (int)clamp(R.kind, 0.0, (float)(EK_COUNT - 1));
        uint rows = ROW_TITLE, nr = 1u;
        if (rec >= LT_ELEM_BASE)
        {
            if (k != EK_SCREEN && k != EK_BLOCK) { rows |= ROW_ELEM_MAT << (4u * nr); nr++; }
            rows |= ROW_ELEM_PLACE << (4u * nr); nr++;
            rows |= ROW_ELEM_LIGHT << (4u * nr); nr++;
            if (k == EK_PRISM) { rows |= ROW_PRISM_AIM << (4u * nr); nr++; }
        }
        else
        {
            rows |= (ROW_SRC_LIGHT << 4) | (ROW_SRC_BEAM << 8) | (ROW_SRC_PLACE << 12);
            nr = 4u;
            if (LtFlagF(R.flags, F_OFF)) { rows |= ROW_SRC_OFF << 16; nr = 5u; }
        }
        g_rows = rows; g_nRows = nr;
    }
    // Tooltips off: the highlights above stay, no card is drawn (hover and drag alike)
    if (tooltips == 0) { g_card = CARD_NONE; g_rows = 0u; g_nRows = 0u; }
}

// ---------------------------------------------------------------- thread 0
void layout()
{
    g_res = _Resolution.xy;
    g_L = ltLayout(g_res);
    g_s = g_L.s;
    gDispGain = dispersion;
    dlBegin(g_res);

    g_H = Bench[LT_HEADER];
    int sel = (int)clamp(g_H.p0.x, -1.0, (float)LT_TOTAL);
    int drag = (int)clamp(g_H.p0.y, -1.0, (float)LT_TOTAL);
    int railEm = (int)clamp(g_H.dev, 0.0, (float)(LT_MAX_EMIT - 1));
    uint railBase = (uint)railEm * (uint)CHIEF_STRIDE;
    g_st = ltRailStats(railBase);

    g_sel = -1;
    g_selRec = (BenchRec)0;
    if (ltRecordValid(sel))
    {
        BenchRec R = Bench[sel];
        if (R.active > 0.5) { g_sel = sel; g_selRec = R; }
    }
    g_below = g_L.planBox.w - g_L.plan.w >= 18.0 * g_s;
    g_selEnd = g_L.plan.x;

    title();
    planChrome();
    apexLabels();
    railChrome(railEm);
    footer();
    inspect(drag, railBase);     // the hover highlights, then the card is chosen
    lines();                     // readouts, selection, grid note, and last the card
    dlFinish();
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    if (gi == 0u) layout();
    dlEnd(gi);
}
