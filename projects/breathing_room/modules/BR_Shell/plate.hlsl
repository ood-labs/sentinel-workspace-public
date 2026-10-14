// BR_Shell / plate.hlsl -- the unfolded room's drawing, per pixel.
//
// Plan in the middle, each wall's interior elevation folded out from its own plan edge, drawn in
// drafting convention: cut walls in hatched poche, door swings, glazing lines, dashed overhead
// openings, a hearth in front of the breast. It is the content background the shared UI kit draws
// the type, dimensions, handles and corner cards over (ui.hlsl, from layout.hlsl's draw list).
//
// Mostly monochrome (plan_theme): amber is the selection and nothing else, red is a broken
// opening, and the four walls carry a muted identity tint on a rule above each elevation (and on
// their names, in the layout), so an elevation can be matched to its plan edge at a glance.
#include "../_shared/br_records.hlsli"
#include "../_shared/br_floor.hlsli"
#include "shell_layout.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);
StructuredBuffer<BRRec> ShellBuf : register(t0);

// Each opening is read from its record where it is used: a register array of eight, indexed in
// loops, becomes indexable temps (register pressure on every pixel of a full-panel pass).
BROpening opening(int i) { return brOpeningFromRec(ShellBuf[SHELL_OPEN0 + i]); }

static float gS;        // px per metre
static float gUi;       // ui scale

// ---- drafting coverage (px), the module's own: hairlines AA'd over one pixel
float aa(float d, float w) { return 1.0 - smoothstep(w * 0.5 - 0.5, w * 0.5 + 0.5, d); }
float dSeg(float2 P, float2 a, float2 b, float w) { return aa(ilSdSeg(P, a, b), w); }
float dDash(float2 P, float2 a, float2 b, float w, float dash, float gap)
{
    float2 ab = b - a;
    float len = max(length(ab), 1e-4);
    float h = saturate(dot(P - a, ab) / (len * len));
    float on = step(fmod(h * len, dash + gap), dash);         // the phase runs from a
    return aa(length(P - (a + ab * h)), w) * on;
}
float dRectDash(float2 P, float4 r, float w, float dash, float gap)
{
    float c = dDash(P, r.xy, float2(r.z, r.y), w, dash, gap);
    c = max(c, dDash(P, float2(r.z, r.y), r.zw, w, dash, gap));
    c = max(c, dDash(P, r.zw, float2(r.x, r.w), w, dash, gap));
    return max(c, dDash(P, float2(r.x, r.w), r.xy, w, dash, gap));
}
// Section hatch (poche): parallel lines at `angle`, `spacing` px apart, `w` px wide.
float dHatch(float2 P, float spacing, float angle, float w)
{
    float2 dir = float2(cos(angle), sin(angle));
    float s = dot(P, float2(-dir.y, dir.x));
    return aa(abs(frac(s / spacing + 0.5) - 0.5) * spacing, w);
}

float cm(float dMetres, float widthPx) { return aa(dMetres * gS, widthPx); }   // metres -> coverage
void ink(inout float3 col, float3 c, float a) { col = lerp(col, c, saturate(a)); }

float sdRect2(float2 p, float2 lo, float2 hi)
{
    float2 c = (lo + hi) * 0.5, h = (hi - lo) * 0.5;
    float2 q = abs(p - c) - h;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}
float rectLine(float2 p, float2 lo, float2 hi, float w) { return cm(abs(sdRect2(p, lo, hi)), w); }
float rectIn(float2 p, float2 lo, float2 hi) { return step(sdRect2(p, lo, hi), 0.0); }
float segM(float2 p, float2 a, float2 b, float w) { return cm(ilSdSeg(p, a, b), w); }

// ---------------------------------------------------------------------------------------------
// ELEVATION DRAWING. p = (a, y) in metres in wall w's frame (a = along-wall, y = height).

