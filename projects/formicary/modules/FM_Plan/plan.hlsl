// FM_Plan / plan.hlsl — the plan authority for formicary.
//
// One node decides the arena, the nest, the food, the obstacles and the trail network.
// FM_Field bakes its obstacle mask from these records, FM_Colony steers on these routes and
// FM_Render draws these solids. None of them re-decides anything: there is exactly one answer
// to "where is the nest" or "does that route clear the twig".
//
// Single threaded on purpose. 36 records is nothing, the layout is sequential, and the viewport
// event queue has to be reduced in order.
//
// Regeneration is SIGNATURE-DRIVEN and covers the ARRANGEMENT ONLY. Arena, light and palette
// are republished in place every cook, so changing the ground colour or the sun angle never
// costs the user a hand-placed cache. Shader edits are invisible to the signature — bump
// PLAN_VERSION when the generation code changes or the persistent buffer keeps serving records
// built by the old code and the edit looks like it did nothing.
#include "../_shared/formic.hlsli"
#include "layout.hlsli"

RWStructuredBuffer<FmRec> Plan : register(u0);

// 1.3 — stations. The generation code changed, and the signature is built from parameters, so
// without this bump the persistent buffer keeps serving an arrangement built by the old code and
// the new tail stays whatever the resize left in it.
#define PLAN_VERSION 1.3

#define MARGIN     0.10     // keep placed records this far inside the footprint edge
#define SEP_MIN    0.34     // minimum footprint separation between two caches
#define TARGET_R   1.0000   // the transcription's total recruitment, sum over active edges

// ---------------------------------------------------------------------------
// THE REFERENCE, TRANSCRIBED.
//
// The photograph is a close crop of a single foraging trail: six or seven workers strung along
// one diagonal, some antennating, all of them oriented along the same axis. There is no nest in
// frame, no food in frame, and no obstacle on the clean white sweep — what is in frame is the
// MIDDLE of one route. So the transcription is exactly that: a nest just outside the near-left
// corner, one cache just outside the far-right, one trail between them, and the camera framing
// a section of it.
//
// This is why the arrangement is called Trail Crop rather than something grander. Getting it
// right means resisting the urge to put the whole colony on screen; the reference chose a crop
// and the crop is the composition.
// ---------------------------------------------------------------------------
static const float2 REF_NEST  = float2(-0.88,  0.76);
static const float2 REF_CACHE = float2( 0.86, -0.72);

// working set, single thread
static float2 gNest;
static float2 gC[FM_CACHES];        // cache footprint positions
static float  gPay[FM_CACHES];      // payload ladder
static float  gCK[FM_CACHES];       // food kind
static uint   gNC = 1u;             // active caches
static uint   gEF[FM_EDGES];        // edge FROM slot
static uint   gET[FM_EDGES];        // edge TO slot
static float  gER[FM_EDGES];        // edge recruitment
static uint   gNE = 1u;             // active edges

// A descending payload ladder, imposed BY CONSTRUCTION rather than hoped for. Every seed keeps
// one dominant food source and a tail of lesser ones, which is what stops a re-roll reading as
// four equal dots instead of a colony that has found something worth recruiting to.
float ladderPayload(uint i, float s)
{
    return pow(0.74, (float)i) * lerp(0.90, 1.12, fmRnd2(i * 31u + 7u, s));
}

// Stratified BEARING draw around the nest. Angular sectors visited in a hash-permuted order, so
// consecutive caches do not march around the circle, and the whole set cannot land on one side.
// Radius comes from a band, never from zero: a cache on top of the nest is not a foraging
// problem, it is a bug that looks like one.
float2 bearingStratum(uint i, uint n, float s, float rMin, float rMax)
{
    uint sect = fmHashU(i * 2654435761u ^ asuint(s + 3.0)) % max(n, 1u);
    float span = 6.2831853 / (float)max(n, 1u);
    float a = ((float)sect + 0.5) * span + (fmRnd2(i * 17u + 3u, s) - 0.5) * span * 0.72;
    float r = lerp(rMin, rMax, fmRnd2(i * 17u + 4u, s));
    return float2(cos(a), sin(a)) * r;
}

