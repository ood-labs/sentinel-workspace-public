// PR_Render / solids.hlsl — the opaque pass.
//
// Owns Sentinel's internal camera. Every ray comes from the injected _InvViewProjMatrix;
// there is no shader-local camera equation anywhere in this project.
//
// All lighting is sampled from PR_Env's panorama. That is deliberate: the renderer holds no
// duplicate copy of "where the key is". If the studio moves, every chrome ball, every glass
// edge and every fur highlight moves with it, because they are all reading the same texture.
//
// STRUCTURE NOTE: cs_5_0 forbids recursion, so shading cannot call itself to resolve a
// reflection. Instead the surface frame is resolved first (surfaceFrame), the reflection
// colour is resolved second (either one scene bounce or straight from the environment), and
// shadeCore is a pure function of both. That is why there are two thin wrappers rather than
// one shade function with an `allowBounce` flag.

#include "scene.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

// _Tex1 is the Studio panorama (pass input slot 1).
float3 envAt(float3 d)
{
    return _Tex1.SampleLevel(LinearSampler, pr_env_uv(d), 0).rgb;
}

static const float3 HEMI[8] = {
    float3( 0.000,  0.000, 1.000), float3( 0.500,  0.000, 0.866),
    float3(-0.250,  0.433, 0.866), float3(-0.250, -0.433, 0.866),
    float3( 0.707,  0.408, 0.577), float3(-0.707,  0.408, 0.577),
    float3( 0.000, -0.816, 0.577), float3( 0.325,  0.188, 0.927)
};

// Cheap irradiance: 8 cosine-ish taps. Enough because the studio is almost entirely dark
// with a few concentrated sources, which is exactly the case a handful of taps handles well.
float3 envDiffuse(float3 n)
{
    float3 up = abs(n.y) < 0.95 ? float3(0, 1, 0) : float3(1, 0, 0);
    float3 tx = normalize(cross(up, n));
    float3 ty = cross(n, tx);
    float3 s = 0.0;
    [unroll] for (int i = 0; i < 8; i++)
    {
        float3 h = HEMI[i];
        s += envAt(normalize(tx * h.x + ty * h.y + n * h.z)) * h.z;
    }
    return s * 0.30;
}

float3 envSpec(float3 r, float rough, float jit)
{
    if (rough < 0.015) return envAt(r);
    float3 up = abs(r.y) < 0.95 ? float3(0, 1, 0) : float3(1, 0, 0);
    float3 tx = normalize(cross(up, r));
    float3 ty = cross(r, tx);
    float3 s = 0.0;
    [unroll] for (int i = 0; i < 4; i++)
    {
        float a = PR_TAU * ((float)i / 4.0 + jit);
        float2 o = float2(cos(a), sin(a)) * rough;
        s += envAt(normalize(r + tx * o.x + ty * o.y));
    }
    return s * 0.25;
}

float3 backdrop(float2 suv)
{
    CastRec st = Cast[SLOT_STAGE];
    float lift = st.active > 0.5 ? st.dims.z : 0.26;
    // One soft bloom of wall light behind the subject's shoulder, and nothing else. The
    // reference's background is a void; resisting the urge to put something in it is most
    // of why the objects read as bright.
    float d = length((suv - float2(0.34, 0.30)) * float2(1.25, 1.05));
    return PR_VOID * (1.0 + lift * 5.5 * exp(-d * 2.35))
         + PR_VOID * 0.6 * exp(-length(suv - float2(0.72, 0.62)) * 3.2) * lift;
}

