// VT_Growth / layout.hlsl - the Growth View's words, live counts, the group tally, the hover
// inspector and its verb, recorded for the shared UI kit (ui.hlsl draws them over preview.hlsl).
//
// THE TALLY IS LOAD-BEARING (README): one bar per group header, its outline the node count the
// header DECLARES, its fill the nodes actually found active in that range, any shortfall in the
// alarm red. A grower that writes fewer records than it promised is otherwise invisible.
//
// All 64 threads count first (the live records, and each header's found nodes, into groupshared),
// then thread 0 records everything. Hover is a read of the pointer snapshot and is never stored:
// the inspected group is the tally bar under the pointer, or the smallest bounding circle round it.
#include "../_shared/vitrine.hlsli"
StructuredBuffer<LimbRec> Limbs : register(t0);
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"
#include "growth_view.hlsli"

groupshared uint gsLive[3];               // active mass nodes, active stroke points, live headers
groupshared uint gsFound[LIMB_HEADERS];   // nodes found active in each header's declared range

static GVLayout g_L;
static float g_s;
static float2 g_res;

float3 matTint(uint m) { return ptRamp(m == 0u ? 0.15 : (m == 1u ? 1.00 : (m == 2u ? 0.70 : 0.42))); }
float3 famTint(uint g) { return g < LIMB_STROKE_H_0 ? PT_ID_B : PT_ID_C; }
uint digitsOf(uint v) { return v >= 1000u ? 4u : (v >= 100u ? 3u : (v >= 10u ? 2u : 1u)); }
uint declaredOf(LimbRec h) { return h.active > 0.5 ? (uint)clamp(h.group, 0.0, 384.0) : 0u; }

// ---------------------------------------------------------------- header: title and live counts
// Right to left: live groups, stroke points and their budget, mass nodes and theirs (the grower's
// own: min(max(budget, 16), partition)). A budget, not a capacity: grow.hlsl floors every live mass
// at 6 nodes, so the mass count can exceed it, and "48 of 32" would read as an overflow. Parts
// drop, never squeeze, as the panel narrows.
void header()
{
    float s = g_s;
    float hy = 0.5 * g_L.head.w;
    float val = IL_T_VALUE * s, cap = IL_T_TITLE * s, sm = IL_T_CAP * s;
    uint massPool = min((uint)max(mass_budget, 16), LIMB_MASS_CAP - LIMB_NODE_0);
    uint strokePool = min((uint)max(stroke_budget, 16), LIMB_RECORDS - LIMB_STROKE_0);
    float baseW = 0.0, poolW = 0.0;
    [loop] for (uint k = 0u; k < 3u; k++)
    {
        uint n = gsLive[k == 0u ? 2u : (k == 1u ? 1u : 0u)];
        uint lab = k == 0u ? LB_N_GROUPS : (k == 1u ? LB_N_STROKE : LB_N_MASS);
        baseW += ilNumW(digitsOf(n), val) + 6.0 * s + ilLabelW(lab, cap) + (k > 0u ? 13.0 * s : 0.0) + 22.0 * s;
        if (k > 0u) poolW += ilNumW(digitsOf(k == 1u ? strokePool : massPool), val) + ilLabelW(LB_BUDGET, sm) + 10.0 * s;
    }
    float tw = ilLabelW(LB_TITLE, 14.0 * s), sw = ilLabelW(LB_SUBTITLE, 12.0 * s);
    float room = g_L.head.z - 28.0 * s - tw - 30.0 * s;
    bool pools = baseW + poolW <= room - sw - 10.0 * s;
    bool sub = baseW <= room - sw - 10.0 * s;
    bool counts = baseW <= room;

    float x = 14.0 * s;
    x += dlLabel(LB_TITLE, x, hy, 14.0 * s, IL_INK, IL_LEFT) + 10.0 * s;
    if (sub) dlLabel(LB_SUBTITLE, x, hy, 12.0 * s, IL_DIM, IL_LEFT);
    if (!counts) return;
    float rx = g_L.head.z - 14.0 * s;
    [loop] for (uint j = 0u; j < 3u; j++)
    {
        uint n = gsLive[j == 0u ? 2u : (j == 1u ? 1u : 0u)];
        uint lab = j == 0u ? LB_N_GROUPS : (j == 1u ? LB_N_STROKE : LB_N_MASS);
        if (pools && j > 0u)
        {
            rx -= dlInt((int)(j == 1u ? strokePool : massPool), 1, rx, hy, val, IL_MID, IL_RIGHT) + 5.0 * s;
            rx -= dlLabel(LB_BUDGET, rx, hy, sm, IL_DIM, IL_RIGHT) + 5.0 * s;
        }
        rx -= dlInt((int)n, 1, rx, hy, val, IL_INK, IL_RIGHT) + 6.0 * s;
        rx -= dlLabel(lab, rx, hy, cap, IL_DIM, IL_RIGHT);
        if (j > 0u)
        {
            rx -= 7.0 * s;
            dlCircle(float2(rx - 3.0 * s, hy), 3.0 * s, famTint(j == 1u ? LIMB_STROKE_H_0 : 0u), 1.0);   // the family's hue
            rx -= 6.0 * s;
        }
        rx -= 22.0 * s;
    }
}

