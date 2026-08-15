// FM_Stage / canvas.hlsl — the program image with the stations drawn where they actually are.
//
// THE OVERLAY IS DRAWN IN WORLD SPACE, PER PIXEL. Every pixel asks the Ground lane which point
// of the sweep it is looking at, then asks the plan whether that point is inside a station. So
// a reach is not a circle pasted over the frame — it is the real disc on the ground, seen in
// perspective, lying under the ants that are inside it. Nothing here projects world to screen
// and nothing here needs a camera.
//
// A LIGHT-GROUND INK SET, for the same reason FM_Scope has one. The shared instrument palette
// is built for a near-black canvas, where the brightest mark is the most present; this overlay
// sits on a blown-out white studio sweep, where near-white is invisible and mid grey is the
// loudest thing in frame. The value ladder is inverted end to end and the two reserved hues are
// darkened so they still separate from white — the STRUCTURE and the roles are unchanged.
#include "../_shared/formic.hlsli"
#include "stage.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);
// _Tex0 the program image, _Tex1 the ground lane, _Tex5 the pheromone field — auto-declared.
StructuredBuffer<FmRec>    PlanB : register(t2);
StructuredBuffer<FmStgCtl> Ctl   : register(t3);

#define ST_BACK   float3(0.052, 0.053, 0.058)   // the bench the picture sits on
#define ST_INK    float3(0.090, 0.092, 0.100)   // a measurement
#define ST_MID    float3(0.330, 0.335, 0.345)
#define ST_RULE   float3(0.560, 0.565, 0.575)   // faint structure
#define ST_ACCENT float3(0.860, 0.330, 0.020)   // RESERVED: the selection
#define ST_ALARM  float3(0.800, 0.060, 0.120)   // RESERVED: switched off / consuming

float3 inkOver(float3 base, float3 ink, float a) { return lerp(base, ink, saturate(a)); }

float sdSeg(float2 p, float2 a, float2 b)
{
    float2 pa = p - a, ba = b - a;
    return length(pa - ba * saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6)));
}
float lineA(float2 p, float2 a, float2 b, float w) { return 1.0 - smoothstep(0.0, w, sdSeg(p, a, b)); }
float discA(float2 p, float2 c, float r)           { return 1.0 - smoothstep(r - 1.0, r + 1.0, length(p - c)); }
float ringA(float2 p, float2 c, float r, float w)  { return 1.0 - smoothstep(0.0, w, abs(length(p - c) - r)); }

