// VC_Render / render.hlsl — spectral ray transport through a stack of media.
//
// Owns Sentinel's internal camera. Every ray comes from the injected _InvViewProjMatrix;
// there is no shader-local camera equation anywhere in this project.
//
// THE TRANSPORT LOOP is the whole node. A ray is not shaded where it lands — it is carried
// through interface after interface, splitting Fresnel-wise at each one, accumulating
// Beer-Lambert absorption along every segment it spends inside a medium, and terminating only
// on an opaque plate, on the cyclorama, on the environment, or when its throughput has decayed
// to nothing. Refraction, caustic-like internal brightening, total internal reflection, the
// swollen lensing of the air cavities and the reference's black interior windows all fall out
// of that one loop; none of them is an effect that was added.
//
// cs_5_0 forbids recursion, so a partial reflection cannot re-enter the tracer. Partial
// reflections therefore resolve straight to the studio panorama, while TOTAL internal
// reflections — the ones that carry the scene's own image around inside the glass, and the
// ones the reference is visibly full of — continue in the main loop and are fully traced.
#include "scene.hlsli"

RWTexture2D<float4> OutputUAV : register(u0);

// _Tex1 is VC_Env's sharp Studio panorama; _Tex2 is its cosine-convolved irradiance map.
float3 envAt(float3 dStage)
{
    return _Tex1.SampleLevel(LinearSampler, vc_envUV(vcStageToWorld(dStage)), 0).rgb;
}

float3 irradianceAt(float3 nStage)
{
    return _Tex2.SampleLevel(LinearSampler, vc_envUV(vcStageToWorld(nStage)), 0).rgb;
}

// Soft shadow toward the key. The direction is not authored here — it arrives from VC_Env's
// key_dir control outputs, so moving the studio light moves this shadow and there is no second
// copy of the rig to fall out of sync.
float vcSoftShadow(float3 p, float3 ld)
{
    float res = 1.0;
    float t = 0.06;
    int steps = (int)shadow_steps;
    [loop]
    for (int i = 0; i < 64; i++)
    {
        if (i >= steps) break;
        float d = vcOccluderSDF(p + ld * t);
        res = min(res, shadow_sharp * d / t);
        t += clamp(d, 0.05, 0.7);
        if (res < 0.01 || t > 16.0) break;
    }
    res = saturate(res);
    // The sculpture is glass. A fully opaque shadow under it would be a lie, so what the
    // occluder blocks is scaled by how much light the glass actually passes.
    return saturate(res + (1.0 - res) * shadow_transmit);
}

float3 shadeOpaque(float3 p, float3 n, float3 rd, bool isCyc, int mat, float3 tint)
{
    float3 albedo = isCyc ? cyc_albedo : vc_plateAlbedo(mat, tint);

    float3 c = albedo * irradianceAt(n) * plate_diffuse;

    if (isCyc)
        c *= lerp(1.0, vcSoftShadow(p + n * 0.02, gKeyStage), shadow_strength);

    // The plates are lacquered card, not chalk: a broad low-gloss term keeps them sitting in
    // the same light as the glass around them instead of reading as cut-out matte stickers.
    float f = 0.035 + 0.22 * pow(saturate(1.0 + dot(n, rd)), 5.0);
    c += envAt(reflect(rd, n)) * f * (isCyc ? cyc_spec : plate_spec);

    return c;
}

