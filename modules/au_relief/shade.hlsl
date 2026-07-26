// AUTOPSIA — shade the relief. Same injected internal camera as the march pass;
// the ray is rebuilt identically so world reconstruction stays aligned.
// _Tex0 = gbuffer   _Tex1 = Field (height)   _Tex2 = Plate (inscription)
#include "scene.hlsli"

RWTexture2D<float4> Color : register(u0);

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

    float4 g = _Tex0.Load(int3(tid.xy, 0));
    float t = g.a;

    float3 col = float3(0.004, 0.0045, 0.005);

    if (t > 0.0) {
        float3 p = ro + rd * t;
        float3 n = normalize(g.rgb);

        float dCage = auSdBoxFrame(p - float3(0.0, height_scale * 0.62, 0.0),
                                   float3(AU_DOMAIN.x * 0.5, height_scale * 0.62, AU_DOMAIN.y * 0.5),
                                   max(cage_inset, 0.0005));
        bool isCage = dCage < 0.004;

        if (isCage) {
            // survey cage: pure thin structure, no shading model
            col = float3(0.52, 0.525, 0.505) * cage_gain;
        } else {
            float2 uv = auWorldToUV(p.xz);
            float dens = _Tex1.SampleLevel(LinearSampler, uv, 0).r;
            float3 plate = _Tex2.SampleLevel(LinearSampler, uv, 0).rgb;

            // raking key light, deliberately low and hard
            float3 L = normalize(float3(-0.62, 0.235, -0.75));
            float diff = saturate(dot(n, L));
            float rim = pow(saturate(1.0 - dot(n, -rd)), 2.6);

            // ---- soft raking shadow -------------------------------------------
            // Long low shadows are what make a relief legible as relief; without
            // them the terraces read as flat pattern.
            float shadow = 1.0;
            {
                float st = 0.012;
                float kmin = 1.0;
                [loop] for (int s = 0; s < 24; ++s) {
                    float3 sp = p + L * st;
                    if (sp.y > height_scale * 1.15) break;
                    float ds = auSolid(_Tex1, LinearSampler, sp, height_scale, slab_depth);
                    if (ds < 0.0008) { kmin = 0.0; break; }
                    kmin = min(kmin, shadow_hardness * ds / st);
                    st += clamp(ds * 0.55, 0.006, 0.06);
                    if (st > 1.6) break;
                }
                shadow = saturate(kmin);
            }
            diff *= lerp(1.0, shadow, shadow_gain);

            // cheap ambient occlusion from the height field around p
            float ao = 0.0;
            [unroll] for (int k = 0; k < 6; ++k) {
                float a = (float)k * 1.0471975512;
                float2 o = float2(cos(a), sin(a)) * 0.055;
                float hs = auTerrainHeight(_Tex1, LinearSampler, p.xz + o, height_scale);
                ao += saturate((p.y - hs) * 6.0);
            }
            ao = saturate(ao / 6.0) * 0.88 + 0.12;

            // the specimen's own inscription, wrapped onto its relief
            float ink = dot(plate, float3(0.2126, 0.7152, 0.0722));

            float3 base = float3(0.019, 0.020, 0.019);
            col  = base * (0.20 + 0.80 * diff) * ao;
            col += float3(0.17, 0.174, 0.168) * ink * (0.16 + 0.84 * diff) * plate_gain;
            col += float3(0.11, 0.113, 0.106) * rim * 0.55;

            // 3D height contours: iso-lines cut through the actual relief.
            // Compute shaders have no screen derivatives, so the line width comes
            // from the real ray footprint at this depth and grazing angle — which
            // keeps contours a constant pixel weight instead of aliasing at range.
            float2 ndcDown = float2(ndc.x, 1.0 - (screenUV.y + 1.0 / _Resolution.y) * 2.0);
            float4 farD = mul(_InvViewProjMatrix, float4(ndcDown, 1.0, 1.0));
            farD /= farD.w;
            float3 rdDown = normalize(farD.xyz - nearW.xyz);
            float footprint = t * length(rdDown - rd) / max(abs(dot(n, -rd)), 0.12);

            float hb = p.y * max(height_bands, 1.0);
            float dyPerPixel = footprint * sqrt(saturate(1.0 - n.y * n.y));
            float hgrad = max(dyPerPixel * max(height_bands, 1.0), 1e-5);
            float hl = 1.0 - smoothstep(0.0, 1.35, abs(hb - round(hb)) / hgrad);
            col += float3(0.62, 0.625, 0.60) * hl * height_line_gain * step(0.02, dens);

            // ---- measured surface grid ---------------------------------------
            // World-space rules laid over the relief. They give the surface the
            // crisp linework the shading alone lacks, and they communicate scale:
            // every cell is a fixed real distance across the plate.
            float2 gcell = p.xz * max(surface_grid, 0.01);
            float2 gd = abs(frac(gcell) - 0.5);
            float dLine = min(gd.x, gd.y) / max(surface_grid, 0.01);
            float gpix = dLine / max(footprint, 1e-6);
            float gline = (1.0 - smoothstep(0.35, 1.45, gpix)) * saturate(n.y * 1.6);
            col += float3(0.20, 0.205, 0.196) * gline * grid_gain;

            // ---- cut faces: the block's sides read as a geological section ----
            // Below the plate the block is sliced material, not landscape, so it
            // gets horizontal strata instead of terrain contours.
            float cut = smoothstep(0.55, 0.15, abs(n.y)) * step(p.y, 0.0006);
            if (cut > 0.001) {
                float strata = frac(p.y * strata_bands);
                float sline = 1.0 - smoothstep(0.0, 0.10, min(strata, 1.0 - strata));
                float coarse = 1.0 - smoothstep(0.0, 0.022, abs(frac(p.y * strata_bands * 0.2) - 0.5));
                // the block is context, not the subject: keep it well under the relief
                col = lerp(col, float3(0.0055, 0.006, 0.0055), cut);
                col += float3(0.028, 0.029, 0.027) * sline * cut * 0.5;
                col += float3(0.085, 0.087, 0.082) * coarse * cut * 0.5;
            }

            // steep faces read as cut/section surfaces
            float slope = 1.0 - saturate(n.y);
            col += float3(0.10, 0.102, 0.098) * pow(slope, 2.0) * 0.8;
        }

        float fog = exp(-max(t - 1.0, 0.0) * fog_density);
        col *= fog;
    }

    col *= exposure;
    col = col / (1.0 + col);
    col = pow(saturate(col), 1.0 / 2.2);
    Color[tid.xy] = float4(col, 1.0);
}