// ---------------------------------------------------------------------------
// THE PLAN VIEW — straight down on the whole arena, with the live colony on it.
//
// This is the view the project was missing. FM_Plan owns the arrangement but sits UPSTREAM of
// the ants and cannot see them without making the graph a cycle; FM_Colony can see the ants but
// does not own the arrangement and cannot be edited. This node is downstream of both, so it is
// the only place the diagram and the traffic can be the same picture — and the only place you
// can drag a station while watching what the drag does to the column.
//
// It shares fmTopFit with FM_Plan's diagram strip and FM_Colony's live view, so all three are
// the same way up. They were not: two of them were mirror images and neither said so.
// ---------------------------------------------------------------------------
float3 drawPlanView(float2 px, float2 res, FmRec arena, uint sel)
{
    FmTop T = fmTopFit(float2(0, 0), res, arena, FM_STAGE_PLAN_INSET);
    float2 ah = fmArenaHalf(arena);
    float hair = max(res.x / 1280.0, 0.75);

    float2 w = fmPxToTop(T, px);
    bool inArena = (abs(w.x) <= ah.x && abs(w.y) <= ah.y);

    float3 col = ST_BACK;
    if (inArena) col = lerp(ST_BACK, float3(0.085, 0.087, 0.094), saturate(plan_ground));

    // --- the scent, if asked for. Off by default: it is the colony's own diagnostic and on a
    // working view it competes with the thing you are placing.
    if (inArena && plan_field > 0.001)
    {
        float4 f = _Tex5.SampleLevel(LinearSampler, fmWorldToFieldUV(w, arena), 0);
        float food = saturate(f.r * plan_field);
        float home = saturate(f.g * plan_field);
        col = inkOver(col, float3(0.62, 0.60, 0.55), pow(food, 0.62) * 0.55);
        col = inkOver(col, float3(0.30, 0.36, 0.44), pow(home, 0.75) * 0.30);
    }

    // --- a 10 mm grid, the ruler of the whole drawing
    if (inArena)
    {
        float2 g = abs(frac(w / 10.0 + 0.5) - 0.5) * 10.0 * T.scale;
        col = inkOver(col, float3(0.16, 0.163, 0.172), (1.0 - smoothstep(0.0, hair * 1.1, min(g.x, g.y))) * 0.9);
        float2 g5 = abs(frac(w / 50.0 + 0.5) - 0.5) * 50.0 * T.scale;
        col = inkOver(col, float3(0.26, 0.265, 0.275), (1.0 - smoothstep(0.0, hair * 1.2, min(g5.x, g5.y))) * 0.85);
    }

    // --- arena frame
    {
        float2 aLo, aHi; fmTopBoxPx(T, -ah, ah, aLo, aHi);
        float d = max(max(aLo.x - px.x, px.x - aHi.x), max(aLo.y - px.y, px.y - aHi.y));
        col = inkOver(col, float3(0.42, 0.425, 0.435), (1.0 - smoothstep(0.0, hair * 1.6, abs(d))) * 0.9);
    }

    // --- obstacles, from the same signed distance function the colony steers on
    for (uint oi = 0u; oi < FM_OBSTS; oi++)
    {
        FmRec o = PlanB[FM_OBST_0 + oi];
        if (o.active < 0.5) continue;
        float d = fmObstDist(w, o, arena) * T.scale;
        col = inkOver(col, float3(0.20, 0.20, 0.21), 1.0 - smoothstep(0.0, 1.5, d));
        col = inkOver(col, float3(0.48, 0.48, 0.49), 1.0 - smoothstep(0.0, hair * 1.3, abs(d)));
    }

    // --- routes
    for (uint ei = 0u; ei < FM_EDGES; ei++)
    {
        FmRec r = PlanB[FM_EDGE_0 + ei];
        if (r.active < 0.5) continue;
        float2 A = fmRecWorld(PlanB[(uint)r.p0], arena);
        float2 B = fmRecWorld(PlanB[(uint)r.p1], arena);
        float2 ctrl = float2(r.dims.x, r.dims.z);
        float best = 1e9;
        for (uint k = 0u; k < 24u; k++)
        {
            float2 p0 = fmTopToPx(T, fmRoutePoint(A, B, ctrl, (float)k / 24.0));
            float2 p1 = fmTopToPx(T, fmRoutePoint(A, B, ctrl, (float)(k + 1u) / 24.0));
            best = min(best, sdSeg(px, p0, p1));
        }
        bool blocked = (((uint)r.flags) & F_BLOCKED) != 0u;
        col = inkOver(col, blocked ? ST_ALARM : float3(0.40, 0.40, 0.41),
                      (1.0 - smoothstep(0.0, hair * 1.6, best)) * 0.85);
    }

    // --- nest and caches
    {
        FmRec nr = PlanB[FM_NEST];
        if (nr.active > 0.5)
        {
            float2 c = fmTopToPx(T, fmRecWorld(nr, arena));
            float rad = max(nr.dims.x * T.scale, 5.0 * hair);
            col = inkOver(col, float3(0.04, 0.04, 0.045), discA(px, c, rad));
            col = inkOver(col, float3(0.70, 0.70, 0.71), ringA(px, c, rad, hair * 1.8));
        }
        for (uint ci = 0u; ci < FM_CACHES; ci++)
        {
            FmRec cr = PlanB[FM_CACHE_0 + ci];
            if (cr.active < 0.5) continue;
            float2 c = fmTopToPx(T, fmRecWorld(cr, arena));
            float rad = max(cr.dims.x * T.scale, 4.0 * hair);
            col = inkOver(col, float3(0.34, 0.33, 0.28), discA(px, c, rad) * 0.75);
            col = inkOver(col, float3(0.68, 0.66, 0.58), ringA(px, c, rad, hair * 1.4));
        }
    }

    // --- THE LIVE COLONY, SAMPLED. FM_Colony bakes the ants as oriented ticks into the Field
    // output's alpha, in arena space, using the bucket grid.
    //
    // The obvious implementation — loop the population here and draw each tick — is 1024 record
    // loads for every pixel of a 1280x720 frame, which is 943 million a frame and is exactly the
    // mistake the contact shadows made. A per-pixel loop over a population is never the answer
    // in this project; the grid exists so that it never has to be.
    if (plan_ants > 0.5 && inArena)
    {
        float t = _Tex5.SampleLevel(LinearSampler, fmWorldToFieldUV(w, arena), 0).a;
        col = inkOver(col, float3(0.86, 0.85, 0.82), saturate(t) * 0.95);
    }

    // --- STATIONS, last, because they are the layer you are working on.
    for (uint si = 0u; si < FM_STAS; si++)
    {
        FmRec r = PlanB[FM_STA_0 + si];
        if (r.active < 0.5) continue;

        bool selHere = (sel == si + 1u);
        int k = (int)(r.kind + 0.5);
        int md = (int)(r.p1 + 0.5);
        float2 c = fmTopToPx(T, fmRecWorld(r, arena));
        float reach = fmStaRadius(r) * T.scale;
        float3 ink = selHere ? ST_ACCENT : float3(0.80, 0.80, 0.81);

        if (show_reach > 0.5)
        {
            col = inkOver(col, selHere ? ST_ACCENT : float3(0.38, 0.38, 0.39),
                          ringA(px, c, reach, hair * (selHere ? 1.7 : 1.1)) * (selHere ? 1.0 : 0.7));
            col = inkOver(col, (k == 2) ? float3(0.34, 0.26, 0.26) : ink,
                          (1.0 - smoothstep(0.0, reach, length(px - c))) * (selHere ? 0.16 : 0.08));
            // A pulsing station's ring is dashed, so "this one beats" is visible in a still.
            if (md == 1 && (k == 1 || k == 2))
            {
                float ang = atan2(px.y - c.y, px.x - c.x);
                col = inkOver(col, ST_BACK, ringA(px, c, reach, hair * 2.2) * step(0.5, frac(ang * 5.7296)) * 0.9);
            }
        }

        float hr = 8.0 * hair;
        col = inkOver(col, ink, ringA(px, c, hr, hair * 1.6));
        col = inkOver(col, (k == 3) ? float3(0.05, 0.05, 0.06) : ink, discA(px, c, hr * 0.72) * ((k == 3) ? 0.95 : 0.30));

        // Four arms: out for an emitter, in for an attractor, out with a bar for a repeller,
        // short and in for a sink. Same vocabulary as FM_Plan's diagram.
        {
            float2 rel = px - c;
            float dd = length(rel);
            float ang = atan2(rel.y, rel.x);
            float arm = abs(frac(ang / 1.5707963 + 0.5) - 0.5) * 1.5707963 * dd;
            float band = step(hr * 1.35, dd) * step(dd, (k == 3) ? hr * 2.05 : hr * 2.8);
            col = inkOver(col, ink, (1.0 - smoothstep(0.0, hair * 1.5, arm)) * band * 0.85);
        }

        if (k == 0)
        {
            float2 av = float2(cos(r.pos.y), sin(r.pos.y)) * T.axis;
            float t = dot(px - c, av);
            float perp = length((px - c) - av * t);
            col = inkOver(col, ink, (1.0 - smoothstep(0.0, hair * 1.6, perp)) * step(0.0, t) * step(t, reach * 0.55) * 0.85);
        }
        if (!(k == 1) && k == 2)
            col = inkOver(col, ink, lineA(px, c - float2(hr, 0), c + float2(hr, 0), hair * 1.9));
        if (k == 3 && md == 1)
            col = inkOver(col, ST_ALARM, lineA(px, c - hr * 0.8, c + hr * 0.8, hair * 1.6));
    }

    // --- the scale bar IS an ant, the same rule the plan canvas uses: every extent readable in
    // workers rather than in millimetres.
    {
        float2 sb = float2(res.x * 0.020, res.y * 0.968);
        float2 sbe = sb + float2(10.0 * T.scale, 0.0);
        float3 dim = float3(0.34, 0.345, 0.355);
        col = inkOver(col, dim, lineA(px, sb, sbe, hair * 1.3));
        col = inkOver(col, dim, lineA(px, sb + float2(0, -4.0 * hair), sb + float2(0, 4.0 * hair), hair * 1.3));
        col = inkOver(col, dim, lineA(px, sbe + float2(0, -4.0 * hair), sbe + float2(0, 4.0 * hair), hair * 1.3));
    }

    return col;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    if (DTid.x >= W || DTid.y >= H) return;

    float2 px = (float2)DTid.xy + 0.5;
    float2 res = float2(W, H);

    FmRec arenaR = PlanB[FM_ARENA];
    uint selR = (uint)max(Ctl[0].sel, 0.0);

    // ---- PLAN VIEW. Same records, same stations, same verbs — a different projection.
    if (((int)view) == 1)
    {
        OutputUAV[DTid.xy] = float4(drawPlanView(px, res, arenaR, selR), 1.0);
        return;
    }

    uint gw, gh;
    _Tex1.GetDimensions(gw, gh);
    FmStage stg = fmStage(res, float2(max((float)gw, 1.0), max((float)gh, 1.0)));

    float3 col = ST_BACK;

    if (!fmStageInside(stg, px))
    {
        OutputUAV[DTid.xy] = float4(col, 1.0);
        return;
    }

    float2 uv = fmStageUV(stg, px);

    // THE PROGRAM IMAGE, FITTED. Never stretched: a canonical frame distorted to fill a dock is
    // no longer the frame that was composed.
    col = _Tex0.SampleLevel(LinearSampler, uv, 0).rgb;

    float mix = saturate(overlay_mix);
    if (mix <= 0.001)
    {
        // A true pass-through at zero, so a capture taken through this node is bit-for-bit the
        // picture FM_Post produced.
        OutputUAV[DTid.xy] = float4(col, 1.0);
        return;
    }

    float4 g = _Tex1.SampleLevel(LinearSampler, uv, 0);
    if (g.b < 0.995)
    {
        OutputUAV[DTid.xy] = float4(col, 1.0);
        return;
    }
    float2 w = g.rg;

    // World millimetres per pixel, differenced by hand. There are no derivatives in a compute
    // shader — fwidth is a cryptic X4532 here — so the neighbouring texel is sampled and the
    // difference taken, which is what a derivative is. This is what keeps a ring that lies flat
    // on a receding plane the same THICKNESS on screen at the front of the plate and the back.
    float wpp;
    {
        float2 duv = float2(1.0, 0.0) / max(stg.hi - stg.lo, 1e-3);
        float4 g2 = _Tex1.SampleLevel(LinearSampler, uv + duv, 0);
        wpp = (g2.b > 0.995) ? max(length(g2.rg - w), 1e-4) : 0.25;
    }
    float lw = max(line_px, 0.5) * wpp;

    FmRec arena = PlanB[FM_ARENA];
    uint sel = (uint)max(Ctl[0].sel, 0.0);

    float3 over = col;

    for (uint s = 0u; s < FM_STAS; s++)
    {
        FmRec r = PlanB[FM_STA_0 + s];
        if (r.active < 0.5) continue;

        bool selHere = (sel == s + 1u);
        int k = (int)(r.kind + 0.5);
        int md = (int)(r.p1 + 0.5);

        float2 c = fmRecWorld(r, arena);
        float d = length(w - c);
        float reach = fmStaRadius(r);

        float3 ink = selHere ? ST_ACCENT : ST_INK;

        // THE REACH, as the real disc. A very faint interior wash as well as the rim, because a
        // rim alone on a busy photograph reads as a scratch on the print; the wash is what says
        // "these ants, the ones inside here, are the ones this is acting on".
        if (show_reach > 0.5)
        {
            float rim = 1.0 - smoothstep(0.0, lw * 1.6, abs(d - reach));
            over = inkOver(over, selHere ? ST_ACCENT : ST_RULE, rim * (selHere ? 0.95 : 0.55));

            float fillA = (1.0 - smoothstep(reach * 0.0, reach, d)) * (selHere ? 0.13 : 0.06);
            // A repeller's wash is pushed toward the alarm end of the ladder rather than given
            // a hue of its own: it is the one station that takes territory away.
            over = inkOver(over, (k == 2) ? ST_MID : ink, fillA);
        }

        // THE HANDLE. Sized in SCREEN pixels through wpp, not in millimetres, so the thing you
        // grab is the same size wherever it is on the plate — a handle that shrinks with
        // distance is a handle you cannot hit at the back of the frame.
        float hr = 7.0 * wpp;
        float dot0 = 1.0 - smoothstep(hr * 0.72, hr, d);
        float ring = 1.0 - smoothstep(0.0, lw * 1.5, abs(d - hr));
        over = inkOver(over, ink, ring * 0.95);
        over = inkOver(over, (k == 3) ? ST_INK : ink, dot0 * ((k == 3) ? 0.85 : 0.28));

        // WHAT IT DOES, as four arms rather than four colours. Same vocabulary as the plan
        // canvas so the two drawings read as one instrument: out for an emitter, in for an
        // attractor, out with a bar for a repeller, in and short for a sink.
        {
            float2 rel = w - c;
            float ang = atan2(rel.y, rel.x);
            // four arms at the diagonals
            float arm = abs(frac(ang / 1.5707963 + 0.5) - 0.5) * 1.5707963;
            float armMask = 1.0 - smoothstep(0.0, lw * 1.4 / max(d, 1e-3), arm);

            float lo0 = (k == 1 || k == 3) ? hr * 1.35 : hr * 1.35;
            float hi0 = (k == 3) ? hr * 2.0 : hr * 2.7;
            float band = step(lo0, d) * step(d, hi0);
            over = inkOver(over, ink, armMask * band * 0.8);
        }

        // An EMITTER has an orientation and nothing else here does, so it gets the one extra
        // mark: its aim, drawn as a real vector on the ground.
        if (k == 0)
        {
            float2 av = float2(cos(r.pos.y), sin(r.pos.y));
            float t = dot(w - c, av);
            float perp = length((w - c) - av * t);
            float seg = step(0.0, t) * step(t, reach * 0.55);
            over = inkOver(over, ink, (1.0 - smoothstep(0.0, lw * 1.5, perp)) * seg * 0.85);
        }

        // Two states get the reserved alarm, and nothing else does: a station that is switched
        // off, and a sink set to CONSUME, which is the one setting in this whole system that
        // permanently removes ants from the pool.
        if (k == 3 && md == 1)
        {
            float bar = 1.0 - smoothstep(0.0, lw * 1.5, abs(dot(w - c, normalize(float2(1.0, 1.0)))));
            over = inkOver(over, ST_ALARM, bar * step(d, hr * 1.9) * 0.9);
        }
    }

    col = lerp(col, over, mix);
    OutputUAV[DTid.xy] = float4(col, 1.0);
}
