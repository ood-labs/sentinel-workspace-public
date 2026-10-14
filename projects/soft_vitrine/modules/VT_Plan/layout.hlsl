// VT_Plan / layout.hlsl - the plan canvas's words, live counts, kind numbers, hover inspector and
// verbs, recorded for the shared UI kit (ui.hlsl draws them over canvas.hlsl's drawing).
//
// The plan runs edge to edge (stage space IS the canvas uv and the pointer's normalized position,
// so the drawing cannot be inset), which is why the header, the footer and the legend sit on
// translucent plates over it rather than in strips beside it.
//
// Hover is a read of the pointer snapshot and is never stored. The hovered record is pickRecord()
// at the pointer - the very test plan.hlsl selects and drags with (pick.hlsli) - so what lights is
// what a click takes. While a drag is held the card follows the dragged record instead. Every
// figure is read from the Plan buffer this node publishes.
#include "../_shared/vitrine.hlsli"
StructuredBuffer<PlanRec> Plan : register(t0);
#include "pick.hlsli"
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"

static float g_s;
static float2 g_res;

// the role identity hues and the material value ramp, exactly as canvas.hlsl draws them
float3 roleTint(uint role) { return role == 0u ? PT_ID_A : (role == 1u ? PT_ID_C : PT_ID_B); }
float3 matTint(uint m) { return ptRamp(m == 0u ? 0.15 : (m == 1u ? 1.00 : (m == 2u ? 0.70 : 0.42))); }

// a translucent plate for type that sits over the drawing
void plate(float4 r) { dlRect(r, IL_PANEL, 0.86, IL_RADIUS * g_s); }

uint digitsOf(uint v) { return v >= 100u ? 3u : (v >= 10u ? 2u : 1u); }

// ---------------------------------------------------------------- header: title and the live cast
void header(PlanRec hdr, bool ok)
{
    float s = g_s;
    uint n0 = ok ? (uint)hdr.grp : 0u, n1 = ok ? (uint)hdr.phase : 0u, n2 = ok ? (uint)hdr.flags : 0u;
    float tw = ilLabelW(LB_TITLE, 14.0 * s), sw = ilLabelW(LB_SUBTITLE, 12.0 * s);
    float cw = 0.0;
    [unroll] for (uint k = 0u; k < 3u; k++)
    {
        uint n = k == 0u ? n0 : (k == 1u ? n1 : n2);
        cw += 11.0 * s + ilLabelW(LB_N_MASSES + k, IL_T_TITLE * s) + 6.0 * s + ilNumW(digitsOf(n), IL_T_VALUE * s) + 16.0 * s;
    }
    float4 hr = float4(12.0 * s, 10.0 * s, 24.0 * s + tw + 10.0 * s + sw + 22.0 * s + cw - 4.0 * s, 36.0 * s);
    plate(hr);
    float hy = ilMid(hr).y;
    float x = hr.x + 12.0 * s;
    x += dlLabel(LB_TITLE, x, hy, 14.0 * s, IL_INK, IL_LEFT) + 10.0 * s;
    x += dlLabel(LB_SUBTITLE, x, hy, 12.0 * s, IL_DIM, IL_LEFT) + 22.0 * s;
    // masses, strokes, plates: each count beside its role's identity dot (the legend for the hues)
    [unroll] for (uint j = 0u; j < 3u; j++)
    {
        uint n = j == 0u ? n0 : (j == 1u ? n1 : n2);
        dlCircle(float2(x + 3.0 * s, hy), 3.0 * s, roleTint(2u - j), 1.0);
        x += 11.0 * s;
        x += dlLabel(LB_N_MASSES + j, x, hy, IL_T_TITLE * s, IL_DIM, IL_LEFT) + 6.0 * s;
        x += dlInt((int)n, 1, x, hy, IL_T_VALUE * s, IL_INK, IL_LEFT) + 16.0 * s;
    }
}

// ---------------------------------------------------------------- the selection, top right
uint roleOf(uint idx) { return idx < PLAN_STROKE_0 ? 0u : (idx < PLAN_MASS_0 ? 1u : 2u); }

