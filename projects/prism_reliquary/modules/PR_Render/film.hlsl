// PR_Render / film.hlsl — the soap membrane.
//
// It is a separate pass rather than a separate node because it is TRANSMISSIVE: it has to
// composite over the resolved opaque image and be occluded by it, which means it needs the
// solids pass's colour and depth. Keeping it inside this Module also means it shares the one
// injected internal camera — two camera-capable renderer nodes would have needed an external
// camera rig for no gain.
//
// The colour is a real thin-film interference model (pr_thinfilm), not a rainbow ramp. That
// matters: interference bands compress toward grazing angles and shift with thickness, which
// is exactly the behaviour that makes the reference read as a soap membrane instead of
// tinted glass.

#include "scene.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

float3 envAt(float3 d)
{
    return _Tex1.SampleLevel(LinearSampler, pr_env_uv(d), 0).rgb;
}

// Sheet displacement over the drape's local XY, in local Z.
float filmH(float2 xy, CastRec fm, float t)
{
    float  f = max(fm.p1, 1.0);
    float2 n = xy / max(fm.dims.xy, float2(1e-4, 1e-4));   // -1..1 across the drape

    float h;
    if (film_form == 1)
    {
        // Furl — one dominant roll, like a sheet curling off its near edge.
        h  = sin(n.x * f * 0.55 - 1.2 + t * 0.83) * 0.95;
        h += sin(n.y * f * 0.30 + 0.4 - t * 0.51) * 0.22;
    }
    else if (film_form == 2)
    {
        // Sheet — a gentle single bow, almost taut.
        h = (1.0 - n.x * n.x) * (0.55 + 0.16 * sin(t * 0.61)) + n.y * 0.12;
    }
    else
    {
        // Drape — several soft folds crossing the sheet. This is the reference.
        // Three harmonics at incommensurate rates. Equal rates would read as one sheet
        // sliding; different ones read as a membrane breathing.
        h  = sin(n.x * f * 1.15 + n.y * 0.80 + t * 1.00) * 0.55;
        h += sin(n.y * f * 0.85 - n.x * 0.50 + 1.7 - t * 0.73) * 0.40;
        h += sin((n.x + n.y) * f * 0.55 + 3.1 + t * 1.31) * 0.22;
    }

    // The middle is held taut and the edges billow, as a hanging sheet does.
    float edge = smoothstep(0.0, 1.0, length(n) * 0.80);
    return h * fm.dims.z * lerp(0.40, 1.0, edge);
}

// The membrane distance field. The 0.34 divisor is a Lipschitz guard: the heightfield's
// slope can far exceed 1, and without it the march steps straight through the sheet.
float filmSDF(float3 p, CastRec fm, float t)
{
    float3 lp    = pr_qinv(fm.rot, p - fm.pos);
    float  sheet = abs(lp.z - filmH(lp.xy, fm, t)) - fm.radius;

    // ORGANIC BOUNDARY, not a rectangle. A box-bounded sheet reads as a cut panel of
    // oil-slick plastic; the reference's drape has lobed, cloth-like edges. This is a
    // rounded superellipse pushed around by two low harmonics of its own polar angle.
    float2 nn  = lp.xy / max(fm.dims.xy, float2(1e-4, 1e-4));
    float  ang = atan2(nn.y, nn.x);
    float  rr  = length(nn * float2(1.00, 0.94));
    float  wob = 0.15 * sin(ang * 3.0 + 1.1) + 0.09 * sin(ang * 5.0 - 2.2);
    float  bound = (rr - (1.0 + wob)) * min(fm.dims.x, fm.dims.y);

    return pr_smax(sheet * 0.34, bound, 0.06);
}