// ---------------------------------------------------------------------------
// Surface frame. Resolves the shading normal (faceted for chips, ripple-perturbed for the
// floor, coarse-epsilon for the pelt), the reflection roughness, and occlusion — once, so
// both the direct and the reflected shading paths agree about the surface.
// ---------------------------------------------------------------------------
void surfaceFrame(float3 p, float3 rd, float3 hit,
                  out float3 n, out float rough, out float ao)
{
    float   mat = hit.y;
    CastRec rec = Cast[(uint)max(hit.z, 0.0)];

    float neps = (mat == MAT_FUR) ? normal_eps * 3.4 : normal_eps;
    n = pr_normal(p, neps);

    if (mat == MAT_GEM)
    {
        // Facet the normal. A smooth normal makes these read as beads; the reference's
        // chips are clearly cut, and the cut is what produces the single hard glint.
        float2 sa = float2(atan2(n.z, n.x), acos(clamp(n.y, -1.0, 1.0)));
        float2 qz = float2(3.0, 2.4) * max(gem_facets, 0.5);
        sa = (floor(sa * qz) + 0.5) / qz;
        float3 fn = normalize(float3(sin(sa.y) * cos(sa.x), cos(sa.y), sin(sa.y) * sin(sa.x)));
        n = normalize(lerp(n, fn, 0.85));
        rough = 0.02;
    }
    else if (mat == MAT_FLOOR)
    {
        CastRec st = Cast[SLOT_STAGE];
        // Broad striations running in z: the reflection smears along the viewing axis, not
        // across it, which is what makes the reference's floor read as a wet sweep.
        float wob = sin(p.z * 5.5 + pr_vnoise(float3(p.x * 1.7, 0.0, p.z * 3.1)) * 5.0) * 0.5 + 0.5;
        n = normalize(n + float3(0.0, 0.0, (wob - 0.5) * st.dims.y * 0.06));
        rough = lerp(0.16, 0.012, st.dims.x) + st.dims.y * 0.020 * wob;
    }
    else if (mat == MAT_CHROME) rough = rec.p0 + 0.01;
    else if (mat == MAT_DGLASS) rough = 0.025;
    else if (mat == MAT_MARBLE) rough = 0.10;
    else if (mat == MAT_FUR)    rough = 0.20;
    else                        rough = 0.30;

    ao = pr_ao(p, n, ao_amt);
}