void drawOpeningElev(inout float3 col, float2 p, BROpening o, BRRoom r, float3 lineC, float3 trimC, float lw)
{
    float hw = o.width * 0.5;
    float a = o.a, s0 = o.sill, s1 = o.sill + o.height;
    float2 lo = float2(a - hw, s0), hi = float2(a + hw, s1);
    float cw = 0.075;                 // casing width

    if (o.kind == OPEN_FIREPLACE)
    {
        // chimney breast to the ceiling, mantel shelf, pilasters, arched firebox, hearth slab
        ink(col, PT_WELL * 1.4, rectIn(p, float2(a - hw, 0), float2(a + hw, r.H)));
        ink(col, trimC, segM(p, float2(a - hw, 0), float2(a - hw, r.H), 1.0));
        ink(col, trimC, segM(p, float2(a + hw, 0), float2(a + hw, r.H), 1.0));
        float mh = o.height;
        ink(col, lineC, rectLine(p, float2(a - hw - 0.06, mh), float2(a + hw + 0.06, mh + 0.055), lw));
        ink(col, lineC, rectLine(p, float2(a - hw + 0.05, 0.0), float2(a - hw + 0.24, mh - 0.10), lw * 0.8));
        ink(col, lineC, rectLine(p, float2(a + hw - 0.24, 0.0), float2(a + hw - 0.05, mh - 0.10), lw * 0.8));
        ink(col, lineC, rectLine(p, float2(a - hw + 0.24, mh - 0.26), float2(a + hw - 0.24, mh - 0.10), lw * 0.8));
        float fbw = o.cols * 0.5, fbh = o.rows;
        float capH = fbw * 0.55;
        float cy = fbh - capH;
        float2 uv = float2(abs(p.x - a), p.y - cy);
        float dCap = (length(float2(uv.x / fbw, max(uv.y, 0.0) / capH)) - 1.0) * capH;
        float dBox = min(dCap, sdRect2(uv, float2(-fbw, 0.04 - cy), float2(fbw, 0.0)));
        float notFloor = step(0.045, p.y);
        ink(col, PT_FIELD, step(dBox, 0.0) * 0.85);
        ink(col, PT_RULE, step(dBox, 0.0) * dHatch(p * gS, 4.0, 0.785, 1.0) * 0.6);
        ink(col, lineC, cm(abs(dBox), lw) * notFloor);
        ink(col, lineC, rectLine(p, float2(a - hw - 0.12, 0.0), float2(a + hw + 0.12, 0.04), lw * 0.8));
        return;
    }

    if (o.kind == OPEN_ARCH)
    {
        float cy = s1 - hw;
        float2 uv = float2(abs(p.x - a), p.y - cy);
        float dShape = min(length(uv) - hw, sdRect2(uv, float2(-hw, s0 - cy), float2(hw, 0.0)));
        float notFloor = step(s0 + 0.005, p.y);
        ink(col, PT_FIELD, step(dShape, 0.0) * 0.8);
        ink(col, trimC, cm(abs(dShape - cw), lw * 0.8) * notFloor);
        ink(col, lineC, cm(abs(dShape), lw) * notFloor);
        return;
    }

    // rectangular openings: casing, then the opening, then its fill
    float2 clo = float2(lo.x - cw, s0);
    float2 chi = hi + float2(cw, cw);
    ink(col, PT_FIELD, rectIn(p, clo, chi) * 0.55);
    ink(col, trimC, rectLine(p, clo, chi, lw * 0.8));
    ink(col, lineC, rectLine(p, lo, hi, lw));

    if (brOpenIsWindow(o.kind))
    {
        // stool + apron below the sill
        ink(col, trimC, rectLine(p, float2(lo.x - cw - 0.03, s0 - 0.03), float2(hi.x + cw + 0.03, s0), lw * 0.8));
        ink(col, trimC, rectLine(p, float2(lo.x - cw + 0.02, s0 - 0.12), float2(hi.x + cw - 0.02, s0 - 0.03), lw * 0.7));
        float fw = 0.045;
        if (o.kind == OPEN_DOUBLEHUNG)
        {
            float mid = (s0 + s1) * 0.5;
            ink(col, lineC, rectLine(p, float2(lo.x + fw, s0 + fw), float2(hi.x - fw, mid - 0.02), lw * 0.8));
            ink(col, lineC, rectLine(p, float2(lo.x + fw, mid + 0.02), float2(hi.x - fw, s1 - fw), lw * 0.8));
            ink(col, lineC, rectLine(p, float2(lo.x, mid - 0.02), float2(hi.x, mid + 0.02), lw * 0.7));
            float cols = max(o.cols, 1.0);
            [loop] for (int i = 1; i < (int)cols; i++)
            {
                float x = lerp(lo.x + fw, hi.x - fw, (float)i / cols);
                ink(col, lineC, segM(p, float2(x, s0 + fw), float2(x, s1 - fw), lw * 0.7));
            }
        }
        else
        {
            float cols = max(o.cols, 1.0), rows = max(o.rows, 1.0);
            ink(col, lineC, rectLine(p, lo + fw, hi - fw, lw * 0.8));
            [loop] for (int i = 1; i < (int)cols; i++)
            {
                float x = lerp(lo.x, hi.x, (float)i / cols);
                ink(col, lineC, segM(p, float2(x, s0), float2(x, s1), lw * 0.9));
            }
            [loop] for (int j = 1; j < (int)rows; j++)
            {
                float y = lerp(s0 + fw, s1 - fw, (float)j / rows);
                ink(col, lineC, segM(p, float2(lo.x + fw, y), float2(hi.x - fw, y), lw * 0.6));
            }
        }
        // glass glints: two short diagonals in the upper-left of the glazing
        float2 gq = p - (lo + float2(0.12, o.height * 0.62));
        float gl = min(ilSdSeg(gq, float2(0, 0), float2(0.10, 0.10)), ilSdSeg(gq, float2(0.06, -0.05), float2(0.16, 0.05)));
        ink(col, PT_DIM, cm(gl, 0.8) * 0.6);

        if (o.radiator && (r.flags & ROOM_FLAG_RADIATORS) != 0)
        {
            float top = min(s0 - 0.16, 0.72);
            float2 rlo = float2(lo.x + 0.06, 0.13), rhi = float2(hi.x - 0.06, max(top, 0.30));
            ink(col, trimC, rectLine(p, rlo, rhi, lw * 0.8));
            float fin = fmod(abs(p.x - rlo.x), 0.065);
            float inR = rectIn(p, rlo + float2(0.02, 0.03), rhi - float2(0.02, 0.03));
            ink(col, PT_RULE, inR * cm(min(fin, 0.065 - fin), 0.8));
        }
    }
    else if (o.kind == OPEN_FRENCH)
    {
        float fw = 0.06;
        float mid = a;
        ink(col, lineC, segM(p, float2(mid, s0), float2(mid, s1), lw));
        float rows = max(o.rows, 1.0);
        [unroll] for (int leaf = 0; leaf < 2; leaf++)
        {
            float x0 = leaf == 0 ? lo.x : mid, x1 = leaf == 0 ? mid : hi.x;
            ink(col, lineC, rectLine(p, float2(x0 + fw, 0.36), float2(x1 - fw, s1 - fw), lw * 0.7));
            ink(col, lineC, rectLine(p, float2(x0 + fw, 0.08), float2(x1 - fw, 0.30), lw * 0.6));
            [loop] for (int j = 1; j < (int)rows; j++)
            {
                float y = lerp(0.36, s1 - fw, (float)j / rows);
                ink(col, lineC, segM(p, float2(x0 + fw, y), float2(x1 - fw, y), lw * 0.6));
            }
        }
    }
    else if (o.kind == OPEN_DOOR)
    {
        float cols = max(o.cols, 1.0), rows = max(o.rows, 1.0);
        float m = 0.09;
        [loop] for (int i = 0; i < (int)cols; i++)
        {
            [loop] for (int j = 0; j < (int)rows; j++)
            {
                float x0 = lerp(lo.x + m, hi.x - m, (float)i / cols) + (i > 0 ? 0.04 : 0.0);
                float x1 = lerp(lo.x + m, hi.x - m, (float)(i + 1) / cols) - (i + 1 < (int)cols ? 0.04 : 0.0);
                float yTop = s1 - m;
                float yb = 0.12;
                float hgt = (yTop - yb);
                float split = (j == 0) ? 0.0 : ((j == 1) ? 0.42 : 0.62);
                float split2 = (j == 0) ? 0.38 : ((j == 1) ? 0.58 : 1.0);
                float y0 = yb + hgt * split + (j > 0 ? 0.03 : 0.0);
                float y1 = yb + hgt * split2 - 0.03;
                ink(col, lineC, rectLine(p, float2(x0, y0), float2(x1, y1), lw * 0.7));
            }
        }
        ink(col, lineC, aa(length(p - float2(hi.x - 0.075, 0.98)) * gS - 0.035 * gS, 1.2));
    }
}

