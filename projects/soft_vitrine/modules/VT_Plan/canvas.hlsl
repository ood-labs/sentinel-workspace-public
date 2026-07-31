// VT_Plan / canvas.hlsl — the schematic plan preview.
//
// This is the diagnostic surface for the entire show, so it decodes every field that matters
// downstream: role, kind, material, depth band, growth reserve, stroke weight, active state,
// hand-edited state and the current selection. It draws a PLAN, not a copy of the program
// image — 1:1 with stage space so pick and drag cannot drift from what is drawn.
#include "../_shared/vitrine.hlsli"
#include "../_shared/microfont.hlsli"

StructuredBuffer<PlanRec> Plan : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

static const float3 ROLE_TINT[4] = {
    float3(0.55, 0.72, 0.88),   // plate  — cool slate
    float3(0.98, 0.72, 0.28),   // stroke — amber
    float3(0.96, 0.34, 0.62),   // mass   — magenta
    float3(0.60, 0.60, 0.60)    // header
};

// material marker: a small badge shape drawn beside each mass
static const float3 MAT_TINT[4] = {
    float3(0.92, 0.46, 0.30),   // clay
    float3(0.85, 0.90, 1.00),   // chrome
    float3(0.72, 0.78, 0.98),   // frost
    float3(0.55, 0.95, 0.70)    // gloss
};

float ring(float d, float w, float px) { return vt_fill(abs(d) - w, px); }