// ---------------------------------------------------------------------------
// The materials. Pure in (p, rd, hit, n, refl, ao) — no marching, no recursion.
// ---------------------------------------------------------------------------
float3 shadeCore(float3 p, float3 rd, float3 hit, float3 n, float3 refl, float ao)
{
    float   mat = hit.y;
    CastRec rec = Cast[(uint)max(hit.z, 0.0)];

    float3 v    = -rd;
    float  cosI = saturate(dot(n, v));
    float  rim  = pow(1.0 - cosI, 2.2);

    if (mat == MAT_FUR)
    {
        CastRec tr = Cast[SLOT_TORUS];
        float3  lp = pr_qinv(tr.rot, p - tr.pos);

        // THE SMOOTH NORMAL IS THE WHOLE TRICK.
        //
        // `n` is the normal of a noise-displaced field, so it scatters wildly from pixel to
        // pixel. Feeding that into a high-contrast studio gives rainbow CONFETTI: every
        // pixel independently rolls a reflection direction and some fraction of them hit
        // the softbox. Real fur reads as coherent colour bands because the strands are
        // coherent. So every broad term here — irradiance, the anisotropic sheen, and above
        // all the spectral phase — is computed from the ANALYTIC normal of the underlying
        // torus, and the noisy normal contributes only fine strand texture.
        float2 cxz  = normalize(lp.xz + float2(1e-6, 0.0)) * tr.radius;
        float3 lnrm = normalize(lp - float3(cxz.x, 0.0, cxz.y));
        float3 sn   = pr_qrot(tr.rot, lnrm);

        float scos = saturate(dot(sn, v));
        float srim = pow(1.0 - scos, 2.2);

        // Strand field read from the SAME function the SDF displaced with, so texture
        // tracks geometry instead of floating over it.
        float strand = pr_strand(lp, tr);
        float L      = pr_furLen(tr);
        float dep    = saturate((pr_torus(lp, tr.radius, tr.dims.x) + L) / max(L * 2.0, 1e-4));
        float lean   = saturate(dot(n, sn));           // how far this strand tips off the body

        float3 amb = envDiffuse(sn);

        // The colour has to be driven by a HIGHLIGHT, not by irradiance. `amb` is smooth and
        // nearly uniform over the pelt, so gating the spectral terms with it paints every
        // strand — the torus comes out as a full-spectrum gradient with no black in it.
        // envSpec off the SMOOTH normal is bright only where the body actually reflects a
        // source, which is where the reference's colour lives; and because sn is analytic
        // rather than noise-displaced, sampling a high-contrast studio with it is safe.
        float3 spec = envSpec(reflect(rd, sn), 0.28, pr_hash31(p * 37.0));

        // Fur is mostly shadow: the pelt darkens sharply toward the roots, which is what
        // gives the reference's torus an almost-black body under all that colour.
        float3 diff = amb * rec.tint * fur_shade * lerp(0.10, 1.0, dep) * lerp(0.45, 1.0, lean);

        // Anisotropic sheen combed around the ring, off the smooth frame.
        float3 ringAxis = pr_qrot(tr.rot, float3(0, 1, 0));
        float3 tang     = normalize(cross(sn, ringAxis) + 1e-5);
        float3 hv       = normalize(v + reflect(rd, sn));
        float  th       = dot(tang, hv);
        float  anis     = pow(saturate(sqrt(max(1.0 - th * th, 0.0))), 30.0);

        // The bands in the reference run CONCENTRIC with the hole — they follow the minor
        // angle around the tube, not the viewing angle. Driving the phase from that angle is
        // what turns a generic iridescent sheen into this specific object.
        float minorA = atan2(lp.y, length(lp.xz) - tr.radius);
        // The pelt's colour creeps around the tube over time. Adding the clock to the
        // spectral PHASE animates the material without moving one atom of geometry, which
        // is why it costs nothing and never fights the layout.
        float drift = Cast[SLOT_STAGE].aux.x * irid_drift;
        float3 irid = pr_spectral(frac(minorA / PR_TAU * irid_bands
                                     + scos * 0.20 + strand * 0.07 + irid_phase + drift));

        // Colour exists only where there IS a highlight, so the body stays black. Crests
        // catch the sheen; roots do not.
        //
        // These coefficients are small on purpose. `amb` already carries the studio's full
        // dynamic range — the key runs at gain 9 — so multiplying it by anything near unity
        // turns the pelt into a neon ring. The reference's torus is a BLACK object wearing
        // colour, and the ratio between the body term and these two is what decides that.
        float crest = lerp(0.25, 1.0, strand);

        float3 col = diff;
        col += spec * lerp(float3(1, 1, 1), irid, irid_sat) * fur_spec * anis * 0.55 * crest;
        col += spec * irid * srim * srim * srim * tr.p1 * 0.55 * crest;
        col += pr_fresnel3(scos, 0.035, irid_spread) * irid * spec * srim * tr.p1 * 0.18;
        // A hard uncoloured glint on the very tips. Real fur sparkles white before it
        // sparkles in colour, and without this the pelt reads as dyed felt.
        col += spec * pow(anis, 3.0) * pow(strand, 3.0) * fur_spec * 0.9;
        return col * ao;
    }

    if (mat == MAT_CHROME)
    {
        float f = lerp(0.72, 1.0, pr_fresnel(cosI, 0.10));
        return refl * rec.tint * f * ao;
    }

    if (mat == MAT_DGLASS)
    {
        float3 f3  = pr_fresnel3(cosI, 0.055, glass_dispersion);
        float3 col = rec.tint * envDiffuse(n) * 3.2;
        col += refl * f3 * glass_rim;
        // The outline itself: a hard grazing-angle spectral edge. This — not geometry — is
        // what draws the reference's neon cross.
        float edge = pow(1.0 - cosI, 4.5);
        col += pr_spectral(frac(cosI * 1.8 + n.y * 0.55 + irid_phase)) * edge * glass_rim * 2.6;
        return col * lerp(1.0, ao, 0.55);
    }

    if (mat == MAT_GEM)
    {
        float3 col = rec.tint * envDiffuse(n) * 2.2;
        col += refl * rec.tint * gem_spark * rec.p1;
        col += refl * pr_fresnel3(cosI, 0.08, glass_dispersion * 1.4) * gem_spark * 0.8;
        return col * ao;
    }

    if (mat == MAT_EMIT)
    {
        return rec.tint * rec.p0 * (0.65 + 0.75 * pow(1.0 - cosI, 1.6));
    }

    if (mat == MAT_MARBLE)
    {
        float3 lp = (p - rec.pos) / max(rec.radius, 1e-3);
        // Gentle veining. The frac() wrap on a high multiplier gives hard-edged cow spots;
        // the reference's little sphere is a soft swirl, so the bands are wide and the
        // contrast between them is small.
        float  sw = pr_fbm(lp * 1.9 + rec.seed, 4);
        sw = 0.5 + 0.5 * sin((sw * 3.4 + lp.y * 0.7) * PR_TAU);
        float3 base = lerp(float3(0.075, 0.078, 0.088), rec.tint, smoothstep(0.25, 0.75, sw));
        base = lerp(base, float3(0.34, 0.36, 0.42), smoothstep(0.82, 1.00, sw) * 0.7);
        float f = pr_fresnel(cosI, 0.05);
        return (base * envDiffuse(n) * 2.4 + refl * (f + 0.14)) * ao;
    }

    if (mat == MAT_FLOOR)
    {
        CastRec st = Cast[SLOT_STAGE];
        float f    = pr_fresnel(cosI, 0.030);
        float fade = saturate(1.0 - length(p.xz) * 0.052);
        return st.tint * 0.55 + refl * f * floor_reflect * saturate(fade + 0.18);
    }

    // matte backing plate
    float3 col = rec.tint * envDiffuse(n) * 1.1;
    col += refl * pr_fresnel(cosI, 0.03) * 0.22;
    return col * ao;
}