float3 filmNormal(float3 p, CastRec fm, float e, float t)
{
    float2 k = float2(1.0, -1.0) * e;
    return normalize(k.xyy * filmSDF(p + k.xyy, fm, t) + k.yyx * filmSDF(p + k.yyx, fm, t) +
                     k.yxy * filmSDF(p + k.yxy, fm, t) + k.xxx * filmSDF(p + k.xxx, fm, t));
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    float2 suv = ((float2)pixel + 0.5) / _Resolution.xy;

    float4 solid = _Tex2.SampleLevel(LinearSampler, suv, 0);
    float3 col   = solid.rgb;
    float  solidT = solid.a;              // linear depth, or a large value on a miss

    // The clock comes from the plan's stage record, so the membrane breathes on the same
    // phase the spheres float on.
    float tphase = Cast[SLOT_STAGE].aux.x * film_undulate;

    CastRec fm = Cast[SLOT_FILM];
    if (fm.active < 0.5 || film_opacity <= 0.001)
    {
        OutputUAV[pixel] = float4(col, solidT);
        return;
    }

    // Same internal camera as the solids pass. Not a copy of the equation — the same
    // injected matrix.
    float2 ndc   = float2(suv.x * 2.0 - 1.0, 1.0 - suv.y * 2.0);
    float4 nearW = mul(_InvViewProjMatrix, float4(ndc, 0.0, 1.0));
    float4 farW  = mul(_InvViewProjMatrix, float4(ndc, 1.0, 1.0));
    nearW /= nearW.w;
    farW  /= farW.w;

    float3 ro = _CameraPos;
    float3 rd = normalize(farW.xyz - nearW.xyz);

    // Cheap bounding-sphere entry so pixels nowhere near the drape pay almost nothing.
    float bound = length(fm.dims) + fm.dims.z + 0.2;
    float3 oc = ro - fm.pos;
    float b = dot(oc, rd), c2 = dot(oc, oc) - bound * bound;
    float disc = b * b - c2;
    if (disc <= 0.0)
    {
        OutputUAV[pixel] = float4(col, solidT);
        return;
    }
    float tEnter = max(-b - sqrt(disc), 0.05);
    float tExit  = min(-b + sqrt(disc), solidT);

    // ---- ANALYTIC SILHOUETTE COVERAGE ---------------------------------------
    // The membrane is one ray per pixel, so a plain hit/miss test gives a hard binary edge
    // — the single worst aliasing in the frame, and something a post filter can only ever
    // partly disguise. But this is a distance field: the march already knows how CLOSE it
    // came to the surface. Converting that closest approach into sub-pixel coverage
    // antialiases the silhouette analytically, at one ray, for a couple of extra maths ops.
    //
    // The pixel's angular size comes from the real camera (one pixel step through the same
    // inverse view-projection), so the coverage width is correct at any FOV or resolution
    // rather than a tuned constant.
    float2 ndcX  = float2((suv.x + 1.0 / _Resolution.x) * 2.0 - 1.0, 1.0 - suv.y * 2.0);
    float4 farX  = mul(_InvViewProjMatrix, float4(ndcX, 1.0, 1.0));
    farX /= farX.w;
    float  pxAng = max(length(normalize(farX.xyz - nearW.xyz) - rd), 1e-7);

    float t     = tEnter;
    bool  hit   = false;
    float minRel = 1e9;      // closest approach, in pixel widths
    float minT   = tEnter;

    [loop] for (int i = 0; i < film_steps; i++)
    {
        if (t > tExit) break;
        float d = filmSDF(ro + rd * t, fm, tphase);

        float rel = d / max(t * pxAng, 1e-6);
        if (rel < minRel) { minRel = rel; minT = t; }

        if (d < 0.0012) { hit = true; break; }
        t += max(d, 0.0012);
    }

    // Full coverage on a hit; a near miss inside the edge band gets partial coverage and is
    // shaded at its closest-approach point.
    float cover = 1.0;
    if (!hit)
    {
        cover = saturate(1.0 - minRel / max(film_edge_aa, 1e-3));
        if (cover > 0.002) { hit = true; t = minT; }
    }

    if (hit)
    {
        float3 p    = ro + rd * t;
        float3 n    = filmNormal(p, fm, 0.0035, tphase);
        float3 v    = -rd;
        if (dot(n, v) < 0.0) n = -n;
        float  cosI = saturate(dot(n, v));

        // Thickness varies over the sheet — that variation IS the banding.
        float3 lp = pr_qinv(fm.rot, p - fm.pos);
        // the thickness field drifts too, so the interference bands crawl across the folds
        float  tv = pr_fbm(lp * film_grain * 2.2 + fm.seed + tphase * 0.07, 3);
        float  dnm = fm.p0 * (0.70 + 0.75 * tv);

        float3 tf = pr_thinfilm(dnm, cosI, 1.34);
        float  F  = pr_fresnel(cosI, 0.028) * film_opacity;

        // Reflected studio, tinted by the interference.
        float3 refl = envAt(reflect(rd, n)) * tf;

        // Transmitted image, displaced by the sheet's slope. A soap film barely refracts,
        // so this is a small offset — enough to smear what is behind it, not to distort it.
        float2 duv = n.xy * film_refract * 0.035;
        float3 through = _Tex2.SampleLevel(LinearSampler, saturate(suv + duv), 0).rgb;

        // Absorption is nearly zero; the membrane mostly ADDS. That is why the reference's
        // drape brightens the void behind it instead of darkening it.
        float3 filmCol = through * lerp(1.0, 0.86, F) + refl * (F * 3.4 + 0.10 * film_opacity);

        // Grazing-angle spectral flare along the silhouette and the fold crests.
        float graze = pow(1.0 - cosI, 3.0);
        filmCol += tf * graze * film_flare;

        col = lerp(col, filmCol, cover);

        // Depth only where the membrane genuinely covers the pixel. Writing it across the
        // soft fringe would put a ring of wrong focus around the drape.
        if (cover > 0.5) solidT = min(solidT, t);
    }

    // Alpha carries linear depth for PR_Post's lens blur. Nothing displays this pass
    // directly, so the usual alpha = 1.0 rule does not apply to it.
    OutputUAV[pixel] = float4(col, solidT);
}