// ---------------------------------------------------------------- hover
// the bar slot under the pointer, else the smallest live bounding circle containing it
uint hovered(float2 p)
{
    uint g = gvBarAt(g_L, p);
    if (g != 0xFFFFu) return g;
    if (!ilIn(p, g_L.stage)) return 0xFFFFu;
    uint best = 0xFFFFu;
    float bestR = 1e9;
    [loop] for (uint k = 0u; k < LIMB_HEADERS; k++)
    {
        LimbRec h = Limbs[k];
        float3 c = gvBound(g_L, k, h);
        if (h.active > 0.5 && length(p - c.xy) <= c.z && c.z < bestR) { bestR = c.z; best = k; }
    }
    return best;
}

// ---------------------------------------------------------------- the stage's frame and caption
void stage(uint hov)
{
    float s = g_s;
    float4 st = g_L.stage;
    dlBorderRect(st, IL_RADIUS * s, IL_EDGE, 1.0);
    float cy = st.y + 14.0 * s;
    float w = dlLabel(LB_STAGE, st.x + 10.0 * s, cy, IL_T_TITLE * s, IL_DIM, IL_LEFT);
    dlLabelFit(LB_STAGE_D, st.x + 20.0 * s + w, cy, IL_T_CAP * s, IL_DIM, IL_LEFT, st.z - st.x - 30.0 * s - w);
    if (gsLive[2] == 0u) dlLabel(LB_WAITING, ilMid(st).x, ilMid(st).y, IL_T_BODY * s, IL_DIM, IL_CENTER);
    // the inspected group's bounding sphere, lifted from dashed grey to solid ink
    if (hov == 0xFFFFu) return;
    LimbRec h = Limbs[hov];
    if (h.active < 0.5) return;
    float3 c = gvBound(g_L, hov, h);
    dlClip(st);
    dlRing(c.xy, c.z, 1.5 * s, IL_INK, 1.0);
    dlClipReset();
}