void drawCurtainsElev(inout float3 col, float2 p, BROpening o, float3 c, float lw)
{
    float hw = o.width * 0.5;
    float rodY = o.sill + o.height + 0.17;
    float ext = 0.36;
    ink(col, c, segM(p, float2(o.a - hw - ext, rodY), float2(o.a + hw + ext, rodY), lw * 1.2));
    ink(col, c, aa((length(p - float2(o.a - hw - ext - 0.025, rodY)) - 0.025) * gS, 1.0));
    ink(col, c, aa((length(p - float2(o.a + hw + ext + 0.025, rodY)) - 0.025) * gS, 1.0));
    // two gathered panels, hem 2 cm off the floor
    [unroll] for (int side = 0; side < 2; side++)
    {
        float x0 = (side == 0) ? o.a - hw - ext + 0.02 : o.a + hw - 0.14;
        float x1 = (side == 0) ? o.a - hw + 0.14 : o.a + hw + ext - 0.02;
        float inP = step(x0, p.x) * step(p.x, x1) * step(0.02, p.y) * step(p.y, rodY - 0.02);
        float t = (p.x - x0) / max(x1 - x0, 1e-3);
        float folds = abs(sin(t * 3.14159 * 6.0 + p.y * 0.8));
        ink(col, PT_RULE * 0.9, inP * cm(folds * 0.03, 1.0) * 0.9);
        ink(col, c, rectLine(p, float2(x0, 0.02), float2(x1, rodY - 0.02), lw * 0.6) * 0.8);
    }
}

