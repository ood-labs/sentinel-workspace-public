// FM_Colony / canvas.hlsl — the colony's own instrument.
//
// TWO STRIPS, and the second one is the reason this node has a preview at all.
//
//   ARENA    the field the ants are steering on, with the ants on it. Trails are the SUBJECT
//            here, not the ants: what this strip is for is watching a trail form, sharpen and
//            fade, which is invisible in the render because the render shows six ants and no
//            chemistry.
//
//   GAIT     a Hildebrand footfall chart for the focused ant. Six lanes, time running left to
//            right, a bar wherever a leg was bearing weight. The lanes are ordered BY TRIPOD
//            rather than by leg number, so the alternation is a checkerboard when the gait is
//            right and visibly is not when it is wrong.
//
//            This is the readout the renderer cannot give. A still frame of an ant shows six
//            legs in some arrangement and says nothing about whether the two tripods are
//            actually anti-phase, and a foot that scuffs the ground is completely invisible in
//            a still and nearly invisible in motion — but it is the single most common defect
//            in a procedural walk. Measured slip is drawn in alarm red on the bar it happened
//            on, so the fault has a leg and a moment attached to it.
#include "../_shared/formic.hlsli"
#include "../_shared/plan_theme.hlsli"
#include "../_shared/readout.hlsli"
#include "colony.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);
StructuredBuffer<FmAnt>  Ants  : register(t0);
StructuredBuffer<FmFoot> Feet  : register(t1);
StructuredBuffer<FmMeas> Meas  : register(t2);
StructuredBuffer<FmRec>  PlanB : register(t3);
// _Tex4 — the pheromone field, auto-declared.
StructuredBuffer<FmGait> Hist  : register(t5);