// ---------------------------------------------------------------- the group tally
void tally(uint hov, uint scale)
{
    float s = g_s;
    float4 t = g_L.tally;
    float cap = IL_T_CAP * s;
    dlBorderRect(t, IL_RADIUS * s, IL_EDGE, 1.0);

    // caption and legend: outline = declared, fill = found (each family's hue), red = short
    uint shortN = 0u;
    [loop] for (uint g0 = 0u; g0 < LIMB_HEADERS; g0++)
    {
        uint d = declaredOf(Limbs[g0]);
        shortN += (gsFound[g0] < d) ? 1u : 0u;
    }
    float cy = t.y + 15.0 * s;
    float x = t.x + 12.0 * s;
    x += dlLabel(LB_TALLY, x, cy, IL_T_TITLE * s, IL_DIM, IL_LEFT) + 18.0 * s;
    float limit = t.z - 90.0 * s;
    float sw = 10.0 * s;
    if (x + 120.0 * s < limit)
    {
        dlBorderRect(float4(x, cy - 5.0 * s, x + sw, cy + 5.0 * s), 0.0, IL_RULE, 1.0);
        x += sw + 5.0 * s;
        x += dlLabel(LB_L_DECLARED, x, cy, cap, IL_DIM, IL_LEFT) + 14.0 * s;
        dlRect(float4(x, cy - 5.0 * s, x + 0.5 * sw, cy + 5.0 * s), famTint(0u), 1.0, 0.0);
        dlRect(float4(x + 0.5 * sw, cy - 5.0 * s, x + sw, cy + 5.0 * s), famTint(LIMB_STROKE_H_0), 1.0, 0.0);
        x += sw + 5.0 * s;
        x += dlLabel(LB_L_FOUND, x, cy, cap, IL_DIM, IL_LEFT) + 14.0 * s;
        dlRect(float4(x, cy - 5.0 * s, x + sw, cy + 5.0 * s), IL_ALARM, 1.0, 0.0);
        x += sw + 5.0 * s;
        x += dlLabel(LB_L_SHORT, x, cy, cap, IL_DIM, IL_LEFT) + 18.0 * s;
        // the scale the bars are drawn to
        float need = ilLabelW(LB_L_SCALE, cap) + ilNumW(digitsOf(scale), IL_T_VALUE * s) + ilLabelW(LB_U_NODES, cap) + 10.0 * s;
        if (x + need < limit)
        {
            x += dlLabel(LB_L_SCALE, x, cy, cap, IL_DIM, IL_LEFT) + 5.0 * s;
            x += dlInt((int)scale, 1, x, cy, IL_T_VALUE * s, IL_MID, IL_LEFT) + 4.0 * s;
            dlLabel(LB_U_NODES, x, cy, cap, IL_DIM, IL_LEFT);
        }
    }
    if (shortN > 0u)
    {
        float rx = t.z - 12.0 * s;
        rx -= dlLabel(LB_SHORT, rx, cy, IL_T_TITLE * s, IL_ALARM, IL_RIGHT) + 6.0 * s;
        dlInt((int)shortN, 1, rx, cy, IL_T_VALUE * s, IL_ALARM, IL_RIGHT);
    }

    // the bars, painted over a lifted slot when inspected. One exit per iteration, no `continue`:
    // out of a [loop] that has already drawn, fxc can drop iterations (README, the mass grower).
    float4 m0 = gvBarSlot(g_L, 0u), m1 = gvBarSlot(g_L, LIMB_STROKE_H_0 - 1u);
    float4 s0 = gvBarSlot(g_L, LIMB_STROKE_H_0), s1 = gvBarSlot(g_L, LIMB_HEADERS - 1u);
    [loop] for (uint g = 0u; g < LIMB_HEADERS; g++)
    {
        LimbRec h = Limbs[g];
        bool hot = g == hov;
        if (hot) dlRect(ilInset(gvBarSlot(g_L, g), -1.0), IL_RAISE, 1.0, 2.0 * s);
        float4 b = gvBar(g_L, g);
        uint declared = declaredOf(h);
        if (declared > 0u)
        {
            uint found = min(gsFound[g], declared);
            float bh = b.w - b.y;
            float yd = b.w - saturate((float)declared / (float)scale) * bh;
            float yf = b.w - saturate((float)found / (float)scale) * bh;
            if (found > 0u) dlRect(float4(b.x, yf, b.z, b.w), famTint(g), 1.0, 0.0);
            if (found < declared) dlRect(float4(b.x, yd, b.z, yf), IL_ALARM, 1.0, 0.0);
            dlBorderRect(float4(b.x - 1.0, yd - 1.0, b.z + 1.0, b.w), 0.0, hot ? IL_INK : IL_RULE, 1.0);
        }
    }
    dlHLine(g_L.bars.w + 0.5, m0.x, m1.z, IL_EDGE);
    dlHLine(g_L.bars.w + 0.5, s0.x, s1.z, IL_EDGE);
    float ly = 0.5 * (g_L.bars.w + t.w);
    dlLabel(LB_F_MASSES, 0.5 * (m0.x + m1.z), ly, cap, IL_DIM, IL_CENTER);
    dlLabel(LB_F_STROKES, 0.5 * (s0.x + s1.z), ly, cap, IL_DIM, IL_CENTER);
}

