// TP_School / canvas.hlsl — the school, as a plan and a section.
//
// This is an INSTRUMENT, not a beauty pass. TP_Render already shows what the fish look like;
// what it cannot show is why they are where they are. So this draws the two things that decide
// that and nothing else: the plan, with every fish as an arrowhead pointing where it is actually
// heading, and the section, which is the only view in the whole show where the depth envelope is
// visible as a thing the fish are being steered inside rather than as two numbers.
//
// The envelope box comes from tpSchoolBounds — the SAME function the swim pass steers off. A
// preview that draws its own idea of the boundary is worse than no preview, because it will
// agree right up until the moment something is wrong.
#include "school.hlsli"

StructuredBuffer<TpFish> Fish  : register(t0);
StructuredBuffer<TpSCtl> Ctl   : register(t1);
StructuredBuffer<TpRec>  Plan  : register(t2);
StructuredBuffer<float4> Trail : register(t3);
RWTexture2D<float4> OutputUAV  : register(u0);

static const float3 TRAILC = float3(1.00, 0.62, 0.18);
static const float3 FCASTC = float3(0.62, 0.34, 0.98);

static const float3 BG    = float3(0.055, 0.062, 0.075);
static const float3 INK   = float3(0.30, 0.34, 0.40);
static const float3 ENV   = float3(0.22, 0.52, 0.62);
static const float3 WATER = float3(0.10, 0.16, 0.20);

float tpLine(float2 p, float2 a, float2 b, float w)
{
    float2 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-6));
    return 1.0 - smoothstep(w, w * 2.0, length(pa - ba * h));
}

float tpBoxOutline(float2 p, float2 lo, float2 hi, float w)
{
    float o = 0.0;
    o = max(o, tpLine(p, float2(lo.x, lo.y), float2(hi.x, lo.y), w));
    o = max(o, tpLine(p, float2(hi.x, lo.y), float2(hi.x, hi.y), w));
    o = max(o, tpLine(p, float2(hi.x, hi.y), float2(lo.x, hi.y), w));
    o = max(o, tpLine(p, float2(lo.x, hi.y), float2(lo.x, lo.y), w));
    return o;
}

// A KITE, not an arrowhead.
//
// The previous glyph carved a notch out of a triangle to make it read as a dart, and at the size
// these are actually drawn the notch simply split it — every fish came out as two little
// triangles side by side, which is both ugly and misleading, because two marks look like two
// objects. A kite is one closed shape: nose forward, widest a third of the way back, tapering to
// the tail. That is a fish seen from above, it reads at four pixels, and it still states the
// heading unambiguously because it is asymmetric along its own axis.
float tpKite(float2 p, float2 c, float2 dir, float size)
{
    float2 f = normalize(dir + 1e-6);
    float2 r = float2(-f.y, f.x);
    float sz = max(size, 1e-5);
    float2 q = float2(dot(p - c, f), dot(p - c, r)) / sz;

    // Widest station sits FORWARD of centre; a rhombus with its waist in the middle reads as a
    // lozenge rather than as something with a front.
    const float xw = 0.15, wmax = 0.42;
    float w = (q.x >= xw) ? wmax * (1.0 - q.x) / (1.0 - xw)
                          : wmax * (q.x + 1.0) / (xw + 1.0);

    // Distance in PIXELS so the edge softness is constant regardless of glyph size.
    float d = (abs(q.y) - w) * sz;
    return 1.0 - smoothstep(0.0, 1.4, d);
}


// ---------------------------------------------------------------------------
// Trails and forecasts, drawn per pixel.
//
// This is a full-screen shader, so every fish considered costs every pixel. Sixteen fish times
// sixty-four segments is a thousand distance tests per pixel and would make the preview cost
// more than the render it is previewing — so each fish is first rejected against a circle around
// its current position, sized by how far it could possibly have swum in the ring's span. Almost
// every pixel is outside almost every fish, and the ones that are not do only the work they owe.
// ---------------------------------------------------------------------------
float tpFishReach(TpFish f)
{
    return f.speed * max(trail_rate, 0.005) * (float)TP_TRAIL * 1.15 + f.len * 2.0;
}