// ---------------------------------------------------------------------------
// The arrangement. Four structural axes, each a different thing a colony does with a plane.
// ---------------------------------------------------------------------------
void buildArrangement(float s)
{
    int arr = (int)arrangement;
    gNC = (uint)clamp((float)cache_count, 1.0, (float)FM_CACHES);

    for (uint i = 0u; i < FM_CACHES; i++)
    {
        gPay[i] = ladderPayload(i, s);
        gCK[i] = (float)(fmHashU(i * 7919u ^ asuint(s)) % 3u);
    }

    if (arr == 0)
    {
        // Trail Crop — the transcription. One nest off the near-left corner, one cache off the
        // far-right, and the frame lands in the middle of the route between them. Extra caches
        // string along the SAME axis rather than fanning out, because a fan would stop being a
        // crop of one trail and start being a different picture.
        gNest = REF_NEST;
        for (uint c = 0u; c < FM_CACHES; c++)
        {
            float f = (c == 0u) ? 1.0 : 1.0 + 0.22 * (float)c;
            gC[c] = REF_CACHE * f + float2(0.0, -0.10 * (float)c);
        }
        gNE = gNC;
        for (uint e = 0u; e < FM_EDGES; e++) { gEF[e] = FM_NEST; gET[e] = FM_CACHE_0 + min(e, FM_CACHES - 1u); gER[e] = (e == 0u) ? 1.0 : 0.35 * pow(0.7, (float)e); }
    }
    else if (arr == 1)
    {
        // Foraging Fan — nest near the centre, caches on stratified bearings, one route each.
        // The classic textbook picture of a colony that has just discovered several things.
        gNest = float2(0.02, 0.06);
        for (uint c = 0u; c < FM_CACHES; c++)
            gC[c] = gNest + bearingStratum(c, gNC, s + 11.0, 0.46, 0.92);
        gNE = gNC;
        for (uint e = 0u; e < FM_EDGES; e++) { gEF[e] = FM_NEST; gET[e] = FM_CACHE_0 + min(e, FM_CACHES - 1u); gER[e] = lerp(1.0, 0.30, (float)e / max((float)gNC - 1.0, 1.0)); }
    }
    else if (arr == 2)
    {
        // Trunk Trail — the thing real colonies actually build. One long trunk from the nest to
        // a distant junction, then short branches off the junction. It is worth having because
        // it is the only arrangement where an edge starts somewhere that is not the nest, which
        // is what proves the edge contract is a graph and not a star.
        gNest = float2(-0.80, 0.62);
        gC[0] = float2(0.34, -0.28);                                   // the junction
        for (uint c = 1u; c < FM_CACHES; c++)
            gC[c] = gC[0] + bearingStratum(c, max(gNC - 1u, 1u), s + 29.0, 0.28, 0.58);
        gNE = gNC;
        gEF[0] = FM_NEST; gET[0] = FM_CACHE_0; gER[0] = 1.0;
        for (uint e = 1u; e < FM_EDGES; e++) { gEF[e] = FM_CACHE_0; gET[e] = FM_CACHE_0 + min(e, FM_CACHES - 1u); gER[e] = 0.55 * pow(0.82, (float)e); }
    }
    else
    {
        // Raid Front — nest along one edge, food spread along the opposite one, routes nearly
        // parallel. An advancing sheet rather than a line, which is what a raid looks like from
        // above and what makes the lanes in the flow strip nearly equal length.
        gNest = float2(-0.02, 0.86);
        for (uint c = 0u; c < FM_CACHES; c++)
        {
            float u = ((float)c + 0.5) / (float)max(gNC, 1u) * 2.0 - 1.0;
            gC[c] = float2(u * 0.86, -0.80 + (fmRnd2(c * 23u, s) - 0.5) * 0.22);
            gPay[c] = lerp(0.55, 1.0, fmRnd2(c * 37u, s));   // a front has no single prize
        }
        gNE = gNC;
        for (uint e = 0u; e < FM_EDGES; e++) { gEF[e] = FM_NEST; gET[e] = FM_CACHE_0 + min(e, FM_CACHES - 1u); gER[e] = lerp(0.70, 1.0, fmRnd2(e * 41u, s)); }
    }

    // --- variation: lerp each cache toward a free stratified BEARING draw around the nest.
    //
    // This is the whole design decision of the randomiser, and it is deliberately not a
    // coordinate draw. A cache is not a point on a plane, it is a distance and a direction FROM
    // THE NEST — that relationship is the thing being explored, and drawing raw coordinates for
    // it produces seeds where the food lands next to the nest, or all of it lands behind the
    // camera, and the picture stops being a foraging problem. The topology (who connects to
    // whom) is never re-rolled at all, because the topology IS the arrangement's identity.
    float v = saturate(variation);
    if (v > 0.0)
    {
        for (uint j = 0u; j < FM_CACHES; j++)
        {
            float2 free = gNest + bearingStratum(j, gNC, s, 0.40, 0.94);
            gC[j] = lerp(gC[j], free, v);
            gPay[j] = lerp(gPay[j], ladderPayload(j, s), v);
        }
    }

    for (uint p = 0u; p < FM_CACHES; p++) gC[p] *= max(spread, 0.05);
    gNest *= max(spread, 0.05);

    // ---------------------------------------------------------------------------
    // GUARANTEES. Every one is gated on variation > 0 so the transcription is never nudged off
    // its own transcribed coordinates by a correction it does not need — which is what keeps
    // "variation = 0 is exactly the reference" a fact rather than a claim.
    // ---------------------------------------------------------------------------
    if (v > 0.0)
    {
        float lim = 1.0 - MARGIN;

        // Separation. Three relaxation sweeps. Without it a draw regularly puts two caches
        // inside one ant-lengths' distance of each other, and two caches that close are not two
        // caches — they are one blob with two routes to it.
        for (uint sweep = 0u; sweep < 3u; sweep++)
        {
            for (uint a = 0u; a < gNC; a++)
            {
                for (uint b = a + 1u; b < gNC; b++)
                {
                    float2 d = gC[b] - gC[a];
                    float l = length(d);
                    if (l < SEP_MIN && l > 1e-5)
                    {
                        float2 push = d / l * (SEP_MIN - l) * 0.5;
                        gC[a] -= push; gC[b] += push;
                    }
                }
                // and never on the nest itself
                float2 dn = gC[a] - gNest;
                float ln = length(dn);
                if (ln < SEP_MIN && ln > 1e-5) gC[a] = gNest + dn / ln * SEP_MIN;
            }
        }

        // A uniform centroid-and-scale fit of the whole network into the footprint. Growth
        // produces a valid arrangement but says nothing about where it lands or how big it is,
        // which is the single most common way a seed looks broken. Uniform, so no proportion
        // changes, and run BEFORE the obstacles are placed so they inherit the framing free.
        float2 cen = gNest;
        for (uint q = 0u; q < gNC; q++) cen += gC[q];
        cen /= (float)(gNC + 1u);

        float maxR = length(gNest - cen);
        for (uint q2 = 0u; q2 < gNC; q2++) maxR = max(maxR, length(gC[q2] - cen));
        float fit = (maxR > 1e-4) ? min(lim / maxR, 1.6) : 1.0;

        gNest = (gNest - cen) * fit;
        for (uint q3 = 0u; q3 < FM_CACHES; q3++) gC[q3] = (gC[q3] - cen) * fit;

        // Final margin clamp. The fit handles the common case; this catches the rest.
        gNest = clamp(gNest, -lim, lim);
        for (uint q4 = 0u; q4 < FM_CACHES; q4++) gC[q4] = clamp(gC[q4], -lim, lim);

        // Total recruitment normalised to the transcription's. Without it a seed comes out with
        // nothing walking anywhere, or with every route saturated so none of them means
        // anything — and either reads as the colony being broken rather than the draw being
        // unlucky.
        float tot = 0.0;
        for (uint r = 0u; r < gNE; r++) tot += gER[r];
        if (tot > 1e-4)
        {
            float k = TARGET_R / tot;
            for (uint r2 = 0u; r2 < FM_EDGES; r2++) gER[r2] *= k;
        }
    }
}