// ---------------------------------------------------------------- the inspector card
// Title: the family and the plan record the group grows from (the plan canvas's own number), its
// kind. Rows: mass  nodes, material, bound radius (world), depth, centre (world x, y)
//             stroke points, bound radius, depth, centre (in % of the square frame)
void card(uint g, float2 at)
{
    float s = g_s;
    float2 R = g_res;
    LimbRec h = Limbs[g];
    bool mass = g < LIMB_STROKE_H_0;
    bool live = h.active > 0.5;
    uint rows = live ? (mass ? 5u : 4u) : 1u;
    float w = 252.0 * s, hgt = (36.0 + 18.0 * (float)rows) * s;
    float x0 = at.x + 18.0 * s;
    if (x0 + w > R.x - 8.0 * s) x0 = at.x - 18.0 * s - w;
    float y0 = at.y + 18.0 * s;
    if (y0 + hgt > R.y - 8.0 * s) y0 = at.y - 18.0 * s - hgt;
    x0 = max(x0, 8.0 * s);
    y0 = max(y0, 8.0 * s);
    dlRectEdged(float4(x0, y0, x0 + w, y0 + hgt), IL_RAISE, 1.0, IL_RADIUS * s, IL_EDGE, 1.0);

    float ty = y0 + 15.0 * s, tx = x0 + 10.0 * s;
    uint planId = mass ? PLAN_MASS_0 + g + 1u : PLAN_STROKE_0 + (g - LIMB_STROKE_H_0) + 1u;
    tx += dlLabel(mass ? LB_R_MASS : LB_R_STROKE, tx, ty, IL_T_TITLE * s, IL_INK, IL_LEFT) + 5.0 * s;
    tx += dlInt((int)planId, 1, tx, ty, IL_T_VALUE * s, IL_INK, IL_LEFT) + 9.0 * s;
    int kind = (int)h.kind;
    if (live) dlLabel(mass ? LB_MK_0 + (uint)clamp(kind, 0, MK_KINDS - 1) : LB_SK_0 + (uint)clamp(kind, 0, SK_KINDS - 1),
                      tx, ty, IL_T_BODY * s, IL_MID, IL_LEFT);
    if (live && !mass)
    {
        float rx = x0 + w - 10.0 * s;      // the stroke's own accent tone
        dlRect(float4(rx - 12.0 * s, ty - 6.0 * s, rx, ty + 6.0 * s), ptSampleColour(vt_accent(h.material)), 1.0, 2.0 * s);
    }
    dlHLine(y0 + 29.0 * s, x0 + 1.0, x0 + w - 1.0, IL_EDGE);
    float cx = x0 + 10.0 * s, vx = x0 + w - 10.0 * s;
    float y = y0 + 29.0 * s + 15.0 * s;
    if (!live)
    {
        dlLabelFit(LB_EMPTY, cx, y, IL_T_CAP * s, IL_DIM, IL_LEFT, w - 20.0 * s);
        return;
    }
    uint declared = declaredOf(h), found = min(gsFound[g], declared);
    uint depthWord = h.tparam < 0.34 ? LB_D_FAR : (h.tparam < 0.67 ? LB_D_MID : LB_D_NEAR);
    [loop] for (uint k = 0u; k < rows; k++)
    {
        // defaults: the CENTRE row
        uint capL = LB_I_CENTRE, unit = mass ? LB_U_WORLD : LB_U_PCT, sep = LB_U_COMMA, word = LB_MAT_0;
        uint nums = 2u;
        float v0 = mass ? h.pos.x : h.pos.x * 100.0, v1 = mass ? h.pos.y : h.pos.y * 100.0;
        int dec = mass ? 2 : 1;
        bool tallyRow = k == 0u;
        if (tallyRow) { capL = mass ? LB_I_NODES : LB_I_POINTS; }
        else if (mass && k == 1u) { capL = LB_I_MATERIAL; nums = 0u; word = LB_MAT_0 + (((uint)h.material) & 3u); }
        else if (k == (mass ? 2u : 1u)) { capL = LB_I_BOUND; nums = 1u; v0 = mass ? h.radius : h.radius * 100.0; dec = mass ? 3 : 1; }
        else if (k == (mass ? 3u : 2u)) { capL = LB_I_DEPTH; nums = 1u; v0 = h.tparam; dec = 2; unit = depthWord; }
        dlLabel(capL, cx, y, IL_T_CAP * s, IL_DIM, IL_LEFT);
        if (tallyRow)
        {
            // found of declared: the tally's two numbers, the found one red when it falls short
            float xr = vx - dlInt((int)declared, 1, vx, y, IL_T_VALUE * s, IL_INK, IL_RIGHT) - 5.0 * s;
            xr -= dlLabel(LB_OF, xr, y, IL_T_CAP * s, IL_DIM, IL_RIGHT) + 5.0 * s;
            dlInt((int)found, 1, xr, y, IL_T_VALUE * s, found < declared ? IL_ALARM : IL_INK, IL_RIGHT);
        }
        else if (nums == 0u)
            dlLabel(word, vx, y, IL_T_BODY * s, IL_INK, IL_RIGHT);
        else
        {
            float xr = vx - dlLabel(unit, vx, y, IL_T_CAP * s, IL_DIM, IL_RIGHT) - 4.0 * s;
            xr -= dlNum(nums == 2u ? v1 : v0, dec, xr, y, IL_T_VALUE * s, IL_INK, IL_RIGHT);
            if (nums == 2u)
            {
                xr -= 4.0 * s;
                xr -= dlLabel(sep, xr, y, IL_T_CAP * s, IL_DIM, IL_RIGHT) + 4.0 * s;
                dlNum(v0, dec, xr, y, IL_T_VALUE * s, IL_INK, IL_RIGHT);
            }
        }
        y += 18.0 * s;
    }
}