// ---------------------------------------------------------------------------
// One spectral path.
// ---------------------------------------------------------------------------
float3 tracePath(float3 ro, float3 rd, float lambdaNM, out float firstT, out float stepsUsed,
                 out int firstMedium, out float3 firstNormal)
{
    float lambdaUM = lambdaNM * 0.001;

    float3 L = float3(0, 0, 0);
    float3 T = float3(1, 1, 1);
    float3 medTint;
    int medium = vcMediumAt(ro, medTint);

    firstT = far_clip;
    stepsUsed = 0.0;
    firstMedium = medium;
    firstNormal = float3(0, 0, 1);

    float pushE = surface_eps * 4.0;
    float lipS = step_scale / vcIncLipschitz();
    int maxB = (int)max_bounces;
    int steps = (int)march_steps;
    // Did the path actually finish, or did it just run out of interface budget?
    bool resolved = false;

    [loop]
    for (int b = 0; b < 24; b++)
    {
        if (b >= maxB) break;

        // ---- the cyclorama, analytically. It brackets the march: nothing beyond it can be
        // seen, so the sculpture only has to be searched up to here.
        float3 cycN = float3(0, 1, 0);
        float tCyc = far_clip;
        {
            float3 oW = vcStageToWorld(ro), dW = vcStageToWorld(rd);
            float tc; float3 nW;
            if (vcCycHit(oW, dW, tc, nW) && tc < tCyc)
            {
                tCyc = tc;
                cycN = normalize(vcWorldToStage(nW));
            }
        }
        float tMax = min(far_clip, tCyc);

        // ---- march to the next interface, from whichever side of it we are on
        float t = pushE;
        int hid = SH_NONE;
        bool found = false;
        [loop]
        for (int i = 0; i < 320; i++)
        {
            if (i >= steps) break;
            stepsUsed += 1.0;
            float3 q = ro + rd * t;
            int id;
            float du = vcBoundary(q, id);
            if (du < surface_eps) { hid = id; found = true; break; }
            t += max(du * lipS, surface_eps * 0.75);
            if (t > tMax) break;
        }

        // ---- Beer-Lambert over the segment just travelled, in the medium it was travelled in
        float segLen = found ? t : tMax;
        if (medium != MED_AIR)
            T *= exp(-vc_extinction(medium, medTint) * min(segLen, far_clip) * absorb_gain);

        if (!found)
        {
            if (tCyc < far_clip)
            {
                float3 pc = ro + rd * tCyc;
                if (b == 0) firstT = tCyc;
                float3 nc = cycN;
                if (dot(nc, rd) > 0.0) nc = -nc;
                L += T * shadeOpaque(pc, nc, rd, true, MAT_WHITE, float3(1, 1, 1));
            }
            else
            {
                L += T * envAt(rd);
            }
            resolved = true;
            break;
        }

        float3 p = ro + rd * t;
        if (b == 0) firstT = t;

        float3 nextTint;
        int next = vcMediumAt(p + rd * pushE, nextTint);

        if (next == medium)
        {
            // A coincident face or a grazing contact: no interface was actually crossed.
            // Step through rather than reflecting off nothing.
            ro = p + rd * pushE;
            continue;
        }

        float3 n = vcNormal(hid, p);
        float cosI = -dot(rd, n);
        if (cosI < 0.0) { n = -n; cosI = -cosI; }
        if (b == 0) { firstNormal = n; firstMedium = next; }

        if (!VC_MAT_TRANSMISSIVE(next))
        {
            L += T * shadeOpaque(p, n, rd, false, next, nextTint);
            resolved = true;
            break;
        }

        float n1 = vcIOR(medium, lambdaUM);
        float n2 = vcIOR(next, lambdaUM);
        float F = vcFresnel(cosI, n1, n2);

        // A cavity boundary is a MEMBRANE, not a bare interface. Swapping the plain Fresnel
        // reflectance for the film's Airy reflectance is what produces the reference's narrow
        // rainbow fringes — and it produces them in the right places for free, because the
        // film's bands compress toward grazing incidence exactly where a silhouette is.
        if (film_amount > 0.001 && (medium == MAT_CAVITY || next == MAT_CAVITY))
        {
            float Rf = vcThinFilm(lambdaNM, vcFilmThickness(p), cosI, n1, film_ior);
            F = lerp(F, saturate(Rf), film_amount);
        }

        float3 refl = reflect(rd, n);
        float3 rt = refract(rd, n, n1 / n2);

        if (dot(rt, rt) < 1e-8)
        {
            // Total internal reflection. Traced, not sampled: this is the light that bounces
            // around inside a glass bar and carries the other bars' images with it.
            rd = refl;
            ro = p + rd * pushE;
        }
        else
        {
            L += T * F * envAt(refl) * spec_gain;
            float3 Tt = T * (1.0 - F);

            // ROUGH INTERFACE. A perfectly smooth membrane shows whatever is behind it, and
            // behind this sculpture is a dark seamless — which is why clear cavities render as
            // dark chrome rather than as the reference's milky opalescent masses. A real soap
            // or frosted membrane scatters transmission into a wide lobe, and the wide-lobe
            // answer is exactly what the pre-convolved irradiance map already holds. Splitting
            // the transmitted energy between that lobe and the coherent ray is a single-scatter
            // rough dielectric, and it is what makes the masses read as substance.
            float rough = (medium == MAT_CAVITY || next == MAT_CAVITY) ? inclusion_frost : glass_frost;
            if (rough > 0.001)
            {
                L += Tt * rough * irradianceAt(-n) * frost_tint;
                Tt *= (1.0 - rough);
            }

            T = Tt;
            rd = normalize(rt);
            ro = p + rd * pushE;
            medium = next;
            medTint = nextTint;
        }

        if (max(T.r, max(T.g, T.b)) < throughput_floor) { resolved = true; break; }
    }

    // A path that exhausted its interface budget still carries its throughput. Dropping it on
    // the floor renders those pixels BLACK, which is why a low Max Interfaces setting used to
    // outline every glass volume in soot — it read as a shading bug rather than as a budget.
    // Cashing the remaining throughput out against the environment is the standard escape: the
    // deep interior of a stack of boxes is mostly ambient anyway, so the approximation is mild
    // and it is what makes the cheap quality rungs usable instead of merely fast.
    if (!resolved) L += T * envAt(rd);

    return L;
}

