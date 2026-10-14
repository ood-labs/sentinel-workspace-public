// VT_Plan / canvas.hlsl — the schematic plan, the DRAWING only.
//
// This is the diagnostic surface for the entire show, so it decodes every field that matters
// downstream: role, kind, material, depth band, growth reserve, stroke weight, active state,
// hand-edited state and the current selection. It draws a PLAN, not a copy of the program
// image — 1:1 with stage space so pick and drag cannot drift from what is drawn.
//
// The words, counts, kind numbers, hover highlight, inspector card and keycap footer are recorded
// by layout.hlsl and drawn over this by the shared UI kit (ui.hlsl).
//
// Every record is drawn by every pixel, and a stroke's schematic spine is twelve segments, so each
// record first checks whether this pixel is within its REACH: a radius around its anchor beyond
// which every mark below is exactly zero (vt_fill is zero from 0.75 px outside a shape). The
// reaches are read off the drawing, so a skipped record would have added nothing.
#include "../_shared/vitrine.hlsli"
#include "../_shared/ui/il_core.hlsli"

StructuredBuffer<PlanRec> Plan : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

static const float3 ROLE_TINT[4] = {
    PT_ID_A,   // plate
    PT_ID_C,   // stroke  (not PT_ACCENT: role identity must not impersonate selection)
    PT_ID_B,   // mass
    PT_DIM     // header
};

// material marker: a small badge shape drawn beside each mass
static const float3 MAT_TINT[4] = {
    ptRamp(0.15),   // clay   — a VALUE ramp, so it cannot compete with the role hues
    ptRamp(1.00),   // chrome
    ptRamp(0.70),   // frost
    ptRamp(0.42)    // gloss
};

float ring(float d, float w, float px) { return vt_fill(abs(d) - w, px); }

// Preview-only legibility lift, then INSTRUMENT DAMPING.
//
// The show's real palette includes a near-black accent and dark bodies; on a dark schematic
// those vanish, so the plan first re-maps them to a readable brightness. It then puts them
// through ptSampleFill: an element's own colour is genuine information (rule 4), but EVERY
// element carries one here, and at full strength that turns the whole diagram into a louder
// version of the render it exists to explain — and drowns the reserved accent.
// This affects the diagnostic drawing only — no consumer reads a colour from this node.
float3 pv(float3 c)
{
    float l = dot(c, float3(0.299, 0.587, 0.114));
    float3 lifted = lerp(normalize(c + 0.08) * 0.62, c, saturate(l * 3.2));
    return ptSampleFill(lifted);
}

