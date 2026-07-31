// VT_Growth / preview.hlsl — the expander's own diagnostic surface.
//
// Two panels over one canvas, because this node publishes two genuinely different record
// families and both must be inspectable:
//   * masses  — front-projected world nodes as discs with their bonds, tinted by GROUP, with
//               each group's bounding sphere (the thing the ray-marcher culls against) drawn.
//   * strokes — stage-space polylines at their real published radius and per-node accent hue.
// A parameter that changes structure must visibly change this picture.
#include "../_shared/vitrine.hlsli"
#include "../_shared/microfont.hlsli"

StructuredBuffer<LimbRec> Limbs : register(t0);
RWTexture2D<float4> OutputUAV : register(u0);

static const float3 MAT_TINT[4] = {
    float3(0.95, 0.45, 0.30), float3(0.88, 0.92, 1.00),
    float3(0.72, 0.78, 0.98), float3(0.55, 0.95, 0.70)
};

// world (x,y) -> canvas uv, the same front projection the canonical camera uses at z = 0
float2 worldToUV(float3 w) { return float2(w.x * 0.5 + 0.5, 0.5 - w.y * 0.5); }

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float px = 1.0 / _Resolution.y;

    float3 col = float3(0.045, 0.050, 0.062);
    float d2 = min(abs(frac(uv.x * 4.0) - 0.5), abs(frac(uv.y * 4.0) - 0.5)) * 0.25;
    col += 0.035 * (1.0 - smoothstep(0.0, 1.4 * px, d2));

    uint massNodes = 0u, strokeNodes = 0u, groups = 0u;

    // ------------------------------------------------------------------ group bounds
    // Drawn first and faintly: these are the culling spheres, not the geometry.
    for (uint g = 0u; g < LIMB_HEADERS; g++)
    {
        LimbRec h = Limbs[g];
        if (h.active < 0.5) continue;
        groups++;
        bool isMass = (g < LIMB_STROKE_H_0);
        float2 c = isMass ? worldToUV(h.pos) : h.pos.xy;
        float r = isMass ? h.radius * 0.5 : h.radius;
        float3 tint = isMass ? float3(0.95, 0.40, 0.70) : vt_accent(h.material);
        float dr = abs(length(uv - c) - r) - 0.7 * px;
        // dashed, so a bound never reads as an object
        float dash = step(0.45, frac(atan2(uv.y - c.y, uv.x - c.x) * 5.6));
        col = lerp(col, tint, vt_fill(dr, px) * 0.30 * dash);
    }

    // ------------------------------------------------------------------ mass limbs
    [loop]
    for (uint i = LIMB_NODE_0; i < LIMB_MASS_CAP; i++)
    {
        LimbRec n = Limbs[i];
        if (n.active < 0.5) continue;
        massNodes++;

        float2 c = worldToUV(n.pos);
        float r = n.radius * 0.5;                       // world radius -> uv (half-extent = 1.0)
        // group tint keeps clusters separable; material stays visible as the core chip
        float3 tint = vt_body(frac(n.group * 0.137 + 0.05));

        // bond to parent, tapered, so the topology is readable
        if (n.parent >= 0.0)
        {
            LimbRec pr = Limbs[(uint)n.parent];
            float2 pc = worldToUV(pr.pos);
            float db = vt_dTaper(uv, pc, c, pr.radius * 0.5 * 0.55, r * 0.55);
            col = lerp(col, tint * 0.55, vt_fill(db, px));
        }

        float dn = length(uv - c) - r;
        col = lerp(col, tint, vt_fill(dn, px) * 0.85);
        // shallow shade so overlapping nodes stay countable
        col = lerp(col, tint * 1.6, vt_fill(dn + r * 0.55, px) * 0.5);
        col = lerp(col, MAT_TINT[((uint)n.material) & 3u], vt_fill(dn + r * 0.82, px) * 0.9);
    }

    // ------------------------------------------------------------------ stroke limbs
    [loop]
    for (uint s = LIMB_STROKE_0; s < LIMB_RECORDS; s++)
    {
        LimbRec n = Limbs[s];
        if (n.active < 0.5) continue;
        strokeNodes++;

        float3 tint = vt_accent(n.material);
        float lum = dot(tint, float3(0.299, 0.587, 0.114));
        tint = lerp(normalize(tint + 0.09) * 0.66, tint, saturate(lum * 3.2));   // preview lift

        if (n.parent >= 0.0)
        {
            LimbRec pr = Limbs[(uint)n.parent];
            float db = vt_dTaper(uv, pr.pos.xy, n.pos.xy, pr.radius, n.radius);
            col = lerp(col, tint, vt_fill(db, px));
        }
        else
        {
            // run starts get a ring, so it is obvious where a polyline begins
            col = lerp(col, float3(1, 1, 1),
                       vt_fill(abs(length(uv - n.pos.xy) - n.radius * 1.9) - 0.6 * px, px) * 0.7);
        }
        col = lerp(col, tint * 1.15, vt_fill(length(uv - n.pos.xy) - n.radius, px) * 0.8);
    }

    // ------------------------------------------------------------------ group tally
    // One bar per group along the bottom: outline = the node count the header DECLARES,
    // fill = the nodes actually found active in that group's range. A short fill means the
    // grower wrote fewer records than it promised, which is otherwise invisible in the picture.
    // Restricted to the strip so the inner scan only costs ~8% of pixels.
    if (uv.y > 0.915)
    {
        float slotW = 0.88 / (float)LIMB_HEADERS;
        float fx = (uv.x - 0.06) / slotW;
        if (fx >= 0.0 && fx < (float)LIMB_HEADERS)
        {
            uint g = (uint)fx;
            float inner = frac(fx);
            LimbRec h = Limbs[g];
            uint declared = (uint)max(h.group, 0.0);
            uint firstIdx = (uint)max(h.parent, 0.0);
            uint found = 0u;
            [loop]
            for (uint k = 0u; k < declared && k < 64u; k++)
                if (Limbs[firstIdx + k].active > 0.5) found++;

            float bh = saturate((float)declared / 64.0);
            float fillFrac = (declared > 0u) ? (float)found / (float)declared : 0.0;
            float yb = (uv.y - 0.915) / 0.085;            // 0 top .. 1 bottom of the strip
            float lvl = 1.0 - yb;
            if (inner > 0.12 && inner < 0.88 && h.active > 0.5)
            {
                float3 barTint = (g < LIMB_STROKE_H_0) ? float3(0.96, 0.42, 0.66)
                                                       : float3(0.98, 0.78, 0.30);
                if (lvl < bh)
                {
                    bool filled = lvl < bh * fillFrac;
                    // a short fill turns red — an unmissable signal, not a subtle one
                    col = filled ? barTint : lerp(col, float3(0.85, 0.12, 0.12), 0.75);
                }
            }
        }
    }

    // ------------------------------------------------------------------ readout
    {
        float2 cell = float2(0.0110, 0.0155);
        uint vals[3] = { massNodes, strokeNodes, groups };
        uint letters[3] = { 22u, 28u, 16u };   // M  S  G
        float3 tints[3] = { float3(0.96, 0.42, 0.66), float3(0.98, 0.78, 0.30), float3(0.55, 0.85, 1.0) };
        for (uint row = 0u; row < 3u; row++)
        {
            float2 rp = uv - (float2(0.014, 0.014) + float2(0.0, (float)row * 0.021));
            float t = mf_glyph(rp / cell, letters[row]);
            t += mf_num((rp - float2(cell.x * 1.6, 0.0)) / float2(cell.x * 2.4, cell.y), vals[row], 3u);
            col = lerp(col, tints[row], saturate(t) * 0.95);
        }
    }

    float2 fq = abs(uv - 0.5) - 0.5 + 0.004;
    col = lerp(col, float3(0.28, 0.32, 0.40), vt_fill(abs(max(fq.x, fq.y)) - 0.7 * px, px));

    OutputUAV[pixel] = float4(col, 1.0);
}
