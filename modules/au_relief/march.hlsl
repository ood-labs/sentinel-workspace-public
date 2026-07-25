// AUTOPSIA — raymarch the specimen relief.
// Rays are built ONLY from the injected internal camera (_InvViewProjMatrix /
// _CameraPos) with the DirectX Y flip. No shader-local orbit, no authored view.
//
// A height field is not a signed distance field: stepping by the vertical
// difference overshoots badly at grazing angles and leaves the surface smeared
// into ghost shells. So the terrain is marched by SIGN CROSSING and then
// refined by bisection, while the cage is sphere-traced as a true SDF.
//
// Output gbuffer: rgb = surface normal, a = hit distance (negative = miss).
#include "scene.hlsli"

RWTexture2D<float4> GBuf : register(u0);

float solidD(float3 p) {
    return auSolid(_Tex0, LinearSampler, p, height_scale, slab_depth);
}

float cageD(float3 p) {
    return auSdBoxFrame(p - float3(0.0, height_scale * 0.62, 0.0),
                        float3(AU_DOMAIN.x * 0.5, height_scale * 0.62, AU_DOMAIN.y * 0.5),
                        max(cage_inset, 0.0005));
}

[numthreads(8, 8, 1)]
void main(uint3 tid : SV_DispatchThreadID) {
    if (tid.x >= (uint)_Resolution.x || tid.y >= (uint)_Resolution.y) return;

    float2 screenUV = ((float2)tid.xy + 0.5) / _Resolution.xy;
    float2 ndc = float2(screenUV.x * 2.0 - 1.0, 1.0 - screenUV.y * 2.0);

    float4 nearW = mul(_InvViewProjMatrix, float4(ndc, 0.0, 1.0));
    float4 farW  = mul(_InvViewProjMatrix, float4(ndc, 1.0, 1.0));
    nearW /= nearW.w;
    farW  /= farW.w;

    float3 ro = _CameraPos;
    float3 rd = normalize(farW.xyz - nearW.xyz);

    float tMax = march_far;
    float t = 0.02;
    float tPrev = t;
    float hitT = -1.0;
    float matId = MAT_MISS;

    int steps = (int)clamp(march_steps, 16.0, 256.0);
    [loop] for (int i = 0; i < steps; ++i) {
        float3 p = ro + rd * t;

        if (p.y > height_scale * 1.7 && rd.y > 0.0) break;
        if (p.y < -(slab_depth + 0.5) && rd.y < 0.0) break;

        float dC = cageD(p);
        if (dC < 0.0015) { hitT = t; matId = MAT_CAGE; break; }

        float dS = solidD(p);
        if (dS < 0.0) {
            // crossed into the solid between tPrev and t — bisect to the real hit
            float lo = tPrev;
            float hi = t;
            [unroll] for (int j = 0; j < 12; ++j) {
                float mid = (lo + hi) * 0.5;
                if (solidD(ro + rd * mid) < 0.0) hi = mid; else lo = mid;
            }
            hitT = hi;
            matId = MAT_TERRAIN;
            break;
        }

        tPrev = t;
        t += max(min(dS * 0.45, dC), 0.0025);
        if (t > tMax) break;
    }

    if (hitT < 0.0) {
        GBuf[tid.xy] = float4(0.0, 0.0, 0.0, -1.0);
        return;
    }

    float3 p = ro + rd * hitT;
    float3 n;
    if (matId == MAT_CAGE) {
        float e = 0.0025;
        n = normalize(float3(
            cageD(p + float3(e, 0, 0)) - cageD(p - float3(e, 0, 0)),
            cageD(p + float3(0, e, 0)) - cageD(p - float3(0, e, 0)),
            cageD(p + float3(0, 0, e)) - cageD(p - float3(0, 0, e))) + float3(0, 1e-6, 0));
    } else {
        float e = 0.0035;
        n = normalize(float3(
            solidD(p + float3(e, 0, 0)) - solidD(p - float3(e, 0, 0)),
            solidD(p + float3(0, e, 0)) - solidD(p - float3(0, e, 0)),
            solidD(p + float3(0, 0, e)) - solidD(p - float3(0, 0, e))) + float3(0, 1e-6, 0));
    }

    GBuf[tid.xy] = float4(n, hitT);
}