// dashed ring, for the growth reserve
float dashRing(float2 q, float r, float w, float px, float segs)
{
    float d = abs(length(q) - r) - w;
    float a = atan2(q.y, q.x);
    float g = step(0.42, frac(a * segs / 6.2831853));
    return vt_fill(d, px) * g;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 P = (float2)pixel + 0.5;
    float2 uv = P / _Resolution.xy;
    float px = 1.0 / _Resolution.y;

    // --- ground: the instrument field, a grid every tenth of the stage and the centre lines ---
    float3 col = IL_FIELD;
    float g10 = max(ilGridLine(P.x, 0.1 * _Resolution.x, 1.0), ilGridLine(P.y, 0.1 * _Resolution.y, 1.0));
    float g2 = max(ilGridLine(P.x, 0.5 * _Resolution.x, 1.0), ilGridLine(P.y, 0.5 * _Resolution.y, 1.0));
    ilOver(col, IL_GRID, g10);
    ilOver(col, IL_EDGE, g2 * 0.7);

    PlanRec hdr = Plan[PLAN_HEADER];
    uint sel = (uint)hdr.pos.y;

    // horizon line, read from the same stage record the backdrop and compositor read
    float hz = Plan[PLAN_STAGE].pos.x;
    col = lerp(col, IL_DIM, vt_fill(abs(uv.y - hz) - 0.0008, px) * 0.55);
    col += IL_GRID * exp(-abs(uv.y - hz) * 55.0) * 0.5;

    // ---------------------------------------------------------------- plates
    for (uint i = 0u; i < PLAN_PLATES; i++)
    {
        PlanRec r = Plan[PLAN_PLATE_0 + i];
        uint fl = (uint)r.flags;
        float2 q = uv - r.pos;
        // reach: the rounded box (any rotation) with its selection ring, or the front tick
        float2 pb = max(r.size, 0.002);
        float pr = min(r.size.x, r.size.y) * 0.35;
        if (length(q) > max(length(pb) + 1.5 * abs(pr) + 0.006 + 2.1 * px,
                            abs(r.size.y) + 0.006 + length(float2(r.size.x * 0.5, 0.0015)) + 0.8 * px))
            continue;
        if ((int)r.kind == PK_DASH) q = vt_rot2(q, -r.phase);
        float d = vt_dRBox(q, max(r.size, 0.002), min(r.size.x, r.size.y) * 0.35);

        float alive = r.active;
        float3 tint = ROLE_TINT[0];
        if ((int)r.kind == PK_BEAN) tint = C_NEON;
        if ((int)r.kind == PK_DASH) tint = vt_accent(r.tone);
        if ((int)r.kind == PK_GRIDPLATE) tint = C_PINK;
        tint = pv(tint);

        // faint body so the footprint reads, crisp outline so the edge is exact
        col = lerp(col, tint * 0.30, vt_fill(d, px) * (0.05 + 0.40 * alive));
        col = lerp(col, tint * lerp(0.16, 1.0, alive), ring(d, 0.8 * px, px));

        // front/back band: a tick on the top edge means "composited in front of the masses"
        if ((fl & F_FRONT) != 0u && alive > 0.5)
            col = lerp(col, IL_MID,
                       vt_fill(vt_dBox(q - float2(0.0, -r.size.y - 0.006), float2(r.size.x * 0.5, 0.0015)), px));

        if (sel == PLAN_PLATE_0 + i + 1u)
            col = lerp(col, IL_ACCENT, ring(d - 0.006, 1.3 * px, px));
    }

    // ---------------------------------------------------------------- strokes
    for (uint s = 0u; s < PLAN_STROKES; s++)
    {
        PlanRec r = Plan[PLAN_STROKE_0 + s];
        float alive = r.active;
        float3 tint = pv(vt_accent(r.tone));
        float2 e = max(r.size, 0.004);
        float2 q = uv - r.pos;
        // reach: every spine archetype stays within 1.17 of the unit extent, and the ellipse,
        // its ring and the selection ring end within 0.008 + 2.05 px of it
        float emin = min(e.x, e.y);
        float sw = max(r.phase, 0.05) * 0.010 + 0.6 * px;
        if (length(q) > max(e.x, e.y) * (1.2 + max(0.008 + 2.1 * px, sw + 0.8 * px) / emin))
            continue;

        // extent ellipse = the box the stroke will be grown inside
        float de = length(q / e) - 1.0;
        float den = de * min(e.x, e.y);
        col = lerp(col, tint * 0.22, vt_fill(den, px) * 0.07 * (0.2 + alive));
        col = lerp(col, tint * lerp(0.14, 1.0, alive), ring(den, 0.7 * px, px));

        // a schematic spine that encodes the archetype, so the kind is visible not just numbered
        int k = (int)r.kind;
        float spine = 1e9;
        for (uint t = 0u; t < 12u; t++)
        {
            float t0 = (float)t / 12.0, t1 = (float)(t + 1u) / 12.0;
            float2 a, b;
            if (k == SK_BUNDLE)
            {
                a = float2(sin(t0 * 9.0) * 0.35, t0 * 2.0 - 1.0);
                b = float2(sin(t1 * 9.0) * 0.35, t1 * 2.0 - 1.0);
            }
            else if (k == SK_ARC)
            {
                a = float2(sin(t0 * 3.14159) * 0.9 - 0.45, t0 * 2.0 - 1.0);
                b = float2(sin(t1 * 3.14159) * 0.9 - 0.45, t1 * 2.0 - 1.0);
            }
            else if (k == SK_BRANCH)
            {
                float ang0 = t0 * 6.2831853, ang1 = t1 * 6.2831853;
                a = float2(cos(ang0), sin(ang0)) * (0.25 + 0.6 * frac(t0 * 3.0));
                b = float2(cos(ang1), sin(ang1)) * (0.25 + 0.6 * frac(t1 * 3.0));
            }
            else if (k == SK_TANGLE)
            {
                a = float2(sin(t0 * 12.6), cos(t0 * 7.9)) * 0.75;
                b = float2(sin(t1 * 12.6), cos(t1 * 7.9)) * 0.75;
            }
            else
            {
                a = float2(t0 * 2.0 - 1.0, sin(t0 * 6.2831853) * 0.6);
                b = float2(t1 * 2.0 - 1.0, sin(t1 * 6.2831853) * 0.6);
            }
            float h;
            spine = min(spine, vt_dSeg(q / e, a, b, h));
        }
        float spineD = spine * min(e.x, e.y);
        // weight is encoded in the drawn thickness, so a heavy stroke looks heavy in the plan
        float w = max(r.phase, 0.05) * 0.010 + 0.6 * px;
        col = lerp(col, tint * lerp(0.12, 1.0, alive), vt_fill(spineD - w, px));

        if (sel == PLAN_STROKE_0 + s + 1u)
            col = lerp(col, IL_ACCENT, ring(den - 0.008, 1.3 * px, px));
    }

    // ---------------------------------------------------------------- masses
    for (uint m = 0u; m < PLAN_MASSES; m++)
    {
        PlanRec r = Plan[PLAN_MASS_0 + m];
        uint fl = (uint)r.flags;
        uint mat = (fl >> 8) & 15u;
        float alive = r.active;
        float2 q = uv - r.pos;
        // reach: the reserve and selection rings, or the core with its badge, arc and edit ring
        float coreR = r.size.x * 0.34 * saturate(r.size.y);
        if (length(q) > max(abs(r.size.x), max(abs(coreR), 0.006)) + 0.04 + 3.0 * px)
            continue;
        float3 body = pv(vt_body(r.tone));

        // dashed reserve ring — the clearance this mass owns, which VT_Growth sizes from
        col = lerp(col, IL_DIM,
                   dashRing(q, r.size.x, 0.7 * px, px, 34.0) * lerp(0.10, 0.65, alive));

        // core disc, radius from the GROWTH SCALE so the two numbers are visibly different
        float core = r.size.x * 0.34 * saturate(r.size.y);
        float dc = length(q) - max(core, 0.006);
        col = lerp(col, body * lerp(0.14, 1.0, alive), vt_fill(dc, px));
        col = lerp(col, IL_FIELD, ring(dc, 0.9 * px, px) * 0.6);

        // material badge: a small chip whose value names the surface (legend in the footer)
        float2 bq = q - float2(max(core, 0.006) + 0.010, 0.0);
        float db = vt_dRBox(bq, float2(0.0075, 0.0075), 0.002);
        col = lerp(col, MAT_TINT[mat] * lerp(0.15, 1.0, alive), vt_fill(db, px));

        // depth band, drawn as a filled arc under the core (0 = far, full ring = near)
        float ang = atan2(q.y, q.x);
        float arcT = saturate((ang + 3.14159) / 6.2831853);
        float dr = abs(length(q) - (max(core, 0.006) + 0.017)) - 0.0022;
        col = lerp(col, IL_MID,
                   vt_fill(dr, px) * step(arcT, saturate(r.grp)) * lerp(0.2, 0.9, alive));

        if ((fl & F_EDITED) != 0u)
            col = lerp(col, IL_MID, ring(length(q) - core - 0.028, 1.0 * px, px));
        if (sel == PLAN_MASS_0 + m + 1u)
        {
            col = lerp(col, IL_ACCENT, ring(length(q) - r.size.x - 0.010, 1.4 * px, px));
            col = lerp(col, IL_ACCENT,
                       vt_fill(min(vt_dBox(q, float2(0.030, 0.0006)), vt_dBox(q, float2(0.0006, 0.030))), px));
        }
    }

    OutputUAV[pixel] = float4(col, 1.0);
}