void selection(uint sel)
{
    float s = g_s;
    float x1 = g_res.x - 12.0 * s;
    uint role = sel == 0u ? 0u : roleOf(sel - 1u);
    float capW = ilLabelW(LB_SELECTED, IL_T_TITLE * s);
    float vw = sel == 0u ? ilLabelW(LB_NONE, IL_T_BODY * s)
                         : ilLabelW(LB_R_PLATE + role, IL_T_TITLE * s) + 6.0 * s + ilNumW(digitsOf(sel), IL_T_VALUE * s);
    float4 r = float4(x1 - capW - vw - 32.0 * s, 10.0 * s, x1, 36.0 * s);
    plate(r);
    float y = ilMid(r).y;
    float x = r.x + 12.0 * s;
    x += dlLabel(LB_SELECTED, x, y, IL_T_TITLE * s, IL_DIM, IL_LEFT) + 8.0 * s;
    if (sel == 0u)
    {
        dlLabel(LB_NONE, x, y, IL_T_BODY * s, IL_DIM, IL_LEFT);
        return;
    }
    x += dlLabel(LB_R_PLATE + role, x, y, IL_T_TITLE * s, IL_ACCENT, IL_LEFT) + 6.0 * s;
    dlInt((int)sel, 1, x, y, IL_T_VALUE * s, IL_ACCENT, IL_LEFT);
}

// ---------------------------------------------------------------- each live record's kind number
// Where the old canvas printed it: a big plate's top-left corner, above a stroke's extent, over a
// mass's core. One loop and one dlInt, so the number formatter is compiled once.
void kindNumbers()
{
    float s = g_s;
    float2 R = g_res;
    [loop] for (uint i = 0u; i < PLAN_MASS_0 + PLAN_MASSES; i++)
    {
        PlanRec r = Plan[i];
        bool show = r.active > 0.5;
        float2 at;
        float3 col = IL_INK;
        uint al = IL_LEFT;
        if (i < PLAN_STROKE_0)
        {
            show = show && r.size.x > 0.030 && r.size.y > 0.022;
            at = float2(r.pos.x - r.size.x + 0.010, r.pos.y - r.size.y + 0.014);
        }
        else if (i < PLAN_MASS_0)
        {
            float2 e = max(r.size, 0.004);
            at = float2(r.pos.x - e.x + 0.008, r.pos.y - e.y + 0.0035);
            col = IL_MID;
        }
        else
        {
            float core = max(r.size.x * 0.34 * saturate(r.size.y), 0.006);
            at = float2(r.pos.x, r.pos.y - core - 0.015);
            al = IL_CENTER;
        }
        if (show) dlInt((int)r.kind, 1, at.x * R.x, at.y * R.y, IL_T_VALUE * s, col, al);
    }
}

// ---------------------------------------------------------------- hover: the record lifts to ink
void highlight(uint idx)
{
    float s = g_s;
    float2 R = g_res;
    PlanRec r = Plan[idx];
    float2 c = r.pos * R;
    float w = 1.5 * s;
    if (idx >= PLAN_MASS_0) dlRing(c, r.size.x * R.y, w, IL_INK, 1.0);                     // its reserve
    else if (idx >= PLAN_STROKE_0) dlEllipse(c, max(r.size, 0.004) * R, w, IL_INK, 1.0, 0.0, 0.0);   // its extent
    else if ((int)r.kind == PK_DASH) dlRing(c, max(r.size.x, r.size.y) * R.x + 4.0 * s, w, IL_INK, 1.0);
    else
    {
        float2 h = max(r.size, 0.002) * R + 1.0;
        dlBorderRect(float4(c - h, c + h), min(h.x, h.y) * 0.35, IL_INK, w);
    }
}