[numthreads(8, 8, 1)]
void main(uint3 DTid : SV_DispatchThreadID)
{
    uint W, H;
    OutputUAV.GetDimensions(W, H);
    uint2 pix = DTid.xy;
    if (pix.x >= W || pix.y >= H) return;
    float2 res = float2(W, H);

    vcSetupScene();

    int aa = (int)clamp((float)aa_samples, 1.0, 3.0);
    int ns = (int)clamp((float)spectral_samples, 1.0, 7.0);
    int vmode = (int)view_mode;

    float3 acc = float3(0, 0, 0);
    float3 wsum = float3(0, 0, 0);
    float depthAcc = 0.0;
    float stepAcc = 0.0;
    float3 nAcc = float3(0, 0, 0);
    float medAcc = 0.0;
    float sampleCount = 0.0;

    for (int sy = 0; sy < 3; sy++)
    {
        if (sy >= aa) continue;
        for (int sx = 0; sx < 3; sx++)
        {
            if (sx >= aa) continue;

            float2 jit = (float2((float)sx, (float)sy) + 0.5) / (float)aa;
            float2 screenUV = ((float2)pix + jit) / res;
            float2 ndc = float2(screenUV.x * 2.0 - 1.0, 1.0 - screenUV.y * 2.0);

            float4 nearW = mul(_InvViewProjMatrix, float4(ndc, 0.0, 1.0));
            float4 farW  = mul(_InvViewProjMatrix, float4(ndc, 1.0, 1.0));
            nearW /= nearW.w;
            farW  /= farW.w;

            float3 roW = _CameraPos;
            float3 rdW = normalize(farW.xyz - nearW.xyz);
            float3 ro = vcWorldToStage(roW);
            float3 rd = normalize(vcWorldToStage(rdW));

            for (int k = 0; k < 7; k++)
            {
                if (k >= ns) break;
                // Sampling the visible band. One sample sits at 550 nm (a neutral trace with
                // no dispersion at all); more samples spread across 440-650 and each carries
                // its own index of refraction, so the split is produced by geometry rather
                // than by offsetting a colour channel afterwards.
                float lam = (ns == 1) ? 550.0 : lerp(442.0, 648.0, (float)k / (float)(ns - 1));
                float3 w = (ns == 1) ? float3(1, 1, 1) : vcSpectralWeight(lam);

                float ft, su;
                int fm;
                float3 fn;
                float3 Lk = tracePath(ro, rd, lam, ft, su, fm, fn);

                acc += w * Lk;
                wsum += w;
                depthAcc += ft;
                stepAcc += su;
                nAcc += fn;
                medAcc += (float)(fm + 1);
                sampleCount += 1.0;
            }
        }
    }

    float3 col = acc / max(wsum, 1e-4);
    float depth = depthAcc / max(sampleCount, 1.0);
    float3 nrm = normalize(nAcc / max(sampleCount, 1.0) + 1e-6);

    col *= exposure;

    // Diagnostic views ship as a real control rather than a debug #define. In a renderer whose
    // whole behaviour is invisible bookkeeping, these are the only way to tell a dead lane
    // from a dark one: Steps finds where the cost is, Medium proves the stack is being tracked,
    // Depth proves the alpha lane the post node focuses on is alive.
    if (vmode == 1)
    {
        float m = medAcc / max(sampleCount, 1.0) - 1.0;
        col = (m < -0.5) ? float3(0.05, 0.05, 0.07) : vc_hash33(float3(m * 1.7 + 0.3, m * 0.9, m * 2.3));
    }
    else if (vmode == 2)
    {
        float s = stepAcc / max(sampleCount, 1.0);
        float u = saturate(s / max(step_budget, 1.0));
        col = float3(saturate(u * 2.0), saturate(u * 2.0 - 0.6), saturate(u * 3.0 - 2.0));
    }
    else if (vmode == 3) col = nrm * 0.5 + 0.5;
    else if (vmode == 4) col = saturate((depth - depth_near) / max(depth_far - depth_near, 1e-3)).xxx;

    OutputUAV[pix] = float4(max(col, 0.0), depth);
}