// Reflected surfaces shade from the environment only — no second bounce.
float3 shadeReflected(float3 p, float3 rd, float3 hit)
{
    float3 n; float rough, ao;
    surfaceFrame(p, rd, hit, n, rough, ao);
    float jit = pr_hash31(p * 37.0);
    return shadeCore(p, rd, hit, n, envSpec(reflect(rd, n), rough, jit), ao);
}

// One scene bounce. Reflections are what make the floor a floor and the chrome chrome;
// without them both read as flat paint.
float3 resolveReflection(float3 p, float3 n, float3 r, float rough, float jit)
{
    float3 e = envSpec(r, rough, jit);
    if (reflect_bounce < 1) return e;

    float3 o = p + n * 0.006;
    float3 h = pr_march(o, r, reflect_steps, surface_eps * 2.2, 24.0, true);
    if (h.x < 0.0) return e;

    float3 c = shadeReflected(o + r * h.x, r, h);
    // fade with distance so the bounce reads as gloss, not a second world
    return lerp(c, e, saturate(h.x / 14.0));
}

float3 shadePrimary(float3 p, float3 rd, float3 hit)
{
    float3 n; float rough, ao;
    surfaceFrame(p, rd, hit, n, rough, ao);
    float jit = pr_hash31(p * 37.0);

    // Only the mirror-ish materials earn a scene bounce. The pelt shades from irradiance
    // off its smooth frame and never reads `refl` at all, and marching a second ray per
    // fur pixel would be pure cost — fur is by far the most expensive surface to hit.
    float m = hit.y;
    bool wantsBounce = (m == MAT_FLOOR) || (m == MAT_CHROME) || (m == MAT_MARBLE);

    float3 r = reflect(rd, n);
    float3 refl = wantsBounce ? resolveReflection(p, n, r, rough, jit)
                              : envSpec(r, rough, jit);
    return shadeCore(p, rd, hit, n, refl, ao);
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint2 pixel = DTid.xy;
    if (pixel.x >= (uint)_Resolution.x || pixel.y >= (uint)_Resolution.y) return;

    int    ns  = clamp(aa_samples, 1, 3);
    float  inv = 1.0 / (float)(ns * ns);
    float3 acc = 0.0;
    // Nearest opaque depth, carried in alpha for the membrane pass to test against.
    // 1000 rather than a huge sentinel: this is an RGBA16F target and 1e6 becomes inf.
    float  zmin = 1000.0;

    [loop] for (int sy = 0; sy < ns; sy++)
    {
        [loop] for (int sx = 0; sx < ns; sx++)
        {
            float2 off = (float2((float)sx, (float)sy) + 0.5) / (float)ns;
            float2 suv = ((float2)pixel + off) / _Resolution.xy;

            // Internal camera, with the DirectX Y flip. Required contract — see
            // knowledge/internal-camera-template.md.
            float2 ndc   = float2(suv.x * 2.0 - 1.0, 1.0 - suv.y * 2.0);
            float4 nearW = mul(_InvViewProjMatrix, float4(ndc, 0.0, 1.0));
            float4 farW  = mul(_InvViewProjMatrix, float4(ndc, 1.0, 1.0));
            nearW /= nearW.w;
            farW  /= farW.w;

            float3 ro = _CameraPos;
            float3 rd = normalize(farW.xyz - nearW.xyz);

            float3 hit = pr_march(ro, rd, march_steps, surface_eps, 60.0, false);
            if (hit.x < 0.0)
            {
                acc += backdrop(suv);
            }
            else
            {
                acc += shadePrimary(ro + rd * hit.x, rd, hit);
                zmin = min(zmin, hit.x);
            }
        }
    }

    OutputUAV[pixel] = float4(acc * inv * exposure, zmin);
}
