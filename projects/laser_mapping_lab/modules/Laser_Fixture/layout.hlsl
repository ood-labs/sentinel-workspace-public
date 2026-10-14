// Laser_Fixture / layout - the Plan and Elevation canvas's words, rulers, readouts, the hover
// inspector and the verb, recorded for the shared UI kit (ui.hlsl draws them over preview).
//
// Every figure is the module's own: its Fixtures records (pose, aim, power, emission), the beams it
// just published (World Scan) and its scan parameters. Where the beams land on the wall is reduced
// by all 64 threads at once, and the inspected record is the lit beam nearest the pointer in
// whichever drawing it is over (an aperture under the pointer wins). Hover is a read of the
// pointer snapshot and is never stored. The rects and the room -> canvas mapping are
// lf_view.hlsli's, the ones preview.hlsl draws with.
//
// Threads: (1) all 64 reduce the beams (lit count, where they land) and search them for the one
// under the pointer; (2) thread 0 records the canvas.
struct Beam { float4 origin; float4 direction0; float4 direction1; float4 color0; float4 color1; float4 timing; float4 meta; };
struct Fixture { float4 aperture; float4 right; float4 up; float4 forward; float4 emission; };
StructuredBuffer<Beam> Beams : register(t0);       // World Scan: [0] header, [1..n] beam pieces
StructuredBuffer<Fixture> Fx : register(t1);       // Fixtures: [0] header, [1..4] apertures
#include "pose.hlsli"
#include "lf_view.hlsli"
#include "_labels.generated.hlsli"
#include "../_shared/ui/il_ui.hlsli"

groupshared uint gsNear;                           // the nearest lit beam: (distance in 1/16 px << 12) | index
groupshared uint gsLit;                            // lit pieces
groupshared uint gsHits;                           // beam ends that land on the wall
groupshared uint gsLoX, gsLoY, gsHiX, gsHiY;       // where they land, lfEnc-coded

static LFLayout g_L;
static float g_s;
static float2 g_res;

uint  lfEnc(float v) { return (uint)((clamp(v, -60.0, 60.0) + 64.0) * 1000.0); }    // 1 mm steps
float lfDec(uint u)  { return (float)u / 1000.0 - 64.0; }
uint  beamCount()    { return min((uint)max(Beams[0].origin.x, 0.0), 4095u); }
uint  fixtureCount() { return (uint)clamp(projector_count, 1, 4); }
bool  isLit(Beam b)  { return b.timing.w <= 0.5 && b.timing.y > 0.0; }
// a direction's yaw and pitch in degrees: the inverse of pose.hlsli's orientFixture
float2 yawPitch(float3 d) { return float2(degrees(atan2(d.x, d.z)), degrees(asin(clamp(d.y, -1.0, 1.0)))); }

// ---------------------------------------------------------------- header: title, input, scanner
void header()
{
    float s = g_s;
    float hy = 0.5 * g_L.head.w;
    float cap = IL_T_TITLE * s;
    float x = 12.0 * s;
    x += dlLabel(LB_TITLE, x, hy, 14.0 * s, IL_INK, IL_LEFT) + 10.0 * s;
    float subEnd = x + ilLabelW(LB_SUBTITLE, 12.0 * s);
    uint inL = LB_IN_0;
    if (input_is_sent_stream) inL = LB_IN_1;
    uint mdL = LB_MODEL_0 + (uint)clamp(scanner_model, 0, 1);
    float need = ilLabelW(LB_INPUT, cap) + ilLabelW(inL, IL_T_BODY * s) + ilLabelW(LB_MODEL, cap) + ilLabelW(mdL, IL_T_BODY * s) + 30.0 * s;
    float rx = g_L.head.z - 12.0 * s;
    if (rx - need > subEnd + 16.0 * s)
    {
        rx -= dlLabel(mdL, rx, hy, IL_T_BODY * s, IL_INK, IL_RIGHT) + 6.0 * s;
        rx -= dlLabel(LB_MODEL, rx, hy, cap, IL_DIM, IL_RIGHT) + 18.0 * s;
        rx -= dlLabel(inL, rx, hy, IL_T_BODY * s, IL_INK, IL_RIGHT) + 6.0 * s;
        dlLabel(LB_INPUT, rx, hy, cap, IL_DIM, IL_RIGHT);
    }
    dlLabel(LB_SUBTITLE, x, hy, 12.0 * s, IL_DIM, IL_LEFT);
}