// Interior elevation of wall w: outline, trims and every opening on it. (The selected opening's
// handles and dimensions are the layout's, drawn over this.)
void drawElevation(inout float3 col, float2 P, ShellLayout L, BRRoom r, int w, int selType, int selIndex, int hoverIndex)
{
    float4 er = shellElevRect(L, w);
    float pad = 46.0 * gUi;
    if (!shellInRect(P, er, pad)) return;
    float2 p = shellElevAY(L, w, P);
    float2 span = shellWallSpan(L, w);
    float a0 = span.x, a1 = span.y;
    bool inside = p.x >= a0 && p.x <= a1 && p.y >= 0.0 && p.y <= r.H;
    if (inside) ink(col, PT_WELL, 1.0);

    // trims: baseboard, picture rail, crown -- interrupted where an opening's casing sits
    float casingMask = 1.0;
    [loop] for (int i = 0; i < SHELL_OPEN_MAX; i++)
    {
        BROpening o = opening(i);
        float hw = o.width * 0.5 + ((o.kind == OPEN_FIREPLACE) ? 0.0 : 0.075);
        float top = (o.kind == OPEN_FIREPLACE) ? r.H - r.crown : o.sill + o.height + 0.075;
        if (o.active && o.wall == w && abs(p.x - o.a) < hw && p.y < top && p.y >= o.sill - 0.13) casingMask = 0.0;
    }
    float3 trimC = PT_DIM;
    if (inside)
    {
        ink(col, trimC, cm(abs(p.y - r.baseH), 1.0) * casingMask);
        ink(col, trimC * 0.8, cm(abs(p.y - r.baseH + 0.025), 1.0) * casingMask * 0.7);
        if (r.railH > 0.0) ink(col, trimC, cm(abs(p.y - r.railH), 1.0) * casingMask);
        if (r.crown > 0.0)
        {
            ink(col, trimC, cm(abs(p.y - (r.H - r.crown)), 1.0));
            ink(col, trimC * 0.8, cm(abs(p.y - (r.H - r.crown * 0.45)), 1.0) * 0.8);
        }
    }

    // outline: floor heavy, ceiling and ends hairline
    float floorL = (p.x >= a0 - 0.02 && p.x <= a1 + 0.02) ? abs(p.y) : 1e9;
    float ceilL = (p.x >= a0 && p.x <= a1) ? abs(p.y - r.H) : 1e9;
    float ends = (p.y >= 0.0 && p.y <= r.H) ? min(abs(p.x - a0), abs(p.x - a1)) : 1e9;
    ink(col, PT_INK, cm(floorL, 2.0));
    bool ceilSel = (selType == 3 && selIndex == w);
    ink(col, ceilSel ? PT_ACCENT : PT_MID, cm(ceilL, ceilSel ? 2.0 : 1.0));
    ink(col, PT_MID, cm(ends, 1.0));

    // openings
    [loop] for (int j = 0; j < SHELL_OPEN_MAX; j++)
    {
        BROpening o = opening(j);
        if (o.active && o.wall == w && abs(p.x - o.a) <= o.width * 0.5 + 0.6)
        {
            bool sel = (selType == 1 && selIndex == j);
            bool hov = (hoverIndex == j);
            float3 lc = (o.alarms != 0) ? PT_ALARM : (sel ? PT_ACCENT : (hov ? PT_INK : PT_MID));
            drawOpeningElev(col, p, o, r, lc, sel ? lc * 0.8 : trimC, sel ? 1.6 : 1.1);
            if (o.curtains && (r.flags & ROOM_FLAG_CURTAINS) != 0) drawCurtainsElev(col, p, o, sel ? PT_ACCENT * 0.8 : PT_RULE * 1.6, 1.0);
        }
    }

    // identity rule just outside the ceiling line
    float3 idc = ptSampleColour(ptId(w));
    ink(col, idc * 0.9, dSeg(P, shellElevPx(L, w, a0, r.H + 0.06), shellElevPx(L, w, a1, r.H + 0.06), 2.0) * 0.8);
}

