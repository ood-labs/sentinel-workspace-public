// TP_Scope / splat.hlsl — scatter the linework.
//
// WHY SCATTER AND NOT A PER-PIXEL LOOP.
//
// The obvious way to draw a line in a compute shader is to project it and, at every pixel, ask
// how far away it is. That works for a dozen segments. This frame has on the order of fifteen
// hundred — sixteen fish each carrying a sixty-four sample trail and a forecast arc, plus the
// cage — and a per-pixel loop over those is a million distance tests per pixel. A scatter
// inverts it: one thread per SAMPLE, stamping where it lands, and the cost becomes proportional
// to the ink actually drawn rather than to the screen area it might have been drawn on.
//
// THREAD BUDGET, in one place so it cannot drift out of step with the dispatch:
//     fish work   TP_FISH_MAX * TP_PER_FISH   = 16 * 106 = 1696
//     cage        TP_CAGE_EDGES * TP_EDGE_SEG = 12 * 128 = 1536
//                                                        = 3232, under the 4096 dispatched.
#include "scope.hlsli"

RWStructuredBuffer<uint>  Acc   : register(u0);
StructuredBuffer<TpSCtl>  Ctl   : register(t1);
StructuredBuffer<TpFish>  Fish  : register(t2);
StructuredBuffer<TpRec>   Plan  : register(t3);
StructuredBuffer<float4>  Trail : register(t4);

#define TP_PER_FISH   130u
#define TP_CAGE_EDGES 12u
#define TP_EDGE_SEG   128u
#define TP_SUBSTEP    6

static uint  gW, gH, gParity;
static float gLift;

// ---------------------------------------------------------------------------
// One stamp. Projects, depth-tests against the render's own alpha, and lays a small
// anti-aliased disc into the accumulation buffer.
//
// The depth test is a FADE, not a reject. A hard reject makes every mark vanish the instant it
// passes behind a tile and the overlay reads as broken; letting an occluded mark survive at a
// fraction of its strength reads as an instrument seen through the water, which is what it is.
// ---------------------------------------------------------------------------
void tpStamp(float3 wp, uint ch, float intensity)
{
    if (intensity <= 0.002) return;

    float2 sp;
    float  dist;
    if (!tpProject(wp, float2(gW, gH), sp, dist)) return;

    float rad = max(line_width, 0.4);
    int   ir  = (int)ceil(rad) + 1;

    if (sp.x < -rad || sp.y < -rad || sp.x > (float)gW + rad || sp.y > (float)gH + rad) return;

    // Scene distance at this pixel. TP_Render writes euclidean ray distance in alpha.
    float2 uv = sp / float2(gW, gH);
    float sceneD = _Tex0.SampleLevel(LinearSampler, uv, 0).a;
    float vis = (dist <= sceneD + 1e-3) ? 1.0 : saturate(occlude);
    if (vis <= 0.002) return;

    int2 base = (int2)floor(sp);

    [loop]
    for (int y = -ir; y <= ir; y++)
    {
        for (int x = -ir; x <= ir; x++)
        {
            int2 px = base + int2(x, y);
            if (px.x < 0 || px.y < 0 || px.x >= (int)gW || px.y >= (int)gH) continue;

            float d = length((float2)px + 0.5 - sp);
            float a = saturate(1.0 - d / rad);
            a *= a;
            if (a <= 0.004) continue;

            uint idx = tpAccIndex((uint2)px, gW, gH, ch, gParity);
            uint add = (uint)(a * vis * intensity * 2048.0);
            if (add > 0u) InterlockedAdd(Acc[idx], add);
        }
    }
}

// A run of stamps between two points, so a polyline reads as a line rather than as beads.
void tpStampRun(float3 a, float3 b, uint ch, float i0, float i1)
{
    [unroll]
    for (int k = 0; k < TP_SUBSTEP; k++)
    {
        float t = ((float)k + 0.5) / (float)TP_SUBSTEP;
        tpStamp(lerp(a, b, t), ch, lerp(i0, i1, t));
    }
}

