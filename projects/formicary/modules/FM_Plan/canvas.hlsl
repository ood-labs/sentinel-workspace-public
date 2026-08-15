// FM_Plan / canvas.hlsl — the draughtsman's drawing of the arrangement.
//
// Plan over route diagram. See layout.hlsli for why there are two strips and what the second
// one is for. This file only DRAWS; every number on it is read back out of the plan buffer or
// out of a live measurement fed in from FM_Colony, and nothing here decides anything.
//
// Styling follows the shared instrument palette: mostly monochrome, hue only where it carries
// information. The four uses in this canvas, each nameable:
//   ACCENT   the current selection, and the measured live readings
//   ALARM    a route that passes through an obstacle or leaves the arena
//   IDENTITY food kind — three kinds all drawn as discs, so shape cannot tell them apart
//   RAMP     payload rank and recruitment weight, which are ordinal, so no hue is spent on them
#include "../_shared/formic.hlsli"
#include "../_shared/plan_theme.hlsli"
#include "../_shared/microfont.hlsli"
#include "layout.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);
StructuredBuffer<FmRec> Plan : register(t0);

// letters: A=10 ... Z=35, digits 0-9 = 0-9, '-'=36 '.'=37 '/'=38 ':'=39 '+'=40 '>'=41
#define GA 10u
#define GB 11u
#define GC 12u
#define GD 13u
#define GE 14u
#define GF 15u
#define GG 16u
#define GH 17u
#define GI 18u
#define GK 20u
#define GL 21u
#define GM 22u
#define GN 23u
#define GO 24u
#define GP 25u
#define GR 27u
#define GS 28u
#define GT 29u
#define GU 30u
#define GV 31u
#define GX 33u
#define GY 34u
#define GDASH 36u
#define GDOT  37u
#define GCOL  39u

// A label anchored at its left edge. `h` is the glyph cell height in pixels; the advance
// includes the font's one column of tracking, so a rendered string's width is predictable and
// two labels stacked in a column line up.
float fmLabel(float2 px, float2 org, float h, uint2 packed, uint count)
{
    float cw = h * (5.0 / 7.0) * 1.2;
    float2 lp = (px - org) / float2(cw * (float)count, h);
    return mf_text(lp, packed, count);
}

float fmLabelW(float h, uint count) { return h * (5.0 / 7.0) * 1.2 * (float)count; }

// A right-aligned fixed-width integer. Leading zeros are kept deliberately: a fixed-width
// reading does not reflow as the value changes, which is what stops a column of numbers
// twitching sideways while the colony walks.
float fmNumR(float2 px, float2 rightOrg, float h, uint value, uint digits)
{
    float cw = h * (5.0 / 7.0) * 1.2;
    float2 lp = (px - (rightOrg - float2(cw * (float)digits, 0.0))) / float2(cw * (float)digits, h);
    return mf_num(lp, value, digits);
}

// Fixed-point: value shown with two decimals as NNN.DD. Built from two integer fields plus a
// dot so it needs no float formatting, and it never loses its decimal point to rounding.
float fmFixed(float2 px, float2 org, float h, float value, uint intDigits)
{
    float cw = h * (5.0 / 7.0) * 1.2;
    float v = max(value, 0.0);
    uint ip = (uint)floor(v);
    uint fp = (uint)floor(frac(v) * 100.0 + 0.5);
    if (fp >= 100u) { fp = 0u; ip += 1u; }

    float m = 0.0;
    m = max(m, mf_num((px - org) / float2(cw * (float)intDigits, h), ip, intDigits));
    float2 dOrg = org + float2(cw * (float)intDigits, 0.0);
    m = max(m, mf_glyph((px - dOrg) / float2(cw, h) * float2(1.2, 1.0), GDOT));
    float2 fOrg = dOrg + float2(cw, 0.0);
    m = max(m, mf_num((px - fOrg) / float2(cw * 2.0, h), fp, 2u));
    return m;
}