// ---------------------------------------------------------------- the plates and their furniture
// Edges and captions (preview.hlsl fills them), the metre rulers, WALL and FLOOR, the apertures'
// names, and where the beams land: an ink span on the wall face in each drawing.
void plates(uint hits, float2 lo, float2 hi)
{
    float s = g_s, k = g_L.k;
    float cap = IL_T_CAP * s;
    [loop] for (uint v = 0u; v < 2u; v++)
    {
        float4 p = v == 0u ? g_L.plan : g_L.elev;
        dlBorderRect(p, IL_RADIUS * s, IL_EDGE, 1.0);
        float cy = p.y + 11.0 * s;
        float w = dlLabel(LB_PLAN + 2u * v, p.x + 10.0 * s, cy, IL_T_TITLE * s, IL_DIM, IL_LEFT);
        dlLabelFit(LB_PLAN_D + 2u * v, p.x + 18.0 * s + w, cy, cap, IL_DIM, IL_LEFT, p.z - p.x - 28.0 * s - w);
    }

    // z along the elevation's foot, every metre (every second when they would crowd)
    int st = k < 24.0 * s ? 2 : 1;
    int zA = (int)ceil(lfZAt(g_L, g_L.elevD.x + 6.0 * s) / (float)st) * st;
    int zB = (int)floor(lfZAt(g_L, g_L.elevD.z - 6.0 * s));
    float ry = g_L.elevD.w + 8.0 * s;
    [loop] for (int z = zA; z <= zB && z <= zA + 80; z += st)
        dlInt(z, 1, lfZPx(g_L, (float)z), ry, cap, IL_DIM, IL_CENTER);
    // x up the plan's left edge, y up the elevation's
    int sv = k < 15.0 * s ? 2 : 1;
    float lx = g_L.planD.x - 5.0 * s;
    float hh = 0.5 * (g_L.planD.w - g_L.planD.y) / k;
    int xA = (int)ceil(g_L.xMid - hh + 0.15), xB = (int)floor(g_L.xMid + hh - 0.15);
    [loop] for (int xm = xA; xm <= xB && xm <= xA + 80; xm++)
        if ((abs(xm) % sv) == 0) dlInt(xm, 1, lx, lfPlanPx(g_L, float3((float)xm, 0.0, 0.0)).y, cap, IL_DIM, IL_RIGHT);
    float top = g_L.yLo + (g_L.elevD.w - g_L.elevD.y) / k;
    int yA = (int)ceil(g_L.yLo + 0.15), yB = (int)floor(top - 0.15);
    [loop] for (int ym = yA; ym <= yB && ym <= yA + 80; ym++)
        if ((abs(ym) % sv) == 0) dlInt(ym, 1, lx, lfElevPx(g_L, float3(0.0, (float)ym, 0.0)).y, cap, IL_DIM, IL_RIGHT);

    float wx = lfZPx(g_L, 0.0);
    dlLabel(LB_WALL, wx + 6.0 * s, g_L.planD.y + 8.0 * s, cap, IL_DIM, IL_LEFT);
    dlLabel(LB_FLOOR, g_L.elevD.z - 6.0 * s, lfElevPx(g_L, float3(0.0, 0.0, 0.0)).y - 8.0 * s, cap, IL_DIM, IL_RIGHT);

    // where the lit beams land: their extent across the wall (plan) and up it (elevation)
    if (hits > 0u)
    {
        dlClip(g_L.planD);
        float ya = lfPlanPx(g_L, float3(lo.x, 0.0, 0.0)).y, yb = lfPlanPx(g_L, float3(hi.x, 0.0, 0.0)).y;
        dlRect(float4(wx - 1.5 * s, min(ya, yb) - 0.5, wx + 1.5 * s, max(ya, yb) + 0.5), IL_INK, 1.0, 1.0);
        dlClip(g_L.elevD);
        ya = lfElevPx(g_L, float3(0.0, lo.y, 0.0)).y;
        yb = lfElevPx(g_L, float3(0.0, hi.y, 0.0)).y;
        dlRect(float4(wx - 1.5 * s, min(ya, yb) - 0.5, wx + 1.5 * s, max(ya, yb) + 0.5), IL_INK, 1.0, 1.0);
        dlClipReset();
    }

    // each aperture named beside its dot: FIXTURE, or its number in a bank
    uint nf = fixtureCount();
    [loop] for (uint f = 0u; f < nf; f++)
    {
        [loop] for (uint e = 0u; e < 2u; e++)
        {
            bool el = e == 1u;
            float4 D = el ? g_L.elevD : g_L.planD;
            float2 a = lfPx(g_L, apertureFor(f), el);
            if (!ilIn(a, D)) continue;
            dlClip(D);
            if (nf == 1u)
            {
                bool right = a.x + 8.0 * s + ilLabelW(LB_FIXTURE, cap) <= D.z;
                dlLabel(LB_FIXTURE, right ? a.x + 8.0 * s : a.x - 8.0 * s, a.y - 10.0 * s, cap, IL_MID, right ? IL_LEFT : IL_RIGHT);
            }
            else dlInt((int)f + 1, 1, a.x + 8.0 * s, a.y - 10.0 * s, IL_T_VALUE * s, IL_MID, IL_LEFT);
            dlClipReset();
        }
    }
}