// Accumulated ink from one fish's recorded history. `proj` maps world -> canvas for whichever
// view is asking, encoded as origin + two basis scales so plan and section share the code.
float tpTrailInk(float2 px, uint fi, TpFish f, uint head, float2 org, float3 sxz, bool section)
{
    if (show_trail < 0.5) return 0.0;

    float ink = 0.0;
    // N slots give N-1 CONSECUTIVE pairs. The Nth pair is the wrap seam — it joins the oldest
    // sample straight to the newest — and drawing it puts a chord across the entire trail. It
    // was being culled only by the length guard below, so it appeared and vanished as the fish
    // moved and re-formed every time the head advanced: exactly the flashing at the trail
    // interval. Never generate it in the first place.
    [loop]
    for (uint k = 0u; k + 1u < TP_TRAIL; k++)
    {
        uint i0 = (head + TP_TRAIL - k) % TP_TRAIL;
        uint i1 = (head + TP_TRAIL - k - 1u) % TP_TRAIL;
        float4 a = Trail[fi * TP_TRAIL + i0];
        float4 b = Trail[fi * TP_TRAIL + i1];
        // w carries the cook time the sample was taken at. A slot that has NEVER been written is
        // all zeroes, so "not yet valid" has to be <= 0 rather than < 0 — otherwise a fresh ring
        // draws sixty-four lines converging on the tank origin.
        if (a.w <= 0.0 || b.w <= 0.0) continue;
        // TIME ORDER IS THE PROOF, not the ring index.
        //
        // Walking back from the head assumes the head slot already holds THIS cook's sample. It
        // is written this cook — but if the buffer's generation flips on write, a reader can see
        // the previous version, in which that slot still holds the OLDEST sample. The result is a
        // single frame of chord from the far end of the trail back to the fish, once per
        // interval: the flashing line.
        //
        // Every sample carries the time it was taken, so a pair walking backwards must be
        // non-increasing in time. One comparison rejects the stale slot no matter which
        // generation was served, and needs no assumption about buffer semantics at all.
        if (a.w < b.w) continue;
        if (length(b.xyz - a.xyz) > f.len * 6.0) continue;

        float2 pa = section ? float2(org.x + a.x * sxz.x, org.y - a.y * sxz.y)
                            : org + float2(a.x, a.z) * sxz.x;
        float2 pb = section ? float2(org.x + b.x * sxz.x, org.y - b.y * sxz.y)
                            : org + float2(b.x, b.z) * sxz.x;

        float age = (float)k / (float)TP_TRAIL;
        ink = max(ink, tpLine(px, pa, pb, 1.1) * lerp(1.0, 1.0 - saturate(trail_fade), age));
    }
    return ink;
}

// The predicted arc. Integrated from the heading using the turn rate implied by bank — see
// TP_School's steering — so it is an extrapolation and never a re-simulation. Dashed, because a
// prediction drawn like a measurement is a lie about how much the node knows.
float tpFcastInk(float2 px, TpFish f, float2 org, float3 sxz, bool section)
{
    if (show_fcast < 0.5 || fcast_time <= 0.001) return 0.0;

    const uint N = 20u;
    float dt = fcast_time / (float)N;
    float turn = -f.bank / 0.22;

    float3 d = normalize(f.dir);
    float3 p = f.pos;
    float ink = 0.0;

    [loop]
    for (uint k = 0u; k < N; k++)
    {
        float ca = cos(turn * dt), sa = sin(turn * dt);
        float3 rgt = normalize(cross(d, float3(0, 1, 0)) + 1e-6);
        float3 nd = normalize(d * ca + rgt * sa);
        float3 np = p + nd * f.speed * dt;

        if ((k & 1u) == 0u)
        {
            float2 pa = section ? float2(org.x + p.x * sxz.x, org.y - p.y * sxz.y)
                                : org + float2(p.x, p.z) * sxz.x;
            float2 pb = section ? float2(org.x + np.x * sxz.x, org.y - np.y * sxz.y)
                                : org + float2(np.x, np.z) * sxz.x;
            ink = max(ink, tpLine(px, pa, pb, 1.0) * (1.0 - (float)k / (float)N));
        }
        p = np; d = nd;
    }
    return ink;
}