// ---------------------------------------------------------------------------
// Obstacles are placed ON a route, not on the plane.
//
// This is the same relational rule as the caches, applied to the family whose entire reason to
// exist is to be IN THE WAY. An obstacle drawn at a free coordinate blocks nothing most of the
// time: it lands in an empty corner, the routes stay ruled straight, and the arrangement looks
// like a starburst with some litter on it. Drawn onto a route at a lateral offset smaller than
// its own half width, it is guaranteed to intersect the straight line it was placed against,
// and the clearance solve then has something real to bend around.
// ---------------------------------------------------------------------------
void placeObstacles(float s, FmRec arena)
{
    uint n = (uint)clamp((float)obstacle_count, 0.0, (float)FM_OBSTS);

    for (uint i = 0u; i < FM_OBSTS; i++)
    {
        FmRec o = (FmRec)0;
        o.role = ROLE_OBST;
        o.active = (i < n) ? 1.0 : 0.0;

        if (i < n)
        {
            uint e = (gNE > 0u) ? (i % gNE) : 0u;
            float2 a = fmFootToWorld(gEF[e] == FM_NEST ? gNest : gC[gEF[e] - FM_CACHE_0], arena);
            float2 b = fmFootToWorld(gC[min(gET[e] - FM_CACHE_0, FM_CACHES - 1u)], arena);
            float2 chord = b - a;
            float clen = max(length(chord), 1e-3);
            float2 dirn = chord / clen;
            float2 perp = float2(-dirn.y, dirn.x);

            float t = lerp(0.24, 0.76, fmRnd2(i * 61u + 5u, s));
            uint kind = fmHashU(i * 104729u ^ asuint(s + 5.0)) % 3u;

            float sc = max(obst_scale, 0.05);
            float hl, hw, hgt;
            if (kind == 1u)      { hl = lerp( 7.0, 22.0, fmRnd2(i * 71u, s)) * sc; hw = lerp(0.45, 1.30, fmRnd2(i * 73u, s)) * sc; hgt = hw * 1.6; }
            else if (kind == 2u) { hl = lerp( 6.0, 15.0, fmRnd2(i * 79u, s)) * sc; hw = lerp(3.00, 7.00, fmRnd2(i * 83u, s)) * sc; hgt = lerp(0.3, 0.9, fmRnd2(i * 89u, s)) * sc; }
            else                 { hl = lerp( 2.5,  6.5, fmRnd2(i * 97u, s)) * sc; hw = hl * lerp(0.66, 0.98, fmRnd2(i *101u, s));  hgt = hl * lerp(0.45, 0.85, fmRnd2(i *103u, s)); }

            // GUARANTEE: the lateral offset is drawn strictly BELOW the obstacle's own half
            // width, so the body always overlaps the straight route it was placed against.
            float lat = fmSRnd(i * 107u, s) * hw * 0.70;
            float2 w = a + dirn * (clen * t) + perp * lat;

            // A twig lies ACROSS the trail, give or take. That is both what a fallen twig does
            // and what makes it an obstacle rather than a handrail.
            float yaw = (kind == 1u)
                      ? atan2(perp.y, perp.x) + fmSRnd(i * 109u, s) * 0.55
                      : fmRnd2(i * 113u, s) * 6.2831853;

            o.pos = float3(fmWorldToFoot(w, arena).x, 0.0, fmWorldToFoot(w, arena).y);
            o.dims = float3(hl, hgt, hw);
            o.kind = (float)kind;
            o.p0 = yaw;
            o.p1 = 0.0;
            o.seed = fmRnd2(i * 127u, s) * 97.0;
            o.tint = float3(0.42, 0.38, 0.33);
        }

        Plan[FM_OBST_0 + i] = o;
    }
}

// ---------------------------------------------------------------------------
// Appearance, republished unconditionally every cook. None of this is in the signature, so
// tuning the sun angle or the chitin colour can never cost a hand-arranged network.
// ---------------------------------------------------------------------------
void refreshArena()
{
    FmRec a = (FmRec)0;
    a.pos = float3(0, 0, 0);
    a.dims = float3(max(arena_w, 20.0) * 0.5, 0.0, max(arena_d, 20.0) * 0.5);
    a.role = ROLE_ARENA;
    a.tint = ground_color;
    a.p0 = ground_grain;
    a.p1 = ground_tone;
    // WHICH WAY ROUND THE PAGE GOES, published so every other node draws the arena the same way
    // up. It was a parameter of this node alone, and FM_Colony's canvas consequently kept
    // drawing world +x to the RIGHT after the plan was corrected to draw it left — the two
    // top-down views of the same colony were mirror images and neither was labelled. A
    // convention that more than one node has to obey belongs in the record, not in a parameter
    // each node is trusted to copy.
    a.p2 = (float)((int)plan_facing);
    a.active = 1.0;
    Plan[FM_ARENA] = a;
}

void refreshLight()
{
    float az = radians(sun_azimuth);
    float el = radians(clamp(sun_elev, 5.0, 89.0));
    FmRec l = (FmRec)0;
    l.pos = normalize(float3(cos(el) * sin(az), sin(el), cos(el) * cos(az)));
    l.role = ROLE_LIGHT;
    l.tint = sun_color;
    l.p0 = key_intensity;
    l.p1 = sky_level;
    l.p2 = shadow_soften;
    l.p3 = spec_power;
    l.active = 1.0;
    Plan[FM_LIGHT] = l;
}

void refreshPalette(float palSalt)
{
    float3 src[4] = { pal_gaster, pal_thorax, pal_limb, ground_color };
    for (uint i = 0u; i < FM_PALS; i++)
    {
        float3 c = src[i];

        // A palette re-roll stays INSIDE the authored chitin range rather than wandering off
        // it. A fire ant is one species; the individuals differ in value and a little in
        // saturation, not in hue. Inventing a new hue per re-roll would produce a bag of
        // differently coloured insects, which is not what a colony is.
        if (palSalt > 0.5 && i < 3u)
        {
            float w = lerp(0.86, 1.18, fmRnd2(i * 83u, palSalt));
            float h = lerp(0.92, 1.10, fmRnd2(i * 91u, palSalt));
            c = saturate(float3(c.r * w * h, c.g * w, c.b * w / max(h, 0.5)));
        }

        FmRec r = (FmRec)0;
        r.role = ROLE_PAL;
        r.tint = saturate(c);
        r.seed = palSalt;
        r.p0 = 1.0;
        r.active = 1.0;
        Plan[FM_PAL_0 + i] = r;
    }
}

// ---------------------------------------------------------------------------
// Route measurement. Runs EVERY cook, because the user can drag an obstacle onto a finished
// route and the diagram has to say so immediately.
//
// It only MEASURES. Bending the route is a separate, explicit act (the B key, or dragging the
// mid handle), because a solve that ran unconditionally would silently undo every hand edit the
// moment anything else moved.
// ---------------------------------------------------------------------------
float2 fmNodeWorld(uint slot, FmRec arena)
{
    return fmRecWorld(Plan[slot], arena);
}

void measureRoutes(FmRec arena)
{
    float lim = 1.02;
    for (uint e = 0u; e < FM_EDGES; e++)
    {
        FmRec r = Plan[FM_EDGE_0 + e];
        if (r.active < 0.5) { r.p3 = 0.0; Plan[FM_EDGE_0 + e] = r; continue; }

        float2 a = fmNodeWorld((uint)r.p0, arena);
        float2 b = fmNodeWorld((uint)r.p1, arena);
        float2 ctrl = float2(r.dims.x, r.dims.z);

        float len = 0.0;
        float2 prev = a;
        uint blockedAt = 0u;      // sample index of the first violation, 0 = none
        float worst = 1e9;

        for (uint k = 1u; k <= 48u; k++)
        {
            float t = (float)k / 48.0;
            float2 pt = fmRoutePoint(a, b, ctrl, t);
            len += length(pt - prev);
            prev = pt;

            float d; float2 nrm;
            FM_OBST_QUERY(Plan, arena, pt, d, nrm)
            worst = min(worst, d);

            float2 f = fmWorldToFoot(pt, arena);
            bool outside = (abs(f.x) > lim || abs(f.y) > lim);
            if ((d < 0.0 || outside) && blockedAt == 0u) blockedAt = k;
        }

        uint fl = (uint)r.flags;
        fl = (blockedAt > 0u) ? (fl | F_BLOCKED) : (fl & ~F_BLOCKED);
        r.flags = (float)fl;
        r.p3 = len;
        r.pad0 = (float)blockedAt / 48.0;    // where along the route it breaks, for the lane tick
        r.pad1 = worst;                      // measured clearance, mm — negative means through it
        Plan[FM_EDGE_0 + e] = r;
    }
}