[numthreads(256, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint idx = tid.x;

    uint w, h;
    _Tex0.GetDimensions(w, h);
    gW = w; gH = h;

    TpSCtl st = Ctl[0];
    gParity = ((uint)max(st.a.w, 0.0)) & 1u;

    // WIPE THE HALF THIS COOK WILL NOT FILL.
    //
    // Nothing else clears the accumulator, and it must not be cleared as its own full-resolution
    // pass — that would cost more than the scatter that fills it. Parity means the half being
    // wiped here is never the half being stamped below and never the half being read downstream,
    // so there is nothing to order and nothing to race. Every thread takes a strided slice.
    uint halfSz = TP_ACC_CH * gW * gH;
    uint wbase = (gParity ^ 1u) * halfSz;
    [loop]
    for (uint q = idx; q < halfSz; q += 4096u) Acc[wbase + q] = 0u;

    // State the choice for the resolve. See tpAccStamp.
    if (idx == 0u) Acc[tpAccStamp(gW, gH)] = gParity;

    TpRec tank = Plan[TP_TANK];
    float3 half3 = tpTankHalf(tank);

    float cageLift = tpLayerLift(TP_LAYER_CAGE, 0.0, half3.y, explode);

    // ---------------------------------------------------------------- fish work
    if (idx < TP_FISH_MAX * TP_PER_FISH)
    {
        uint fi  = idx / TP_PER_FISH;
        uint sub = idx % TP_PER_FISH;

        TpFish f = Fish[fi];
        if (f.active < 0.5) return;

        // Fish marks never move. See tpLayerLift: they annotate fish that are visibly present
        // in the render, and a vector that has drifted off its fish is no longer about that fish.
        float3 up = float3(0.0, 0.0, 0.0);

        // ---- 0..63 : the MEASURED trail, straight out of the ring
        if (sub < TP_TRAIL)
        {
            if (show_trail < 0.5) return;
            // N slots give N-1 consecutive pairs; the Nth is the wrap seam, joining oldest to
            // newest across the whole trail. Never generate it — see the matching note in
            // TP_School's canvas for the flashing it causes.
            if (sub + 1u >= TP_TRAIL) return;

            uint head = (uint)max(st.b.x, 0.0) % TP_TRAIL;
            // Walk backwards from the head so `sub` is "samples ago" regardless of ring phase.
            uint i0 = (head + TP_TRAIL - sub) % TP_TRAIL;
            uint i1 = (head + TP_TRAIL - sub - 1u) % TP_TRAIL;

            float4 p0 = Trail[fi * TP_TRAIL + i0];
            float4 p1 = Trail[fi * TP_TRAIL + i1];
            // Never-written slots are all zeroes, so invalid is <= 0, not < 0.
            if (p0.w <= 0.0 || p1.w <= 0.0) return;
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
            if (p0.w < p1.w) return;

            // A ring that has wrapped once holds one seam where the oldest meets the newest.
            // Segments longer than a fish can swim in an interval are that seam, not motion.
            if (length(p1.xyz - p0.xyz) > f.len * 6.0) return;

            float age = (float)sub / (float)TP_TRAIL;
            float fade = lerp(1.0, 1.0 - saturate(trail_fade), age);
            tpStampRun(p0.xyz + up, p1.xyz + up, 1u, fade * line_gain, fade * line_gain * 0.92);
            return;
        }

        // ---- 64..91 : the PREDICTED arc
        //
        // NOT a re-simulation. It integrates the heading forward using the speed the fish is
        // actually carrying and the turn rate implied by its bank — TP_School banks in
        // proportion to how hard it is turning, so the bank is a readable proxy for curvature.
        // That makes the arc honest for roughly a second and progressively wrong after, which is
        // exactly why it is drawn in its own ink and faded out along its length rather than
        // being presented as if it were measured.
        if (sub < TP_TRAIL + TP_FCAST)
        {
            if (show_fcast < 0.5) return;

            uint k = sub - TP_TRAIL;
            float dtF = max(fcast_time, 0.0) / (float)TP_FCAST;

            // Recover the angular rate TP_School banked for, then step to this thread's segment.
            float turn = -f.bank / 0.22;
            float3 d = normalize(f.dir);
            float3 p = f.pos;

            [loop]
            for (uint s = 0u; s < TP_FCAST; s++)
            {
                if (s >= k) break;
                float ca = cos(turn * dtF), sa = sin(turn * dtF);
                float3 rgt = normalize(cross(d, float3(0, 1, 0)) + 1e-6);
                d = normalize(d * ca + rgt * sa);
                p += d * f.speed * dtF;
            }

            float ca2 = cos(turn * dtF), sa2 = sin(turn * dtF);
            float3 rgt2 = normalize(cross(d, float3(0, 1, 0)) + 1e-6);
            float3 d2 = normalize(d * ca2 + rgt2 * sa2);
            float3 p2 = p + d2 * f.speed * dtF;

            float t0 = (float)k / (float)TP_FCAST;
            float t1 = (float)(k + 1u) / (float)TP_FCAST;
            // Confidence falls along the arc, and the dashes state "this is a prediction"
            // without a legend.
            float dash = (fmod((float)k, 4.0) < 2.5) ? 1.0 : 0.15;
            tpStampRun(p + up, p2 + up, 2u,
                       (1.0 - t0) * line_gain * dash, (1.0 - t1) * line_gain * dash);
            return;
        }

        // ---- 106..129 : the TRANSFORM GIZMO.
        //
        // The fish's own frame, drawn as three axes in the convention every 3D tool uses: red
        // forward, green up, blue right. Taken from tpFishFrame, which is the SAME frame the
        // renderer builds the body in — including the bank roll — so the gizmo reports the
        // fish's actual orientation rather than a re-derived guess at it. Watching the green
        // axis tilt as a fish banks into a turn is the clearest read of the steering there is.
        if (sub >= TP_TRAIL + TP_FCAST + 14u)
        {
            if (show_gizmo < 0.5) return;

            uint g = sub - (TP_TRAIL + TP_FCAST + 14u);   // 0..9
            uint axis = g / 4u;                            // 0,1,2 (last two indices unused)
            if (axis > 2u) return;
            uint seg = g % 4u;

            float3 fwd, upv, rgt;
            tpFishFrame(f, fwd, upv, rgt);
            float3 dirA = (axis == 0u) ? fwd : ((axis == 1u) ? upv : rgt);

            float len = f.len * max(gizmo_size, 0.0);
            float t0 = (float)seg / 4.0;
            float t1 = (float)(seg + 1u) / 4.0;

            tpStampRun(f.pos + dirA * (len * t0), f.pos + dirA * (len * t1),
                       TP_CH_GIZ_X + axis, line_gain * 1.6, line_gain * 1.6);
            return;
        }

        // ---- 92..105 : the heading vector, a stubby arrow out of the nose
        if (show_vec < 0.5) return;
        uint v = sub - (TP_TRAIL + TP_FCAST);
        float3 d0 = normalize(f.dir);
        float vlen = f.len * (1.6 + 2.4 * saturate(f.speed / 0.6));
        float3 a0 = f.pos + up;
        float3 b0 = a0 + d0 * vlen;

        if (v < 10u)
        {
            float t0 = (float)v / 10.0, t1 = (float)(v + 1u) / 10.0;
            tpStampRun(lerp(a0, b0, t0), lerp(a0, b0, t1), 1u, line_gain * 1.5, line_gain * 1.5);
        }
        else
        {
            // barbs, so the vector reads as pointing rather than merely lying along the heading
            float3 rgt = normalize(cross(d0, float3(0, 1, 0)) + 1e-6);
            float sgn = (v & 1u) ? 1.0 : -1.0;
            float3 tipA = b0 - d0 * vlen * 0.28 + rgt * vlen * 0.16 * sgn;
            tpStampRun(b0, tipA, 1u, line_gain * 1.5, line_gain * 0.6);
        }
        return;
    }

    // ---------------------------------------------------------------- the cage
    uint c = idx - TP_FISH_MAX * TP_PER_FISH;
    if (c >= TP_CAGE_EDGES * TP_EDGE_SEG) return;
    if (show_cage < 0.5) return;

    uint e = c / TP_EDGE_SEG;
    uint s = c % TP_EDGE_SEG;

    // The interior box: the volume TP_Plan actually says the water occupies.
    float3 lo = float3(-half3.x, -half3.y, -half3.z);
    float3 hi = float3( half3.x,  0.0,      half3.z);

    float3 a, b;
    if (e < 4u)                       // verticals
    {
        float sx = (e & 1u) ? 1.0 : -1.0;
        float sz = (e & 2u) ? 1.0 : -1.0;
        a = float3(sx > 0 ? hi.x : lo.x, lo.y, sz > 0 ? hi.z : lo.z);
        b = float3(a.x, hi.y, a.z);
    }
    else                              // the two horizontal rectangles: floor, then waterline
    {
        // CORNERS IN CYCLIC ORDER, and edge k joins corner k to corner k+1. The previous form
        // derived both endpoints from separate conditionals on k, which for two of the four
        // values produced the SAME point twice — so each rectangle was really two edges and two
        // zero-length stubs. The cage was never a closed box, which is why it read as a handful
        // of splayed lines that refused to sit on the tank however the camera was matched.
        uint k = (e < 8u) ? (e - 4u) : (e - 8u);
        float y = (e < 8u) ? lo.y : hi.y;

        uint i0 = k;
        uint i1 = (k + 1u) & 3u;
        float2 c0 = float2((i0 == 0u || i0 == 3u) ? lo.x : hi.x, (i0 < 2u) ? lo.z : hi.z);
        float2 c1 = float2((i1 == 0u || i1 == 3u) ? lo.x : hi.x, (i1 < 2u) ? lo.z : hi.z);

        a = float3(c0.x, y, c0.y);
        b = float3(c1.x, y, c1.y);
    }

    float3 lift = float3(0.0, cageLift, 0.0);
    float t0 = (float)s / (float)TP_EDGE_SEG;
    float t1 = (float)(s + 1u) / (float)TP_EDGE_SEG;
    tpStampRun(lerp(a, b, t0) + lift, lerp(a, b, t1) + lift, 0u, line_gain * 0.8, line_gain * 0.8);
}