// ---------------------------------------------------------------- the verb and the material legend
float footer()
{
    float s = g_s;
    float fy = ilMid(g_L.foot).y;
    float x = 14.0 * s;
    float kw = ilLabelW(LB_K_HOVER, IL_T_CAP * s) + 12.0 * s, kh = 18.0 * s;
    dlKeycap(float4(x, fy - 0.5 * kh, x + kw, fy + 0.5 * kh), s, LB_K_HOVER);
    x += kw + 6.0 * s;
    return x + dlLabel(LB_D_HOVER, x, fy, IL_T_CAP * s, IL_DIM, IL_LEFT);
}

// the material chips' values, dark to light (clay, gloss, frost, chrome)
uint matOrder(uint k) { return k == 0u ? 0u : (k == 1u ? 3u : (k == 2u ? 2u : 1u)); }

void legend(float leftLimit)
{
    float s = g_s;
    float fy = ilMid(g_L.foot).y;
    float w = ilLabelW(LB_I_MATERIAL, IL_T_TITLE * s) + 12.0 * s;
    [unroll] for (uint k = 0u; k < 4u; k++) w += 14.0 * s + ilLabelW(LB_MAT_0 + matOrder(k), IL_T_CAP * s) + 12.0 * s;
    float x = g_res.x - 14.0 * s - w + 12.0 * s;
    if (x < leftLimit + 24.0 * s) return;      // no room beside the verb; the inspector names it
    x += dlLabel(LB_I_MATERIAL, x, fy, IL_T_TITLE * s, IL_DIM, IL_LEFT) + 12.0 * s;
    [unroll] for (uint j = 0u; j < 4u; j++)
    {
        dlRect(float4(x, fy - 5.0 * s, x + 10.0 * s, fy + 5.0 * s), matTint(matOrder(j)), 1.0, 2.0 * s);
        x += 14.0 * s;
        x += dlLabel(LB_MAT_0 + matOrder(j), x, fy, IL_T_CAP * s, IL_MID, IL_LEFT) + 12.0 * s;
    }
}

// ---------------------------------------------------------------- thread 0
void layout()
{
    float2 R = g_res;
    dlBegin(R);
    // hover, ignored off the canvas
    float2 pn = _ViewportPointerPosition;
    bool inside = all(pn >= 0.0) && all(pn <= 1.0);
    float2 p = pn * R;
    uint hov = inside ? hovered(p) : 0xFFFFu;
    // the tally's scale: 64 nodes full height, or the tallest declaration, rounded up to 16
    uint top = 64u;
    [loop] for (uint g = 0u; g < LIMB_HEADERS; g++) top = max(top, declaredOf(Limbs[g]));
    top = (top + 15u) / 16u * 16u;

    header();
    stage(hov);
    tally(hov, top);
    legend(footer());
    if (tooltips != 0 && hov != 0xFFFFu) card(hov, p);     // Tooltips off: the stage and tally still lift
    dlFinish();
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    g_res = _Resolution.xy;
    g_L = gvLayout(g_res);
    g_s = g_L.s;

    // every thread: the live records by family, then one header's found nodes each
    if (gi < 3u) gsLive[gi] = 0u;
    GroupMemoryBarrierWithGroupSync();
    uint a = 0u, b = 0u, c = 0u;
    [loop] for (uint i = gi; i < LIMB_RECORDS; i += IL_LAYOUT_THREADS)
    {
        uint on = Limbs[i].active > 0.5 ? 1u : 0u;
        if (i < LIMB_HEADERS) c += on;
        else if (i < LIMB_MASS_CAP) a += on;
        else b += on;
    }
    InterlockedAdd(gsLive[0], a);
    InterlockedAdd(gsLive[1], b);
    InterlockedAdd(gsLive[2], c);
    if (gi < LIMB_HEADERS)
    {
        LimbRec h = Limbs[gi];
        uint declared = declaredOf(h), first = (uint)max(h.parent, 0.0), found = 0u;
        [loop] for (uint k = 0u; k < declared; k++)
            found += (first + k < LIMB_RECORDS && Limbs[first + k].active > 0.5) ? 1u : 0u;
        gsFound[gi] = found;
    }
    GroupMemoryBarrierWithGroupSync();

    if (gi == 0u) layout();
    dlEnd(gi);
}