// ---------------------------------------------------------------------------------------------
// PLAN

void drawPlan(inout float3 col, float2 P, ShellLayout L, BRRoom r, int selType, int selIndex, int hoverIndex)
{
    float2 wp = shellPlanWorld(L, P);
    float T = r.T;
    bool inRoom = wp.x >= r.x0 && wp.x <= r.x1 && wp.y >= r.z0 && wp.y <= r.z1;
    bool inOuter = wp.x >= r.x0 - T && wp.x <= r.x1 + T && wp.y >= r.z0 - T && wp.y <= r.z1 + T;
    if (!inOuter && !(wp.x >= r.x0 - T - 0.6 && wp.x <= r.x1 + T + 0.6 && wp.y >= r.z0 - T - 0.6 && wp.y <= r.z1 + T + 0.6)) return;

    // floor: parquet edges, faint
    if (inRoom)
    {
        ink(col, PT_WELL, 1.0);
        BRSlat sl = brFloorSlat(wp, r.floorPattern, r.plankW);
        float slatPx = r.plankW * gS;
        float vis = saturate((slatPx - 2.5) / 4.0);
        ink(col, PT_GRID * 1.6, cm(sl.edge, 1.0) * vis);
    }

    // poche: the wall band, hatched
    bool inBand = inOuter && !inRoom;
    float cut = 0.0;            // 1 where an opening cuts the band
    [loop] for (int i = 0; i < SHELL_OPEN_MAX; i++)
    {
        BROpening o = opening(i);
        float along = brWallAlongX(o.wall) ? wp.x : wp.y;
        float2 n = brWallNormal(o.wall);
        float plane = brWallPlane(r, o.wall);
        float d = brWallAlongX(o.wall) ? (wp.y - plane) * n.y : (wp.x - plane) * n.x;
        if (o.active && brOpenIsHole(o.kind) && abs(along - o.a) <= o.width * 0.5 && d <= 0.0 && d >= -T) cut = 1.0;
    }
    if (inBand && cut < 0.5)
    {
        ink(col, PT_RULE * 0.55, 1.0);
        ink(col, PT_RULE * 1.5, dHatch(P, 5.0 * gUi, 0.785, 1.0));
    }
    // band outlines
    float dIn = abs(sdRect2(wp, float2(r.x0, r.z0), float2(r.x1, r.z1)));
    float dOut = abs(sdRect2(wp, float2(r.x0 - T, r.z0 - T), float2(r.x1 + T, r.z1 + T)));
    ink(col, PT_MID, cm(dOut, 1.4) * (1.0 - cut));
    ink(col, PT_INK, cm(dIn, 1.6) * (1.0 - cut));

    // wall face selection
    if (selType == 2 && selIndex >= 0)
    {
        int w = selIndex;
        float2 n = brWallNormal(w);
        float plane = brWallPlane(r, w);
        float2 e = brWallExtent(r, w);
        float along = brWallAlongX(w) ? wp.x : wp.y;
        float d = brWallAlongX(w) ? (wp.y - plane) * n.y : (wp.x - plane) * n.x;
        if (along >= e.x && along <= e.y) ink(col, PT_ACCENT, cm(abs(d), 3.0));
    }

    // openings in plan (one exit per iteration: no mid-body `continue`)
    [loop] for (int j = 0; j < SHELL_OPEN_MAX; j++)
    {
        BROpening o = opening(j);
        bool sel = (selType == 1 && selIndex == j);
        bool hov = (hoverIndex == j);
        float3 lc = (o.alarms != 0) ? PT_ALARM : (sel ? PT_ACCENT : (hov ? PT_INK : PT_MID));
        float lw = sel ? 1.6 : 1.1;
        float along = brWallAlongX(o.wall) ? wp.x : wp.y;
        float2 n = brWallNormal(o.wall);
        float plane = brWallPlane(r, o.wall);
        float d = brWallAlongX(o.wall) ? (wp.y - plane) * n.y : (wp.x - plane) * n.x;
        float hw = o.width * 0.5;
        float u = along - o.a;
        bool isNear = o.active && !(abs(u) > hw + 1.2 || d < -T - 0.1 || d > max(o.width, 1.2) + 0.2);
        float2 q = float2(u, d);   // local: x along wall (from centre), y into the room

        if (isNear && o.kind == OPEN_FIREPLACE)
        {
            float dep = o.depth;
            float inBreast = rectIn(q, float2(-hw, 0), float2(hw, dep));
            float fb = o.cols * 0.5;
            float inBox = rectIn(q, float2(-fb, dep - 0.42), float2(fb, dep));
            ink(col, PT_RULE * 0.55, inBreast * (1.0 - inBox));
            ink(col, PT_RULE * 1.5, inBreast * (1.0 - inBox) * dHatch(P, 5.0 * gUi, 0.785, 1.0));
            ink(col, PT_FIELD, inBox);
            ink(col, lc, rectLine(q, float2(-hw, 0), float2(hw, dep), lw));
            ink(col, lc, rectLine(q, float2(-fb, dep - 0.42), float2(fb, dep), lw * 0.8));
            ink(col, lc, dRectDash(P, shellRectOf(shellPlanPx(L, brWallPoint(r, o.wall, o.a - hw - 0.12, dep)), shellPlanPx(L, brWallPoint(r, o.wall, o.a + hw + 0.12, dep + 0.48))), 1.0, 5.0, 4.0) * 0.9);
        }
        else if (isNear && o.kind == OPEN_ARCH)
        {
            float onSpan = step(abs(u), hw);
            float dash = step(fmod(abs(u) * gS, 9.0), 5.0);
            ink(col, lc, onSpan * dash * max(cm(abs(d), lw), cm(abs(d + T), lw)));
            ink(col, lc, step(-T, d) * step(d, 0.0) * cm(abs(abs(u) - hw), lw));
        }
        else if (isNear)
        {
            // jambs
            ink(col, lc, step(-T, d) * step(d, 0.0) * cm(abs(abs(u) - hw), lw));
            if (brOpenIsGlazed(o.kind) && o.kind != OPEN_FRENCH)
            {
                float onSpan = step(abs(u), hw);
                ink(col, lc, onSpan * cm(abs(d + T * 0.5 - 0.018), lw * 0.8));
                ink(col, lc, onSpan * cm(abs(d + T * 0.5 + 0.018), lw * 0.8));
                ink(col, lc, step(abs(u), hw + 0.07) * cm(abs(d - 0.035), lw * 0.8));      // stool
                if (o.radiator && (r.flags & ROOM_FLAG_RADIATORS) != 0)
                    ink(col, PT_DIM, rectLine(q, float2(-hw + 0.06, 0.05), float2(hw - 0.06, 0.15), 1.0));
            }
            else
            {
                // doors swing into the room: single leaf hinged at the low end, French as a pair
                int leaves = (o.kind == OPEN_FRENCH) ? 2 : 1;
                float leafW = o.width / (float)leaves;
                [unroll] for (int lf = 0; lf < 2; lf++)
                {
                    float hx = (lf == 0) ? -hw : hw;
                    float2 hinge = float2(hx, 0);
                    float2 leafEnd = float2(hx, leafW);
                    float2 rel = q - hinge;
                    float ang = atan2(rel.y, rel.x * ((lf == 0) ? 1.0 : -1.0));
                    float onArc = step(0.0, ang) * step(ang, 1.5708);
                    float on = (lf < leaves) ? 1.0 : 0.0;
                    ink(col, lc, segM(q, hinge, leafEnd, lw * 1.2) * on);
                    ink(col, lc, onArc * cm(abs(length(rel) - leafW), 0.9) * 0.8 * on);
                }
                if (o.kind == OPEN_FRENCH)
                {
                    float onSpan = step(abs(u), hw);
                    ink(col, lc, onSpan * cm(abs(d + T * 0.5), lw * 0.7));
                }
            }
            if (o.curtains && (r.flags & ROOM_FLAG_CURTAINS) != 0)
            {
                float span = hw + 0.36;
                float wave = 0.10 + 0.022 * sin(u * 42.0);
                float slope = 0.022 * 42.0 * cos(u * 42.0);
                float dd = abs(d - wave) / sqrt(1.0 + slope * slope);
                ink(col, sel ? PT_ACCENT * 0.8 : PT_RULE * 1.8, step(abs(u), span) * cm(dd, 1.0));
            }
        }
    }
}

