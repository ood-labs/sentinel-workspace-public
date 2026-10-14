// Lighting plot: plan (upstage at the top, the audience below) over a front elevation that shares its
// horizontal scale, so each fixture's plan symbol sits directly above its elevation symbol. Symbols are
// the fixtures' true world bounds from the bounds pass; labels read universe.address (universe 1-based).
// Each 8x8 group first stages only the fixtures whose symbol or label can touch its tile.
#define GDTF_RENDER _Data1
#include "../_shared/fe_tables.hlsli"
#include "../_shared/fe_rig.hlsli"
#include "../_shared/plan_theme.hlsli"
#include "../_shared/ui/sui3_core.hlsli"
#include "../_shared/ui/sui3_text.hlsli"

StructuredBuffer<FeInst> RigIn : register(t0);
StructuredBuffer<float4> Bounds : register(t1);
StructuredBuffer<float4> Status : register(t2);   // status pass: (rig state, fixtures, unknown, over), (placeholders)
RWTexture2D<float4> OutputUAV : register(u0);

static const float4 PLAN = float4(20.0, 50.0, 1260.0, 532.0);
static const float4 ELEV = float4(20.0, 558.0, 1260.0, 706.0);
static const float Z_UP = -10.5;     // upstage edge of the plan (metres)
static const float Z_DOWN = 1.5;     // audience edge
static const uint P10[5] = { 1u, 10u, 100u, 1000u, 10000u };

float plotScale()
{
    float w = max(rig_width, 1.0) + 2.0;
    return min((PLAN.z - PLAN.x) / w, (PLAN.w - PLAN.y) / (Z_DOWN - Z_UP));
}
float elevScale(float sc) { return min(sc, (ELEV.w - ELEV.y - 18.0) / (max(trim, 1.0) + 1.0)); }
float centreX() { return 0.5 * (PLAN.x + PLAN.z); }
float2 planPx(float x, float z, float sc) { return float2(centreX() + x * sc, PLAN.y + (z - Z_UP) * sc); }
float2 elevPx(float x, float y, float sc, float se) { return float2(centreX() + x * sc, ELEV.w - 8.0 - y * se); }

// Identity colour by console role: movers, strobes, then washes and bars.
float3 typeColour(uint t)
{
    uint role = feTypeRole(t);
    return role == FR_ROLE_MOVER ? PT_ID_A : (role == FR_ROLE_STROBE ? PT_ID_B : PT_ID_C);
}

uint digitsOf(uint n) { return n >= 10000u ? 5u : (n >= 1000u ? 4u : (n >= 100u ? 3u : (n >= 10u ? 2u : 1u))); }

// A number, optionally zero-padded to `minDigits`.
float drawNum(float2 P, float2 anchor, float s, uint n, uint minDigits)
{
    uint d = max(digitsOf(n), minDigits);
    if (sui3RunMiss(P, anchor, s, (int)d)) return 0.0;
    float cov = 0.0;
    [loop] for (uint k = 0u; k < d; k++)
    {
        uint digit = (n / P10[min(d - 1u - k, 4u)]) % 10u;
        cov = max(cov, sui3Glyph(P, anchor + float2((float)k * SUI3_ADVANCE * s, 0.0), s, S_0 + (int)digit));
    }
    return cov;
}

// universe.address, e.g. 3.145
float drawPatch(float2 P, float2 anchor, uint u, uint a)
{
    uint ud = digitsOf(u + 1u);
    float cov = drawNum(P, anchor, 1.0, u + 1u, 1u);
    cov = max(cov, sui3Glyph(P, anchor + float2((float)ud * SUI3_ADVANCE, 0.0), 1.0, S_DT));
    cov = max(cov, drawNum(P, anchor + float2((float)(ud + 1u) * SUI3_ADVANCE, 0.0), 1.0, a, 3u));
    return cov;
}

float patchWidth(uint u) { return (float)(digitsOf(u + 1u) + 4u) * SUI3_ADVANCE; }

bool overlaps(float4 a, float4 b) { return a.x <= b.z && b.x <= a.z && a.y <= b.w && b.y <= a.w; }