// Preview-only legibility lift. The show's real palette includes a near-black accent and dark
// bodies; on a dark schematic those vanish, so the PLAN re-maps them to a readable brightness.
// This affects the diagnostic drawing only — no consumer reads a colour from this node.
float3 pv(float3 c)
{
    float l = dot(c, float3(0.299, 0.587, 0.114));
    return lerp(normalize(c + 0.08) * 0.62, c, saturate(l * 3.2));
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
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float px = 1.0 / _Resolution.y;

    // --- ground: dark slate with a faint decimal grid so positions are readable ---
    float3 col = float3(0.055, 0.062, 0.078);
    float d10 = min(abs(frac(uv.x * 10.0) - 0.5), abs(frac(uv.y * 10.0) - 0.5)) * 0.1;  // uv units
    col += 0.030 * (1.0 - smoothstep(0.0, 1.2 * px, d10));
    float d2 = min(abs(frac(uv.x * 2.0) - 0.5), abs(frac(uv.y * 2.0) - 0.5)) * 0.5;
    col += 0.045 * (1.0 - smoothstep(0.0, 1.4 * px, d2));

    PlanRec hdr = Plan[PLAN_HEADER];
    uint sel = (uint)hdr.pos.y;

    // horizon line, read from the same stage record the backdrop and compositor read
    float hz = Plan[PLAN_STAGE].pos.x;
    col = lerp(col, float3(0.30, 0.85, 1.0), vt_fill(abs(uv.y - hz) - 0.0008, px) * 0.55);
    col += float3(0.05, 0.14, 0.18) * exp(-abs(uv.y - hz) * 55.0) * 0.5;

    // ---------------------------------------------------------------- plates
    for (uint i = 0u; i < PLAN_PLATES; i++)
    {
        PlanRec r = Plan[PLAN_PLATE_0 + i];
        uint fl = (uint)r.flags;
        float2 q = uv - r.pos;
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
            col = lerp(col, float3(1.0, 0.95, 0.6),
                       vt_fill(vt_dBox(q - float2(0.0, -r.size.y - 0.006), float2(r.size.x * 0.5, 0.0015)), px));

        // kind digit, only where there is room
        if (alive > 0.5 && r.size.x > 0.030 && r.size.y > 0.022)
        {
            float2 tp = (q - float2(-r.size.x + 0.010, -r.size.y + 0.006)) / float2(0.014, 0.016);
            col = lerp(col, float3(0.95, 0.98, 1.0), mf_num(tp, (uint)r.kind, 1u) * 0.9);
        }
        if (sel == PLAN_PLATE_0 + i + 1u)
            col = lerp(col, float3(1, 1, 1), ring(d - 0.006, 1.3 * px, px));
    }

    // ---------------------------------------------------------------- strokes
    for (uint s = 0u; s < PLAN_STROKES; s++)
    {
        PlanRec r = Plan[PLAN_STROKE_0 + s];
        float alive = r.active;
        float3 tint = pv(vt_accent(r.tone));
        float2 e = max(r.size, 0.004);
        float2 q = uv - r.pos;

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

        if (alive > 0.5)
        {
            float2 tp = (q - float2(-e.x + 0.008, -e.y - 0.004)) / float2(0.013, 0.015);
            col = lerp(col, float3(0.98, 0.90, 0.60), mf_num(tp, (uint)r.kind, 1u) * 0.85);
        }
        if (sel == PLAN_STROKE_0 + s + 1u)
            col = lerp(col, float3(1, 1, 1), ring(den - 0.008, 1.3 * px, px));
    }

    // ---------------------------------------------------------------- masses
    for (uint m = 0u; m < PLAN_MASSES; m++)
    {
        PlanRec r = Plan[PLAN_MASS_0 + m];
        uint fl = (uint)r.flags;
        uint mat = (fl >> 8) & 15u;
        float alive = r.active;
        float2 q = uv - r.pos;
        float3 body = pv(vt_body(r.tone));

        // dashed reserve ring — the clearance this mass owns, which VT_Growth sizes from
        col = lerp(col, float3(0.98, 0.55, 0.78),
                   dashRing(q, r.size.x, 0.7 * px, px, 34.0) * lerp(0.10, 0.65, alive));

        // core disc, radius from the GROWTH SCALE so the two numbers are visibly different
        float core = r.size.x * 0.34 * saturate(r.size.y);
        float dc = length(q) - max(core, 0.006);
        col = lerp(col, body * lerp(0.14, 1.0, alive), vt_fill(dc, px));
        col = lerp(col, float3(0.03, 0.03, 0.05), ring(dc, 0.9 * px, px) * 0.6);

        // material badge: a small chip whose colour names the surface
        float2 bq = q - float2(max(core, 0.006) + 0.010, 0.0);
        float db = vt_dRBox(bq, float2(0.0075, 0.0075), 0.002);
        col = lerp(col, MAT_TINT[mat] * lerp(0.15, 1.0, alive), vt_fill(db, px));

        // depth band, drawn as a filled arc under the core (0 = far, full ring = near)
        float ang = atan2(q.y, q.x);
        float arcT = saturate((ang + 3.14159) / 6.2831853);
        float dr = abs(length(q) - (max(core, 0.006) + 0.017)) - 0.0022;
        col = lerp(col, float3(0.45, 0.95, 1.0),
                   vt_fill(dr, px) * step(arcT, saturate(r.grp)) * lerp(0.2, 0.9, alive));

        if (alive > 0.5)
        {
            float2 tp = (q - float2(-0.009, -core - 0.024)) / float2(0.016, 0.018);
            col = lerp(col, float3(1, 1, 1), mf_num(tp, (uint)r.kind, 1u) * 0.95);
        }
        if ((fl & F_EDITED) != 0u)
            col = lerp(col, float3(1.0, 0.85, 0.25), ring(length(q) - core - 0.028, 1.0 * px, px));
        if (sel == PLAN_MASS_0 + m + 1u)
        {
            col = lerp(col, float3(1, 1, 1), ring(length(q) - r.size.x - 0.010, 1.4 * px, px));
            col = lerp(col, float3(1, 1, 1),
                       vt_fill(min(vt_dBox(q, float2(0.030, 0.0006)), vt_dBox(q, float2(0.0006, 0.030))), px));
        }
    }

    // ---------------------------------------------------------------- readout
    // live counts + selection, all from the header record, never from a second source of truth
    {
        float2 o = float2(0.016, 0.016);
        float2 cell = float2(0.0125, 0.0175);
        uint counts[3] = { (uint)hdr.grp, (uint)hdr.phase, (uint)hdr.flags };
        uint letters[3] = { 22u, 28u, 25u };   // M S P  (MF_A = 10, so A+12, A+18, A+15)
        for (uint row = 0u; row < 3u; row++)
        {
            float2 rp = uv - (o + float2(0.0, (float)row * 0.024));
            float t = mf_glyph(rp / cell, letters[row]);
            t += mf_num((rp - float2(cell.x * 1.6, 0.0)) / float2(cell.x * 2.0, cell.y), counts[row], 2u);
            col = lerp(col, ROLE_TINT[2u - row] * 1.0, saturate(t) * 0.95);
        }
        // selected record index, right-aligned
        float2 sp = uv - float2(0.905, 0.016);
        float st = mf_glyph(sp / cell, MF_GT);   // '>' selection marker
        st += mf_num((sp - float2(cell.x * 1.4, 0.0)) / float2(cell.x * 2.0, cell.y), sel, 2u);
        col = lerp(col, float3(1, 1, 1), saturate(st) * (sel > 0u ? 0.95 : 0.30));
    }

    // frame
    float2 fq = abs(uv - 0.5) - 0.5 + 0.004;
    col = lerp(col, float3(0.30, 0.34, 0.42), ring(max(fq.x, fq.y), 0.7 * px, px));

    OutputUAV[pixel] = float4(col, 1.0);
}
