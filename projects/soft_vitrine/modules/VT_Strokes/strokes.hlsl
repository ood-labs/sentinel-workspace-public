// VT_Strokes / strokes.hlsl — the thin drawn elements.
//
// The reference's squiggles, rainbow bundles, black vein network and orange gradient tube are
// all essentially 2D marks with a rounded, lit cross-section. Ray-marching them as real 3D
// tubes would cost far more and buy nothing, so they are drawn in stage space and given a
// CYLINDRICAL fake normal derived from the distance to the spine: at distance d inside a tube
// of local radius r, the surface tilts by d/r and the height is sqrt(1 - (d/r)^2). That single
// trick is what makes a flat mark read as a glossy extruded tube.
//
// Depth: where several strokes overlap, the one with the larger planned depth band wins. That
// keeps overlap consistent with what VT_Plan decided rather than with buffer order.
#include "../_shared/vitrine.hlsli"

StructuredBuffer<PlanRec> Plan : register(t0);
StructuredBuffer<LimbRec> Limbs : register(t1);
RWTexture2D<float4> OutputUAV : register(u0);

#define ST_TUBE   0
#define ST_RIBBON 1
#define ST_MARKER 2
#define ST_BEADED 3

// distance to a tapered segment, reporting the local radius at the closest point
float segDist(float2 p, float2 a, float2 b, float ra, float rb, out float rloc)
{
    float2 pa = p - a, ba = b - a;
    float h = saturate(dot(pa, ba) / max(dot(ba, ba), 1e-9));
    rloc = lerp(ra, rb, h);
    return length(pa - ba * h);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;
    float2 uv = ((float2)pixel + 0.5) / _Resolution.xy;
    float px = 1.0 / _Resolution.y;

    int style = (int)stroke_style;

    float bestScore = -1.0;      // depth band of the winning stroke
    float bestSd = 1e9;          // signed distance of the winner
    float bestR = 1.0;
    float bestSpine = 1e9;
    float3 bestHue = float3(0, 0, 0);
    float bestT = 0.0;
    float nearestEdge = 1e9;     // for the antialiased rim when nothing covers this pixel
    float3 nearestHue = float3(0, 0, 0);
    float nearestR = 1.0;
    float nearestSpine = 1e9;
    float nearestT = 0.0;
    float nearestScore = -1.0;

    [loop]
    for (uint g = LIMB_STROKE_H_0; g < LIMB_HEADERS; g++)
    {
        LimbRec h = Limbs[g];
        if (h.active < 0.5) continue;
        if (length(uv - h.pos.xy) > h.radius + 0.01) continue;    // bounding-circle reject

        uint first = (uint)max(h.parent, 0.0);
        uint count = (uint)max(h.group, 0.0);

        [loop]
        for (uint k = 0u; k < count && k < 64u; k++)
        {
            LimbRec n = Limbs[first + k];
            if (n.active < 0.5) continue;
            if (n.parent < 0.0) continue;                          // run start: no segment yet
            LimbRec pr = Limbs[(uint)n.parent];

            float ra = pr.radius, rb = n.radius;
            if (style == ST_BEADED)
            {
                // REPAIRED after the exploration sweep. At 22 cycles the bead period was far
                // shorter than the spacing between published points, so the swell aliased away
                // to nothing on every hairline. 7 cycles with a deeper pinch actually reads.
                ra *= 0.34 + 1.30 * abs(sin(pr.tparam * 7.0 + pr.seed));
                rb *= 0.34 + 1.30 * abs(sin(n.tparam * 7.0 + n.seed));
            }

            float rloc;
            float spine = segDist(uv, pr.pos.xy, n.pos.xy, ra, rb, rloc);
            if (style == ST_RIBBON) rloc *= 1.35;                  // wider, flatter section
            float sd = spine - rloc;

            float score = n.pos.z;                                 // planned depth band
            float3 hue = vt_accent(n.material);

            if (sd <= 0.0)
            {
                // Nearer stroke wins outright; WITHIN one stroke the closest segment wins.
                // Taking the first covering segment instead left a dark rib at every joint,
                // because the shading reads the cross-section parameter of whichever segment
                // was picked rather than of the one the pixel is actually inside.
                if (score > bestScore || (score == bestScore && spine < bestSpine))
                {
                    bestScore = score; bestSd = sd; bestR = rloc;
                    bestSpine = spine; bestHue = hue; bestT = n.tparam;
                }
            }
            else if (sd < nearestEdge)
            {
                nearestEdge = sd; nearestHue = hue; nearestR = rloc;
                nearestSpine = spine; nearestT = n.tparam; nearestScore = score;
            }
        }
    }

    float3 col = float3(0, 0, 0);
    float cov = 0.0;

    bool covered = (bestScore >= 0.0);
    float sd = covered ? bestSd : nearestEdge;
    float rloc = covered ? bestR : nearestR;
    float spine = covered ? bestSpine : nearestSpine;
    float3 hue = covered ? bestHue : nearestHue;
    float tp = covered ? bestT : nearestT;

    float alpha = vt_fill(sd, px);
    if (alpha > 0.001)
    {
        // cylindrical cross-section: 0 at the spine, 1 at the silhouette
        float q = saturate(spine / max(rloc, 1e-5));
        float nz = sqrt(max(1.0 - q * q, 0.0));

        // gradient along the run — the reference's orange tube runs orange to yellow
        float3 c = lerp(hue, vt_accent(frac(tp * gradient_span + 0.13)), gradient * saturate(tp));

        if (style == ST_MARKER)
        {
            // deliberately flat: a drawn mark, no volume at all
            col = c * (0.92 + 0.08 * nz);
        }
        else if (style == ST_RIBBON)
        {
            // a flat strap: mostly even across its width, with both edges catching the key
            float edge = smoothstep(0.45, 1.0, q);
            col = c * (0.58 + 0.42 * nz);
            col += float3(1, 1, 1) * edge * 0.28 * shine;
        }
        else
        {
            // round tube: a bright core streak falling off to a dark contact edge, which is
            // what separates overlapping strokes without any outline
            // Solid saturated body first, highlight second. Weighting it the other way made the
            // strokes read as thin neon outlines instead of the reference's chunky glossy tubes.
            float lam = saturate(nz * 0.72 + 0.28);
            col = c * (0.62 + 0.52 * lam);
            float spec = pow(saturate(nz), 7.0) * smoothstep(0.55, 0.0, q);
            col += float3(1, 1, 1) * spec * 0.34 * shine;
            col *= lerp(1.0, 0.68, smoothstep(0.74, 1.0, q));
        }

        col += c * ambient * 0.25;
        cov = alpha;
        col *= alpha;
    }

    OutputUAV[pixel] = float4(col * exposure, cov);
}