// ---------------------------------------------------------------------------------------------

// The opening under the pointer (the reducer's own pick order: smallest elevation footprint, then
// a plan cut), so a hovered opening lifts a value step in both views.
int hoverOpening(float2 ptr, ShellLayout L, BRRoom r)
{
    int best = -1; float bestArea = 1e12;
    [loop] for (int i = 0; i < SHELL_OPEN_MAX; i++)
    {
        BROpening o = opening(i);
        float4 er = shellOpenElevRect(L, o.wall, o.a, o.width, o.sill, o.height);
        float area = (er.z - er.x) * (er.w - er.y);
        if (o.active && shellInRect(ptr, er, 2.0) && area < bestArea) { bestArea = area; best = i; }
        float depthIn = (o.kind == OPEN_FIREPLACE) ? o.depth + 0.5 : 0.25;
        float4 pr = shellPlanBand(L, r, o.wall, o.a - o.width * 0.5, o.a + o.width * 0.5, depthIn, -r.T);
        if (o.active && best < 0 && shellInRect(ptr, pr, 3.0)) best = i;
    }
    return best;
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint W, Hh;
    OutputUAV.GetDimensions(W, Hh);
    if (tid.x >= W || tid.y >= Hh) return;
    float2 res = float2(W, Hh);
    float2 P = float2(tid.xy) + 0.5;

    BRRoom r = brRoomFromRec(ShellBuf[SHELL_ROOM]);
    BRRec ed = ShellBuf[SHELL_EDITOR];
    BRRec fz = ShellBuf[14];
    int selType = (int)round(ed.head.y);
    int selIndex = (int)round(ed.head.z);

    ShellLayout L = shellLayout(res, r, fz.dims, fz.look.zw);
    gS = L.s; gUi = L.ui;
    float3 col = PT_FIELD;
    int hov = hoverOpening(_ViewportPointerPosition * res, L, r);

    drawPlan(col, P, L, r, selType, selIndex, hov);
    [loop] for (int w = 0; w < 4; w++) drawElevation(col, P, L, r, w, selType, selIndex, hov);
    OutputUAV[tid.xy] = float4(saturate(col), 1.0);
}