// Quadratic Bezier distance. Analytic rather than a polyline scan: ten routes sampled at 48
// points each would be 480 segment tests per pixel, which is a frame-rate cliff on a canvas
// this size, and the polyline also visibly facets the bends — which are exactly the parts of a
// route the diagram exists to show.
float fmBezierDist(float2 pos, float2 A, float2 B, float2 C)
{
    float2 a = B - A;
    float2 b = A - 2.0 * B + C;
    float2 c = a * 2.0;
    float2 d = A - pos;

    // Degenerate: control on the chord makes b vanish and kk explode. A straight route is the
    // common case (meander 0), so this branch is not an edge case, it is the default.
    if (dot(b, b) < 1e-6) return fmSegDist(pos, A, C);

    float kk = 1.0 / dot(b, b);
    float kx = kk * dot(a, b);
    float ky = kk * (2.0 * dot(a, a) + dot(d, b)) / 3.0;
    float kz = kk * dot(d, a);

    float res;
    float p = ky - kx * kx;
    float q = kx * (2.0 * kx * kx - 3.0 * ky) + kz;
    float h = q * q + 4.0 * p * p * p;

    if (h >= 0.0)
    {
        h = sqrt(h);
        float2 x = (float2(h, -h) - q) / 2.0;
        float2 uv = sign(x) * pow(abs(x), float2(1.0 / 3.0, 1.0 / 3.0));
        float t = saturate(uv.x + uv.y - kx);
        float2 w = d + (c + b * t) * t;
        res = dot(w, w);
    }
    else
    {
        float z = sqrt(-p);
        float v = acos(q / (p * z * 2.0)) / 3.0;
        float m = cos(v), n = sin(v) * 1.7320508;
        float3 t = saturate(float3(m + m, -n - m, n - m) * z - kx);
        float2 w0 = d + (c + b * t.x) * t.x;
        float2 w1 = d + (c + b * t.y) * t.y;
        res = min(dot(w0, w0), dot(w1, w1));
    }
    return sqrt(res);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 px = (float2)pixel + 0.5;
    float2 res = _Resolution.xy;

    FmRec hdr   = Plan[FM_HEADER];
    FmRec arena = Plan[FM_ARENA];
    uint  lanes = max((uint)hdr.kind, 1u);
    float maxRoute = max(hdr.p3, 1.0);
    uint  selSlot = (hdr.pos.y > 0.5) ? (uint)(hdr.pos.y - 1.0) : 0xffffffffu;

    FmLayout L = fmLayout(res, arena, maxRoute, lanes);

    float3 col = PT_FIELD;

    // Uniform hairline weight across the whole instrument. One number, so a rule in the plan
    // strip and a rule in the flow strip cannot end up different weights.
    float hair = max(res.x / 1200.0, 0.75);

    // ---------------------------------------------------------------------------
    // TITLE BAND
    // ---------------------------------------------------------------------------
    float titleY = FM_TITLE_B * res.y;
    if (px.y < titleY)
    {
        float th = 11.0 * hair;
        float2 org = float2(FM_DRAW_L * res.x, titleY * 0.5 - th * 0.5);
        // "FORMICARY"
        float m = fmLabel(px, org, th, uint2(mf_pack1(GF, GO, GR, GM, GI), mf_pack1(GC, GA, GR, GY, 0u)), 9u);
        col = fmInk(col, PT_INK, m);

        // The arrangement is drawn as a fixed caption plus a RANK rather than spelled out: four
        // enum names of four different widths make the whole header reflow every time the enum
        // changes, and a header that moves is a header you stop reading.
        float2 org2 = org + float2(fmLabelW(th, 9u) + 22.0 * hair, 0.0);
        float th2 = th * 0.82;
        col = fmInk(col, PT_DIM, fmLabel(px, org2, th2,
                    uint2(mf_pack1(GA, GR, GR, GA, GN), mf_pack1(GG, GE, 0u, 0u, 0u)), 7u));
        col = fmInk(col, PT_MID, fmNumR(px, org2 + float2(fmLabelW(th2, 10u), 0.0), th2, (uint)arrangement, 2u));
    }
    col = fmInk(col, PT_RULE, fmLineMask(px, float2(FM_DRAW_L * res.x, titleY),
                                         float2(FM_COL_R * res.x, titleY), hair));

    // ---------------------------------------------------------------------------
    // PLAN STRIP — the arena from above.
    // ---------------------------------------------------------------------------
    float2 planLo = float2(FM_DRAW_L * res.x, FM_PLAN_T * res.y);
    float2 planHi = float2(FM_DRAW_R * res.x, FM_PLAN_B * res.y);

    if (px.x >= planLo.x && px.x <= planHi.x && px.y >= planLo.y && px.y <= planHi.y)
    {
        float2 w = fmPxToPlan(L, px);                       // world millimetres
        float2 half = fmArenaHalf(arena);
        bool inArena = (abs(w.x) <= half.x && abs(w.y) <= half.y);

        if (inArena) col = PT_WELL;

        // A 10 mm grid. The ruler of the whole drawing, and the reason a twig reads as 18 mm
        // long rather than "quite long".
        if (inArena)
        {
            float2 g = abs(frac(w / 10.0 + 0.5) - 0.5) * 10.0 * L.scale;
            float gm = 1.0 - smoothstep(0.0, hair * 1.1, min(g.x, g.y));
            col = fmInk(col, PT_GRID, gm * 0.9);
            // every 50 mm, a heavier line
            float2 g5 = abs(frac(w / 50.0 + 0.5) - 0.5) * 50.0 * L.scale;
            float gm5 = 1.0 - smoothstep(0.0, hair * 1.2, min(g5.x, g5.y));
            col = fmInk(col, PT_GRID * 1.9, gm5 * 0.85);
        }

        // arena boundary. Sorted, because a negative page axis swaps the corners.
        float2 aLo, aHi; fmPlanBoxPx(L, -half, half, aLo, aHi);
        col = fmInk(col, PT_RULE, fmRectFrame(px, aLo, aHi, hair * 1.6));

        // --- obstacles. Drawn from the SAME signed distance function the colony steers on and
        // the field masks with, so a shape the drawing shows as solid is solid to an ant.
        for (uint oi = 0u; oi < FM_OBSTS; oi++)
        {
            FmRec o = Plan[FM_OBST_0 + oi];
            if (o.active < 0.5) continue;
            float d = fmObstDist(w, o, arena) * L.scale;
            uint fl = (uint)o.flags;
            bool selHere = (FM_OBST_0 + oi) == selSlot;

            float fill = 1.0 - smoothstep(-0.75, 0.75, d);
            float edge = 1.0 - smoothstep(hair * 0.8, hair * 1.8, abs(d));
            // Solid bodies stay grey — they are structure, not a reading. Value alone separates
            // them from the ground and the hatch says which is which.
            col = fmInk(col, PT_GRID * 2.2, fill * 0.85);
            col = fmInk(col, selHere ? PT_ACCENT : ((fl & F_EDITED) ? PT_MID : PT_RULE), edge);
        }

        // --- routes
        for (uint ei = 0u; ei < FM_EDGES; ei++)
        {
            FmRec r = Plan[FM_EDGE_0 + ei];
            if (r.active < 0.5) continue;
            uint fl = (uint)r.flags;
            bool blocked = (fl & F_BLOCKED) != 0u;
            bool selHere = (FM_EDGE_0 + ei) == selSlot;

            float2 A = fmRecWorld(Plan[(uint)r.p0], arena);
            float2 Cc = fmRecWorld(Plan[(uint)r.p1], arena);
            float2 Bm = (A + Cc) * 0.5 + float2(r.dims.x, r.dims.z);

            float dpx = fmBezierDist(w, A, Bm, Cc) * L.scale;

            // Width carries recruitment. It is ordinal, so it is spent on WEIGHT rather than on
            // hue: a heavily recruited trail is a thicker line, exactly as it would be drawn on
            // paper, and the accent stays available for the selection.
            //
            // The value stays in the MIDDLE of the ramp on purpose. A route is structure, not a
            // reading, and drawn at full ink it became the brightest thing on the canvas —
            // louder than the selection it is supposed to sit underneath.
            float wpx = lerp(0.9, 2.6, saturate(r.p2)) * hair;
            float m = 1.0 - smoothstep(wpx - 0.75, wpx + 0.75, dpx);

            float3 ink = blocked ? PT_ALARM : (selHere ? PT_ACCENT : ptRamp(0.10 + 0.42 * saturate(r.p2)));
            col = fmInk(col, ink, m);

            // Direction. A route with no arrow is a line between two things and says nothing
            // about which is the food; with ants that distinction is the entire behaviour, and
            // the flow strip below reads left to right on the assumption that it is known.
            for (uint ch = 0u; ch < 2u; ch++)
            {
                float tt = 0.28 + 0.44 * (float)ch;
                float2 cp = fmPlanToPx(L, fmRoutePoint(A, Cc, float2(r.dims.x, r.dims.z), tt));
                float2 tg = fmRouteTangent(A, Cc, float2(r.dims.x, r.dims.z), tt);
                float2 tp = float2(tg.x, tg.y);
                float2 np = float2(-tp.y, tp.x);
                float s = 6.0 * hair;
                float2 tipp = cp + tp * s;
                col = fmInk(col, ink, fmLineMask(px, tipp, cp - tp * s * 0.35 + np * s * 0.90, hair * 1.5));
                col = fmInk(col, ink, fmLineMask(px, tipp, cp - tp * s * 0.35 - np * s * 0.90, hair * 1.5));
            }

            // The failure mode, marked where it happens. A blocked route already draws red, but
            // red along its whole length says the route is wrong without saying WHERE, and the
            // where is the only part that tells you which obstacle to move.
            if (blocked && r.pad0 > 0.0)
            {
                float2 bp = fmPlanToPx(L, fmRoutePoint(A, Cc, float2(r.dims.x, r.dims.z), r.pad0));
                col = fmInk(col, PT_ALARM, fmRingMask(px, bp, 7.0 * hair, hair * 1.6));
                col = fmInk(col, PT_ALARM, fmLineMask(px, bp - 5.0 * hair, bp + 5.0 * hair, hair * 1.4));
                col = fmInk(col, PT_ALARM, fmLineMask(px, bp + float2(-5.0, 5.0) * hair, bp + float2(5.0, -5.0) * hair, hair * 1.4));
            }

            // The mid handle — the one thing that changes a route's shape, so it is drawn as a
            // grabbable object rather than implied.
            float2 hpx = fmPlanToPx(L, fmEdgeHandle(A, Cc, float2(r.dims.x, r.dims.z)));
            col = fmInk(col, selHere ? PT_ACCENT : PT_RULE, fmRingMask(px, hpx, 4.5 * hair, hair * 1.3));
        }

        // --- caches
        for (uint ci = 0u; ci < FM_CACHES; ci++)
        {
            FmRec r = Plan[FM_CACHE_0 + ci];
            if (r.active < 0.5) continue;
            uint fl = (uint)r.flags;
            bool selHere = (FM_CACHE_0 + ci) == selSlot;
            float2 c = fmPlanToPx(L, fmRecWorld(r, arena));
            float rad = max(r.dims.x, 0.4) * L.scale;

            // A cache is drawn as a PILE OF CRUMBS, not as another ringed disc. Shape has to do
            // the work here: the first pass drew nest and cache as concentric rings at similar
            // sizes and the two were indistinguishable at a glance, which is fatal in a diagram
            // whose whole subject is traffic between them.
            float3 kindInk = ptId((int)r.kind);
            float rr = max(rad, 3.0 * hair);
            col = fmInk(col, ptSampleFill(kindInk), fmDiscMask(px, c, rr) * 0.55);
            for (uint g = 0u; g < 7u; g++)
            {
                float ga = fmRnd2(g * 17u + 1u, r.seed) * 6.2831853;
                float gr = rr * (0.20 + 0.62 * sqrt(fmRnd2(g * 17u + 2u, r.seed)));
                float2 gp = c + float2(cos(ga), sin(ga)) * gr;
                col = fmInk(col, ptSampleColour(kindInk), fmDiscMask(px, gp, rr * 0.22 + hair * 0.6));
            }

            // Payload as a ring whose radius IS the pile: the same number the record stores and
            // the same number the renderer sizes the crumb pile from.
            col = fmInk(col, selHere ? PT_ACCENT : PT_INK,
                        fmRingMask(px, c, max(rad, 3.0 * hair) + 3.0 * hair, hair * 1.5));
            float payR = max(rad, 3.0 * hair) + 3.0 * hair + 5.0 * hair * saturate(r.p0);
            col = fmInk(col, ptRamp(saturate(r.p0)), fmRingMask(px, c, payR, hair));

            if ((fl & F_EDITED) != 0u)
                col = fmInk(col, PT_MID, fmRingMask(px, c, payR + 3.5 * hair, hair * 0.9) * 0.75);
        }

        // --- nest. A HOLE: punched out darker than the ground it sits in, ringed once, with a
        // radial spoil hatch around the rim. Nothing else on the drawing is darker than the
        // substrate, so the nest is identifiable by value alone even at thumbnail size.
        {
            FmRec r = Plan[FM_NEST];
            if (r.active > 0.5)
            {
                bool selHere = FM_NEST == selSlot;
                float2 c = fmPlanToPx(L, fmRecWorld(r, arena));
                float rad = max(max(r.dims.x, 0.5) * L.scale, 5.0 * hair);
                float3 ink = selHere ? PT_ACCENT : PT_INK;

                for (uint sp = 0u; sp < 12u; sp++)
                {
                    float sa = ((float)sp + 0.5) / 12.0 * 6.2831853;
                    float2 d0 = float2(cos(sa), sin(sa));
                    col = fmInk(col, PT_RULE, fmLineMask(px, c + d0 * rad * 1.12, c + d0 * rad * 1.52, hair) * 0.8);
                }
                col = fmInk(col, PT_FIELD, fmDiscMask(px, c, rad));
                col = fmInk(col, ink, fmRingMask(px, c, rad, hair * 1.8));
            }
        }

        // --- STATIONS. Drawn last of the placed records, because they are the layer you are
        // working ON: everything else is the arrangement they act upon.
        //
        // Each one is a REACH RING and a CENTRE GLYPH, and the split matters. The ring is the
        // radius the colony is actually steering on, drawn from the same fmStaRadius the walk
        // pass calls, so a station can never show a reach the ants are not obeying. The glyph is
        // what the station DOES, and it is a shape rather than a colour, because four saturated
        // hues on an instrument canvas is exactly the failure the palette rules warn about — the
        // diagram would out-shout the program image it exists to explain.
        //
        //   emitter    chevrons pointing OUT along the aim, inside an open mouth
        //   attractor  chevrons pointing IN
        //   repeller   a bar across, chevrons pointing away
        //   sink       a filled well, darker than the ground, like the nest
        for (uint si = 0u; si < FM_STAS; si++)
        {
            FmRec r = Plan[FM_STA_0 + si];
            if (r.active < 0.5) continue;

            uint fl = (uint)r.flags;
            bool selHere = (FM_STA_0 + si) == selSlot;
            float2 c = fmPlanToPx(L, fmRecWorld(r, arena));
            int k = (int)(r.kind + 0.5);
            int md = (int)(r.p1 + 0.5);
            float3 ink = selHere ? PT_ACCENT : PT_INK;

            // The reach, on the drawing's own millimetre ruler.
            float reach = fmStaRadius(r) * L.scale;
            col = fmInk(col, selHere ? PT_ACCENT : PT_RULE,
                        fmRingMask(px, c, reach, hair * (selHere ? 1.5 : 0.9)) * (selHere ? 1.0 : 0.7));

            // A pulsing station's reach ring is DASHED, so "this one beats" is visible in a
            // still frame rather than only in motion.
            if (md == 1 && (k == 1 || k == 2))
            {
                float ang = atan2(px.y - c.y, px.x - c.x);
                float dash = step(0.5, frac(ang * 5.7296));
                col = fmInk(col, PT_WELL, fmRingMask(px, c, reach, hair * 1.9) * dash * 0.9);
            }

            float g = 7.0 * hair;

            if (k == 3)
            {
                // SINK. A well: the only other thing on the drawing darker than the substrate is
                // the nest, and that is the right family — both are holes the colony goes into.
                col = fmInk(col, PT_FIELD, fmDiscMask(px, c, g * 1.05));
                col = fmInk(col, ink, fmRingMask(px, c, g * 1.05, hair * 1.6));
                for (uint q = 0u; q < 4u; q++)
                {
                    float a0 = ((float)q + 0.5) * 1.5707963;
                    float2 d0 = float2(cos(a0), sin(a0));
                    // arrows pointing IN, and short, so a sink never reads as an attractor
                    col = fmInk(col, ink, fmLineMask(px, c + d0 * g * 2.0, c + d0 * g * 1.25, hair * 1.3));
                }
                // A CONSUME sink is barred: what goes in does not come back to the pool.
                if (md == 1)
                    col = fmInk(col, PT_ALARM, fmLineMask(px, c + float2(-g, -g), c + float2(g, g), hair * 1.5));
            }
            else if (k == 0)
            {
                // EMITTER. An open mouth with the aim drawn as a real vector: this is the only
                // station whose ORIENTATION means anything, and a symmetric glyph would hide it.
                float aim = r.pos.y;
                float cone = clamp(r.dims.z, 0.0, 3.14159265);
                float2 av = float2(cos(aim), sin(aim));
                // The page axes flip the drawing, so an aim drawn from raw world components
                // would point the opposite way to where the ants actually go.
                av *= L.planAxis;

                col = fmInk(col, ink, fmRingMask(px, c, g, hair * 1.6));
                col = fmInk(col, ink, fmLineMask(px, c, c + av * g * 2.6, hair * 1.5));
                // the release cone, as two edges out to the reach
                float2 e0 = float2(cos(aim + cone), sin(aim + cone)) * L.planAxis;
                float2 e1 = float2(cos(aim - cone), sin(aim - cone)) * L.planAxis;
                col = fmInk(col, PT_RULE, fmLineMask(px, c, c + e0 * reach, hair * 0.8) * 0.6);
                col = fmInk(col, PT_RULE, fmLineMask(px, c, c + e1 * reach, hair * 0.8) * 0.6);

                // Mode, as structure rather than as a caption. RING releases around the rim, so
                // the rim is ticked; BURST is silent until fired, so the mouth is dashed.
                if (md == 2)
                    for (uint t2 = 0u; t2 < 12u; t2++)
                    {
                        float ta = ((float)t2 + 0.5) / 12.0 * 6.2831853;
                        float2 td = float2(cos(ta), sin(ta));
                        col = fmInk(col, PT_MID, fmLineMask(px, c + td * reach * 0.94, c + td * reach * 1.06, hair * 1.1));
                    }
                else if (md == 1)
                    col = fmInk(col, PT_WELL, fmRingMask(px, c, g, hair * 2.2) * step(0.5, frac(atan2(px.y - c.y, px.x - c.x) * 2.8648)));
            }
            else
            {
                // ATTRACTOR and REPELLER are the same glyph with the arrows reversed, because
                // they are the same thing with the sign reversed and pretending otherwise would
                // be inventing a distinction the physics does not have.
                bool pull = (k == 1);
                col = fmInk(col, ink, fmRingMask(px, c, g, hair * 1.5));
                for (uint q = 0u; q < 4u; q++)
                {
                    float a0 = ((float)q + 0.5) * 1.5707963;
                    float2 d0 = float2(cos(a0), sin(a0));
                    float2 near = c + d0 * g * 1.35;
                    float2 far  = c + d0 * g * 2.7;
                    col = fmInk(col, ink, fmLineMask(px, pull ? far : near, pull ? near : far, hair * 1.3));
                    // the head, at the pointed end
                    float2 tip = pull ? near : far;
                    float2 pn = float2(-d0.y, d0.x) * g * 0.42;
                    float2 bk = tip + (pull ? d0 : -d0) * g * 0.55;
                    col = fmInk(col, ink, fmLineMask(px, tip, bk + pn, hair * 1.1));
                    col = fmInk(col, ink, fmLineMask(px, tip, bk - pn, hair * 1.1));
                }
                if (!pull)
                    col = fmInk(col, ink, fmLineMask(px, c + float2(-g, 0), c + float2(g, 0), hair * 1.9));
            }

            // Strength, as a grey ordinal arc rather than a hue: it is a magnitude, and the
            // ramp is what magnitudes are drawn with everywhere else on this canvas.
            {
                float mag = (k == 0) ? saturate(r.p0 / 120.0) : saturate(r.p0 / 3.0);
                col = fmInk(col, ptRamp(mag), fmRingMask(px, c, g * 1.9 + 4.0 * hair * mag, hair * 1.2));
            }

            if ((fl & F_EDITED) != 0u)
                col = fmInk(col, PT_MID, fmRingMask(px, c, g * 2.9, hair * 0.9) * 0.7);
        }

        // --- the scale bar IS an ant. A 10 mm rule with a 4 mm body-length tick beside it, so
        // every extent on the drawing can be read in workers rather than in millimetres. The
        // subject has a real size and this is the cheapest way to keep saying so.
        {
            float2 sb = float2(planLo.x + 16.0 * hair, planHi.y - 16.0 * hair);
            float2 sbe = sb + float2(10.0 * L.scale, 0.0);
            col = fmInk(col, PT_DIM, fmLineMask(px, sb, sbe, hair * 1.4));
            col = fmInk(col, PT_DIM, fmLineMask(px, sb + float2(0, -4) * hair, sb + float2(0, 4) * hair, hair * 1.4));
            col = fmInk(col, PT_DIM, fmLineMask(px, sbe + float2(0, -4) * hair, sbe + float2(0, 4) * hair, hair * 1.4));
            col = fmInk(col, PT_DIM, fmLabel(px, sb + float2(0.0, -13.0 * hair), 8.0 * hair,
                                             uint2(mf_pack1(1u, 0u, GM, GM, 0u), 0u), 4u));
            float2 ab = sb + float2(0.0, 9.0 * hair);
            float2 abe = ab + float2(4.0 * L.scale, 0.0);
            col = fmInk(col, PT_MID, fmLineMask(px, ab, abe, hair * 2.6));
            col = fmInk(col, PT_MID, fmDiscMask(px, abe, hair * 2.2));
        }
    }

    // ---------------------------------------------------------------------------
    // FLOW STRIP — one lane per route, laid out by TRUE WALKED LENGTH.
    // ---------------------------------------------------------------------------
    float2 flowLo = float2(FM_DRAW_L * res.x, FM_FLOW_T * res.y);
    float2 flowHi = float2(FM_DRAW_R * res.x, FM_FLOW_B * res.y);
    col = fmInk(col, PT_RULE, fmLineMask(px, float2(flowLo.x, flowLo.y - 8.0 * hair),
                                         float2(FM_COL_R * res.x, flowLo.y - 8.0 * hair), hair * 0.9) * 0.55);

    if (px.x >= flowLo.x && px.x <= flowHi.x && px.y >= flowLo.y && px.y <= flowHi.y)
    {
        // The ruler spans the LANE BLOCK, not the whole band. Ticks drawn across empty band
        // make one route look like a diagram that failed to fill itself.
        float2 blk = fmFlowBlockY(L, lanes);
        float2 rulerA = float2(0.0, blk.x - 5.0 * hair);
        float2 rulerB = float2(0.0, blk.y + 5.0 * hair);

        for (uint t = 0u; t <= 16u; t++)
        {
            float dmm = (float)t * 25.0;
            if (dmm > maxRoute * 1.08) break;
            float x = L.flowO.x + dmm * L.flowScale;
            float h = ((t % 4u) == 0u) ? 1.0 : 0.55;
            col = fmInk(col, PT_GRID, fmLineMask(px, float2(x, rulerA.y),
                                                 float2(x, rulerB.y), hair) * h);
            // Distance labels on the hundreds, so the strip is a ruler rather than a shape.
            if ((t % 4u) == 0u && t > 0u)
                col = fmInk(col, PT_DIM, fmNumR(px, float2(x + fmLabelW(7.0 * hair, 3u) * 0.5, rulerB.y + 3.0 * hair),
                                                7.0 * hair, (uint)dmm, 3u) * 0.85);
        }

        // The distance origin — the nest end of every lane.
        col = fmInk(col, PT_RULE, fmLineMask(px, float2(L.flowO.x, rulerA.y),
                                             float2(L.flowO.x, rulerB.y), hair * 1.6));
        col = fmInk(col, PT_DIM, fmLabel(px, float2(flowLo.x, blk.x - 13.0 * hair), 7.5 * hair,
                    uint2(mf_pack1(GR, GO, GU, GT, GE), mf_pack1(GDASH, GM, GM, 0u, 0u)), 8u) * 0.9);

        uint lane = 0u;
        for (uint ei = 0u; ei < FM_EDGES; ei++)
        {
            FmRec r = Plan[FM_EDGE_0 + ei];
            if (r.active < 0.5) continue;

            uint fl = (uint)r.flags;
            bool blocked = (fl & F_BLOCKED) != 0u;
            bool selHere = (FM_EDGE_0 + ei) == selSlot;

            float2 a = fmFlowToPx(L, 0.0, lane);
            float2 b = fmFlowToPx(L, r.p3, lane);
            float bh = L.laneH * 0.30;

            // The straight-line distance, drawn as a ghost tick. The gap between it and the end
            // of the lane IS the cost of the detour, which is the whole reason this strip
            // exists and is invisible in the plan above.
            float2 pa = fmRecWorld(Plan[(uint)r.p0], arena);
            float2 pb = fmRecWorld(Plan[(uint)r.p1], arena);
            float straight = length(pb - pa);
            float2 sx = fmFlowToPx(L, straight, lane);
            col = fmInk(col, PT_DIM, fmLineMask(px, sx + float2(0, -bh), sx + float2(0, bh), hair) * 0.8);

            // planned recruitment: a bar whose height is the weight
            float rw = bh * saturate(r.p2 / 1.2);
            col = fmInk(col, blocked ? PT_ALARM * 0.6 : PT_GRID * 2.4,
                        fmRectMask(px, float2(a.x, a.y - rw), float2(b.x, b.y + rw)));
            col = fmInk(col, blocked ? PT_ALARM : (selHere ? PT_ACCENT : PT_MID),
                        fmLineMask(px, a, b, hair * 1.5));

            // MEASURED traffic. Only the first four lanes have a measurement fed back from
            // FM_Colony; the rest draw a dashed "no reading" rule rather than a share invented
            // by dividing the total, because a number that was not measured must not be able to
            // look like one that was.
            float meas = -1.0;
            if (lane == 0u) meas = live_e0;
            else if (lane == 1u) meas = live_e1;
            else if (lane == 2u) meas = live_e2;
            else if (lane == 3u) meas = live_e3;

            if (meas >= 0.0)
            {
                float2 mb = fmFlowToPx(L, r.p3 * saturate(meas), lane);
                col = fmInk(col, PT_ACCENT,
                            fmRectMask(px, float2(a.x, a.y - bh * 0.42), float2(mb.x, a.y + bh * 0.42)));
            }
            else
            {
                float dash = frac((px.x - a.x) / (7.0 * hair));
                float m = fmRectMask(px, float2(a.x, a.y - hair), float2(b.x, a.y + hair));
                col = fmInk(col, PT_RULE, m * step(dash, 0.45) * 0.7);
            }

            // where it breaks
            if (blocked && r.pad0 > 0.0)
            {
                float2 bp = fmFlowToPx(L, r.p3 * r.pad0, lane);
                col = fmInk(col, PT_ALARM, fmLineMask(px, bp + float2(0, -bh * 1.25), bp + float2(0, bh * 1.25), hair * 1.8));
            }

            // the destination, sized by payload
            FmRec dst = Plan[(uint)r.p1];
            col = fmInk(col, selHere ? PT_ACCENT : ptSampleFill(ptId((int)dst.kind)),
                        fmDiscMask(px, b, (2.5 + 4.0 * saturate(dst.p0)) * hair));

            // lane tag
            col = fmInk(col, PT_DIM, fmNumR(px, float2(a.x - 6.0 * hair, a.y - 3.5 * hair), 7.0 * hair, lane, 2u));

            lane++;
        }
    }

    // ---------------------------------------------------------------------------
    // READOUT COLUMN — every field read straight back out of the buffer or off a live input.
    // ---------------------------------------------------------------------------
    float colL = FM_COL_L * res.x;
    if (px.x >= colL - 10.0 * hair)
    {
        col = fmInk(col, PT_RULE, fmLineMask(px, float2(colL - 12.0 * hair, FM_PLAN_T * res.y),
                                             float2(colL - 12.0 * hair, FM_FLOW_B * res.y), hair) * 0.7);

        float th = 8.5 * hair;
        float row = 15.0 * hair;
        float y = FM_PLAN_T * res.y + 6.0 * hair;
        float2 rightEdge = float2(FM_COL_R * res.x, 0.0);

        // --- ARRANGEMENT block
        col = fmInk(col, PT_DIM, fmLabel(px, float2(colL, y), th,
                    uint2(mf_pack1(GP, GL, GA, GN, 0u), 0u), 4u));
        y += row * 1.35;

        // caches / edges / obstacles
        col = fmInk(col, PT_MID, fmLabel(px, float2(colL, y), th, uint2(mf_pack1(GF, GO, GO, GD, 0u), 0u), 4u));
        col = fmInk(col, PT_INK, fmNumR(px, float2(rightEdge.x, y), th, (uint)hdr.tint.y, 2u));
        y += row;
        col = fmInk(col, PT_MID, fmLabel(px, float2(colL, y), th, uint2(mf_pack1(GT, GR, GA, GI, GL), 0u), 5u));
        {
            // Counted from the records, not read from a cached header field. The header ran out
            // of room when the stage command counter moved in, and a count is cheap enough that
            // caching it was never buying anything — the obstacle row below always did this.
            uint ne = 0u;
            for (uint k = 0u; k < FM_EDGES; k++) if (Plan[FM_EDGE_0 + k].active > 0.5) ne++;
            col = fmInk(col, PT_INK, fmNumR(px, float2(rightEdge.x, y), th, ne, 2u));
        }
        y += row;
        // stations
        col = fmInk(col, PT_MID, fmLabel(px, float2(colL, y), th, uint2(mf_pack1(GS, GT, GA, 0u, 0u), 0u), 3u));
        {
            uint ns = 0u;
            for (uint k = 0u; k < FM_STAS; k++) if (Plan[FM_STA_0 + k].active > 0.5) ns++;
            col = fmInk(col, ns > 0u ? PT_INK : PT_DIM, fmNumR(px, float2(rightEdge.x, y), th, ns, 2u));
        }
        y += row;
        col = fmInk(col, PT_MID, fmLabel(px, float2(colL, y), th, uint2(mf_pack1(GO, GB, GS, GT, 0u), 0u), 4u));
        {
            uint no = 0u;
            for (uint k = 0u; k < FM_OBSTS; k++) if (Plan[FM_OBST_0 + k].active > 0.5) no++;
            col = fmInk(col, PT_INK, fmNumR(px, float2(rightEdge.x, y), th, no, 2u));
        }
        y += row * 1.5;

        // --- ROUTE cost block
        col = fmInk(col, PT_DIM, fmLabel(px, float2(colL, y), th, uint2(mf_pack1(GR, GO, GU, GT, GE), 0u), 5u));
        y += row * 1.25;
        col = fmInk(col, PT_MID, fmLabel(px, float2(colL, y), th, uint2(mf_pack1(GM, GA, GX, 0u, 0u), 0u), 3u));
        col = fmInk(col, PT_INK, fmFixed(px, float2(rightEdge.x - fmLabelW(th, 6u), y), th, maxRoute, 3u));
        y += row;
        col = fmInk(col, PT_MID, fmLabel(px, float2(colL, y), th, uint2(mf_pack1(GR, GC, GR, GT, 0u), 0u), 4u));
        col = fmInk(col, PT_INK, fmFixed(px, float2(rightEdge.x - fmLabelW(th, 5u), y), th, hdr.p2, 2u));
        y += row * 1.5;

        // --- LIVE block. The accent is spent here on purpose: these are the only numbers on the
        // canvas that were MEASURED rather than authored.
        //
        // But the accent is spent only when there IS a measurement. Before FM_Colony's control
        // outputs are wired, every one of these reads a hard zero, and a hard zero drawn in the
        // reserved live colour claims a reading that was never taken — the exact dishonesty the
        // strip exists to avoid. The per-lane share defaults to -1 precisely so the canvas can
        // tell "measured zero" from "not measured", and the whole block goes grey when it is
        // the latter.
        bool measured = (live_e0 >= 0.0);
        float3 liveInk = measured ? PT_ACCENT : PT_RULE;

        col = fmInk(col, measured ? PT_ACCENT : PT_DIM,
                    fmLabel(px, float2(colL, y), th, uint2(mf_pack1(GL, GI, GV, GE, 0u), 0u), 4u));
        if (!measured)
            col = fmInk(col, PT_RULE, fmLabel(px, float2(colL + fmLabelW(th, 5u), y), th,
                        uint2(mf_pack1(GDASH, GDASH, 0u, 0u, 0u), 0u), 2u) * 0.8);
        y += row * 1.25;
        col = fmInk(col, PT_MID,  fmLabel(px, float2(colL, y), th, uint2(mf_pack1(GT, GR, GA, GF, 0u), 0u), 4u));
        col = fmInk(col, liveInk, fmNumR(px, float2(rightEdge.x, y), th, (uint)max(live_traffic, 0.0), 3u));
        y += row;
        col = fmInk(col, PT_MID,  fmLabel(px, float2(colL, y), th, uint2(mf_pack1(GL, GA, GD, GN, 0u), 0u), 4u));
        col = fmInk(col, liveInk, fmFixed(px, float2(rightEdge.x - fmLabelW(th, 4u), y), th, saturate(live_laden), 1u));
        y += row;
        col = fmInk(col, PT_MID,  fmLabel(px, float2(colL, y), th, uint2(mf_pack1(GS, GP, GD, 0u, 0u), 0u), 3u));
        col = fmInk(col, liveInk, fmFixed(px, float2(rightEdge.x - fmLabelW(th, 6u), y), th, max(live_speed, 0.0), 3u));
        y += row;
        // Foot slip is a CORRECTNESS reading, not a performance one: past about a third of a
        // millimetre per step the ants are skating rather than walking, so it turns alarm red at
        // the threshold instead of merely getting bigger.
        col = fmInk(col, PT_MID, fmLabel(px, float2(colL, y), th, uint2(mf_pack1(GS, GL, GI, GP, 0u), 0u), 4u));
        col = fmInk(col, (measured && live_slip > 0.35) ? PT_ALARM : liveInk,
                    fmFixed(px, float2(rightEdge.x - fmLabelW(th, 4u), y), th, max(live_slip, 0.0), 1u));
        y += row * 1.5;

        // --- SELECTION block
        col = fmInk(col, PT_DIM, fmLabel(px, float2(colL, y), th, uint2(mf_pack1(GS, GE, GL, 0u, 0u), 0u), 3u));
        if (selSlot != 0xffffffffu)
        {
            FmRec s = Plan[selSlot];
            col = fmInk(col, PT_ACCENT, fmNumR(px, float2(rightEdge.x, y), th, selSlot, 2u));
            y += row;
            // role, then the one number that defines this kind of record
            if (s.role == ROLE_CACHE)
            {
                col = fmInk(col, PT_MID, fmLabel(px, float2(colL, y), th, uint2(mf_pack1(GP, GA, GY, 0u, 0u), 0u), 3u));
                col = fmInk(col, PT_ACCENT, fmFixed(px, float2(rightEdge.x - fmLabelW(th, 4u), y), th, s.p0, 1u));
            }
            else if (s.role == ROLE_EDGE)
            {
                col = fmInk(col, PT_MID, fmLabel(px, float2(colL, y), th, uint2(mf_pack1(GR, GC, GR, GT, 0u), 0u), 4u));
                col = fmInk(col, PT_ACCENT, fmFixed(px, float2(rightEdge.x - fmLabelW(th, 4u), y), th, s.p2, 1u));
                y += row;
                col = fmInk(col, PT_MID, fmLabel(px, float2(colL, y), th, uint2(mf_pack1(GC, GL, GR, 0u, 0u), 0u), 3u));
                col = fmInk(col, (s.pad1 < 0.0) ? PT_ALARM : PT_ACCENT,
                            fmFixed(px, float2(rightEdge.x - fmLabelW(th, 6u), y), th, abs(s.pad1), 3u));
            }
            else if (s.role == ROLE_OBST)
            {
                col = fmInk(col, PT_MID, fmLabel(px, float2(colL, y), th, uint2(mf_pack1(GL, GE, GN, 0u, 0u), 0u), 3u));
                col = fmInk(col, PT_ACCENT, fmFixed(px, float2(rightEdge.x - fmLabelW(th, 6u), y), th, s.dims.x * 2.0, 3u));
            }
        }
        else
        {
            col = fmInk(col, PT_RULE, fmLabel(px, float2(rightEdge.x - fmLabelW(th, 2u), y), th,
                        uint2(mf_pack1(GDASH, GDASH, 0u, 0u, 0u), 0u), 2u));
        }
    }

    // ---------------------------------------------------------------------------
    // STATUS ROW — the one place the arrangement announces it is broken in words rather than
    // only in the drawing, so a blocked route cannot be missed at a glance.
    // ---------------------------------------------------------------------------
    float statY = FM_STAT_T * res.y;
    if (px.y >= statY)
    {
        float th = 9.0 * hair;
        float2 org = float2(FM_DRAW_L * res.x, statY + 6.0 * hair);
        uint blocked = (uint)hdr.tint.z;
        if (blocked > 0u)
        {
            // "BLOCKED" then the count
            float m = fmLabel(px, org, th, uint2(mf_pack1(GB, GL, GO, GC, GK), mf_pack1(GE, GD, 0u, 0u, 0u)), 7u);
            col = fmInk(col, PT_ALARM, m);
            col = fmInk(col, PT_ALARM, fmNumR(px, org + float2(fmLabelW(th, 11u), 0.0), th, blocked, 2u));
        }
        else
        {
            float m = fmLabel(px, org, th, uint2(mf_pack1(GC, GL, GE, GA, GR), 0u), 5u);
            col = fmInk(col, PT_DIM, m * 0.8);
        }
    }

    OutputUAV[pixel] = float4(col, 1.0);
}