// ---------------------------------------------------------------- the readout panes
// FIXTURE: fixture 1's record (where it stands, where it aims, how far), and the scan field.
// BEAMS: how many pieces are lit, and how big and where the picture they make on the wall is.
// Ten rows, one loop so the number formatter compiles once; captions R_X .. R_CENTRE run in this
// order in labels.txt.
void panes(uint total, uint litN, uint hits, float2 lo, float2 hi)
{
    float s = g_s;
    uint nf = fixtureCount();
    float4 p0 = lfPane(g_L, 0u), p1 = lfPane(g_L, 1u);
    if (p0.w > p0.y)
    {
        dlPane(p0, s, LB_FIXTURE, false);
        if (nf > 1u)
        {
            float4 hd = ilPaneHead(p0, s);
            float hy = ilMid(hd).y, rx = hd.z - 10.0 * s;
            rx -= dlInt((int)nf, 1, rx, hy, IL_T_VALUE * s, IL_MID, IL_RIGHT) + 4.0 * s;
            rx -= dlLabel(LB_OF, rx, hy, IL_T_CAP * s, IL_DIM, IL_RIGHT) + 4.0 * s;
            dlInt(1, 1, rx, hy, IL_T_VALUE * s, IL_INK, IL_RIGHT);
        }
    }
    if (p1.w > p1.y) dlPane(p1, s, LB_BEAMS, false);

    Fixture fx = Fx[1];
    float3 ap = fx.aperture.xyz, fw = fx.forward.xyz;
    float2 yp = yawPitch(fw);
    bool aims = fw.z < -1e-6;
    float throwM = 0.0;
    if (aims) throwM = -ap.z / fw.z;
    float2 aimAt = (ap + fw * throwM).xy;
    float2 size = hi - lo, mid = 0.5 * (lo + hi);
    [loop] for (uint r = 0u; r < 10u; r++)
    {
        float4 p = r < 7u ? p0 : p1;
        if (p.w <= p.y) continue;
        float y = lfRowY(g_L, p, r < 7u ? r : r - 7u);
        uint nums = 1u, unitL = LB_U_M, sepL = LB_U_COMMA, textL = 0xFFFFu;
        int dec = 2;
        float v0 = ap.x, v1 = 0.0;
        bool show = true;
        if (r == 1u) v0 = ap.y;
        else if (r == 2u) v0 = ap.z;
        else if (r == 3u) { nums = 2u; v0 = yp.x; v1 = yp.y; dec = 1; unitL = LB_U_DEG; }
        else if (r == 4u) { nums = 2u; v0 = aimAt.x; v1 = aimAt.y; if (!aims) textL = LB_MISS; }
        else if (r == 5u) { v0 = throwM; show = aims; }
        else if (r == 6u) { nums = 2u; v0 = scan_x; v1 = scan_y; dec = 1; sepL = LB_U_TIMES; unitL = LB_U_DEG; }
        else if (r == 7u) { nums = 2u; v0 = (float)litN; v1 = (float)total; dec = 0; sepL = LB_OF; unitL = 0xFFFFu; if (total == 0u) textL = LB_NO_SIGNAL; }
        else if (r == 8u) { nums = 2u; v0 = size.x; v1 = size.y; sepL = LB_U_TIMES; show = total > 0u; if (hits == 0u) textL = LB_NO_WALL; }
        else if (r == 9u) { nums = 2u; v0 = mid.x; v1 = mid.y; show = hits > 0u; }
        if (!show) continue;
        float x1 = p.z - 10.0 * s, xr = x1;
        if (textL != 0xFFFFu) xr -= dlLabel(textL, x1, y, IL_T_BODY * s, IL_DIM, IL_RIGHT);
        else
        {
            if (unitL != 0xFFFFu) xr -= dlLabel(unitL, xr, y, IL_T_CAP * s, IL_DIM, IL_RIGHT) + 4.0 * s;
            [loop] for (uint q = 0u; q < nums; q++)
            {
                if (q > 0u) xr -= 8.0 * s + dlLabel(sepL, xr - 4.0 * s, y, IL_T_CAP * s, IL_DIM, IL_RIGHT);
                xr -= dlNum(q + 1u == nums ? v0 : v1, dec, xr, y, IL_T_VALUE * s, IL_INK, IL_RIGHT);
            }
        }
        dlLabelFit(LB_R_X + r, p.x + 10.0 * s, y, IL_T_BODY * s, IL_DIM, IL_LEFT, xr - p.x - 16.0 * s);
    }
}