// The arena view takes three quarters of the canvas and the gait chart is a compact strip under
// it. It used to be a near-even split, which gave the live colony half a panel and spent the
// other half on a six-lane chart of ONE ant's feet. The chart still earns a place — it is the
// only readout that can show whether the tripod is alternating — but it is a check you glance
// at, not the thing you watch.
#define AR_T 0.062
#define AR_B 0.790
#define GT_T 0.838
#define GT_B 0.960
#define DR_L 0.020
#define DR_R 0.752
#define CO_L 0.770
#define CO_R 0.984

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 px = (float2)pixel + 0.5;
    float2 res = _Resolution.xy;

    FmRec arena = PlanB[FM_ARENA];
    FmMeas ms = Meas[0];
    float2 ahalf = fmArenaHalf(arena);
    uint focus = min((uint)focus_ant, FM_MAX_ANTS - 1u);
    uint n = min((uint)ant_count, FM_MAX_ANTS);

    float3 col = PT_FIELD;
    float hair = max(res.x / 1200.0, 0.75);

    // --- title
    float titleY = 0.052 * res.y;
    if (px.y < titleY)
    {
        float th = 11.0 * hair;
        float2 org = float2(DR_L * res.x, titleY * 0.5 - th * 0.5);
        col = fmInk(col, PT_INK, fmLabel(px, org, th,
                    uint2(mf_pack1(GC, GO, GL, GO, GN), mf_pack1(GY, 0u, 0u, 0u, 0u)), 6u));
        float th2 = th * 0.82;
        float2 o2 = org + float2(fmLabelW(th, 7u), 0.0);
        col = fmInk(col, PT_DIM, fmLabel(px, o2, th2,
                    uint2(mf_pack1(GS, GT, GI, GG, GM), mf_pack1(GE, GR, GG, GY, 0u)), 9u));
    }
    col = fmInk(col, PT_RULE, fmLineMask(px, float2(DR_L * res.x, titleY), float2(CO_R * res.x, titleY), hair));

    // ---------------------------------------------------------------------------
    // ARENA STRIP
    // ---------------------------------------------------------------------------
    float2 arLo = float2(DR_L * res.x, AR_T * res.y);
    float2 arHi = float2(DR_R * res.x, AR_B * res.y);

    // THE SHARED TOP-DOWN PROJECTION, not a private one.
    //
    // This strip used to compute its own mapping with world +x to the right. The plan was
    // corrected to draw +x to the LEFT — the half-turn that puts the viewer at the bottom edge
    // for a camera on the +z side — and this strip was not, so the two top-down views of the
    // same colony were mirror images of each other with nothing on either to say so. The page
    // orientation now travels in the arena record and both read it from there.
    FmTop T = fmTopFit(arLo, arHi, arena, 0.96);
    float scale = T.scale;
    float2 arC = T.c;

    if (px.x >= arLo.x && px.x <= arHi.x && px.y >= arLo.y && px.y <= arHi.y)
    {
        float2 w = fmPxToTop(T, px);
        bool inArena = (abs(w.x) <= ahalf.x && abs(w.y) <= ahalf.y);
        if (inArena) col = PT_WELL;

        if (inArena)
        {
            float4 f = _Tex4.SampleLevel(LinearSampler, fmWorldToFieldUV(w, arena), 0);

            // FOOD scent gets the VALUE ramp, because it is the trail that matters — the one
            // that recruits — and value is the strongest channel available.
            //
            // HOME scent gets a muted identity hue, and this is one of the two places in the
            // canvas where hue is spent. Two chemicals, both drawn as intensity fields, lying
            // on top of each other in exactly the same places: value alone genuinely cannot
            // say which is which, and telling them apart is the whole content of the strip.
            float food = saturate(f.r * field_gain);
            float home = saturate(f.g * field_gain);
            col = fmInk(col, ptRamp(0.30 + 0.70 * food), pow(food, 0.62) * 0.92);
            col = fmInk(col, ptSampleFill(ptId(0)), pow(home, 0.75) * 0.45);

            // substrate
            col = fmInk(col, PT_GRID * 2.0, saturate(f.b) * 0.85);
        }

        { float2 aLo, aHi; fmTopBoxPx(T, -ahalf, ahalf, aLo, aHi);
            col = fmInk(col, PT_RULE, fmRectFrame(px, aLo, aHi, hair * 1.4)); }

        // --- the plan's structures, thin. Same records, so this strip and the plan canvas
        // cannot disagree about where anything is.
        {
            FmRec nr = PlanB[FM_NEST];
            float2 nw = fmTopToPx(T, fmRecWorld(nr, arena));
            col = fmInk(col, PT_DIM, fmRingMask(px, nw, max(nr.dims.x * scale, 4.0 * hair), hair * 1.4));
            for (uint c = 0u; c < FM_CACHES; c++)
            {
                FmRec cr = PlanB[FM_CACHE_0 + c];
                if (cr.active < 0.5) continue;
                float2 cw = fmTopToPx(T, fmRecWorld(cr, arena));
                col = fmInk(col, PT_DIM, fmRingMask(px, cw, max(cr.dims.x * scale, 3.0 * hair), hair * 1.2));
            }
        }

        // --- the ants
        for (uint i = 0u; i < n; i++)
        {
            FmAnt a = Ants[i];
            if (a.active < 0.5) continue;
            bool isFocus = (i == focus);

            float2 c = fmTopToPx(T, a.pos.xz);
            // The heading is a WORLD direction and everything below uses it in PAGE space, so it
            // goes through the page axis too. Positions alone are not enough: with the axis
            // applied to the dots and not to the vectors, every ant would sit in the right place
            // facing the mirror image of where it is actually walking, which reads as a colony
            // that is somehow moving backwards.
            float2 d = normalize(a.dir.xz + float2(1e-5, 0.0)) * T.axis;
            float bl = a.size * scale;

            // Only the focused ant is drawn in the accent. Every ant amber would spend the
            // reserved colour on the most numerous thing on the canvas and leave nothing to
            // mark the one being inspected.
            float3 ink = isFocus ? PT_ACCENT : PT_MID;

            // Body as an oriented tick: the mesosoma line plus a heading mark. A dot would show
            // position and throw away the heading, which is half of what an ant record is.
            col = fmInk(col, ink, fmLineMask(px, c - d * bl * 0.45, c + d * bl * 0.45, max(bl * 0.16, hair * 1.2)));
            col = fmInk(col, ink, fmDiscMask(px, c + d * bl * 0.55, max(bl * 0.11, hair)));

            // A LADEN ant carries a mark. Task is a closed set of four and this says the one
            // thing that matters about it — is it bringing something back — using shape, so no
            // hue is spent on it.
            if (a.load > 0.5)
                col = fmInk(col, ink, fmRingMask(px, c - d * bl * 0.62, max(bl * 0.22, hair * 2.0), hair * 1.2));

            // --- FEET. The proof of the gait, and the reason this strip is worth its cost: a
            // planted foot is filled, a swinging foot is hollow, and in a still frame you can
            // count three filled and three hollow per ant and see the tripod.
            if (show_feet > 0.5 && (isFocus || foot_all > 0.5))
            {
                for (uint lg = 0u; lg < FM_LEGS; lg++)
                {
                    FmFoot ft = Feet[i * FM_LEGS + lg];
                    float2 fp = fmTopToPx(T, ft.pos.xz);
                    float3 fink = (ft.slip > slip_alarm) ? PT_ALARM : (isFocus ? PT_ACCENT : PT_RULE);
                    if (ft.stance > 0.5)
                    {
                        col = fmInk(col, fink, fmDiscMask(px, fp, max(bl * 0.09, hair * 1.3)));
                        col = fmInk(col, fink, fmLineMask(px, c, fp, hair * 0.7) * 0.35);
                    }
                    else
                    {
                        col = fmInk(col, fink, fmRingMask(px, fp, max(bl * 0.09, hair * 1.3), hair * 0.9) * 0.8);
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------------------
    // GAIT STRIP — the Hildebrand chart.
    // ---------------------------------------------------------------------------
    float2 gtLo = float2(DR_L * res.x + 40.0 * hair, GT_T * res.y);
    float2 gtHi = float2(DR_R * res.x, GT_B * res.y);

    if (px.x >= DR_L * res.x && px.x <= gtHi.x && px.y >= gtLo.y - 16.0 * hair && px.y <= gtHi.y + 4.0 * hair)
    {
        FmGait hdr = Hist[0];
        uint cursor = (uint)max(hdr.t, 0.0) % FM_GAIT_HIST;
        uint written = (uint)max(hdr.bits, 0.0);

        // Lane order is BY TRIPOD: group 0 (left front, left rear, right middle) then group 1.
        // Ordered by leg number instead, the chart is a plausible-looking mess; ordered by
        // tripod, a correct gait is unmistakably three-on / three-off and a broken one is
        // unmistakably not.
        uint order[6] = { 0u, 2u, 4u, 1u, 3u, 5u };
        float laneH = (gtHi.y - gtLo.y) / 7.0;

        col = fmInk(col, PT_DIM, fmLabel(px, float2(DR_L * res.x, gtLo.y - 14.0 * hair), 7.5 * hair,
                    uint2(mf_pack1(GG, GA, GI, GT, 0u), 0u), 4u) * 0.9);
        col = fmInk(col, PT_DIM, fmNumR(px, float2(DR_L * res.x + fmLabelW(7.5 * hair, 8u), gtLo.y - 14.0 * hair),
                    7.5 * hair, focus, 2u) * 0.9);

        for (uint r = 0u; r < 6u; r++)
        {
            uint leg = order[r];
            float y0 = gtLo.y + (float)r * laneH;
            float2 lc = float2(0.0, y0 + laneH * 0.5);

            // lane label: L or R plus the pair number
            uint sideG = (leg < 3u) ? GL : GR;
            col = fmInk(col, PT_DIM, fmLabel(px, float2(DR_L * res.x, lc.y - 3.5 * hair), 7.0 * hair,
                        uint2(mf_pack1(sideG, 1u + (leg % 3u), 0u, 0u, 0u), 0u), 2u) * 0.85);

            col = fmInk(col, PT_GRID, fmLineMask(px, float2(gtLo.x, lc.y + laneH * 0.5),
                                                 float2(gtHi.x, lc.y + laneH * 0.5), hair) * 0.6);

            if (px.x < gtLo.x || px.x > gtHi.x) continue;

            // Time maps oldest-left to newest-right. The ring is walked from the cursor so the
            // trace scrolls rather than jumping when the write wraps.
            float u = (px.x - gtLo.x) / max(gtHi.x - gtLo.x, 1.0);
            uint span = max(written, 1u);
            uint back = (uint)((1.0 - u) * (float)(span - 1u) + 0.5);
            if (back >= span) continue;
            uint idx = (cursor + FM_GAIT_HIST - 1u - back) % FM_GAIT_HIST;
            FmGait s = Hist[1u + idx];

            uint bits = (uint)(s.bits + 0.5);
            bool down = ((bits >> leg) & 1u) != 0u;

            if (down)
            {
                float m = fmRectMask(px, float2(px.x - 1.0, lc.y - laneH * 0.32),
                                          float2(px.x + 1.0, lc.y + laneH * 0.32));
                // Group 0 sits one value step above group 1 so the two tripods are separable
                // even where the chart is dense; both stay grey, because which tripod is which
                // is ordinal information a value can carry.
                col = fmInk(col, (fmLegGroup(leg) == 0u) ? PT_INK : PT_MID, m);

                if (s.slip > slip_alarm)
                    col = fmInk(col, PT_ALARM, fmRectMask(px, float2(px.x - 1.0, lc.y - laneH * 0.32),
                                                               float2(px.x + 1.0, lc.y - laneH * 0.10)));
            }
        }

        // The speed trace along the bottom lane, so the chart says whether a gap in the bars is
        // a stride hand-over or the ant simply standing still at a food pile.
        {
            float y0 = gtLo.y + 6.0 * laneH;
            if (px.x >= gtLo.x && px.x <= gtHi.x && px.y >= y0 && px.y <= y0 + laneH)
            {
                float u = (px.x - gtLo.x) / max(gtHi.x - gtLo.x, 1.0);
                uint span = max(written, 1u);
                uint back = (uint)((1.0 - u) * (float)(span - 1u) + 0.5);
                uint idx = (cursor + FM_GAIT_HIST - 1u - min(back, span - 1u)) % FM_GAIT_HIST;
                FmGait s = Hist[1u + idx];
                float v = saturate(s.speed / max(walk_speed * 1.6, 1e-3));
                float ly = y0 + laneH * (1.0 - v * 0.86) - laneH * 0.07;
                col = fmInk(col, PT_MID, 1.0 - smoothstep(hair * 0.8, hair * 1.8, abs(px.y - ly)));
                col = fmInk(col, PT_DIM, fmLabel(px, float2(DR_L * res.x, y0 + laneH * 0.5 - 3.5 * hair),
                            7.0 * hair, uint2(mf_pack1(GV, 0u, 0u, 0u, 0u), 0u), 1u) * 0.8);
            }
        }

        // the live edge
        col = fmInk(col, PT_ACCENT, fmLineMask(px, float2(gtHi.x, gtLo.y), float2(gtHi.x, gtHi.y), hair * 1.2) * 0.9);
    }

    // ---------------------------------------------------------------------------
    // READOUT COLUMN — measured, not restated.
    // ---------------------------------------------------------------------------
    float colL = CO_L * res.x;
    if (px.x >= colL - 10.0 * hair)
    {
        col = fmInk(col, PT_RULE, fmLineMask(px, float2(colL - 12.0 * hair, AR_T * res.y),
                                             float2(colL - 12.0 * hair, GT_B * res.y), hair) * 0.7);
        float th = 8.5 * hair, row = 15.0 * hair;
        float y = AR_T * res.y + 4.0 * hair;
        float rx = CO_R * res.x;

        col = fmInk(col, PT_DIM, fmLabel(px, float2(colL, y), th, uint2(mf_pack1(GC, GA, GS, GT, 0u), 0u), 4u));
        y += row * 1.3;
        col = fmInk(col, PT_MID, fmLabel(px, float2(colL, y), th, uint2(mf_pack1(GA, GN, GT, GS, 0u), 0u), 4u));
        col = fmInk(col, PT_INK, fmNumR(px, float2(rx, y), th, n, 3u));
        y += row;
        col = fmInk(col, PT_MID,    fmLabel(px, float2(colL, y), th, uint2(mf_pack1(GW, GA, GL, GK, 0u), 0u), 4u));
        col = fmInk(col, PT_ACCENT, fmNumR(px, float2(rx, y), th, (uint)ms.traffic, 3u));
        y += row;
        col = fmInk(col, PT_MID,    fmLabel(px, float2(colL, y), th, uint2(mf_pack1(GL, GA, GD, GN, 0u), 0u), 4u));
        col = fmInk(col, PT_ACCENT, fmFixed(px, float2(rx - fmFixedW(th, 1u), y), th, ms.laden, 1u));
        y += row;
        col = fmInk(col, PT_MID,    fmLabel(px, float2(colL, y), th, uint2(mf_pack1(GS, GP, GD, 0u, 0u), 0u), 3u));
        col = fmInk(col, PT_ACCENT, fmFixed(px, float2(rx - fmFixedW(th, 3u), y), th, ms.speed, 3u));
        y += row * 1.5;

        // Slip is the correctness reading of the whole node. Red past the threshold, because a
        // number that only gets bigger does not tell you when it became a fault.
        col = fmInk(col, PT_DIM, fmLabel(px, float2(colL, y), th, uint2(mf_pack1(GG, GA, GI, GT, 0u), 0u), 4u));
        y += row * 1.3;
        col = fmInk(col, PT_MID, fmLabel(px, float2(colL, y), th, uint2(mf_pack1(GS, GL, GI, GP, 0u), 0u), 4u));
        col = fmInk(col, (ms.slip > slip_alarm) ? PT_ALARM : PT_ACCENT,
                    fmFixed(px, float2(rx - fmFixedW(th, 1u), y), th, ms.slip, 1u));
        y += row;
        col = fmInk(col, PT_MID, fmLabel(px, float2(colL, y), th, uint2(mf_pack1(GM, GA, GX, 0u, 0u), 0u), 3u));
        col = fmInk(col, (ms.maxSlip > slip_alarm) ? PT_ALARM : PT_MID,
                    fmFixed(px, float2(rx - fmFixedW(th, 1u), y), th, ms.maxSlip, 1u));
        y += row * 1.5;

        col = fmInk(col, PT_DIM, fmLabel(px, float2(colL, y), th, uint2(mf_pack1(GL, GA, GN, GE, GS), 0u), 5u));
        y += row * 1.3;
        for (uint l = 0u; l < 4u; l++)
        {
            float v = (l == 0u) ? ms.e0 : ((l == 1u) ? ms.e1 : ((l == 2u) ? ms.e2 : ms.e3));
            col = fmInk(col, PT_MID, fmNumR(px, float2(colL + fmLabelW(th, 2u), y), th, l, 2u));
            col = fmInk(col, PT_ACCENT, fmFixed(px, float2(rx - fmFixedW(th, 1u), y), th, v, 1u));
            y += row;
        }
        y += row * 0.5;
        col = fmInk(col, PT_MID, fmLabel(px, float2(colL, y), th, uint2(mf_pack1(GO, GF, GF, 0u, 0u), 0u), 3u));
        col = fmInk(col, PT_MID, fmFixed(px, float2(rx - fmFixedW(th, 1u), y), th, ms.offTrail, 1u));
    }

    OutputUAV[pixel] = float4(col, 1.0);
}