// Bend one route until it clears the obstacles, by pushing the single control point
// perpendicular to the chord. Explicit — only the B key runs it. Bounded iterations and a
// bounded push, because a route that cannot be cleared (a twig longer than the gap) must end up
// visibly blocked rather than flung across the arena pretending to have solved it.
void solveRoute(uint e, FmRec arena)
{
    FmRec r = Plan[FM_EDGE_0 + e];
    if (r.active < 0.5) return;

    float2 a = fmNodeWorld((uint)r.p0, arena);
    float2 b = fmNodeWorld((uint)r.p1, arena);
    float2 chord = b - a;
    float clen = max(length(chord), 1e-3);
    float2 perp = float2(-chord.y, chord.x) / clen;
    float2 ctrl0 = float2(r.dims.x, r.dims.z);
    float need = max(clearance, 0.0);

    // BOTH SIDES ARE TRIED, and the better result kept.
    //
    // The first version picked the bend side from the outward normal at the deepest violation.
    // That is right for a pebble and useless for the obstacle that actually matters: a twig
    // lying square across the route has a surface normal parallel to the chord at the point the
    // route crosses it, so the side test is a coin toss, and half the time the solve pushes the
    // curve further along the twig instead of around its end. Measured: three of four routes
    // stayed blocked in a four-route fan. Trying both and scoring the outcome is twice the work
    // on a single-threaded pass that runs only on rebuild or on the B key, and it converges.
    float2 bestCtrl = ctrl0;
    float bestScore = -1e9;

    for (uint sIdx = 0u; sIdx < 2u; sIdx++)
    {
        float side = (sIdx == 0u) ? 1.0 : -1.0;
        float2 ctrl = ctrl0;
        float worst = 0.0;

        for (uint it = 0u; it < 10u; it++)
        {
            worst = 1e9;
            float worstT = 0.5;

            for (uint k = 0u; k <= 32u; k++)
            {
                float t = (float)k / 32.0;
                float2 pt = fmRoutePoint(a, b, ctrl, t);
                float d; float2 nrm;
                FM_OBST_QUERY(Plan, arena, pt, d, nrm)
                if (d < worst) { worst = d; worstT = t; }
            }

            if (worst >= need) break;

            // The 1/(2 t (1-t)) factor converts "move the CURVE here by x" into "move the
            // CONTROL POINT by", which is what stops the first iteration overshooting when the
            // violation is near an endpoint, where the curve barely follows the control at all.
            float w = max(2.0 * worstT * (1.0 - worstT), 0.18);
            float push = min((need - worst) / w * 1.10, clen * 0.50);
            ctrl += perp * side * push;

            if (length(ctrl) > clen * 1.2) { ctrl = normalize(ctrl) * clen * 1.2; break; }
        }

        // Score on achieved clearance, with a small penalty for how far the route was thrown,
        // so that when both sides clear the obstacles the shorter detour wins.
        float score = min(worst, need) - length(ctrl) / max(clen, 1e-3) * 0.35;
        if (score > bestScore) { bestScore = score; bestCtrl = ctrl; }
    }

    r.dims = float3(bestCtrl.x, 0.0, bestCtrl.y);
    r.flags = (float)(((uint)r.flags) | F_EDITED);
    Plan[FM_EDGE_0 + e] = r;
}

// ---------------------------------------------------------------------------
// STATIONS.
//
// Placed RELATIONALLY, like everything else in this plan. A station is not a dot at a
// coordinate — it is a thing that has a job in relation to the arrangement that already exists,
// and drawing fresh coordinates for one would produce a beacon in an empty corner attracting
// nobody. So:
//
//   an EMITTER belongs at the nest        — that is where a colony comes out of the ground
//   an ATTRACTOR belongs beside a route   — it is only a detour if there is something to divert
//   a REPELLER belongs ON a route         — offset inside its own radius, so it is guaranteed
//                                           to intersect the line it was placed against, the
//                                           same guarantee the obstacle placement gives
//   a SINK belongs at a cache             — food is where a column terminates
//
// The kinds cycle rather than being drawn from a distribution, so any station_count above three
// demonstrates all four and no seed can produce four sinks and nothing to fill them.
// ---------------------------------------------------------------------------
void writeStation(uint s, float2 wpos, float kind, FmRec arena, float sd)
{
    FmRec r = (FmRec)0;
    float2 f = clamp(fmWorldToFoot(wpos, arena), -1.0, 1.0);

    r.pos = float3(f.x, 0.0, f.y);        // pos.y is the emitter's AIM, in radians
    r.dims = float3(max(station_radius, 1.0), 0.0, 0.55);   // dims.z is the release cone
    r.role = ROLE_STA;
    r.kind = kind;
    r.seed = sd;
    r.flags = 0.0;
    r.active = 1.0;
    r.pad0 = 0.0;                          // trigger counter, only ever incremented
    r.pad1 = 0.0;

    int k = (int)(kind + 0.5);
    if (k == 0)
    {
        r.p0 = max(emit_rate, 0.0);
        r.p1 = STA_M_DRIP;
        r.p2 = 0.0;                        // budget: 0 = unlimited
        r.p3 = max(emit_burst, 1.0);
        r.tint = float3(0.62, 0.55, 0.30);
    }
    else if (k == 3)
    {
        r.p0 = 1.6;                        // drain speed
        r.p1 = STA_M_RECYCLE;
        r.p3 = 1.0;
        r.tint = float3(0.30, 0.34, 0.40);
    }
    else
    {
        r.p0 = max(station_force, 0.0);
        r.p1 = STA_M_STEADY;
        r.p3 = 0.6;                        // pulse Hz, used only in pulse mode
        r.tint = (k == 1) ? float3(0.52, 0.46, 0.26) : float3(0.44, 0.30, 0.28);
    }

    Plan[FM_STA_0 + s] = r;
}