// ---------------------------------------------------------------- the inspector
// One card for either record, so its row loop (and the number formatter) compiles once:
//   a beam: which piece of how many, its colours at both ends, where it lands and where its sweep
//           ends on the wall, how long the sweep is, when in the cycle it is drawn and for how long
//           (and which fixture drew it, in a bank)
//   a fixture: which one, its emitted colour, where it stands, its aim, where the aim lands, its
//           power and how much it is emitting
// The record lifts to ink in both drawings: its ray to where it lands, ringed there.
void inspect(bool isFx, uint idx, uint total, float2 at)
{
    float s = g_s;
    uint nf = fixtureCount();
    Beam b = Beams[isFx ? 0u : idx];
    Fixture fx = Fx[isFx ? idx + 1u : 1u];
    float inv = 1.0 / max(power, 0.001);
    float3 o = isFx ? fx.aperture.xyz : b.origin.xyz;
    float3 d0 = isFx ? fx.forward.xyz : b.direction0.xyz;
    float3 d1 = isFx ? d0 : b.direction1.xyz;
    float range = isFx ? 1e4 : b.direction1.w;
    bool l0 = lfLands(o, d0, range), l1 = lfLands(o, d1, range);
    bool dwell = isFx || length(d1 - d0) < 1e-5;
    float3 h0 = o + d0 * lfReach(o, d0, range), h1 = o + d1 * lfReach(o, d1, range);
    [loop] for (uint v = 0u; v < 2u; v++)
    {
        bool el = v == 1u;
        dlClip(el ? g_L.elevD : g_L.planD);
        float2 a = lfPx(g_L, o, el), e0 = lfPx(g_L, h0, el), e1 = lfPx(g_L, h1, el);
        if (!dwell) dlLine(a, e1, 1.0 * s, IL_MID, 1.0);
        dlLine(a, e0, 1.75 * s, IL_INK, 1.0);
        if (l0) dlRing(e0, 4.0 * s, 1.25 * s, IL_INK, 1.0);
        if (isFx) dlRing(a, 7.0 * s, 1.5 * s, IL_INK, 1.0);
        dlClipReset();
    }
    if (tooltips == 0) return;                   // Tooltips off: the record still lifts, no card

    bool sweepRow = !isFx && l0 && l1 && !dwell;
    uint rows = isFx ? 5u : 4u + (sweepRow ? 1u : 0u) + (nf > 1u ? 1u : 0u);
    float w = 236.0 * s, hgt = (36.0 + 18.0 * (float)rows) * s;
    float x0 = at.x + 18.0 * s;
    if (x0 + w > g_res.x - 8.0 * s) x0 = at.x - 18.0 * s - w;
    float y0 = at.y + 18.0 * s;
    if (y0 + hgt > g_res.y - 8.0 * s) y0 = at.y - 18.0 * s - hgt;
    x0 = max(x0, 8.0 * s);
    y0 = max(y0, 8.0 * s);
    dlRectEdged(float4(x0, y0, x0 + w, y0 + hgt), IL_RAISE, 1.0, IL_RADIUS * s, IL_EDGE, 1.0);
    float ty = y0 + 15.0 * s, tx = x0 + 10.0 * s;
    tx += dlLabel(isFx ? LB_FIXTURE : LB_I_BEAM, tx, ty, IL_T_TITLE * s, IL_INK, IL_LEFT) + 5.0 * s;
    tx += dlInt((int)(isFx ? idx + 1u : idx), 1, tx, ty, IL_T_VALUE * s, IL_INK, IL_LEFT) + 5.0 * s;
    tx += dlLabel(LB_OF, tx, ty, IL_T_CAP * s, IL_DIM, IL_LEFT) + 5.0 * s;
    dlInt((int)(isFx ? nf : total), 1, tx, ty, IL_T_VALUE * s, IL_MID, IL_LEFT);
    // its own colours, pulled toward the instrument: a beam's start and end, a fixture's emission
    float rx = x0 + w - 10.0 * s;
    dlRect(float4(rx - 10.0 * s, ty - 6.0 * s, rx, ty + 6.0 * s), ptSampleColour((isFx ? fx.emission.rgb : b.color1.rgb) * inv), 1.0, 2.0 * s);
    if (!isFx) dlRect(float4(rx - 22.0 * s, ty - 6.0 * s, rx - 12.0 * s, ty + 6.0 * s), ptSampleColour(b.color0.rgb * inv), 1.0, 2.0 * s);
    dlHLine(y0 + 29.0 * s, x0 + 1.0, x0 + w - 1.0, IL_EDGE);

    float2 yp = yawPitch(d0);
    float cx = x0 + 10.0 * s, vx = x0 + w - 10.0 * s;
    float y = y0 + 44.0 * s;
    [loop] for (uint k = 0u; k < 6u; k++)
    {
        uint capL = LB_I_LANDS, unitL = LB_U_M, textL = 0xFFFFu, nums = 2u;
        int dec = 2;
        float v0 = h0.x, v1 = h0.y, v2 = 0.0;
        bool show = true;
        if (isFx)
        {
            if (k == 0u) { capL = LB_I_AT; nums = 3u; v0 = o.x; v1 = o.y; v2 = o.z; }
            else if (k == 1u) { capL = LB_I_AIM; v0 = yp.x; v1 = yp.y; dec = 1; unitL = LB_U_DEG; }
            else if (k == 2u) { if (!l0) textL = LB_MISS; }
            else if (k == 3u) { capL = LB_I_POWER; nums = 1u; v0 = fx.aperture.w; unitL = LB_U_REL; }
            else if (k == 4u) { capL = LB_I_EMIT; nums = 1u; v0 = ilLum(fx.emission.rgb); unitL = LB_U_REL; }
            else show = false;
        }
        else
        {
            if (k == 0u) { if (!l0) textL = LB_MISS; }
            else if (k == 1u) { capL = LB_I_SWEEPS; v0 = h1.x; v1 = h1.y; if (dwell) textL = LB_DWELL; else if (!l1) textL = LB_MISS; }
            else if (k == 2u) { capL = LB_I_LENGTH; nums = 1u; v0 = distance(h0.xy, h1.xy); show = sweepRow; }
            else if (k == 3u) { capL = LB_I_START; nums = 1u; v0 = b.timing.x * 1000.0; unitL = LB_U_MS; }
            else if (k == 4u) { capL = LB_I_LASTS; nums = 1u; v0 = b.timing.y * 1000.0; dec = 3; unitL = LB_U_MS; }
            else { capL = LB_I_FROM; nums = 1u; v0 = b.meta.w; dec = 0; unitL = 0xFFFFu; show = nf > 1u; }
        }
        if (!show) continue;
        dlLabel(capL, cx, y, IL_T_CAP * s, IL_DIM, IL_LEFT);
        if (textL != 0xFFFFu) dlLabel(textL, vx, y, IL_T_BODY * s, IL_DIM, IL_RIGHT);
        else
        {
            float xr = vx;
            if (unitL != 0xFFFFu) xr -= dlLabel(unitL, xr, y, IL_T_CAP * s, IL_DIM, IL_RIGHT) + 4.0 * s;
            [loop] for (uint q = 0u; q < nums; q++)
            {
                uint qi = nums - 1u - q;                 // right to left: the last number first
                if (q > 0u) xr -= 8.0 * s + dlLabel(LB_U_COMMA, xr - 4.0 * s, y, IL_T_CAP * s, IL_DIM, IL_RIGHT);
                xr -= dlNum(qi == 0u ? v0 : (qi == 1u ? v1 : v2), dec, xr, y, IL_T_VALUE * s, IL_INK, IL_RIGHT);
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
    float x = 12.0 * s;
    float kw = ilLabelW(LB_K_HOVER, IL_T_CAP * s) + 12.0 * s, kh = 18.0 * s;
    dlKeycap(float4(x, fy - 0.5 * kh, x + kw, fy + 0.5 * kh), s, LB_K_HOVER);
    dlLabel(LB_D_HOVER, x + kw + 6.0 * s, fy, IL_T_CAP * s, IL_DIM, IL_LEFT);
}

// ---------------------------------------------------------------- thread 0
void layout(uint total, float2 ptr, bool over, bool overE)
{
    dlBegin(g_res);
    uint litN = gsLit, hits = gsHits;
    float2 lo = float2(lfDec(gsLoX), lfDec(gsLoY)), hi = float2(lfDec(gsHiX), lfDec(gsHiY));
    header();
    plates(hits, lo, hi);
    panes(total, litN, hits, lo, hi);
    if (over)
    {
        // an aperture under the pointer wins over the beams it emits
        int fxHit = -1;
        uint nf = fixtureCount();
        [loop] for (uint f = 0u; f < nf; f++)
            if (fxHit < 0 && length(ptr - lfPx(g_L, apertureFor(f), overE)) < 9.0 * g_s) fxHit = (int)f;
        bool isFx = fxHit >= 0;
        uint idx = gsNear & 4095u;
        if (isFx) idx = (uint)fxHit;
        if (isFx || gsNear != 0xFFFFFFFFu) inspect(isFx, idx, total, ptr);
    }
    footer();
    dlFinish();
}

[numthreads(IL_LAYOUT_THREADS, 1, 1)]
void main(uint gi : SV_GroupIndex)
{
    g_res = _Resolution.xy;
    g_L = lfLayout(g_res);
    g_s = g_L.s;

    if (gi == 0u)
    {
        gsNear = 0xFFFFFFFFu;
        gsLit = 0u;
        gsHits = 0u;
        gsLoX = 0xFFFFFFFFu;
        gsLoY = 0xFFFFFFFFu;
        gsHiX = 0u;
        gsHiY = 0u;
    }
    GroupMemoryBarrierWithGroupSync();

    // 1. every thread: the lit pieces, where they land, and the one under the pointer (only while
    //    the pointer is over one of the drawings)
    float2 pn = _ViewportPointerPosition;
    float2 ptr = pn * g_res;
    bool inside = all(pn >= 0.0) && all(pn <= 1.0);
    bool overE = inside && ilIn(ptr, g_L.elevD);
    bool over = overE || (inside && ilIn(ptr, g_L.planD));
    float reach = 6.0 * g_s;
    uint total = beamCount();
    uint litN = 0u, hits = 0u;
    float2 lo = float2(1e9, 1e9), hi = float2(-1e9, -1e9);
    [loop] for (uint i = 1u + gi; i <= total; i += IL_LAYOUT_THREADS)
    {
        Beam b = Beams[i];
        if (!isLit(b)) continue;
        litN++;
        float3 o = b.origin.xyz;
        float range = b.direction1.w;
        [unroll] for (uint e = 0u; e < 2u; e++)
        {
            float3 d = e == 0u ? b.direction0.xyz : b.direction1.xyz;
            if (lfLands(o, d, range))
            {
                float2 h = (o + d * (-o.z / d.z)).xy;
                lo = min(lo, h);
                hi = max(hi, h);
                hits++;
            }
        }
        if (over)
        {
            float3 d = b.direction0.xyz;
            float dist = ilSdSeg(ptr, lfPx(g_L, o, overE), lfPx(g_L, o + d * lfReach(o, d, range), overE));
            if (dist < reach) InterlockedMin(gsNear, (min((uint)(dist * 16.0), 0xFFFFFu) << 12) | i);
        }
    }
    InterlockedAdd(gsLit, litN);
    if (hits > 0u)
    {
        InterlockedAdd(gsHits, hits);
        InterlockedMin(gsLoX, lfEnc(lo.x));
        InterlockedMin(gsLoY, lfEnc(lo.y));
        InterlockedMax(gsHiX, lfEnc(hi.x));
        InterlockedMax(gsHiY, lfEnc(hi.y));
    }
    GroupMemoryBarrierWithGroupSync();

    // 2. thread 0: the canvas
    if (gi == 0u) layout(total, ptr, over, overE);
    dlEnd(gi);
}
