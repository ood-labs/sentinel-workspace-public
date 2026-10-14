// FM_Colony / canvas.hlsl — the colony's own instrument, the drawing.
//
// TWO PLATES, and the second one is the reason this node has a preview at all.
//
//   ARENA    the field the ants are steering on, with the ants on it. Trails are the SUBJECT
//            here, not the ants: what this plate is for is watching a trail form, sharpen and
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
//
// The type, plate borders, readout column, history traces, legend, inspector and keycap footer
// are recorded by layout.hlsl and drawn over this by the shared UI kit (ui.hlsl). Every rect
// comes from colony_view.hlsli, the same one the layout and the pointer use.
#include "../_shared/formic.hlsli"
#include "../_shared/ui/il_core.hlsli"
#include "colony.hlsli"
#include "colony_view.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);
StructuredBuffer<FmAnt>  Ants  : register(t0);
StructuredBuffer<FmFoot> Feet  : register(t1);
StructuredBuffer<FmMeas> Meas  : register(t2);
StructuredBuffer<FmRec>  PlanB : register(t3);
// _Tex4 — the pheromone field, auto-declared.
StructuredBuffer<FmGait> Hist  : register(t5);

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 px = (float2)pixel + 0.5;
    float2 res = _Resolution.xy;

    FcView V = fcView(res);
    float s = V.s;
    FmRec arena = PlanB[FM_ARENA];
    float2 ahalf = fmArenaHalf(arena);
    uint focus = min((uint)focus_ant, FM_MAX_ANTS - 1u);
    uint n = min((uint)ant_count, FM_MAX_ANTS);

    float3 col = IL_FIELD;
    float hair = max(res.x / 1200.0, 0.75);

    // ---------------------------------------------------------------------------
    // ARENA PLATE
    // ---------------------------------------------------------------------------
    ilOver(col, IL_PANEL, ilFill(ilSdBox(px, V.arena, IL_RADIUS * s)));

    // THE SHARED TOP-DOWN PROJECTION, not a private one.
    //
    // This strip used to compute its own mapping with world +x to the right. The plan was
    // corrected to draw +x to the LEFT — the half-turn that puts the viewer at the bottom edge
    // for a camera on the +z side — and this strip was not, so the two top-down views of the
    // same colony were mirror images of each other with nothing on either to say so. The page
    // orientation now travels in the arena record and both read it from there.
    FmTop T = fcArenaTop(V, arena);
    float scale = T.scale;

    if (ilIn(px, V.draw))
    {
        float2 w = fmPxToTop(T, px);
        bool inArena = (abs(w.x) <= ahalf.x && abs(w.y) <= ahalf.y);
        if (inArena) col = IL_WELL;

        if (inArena)
        {
            float4 f = _Tex4.SampleLevel(LinearSampler, fmWorldToFieldUV(w, arena), 0);

            // FOOD scent gets the VALUE ramp, because it is the trail that matters — the one
            // that recruits — and value is the strongest channel available.
            //
            // HOME scent gets a muted identity hue, and this is one of the two places in the
            // canvas where hue is spent. Two chemicals, both drawn as intensity fields, lying
            // on top of each other in exactly the same places: value alone genuinely cannot
            // say which is which, and telling them apart is the whole content of the plate.
            // The legend under the arena names both.
            float food = saturate(f.r * field_gain);
            float home = saturate(f.g * field_gain);
            col = fmInk(col, ptRamp(0.30 + 0.70 * food), pow(food, 0.62) * 0.92);
            col = fmInk(col, ptSampleFill(ptId(0)), pow(home, 0.75) * 0.45);

            // substrate
            col = fmInk(col, PT_GRID * 2.0, saturate(f.b) * 0.85);
        }

        { float2 aLo, aHi; fmTopBoxPx(T, -ahalf, ahalf, aLo, aHi);
            col = fmInk(col, PT_RULE, fmRectFrame(px, aLo, aHi, hair * 1.4)); }

        // --- the plan's structures, thin. Same records, so this plate and the plan canvas
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

            // --- FEET. The proof of the gait, and the reason this plate is worth its cost: a
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
    // GAIT PLATE — the Hildebrand chart.
    // ---------------------------------------------------------------------------
    ilOver(col, IL_PANEL, ilFill(ilSdBox(px, V.gait, IL_RADIUS * s)));
    float4 ch = V.chart;
    if (px.x >= ch.x && px.x <= ch.z + 2.0 && px.y >= ch.y && px.y <= ch.w)
    {
        FmGait hdr = Hist[0];
        uint cursor = (uint)max(hdr.t, 0.0) % FM_GAIT_HIST;
        uint written = (uint)max(hdr.bits, 0.0);
        float laneH = fcLaneH(V);
        uint row = min((uint)((px.y - ch.y) / laneH), 6u);
        float lc = ch.y + ((float)row + 0.5) * laneH;

        col = IL_WELL;
        if (row > 0u) col = fmInk(col, IL_GRID, 1.0 - smoothstep(0.0, 1.0, abs(px.y - (ch.y + (float)row * laneH))));
        // the tripods are split by a heavier rule: three on, three off reads as two blocks
        if (row == 3u) col = fmInk(col, IL_EDGE, 1.0 - smoothstep(0.0, 1.0, abs(px.y - (ch.y + 3.0 * laneH))));

        FmGait smp = Hist[1u + fcGaitSample(V, px.x, cursor, written)];
        bool painted = written > 0u && px.x <= ch.z;

        if (row < 6u && painted)
        {
            // Lane order is BY TRIPOD: group 0 (left front, left rear, right middle) then group 1.
            // Ordered by leg number instead, the chart is a plausible-looking mess; ordered by
            // tripod, a correct gait is unmistakably three-on / three-off and a broken one is
            // unmistakably not.
            uint leg = fcLaneLeg(row);
            uint bits = (uint)(smp.bits + 0.5);
            bool down = ((bits >> leg) & 1u) != 0u;
            if (down && abs(px.y - lc) <= laneH * 0.32)
            {
                // Group 0 sits one value step above group 1 so the two tripods are separable
                // even where the chart is dense; both stay grey, because which tripod is which
                // is ordinal information a value can carry.
                col = (fmLegGroup(leg) == 0u) ? IL_INK : IL_MID;
                if (smp.slip > slip_alarm && px.y <= lc - laneH * 0.10) col = IL_ALARM;
            }
        }
        else if (row == 6u && painted)
        {
            // The speed trace along the bottom lane, so the chart says whether a gap in the bars
            // is a stride hand-over or the ant simply standing still at a food pile.
            float y0 = ch.y + 6.0 * laneH;
            float v = saturate(smp.speed / max(walk_speed * 1.6, 1e-3));
            float ly = y0 + laneH * (1.0 - v * 0.86) - laneH * 0.07;
            col = fmInk(col, IL_MID, 1.0 - smoothstep(hair * 0.8, hair * 1.8, abs(px.y - ly)));
        }

        // the live edge
        col = fmInk(col, IL_ACCENT, (1.0 - smoothstep(0.0, hair * 1.2, abs(px.x - ch.z))) * 0.9);
    }

    OutputUAV[pixel] = float4(col, 1.0);
}