void buildStations(FmRec arena, float sd)
{
    uint want = min((uint)station_count, FM_STAS);
    float2 nestW = fmFootToWorld(gNest, arena);

    for (uint s = 0u; s < FM_STAS; s++)
    {
        if (s >= want) { FmRec z = (FmRec)0; z.role = ROLE_STA; z.active = 0.0; Plan[FM_STA_0 + s] = z; continue; }

        float kind = (float)(s % STA_KINDS);
        int k = (int)kind;
        float ss = sd + (float)s * 17.3;
        float2 w;

        if (k == 0)
        {
            // At the nest mouth, just off centre so the ring does not sit exactly on the nest's
            // and the two become one unreadable blob in the drawing.
            float ang = fmRnd2(s * 31u + 1u, ss) * 6.2831853;
            w = nestW + float2(cos(ang), sin(ang)) * max(nest_radius, 1.0) * 1.6;
        }
        else if (k == 3)
        {
            // BEYOND the food, on the nest-to-cache ray, not on top of it.
            //
            // "A sink belongs at a cache" was the first answer and it is wrong, measurably: a
            // drain sitting on the food swallows every outbound ant before it can load, so the
            // colony's laden fraction reads 0.00 and the round trip — the entire subject —
            // silently stops existing. What a sink actually means here is the place a column
            // marches OFF to, so it goes past the food along the same line, where it drains the
            // overflow instead of intercepting the traffic.
            uint c = (gNC > 0u) ? (s % gNC) : 0u;
            float2 cw = fmFootToWorld(gC[c], arena);
            float2 dir = normalize(cw - nestW + float2(1e-4, 0.0));
            w = cw + dir * max(station_radius, 1.0) * 1.15;
        }
        else
        {
            // On a route. t is drawn in the middle band so a station never lands on top of the
            // node at either end, and the lateral offset is drawn strictly SMALLER than the
            // station's own radius — the same guarantee the obstacles use — so the thing it was
            // placed against is inside its reach by construction rather than by luck.
            uint e = (gNE > 0u) ? (s % gNE) : 0u;
            float2 a = fmFootToWorld(gEF[e] == FM_NEST ? gNest : gC[min(gEF[e] - FM_CACHE_0, FM_CACHES - 1u)], arena);
            float2 b = fmFootToWorld(gC[min(gET[e] - FM_CACHE_0, FM_CACHES - 1u)], arena);
            float2 ctrl = float2(Plan[FM_EDGE_0 + e].dims.x, Plan[FM_EDGE_0 + e].dims.z);

            float t = lerp(0.28, 0.72, fmRnd2(s * 37u + 5u, ss));
            float2 q = fmRoutePoint(a, b, ctrl, t);
            float2 tg = fmRouteTangent(a, b, ctrl, t);
            float2 perp = float2(-tg.y, tg.x);

            // A REPELLER sits ON the line and must split it, so its offset is small. An
            // ATTRACTOR sits beside the line and must pull it off course, so its offset is
            // most of its reach — at zero it would be an attractor the column is already on,
            // which changes nothing and looks like a control that does not work.
            float lat = (k == 2) ? 0.25 : 0.80;
            float sgn = (fmRnd2(s * 41u + 7u, ss) < 0.5) ? -1.0 : 1.0;
            w = q + perp * sgn * max(station_radius, 1.0) * lat;
        }

        // Kept a full handle-width inside the boundary, not merely on it. Clamping to the arena
        // edge exactly puts a station's glyph half outside the drawn frame, where it reads as a
        // record that has escaped rather than as one that was placed at the limit.
        float2 ah = fmArenaHalf(arena) - max(station_radius, 1.0) * 0.18;
        w = clamp(w, -ah, ah);
        writeStation(s, w, kind, arena, ss);
    }
}

// ---------------------------------------------------------------------------
// Pick, in exactly the space the canvas draws in. Smallest hit wins, so a 2 mm cache sitting
// inside the nest's big ring stays reachable.
// ---------------------------------------------------------------------------
uint pickRecord(float2 w, FmLayout L, FmRec arena)
{
    uint best = 0u;
    float bestR = 1e9;

    // nest
    {
        FmRec r = Plan[FM_NEST];
        float rad = fmPickRadius(L, max(r.dims.x, 1.0));
        if (r.active > 0.5 && length(w - fmRecWorld(r, arena)) < rad * 1.4 && rad < bestR) { bestR = rad; best = FM_NEST + 1u; }
    }
    // caches
    for (uint c = 0u; c < FM_CACHES; c++)
    {
        FmRec r = Plan[FM_CACHE_0 + c];
        if (r.active < 0.5) continue;
        float rad = fmPickRadius(L, max(r.dims.x, 0.6));
        if (length(w - fmRecWorld(r, arena)) < rad * 1.5 && rad < bestR) { bestR = rad; best = FM_CACHE_0 + c + 1u; }
    }
    // obstacles — pick against the real body, so an elongated twig is grabbable along its length
    for (uint o = 0u; o < FM_OBSTS; o++)
    {
        FmRec r = Plan[FM_OBST_0 + o];
        if (r.active < 0.5) continue;
        float d = fmObstDist(w, r, arena);
        float rad = max(r.dims.z, 1.0);
        if (d < 12.0 / max(L.scale, 1e-4) && rad < bestR) { bestR = rad; best = FM_OBST_0 + o + 1u; }
    }
    // stations. Picked against a HANDLE at the centre rather than against the whole reach
    // circle: the reach is often tens of millimetres across and would swallow every other
    // record inside it, so the ring is a readout and the dot is the target.
    for (uint s = 0u; s < FM_STAS; s++)
    {
        FmRec r = Plan[FM_STA_0 + s];
        if (r.active < 0.5) continue;
        float rad = fmPickRadius(L, 2.2);
        if (length(w - fmRecWorld(r, arena)) < rad && rad < bestR) { bestR = rad; best = FM_STA_0 + s + 1u; }
    }
    // edge mid handles — the route's one shape control
    for (uint e = 0u; e < FM_EDGES; e++)
    {
        FmRec r = Plan[FM_EDGE_0 + e];
        if (r.active < 0.5) continue;
        float2 a = fmNodeWorld((uint)r.p0, arena);
        float2 b = fmNodeWorld((uint)r.p1, arena);
        float2 h = fmEdgeHandle(a, b, float2(r.dims.x, r.dims.z));
        float rad = 11.0 / max(L.scale, 1e-4);
        if (length(w - h) < rad && rad < bestR) { bestR = rad; best = FM_EDGE_0 + e + 1u; }
    }
    return best;
}