// ---------------------------------------------------------------- the inspector card
// Rows by role (positions and sizes in % of the square frame, which is what stage space is):
//   mass    material, reserve radius, node share, depth, at
//   stroke  extent, weight, depth, at
//   plate   size, layer (a dash: its angle), at
void card(uint idx, float2 at, bool isSel)
{
    float s = g_s;
    float2 R = g_res;
    PlanRec r = Plan[idx];
    uint role = roleOf(idx);
    int kind = (int)r.kind;
    uint fl = (uint)r.flags;
    bool dash = role == 0u && kind == PK_DASH;
    uint rows = role == 2u ? 5u : (role == 1u ? 4u : 3u);

    float w = 244.0 * s, h = (36.0 + 18.0 * (float)rows) * s;
    float x0 = at.x + 18.0 * s;
    if (x0 + w > R.x - 8.0 * s) x0 = at.x - 18.0 * s - w;
    float y0 = at.y + 18.0 * s;
    if (y0 + h > R.y - 8.0 * s) y0 = at.y - 18.0 * s - h;
    x0 = max(x0, 8.0 * s);
    y0 = max(y0, 8.0 * s);
    dlRectEdged(float4(x0, y0, x0 + w, y0 + h), IL_RAISE, 1.0, IL_RADIUS * s, IL_EDGE, 1.0);

    // title: role and number (the accent when this is the selected record), then its kind
    float ty = y0 + 15.0 * s, tx = x0 + 10.0 * s;
    float3 tc = isSel ? IL_ACCENT : IL_INK;
    tx += dlLabel(LB_R_PLATE + role, tx, ty, IL_T_TITLE * s, tc, IL_LEFT) + 5.0 * s;
    tx += dlInt((int)idx + 1, 1, tx, ty, IL_T_VALUE * s, tc, IL_LEFT) + 9.0 * s;
    uint kl = role == 0u ? LB_PK_0 + (uint)clamp(kind, 0, PK_KINDS - 1)
            : (role == 1u ? LB_SK_0 + (uint)clamp(kind, 0, SK_KINDS - 1) : LB_MK_0 + (uint)clamp(kind, 0, MK_KINDS - 1));
    dlLabel(kl, tx, ty, IL_T_BODY * s, IL_MID, IL_LEFT);
    // its own palette tone (masses, strokes, confetti), then whether a hand has edited it
    float rx = x0 + w - 10.0 * s;
    if (role != 0u || dash)
    {
        float3 own = role == 2u ? vt_body(r.tone) : vt_accent(r.tone);
        dlRect(float4(rx - 12.0 * s, ty - 6.0 * s, rx, ty + 6.0 * s), ptSampleColour(own), 1.0, 2.0 * s);
        rx -= 20.0 * s;
    }
    if ((fl & F_EDITED) != 0u) dlLabel(LB_EDITED, rx, ty, IL_T_CAP * s, IL_DIM, IL_RIGHT);
    dlHLine(y0 + 29.0 * s, x0 + 1.0, x0 + w - 1.0, IL_EDGE);

    float cx = x0 + 10.0 * s, vx = x0 + w - 10.0 * s;
    float y = y0 + 29.0 * s + 15.0 * s;
    [loop] for (uint k = 0u; k < rows; k++)
    {
        // defaults: the AT row
        uint cap = LB_I_AT, unit = LB_U_PCT, sep = LB_U_COMMA, word = LB_NONE;
        uint nums = 2u;
        float v0 = r.pos.x * 100.0, v1 = r.pos.y * 100.0;
        int dec = 1;
        uint depthWord = r.grp < 0.34 ? LB_D_FAR : (r.grp < 0.67 ? LB_D_MID : LB_D_NEAR);
        if (role == 2u)
        {
            if (k == 0u) { cap = LB_I_MATERIAL; nums = 0u; word = LB_MAT_0 + ((fl >> 8) & 3u); }
            else if (k == 1u) { cap = LB_I_RESERVE; nums = 1u; v0 = r.size.x * 100.0; }
            else if (k == 2u) { cap = LB_I_SHARE; nums = 1u; v0 = r.size.y; dec = 2; unit = LB_U_TIMES; }
            else if (k == 3u) { cap = LB_I_DEPTH; nums = 1u; v0 = r.grp; dec = 2; unit = depthWord; }
        }
        else if (role == 1u)
        {
            if (k == 0u) { cap = LB_I_EXTENT; v0 = 2.0 * max(r.size.x, 0.004) * 100.0; v1 = 2.0 * max(r.size.y, 0.004) * 100.0; sep = LB_U_TIMES; }
            else if (k == 1u) { cap = LB_I_WEIGHT; nums = 1u; v0 = r.phase; dec = 2; unit = LB_U_TIMES; }
            else if (k == 2u) { cap = LB_I_DEPTH; nums = 1u; v0 = r.grp; dec = 2; unit = depthWord; }
        }
        else
        {
            if (k == 0u) { cap = LB_I_SIZE; v0 = 2.0 * r.size.x * 100.0; v1 = 2.0 * r.size.y * 100.0; sep = LB_U_TIMES; }
            else if (k == 1u && dash) { cap = LB_I_ANGLE; nums = 1u; v0 = degrees(r.phase); dec = 0; unit = LB_U_DEG; }
            else if (k == 1u) { cap = LB_I_LAYER; nums = 0u; word = (fl & F_FRONT) != 0u ? LB_L_FRONT : LB_L_BACK; }
        }
        dlLabel(cap, cx, y, IL_T_CAP * s, IL_DIM, IL_LEFT);
        if (nums == 0u)
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

// ---------------------------------------------------------------- verbs and the material legend
// The footer is the manifest's viewport.bindings. K, M, X and N act on the selected record, so
// they dim while nothing is selected.
float hintW(uint key, uint does)
{
    float s = g_s;
    return ilLabelW(key, IL_T_CAP * s) + 18.0 * s + ilLabelW(does, IL_T_CAP * s) + 16.0 * s;
}

float hint(float x, float y, uint key, uint does, bool live)
{
    float s = g_s;
    float kw = ilLabelW(key, IL_T_CAP * s) + 12.0 * s, kh = 18.0 * s;
    dlKeycap(float4(x, y - 0.5 * kh, x + kw, y + 0.5 * kh), s, key);
    return kw + 6.0 * s + dlLabel(does, x + kw + 6.0 * s, y, IL_T_CAP * s, live ? IL_DIM : IL_RULE, IL_LEFT) + 16.0 * s;
}

float footer(bool hasSel)
{
    float s = g_s;
    float fy = g_res.y - 23.0 * s;
    float tot = 0.0;
    [loop] for (uint b = 0u; b < 8u; b++) tot += hintW(LB_K_CLICK + b, LB_D_CLICK + b);
    float4 fr = float4(12.0 * s, fy - 13.0 * s, 12.0 * s + tot + 8.0 * s, fy + 13.0 * s);
    plate(fr);
    float x = fr.x + 12.0 * s;
    [loop] for (uint k = 0u; k < 8u; k++) x += hint(x, fy, LB_K_CLICK + k, LB_D_CLICK + k, k < 2u || k > 5u || hasSel);
    return fr.z;
}

// the material badges' values, dark to light (clay, gloss, frost, chrome)
uint matOrder(uint k) { return k == 0u ? 0u : (k == 1u ? 3u : (k == 2u ? 2u : 1u)); }

void legend(float leftLimit)
{
    float s = g_s;
    float fy = g_res.y - 23.0 * s;
    float w = ilLabelW(LB_I_MATERIAL, IL_T_TITLE * s) + 12.0 * s;
    [unroll] for (uint k = 0u; k < 4u; k++) w += 14.0 * s + ilLabelW(LB_MAT_0 + matOrder(k), IL_T_CAP * s) + 12.0 * s;
    float4 r = float4(g_res.x - 24.0 * s - w, fy - 13.0 * s, g_res.x - 12.0 * s, fy + 13.0 * s);
    if (r.x < leftLimit + 8.0 * s) return;      // no room beside the verbs; the inspector names it
    plate(r);
    float x = r.x + 12.0 * s;
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
    PlanRec hdr = Plan[PLAN_HEADER];
    bool ok = hdr.tone > 0.5;                              // the plan has been built at least once
    uint sel = ok ? (uint)hdr.pos.y : 0u;
    if (sel > PLAN_MASS_0 + PLAN_MASSES) sel = 0u;

    // hover: pickRecord at the pointer, ignored off the canvas; a held drag shows the dragged record
    float2 pn = _ViewportPointerPosition;
    bool inside = all(pn >= 0.0) && all(pn <= 1.0);
    bool drag = ok && hdr.size.x > 0.5 && sel > 0u;
    uint hov = (ok && inside && !drag) ? pickRecord(pn) : 0u;
    uint show = drag ? sel : hov;

    if (ok) kindNumbers();
    if (show > 0u) highlight(show - 1u);
    header(hdr, ok);
    selection(sel);
    legend(footer(sel > 0u));
    // Tooltips off: the highlight stays, the card goes (hover and drag alike)
    if (tooltips != 0 && show > 0u) card(show - 1u, pn * R, show == sel);
    dlFinish();
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    g_res = _Resolution.xy;
    g_s = clamp(min(g_res.x, g_res.y) / 1024.0, 0.86, 2.4);   // the square stage's own scale: 1 at 1024
    if (gi == 0u) layout();
    dlEnd(gi);
}
