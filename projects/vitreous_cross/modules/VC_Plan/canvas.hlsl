// VC_Plan / canvas.hlsl — the editor's schematic.
//
// A front elevation of the plan drawn DIRECTLY in stage space: uv -> stage is the exact
// inverse of the pointerToStage() the hit test uses, so what you click is what you see.
// This is deliberately NOT a small copy of the program image — it is a diagram of editor
// state: what is where, how deep it sits, what material it wears, what is selected, what has
// been hand-edited and what has been switched off.
#include "../_shared/vitreous.hlsli"
#include "../_shared/plan_theme.hlsli"

StructuredBuffer<VcRec> Plan : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

static float PX = 0.002;   // one pixel in stage units, set per dispatch

float3 matColourRaw(int m)
{
    if (m == MAT_CLEAR)  return float3(0.55, 0.78, 0.92);
    if (m == MAT_AMBER)  return float3(0.95, 0.52, 0.20);
    if (m == MAT_SMOKE)  return float3(0.58, 0.58, 0.64);
    if (m == MAT_CAVITY) return float3(0.62, 0.95, 0.86);
    if (m == MAT_FLUID)  return float3(0.42, 0.68, 1.00);
    if (m == MAT_WHITE)  return float3(0.94, 0.94, 0.94);
    if (m == MAT_BLACK)  return float3(0.34, 0.34, 0.38);
    return float3(0.86, 0.42, 0.18);
}

// Role/material identity IS information, so its hue survives — but damped to instrument level.
// At full strength a saturated cast makes the schematic louder than the render it exists to
// explain, and drowns the reserved accent.
float3 matColour(int m) { return ptSampleFill(matColourRaw(m)); }

float sdBox2(float2 p, float2 b)
{
    float2 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}

// unsigned distance to an axis-aligned ellipse boundary, good enough for a schematic
float sdEllipse2(float2 p, float2 r)
{
    float k0 = length(p / r);
    float k1 = length(p / (r * r));
    return k0 * (k0 - 1.0) / max(k1, 1e-5);
}

float stroke(float d, float w)
{
    return smoothstep(w + PX, w - PX, abs(d));
}

float solid(float d)
{
    return smoothstep(PX, -PX, d);
}