[numthreads(1, 1, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    FmRec hdr = Plan[FM_HEADER];
    float initFlag = hdr.tint.x;
    float salt     = hdr.seed;
    float palSalt  = hdr.p0;
    float sel      = hdr.pos.y;      // selected slot + 1, 0 = nothing selected
    float dragOn   = hdr.dims.x;
    float2 grab    = float2(hdr.dims.y, hdr.dims.z);
    float prevMaxR = max(hdr.p3, 1.0);
    uint  prevLanes = max((uint)hdr.kind, 1u);
    // Where the pointer was last seen, in world millimetres. Carried in the header because
    // pressing A has to place a station SOMEWHERE, and a key event carries no position — the
    // alternative is placing at the arena centre, which means every station starts life on top
    // of the last one and has to be dragged out before it is even visible.
    float2 lastPtr = float2(hdr.pad0, hdr.pad1);

    // The arena must exist before anything can be picked against it, and it is pure appearance
    // as far as the arrangement is concerned, so it is refreshed first and unconditionally.
    refreshArena();
    refreshLight();

    FmRec arena = Plan[FM_ARENA];
    FmLayout L = fmLayout(_Resolution.xy, arena, prevMaxR, prevLanes);

    uint n = min((uint)_ViewportEventCount, 64u);

    // The pointer position is harvested BEFORE the keys are handled, so pressing A places a
    // station where the cursor is in the same batch of events rather than one cook behind it.
    for (uint evp = 0u; evp < n; evp++)
    {
        ViewportEvent evq = _ViewportEvents[evp];
        if (evq.type != 5u) continue;
        float2 pxq = evq.position * _Resolution.xy;
        if (fmInPlanStrip(L, pxq)) lastPtr = fmPxToPlan(L, pxq);
    }

    // --- keys. R and P change salts, so they land BEFORE the signature test or the rebuild
    // they ask for is immediately overwritten by the next cook's unchanged signature.
    for (uint ev0 = 0u; ev0 < n; ev0++)
    {
        ViewportEvent ev = _ViewportEvents[ev0];
        if (ev.type != 4u || ev.phase != 1u) continue;
        uint c = (uint)ev.code;

        if (c == 18u) { salt += 1.0; }                       // R  reseed the arrangement
        else if (c == 16u) { palSalt += 1.0; }               // P  re-roll the palette
        else if (c == 3u) { sel = 0.0; }                     // C  clear selection
        else if (c == 4u && sel > 0.5)                       // D  delete the selected station
        {
            // Stations only. Everything else in the plan is part of the arrangement's structure
            // and is switched off with X rather than removed — deleting the nest, or the one
            // route, would leave a plan the colony cannot walk and no way to get it back short
            // of a reseed. A station is the one record you genuinely put down and take away.
            uint di = (uint)(sel - 1.0);
            if (di >= FM_STA_0 && di < FM_STA_0 + FM_STAS)
            {
                FmRec z = (FmRec)0;
                z.role = ROLE_STA;
                z.active = 0.0;
                Plan[di] = z;
                sel = 0.0;
            }
        }
        else if (c == 1u)                                    // A  add a station at the pointer
        {
            // The first slot that is switched off, which makes A and X a pair: turning a
            // station off frees its slot and the next A reuses it, so the sixteen never fill up
            // with records nobody can see.
            int free = -1;
            for (uint fs = 0u; fs < FM_STAS; fs++)
                if (Plan[FM_STA_0 + fs].active < 0.5) { free = (int)fs; break; }

            if (free >= 0)
            {
                // A new station is an ATTRACTOR. It is the kind that does something visible the
                // instant it exists, with no other setup: an emitter needs the colony switched
                // to Dormant Pool before it has anything to release, and a sink placed by
                // accident quietly eats the population.
                writeStation((uint)free, lastPtr, STA_ATTRACT, arena, seed + salt + (float)free * 17.3);
                Plan[FM_STA_0 + (uint)free].flags = (float)F_EDITED;
                sel = (float)(FM_STA_0 + (uint)free + 1u);
            }
        }
        else if (c == 2u)                                    // B  auto-route around obstacles
        {
            if (sel > 0.5 && (uint)(sel - 1.0) >= FM_EDGE_0 && (uint)(sel - 1.0) < FM_EDGE_0 + FM_EDGES)
                solveRoute((uint)(sel - 1.0) - FM_EDGE_0, arena);
            else
                for (uint se = 0u; se < FM_EDGES; se++) solveRoute(se, arena);
        }
        else if (sel > 0.5)
        {
            uint idx = (uint)(sel - 1.0);
            FmRec r = Plan[idx];
            uint fl = (uint)r.flags;
            bool touched = true;
            bool isCache = (idx >= FM_CACHE_0 && idx < FM_CACHE_0 + FM_CACHES);
            bool isObst  = (idx >= FM_OBST_0  && idx < FM_OBST_0  + FM_OBSTS);
            bool isEdge  = (idx >= FM_EDGE_0  && idx < FM_EDGE_0  + FM_EDGES);
            bool isSta   = (idx >= FM_STA_0   && idx < FM_STA_0   + FM_STAS);

            if (c == 13u && isSta)                           // M  cycle station kind
            {
                // The strength means a different thing per kind — ants per second, a steering
                // gain, a drain speed — so cycling has to re-scale it or an emitter cycled from
                // an attractor emits 1.4 ants a second and reads as broken.
                float kk = fmod(r.kind + 1.0, (float)STA_KINDS);
                float2 keepW = fmRecWorld(r, arena);
                float keepR = r.dims.x;
                writeStation(idx - FM_STA_0, keepW, kk, arena, r.seed);
                r = Plan[idx];
                r.dims.x = keepR;                            // reach is the user's, not the kind's
            }
            else if (c == 5u && isSta)                       // E  cycle the mode within the kind
            {
                int kk = (int)(r.kind + 0.5);
                // Emitters have three modes, everything else has two.
                float modes = (kk == 0) ? 3.0 : 2.0;
                r.p1 = fmod(r.p1 + 1.0, modes);
            }
            else if (c == 20u && isSta)                      // T  fire it
            {
                // MONOTONIC, never a held flag. The colony acts on the DIFFERENCE against what
                // it last saw, so a trigger cannot be lost to a dropped cook or counted twice
                // by a slow one — and it cannot be missed by the one-cook delay between this
                // node and the colony either.
                r.pad0 += 1.0;
            }
            else if (c == 13u && isObst)                     // M  cycle obstacle kind
            {
                r.kind = fmod(r.kind + 1.0, 3.0);
                // The three kinds are different SHAPES, not one shape recoloured, so the extents
                // have to be re-proportioned or a twig cycles into a 20 mm wide pebble.
                float sc = max(obst_scale, 0.05);
                int k = (int)r.kind;
                if (k == 1)      { r.dims = float3(14.0 * sc, 1.4 * sc, 0.85 * sc); }
                else if (k == 2) { r.dims = float3(10.0 * sc, 0.6 * sc, 5.00 * sc); }
                else             { r.dims = float3( 4.2 * sc, 2.4 * sc, 3.60 * sc); }
            }
            else if (c == 6u)                                // F  more of it
            {
                if (isCache) r.p0 = min(r.p0 * 1.18, 4.0);
                else if (isObst) r.dims *= 1.12;
                // A station at strength zero can never be grown by multiplying, so the step is
                // additive off the floor and multiplicative above it.
                else if (isSta) r.p0 = min(max(r.p0 * 1.20, r.p0 + 0.08), 200.0);
                else touched = false;
            }
            else if (c == 22u)                               // V  less of it
            {
                if (isCache) r.p0 = max(r.p0 * 0.85, 0.02);
                else if (isObst) r.dims *= 0.89;
                else if (isSta) r.p0 = max(r.p0 * 0.83, 0.0);
                else touched = false;
            }
            else if (c == 7u && isEdge) r.p2 = min(r.p2 * 1.15, 3.0);      // G  recruit harder
            else if (c == 8u && isEdge) r.p2 = max(r.p2 * 0.87, 0.01);     // H  recruit less
            else if (c == 7u && isSta) r.dims.x = min(r.dims.x * 1.14, 300.0);   // G  wider reach
            else if (c == 8u && isSta) r.dims.x = max(r.dims.x * 0.88, 1.0);     // H  tighter
            else if (c == 24u) r.active = (r.active > 0.5) ? 0.0 : 1.0;    // X  on / off
            else if (c == 14u)                                             // N  re-roll this one
            {
                r.seed += 9.31;
                if (isObst)
                {
                    float sc = max(obst_scale, 0.05);
                    r.p0 = fmRnd(r.seed, 2.0) * 6.2831853;
                    r.dims = float3(r.dims.x * lerp(0.72, 1.35, fmRnd(r.seed, 3.0)),
                                    r.dims.y * lerp(0.72, 1.35, fmRnd(r.seed, 4.0)),
                                    r.dims.z * lerp(0.72, 1.35, fmRnd(r.seed, 5.0)));
                }
                else if (isCache) { r.p0 = lerp(0.15, 1.0, fmRnd(r.seed, 6.0)); r.kind = floor(fmRnd(r.seed, 7.0) * 3.0); }
                else if (isEdge)  { r.dims = float3(r.dims.x * lerp(-1.2, 1.2, fmRnd(r.seed, 8.0)), 0.0, r.dims.z * lerp(-1.2, 1.2, fmRnd(r.seed, 9.0))); }
                else if (isSta)
                {
                    // Re-rolls the two things that define a station's behaviour and leaves its
                    // PLACE alone. Where it is, is the thing you put it there for.
                    r.dims.x *= lerp(0.70, 1.42, fmRnd(r.seed, 10.0));
                    r.p0 *= lerp(0.60, 1.65, fmRnd(r.seed, 11.0));
                    r.pos.y = fmRnd(r.seed, 12.0) * 6.2831853;      // the emitter's aim
                    r.dims.z = lerp(0.12, 1.40, fmRnd(r.seed, 13.0));
                }
            }
            else touched = false;

            if (touched) r.flags = (float)(fl | F_EDITED);
            Plan[idx] = r;
        }
    }

    // Only STRUCTURAL parameters are in the signature. Arena size, light, palette and the live
    // measurements are all out of it.
    float sig = seed * 7.31
              + (float)arrangement * 137.7
              + (float)cache_count * 11.3
              + (float)obstacle_count * 23.9
              + spread * 53.1
              + variation * 211.9
              + meander * 71.3
              + obst_scale * 31.7
              + (float)station_count * 43.1
              + salt * 101.3
              + PLAN_VERSION * 911.7;

    bool rebuild = (initFlag < 0.5 || abs(sig - hdr.pos.x) > 1e-4);

    if (rebuild)
    {
        buildArrangement(seed + salt * 3.19);

        // nest
        {
            FmRec r = (FmRec)0;
            r.pos = float3(gNest.x, 0.0, gNest.y);
            r.dims = float3(max(nest_radius, 0.5), 0.0, 0.0);
            r.role = ROLE_NEST;
            r.tint = float3(0.30, 0.24, 0.19);
            r.p0 = 1.0;
            r.seed = seed + salt;
            r.active = 1.0;
            Plan[FM_NEST] = r;
        }

        // caches
        for (uint c = 0u; c < FM_CACHES; c++)
        {
            FmRec r = (FmRec)0;
            r.pos = float3(gC[c].x, 0.0, gC[c].y);
            // Radius derived from the payload rather than given its own parameter: a big cache
            // IS a big pile, and two numbers that must be kept in agreement by hand are two
            // numbers that will silently disagree.
            r.dims = float3(max(cache_radius, 0.3) * (0.55 + 0.75 * saturate(gPay[c])), 0.0, 0.0);
            r.role = ROLE_CACHE;
            r.kind = gCK[c];
            r.tint = float3(0.62, 0.52, 0.24);
            r.p0 = gPay[c];
            r.p1 = 1.0;
            r.seed = seed + salt + (float)c * 3.7;
            r.active = (c < gNC) ? 1.0 : 0.0;
            Plan[FM_CACHE_0 + c] = r;
        }

        // edges. The control offset starts as a MEANDER — a real trail is not a ruled line, it
        // is a track worn by ants each of whom was only approximately following the last one.
        for (uint e = 0u; e < FM_EDGES; e++)
        {
            FmRec r = (FmRec)0;
            r.role = ROLE_EDGE;
            r.active = (e < gNE) ? 1.0 : 0.0;
            r.p0 = (float)gEF[e];
            r.p1 = (float)gET[e];
            r.p2 = gER[e];
            r.tint = float3(0.55, 0.48, 0.40);
            r.seed = seed + salt + (float)e * 5.3;

            float2 a = fmFootToWorld(gEF[e] == FM_NEST ? gNest : gC[min(gEF[e] - FM_CACHE_0, FM_CACHES - 1u)], arena);
            float2 b = fmFootToWorld(gC[min(gET[e] - FM_CACHE_0, FM_CACHES - 1u)], arena);
            float2 ch = b - a;
            float cl = max(length(ch), 1e-3);
            float2 perp = float2(-ch.y, ch.x) / cl;
            // The SIGN is drawn but the MAGNITUDE is not: a signed draw regularly lands near
            // zero, and a trail that came out ruled straight because the hash said 0.02 is
            // indistinguishable from a meander control that does nothing. Sign picks the side,
            // magnitude stays in a band the parameter actually governs.
            float sgn = (fmRnd2(e * 149u + 3u, seed + salt) < 0.5) ? -1.0 : 1.0;
            float bend = cl * 0.16 * meander * lerp(0.62, 1.0, fmRnd2(e * 151u + 9u, seed + salt)) * sgn;
            r.dims = float3(perp.x * bend, 0.0, perp.y * bend);
            Plan[FM_EDGE_0 + e] = r;
        }

        placeObstacles(seed + salt * 3.19, arena);

        // Bend every route clear of the obstacles once, as part of generation. After this the
        // solve is explicit only (B), so hand edits survive.
        for (uint se = 0u; se < FM_EDGES; se++) solveRoute(se, arena);

        // Stations LAST, because they are placed in relation to the routes and the routes are
        // not final until the clearance solve above has bent them. Placing them first would put
        // every attractor beside where a route used to be.
        buildStations(arena, seed + salt * 3.19);

        sel = 0.0;
        dragOn = 0.0;
    }

    refreshPalette(palSalt);

    // --- pointer. Select and drag share pickRecord() and world space with the canvas.
    for (uint ev1 = 0u; ev1 < n; ev1++)
    {
        ViewportEvent ev = _ViewportEvents[ev1];
        if (ev.type != 5u) continue;

        float2 px = ev.position * _Resolution.xy;
        bool inPlan = fmInPlanStrip(L, px);
        float2 w = fmPxToPlan(L, px);

        if (ev.code == 1u && ev.phase == 7u)
        {
            if (inPlan) sel = (float)pickRecord(w, L, arena);
        }
        else if (ev.code == 3u)
        {
            if (ev.phase == 5u)
            {
                if (inPlan)
                {
                    uint hit = pickRecord(w, L, arena);
                    sel = (float)hit;
                    if (hit != 0u)
                    {
                        dragOn = 1.0;
                        uint idx = hit - 1u;
                        FmRec r = Plan[idx];
                        if (idx >= FM_EDGE_0 && idx < FM_EDGE_0 + FM_EDGES)
                        {
                            float2 a = fmNodeWorld((uint)r.p0, arena);
                            float2 b = fmNodeWorld((uint)r.p1, arena);
                            grab = fmEdgeHandle(a, b, float2(r.dims.x, r.dims.z)) - w;
                        }
                        else grab = fmRecWorld(r, arena) - w;
                    }
                }
            }
            else if (ev.phase == 6u && dragOn > 0.5 && sel > 0.5)
            {
                uint idx = (uint)(sel - 1.0);
                FmRec r = Plan[idx];
                float2 tgt = w + grab;

                if (idx >= FM_EDGE_0 && idx < FM_EDGE_0 + FM_EDGES)
                {
                    // Dragging the mid handle bends the route. The handle sits at t = 0.5, where
                    // a quadratic Bezier is exactly halfway between the chord midpoint and the
                    // control point — so the control offset is twice the handle's displacement,
                    // and dropping that factor makes the curve lag the cursor by half.
                    float2 a = fmNodeWorld((uint)r.p0, arena);
                    float2 b = fmNodeWorld((uint)r.p1, arena);
                    float2 off = (tgt - (a + b) * 0.5) * 2.0;
                    float cl = max(length(b - a), 1e-3);
                    if (length(off) > cl * 0.9) off = normalize(off) * cl * 0.9;
                    r.dims = float3(off.x, 0.0, off.y);
                }
                else
                {
                    float2 f = clamp(fmWorldToFoot(tgt, arena), -1.30, 1.30);
                    r.pos.x = f.x; r.pos.z = f.y;
                }
                r.flags = (float)(((uint)r.flags) | F_EDITED);
                Plan[idx] = r;
            }
            else { dragOn = 0.0; }
        }
    }

    // ---------------------------------------------------------------------------
    // EDITS ARRIVING FROM FM_STAGE.
    //
    // Applied AFTER the local pointer and keys, so if both surfaces are touched in the same
    // cook the one you are actually looking at wins — and applied BEFORE measureRoutes, so a
    // station placed from the stage is measured and drawn this cook rather than next.
    //
    // The counter is compared, never the flag. hdr.p1 is reused to carry the last value seen;
    // it held a duplicate of liveEdge, which is recomputed unconditionally at the bottom of
    // this pass and was therefore never actually read from the header.
    // ---------------------------------------------------------------------------
    {
        float lastCmd = hdr.p1;
        if (!(abs(lastCmd) < 1e12)) lastCmd = 0.0;

        if (stage_cmd > lastCmd + 0.5)
        {
            int act = (int)(stage_act + 0.5);
            float2 sw = float2(stage_x, stage_z);
            uint ssel = (uint)(stage_sel + 0.5);

            if (act == 1)
            {
                int free = -1;
                for (uint fs = 0u; fs < FM_STAS; fs++)
                    if (Plan[FM_STA_0 + fs].active < 0.5) { free = (int)fs; break; }
                if (free >= 0)
                {
                    writeStation((uint)free, sw, STA_ATTRACT, arena, seed + salt + (float)free * 17.3);
                    Plan[FM_STA_0 + (uint)free].flags = (float)F_EDITED;
                    sel = (float)(FM_STA_0 + (uint)free + 1u);
                }
            }
            else if (ssel >= 1u && ssel <= FM_STAS)
            {
                uint idx = FM_STA_0 + ssel - 1u;
                FmRec r = Plan[idx];
                if (act == 2)
                {
                    float2 f = clamp(fmWorldToFoot(sw, arena), -1.0, 1.0);
                    r.pos.x = f.x; r.pos.z = f.y;
                }
                else if (act == 3) r.pad0 += 1.0;                                  // fire
                else if (act == 4) r.active = (r.active > 0.5) ? 0.0 : 1.0;        // mute
                else if (act == 5)                                                 // delete
                {
                    FmRec z = (FmRec)0;
                    z.role = ROLE_STA;
                    z.active = 0.0;
                    Plan[idx] = z;
                    sel = 0.0;
                }

                if (act != 5)
                {
                    r.flags = (float)(((uint)r.flags) | F_EDITED);
                    Plan[idx] = r;
                    sel = (float)(idx + 1u);
                }
            }
        }
        hdr.p1 = stage_cmd;
    }

    // Routes are measured after every possible mutation this cook, so the flow strip and the
    // blocked flags describe the arrangement as it is now rather than as it was.
    measureRoutes(arena);

    // Selection is derived from the ONE stored index and written onto the records as a display
    // flag. It is never the source of truth — that is `sel` — so the two cannot disagree.
    uint liveCache = 0u, liveEdge = 0u, blocked = 0u, liveSta = 0u;
    float maxRoute = 1.0, totalRecruit = 0.0, totalPayload = 0.0;
    for (uint i = 0u; i < FM_COUNT; i++)
    {
        if (i == FM_HEADER) continue;
        FmRec r = Plan[i];
        uint f = (uint)r.flags;
        f = (sel > 0.5 && (uint)(sel - 1.0) == i) ? (f | F_SELECTED) : (f & ~F_SELECTED);
        r.flags = (float)f;
        Plan[i] = r;

        if (r.active < 0.5) continue;
        if (r.role == ROLE_STA) liveSta++;
        if (r.role == ROLE_CACHE) { liveCache++; totalPayload += r.p0; }
        if (r.role == ROLE_EDGE)
        {
            liveEdge++;
            totalRecruit += r.p2;
            maxRoute = max(maxRoute, r.p3);
            if ((f & F_BLOCKED) != 0u) blocked++;
        }
    }

    hdr.pos    = float3(sig, sel, totalPayload);
    hdr.dims   = float3(dragOn, grab.x, grab.y);
    hdr.role   = ROLE_HEADER;
    hdr.kind   = (float)max(liveEdge, 1u);
    hdr.tint   = float3(1.0, (float)liveCache, (float)blocked);
    hdr.seed   = salt;
    hdr.p0     = palSalt;
    // p1 carries the last FM_Stage command counter seen. It used to hold a copy of liveEdge,
    // which nothing read — hdr.kind already carries the lane count the layout needs.
    hdr.p2     = totalRecruit;
    hdr.p3     = maxRoute;
    hdr.flags  = (float)liveSta;
    hdr.active = 1.0;
    hdr.pad0   = lastPtr.x;
    hdr.pad1   = lastPtr.y;
    Plan[FM_HEADER] = hdr;
}