groupshared uint gList[160];
groupshared uint gN;
groupshared uint gCount[3];
groupshared uint gMaxU;

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID, uint3 gid : SV_GroupID, uint gi : SV_GroupIndex)
{
    uint w, h;
    OutputUAV.GetDimensions(w, h);
    float sc = plotScale();
    float se = elevScale(sc);
    if (gi == 0u)
    {
        gN = 0u; gCount[0] = 0u; gCount[1] = 0u; gCount[2] = 0u; gMaxU = 0u;
    }
    GroupMemoryBarrierWithGroupSync();
    float4 tile = float4((float2)(gid.xy * 8u), (float2)(gid.xy * 8u + 8u));
    bool header = gid.y < 6u;
    for (uint k = gi; k < FE_N_MAX; k += 64u)
    {
        float4 lo = Bounds[k * 2u], hi = Bounds[k * 2u + 1u];
        if (lo.w > 0.5)
        {
            FeInst r = RigIn[k];
            if (header)
            {
                InterlockedAdd(gCount[min(r.group, 2u)], 1u);
                uint top = max(r.a0 > 0u ? r.u0 : 0u, max(r.a1 > 0u ? r.u1 : 0u, r.a2 > 0u ? r.u2 : 0u));
                InterlockedMax(gMaxU, top + 1u);
            }
            float2 p0 = planPx(lo.x, lo.z, sc), p1 = planPx(hi.x, hi.z, sc);
            float2 cmin = min(p0, p1), cmax = max(p0, p1);
            float lw = patchWidth(r.u0);
            float cx = 0.5 * (cmin.x + cmax.x);
            float4 pr = float4(min(cmin.x, cx - 0.5 * lw) - 2.0, cmin.y - 2.0, max(cmax.x, cx + 0.5 * lw) + 2.0, cmax.y + 16.0);
            float2 e0 = elevPx(lo.x, hi.y, sc, se), e1 = elevPx(hi.x, lo.y, sc, se);
            float4 er = float4(min(e0, e1) - 2.0, max(e0, e1) + 2.0);
            if (overlaps(tile, pr) || overlaps(tile, er))
            {
                // Label only when the neighbours in the same group leave room for it.
                float room = 1e6;
                if (k > 0u && RigIn[k - 1u].group == r.group && Bounds[(k - 1u) * 2u].w > 0.5)
                    room = min(room, abs(0.5 * (planPx(Bounds[(k - 1u) * 2u].x, 0, sc).x + planPx(Bounds[(k - 1u) * 2u + 1u].x, 0, sc).x) - cx));
                if (k + 1u < FE_N_MAX && RigIn[k + 1u].group == r.group && Bounds[(k + 1u) * 2u].w > 0.5)
                    room = min(room, abs(0.5 * (planPx(Bounds[(k + 1u) * 2u].x, 0, sc).x + planPx(Bounds[(k + 1u) * 2u + 1u].x, 0, sc).x) - cx));
                uint j;
                InterlockedAdd(gN, 1u, j);
                if (j < 160u) gList[j] = k | (room >= lw + 6.0 ? 0x80000000u : 0u);
            }
        }
    }
    GroupMemoryBarrierWithGroupSync();
    // Draw in record order, so overlapping symbols stack the same way every frame.
    if (gi == 0u)
    {
        uint n = min(gN, 160u);
        for (uint a = 1u; a < n; a++)
        {
            uint v = gList[a];
            uint b = a;
            while (b > 0u && (gList[b - 1u] & 0x7FFFFFFFu) > (v & 0x7FFFFFFFu))
            {
                gList[b] = gList[b - 1u];
                b--;
            }
            gList[b] = v;
        }
    }
    GroupMemoryBarrierWithGroupSync();
    if (tid.x >= w || tid.y >= h) return;
    float2 P = (float2)tid.xy + 0.5;

    // Chrome: wells, metre grid, stage edge, centre line, floor and trim in the elevation.
    float3 col = PT_FIELD;
    float inPlan = sui3RectIn(P, PLAN), inElev = sui3RectIn(P, ELEV);
    col = lerp(col, PT_WELL, max(inPlan, inElev));
    float2 g0 = planPx(-50.0, Z_UP, sc);
    float metre = sc;
    float2 gp = (P - planPx(0.0, 0.0, sc)) / metre;
    float2 gd = abs(frac(gp + 0.5) - 0.5) * metre;
    col += PT_GRID * inPlan * sui3Hair(min(gd.x, gd.y)) * step(6.0, metre);
    float2 edgeL = planPx(-0.5 * rig_width - 0.5, 0.0, sc), edgeR = planPx(0.5 * rig_width + 0.5, 0.0, sc);
    col += PT_RULE * inPlan * sui3Line(P, edgeL, edgeR, 1.0);                       // downstage edge, z = 0
    float2 c0 = planPx(0.0, Z_UP, sc), c1 = planPx(0.0, Z_DOWN, sc);
    col += PT_RULE * 0.6 * inPlan * sui3Hair(abs(P.x - sui3Snap(c0.x))) * step(0.5, frac(P.y / 8.0));
    float2 fl = elevPx(0.0, 0.0, sc, se), tr = elevPx(0.0, trim, sc, se);
    col += PT_RULE * inElev * sui3HairAt(P.y, fl.y);
    col += PT_DIM * 0.5 * inElev * sui3HairAt(P.y, tr.y) * step(0.5, frac(P.x / 10.0));
    col += PT_DIM * sui3Frame(P, PLAN) * 0.5 + PT_DIM * sui3Frame(P, ELEV) * 0.5;

    // Fixtures.
    uint n = min(gN, 160u);
    [loop] for (uint q = 0u; q < n; q++)
    {
        uint k = gList[q] & 0x7FFFFFFFu;
        bool label = (gList[q] & 0x80000000u) != 0u;
        FeInst r = RigIn[k];
        bool placeholder = (r.flags & FE_INST_PLACEHOLDER) != 0u;
        float4 lo = Bounds[k * 2u], hi = Bounds[k * 2u + 1u];
        float3 tc = placeholder ? PT_ALARM : typeColour(r.type);
        float2 p0 = planPx(lo.x, lo.z, sc), p1 = planPx(hi.x, hi.z, sc);
        float4 pr = float4(min(p0, p1), max(p0, p1));
        float2 pc = 0.5 * (pr.xy + pr.zw);
        pr = float4(min(pr.xy, pc - 2.0), max(pr.zw, pc + 2.0));
        float d = sui3SdRect(P, pr);
        col = lerp(col, ptSampleFill(tc), sui3Aa(d, 1.0) * 0.9);
        col += tc * 0.8 * sui3Hair(abs(d));
        // Aim tick: where the light leaves the fixture, projected on the plan (a placeholder has no face).
        uint4 geo = placeholder ? uint4(0u, 0u, 0u, 0u) : FE_TYPE_GEO_AT(r.type);
        if (geo.w > 0u)
        {
            float3 nrm = feWorldVector(r, FE_FACE_G_AT(geo.z * 4u + 1u).xyz);
            float2 aim = float2(nrm.x, nrm.z);
            if (dot(aim, aim) > 0.04)
                col += tc * sui3Line(P, pc, pc + normalize(aim) * 9.0, 1.0);
            else
                col += tc * sui3Ring(P, pc, 2.5, 1.0);   // pointing straight up or down
        }
        if (label)
            col += PT_DIM * drawPatch(P, float2(sui3Snap(pc.x - 0.5 * patchWidth(r.u0)), sui3Snap(pr.w + 2.0)), r.u0, r.a0);
        float2 e0 = elevPx(lo.x, hi.y, sc, se), e1 = elevPx(hi.x, lo.y, sc, se);
        float4 er = float4(min(e0, e1), max(e0, e1));
        float2 ec = 0.5 * (er.xy + er.zw);
        er = float4(min(er.xy, ec - 1.5), max(er.zw, ec + 1.5));
        float de = sui3SdRect(P, er);
        col = lerp(col, ptSampleFill(tc), sui3Aa(de, 1.0) * 0.9);
        col += tc * 0.8 * sui3Hair(abs(de));
    }

    // Header: title, totals, legend.
    col += PT_INK * sui3Text(P, float2(20.0, 10.0), 2.0, S_F, S_E, S_SP, S_R, S_I, S_G, 0, 0, 0, 0, 0, 0);
    uint total = gCount[0] + gCount[1] + gCount[2];
    col += PT_MID * drawNum(P, float2(150.0, 20.0), 1.0, total, 1u);
    col += PT_DIM * sui3Text(P, float2(150.0 + (float)(digitsOf(total) + 1u) * SUI3_ADVANCE, 20.0), 1.0,
                             S_F, S_I, S_X, S_T, S_U, S_R, S_E, S_S, 0, 0, 0, 0);
    uint unis = gMaxU;
    col += PT_MID * drawNum(P, float2(260.0, 20.0), 1.0, unis, 1u);
    col += PT_DIM * sui3Text(P, float2(260.0 + (float)(digitsOf(unis) + 1u) * SUI3_ADVANCE, 20.0), 1.0,
                             S_U, S_N, S_I, S_V, S_E, S_R, S_S, S_E, S_S, 0, 0, 0);
    // Legend: the console roles any type falls into.
    float lx = 560.0;
    col += PT_ID_A * sui3Aa(sui3SdRect(P, float4(lx, 22.0, lx + 8.0, 30.0)), 1.0);
    col += PT_MID * sui3Text(P, float2(lx + 14.0, 20.0), 1.0, S_M, S_O, S_V, S_E, S_R, S_S, 0, 0, 0, 0, 0, 0);
    col += PT_INK * drawNum(P, float2(lx + 63.0, 20.0), 1.0, gCount[0], 1u);
    lx = 760.0;
    col += PT_ID_B * sui3Aa(sui3SdRect(P, float4(lx, 22.0, lx + 8.0, 30.0)), 1.0);
    col += PT_MID * sui3Text(P, float2(lx + 14.0, 20.0), 1.0, S_S, S_T, S_R, S_O, S_B, S_E, S_S, 0, 0, 0, 0, 0);
    col += PT_INK * drawNum(P, float2(lx + 70.0, 20.0), 1.0, gCount[1], 1u);
    lx = 940.0;
    col += PT_ID_C * sui3Aa(sui3SdRect(P, float4(lx, 22.0, lx + 8.0, 30.0)), 1.0);
    col += PT_MID * sui3Text(P, float2(lx + 14.0, 20.0), 1.0, S_W, S_A, S_S, S_H, S_E, S_S, S_SP, S_B, S_A, S_R, S_S, 0);
    col += PT_INK * drawNum(P, float2(lx + 112.0, 20.0), 1.0, gCount[2], 1u);
    col += PT_DIM * sui3Text(P, float2(PLAN.x + 4.0, PLAN.y - 14.0), 1.0, S_P, S_L, S_A, S_N, 0, 0, 0, 0, 0, 0, 0, 0);
    // Rig status, right of the plan label: FIXTURE RIG and how many fixtures are placeholders, or NO FIXTURE RIG in
    // red when the Fixture Rig node gives no records or no tables.
    float4 st = Status[0];
    uint state = (uint)(st.x + 0.5);
    float2 sp = float2(PLAN.x + 60.0, PLAN.y - 14.0);
    float adv = SUI3_ADVANCE;
    if (state == 0u)
    {
        col += PT_MID * sui3Text(P, sp, 1.0, S_F, S_I, S_X, S_T, S_U, S_R, S_E, S_SP, S_R, S_I, S_G, 0);
        uint ph = (uint)(Status[1].x + 0.5);
        if (ph > 0u)
        {
            float2 q = sp + float2(13.0 * adv, 0.0);
            col += PT_ALARM * drawNum(P, q, 1.0, ph, 1u);
            col += PT_ALARM * sui3Text(P, q + float2((float)(digitsOf(ph) + 1u) * adv, 0.0), 1.0,
                                       S_P, S_L, S_A, S_C, S_E, S_H, S_O, S_L, S_D, S_E, S_R, ph == 1u ? 0 : S_S);
        }
    }
    else
        col += PT_ALARM * sui3Text(P, sp, 1.0, S_N, S_O, S_SP, S_F, S_I, S_X, S_T, S_U, S_R, S_E, S_SP, S_R) +
               PT_ALARM * sui3Text(P, sp + float2(12.0 * adv, 0.0), 1.0, S_I, S_G, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    col += PT_DIM * sui3Text(P, float2(ELEV.x + 4.0, ELEV.y - 14.0), 1.0, S_E, S_L, S_E, S_V, S_A, S_T, S_I, S_O, S_N, 0, 0, 0);
    OutputUAV[tid.xy] = float4(col, 1.0);
}