// ---------------------------------------------------------------------------
// THE TRANSFORM GIZMO.
//
// Three axes in the convention every 3D tool uses — red forward, green up, blue right — taken
// from tpFishFrame, which is the SAME frame the renderer builds the body in. That matters: the
// gizmo reports the fish's real orientation including its bank roll, rather than a heading
// re-derived from `dir` alone, so watching the green axis tilt as a fish leans into a turn is a
// direct read of the steering rather than an illustration of it.
//
// Cheap here because the views are orthographic: no projection matrix, just the two components
// each view already shows. An axis pointing at the viewer collapses to a dot, which is correct
// and is itself information.
// ---------------------------------------------------------------------------
float3 tpGizmo(float2 px, TpFish f, float2 org, float sc, bool section)
{
    if (show_gizmo < 0.5 || gizmo_size <= 0.001) return float3(0, 0, 0);

    float3 fwd, upv, rgt;
    tpFishFrame(f, fwd, upv, rgt);
    float len = f.len * gizmo_size;

    float2 c = section ? float2(org.x + f.pos.x * sc, org.y - f.pos.y * sc)
                       : org + f.pos.xz * sc;

    float3 acc = float3(0, 0, 0);
    [unroll]
    for (int a = 0; a < 3; a++)
    {
        float3 d = (a == 0) ? fwd : ((a == 1) ? upv : rgt);
        float3 w = f.pos + d * len;
        float2 e = section ? float2(org.x + w.x * sc, org.y - w.y * sc)
                           : org + w.xz * sc;

        float ink = tpLine(px, c, e, 1.0);
        float3 col = (a == 0) ? float3(1.00, 0.20, 0.20)
                  : ((a == 1) ? float3(0.24, 1.00, 0.32) : float3(0.30, 0.46, 1.00));
        acc = max(acc, col * ink);
    }
    return acc;
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    if (tid.x >= W || tid.y >= H) return;

    float2 px = (float2)tid.xy + 0.5;
    float2 uv = px / float2(W, H);

    TpRec tank = Plan[TP_TANK];
    float3 half3 = tpTankHalf(tank);
    TpSCtl ctl = Ctl[0];

    uint n = (uint)clamp((int)fish_count, 1, (int)TP_FISH_MAX);

    float3 lo3, hi3;
    tpSchoolBounds(tank, wall_margin, depth_bias, depth_band, lo3, hi3);

    float3 col = BG;

    // Layout: plan on top (the tank footprint, fitted), section as a strip beneath it.
    float split = 0.66;
    bool inPlan = uv.y < split;

    if (inPlan)
    {
        // Fit the footprint into the plan region, aspect preserved — a stretched plan would
        // misreport the shape of the basin, which is an exploration axis on TP_Plan.
        float2 region = float2((float)W, (float)H * split);
        float2 pad = float2(28.0, 24.0);
        float2 avail = region - pad * 2.0;
        float2 ext = half3.xz * 2.0;
        float sc = min(avail.x / max(ext.x, 1e-4), avail.y / max(ext.y, 1e-4));
        float2 org = region * 0.5;

        float2 wp = (px - org) / sc;                 // world xz under this pixel
        float2 pl = org + float2(-half3.x, -half3.z) * sc;
        float2 ph = org + float2( half3.x,  half3.z) * sc;

        // water inside the tank
        if (abs(wp.x) <= half3.x && abs(wp.y) <= half3.z) col = WATER;

        // the tank wall
        col = lerp(col, INK, tpBoxOutline(px, pl, ph, 1.6));

        // the envelope the fish are actually steered inside
        float2 el = org + lo3.xz * sc;
        float2 eh = org + hi3.xz * sc;
        col = lerp(col, ENV * 0.75, tpBoxOutline(px, el, eh, 1.0) * 0.85);

        // neighbour radius, drawn once around the first fish so the flocking scale is a
        // visible distance rather than a number with no referent
        TpFish f0 = Fish[0];
        if (f0.active > 0.5)
        {
            float rr = f_radius * min(half3.x, half3.z) * sc;
            float dc = abs(length(px - (org + f0.pos.xz * sc)) - rr);
            col = lerp(col, ENV * 0.5, (1.0 - smoothstep(0.8, 2.0, dc)) * 0.5);
        }

        uint head = (uint)max(ctl.b.x, 0.0) % TP_TRAIL;

        // History and forecast first, so the fish glyphs sit on top of their own paths.
        [loop]
        for (uint t = 0u; t < TP_FISH_MAX; t++)
        {
            if (t >= n) break;
            TpFish f = Fish[t];
            if (f.active < 0.5) continue;

            // Reject the whole fish against a circle sized by how far it could have swum.
            if (length(px - (org + f.pos.xz * sc)) > tpFishReach(f) * sc) continue;

            col = lerp(col, FCASTC, tpFcastInk(px, f, org, float3(sc, sc, 0), false) * 0.85);
            col = lerp(col, TRAILC, tpTrailInk(px, t, f, head, org, float3(sc, sc, 0), false));
        }

        [loop]
        for (uint i = 0u; i < TP_FISH_MAX; i++)
        {
            if (i >= n) break;
            TpFish f = Fish[i];
            if (f.active < 0.5) continue;

            float2 c = org + f.pos.xz * sc;
            float2 d = f.dir.xz;
            if (dot(d, d) < 1e-8) d = float2(1, 0);

            // Size on the plan is the fish's REAL length, so the size variance is inspectable
            // here instead of only in the render.
            // Half-length: the kite spans -1..+1, so this makes the glyph exactly one body
            // long. Overstating it clutters the plan AND misreports Size Variance.
            float size = max(f.len * sc * 0.5, 2.5);

            float3 fc = f.tint;
            if ((int)view_mode == 1)
            {
                // Speed view: the school recoloured by how hard each fish is swimming, which is
                // how a stalled corner or a runaway shows up as a pattern rather than as one
                // fish you happen to be watching.
                float sp = saturate(f.speed / max(swim_speed * 1.5, 1e-4));
                fc = lerp(float3(0.18, 0.42, 0.85), float3(1.0, 0.72, 0.20), sp);
            }

            // depth cue: deeper fish sit back into the plate
            float dep = saturate((f.pos.y - lo3.y) / max(hi3.y - lo3.y, 1e-4));
            fc *= lerp(0.45, 1.0, dep);

            col = lerp(col, fc, tpKite(px, c, d, size));

            float3 gz = tpGizmo(px, f, org, sc, false);
            col = max(col, gz);
        }
    }
    else
    {
        // ---- section: x across, y up. The depth envelope as a band the fish live inside.
        float2 region = float2((float)W, (float)H * (1.0 - split));
        float2 p2 = float2(px.x, px.y - (float)H * split);
        float2 pad = float2(28.0, 18.0);
        float2 avail = region - pad * 2.0;
        float scx = avail.x / max(half3.x * 2.0, 1e-4);
        float scy = avail.y / max(half3.y, 1e-4);
        float sc = min(scx, scy);

        float2 org = float2(region.x * 0.5, pad.y);      // y=0 (waterline) at the top of the strip
        float2 wp = float2((p2.x - org.x) / sc, -(p2.y - org.y) / sc);

        if (abs(wp.x) <= half3.x && wp.y <= 0.0 && wp.y >= -half3.y) col = WATER;

        float2 tl = float2(org.x - half3.x * sc, org.y);
        float2 br = float2(org.x + half3.x * sc, org.y + half3.y * sc);
        col = lerp(col, INK, tpBoxOutline(p2, tl, br, 1.6));

        // the waterline, which is the one line in this strip that is a physical fact
        col = lerp(col, float3(0.45, 0.72, 0.80), tpLine(p2, tl, float2(br.x, tl.y), 1.2) * 0.9);

        float2 sl = float2(org.x + lo3.x * sc, org.y - hi3.y * sc);
        float2 sh = float2(org.x + hi3.x * sc, org.y - lo3.y * sc);
        col = lerp(col, ENV * 0.75, tpBoxOutline(p2, sl, sh, 1.0) * 0.85);

        uint head = (uint)max(ctl.b.x, 0.0) % TP_TRAIL;

        [loop]
        for (uint t = 0u; t < TP_FISH_MAX; t++)
        {
            if (t >= n) break;
            TpFish f = Fish[t];
            if (f.active < 0.5) continue;

            float2 fc2 = float2(org.x + f.pos.x * sc, org.y - f.pos.y * sc);
            if (length(p2 - fc2) > tpFishReach(f) * sc) continue;

            col = lerp(col, FCASTC, tpFcastInk(p2, f, org, float3(sc, sc, 0), true) * 0.85);
            col = lerp(col, TRAILC, tpTrailInk(p2, t, f, head, org, float3(sc, sc, 0), true));
        }

        [loop]
        for (uint i = 0u; i < TP_FISH_MAX; i++)
        {
            if (i >= n) break;
            TpFish f = Fish[i];
            if (f.active < 0.5) continue;

            float2 c = float2(org.x + f.pos.x * sc, org.y - f.pos.y * sc);
            float2 d = normalize(float2(f.dir.x, -f.dir.y) + 1e-6);
            float size = max(f.len * sc * 0.5, 2.5);
            col = lerp(col, f.tint, tpKite(p2, c, d, size));

            float3 gz = tpGizmo(p2, f, org, sc, true);
            col = max(col, gz);
        }

        // the seam between the two views
        col = lerp(col, INK * 0.6, tpLine(p2, float2(0, 0), float2(region.x, 0), 1.0));
    }

    OutputUAV[tid.xy] = float4(col, 1.0);
}