// dashes along a shape's boundary, used for switched-off records
float dashed(float d, float w, float2 p, float scale)
{
    float phase = frac((p.x + p.y) * scale);
    float on = step(0.45, phase);
    return stroke(d, w) * on;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    uint2 pix = DTid.xy;
    if (pix.x >= W || pix.y >= H) return;

    float2 uv = ((float2)pix + 0.5) / float2(W, H);
    // the SAME conversion pointerToStage() uses — see vitreous.hlsli
    float2 p = vc_uvToStage(uv);
    // no derivatives in a compute shader: pixel width comes from the target extent
    PX = VC_VIEW_W / (float)W;

    VcRec hdr = Plan[VC_HEADER];
    float sel = hdr.pos.y;
    float liveS = hdr.tint.y;
    float liveI = hdr.tint.z;
    float liveP = hdr.p0;

    // --- ground: a cool graph field, with the stage rectangle marked
    float3 col = PT_FIELD;
    float2 g = abs(frac(p * 4.0) - 0.5);
    float grid = smoothstep(0.5 * PX * 4.0 + 0.004, 0.0, min(g.x, g.y) / 4.0);
    col += grid * 0.035;
    float2 g2 = abs(frac(p * 1.0) - 0.5);
    col += smoothstep(0.010, 0.0, min(g2.x, g2.y)) * 0.045;
    col += stroke(p.x, PX) * 0.10 + stroke(p.y, PX) * 0.10;
    // the 3:2 frame the program image will actually crop to
    col += stroke(sdBox2(p, float2(1.5, 1.0)), PX * 1.4) * PT_RULE;

    // --- slabs: outlines, weight and fill cued by depth so the stacking order is readable
    for (uint i = 0u; i < VC_SLABS; i++)
    {
        VcRec r = Plan[VC_SLAB_0 + i];
        uint fl = (uint)r.flags;
        float d = sdBox2(p - r.pos.xy, r.dims.xy);
        float3 mc = matColour((int)r.mat);
        // depth cue: nearer records draw brighter and heavier
        float near = saturate(0.5 + r.pos.z * 0.8);
        float w = PX * lerp(1.0, 2.6, near);

        if (r.active > 0.5)
        {
            col = lerp(col, mc * 0.16, solid(d) * 0.55);
            col = lerp(col, mc * lerp(0.55, 1.1, near), stroke(d, w));
        }
        else
        {
            col = lerp(col, mc * 0.45, dashed(d, PX * 1.1, p, 9.0) * 0.7);
        }

        if (fl & F_EDITED)
        {
            // a hand-edited record wears a corner tick, so the user can see what the global
            // controls will no longer move
            float2 cq = abs(p - (r.pos.xy + float2(r.dims.x, r.dims.y))) ;
            col = lerp(col, PT_MID, stroke(max(cq.x, cq.y) - 0.022, PX * 1.6));
        }
        if (fl & F_SELECTED)
            col = lerp(col, PT_MID, stroke(d - 0.028, PX * 2.2));
    }

    // --- panels: solid plates, drawn on top of the glass they sit inside
    for (uint j = 0u; j < VC_PANELS; j++)
    {
        VcRec r = Plan[VC_PANEL_0 + j];
        uint fl = (uint)r.flags;
        float d = sdBox2(p - r.pos.xy, r.dims.xy);
        float3 mc = matColour((int)r.mat);

        if (r.active > 0.5)
        {
            col = lerp(col, mc * 0.55, solid(d) * 0.80);
            col = lerp(col, mc, stroke(d, PX * 1.3));
        }
        else
        {
            col = lerp(col, mc * 0.40, dashed(d, PX * 1.1, p, 9.0) * 0.6);
        }

        if (fl & F_EDITED)
        {
            float2 cq = abs(p - (r.pos.xy + float2(r.dims.x, r.dims.y)));
            col = lerp(col, PT_MID, stroke(max(cq.x, cq.y) - 0.018, PX * 1.6));
        }
        if (fl & F_SELECTED)
            col = lerp(col, PT_MID, stroke(d - 0.024, PX * 2.2));
    }

    // --- inclusions: the organic mass, drawn as translucent lenses with a fused hull so the
    // schematic shows what will actually merge in the field rather than a set of loose eggs
    // ITERATED SMOOTH-MIN COMPOUNDS. Fusing two dozen records one after another accumulates
    // one blend radius per step, and the total inflation drew a single amoeba spanning the
    // whole frame — a hull for masses that are not there. Bounding the result to
    // (plain min - one blend radius) caps the inflation at what a single fuse can do.
    float hull = 1e9;
    float plain = 1e9;
    float kMax = 0.0;
    for (uint k = 0u; k < VC_INCS; k++)
    {
        VcRec r = Plan[VC_INC_0 + k];
        if (r.active > 0.5)
        {
            float d = sdEllipse2(p - r.pos.xy, max(r.dims.xy, 0.02));
            float kk = max(r.p0, 0.01);
            plain = min(plain, d);
            kMax = max(kMax, kk);
            hull = vc_fuse(hull, d, kk);
        }
    }
    hull = max(hull, plain - kMax);
    col = lerp(col, PT_ID_C, solid(hull) * 0.22);
    col = lerp(col, PT_ID_C, stroke(hull, PX * 1.1) * 0.75);

    for (uint k2 = 0u; k2 < VC_INCS; k2++)
    {
        VcRec r = Plan[VC_INC_0 + k2];
        uint fl = (uint)r.flags;
        float d = sdEllipse2(p - r.pos.xy, max(r.dims.xy, 0.02));
        float3 mc = matColour((int)r.mat);
        float near = saturate(0.5 + r.pos.z * 0.8);

        if (r.active > 0.5)
        {
            col = lerp(col, mc * 0.9, stroke(d, PX * lerp(0.8, 1.8, near)) * 0.85);
            // centre pip carries the depth: filled = near, hollow = far
            float cd = length(p - r.pos.xy) - 0.014;
            col = lerp(col, mc, solid(cd) * near);
            col = lerp(col, mc * 0.8, stroke(cd, PX));
        }
        else
        {
            col = lerp(col, mc * 0.35, dashed(d, PX, p, 12.0) * 0.6);
        }

        if (fl & F_EDITED)
            col = lerp(col, PT_MID, stroke(length(p - r.pos.xy) - 0.030, PX * 1.5));
        if (fl & F_SELECTED)
            col = lerp(col, PT_MID, stroke(d - 0.026, PX * 2.2));
    }

    // --- selected record callout: a material chip pinned beside it, so "what did M just do"
    // is answerable without leaving the preview
    if (sel > 0.5)
    {
        VcRec r = Plan[(uint)(sel - 1.0)];
        float2 anchor = r.pos.xy + float2(max(r.dims.x, 0.05) + 0.075, max(r.dims.y, 0.05) + 0.055);
        float chip = sdBox2(p - anchor, float2(0.055, 0.030));
        col = lerp(col, PT_FIELD, solid(chip));
        col = lerp(col, matColour((int)r.mat), solid(chip + 0.012));
        col = lerp(col, PT_MID, stroke(chip, PX * 1.2));
        // depth bar under the chip: where this record sits in z
        float2 bp = p - (anchor - float2(0.0, 0.055));
        float bar = sdBox2(bp, float2(0.055, 0.008));
        col = lerp(col, PT_GRID, solid(bar));
        float zt = saturate(r.pos.z * 0.5 + 0.5);
        col = lerp(col, PT_ID_A, solid(sdBox2(bp - float2((zt - 0.5) * 0.10, 0.0), float2(0.006, 0.008))));
    }

    // --- census strip, bottom left: one pip per live record in each family, so a count
    // parameter change is visible in the diagram and not only in Properties
    for (uint c = 0u; c < 24u; c++)
    {
        float2 base = float2(-1.62 + (float)c * 0.036, -0.98);
        float pipS = length(p - base) - 0.011;
        float pipI = length(p - (base + float2(0.0, 0.048))) - 0.011;
        float pipP = length(p - (base + float2(0.0, 0.096))) - 0.011;
        float on;
        on = ((float)c < liveS) ? 1.0 : 0.18;
        col = lerp(col, PT_ID_A * on, solid(pipS));
        on = ((float)c < liveI) ? 1.0 : 0.18;
        col = lerp(col, PT_ID_C * on, solid(pipI));
        on = ((float)c < liveP) ? 1.0 : 0.18;
        col = lerp(col, PT_ID_D * on, solid(pipP));
    }

    OutputUAV[pix] = float4(col, 1.0);
}
